import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const source = fs.readFileSync(new URL('./FrameGovernor.js', import.meta.url), 'utf8');

function harness() {
  let nextNative = 0;
  const nativeFrames = new Map();
  const window = {
    requestAnimationFrame(callback) {
      const id = ++nextNative;
      nativeFrames.set(id, callback);
      return id;
    },
    cancelAnimationFrame(id) { nativeFrames.delete(id); },
  };

  vm.runInNewContext(source, { window, setTimeout });
  return {
    window,
    queued: () => nativeFrames.size,
    step(time) {
      const active = [...nativeFrames.values()];
      nativeFrames.clear();
      for (const callback of active) callback(time);
    }
  };
}

test('30 FPS governor skips intermediate native frames', () => {
  const h = harness();
  const called = [];
  function loop(ts) {
    called.push(ts);
    if (called.length < 3) h.window.requestAnimationFrame(loop);
  }
  h.window.requestAnimationFrame(loop);
  h.step(0);
  h.step(16);
  h.step(34);
  h.step(50);
  h.step(68);
  assert.deepEqual(called, [0, 34, 68]);
});

test('pausing cancels pending native frames, then resumes', () => {
  const h = harness();
  let count = 0;
  h.window.requestAnimationFrame(() => count++);
  h.window.__oceanGovernor.setPaused(true);
  assert.equal(h.queued(), 0);
  h.step(1000);
  assert.equal(count, 0);
  h.window.__oceanGovernor.setPaused(false);
  assert.equal(h.queued(), 1);
  h.step(2000);
  assert.equal(count, 1);
});

test('cancelAnimationFrame removes callbacks', () => {
  const h = harness();
  let count = 0;
  const id = h.window.requestAnimationFrame(() => count++);
  h.window.cancelAnimationFrame(id);
  assert.equal(h.queued(), 0);
  h.step(100);
  assert.equal(count, 0);
});

test('setting FPS changes the budget without recreating the simulation', () => {
  const h = harness();
  h.window.__oceanGovernor.setFPS(15);
  assert.equal(h.window.__oceanGovernor.getState().fps, 15);
  h.window.__oceanGovernor.setFPS(NaN);
  assert.equal(h.window.__oceanGovernor.getState().fps, 15);
  h.window.__oceanGovernor.setFPS(10000);
  assert.equal(h.window.__oceanGovernor.getState().fps, 120);
});

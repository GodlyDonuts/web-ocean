// Injected in the page world before ocean.html executes.
// Keeps the original renderer unmodified. No timers or network requests.
(() => {
  'use strict';

  const nativeRequest = window.requestAnimationFrame.bind(window);
  const nativeCancel = window.cancelAnimationFrame.bind(window);
  const pending = new Map();
  let nextId = 1;
  let scheduled = null;
  let fps = 30;
  let paused = false;
  let lastFrame = -Infinity;

  function schedule() {
    if (paused || scheduled !== null || pending.size === 0) return;
    scheduled = nativeRequest(tick);
  }

  function tick(now) {
    scheduled = null;
    if (paused) return;
    if (now - lastFrame + 0.25 < 1000 / fps) {
      schedule();
      return;
    }

    lastFrame = now;
    const callbacks = Array.from(pending.values());
    pending.clear();
    for (const callback of callbacks) {
      try {
        callback(now);
      } catch (error) {
        // Match requestAnimationFrame: one callback failure must not block the rest.
        setTimeout(() => { throw error; }, 0);
      }
    }
    schedule();
  }

  window.requestAnimationFrame = callback => {
    if (typeof callback !== 'function') throw new TypeError('Expected frame callback');
    const id = nextId++;
    pending.set(id, callback);
    schedule();
    return id;
  };

  window.cancelAnimationFrame = id => {
    pending.delete(id);
    if (!pending.size && scheduled !== null) {
      nativeCancel(scheduled);
      scheduled = null;
    }
  };

  window.__oceanGovernor = Object.freeze({
    setFPS(value) {
      const n = Number(value);
      if (!Number.isFinite(n)) return;
      fps = Math.max(1, Math.min(120, n));
      lastFrame = -Infinity;
      schedule();
    },
    setPaused(value) {
      paused = Boolean(value);
      if (paused && scheduled !== null) {
        nativeCancel(scheduled);
        scheduled = null;
      }
      if (!paused) {
        lastFrame = -Infinity;
        schedule();
      }
    },
    getState() {
      return { fps, paused, pending: pending.size };
    }
  });
})();
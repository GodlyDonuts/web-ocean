// Experimental candidate: fuse SIM_EVOLVE with FFT_ROWS.
// Source: GodlyDonuts/web-ocean, 8739f0793f84b96cb87a21558a117e1714184ad7
// js/wgsl/sim.js: SIM_STRUCT, SIM_EVOLVE, FFT_CORE, FFT_ROWS.
//
// UNCOMPILED AND UNBENCHMARKED ON A GPU.
// This first candidate deliberately preserves N=256, LOGN=8, FP32 arithmetic,
// frequency quantization, field packing, and the existing butterfly schedule.
// It does not add sparse-band pruning, new twiddles, or new FFT layouts.

const N: u32 = 256u;
const LOGN: u32 = 8u;
const PI: f32 = 3.14159265358979;
const GRAV: f32 = 9.81;
const SURF: f32 = 7.4e-5;

struct Sim {
  L:          array<vec4f, 2>,
  kMin:       array<vec4f, 2>,
  kMax:       array<vec4f, 2>,
  foamDecay:  array<vec4f, 2>,
  foamThresh: array<vec4f, 2>,
  wind:       vec4f,
  swell:      vec4f,
  misc:       vec4f,
  timeP:      vec4f,
};

// Binding resources: existing simUBO, h0Buf, tmpA, tmpB, in that order.
@group(0) @binding(0) var<uniform> S: Sim;
@group(0) @binding(1) var<storage, read> h0: array<vec4f>;
@group(0) @binding(2) var<storage, read_write> outA: array<vec4f>;
@group(0) @binding(3) var<storage, read_write> outB: array<vec4f>;

var<workgroup> wa: array<vec4f, 256>;
var<workgroup> wb: array<vec4f, 256>;

fn waveVec(x: u32, y: u32, L: f32) -> vec2f {
  let nx = select(i32(x), i32(x) - i32(N), x >= N / 2u);
  let ny = select(i32(y), i32(y) - i32(N), y >= N / 2u);
  return vec2f(f32(nx), f32(ny)) * (2.0 * PI / L);
}

fn omegaOf(k: f32) -> f32 {
  return sqrt(GRAV * k + SURF * k * k * k);
}

fn cmul(a: vec2f, b: vec2f) -> vec2f {
  return vec2f(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x);
}

fn mulI(a: vec2f) -> vec2f {
  return vec2f(-a.y, a.x);
}

struct PackedSpectra {
  a: vec4f,
  b: vec4f,
};

// This is the body of SIM_EVOLVE, returning its two stores as values.
// Its DC return is local to this helper. No entry-point invocation returns
// before a workgroup barrier.
fn evolveAt(x: u32, y: u32, c: u32) -> PackedSpectra {
  let idx = (c * N + y) * N + x;
  let k = waveVec(x, y, S.L[c >> 2u][c & 3u]);
  let kl = length(k);
  if (kl < 1e-5) {
    return PackedSpectra(vec4f(0.0), vec4f(0.0));
  }
  let w0 = 2.0 * PI / S.misc.z;
  let w = floor(omegaOf(kl) / w0) * w0;
  let ph = w * S.timeP.x;
  let e = vec2f(cos(ph), sin(ph));
  let H0 = h0[idx];
  let h = cmul(H0.xy, vec2f(e.x, -e.y)) + cmul(H0.zw, e);
  let ih = mulI(h);
  let lam = S.misc.x;
  let ik = 1.0 / kl;
  let Dx = ih * (lam * k.x * ik);
  let Dz = ih * (lam * k.y * ik);
  let jxz = h * (-lam * k.x * k.y * ik);
  let sx = ih * k.x;
  let sz = ih * k.y;
  let jxx = h * (-lam * k.x * k.x * ik);
  let jzz = h * (-lam * k.y * k.y * ik);
  return PackedSpectra(
    vec4f(Dx + mulI(Dz), h + mulI(jxz)),
    vec4f(sx + mulI(sz), jxx + mulI(jzz))
  );
}

fn bitrev(i: u32) -> u32 {
  return reverseBits(i) >> (32u - LOGN);
}

// The original FFT_CORE butterfly schedule and arithmetic.
fn butterflies(t: u32) {
  for (var s = 0u; s < LOGN; s++) {
    let half = 1u << s;
    let pos = t & (half - 1u);
    let i0 = ((t >> s) << (s + 1u)) + pos;
    let i1 = i0 + half;
    let ang = PI * f32(pos) / f32(half);
    let w = vec2f(cos(ang), sin(ang));
    let a0 = wa[i0]; let a1 = wa[i1];
    let b0 = wb[i0]; let b1 = wb[i1];
    let ta = vec4f(cmul(a1.xy, w), cmul(a1.zw, w));
    let tb = vec4f(cmul(b1.xy, w), cmul(b1.zw, w));
    wa[i0] = a0 + ta; wa[i1] = a0 - ta;
    wb[i0] = b0 + tb; wb[i1] = b0 - tb;
    workgroupBarrier();
  }
}

// Dispatch(N, 1, CASCADES), identical to the original row FFT.
@compute @workgroup_size(128)
fn main(@builtin(workgroup_id) wg: vec3u,
        @builtin(local_invocation_index) t: u32) {
  let base = (wg.z * N + wg.x) * N;
  let e0 = t;
  let e1 = t + N / 2u;

  let p0 = evolveAt(e0, wg.x, wg.z);
  let p1 = evolveAt(e1, wg.x, wg.z);
  wa[bitrev(e0)] = p0.a;
  wa[bitrev(e1)] = p1.a;
  wb[bitrev(e0)] = p0.b;
  wb[bitrev(e1)] = p1.b;
  workgroupBarrier();

  butterflies(t);

  outA[base + e0] = wa[e0];
  outA[base + e1] = wa[e1];
  outB[base + e0] = wb[e0];
  outB[base + e1] = wb[e1];
}

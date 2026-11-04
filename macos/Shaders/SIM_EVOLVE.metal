// Native Metal shaders migrated from the original ocean equations using Naga.
// Edit this file for native rendering; no WGSL or JavaScript runs in the app.
// language: metal2.3
#include <metal_stdlib>
#include <simd/simd.h>

using metal::uint;

struct _mslBufferSizes {
    uint size1;
    uint size2;
    uint size3;
};

struct type_3 {
    metal::float4 inner[2];
};
struct Sim {
    type_3 L;
    type_3 kMin;
    type_3 kMax;
    type_3 foamDecay;
    type_3 foamThresh;
    metal::float4 wind;
    metal::float4 swell;
    metal::float4 misc;
    metal::float4 timeP;
};
typedef metal::float4 type_5[1];
constant uint N = 256u;
constant uint LOGN = 8u;
constant float PI = 3.1415927;
constant float GRAV = 9.81;
constant float SURF = 0.000074;

metal::float2 waveVec(
    uint x,
    uint y,
    float L
) {
    int nx = (x >= 128u) ? as_type<int>(as_type<uint>(static_cast<int>(x)) - as_type<uint>(256)) : static_cast<int>(x);
    int ny = (y >= 128u) ? as_type<int>(as_type<uint>(static_cast<int>(y)) - as_type<uint>(256)) : static_cast<int>(y);
    return metal::float2(static_cast<float>(nx), static_cast<float>(ny)) * (6.2831855 / L);
}

float omegaOf(
    float k
) {
    return metal::sqrt((GRAV * k) + (((SURF * k) * k) * k));
}

float dOmegaOf(
    float k_1
) {
    float _e6 = omegaOf(k_1);
    return (GRAV + ((0.000222 * k_1) * k_1)) / (2.0 * _e6);
}

metal::float2 cmul(
    metal::float2 a,
    metal::float2 b
) {
    return metal::float2((a.x * b.x) - (a.y * b.y), (a.x * b.y) + (a.y * b.x));
}

metal::float2 mulI(
    metal::float2 a_1
) {
    return metal::float2(-(a_1.y), a_1.x);
}

struct main_Input {
};
[[max_total_threads_per_threadgroup(256)]] kernel void main_(
  metal::uint3 id [[thread_position_in_grid]]
, constant Sim& S [[buffer(0)]]
, device type_5 const& h0_ [[buffer(1)]]
, device type_5& specA [[buffer(2)]]
, device type_5& specB [[buffer(3)]]
, constant _mslBufferSizes& _buffer_sizes [[buffer(30)]]
) {

    uint c = id.z;
    uint idx = (((c * N) + id.y) * N) + id.x;
    float _e20 = S.L.inner[c >> 2u][c & 3u];
    metal::float2 _e21 = waveVec(id.x, id.y, _e20);
    float kl = metal::length(_e21);
    if (kl < 0.00001) {
        specA[idx] = metal::float4(0.0);
        specB[idx] = metal::float4(0.0);
        return;
    }
    float _e37 = S.misc.z;
    float w0_ = 6.2831855 / _e37;
    float _e39 = omegaOf(kl);
    float w = metal::floor(_e39 / w0_) * w0_;
    float _e46 = S.timeP.x;
    float ph = w * _e46;
    metal::float2 e = metal::float2(metal::cos(ph), metal::sin(ph));
    metal::float4 H0_ = h0_[idx];
    metal::float2 _e59 = cmul(H0_.xy, metal::float2(e.x, -(e.y)));
    metal::float2 _e61 = cmul(H0_.zw, e);
    metal::float2 h = _e59 + _e61;
    metal::float2 _e63 = mulI(h);
    float lam = S.misc.x;
    float ik = 1.0 / kl;
    metal::float2 Dx = _e63 * ((lam * _e21.x) * ik);
    metal::float2 Dz = _e63 * ((lam * _e21.y) * ik);
    metal::float2 jxz = h * (((-(lam) * _e21.x) * _e21.y) * ik);
    metal::float2 sx = _e63 * _e21.x;
    metal::float2 sz = _e63 * _e21.y;
    metal::float2 jxx = h * (((-(lam) * _e21.x) * _e21.x) * ik);
    metal::float2 jzz = h * (((-(lam) * _e21.y) * _e21.y) * ik);
    metal::float2 _e105 = mulI(Dz);
    metal::float2 _e107 = mulI(jxz);
    specA[idx] = metal::float4(Dx + _e105, h + _e107);
    metal::float2 _e112 = mulI(sz);
    metal::float2 _e114 = mulI(jzz);
    specB[idx] = metal::float4(sx + _e112, jxx + _e114);
    return;
}

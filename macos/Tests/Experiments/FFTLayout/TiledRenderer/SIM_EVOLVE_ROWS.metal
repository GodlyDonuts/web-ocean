// Fused native evolution and row FFT. Equations and butterfly order retained.
// Native Metal shaders migrated from the original ocean equations using Naga.
// Edit this file for native rendering; no WGSL or JavaScript runs in the app.
// language: metal2.3
#include <metal_stdlib>
#include <simd/simd.h>

using metal::uint;

// 0: row-major, 1: column-major, 2..5: square 4/8/16/32 tiles.
uint fftAddress(uint x, uint y, uint layer) {
#if FFT_LAYOUT == 1
    return ((layer*256u+x)*256u)+y;
#elif FFT_LAYOUT >= 2
    const uint shift = FFT_LAYOUT;
    const uint mask = (1u<<shift)-1u;
    const uint tile = (y>>shift)*(256u>>shift)+(x>>shift);
    return layer*65536u+(tile<<(2u*shift))+((y&mask)<<shift)+(x&mask);
#else
    return ((layer*256u+y)*256u)+x;
#endif
}


struct SimLengths {
    metal::float4 inner[2];
};
struct Sim {
    SimLengths L;
    SimLengths kMin;
    SimLengths kMax;
    SimLengths foamDecay;
    SimLengths foamThresh;
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

struct EvolvedSpectrum { metal::float4 a, b; };
EvolvedSpectrum evolveSample(metal::uint3 id, constant Sim& S, device type_5 const& h0_) {
    EvolvedSpectrum result;
    uint c = id.z;
    uint idx = (((c * N) + id.y) * N) + id.x;
    float _e20 = S.L.inner[c >> 2u][c & 3u];
    metal::float2 _e21 = waveVec(id.x, id.y, _e20);
    float kl = metal::length(_e21);
    if (kl < 0.00001) {
        result.a = metal::float4(0.0);
        result.b = metal::float4(0.0);
        return result;
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
    result.a = metal::float4(Dx + _e105, h + _e107);
    metal::float2 _e112 = mulI(sz);
    metal::float2 _e114 = mulI(jzz);
    result.b = metal::float4(sx + _e112, jxx + _e114);
    return result;
}
struct type_3 { metal::float4 inner[256]; };
uint bitrev(
    uint i
) {
    return metal::reverse_bits(i) >> 24u;
}

void butterflies(
    uint t_1,
    threadgroup type_3& wa,
    threadgroup type_3& wb
) {
    uint s = 0u;
    bool loop_init = true;
    while(true) {
        if (!loop_init) {
            uint _e63 = s;
            s = _e63 + 1u;
        }
        loop_init = false;
        uint _e3 = s;
        if (_e3 < LOGN) {
        } else {
            break;
        }
        {
            uint _e7 = s;
            uint half_ = 1u << _e7;
            uint pos = t_1 & (half_ - 1u);
            uint _e12 = s;
            uint _e14 = s;
            uint i0_ = ((t_1 >> _e12) << (_e14 + 1u)) + pos;
            uint i1_ = i0_ + half_;
            float ang = (PI * static_cast<float>(pos)) / static_cast<float>(half_);
            metal::float2 w = metal::float2(metal::cos(ang), metal::sin(ang));
            metal::float4 a0_ = wa.inner[i0_];
            metal::float4 a1_ = wa.inner[i1_];
            metal::float4 b0_ = wb.inner[i0_];
            metal::float4 b1_ = wb.inner[i1_];
            metal::float2 _e41 = cmul(a1_.xy, w);
            metal::float2 _e43 = cmul(a1_.zw, w);
            metal::float4 ta = metal::float4(_e41, _e43);
            metal::float2 _e46 = cmul(b1_.xy, w);
            metal::float2 _e48 = cmul(b1_.zw, w);
            metal::float4 tb = metal::float4(_e46, _e48);
            wa.inner[i0_] = a0_ + ta;
            wa.inner[i1_] = a0_ - ta;
            wb.inner[i0_] = b0_ + tb;
            wb.inner[i1_] = b0_ - tb;
            metal::threadgroup_barrier(metal::mem_flags::mem_threadgroup);
        }
    }
    return;
}

[[max_total_threads_per_threadgroup(128)]] kernel void main_(
  metal::uint3 wg [[threadgroup_position_in_grid]]
, uint t [[thread_index_in_threadgroup]]
, constant Sim& S [[buffer(0)]]
, device type_5 const& h0_ [[buffer(1)]]
, device type_5& outA [[buffer(2)]]
, device type_5& outB [[buffer(3)]]
) {
    threadgroup type_3 wa;
    threadgroup type_3 wb;
    uint base = ((wg.z * N) + wg.x) * N;
    uint e1_ = t + 128u;
    EvolvedSpectrum first = evolveSample(metal::uint3(t,wg.x,wg.z),S,h0_);
    EvolvedSpectrum second = evolveSample(metal::uint3(e1_,wg.x,wg.z),S,h0_);
    uint _e12 = bitrev(t);
    metal::float4 _e17 = first.a;
    wa.inner[_e12] = _e17;
    uint _e19 = bitrev(e1_);
    metal::float4 _e24 = second.a;
    wa.inner[_e19] = _e24;
    uint _e26 = bitrev(t);
    metal::float4 _e31 = first.b;
    wb.inner[_e26] = _e31;
    uint _e33 = bitrev(e1_);
    metal::float4 _e38 = second.b;
    wb.inner[_e33] = _e38;
    metal::threadgroup_barrier(metal::mem_flags::mem_threadgroup);
    butterflies(t, wa, wb);
    const uint destination0 = fftAddress(t,wg.x,wg.z);
    const uint destination1 = fftAddress(e1_,wg.x,wg.z);
    metal::float4 _e44 = wa.inner[t];
    outA[destination0] = _e44;
    metal::float4 _e50 = wa.inner[e1_];
    outA[destination1] = _e50;
    metal::float4 _e56 = wb.inner[t];
    outB[destination0] = _e56;
    metal::float4 _e62 = wb.inner[e1_];
    outB[destination1] = _e62;
    return;
}

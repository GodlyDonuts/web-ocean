// Native Metal shaders migrated from the original ocean equations using Naga.
// Edit this file for native rendering; no WGSL or JavaScript runs in the app.
// language: metal2.3
#include <metal_stdlib>
#include <simd/simd.h>

using metal::uint;

struct _mslBufferSizes {
    uint size2;
    uint size3;
    uint size4;
    uint size5;
};

struct type_3 {
    metal::float4 inner[256];
};
typedef metal::float4 type_5[1];
constant uint N = 256u;
constant uint LOGN = 8u;
constant float PI = 3.1415927;

metal::float2 cmul(
    metal::float2 a,
    metal::float2 b
) {
    return metal::float2((a.x * b.x) - (a.y * b.y), (a.x * b.y) + (a.y * b.x));
}

uint bitrev(
    uint i
) {
    return metal::reverse_bits(i) >> 24u;
}

void butterflies(
    uint t_1,
    threadgroup type_3& wa,
    threadgroup type_3& wb
#if FFT_TWIDDLE_TABLE
, constant metal::float2* twiddles
#endif
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
#if FFT_TWIDDLE_TABLE
            metal::float2 w = twiddles[s*128u+t_1];
#else
            float ang = (PI * static_cast<float>(pos)) / static_cast<float>(half_);
            metal::float2 w = metal::float2(metal::cos(ang), metal::sin(ang));
#endif
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

struct main_Input {
};
[[max_total_threads_per_threadgroup(128)]] kernel void main_(
  metal::uint3 wg [[threadgroup_position_in_grid]]
, uint t [[thread_index_in_threadgroup]]
, device type_5 const& inA [[buffer(0)]]
, device type_5 const& inB [[buffer(1)]]
, device type_5& outA [[buffer(2)]]
, device type_5& outB [[buffer(3)]]
#if FFT_TWIDDLE_TABLE
, constant metal::float2* twiddles [[buffer(4)]]
#endif
, constant _mslBufferSizes& _buffer_sizes [[buffer(30)]]
) {
    threadgroup type_3 wa;
    threadgroup type_3 wb;
    uint base = ((wg.z * N) + wg.x) * N;
    uint e1_ = t + 128u;
    uint _e12 = bitrev(t);
    metal::float4 _e17 = inA[base + t];
    wa.inner[_e12] = _e17;
    uint _e19 = bitrev(e1_);
    metal::float4 _e24 = inA[base + e1_];
    wa.inner[_e19] = _e24;
    uint _e26 = bitrev(t);
    metal::float4 _e31 = inB[base + t];
    wb.inner[_e26] = _e31;
    uint _e33 = bitrev(e1_);
    metal::float4 _e38 = inB[base + e1_];
    wb.inner[_e33] = _e38;
    metal::threadgroup_barrier(metal::mem_flags::mem_threadgroup);
    butterflies(t, wa, wb
#if FFT_TWIDDLE_TABLE
, twiddles
#endif
);
    metal::float4 _e44 = wa.inner[t];
    outA[base + t] = _e44;
    metal::float4 _e50 = wa.inner[e1_];
    outA[base + e1_] = _e50;
    metal::float4 _e56 = wb.inner[t];
    outB[base + t] = _e56;
    metal::float4 _e62 = wb.inner[e1_];
    outB[base + e1_] = _e62;
    return;
}

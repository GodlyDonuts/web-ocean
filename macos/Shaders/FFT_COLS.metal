// Native Metal shaders migrated from the original ocean equations using Naga.
// Edit this file for native rendering; no WGSL or JavaScript runs in the app.
// language: metal2.3
#include <metal_stdlib>
#include <simd/simd.h>

using metal::uint;

struct _mslBufferSizes {
    uint size2;
    uint size3;
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

void emit(
    uint x,
    uint y,
    uint c,
    metal::float4 a_1,
    metal::float4 b_1,
    metal::texture2d_array<float, metal::access::write> dispOut,
    metal::texture2d_array<float, metal::access::write> derivOut,
    metal::texture2d_array<float, metal::access::write> momOut
) {
    metal::uint2 p = metal::uint2(x, y);
    dispOut.write(metal::float4(a_1.x, a_1.z, a_1.y, a_1.w), metal::uint2(p), c);
    derivOut.write(b_1, metal::uint2(p), c);
#if OCEAN_PACKED_JACOBIAN
    momOut.write(metal::float4(b_1.x * b_1.x, b_1.y * b_1.y, b_1.x * b_1.y, a_1.w), metal::uint2(p), c);
#else
    momOut.write(metal::float4(b_1.x * b_1.x, b_1.y * b_1.y, b_1.x * b_1.y, 0.0), metal::uint2(p), c);
#endif
    return;
}

struct main_Input {
};
[[max_total_threads_per_threadgroup(128)]] kernel void main_(
  metal::uint3 wg [[threadgroup_position_in_grid]]
, uint t [[thread_index_in_threadgroup]]
, device type_5 const& inA [[buffer(0)]]
, device type_5 const& inB [[buffer(1)]]
, metal::texture2d_array<float, metal::access::write> dispOut [[texture(2)]]
, metal::texture2d_array<float, metal::access::write> derivOut [[texture(3)]]
, metal::texture2d_array<float, metal::access::write> momOut [[texture(4)]]
, constant _mslBufferSizes& _buffer_sizes [[buffer(30)]]
) {
    threadgroup type_3 wa;
    threadgroup type_3 wb;
    uint x_1 = wg.x;
    uint c_1 = wg.z;
    uint e1_ = t + 128u;
    uint i0_1 = (((c_1 * N) + t) * N) + x_1;
    uint i1_1 = (((c_1 * N) + e1_) * N) + x_1;
    uint _e19 = bitrev(t);
    metal::float4 _e23 = inA[i0_1];
    wa.inner[_e19] = _e23;
    uint _e25 = bitrev(e1_);
    metal::float4 _e29 = inA[i1_1];
    wa.inner[_e25] = _e29;
    uint _e31 = bitrev(t);
    metal::float4 _e35 = inB[i0_1];
    wb.inner[_e31] = _e35;
    uint _e37 = bitrev(e1_);
    metal::float4 _e41 = inB[i1_1];
    wb.inner[_e37] = _e41;
    metal::threadgroup_barrier(metal::mem_flags::mem_threadgroup);
    butterflies(t, wa, wb);
    metal::float4 _e44 = wa.inner[t];
    metal::float4 _e47 = wb.inner[t];
    emit(x_1, t, c_1, _e44, _e47, dispOut, derivOut, momOut);
    metal::float4 _e50 = wa.inner[e1_];
    metal::float4 _e53 = wb.inner[e1_];
    emit(x_1, e1_, c_1, _e50, _e53, dispOut, derivOut, momOut);
    return;
}

// Native Metal shaders migrated from the original ocean equations using Naga.
// Edit this file for native rendering; no WGSL or JavaScript runs in the app.
// language: metal2.3
#include <metal_stdlib>
#include <simd/simd.h>

using metal::uint;

constant float SIZE = 512.0;

uint pcgHash(
    uint v
) {
    uint s_1 = (v * 747796405u) + 2891336453u;
    uint w = ((s_1 >> ((s_1 >> 28u) + 4u)) ^ s_1) * 277803737u;
    return (w >> 22u) ^ w;
}

metal::float2 hashGrad(
    metal::int2 i
) {
    uint _e9 = pcgHash(static_cast<uint>(i.y) + 1013904223u);
    uint _e11 = pcgHash((static_cast<uint>(i.x) * 1664525u) + _e9);
    float a_1 = static_cast<float>(_e11) * 0.0000000014629181;
    return metal::float2(metal::cos(a_1), metal::sin(a_1));
}

metal::int2 naga_f2i32(metal::float2 value) {
    return static_cast<metal::int2>(metal::clamp(value, -2147483600.0, 2147483500.0));
}

float gnoise(
    metal::float2 p
) {
    metal::int2 i_3 = naga_f2i32(metal::floor(p));
    metal::float2 f = p - metal::floor(p);
    metal::float2 u = ((f * f) * f) * ((f * ((f * 6.0) - metal::float2(15.0))) + metal::float2(10.0));
    metal::float2 _e17 = hashGrad(i_3);
    float a_2 = metal::dot(_e17, f);
    metal::float2 _e23 = hashGrad(as_type<metal::int2>(as_type<metal::uint2>(i_3) + as_type<metal::uint2>(metal::int2(1, 0))));
    float b = metal::dot(_e23, f - metal::float2(1.0, 0.0));
    metal::float2 _e33 = hashGrad(as_type<metal::int2>(as_type<metal::uint2>(i_3) + as_type<metal::uint2>(metal::int2(0, 1))));
    float c = metal::dot(_e33, f - metal::float2(0.0, 1.0));
    metal::float2 _e43 = hashGrad(as_type<metal::int2>(as_type<metal::uint2>(i_3) + as_type<metal::uint2>(metal::int2(1, 1))));
    float d = metal::dot(_e43, f - metal::float2(1.0, 1.0));
    return metal::mix(metal::mix(a_2, b, u.x), metal::mix(c, d, u.x), u.y);
}

float pnoise(
    metal::float2 p_1,
    int period
) {
    metal::int2 i_4 = naga_f2i32(metal::floor(p_1));
    metal::float2 f_1 = p_1 - metal::floor(p_1);
    metal::float2 u_1 = ((f_1 * f_1) * f_1) * ((f_1 * ((f_1 * 6.0) - metal::float2(15.0))) + metal::float2(10.0));
    metal::int2 i00_ = as_type<metal::int2>(as_type<metal::uint2>(i_4 % metal::int2(period)) + as_type<metal::uint2>(metal::int2(period))) % metal::int2(period);
    metal::int2 i10_ = as_type<metal::int2>(as_type<metal::uint2>(as_type<metal::int2>(as_type<metal::uint2>(i_4) + as_type<metal::uint2>(metal::int2(1, 0))) % metal::int2(period)) + as_type<metal::uint2>(metal::int2(period))) % metal::int2(period);
    metal::int2 i01_ = as_type<metal::int2>(as_type<metal::uint2>(as_type<metal::int2>(as_type<metal::uint2>(i_4) + as_type<metal::uint2>(metal::int2(0, 1))) % metal::int2(period)) + as_type<metal::uint2>(metal::int2(period))) % metal::int2(period);
    metal::int2 i11_ = as_type<metal::int2>(as_type<metal::uint2>(as_type<metal::int2>(as_type<metal::uint2>(i_4) + as_type<metal::uint2>(metal::int2(1, 1))) % metal::int2(period)) + as_type<metal::uint2>(metal::int2(period))) % metal::int2(period);
    metal::float2 _e54 = hashGrad(i00_);
    float a_3 = metal::dot(_e54, f_1);
    metal::float2 _e56 = hashGrad(i10_);
    float b_1 = metal::dot(_e56, f_1 - metal::float2(1.0, 0.0));
    metal::float2 _e62 = hashGrad(i01_);
    float c_1 = metal::dot(_e62, f_1 - metal::float2(0.0, 1.0));
    metal::float2 _e68 = hashGrad(i11_);
    float d_1 = metal::dot(_e68, f_1 - metal::float2(1.0, 1.0));
    return metal::mix(metal::mix(a_3, b_1, u_1.x), metal::mix(c_1, d_1, u_1.x), u_1.y);
}

float pfbm(
    metal::float2 p_2,
    int period_1,
    int oct
) {
    float s = 0.0;
    float a = 0.5;
    metal::float2 q = {};
    int per = {};
    int o = 0;
    q = p_2;
    per = period_1;
    bool loop_init = true;
    while(true) {
        if (!loop_init) {
            int _e30 = o;
            o = as_type<int>(as_type<uint>(_e30) + as_type<uint>(1));
        }
        loop_init = false;
        int _e11 = o;
        if (_e11 < oct) {
        } else {
            break;
        }
        {
            float _e13 = s;
            float _e14 = a;
            metal::float2 _e15 = q;
            int _e16 = per;
            float _e17 = pnoise(_e15, _e16);
            s = _e13 + (_e14 * _e17);
            metal::float2 _e20 = q;
            q = _e20 * 2.0;
            int _e23 = per;
            per = as_type<int>(as_type<uint>(_e23) * as_type<uint>(2));
            float _e26 = a;
            a = _e26 * 0.5;
        }
    }
    float _e32 = s;
    return _e32;
}

metal::float2 h2_(
    metal::int2 i_1,
    uint salt
) {
    uint _e11 = pcgHash((static_cast<uint>(i_1.y) * 19349663u) + salt);
    uint _e13 = pcgHash((static_cast<uint>(i_1.x) * 73856093u) ^ _e11);
    uint _e16 = pcgHash(_e13 + 2654435769u);
    return metal::float2(static_cast<float>(_e13 >> 8u), static_cast<float>(_e16 >> 8u)) / metal::float2(16777216.0);
}

float bubbles(
    metal::float2 uv,
    int period_2,
    uint salt_1,
    float rmin,
    float rmax
) {
    float v_1 = 9.0;
    int j = -1;
    int i_2 = {};
    float _e12 = pfbm((uv * static_cast<float>(period_2)) * 0.5, period_2 / 2, 3);
    float _e23 = pfbm(((uv * static_cast<float>(period_2)) * 0.5) + metal::float2(17.0), period_2 / 2, 3);
    metal::float2 w_1 = metal::float2(_e12, _e23);
    metal::float2 p_3 = (uv * static_cast<float>(period_2)) + (w_1 * 0.9);
    metal::int2 ip = naga_f2i32(metal::floor(p_3));
    metal::float2 fp = p_3 - metal::floor(p_3);
    bool loop_init_1 = true;
    while(true) {
        if (!loop_init_1) {
            int _e78 = j;
            j = as_type<int>(as_type<uint>(_e78) + as_type<uint>(1));
        }
        loop_init_1 = false;
        int _e38 = j;
        if (_e38 <= 1) {
        } else {
            break;
        }
        {
            i_2 = -1;
            bool loop_init_2 = true;
            while(true) {
                if (!loop_init_2) {
                    int _e75 = i_2;
                    i_2 = as_type<int>(as_type<uint>(_e75) + as_type<uint>(1));
                }
                loop_init_2 = false;
                int _e43 = i_2;
                if (_e43 <= 1) {
                } else {
                    break;
                }
                {
                    int _e46 = i_2;
                    int _e47 = j;
                    metal::int2 o_1 = metal::int2(_e46, _e47);
                    metal::int2 cell = as_type<metal::int2>(as_type<metal::uint2>(as_type<metal::int2>(as_type<metal::uint2>(ip) + as_type<metal::uint2>(o_1)) % metal::int2(period_2)) + as_type<metal::uint2>(metal::int2(period_2))) % metal::int2(period_2);
                    metal::float2 _e56 = h2_(cell, salt_1);
                    metal::float2 r = ((static_cast<metal::float2>(o_1) + (_e56 * 0.9)) + metal::float2(0.05)) - fp;
                    metal::float2 _e67 = h2_(cell, salt_1 + 7u);
                    float rad = metal::mix(rmin, rmax, _e67.x);
                    float _e70 = v_1;
                    v_1 = metal::min(_e70, metal::length(r) / rad);
                }
            }
        }
    }
    float _e80 = v_1;
    return metal::smoothstep(0.8, 1.25, _e80);
}

struct main_Input {
};
[[max_total_threads_per_threadgroup(64)]] kernel void main_(
  metal::uint3 id [[thread_position_in_grid]]
, metal::texture2d<float, metal::access::write> dst [[texture(0)]]
) {

    metal::float2 uv_1 = (static_cast<metal::float2>(id.xy) + metal::float2(0.5)) / metal::float2(512.0);
    float _e13 = pfbm(uv_1 * 5.0, 5, 3);
    float _e22 = pfbm((uv_1 * 5.0) + metal::float2(3.7, 9.1), 5, 3);
    metal::float2 w1_ = metal::float2(_e13, _e22);
    float _e31 = pfbm((uv_1 * 10.0) + (w1_ * 1.4), 10, 5);
    float m1_ = metal::smoothstep(-0.14, 0.06, _e31);
    float _e42 = pfbm((uv_1 * 12.0) + metal::float2(1.3), 12, 2);
    float _e50 = pfbm((uv_1 * 12.0) + metal::float2(7.9), 12, 2);
    metal::float2 w2_ = metal::float2(_e42, _e50);
    float _e59 = pfbm((uv_1 * 27.0) + (w2_ * 0.9), 27, 4);
    float m2_ = metal::smoothstep(-0.16, 0.04, _e59);
    float _e67 = bubbles(uv_1, 29, 37u, 0.06, 0.45);
    float _e72 = bubbles(uv_1, 61, 53u, 0.05, 0.42);
    float _e77 = pfbm(uv_1 * 4.0, 4, 5);
    float dens = (_e77 * 0.5) + 0.5;
    float _e86 = pfbm(uv_1 * 16.0, 16, 3);
    float fineD = (_e86 * 0.5) + 0.5;
    float big = (m1_ * (0.55 + (0.45 * m2_))) * (0.75 + (0.25 * _e67));
    float fine = 0.45 + ((0.55 * _e67) * (0.7 + (0.3 * _e72)));
    float _e116 = pfbm(uv_1 * metal::float2(4.0, 16.0), 4, 5);
    float streak = (_e116 * 0.5) + 0.5;
    dst.write(metal::float4(metal::clamp((big * 0.6) + (dens * 0.4), 0.0, 1.0), metal::clamp((fine * 0.8) + (fineD * 0.2), 0.0, 1.0), dens, streak), metal::uint2(id.xy));
    return;
}

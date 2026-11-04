// Native Metal shaders migrated from the original ocean equations using Naga.
// Edit this file for native rendering; no WGSL or JavaScript runs in the app.
// language: metal2.3
#include <metal_stdlib>
#include <simd/simd.h>

using metal::uint;

struct _mslBufferSizes {
    uint size1;
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
typedef metal::float4 type_6[1];
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

uint pcgHash(
    uint v
) {
    uint s_2 = (v * 747796405u) + 2891336453u;
    uint w_2 = ((s_2 >> ((s_2 >> 28u) + 4u)) ^ s_2) * 277803737u;
    return (w_2 >> 22u) ^ w_2;
}

metal::float2 hashGrad(
    metal::int2 i
) {
    uint _e9 = pcgHash(static_cast<uint>(i.y) + 1013904223u);
    uint _e11 = pcgHash((static_cast<uint>(i.x) * 1664525u) + _e9);
    float a_3 = static_cast<float>(_e11) * 0.0000000014629181;
    return metal::float2(metal::cos(a_3), metal::sin(a_3));
}

metal::int2 naga_f2i32(metal::float2 value) {
    return static_cast<metal::int2>(metal::clamp(value, -2147483600.0, 2147483500.0));
}

float gnoise(
    metal::float2 p
) {
    metal::int2 i_1 = naga_f2i32(metal::floor(p));
    metal::float2 f = p - metal::floor(p);
    metal::float2 u = ((f * f) * f) * ((f * ((f * 6.0) - metal::float2(15.0))) + metal::float2(10.0));
    metal::float2 _e17 = hashGrad(i_1);
    float a_4 = metal::dot(_e17, f);
    metal::float2 _e23 = hashGrad(as_type<metal::int2>(as_type<metal::uint2>(i_1) + as_type<metal::uint2>(metal::int2(1, 0))));
    float b_1 = metal::dot(_e23, f - metal::float2(1.0, 0.0));
    metal::float2 _e33 = hashGrad(as_type<metal::int2>(as_type<metal::uint2>(i_1) + as_type<metal::uint2>(metal::int2(0, 1))));
    float c_1 = metal::dot(_e33, f - metal::float2(0.0, 1.0));
    metal::float2 _e43 = hashGrad(as_type<metal::int2>(as_type<metal::uint2>(i_1) + as_type<metal::uint2>(metal::int2(1, 1))));
    float d = metal::dot(_e43, f - metal::float2(1.0, 1.0));
    return metal::mix(metal::mix(a_4, b_1, u.x), metal::mix(c_1, d, u.x), u.y);
}

float rand01_(
    uint s
) {
    uint _e1 = pcgHash(s);
    return (static_cast<float>(_e1 >> 8u) + 0.5) / 16777216.0;
}

metal::float2 gauss2_(
    uint seed
) {
    float _e5 = rand01_((seed * 2u) + 17u);
    uint _e10 = pcgHash(seed);
    float _e12 = rand01_(((seed * 2u) + 18u) + _e10);
    float r = metal::sqrt(-2.0 * metal::log(_e5));
    float a_5 = 6.2831855 * _e12;
    return r * metal::float2(metal::cos(a_5), metal::sin(a_5));
}

float wrapAngle(
    float a_2
) {
    float x_1 = {};
    x_1 = a_2;
    float _e2 = x_1;
    float _e4 = x_1;
    x_1 = _e2 - (6.2831855 * metal::floor((_e4 + PI) / 6.2831855));
    float _e12 = x_1;
    return _e12;
}

float jonswap(
    float w,
    float wp,
    float alpha,
    float gamma
) {
    float sigma = (w <= wp) ? 0.07 : 0.09;
    float d_1 = (w - wp) / (sigma * wp);
    float r_1 = metal::exp((-0.5 * d_1) * d_1);
    float q = wp / w;
    float q2_ = q * q;
    return ((((alpha * GRAV) * GRAV) / ((((w * w) * w) * w) * w)) * metal::exp((-1.25 * q2_) * q2_)) * metal::pow(gamma, r_1);
}

float donelanBanner(
    float theta,
    float w_1,
    float wp_1
) {
    float beta = {};
    float ratio = w_1 / wp_1;
    if (ratio < 0.95) {
        beta = 2.61 * metal::pow(ratio, 1.3);
    } else {
        if (ratio < 1.6) {
            beta = 2.28 * metal::pow(ratio, -1.3);
        } else {
            float eps = -0.4 + (0.8393 * metal::exp(-0.567 * metal::log(ratio * ratio)));
            beta = metal::pow(10.0, eps);
        }
    }
    float _e28 = beta;
    float sh = 1.0 / metal::cosh(metal::clamp(_e28 * theta, -20.0, 20.0));
    float _e36 = beta;
    float _e37 = beta;
    return ((_e36 / (2.0 * metal::tanh(_e37 * PI))) * sh) * sh;
}

float cosSpread(
    float theta_1,
    float s_1
) {
    float q_1 = metal::sqrt(s_1 + 0.25) / 3.5449078;
    return q_1 * metal::pow(metal::abs(metal::cos(theta_1 * 0.5)), 2.0 * s_1);
}

float spectrum(
    metal::float2 k_2,
    constant Sim& S
) {
    float Sw = 0.0;
    float kl = metal::length(k_2);
    float _e2 = omegaOf(kl);
    float theta_2 = metal::atan2(k_2.y, k_2.x);
    float U = S.wind.x;
    float F = S.wind.z;
    if (U > 0.1) {
        float alpha_1 = 0.076 * metal::pow((U * U) / (F * GRAV), 0.22);
        float wp_2 = 22.0 * metal::pow(96.23611 / (U * F), 0.33333334);
        float _e36 = S.wind.w;
        float _e37 = jonswap(_e2, wp_2, alpha_1, _e36);
        float _e41 = S.wind.y;
        float _e43 = wrapAngle(theta_2 - _e41);
        float _e44 = donelanBanner(_e43, _e2, wp_2);
        Sw = _e37 * _e44;
    }
    float _e49 = S.swell.x;
    if (_e49 > 0.001) {
        float ws = S.swell.z;
        float _e60 = S.swell.x;
        float hs4_ = _e60 * 0.25;
        float alphaS = (((((((hs4_ * hs4_) * 5.0) * ws) * ws) * ws) * ws) / 96.23611) * (1.0 - (0.287 * metal::log(6.0)));
        float _e78 = Sw;
        float _e79 = jonswap(_e2, ws, alphaS, 6.0);
        float _e83 = S.swell.y;
        float _e85 = wrapAngle(theta_2 - _e83);
        float _e89 = S.swell.w;
        float _e90 = cosSpread(_e85, _e89);
        Sw = _e78 + (_e79 * _e90);
    }
    float sc = S.misc.y;
    float _e97 = Sw;
    Sw = _e97 * metal::exp(((-(kl) * kl) * sc) * sc);
    float _e104 = Sw;
    float _e105 = dOmegaOf(kl);
    float _e111 = S.timeP.w;
    return ((_e104 * _e105) / kl) * _e111;
}

float amplitude(
    metal::float2 k_3,
    uint c,
    constant Sim& S
) {
    bool local = {};
    bool local_1 = {};
    float kl_1 = metal::length(k_3);
    if (!((kl_1 < 0.00001))) {
        float _e16 = S.kMin.inner[c >> 2u][c & 3u];
        local = kl_1 < _e16;
    } else {
        local = true;
    }
    bool _e19 = local;
    if (!(_e19)) {
        float _e31 = S.kMax.inner[c >> 2u][c & 3u];
        local_1 = kl_1 >= _e31;
    } else {
        local_1 = true;
    }
    bool _e34 = local_1;
    if (_e34) {
        return 0.0;
    }
    float _e45 = S.L.inner[c >> 2u][c & 3u];
    float dk = 6.2831855 / _e45;
    float g = (c >= 4u) ? ((c == 5u) ? 0.6 : 0.85) : 1.0;
    float _e56 = spectrum(k_3, S);
    return ((metal::sqrt(metal::max(_e56, 0.0)) * dk) * 0.5) * g;
}
uint naga_f2u32(float value) {
    return static_cast<uint>(metal::clamp(value, 0.0, 4294967000.0));
}


struct main_Input {
};
[[max_total_threads_per_threadgroup(256)]] kernel void main_(
  metal::uint3 id [[thread_position_in_grid]]
, constant Sim& S [[buffer(0)]]
, device type_6& h0_ [[buffer(1)]]
, constant _mslBufferSizes& _buffer_sizes [[buffer(30)]]
) {

    uint c_2 = id.z;
    float L_1 = S.L.inner[c_2 >> 2u][c_2 & 3u];
    metal::float2 _e13 = waveVec(id.x, id.y, L_1);
    uint mx = (N - id.x) % N;
    uint my = (N - id.y) % N;
    float _e27 = S.misc.w;
    uint seed_1 = (naga_f2u32(_e27) * 7919u) + (c_2 * 1000003u);
    metal::float2 _e40 = gauss2_(seed_1 + ((id.y * N) + id.x));
    float _e41 = amplitude(_e13, c_2, S);
    metal::float2 a_6 = _e40 * _e41;
    metal::float2 _e47 = gauss2_(seed_1 + ((my * N) + mx));
    float _e49 = amplitude(-(_e13), c_2, S);
    metal::float2 b_2 = _e47 * _e49;
    h0_[(((c_2 * N) + id.y) * N) + id.x] = metal::float4(a_6, b_2.x, -(b_2.y));
    return;
}

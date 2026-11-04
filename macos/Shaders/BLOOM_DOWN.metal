// Native Metal shaders migrated from the original ocean equations using Naga.
// Edit this file for native rendering; no WGSL or JavaScript runs in the app.
// language: metal2.3
#include <metal_stdlib>
#include <simd/simd.h>

using metal::uint;

struct VO {
    metal::float4 pos;
    metal::float2 uv;
    char _pad2[8];
};
struct P {
    metal::float4 texel;
};

float luma(
    metal::float3 c
) {
    return metal::dot(c, metal::float3(0.2126, 0.7152, 0.0722));
}

metal::float3 tap(
    metal::float2 uv,
    metal::texture2d<float, metal::access::sample> src,
    metal::sampler samp
) {
    metal::float4 _e4 = src.sample(samp, uv, metal::level(0.0));
    return _e4.xyz;
}

float karis(
    metal::float3 c_1
) {
    float _e1 = luma(c_1);
    return 1.0 / (1.0 + (_e1 * 0.25));
}

struct vsInput {
};
struct vsOutput {
    metal::float4 pos [[position]];
    metal::float2 uv [[user(loc0), center_perspective]];
};
vertex vsOutput vs(
  uint i [[vertex_id]]
) {
    VO o = {};
    metal::float2 p = metal::float2(static_cast<float>((i << 1u) & 2u), static_cast<float>(i & 2u));
    o.pos = metal::float4((p * 2.0) - metal::float2(1.0), 0.0, 1.0);
    o.uv = metal::float2(p.x, 1.0 - p.y);
    VO _e26 = o;
    const auto _tmp = _e26;
    return vsOutput { _tmp.pos, _tmp.uv };
}


struct fsInput {
    metal::float2 uv_1 [[user(loc0), center_perspective]];
};
struct fsOutput {
    metal::float4 member_1 [[color(0)]];
};
fragment fsOutput fs(
  fsInput varyings_1 [[stage_in]]
, metal::float4 pos [[position]]
, metal::texture2d<float, metal::access::sample> src [[texture(0)]]
, metal::sampler samp [[sampler(1)]]
, constant P& U [[buffer(2)]]
) {
    const VO in = { pos, varyings_1.uv_1 };
    metal::float3 o_1 = {};
    metal::float4 _e3 = U.texel;
    metal::float2 t = _e3.xy;
    metal::float2 uv_1 = in.uv;
    metal::float3 _e11 = tap(uv_1 + (t * metal::float2(-2.0, -2.0)), src, samp);
    metal::float3 _e17 = tap(uv_1 + (t * metal::float2(0.0, -2.0)), src, samp);
    metal::float3 _e23 = tap(uv_1 + (t * metal::float2(2.0, -2.0)), src, samp);
    metal::float3 _e29 = tap(uv_1 + (t * metal::float2(-2.0, 0.0)), src, samp);
    metal::float3 _e30 = tap(uv_1, src, samp);
    metal::float3 _e36 = tap(uv_1 + (t * metal::float2(2.0, 0.0)), src, samp);
    metal::float3 _e42 = tap(uv_1 + (t * metal::float2(-2.0, 2.0)), src, samp);
    metal::float3 _e48 = tap(uv_1 + (t * metal::float2(0.0, 2.0)), src, samp);
    metal::float3 _e54 = tap(uv_1 + (t * metal::float2(2.0, 2.0)), src, samp);
    metal::float3 _e60 = tap(uv_1 + (t * metal::float2(-1.0, -1.0)), src, samp);
    metal::float3 _e66 = tap(uv_1 + (t * metal::float2(1.0, -1.0)), src, samp);
    metal::float3 _e72 = tap(uv_1 + (t * metal::float2(-1.0, 1.0)), src, samp);
    metal::float3 _e78 = tap(uv_1 + (t * metal::float2(1.0, 1.0)), src, samp);
    float _e83 = U.texel.z;
    if (_e83 > 0.5) {
        metal::float3 g0_ = (((_e11 + _e17) + _e29) + _e30) * 0.25;
        metal::float3 g1_ = (((_e17 + _e23) + _e30) + _e36) * 0.25;
        metal::float3 g2_ = (((_e29 + _e30) + _e42) + _e48) * 0.25;
        metal::float3 g3_ = (((_e30 + _e36) + _e48) + _e54) * 0.25;
        metal::float3 g4_ = (((_e60 + _e66) + _e72) + _e78) * 0.25;
        float _e111 = karis(g0_);
        float w0_ = _e111 * 0.125;
        float _e114 = karis(g1_);
        float w1_ = _e114 * 0.125;
        float _e117 = karis(g2_);
        float w2_ = _e117 * 0.125;
        float _e120 = karis(g3_);
        float w3_ = _e120 * 0.125;
        float _e123 = karis(g4_);
        float w4_ = _e123 * 0.5;
        o_1 = (((((g0_ * w0_) + (g1_ * w1_)) + (g2_ * w2_)) + (g3_ * w3_)) + (g4_ * w4_)) / metal::float3((((w0_ + w1_) + w2_) + w3_) + w4_);
    } else {
        o_1 = (((_e30 * 0.125) + ((((_e11 + _e23) + _e42) + _e54) * 0.03125)) + ((((_e17 + _e29) + _e36) + _e48) * 0.0625)) + ((((_e60 + _e66) + _e72) + _e78) * 0.125);
    }
    metal::float3 _e161 = o_1;
    return fsOutput { metal::float4(metal::min(_e161, metal::float3(60000.0)), 1.0) };
}

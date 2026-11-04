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

metal::float3 tap(
    metal::float2 uv,
    metal::texture2d<float, metal::access::sample> src,
    metal::sampler samp
) {
    metal::float4 _e4 = src.sample(samp, uv, metal::level(0.0));
    return _e4.xyz;
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
    float _e8 = U.texel.z;
    metal::float2 t = _e3.xy * _e8;
    metal::float2 uv_1 = in.uv;
    metal::float3 _e11 = tap(uv_1, src, samp);
    o_1 = _e11 * 4.0;
    metal::float3 _e15 = o_1;
    metal::float3 _e21 = tap(uv_1 + metal::float2(-(t.x), 0.0), src, samp);
    metal::float3 _e26 = tap(uv_1 + metal::float2(t.x, 0.0), src, samp);
    metal::float3 _e33 = tap(uv_1 + metal::float2(0.0, -(t.y)), src, samp);
    metal::float3 _e39 = tap(uv_1 + metal::float2(0.0, t.y), src, samp);
    o_1 = _e15 + ((((_e21 + _e26) + _e33) + _e39) * 2.0);
    metal::float3 _e44 = o_1;
    metal::float3 _e51 = tap(uv_1 + metal::float2(-(t.x), -(t.y)), src, samp);
    metal::float3 _e57 = tap(uv_1 + metal::float2(t.x, -(t.y)), src, samp);
    metal::float3 _e64 = tap(uv_1 + metal::float2(-(t.x), t.y), src, samp);
    metal::float3 _e70 = tap(uv_1 + metal::float2(t.x, t.y), src, samp);
    o_1 = _e44 + (((_e51 + _e57) + _e64) + _e70);
    metal::float3 _e73 = o_1;
    float _e77 = U.texel.w;
    return fsOutput { metal::float4(_e73 * (_e77 / 16.0), 1.0) };
}

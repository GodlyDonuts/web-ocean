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
    metal::float4 p;
    metal::float4 q;
    metal::float4 rain; // density, crosswind, continuous phase seconds, mist
    metal::float4 weather; // severity, thunder, night, reserved
};

metal::float3 agxContrast(
    metal::float3 x
) {
    metal::float3 x2_ = x * x;
    metal::float3 x4_ = x2_ * x2_;
    return (((((((15.5 * x4_) * x2_) - ((40.14 * x4_) * x)) + (31.96 * x4_)) - ((6.868 * x2_) * x)) + (0.4298 * x2_)) + (0.1191 * x)) - metal::float3(0.00232);
}

metal::float3 agx(
    metal::float3 v
) {
    metal::float3 x_1 = {};
    metal::float3x3 m = metal::float3x3(metal::float3(0.84247905, 0.042328242, 0.042375654), metal::float3(0.0784336, 0.87846863, 0.0784336), metal::float3(0.079223745, 0.07916613, 0.879143));
    x_1 = m * metal::max(v, metal::float3(0.0000000001));
    metal::float3 _e21 = x_1;
    x_1 = metal::clamp(metal::log2(_e21), metal::float3(-12.47393), metal::float3(4.026069));
    metal::float3 _e26 = x_1;
    x_1 = (_e26 - metal::float3(-12.47393)) / metal::float3(4.026069 - -12.47393);
    metal::float3 _e32 = x_1;
    metal::float3 _e33 = agxContrast(_e32);
    return _e33;
}

metal::float3 agxEotf(
    metal::float3 v_1
) {
    metal::float3x3 mi = metal::float3x3(metal::float3(1.196879, -0.052896854, -0.052971635), metal::float3(-0.09802088, 1.1519032, -0.09804345), metal::float3(-0.09902974, -0.098961174, 1.1510737));
    return mi * v_1;
}

metal::float3 agxLook(
    metal::float3 v_2,
    float sat,
    float power
) {
    float l = metal::dot(v_2, metal::float3(0.2126, 0.7152, 0.0722));
    metal::float3 p_1 = metal::pow(metal::max(v_2, metal::float3(0.0)), metal::float3(power));
    return metal::float3(l) + (sat * (p_1 - metal::float3(l)));
}

float ign(
    metal::float2 p
) {
    return metal::fract(52.982918 * metal::fract(metal::dot(p, metal::float2(0.06711056, 0.00583715))));
}

float weatherHash(metal::float2 p) {
    return metal::fract(metal::sin(metal::dot(p,metal::float2(127.1,311.7)))*43758.5453);
}
metal::float3 precipitation(metal::float3 color,metal::float2 uv,metal::float2 dims,constant P& U) {
    float density=U.rain.x,storm=U.weather.x,time=U.rain.z;
    if (density<=0.00001 && U.rain.w<=0.00001 && U.weather.y<=0.00001) return color;
    float night=U.weather.z;
    // Rain and precipitation extinction are rendered in world space before
    // tone mapping. Only the rare atmospheric lightning glow remains here.
    float horizon=metal::exp(-metal::abs(uv.y-0.413)*9.0);
    float flash=U.weather.w;
    color+=metal::float3(0.45,0.57,0.76)*flash*(0.35+horizon*0.65);
    // A distant forked lightning channel, softened by the rain curtain.
    if (flash>0.001) {
        float event=metal::floor(time/13.0);
        float center=0.24+weatherHash(metal::float2(event,7.2))*0.52;
        float y=metal::clamp((uv.y-0.12)/0.30,0.0,1.0);
        float bend=metal::sin(y*31.0+event)*0.008+metal::sin(y*79.0)*0.003;
        float bolt=metal::exp(-metal::abs(uv.x-center-bend-y*0.055)*dims.x*0.40);
        bolt*=metal::smoothstep(0.12,0.15,uv.y)*(1.0-metal::smoothstep(0.38,0.42,uv.y));
        color+=metal::float3(1.7,1.9,2.5)*bolt*flash;
    }
    return color;
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
    metal::float2 p_2 = metal::float2(static_cast<float>((i << 1u) & 2u), static_cast<float>(i & 2u));
    o.pos = metal::float4((p_2 * 2.0) - metal::float2(1.0), 0.0, 1.0);
    o.uv = metal::float2(p_2.x, 1.0 - p_2.y);
    VO _e26 = o;
    const auto _tmp = _e26;
    return vsOutput { _tmp.pos, _tmp.uv };
}

metal::int2 naga_f2i32(metal::float2 value) {
    return static_cast<metal::int2>(metal::clamp(value, -2147483600.0, 2147483500.0));
}


struct fsInput {
    metal::float2 uv [[user(loc0), center_perspective]];
};
struct fsOutput {
    metal::float4 member_1 [[color(0)]];
};
// Shared display transform: bloom, weather glow, exposure, vignette, AgX and dither.
metal::float4 compositeFinish(metal::float3 c, metal::float3 b, metal::float2 uv, metal::float2 pos,
                              metal::float2 dims, constant P& U) {
    c = metal::mix(c, b, U.p.y);
    c = precipitation(c, uv, dims, U);
    c = c * U.p.x;
    metal::float2 d = (uv - metal::float2(0.5)) * metal::float2(dims.x / dims.y, 1.0);
    c = c * (1.0 - (U.p.w * metal::dot(d, d)));
    c = c * metal::float3(1.0 + U.q.z, 1.0, 1.0 - U.q.z);
    float lum = metal::dot(c, metal::float3(0.2126, 0.7152, 0.0722));
    c = metal::mix(c, metal::float3(lum), metal::smoothstep(0.7, 6.0, lum) * 0.55);
    metal::float3 o_1 = agx(c);
    o_1 = agxLook(o_1, U.q.x, U.q.y);
    o_1 = agxEotf(o_1);
    float n = (ign(pos + metal::float2(U.p.z * 5.588238)) + ign(((pos * 1.37) + metal::float2(17.0)) + metal::float2(U.p.z * 3.1))) - 1.0;
    o_1 = o_1 + metal::float3(n / 255.0);
    return metal::float4(metal::clamp(o_1, metal::float3(0.0), metal::float3(1.0)), 1.0);
}
fragment fsOutput fs(
  fsInput varyings_1 [[stage_in]]
, metal::float4 pos [[position]]
, metal::texture2d<float, metal::access::sample> hdr [[texture(0)]]
, metal::texture2d<float, metal::access::sample> bloom [[texture(1)]]
, metal::sampler samp [[sampler(2)]]
, constant P& U [[buffer(3)]]
) {
    metal::float2 dims = static_cast<metal::float2>(metal::uint2(hdr.get_width(), hdr.get_height()));
    metal::int2 pc = naga_f2i32(pos.xy);
    metal::float3 c = hdr.read(metal::uint2(pc), 0).xyz;
    metal::float3 b = bloom.sample(samp, varyings_1.uv, metal::level(0.0)).xyz * 0.125;
    return fsOutput { compositeFinish(c, b, varyings_1.uv, pos.xy, dims, U) };
}
// Additional displays reuse the same HDR frame with an aspect-fill mapping:
// one simulation and one scene render, one cheap resample per extra screen.
fragment fsOutput fs_mirror(
  fsInput varyings_1 [[stage_in]]
, metal::float4 pos [[position]]
, metal::texture2d<float, metal::access::sample> hdr [[texture(0)]]
, metal::texture2d<float, metal::access::sample> bloom [[texture(1)]]
, metal::sampler samp [[sampler(2)]]
, constant P& U [[buffer(3)]]
, constant metal::float4& M [[buffer(4)]]
) {
    metal::float2 uv = varyings_1.uv * M.xy + M.zw;
    metal::float2 dims = static_cast<metal::float2>(metal::uint2(hdr.get_width(), hdr.get_height()));
    metal::float3 c = hdr.sample(samp, uv, metal::level(0.0)).xyz;
    metal::float3 b = bloom.sample(samp, uv, metal::level(0.0)).xyz * 0.125;
    return fsOutput { compositeFinish(c, b, uv, pos.xy, dims, U) };
}

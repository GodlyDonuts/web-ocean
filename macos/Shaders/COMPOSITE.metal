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
fragment fsOutput fs(
  fsInput varyings_1 [[stage_in]]
, metal::float4 pos [[position]]
, metal::texture2d<float, metal::access::sample> hdr [[texture(0)]]
, metal::texture2d<float, metal::access::sample> bloom [[texture(1)]]
, metal::sampler samp [[sampler(2)]]
, constant P& U [[buffer(3)]]
) {
    const VO in = { pos, varyings_1.uv };
    metal::float3 c = {};
    metal::float3 o_1 = {};
    metal::float2 dims = static_cast<metal::float2>(metal::uint2(hdr.get_width(), hdr.get_height()));
    metal::int2 pc = naga_f2i32(in.pos.xy);
    metal::float4 _e9 = hdr.read(metal::uint2(pc), 0);
    c = _e9.xyz;
    metal::float4 _e16 = bloom.sample(samp, in.uv, metal::level(0.0));
    metal::float3 b = _e16.xyz * 0.125;
    metal::float3 _e20 = c;
    float _e24 = U.p.y;
    c = metal::mix(_e20, b, _e24);
    c=precipitation(c,in.uv,dims,U);
    metal::float3 _e26 = c;
    float _e30 = U.p.x;
    c = _e26 * _e30;
    metal::float2 d = (in.uv - metal::float2(0.5)) * metal::float2(dims.x / dims.y, 1.0);
    metal::float3 _e42 = c;
    float _e46 = U.p.w;
    c = _e42 * (1.0 - (_e46 * metal::dot(d, d)));
    metal::float3 _e52 = c;
    float _e56 = U.q.z;
    float _e62 = U.q.z;
    c = _e52 * metal::float3(1.0 + _e56, 1.0, 1.0 - _e62);
    metal::float3 _e68 = c;
    float lum = metal::dot(_e68, metal::float3(0.2126, 0.7152, 0.0722));
    metal::float3 _e74 = c;
    c = metal::mix(_e74, metal::float3(lum), metal::smoothstep(0.7, 6.0, lum) * 0.55);
    metal::float3 _e82 = c;
    metal::float3 _e83 = agx(_e82);
    o_1 = _e83;
    metal::float3 _e85 = o_1;
    float _e89 = U.q.x;
    float _e93 = U.q.y;
    metal::float3 _e94 = agxLook(_e85, _e89, _e93);
    o_1 = _e94;
    metal::float3 _e95 = o_1;
    metal::float3 _e96 = agxEotf(_e95);
    o_1 = _e96;
    float _e102 = U.p.z;
    float _e107 = ign(in.pos.xy + metal::float2(_e102 * 5.588238));
    float _e118 = U.p.z;
    float _e123 = ign(((in.pos.xy * 1.37) + metal::float2(17.0)) + metal::float2(_e118 * 3.1));
    float n = (_e107 + _e123) - 1.0;
    metal::float3 _e127 = o_1;
    o_1 = _e127 + metal::float3(n / 255.0);
    metal::float3 _e132 = o_1;
    return fsOutput { metal::float4(metal::clamp(_e132, metal::float3(0.0), metal::float3(1.0)), 1.0) };
}

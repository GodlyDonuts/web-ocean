// Native Metal shaders migrated from the original ocean equations using Naga.
// Edit this file for native rendering; no WGSL or JavaScript runs in the app.
// language: metal2.3
#include <metal_stdlib>
#include <simd/simd.h>

using metal::uint;
#include "WATER_VIEW.metalinc"
#include "AURORA.metalinc"


struct VO {
    metal::float4 pos;
    metal::float2 uv;
    char _pad2[8];
};

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
    metal::float2 uv [[user(loc0), center_perspective]];
};
struct fsOutput {
    metal::float4 member_1 [[color(0)]];
};
fragment fsOutput fs(
  fsInput varyings_1 [[stage_in]]
, metal::float4 pos [[position]]
, metal::texture2d<float, metal::access::sample> sky [[texture(0)]]
, metal::sampler samp [[sampler(1)]]
, constant metal::float4* F [[buffer(2)]]
, const device metal::float4* water [[buffer(3)]]
) {
    const VO in = { pos, varyings_1.uv };
    metal::float4 _e4 = sky.sample(samp, in.uv);
    metal::float2 ndc=metal::float2(in.uv.x*2.0-1.0,1.0-in.uv.y*2.0);
    metal::float3 ray=metal::normalize(F[7].xyz+ndc.x*F[5].xyz+ndc.y*F[6].xyz);
    // Uncovered downward rays see the sea volume, including when a near wave
    // passes through the eye/near plane. Never expose the cleared sky cache.
    float below=1.0-metal::smoothstep(-0.015,0.0,ray.y);
    float volume=metal::max(below,water[0].z);
    if (F[17].w>7.5 && F[17].w<8.5) volume=0.0;
    metal::float3 color=metal::mix(_e4.xyz,waterVolumeRadiance(F[40].z,ray.y,water[0].y),volume);
    float night=F[40].w>0.5 ? F[40].z : 0.0;
    if (night>0.001 && volume<0.999 && ray.y>0.0) {
        // Full-rate night events over the 8 Hz cloud cache; its alpha is the
        // view-ray cloud transmission, so clouds occlude curtains and meteors.
        float jitter=fxHash(pos.xy+metal::float2(metal::fmod(F[17].z,64.0)*7.31,0.0));
        float pixAng=2.0*metal::length(F[6].xyz)*F[9].w;
        metal::float3 fx=auroraRadiance(ray,F[48],night,16,jitter)+meteorRadiance(ray,F[48],night,pixAng,F[7].xyz);
        color+=fx*metal::clamp(_e4.w,0.0,1.0)*(1.0-volume);
    }
    if (F[18].z>0.05 && volume<0.999 && ray.y>0.0) {
        metal::float3 halo=iceHalo(ray,metal::normalize(F[41].xyz),F[18].z);
        color+=_e4.xyz*halo*metal::clamp(_e4.w,0.0,1.0)*(1.0-volume);
    }
    float bowRain=metal::smoothstep(0.03,0.3,F[47].y)*(1.0-0.75*F[47].x)*(1.0-(F[40].w>0.5 ? F[40].z : 0.0));
    if (bowRain>0.001 && volume<0.999 && ray.y>0.0) {
        metal::float3 bow=rainbow(ray,metal::normalize(F[42].xyz),bowRain);
        color=metal::max(color+_e4.xyz*bow*(1.0-volume),metal::float3(0.0));
    }
    return fsOutput { metal::float4(color,1.0) };
}

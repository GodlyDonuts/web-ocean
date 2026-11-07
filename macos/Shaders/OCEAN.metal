// Native Metal shaders migrated from the original ocean equations using Naga.
// Edit this file for native rendering; no WGSL or JavaScript runs in the app.
// language: metal2.3
#include <metal_stdlib>
#include <simd/simd.h>

using metal::uint;
#include "WATER_VIEW.metalinc"

struct type_2 {
    metal::float4 inner[2];
};
struct Frame {
    metal::float4x4 viewProj;
    metal::float4 camPos;
    metal::float4 camRight;
    metal::float4 camUp;
    metal::float4 camFwd;
    metal::float4 sunDir;
    metal::float4 screen;
    type_2 cascL;
    type_2 cascInvL;
    type_2 windP;
    metal::float4 lodP;
    metal::float4 post;
    metal::float4 atmo;
    metal::float4 waterCol;
    metal::float4 sssCol;
    metal::float4 foamP;
    metal::float4 fogExt;
    metal::float4 cloudP;
    metal::float4 cloudPadding[15];
    metal::float4 moonDir;
    metal::float4 celestial; // sun radius, moon radius, night factor, enabled
    metal::float4 lightDir; // dominant directional light and illuminance
    metal::float4 sunDiskDir; // apparent direction, angular radius
    metal::float4 starX;
    metal::float4 starY;
    metal::float4 starZ;
    metal::float4 motionPadding[2]; // cloud evolution and weather
    metal::float4 moonPhaseLight;

};
struct Medium {
    metal::float3 ext;
    metal::packed_float3 rayS;
    float mieS;
};
struct type_11 {
    float inner[4];
};
struct VSOut {
    metal::float4 pos;
    metal::float3 rel;
    metal::float2 xz;
    float height;
    char _pad4[4];
};
constant float PI = 3.1415927;
constant float RG = 6360.0;
constant float RT = 6460.0;
constant metal::float3 RAY_S = metal::float3(0.005802, 0.013558, 0.0331);
constant float MIE_S = 0.003996;
constant float MIE_E = 0.0044;
constant metal::float3 OZO_A = metal::float3(0.00065, 0.001881, 0.000085);
constant float SUN_ANG_R = 0.004675;
constant float TRANS_W = 256.0;
constant float TRANS_H = 64.0;
constant float MS_SIZE = 32.0;
constant float SKY_W = 256.0;
constant float SKY_H = 144.0;
constant float ENV_MAXMIP = 7.0;
constant float ENV_TEXELS_PER_RAD = 81.48714;
constant float TEX_N = 256.0;

Medium medium(
    float h,
    float haze
) {
    Medium m = {};
    float hh = metal::max(h, 0.0);
    float dR = metal::exp(-(hh) / 8.0);
    float dM = metal::exp(-(hh) / 1.2);
    float dO = metal::max(0.0, 1.0 - (metal::abs(hh - 25.0) / 15.0));
    m.rayS = RAY_S * dR;
    m.mieS = (MIE_S * dM) * haze;
    metal::float3 _e31 = m.rayS;
    m.ext = (_e31 + metal::float3((MIE_E * dM) * haze)) + (OZO_A * dO);
    Medium _e40 = m;
    return _e40;
}

metal::float2 raySphere(
    metal::float3 ro,
    metal::float3 rd,
    float R_1
) {
    float l = metal::length(ro);
    float b = metal::dot(ro, rd);
    float c_6 = (l - R_1) * (l + R_1);
    float d = (b * b) - c_6;
    if (d < 0.0) {
        return metal::float2(-1.0, -1.0);
    }
    float s_1 = metal::sqrt(d);
    return metal::float2(-(b) - s_1, -(b) + s_1);
}

float rhoOf(
    float r
) {
    return metal::sqrt(metal::max(0.0, (r - RG) * (r + RG)));
}

metal::float2 transRMuToUV(
    float r_1,
    float mu
) {
    float _e3 = rhoOf(r_1);
    float disc = ((r_1 * r_1) * ((mu * mu) - 1.0)) + 41731600.0;
    float d_1 = metal::max(0.0, (-(r_1) * mu) + metal::sqrt(metal::max(disc, 0.0)));
    float dMin = RT - r_1;
    float dMax = _e3 + 1132.2544;
    float x = (d_1 - dMin) / (dMax - dMin);
    float y = _e3 / 1132.2544;
    return metal::float2(x, y);
}

metal::float2 transUVToRMu(
    metal::float2 uv
) {
    float mu_1 = 1.0;
    float rho = 1132.2544 * uv.y;
    float r_4 = metal::sqrt((rho * rho) + 40449600.0);
    float dMin_1 = RT - r_4;
    float dMax_1 = rho + 1132.2544;
    float d_2 = dMin_1 + (uv.x * (dMax_1 - dMin_1));
    if (d_2 > 0.0) {
        mu_1 = (((1132.2544 * 1132.2544) - (rho * rho)) - (d_2 * d_2)) / ((2.0 * r_4) * d_2);
    }
    float _e28 = mu_1;
    return metal::float2(r_4, metal::clamp(_e28, -1.0, 1.0));
}

float fromUnitToSubUvs(
    float u,
    float res
) {
    return (u + (0.5 / res)) * (res / (res + 1.0));
}

float fromSubUvsToUnit(
    float u_1,
    float res_1
) {
    return (u_1 - (0.5 / res_1)) * (res_1 / (res_1 - 1.0));
}

float phaseRayleigh(
    float c_2
) {
    return 0.059683103 * (1.0 + (c_2 * c_2));
}

float phaseMie(
    float c_3,
    float g
) {
    float g2_ = g * g;
    return (0.119366206 * ((1.0 - g2_) * (1.0 + (c_3 * c_3)))) / ((2.0 + g2_) * metal::pow(metal::max((1.0 + g2_) - ((2.0 * g) * c_3), 0.0001), 1.5));
}

float phaseHG(
    float c_4,
    float g_1
) {
    float g2_1 = g_1 * g_1;
    return (1.0 - g2_1) / (12.566371 * metal::pow(metal::max((1.0 + g2_1) - ((2.0 * g_1) * c_4), 0.0001), 1.5));
}

bool sunBelowHorizon(
    float r_2,
    float mu_2
) {
    float _e2 = rhoOf(r_2);
    return mu_2 < (-(_e2) / r_2);
}

uint pcgHash(
    uint v
) {
    uint s_2 = (v * 747796405u) + 2891336453u;
    uint w_1 = ((s_2 >> ((s_2 >> 28u) + 4u)) ^ s_2) * 277803737u;
    return (w_1 >> 22u) ^ w_1;
}

metal::float2 hashGrad(
    metal::int2 i
) {
    uint _e9 = pcgHash(static_cast<uint>(i.y) + 1013904223u);
    uint _e11 = pcgHash((static_cast<uint>(i.x) * 1664525u) + _e9);
    float a = static_cast<float>(_e11) * 0.0000000014629181;
    return metal::float2(metal::cos(a), metal::sin(a));
}

metal::int2 naga_f2i32(metal::float2 value) {
    return static_cast<metal::int2>(metal::clamp(value, -2147483600.0, 2147483500.0));
}

float gnoise(
    metal::float2 p
) {
    metal::int2 i_1 = naga_f2i32(metal::floor(p));
    metal::float2 f = p - metal::floor(p);
    metal::float2 u_2 = ((f * f) * f) * ((f * ((f * 6.0) - metal::float2(15.0))) + metal::float2(10.0));
    metal::float2 _e17 = hashGrad(i_1);
    float a_1 = metal::dot(_e17, f);
    metal::float2 _e23 = hashGrad(as_type<metal::int2>(as_type<metal::uint2>(i_1) + as_type<metal::uint2>(metal::int2(1, 0))));
    float b_1 = metal::dot(_e23, f - metal::float2(1.0, 0.0));
    metal::float2 _e33 = hashGrad(as_type<metal::int2>(as_type<metal::uint2>(i_1) + as_type<metal::uint2>(metal::int2(0, 1))));
    float c_7 = metal::dot(_e33, f - metal::float2(0.0, 1.0));
    metal::float2 _e43 = hashGrad(as_type<metal::int2>(as_type<metal::uint2>(i_1) + as_type<metal::uint2>(metal::int2(1, 1))));
    float d_3 = metal::dot(_e43, f - metal::float2(1.0, 1.0));
    return metal::mix(metal::mix(a_1, b_1, u_2.x), metal::mix(c_7, d_3, u_2.x), u_2.y);
}

float camR(
    constant Frame& F
) {
    float _e4 = F.atmo.y;
    return RG + _e4;
}

metal::float3 sampleTrans(
    float r_3,
    float mu_3,
    metal::texture2d<float, metal::access::sample> transLUT,
    metal::sampler sampC
) {
    metal::float2 _e4 = transRMuToUV(r_3, mu_3);
    metal::float4 _e6 = transLUT.sample(sampC, _e4, metal::level(0.0));
    return _e6.xyz;
}

metal::float3 sunIlluminance(
    constant Frame& F,
    metal::texture2d<float, metal::access::sample> transLUT,
    metal::sampler sampC
) {
    if (F.celestial.w>0.5) {
        float visible=metal::smoothstep(-F.celestial.x,F.celestial.x,F.lightDir.y);
        metal::float3 tint=F.sunDir.y < -0.0174524 ? metal::float3(0.72,0.81,1.0) : metal::float3(1.0);
        return sampleTrans(camR(F),F.lightDir.y,transLUT,sampC)*F.lightDir.w*visible*tint;
    }
    float _e0 = camR(F);
    float _e4 = F.sunDir.y;
    metal::float3 _e5 = sampleTrans(_e0, _e4, transLUT, sampC);
    float _e9 = F.sunDir.w;
    return _e5 * _e9;
}

metal::float2 skyViewUV(
    metal::float3 dir,
    constant Frame& F
) {
    metal::float2 uv_1 = {};
    float coord = {};
    float coord_1 = {};
    float lvc = 1.0;
    bool local_8 = {};
    float _e1 = camR(F);
    float _e2 = rhoOf(_e1);
    float cosBeta = _e2 / _e1;
    float beta = metal::acos(metal::clamp(cosBeta, -1.0, 1.0));
    float zha = PI - beta;
    float vzc = metal::clamp(dir.y, -1.0, 1.0);
    if (vzc >= -(cosBeta)) {
        coord = metal::acos(vzc) / zha;
        float _e20 = coord;
        coord = 1.0 - _e20;
        float _e23 = coord;
        coord = metal::sqrt(metal::max(_e23, 0.0));
        float _e27 = coord;
        coord = 1.0 - _e27;
        float _e31 = coord;
        uv_1.y = _e31 * 0.5;
    } else {
        coord_1 = (metal::acos(vzc) - zha) / beta;
        float _e38 = coord_1;
        coord_1 = metal::sqrt(metal::max(_e38, 0.0));
        float _e43 = coord_1;
        uv_1.y = (_e43 * 0.5) + 0.5;
    }
    float dl = metal::length(dir.xz);
    metal::float4 _e52 = F.sunDir;
    float sl = metal::length(_e52.xz);
    if (dl > 0.000001) {
        local_8 = sl > 0.000001;
    } else {
        local_8 = false;
    }
    bool _e64 = local_8;
    if (_e64) {
        metal::float4 _e68 = F.sunDir;
        lvc = metal::clamp(metal::dot(dir.xz, _e68.xz) / (dl * sl), -1.0, 1.0);
    }
    float _e77 = lvc;
    uv_1.x = metal::sqrt(metal::max((-(_e77) * 0.5) + 0.5, 0.0));
    float _e87 = uv_1.x;
    float _e89 = fromUnitToSubUvs(_e87, SKY_W);
    float _e91 = uv_1.y;
    float _e93 = fromUnitToSubUvs(_e91, SKY_H);
    return metal::float2(_e89, _e93);
}

// CELESTIAL_SKY_IMPLEMENTATION
metal::float3 skyAtmo(
    metal::float3 dir_1,
    constant Frame& F,
    metal::texture2d<float, metal::access::sample> skyLUT,
    metal::sampler sampC
) {
    metal::float2 _e3 = skyViewUV(dir_1, F);
    metal::float4 _e5 = skyLUT.sample(sampC, _e3, metal::level(0.0));
    float _e10 = F.sunDir.w;
    return _e5.xyz * _e10 + celestialNightSky(dir_1,F);
}

metal::float4 cubicWave(
    metal::texture2d_array<float, metal::access::sample> t,
    metal::float2 uv_2,
    uint layer,
    metal::sampler sampR
) {
    metal::float2 size = static_cast<metal::float2>(metal::uint2(t.get_width(0), t.get_height(0)));
    metal::float2 p_1 = (uv_2 * size) - metal::float2(0.5);
    metal::float2 base = metal::floor(p_1);
    metal::float2 f_1 = metal::fract(p_1);
    metal::float2 w0_ = (((metal::float2(1.0) - f_1) * (metal::float2(1.0) - f_1)) * (metal::float2(1.0) - f_1)) / metal::float2(6.0);
    metal::float2 w1_ = (((((3.0 * f_1) * f_1) * f_1) - ((6.0 * f_1) * f_1)) + metal::float2(4.0)) / metal::float2(6.0);
    metal::float2 w2_ = ((((((-3.0 * f_1) * f_1) * f_1) + ((3.0 * f_1) * f_1)) + (3.0 * f_1)) + metal::float2(1.0)) / metal::float2(6.0);
    metal::float2 w3_ = ((f_1 * f_1) * f_1) / metal::float2(6.0);
    metal::float2 g0_ = w0_ + w1_;
    metal::float2 g1_ = w2_ + w3_;
    metal::float2 h0_ = (((base - metal::float2(1.0)) + (w1_ / g0_)) + metal::float2(0.5)) / size;
    metal::float2 h1_ = (((base + metal::float2(1.0)) + (w3_ / g1_)) + metal::float2(0.5)) / size;
    metal::float4 _e84 = t.sample(sampR, h0_, layer, metal::level(0.0));
    metal::float4 _e90 = t.sample(sampR, metal::float2(h1_.x, h0_.y), layer, metal::level(0.0));
    metal::float4 _e98 = t.sample(sampR, metal::float2(h0_.x, h1_.y), layer, metal::level(0.0));
    metal::float4 _e101 = t.sample(sampR, h1_, layer, metal::level(0.0));
    return metal::mix(metal::mix(_e84, _e90, g1_.x), metal::mix(_e98, _e101, g1_.x), g1_.y);
}

#if OCEAN_SHARED_CUBIC
// Both slope textures have identical dimensions, coordinates and reconstruction.
// Keep cubicWave unchanged for vertex displacement and the comparison path.
struct CubicStencil { metal::float2 h0, h1, weight; };
CubicStencil cubicStencil(metal::float2 uv_2, metal::float2 size) {
    metal::float2 p_1 = (uv_2 * size) - metal::float2(0.5);
    metal::float2 base = metal::floor(p_1);
    metal::float2 f_1 = metal::fract(p_1);
    metal::float2 w0_ = (((metal::float2(1.0) - f_1) * (metal::float2(1.0) - f_1)) * (metal::float2(1.0) - f_1)) / metal::float2(6.0);
    metal::float2 w1_ = (((((3.0 * f_1) * f_1) * f_1) - ((6.0 * f_1) * f_1)) + metal::float2(4.0)) / metal::float2(6.0);
    metal::float2 w2_ = ((((((-3.0 * f_1) * f_1) * f_1) + ((3.0 * f_1) * f_1)) + (3.0 * f_1)) + metal::float2(1.0)) / metal::float2(6.0);
    metal::float2 w3_ = ((f_1 * f_1) * f_1) / metal::float2(6.0);
    metal::float2 g0_ = w0_ + w1_;
    metal::float2 g1_ = w2_ + w3_;
    metal::float2 h0_ = (((base - metal::float2(1.0)) + (w1_ / g0_)) + metal::float2(0.5)) / size;
    metal::float2 h1_ = (((base + metal::float2(1.0)) + (w3_ / g1_)) + metal::float2(0.5)) / size;
    return {h0_, h1_, g1_};
}
metal::float4 applyCubic(metal::texture2d_array<float, metal::access::sample> t,
                        CubicStencil stencil, uint layer, metal::sampler sampR) {
    const auto h0_ = stencil.h0, h1_ = stencil.h1, g1_ = stencil.weight;
    metal::float4 _e84 = t.sample(sampR, h0_, layer, metal::level(0.0));
    metal::float4 _e90 = t.sample(sampR, metal::float2(h1_.x, h0_.y), layer, metal::level(0.0));
    metal::float4 _e98 = t.sample(sampR, metal::float2(h0_.x, h1_.y), layer, metal::level(0.0));
    metal::float4 _e101 = t.sample(sampR, h1_, layer, metal::level(0.0));
    return metal::mix(metal::mix(_e84, _e90, g1_.x), metal::mix(_e98, _e101, g1_.x), g1_.y);
}
#endif

float fresnelWater(
    float c_5
) {
    float x_1 = 1.0 - metal::clamp(c_5, 0.0, 1.0);
    float x2_ = x_1 * x_1;
    return 0.02 + (((0.98 * x2_) * x2_) * x_1);
}

float lambdaSmith(
    metal::float3 w,
    metal::float3 cov_1
) {
    float xz2_ = metal::max(metal::dot(w.xz, w.xz), 0.00000001);
    float il = metal::rsqrt(xz2_);
    metal::float2 az = w.xz * il;
    float sig2_ = (((az.x * az.x) * cov_1.x) + ((az.y * az.y) * cov_1.y)) + (((2.0 * az.x) * az.y) * cov_1.z);
    float cotT = w.y * il;
    float a_2 = metal::max(cotT, 0.001) / metal::sqrt(2.0 * metal::max(sig2_, 0.0000001));
    if (a_2 >= 1.6) {
        return 0.0;
    }
    return ((1.0 - (1.259 * a_2)) + ((0.396 * a_2) * a_2)) / ((3.535 * a_2) + ((2.181 * a_2) * a_2));
}

float foamPattern(
    metal::float2 xz,
    float t_1,
    metal::texture2d<float, metal::access::sample> foamTex,
    metal::sampler sampR
) {
    metal::float4 _e11 = foamTex.sample(sampR, (xz * 0.23) + (metal::float2(0.013, 0.0) * t_1));
    float a_3 = _e11.x;
    metal::float4 _e21 = foamTex.sample(sampR, (xz * 0.71) + metal::float2(0.37, 0.71));
    float b_2 = _e21.y;
    return (a_3 * 0.78) + (b_2 * 0.22);
}
#if OCEAN_STABLE_TIME
float foamPatternPhase(
    metal::float2 xz,
    float t_1,
    metal::texture2d<float, metal::access::sample> foamTex,
    metal::sampler sampR
) {
    metal::float4 _e11 = foamTex.sample(sampR, (xz * 0.23) + (metal::float2(t_1, 0.0)));
    float a_3 = _e11.x;
    metal::float4 _e21 = foamTex.sample(sampR, (xz * 0.71) + metal::float2(0.37, 0.71));
    float b_2 = _e21.y;
    return (a_3 * 0.78) + (b_2 * 0.22);
}
#endif

uint naga_f2u32(float value) {
    return static_cast<uint>(metal::clamp(value, 0.0, 4294967000.0));
}


struct vsInput {
};
struct vsOutput {
    metal::float4 pos [[position]];
    metal::float3 rel [[user(loc0), center_perspective]];
    metal::float2 xz [[user(loc1), center_perspective]];
    float height [[user(loc2), center_perspective]];
};
vertex vsOutput vs(
  uint vi [[vertex_id]]
, constant Frame& F [[buffer(0)]]
, metal::texture2d_array<float, metal::access::sample> dispTex [[texture(4)]]
, metal::sampler sampR [[sampler(9)]]
#if OCEAN_PHYSICAL_GUARD
, const device metal::float4* displacementBounds [[buffer(13)]]
#endif
) {
    float sx = {};
    float sy = {};
    bool local = {};
    metal::float3 disp = metal::float3(0.0);
    uint c = 0u;
    metal::float4 wave = {};
    bool local_1 = {};
    VSOut o = {};
    float _e4 = F.lodP.x;
    uint columns = naga_f2u32(_e4);
    float _e9 = F.lodP.y;
    uint rows = naga_f2u32(_e9);
    metal::float2 grid = metal::float2(static_cast<float>(vi % (columns + 1u)) / static_cast<float>(columns), static_cast<float>(vi / (columns + 1u)) / static_cast<float>(rows));
    float _e27 = F.camFwd.y;
    float _e32 = F.camUp.y;
    float horizon = -(_e27) / _e32;
    if (grid.x < 0.04) {
        sx = metal::mix(-3.0, -1.15, grid.x / 0.04);
    } else {
        if (grid.x > 0.96) {
            sx = metal::mix(1.15, 3.0, (grid.x - 0.96) / 0.04);
        } else {
            sx = metal::mix(-1.15, 1.15, (grid.x - 0.04) / 0.92);
        }
    }
    if (grid.y < 0.15) {
        sy = metal::mix(-4.0, -1.15, grid.y / 0.15);
    } else {
        sy = metal::mix(-1.15, horizon - 0.00008, (grid.y - 0.15) / 0.85);
    }
    float _e82 = sx;
    float _e83 = sy;
    metal::float2 ndc = metal::float2(_e82, _e83);
    metal::float4 _e87 = F.camFwd;
    metal::float4 _e92 = F.camRight;
    metal::float4 _e99 = F.camUp;
    metal::float3 ray = (_e87.xyz + (ndc.x * _e92.xyz)) + (ndc.y * _e99.xyz);
    float _e106 = F.camPos.y;
    float t_2 = metal::min(160000.0, _e106 / metal::max(-(ray.y), 0.00001));
    metal::float4 _e116 = F.camPos;
    metal::float2 xz_1 = _e116.xz + (ray.xz * t_2);
    if (grid.y<0.15) {
        // A projected mean-plane grid starts in front of the camera. Large
        // chop can pull that boundary through the near plane and open a hole.
        // Spend the existing guard rows on a patch extending behind the eye.
        metal::float3 edgeRay=F.camFwd.xyz+sx*F.camRight.xyz-1.15*F.camUp.xyz;
        metal::float2 edge=F.camPos.xz+edgeRay.xz*(F.camPos.y/(-edgeRay.y));
        metal::float2 behind=F.camPos.xz+metal::float2(sx*16.0,32.0);
        xz_1=metal::mix(behind,edge,grid.y/0.15);
    }
#if OCEAN_PHYSICAL_GUARD
    float worldGuard = 0.0;
    if (F.screen.x*2.0 < F.screen.y) {
        metal::float3 bound = displacementBounds[0].xyz;
        float depthBound = metal::dot(metal::abs(F.camFwd.xyz),bound);
        worldGuard = bound.x+3.0*F.camRight.x*depthBound;
        float band = metal::clamp((metal::abs(sx)-1.15)/1.85,0.0,1.0);
        xz_1.x += metal::copysign(worldGuard*band,sx);
    }
#endif
    if (!((grid.x < 0.04))) {
        local = grid.x > 0.96;
    } else {
        local = true;
    }
    bool _e131 = local;
    float dx = _e131 ? 46.25 : 2.5;
    float dy = (grid.y < 0.15) ? 57.0 : ((horizon + 1.15) / 0.85);
    metal::float4 _e147 = F.camRight;
    float spacingX = ((t_2 * dx) * metal::length(_e147.xyz)) / static_cast<float>(columns);
#if OCEAN_PHYSICAL_GUARD
    if (worldGuard>0.0 && metal::abs(sx)>1.15) {
        spacingX += (worldGuard*25.0)/static_cast<float>(columns);
    }
#endif
    float _e156 = F.camUp.y;
    float spacingY = (t_2 * metal::abs((dy * _e156) / metal::max(-(ray.y), 0.00001))) / static_cast<float>(rows);
    float spacing = metal::max(spacingX, metal::min(spacingY, 3000.0));
    if (grid.y<0.15) spacing=metal::max(96.0/float(columns),40.0/(float(rows)*0.15));
    bool loop_init = true;
    while(true) {
        if (!loop_init) {
            uint _e236 = c;
            c = _e236 + 1u;
        }
        loop_init = false;
        uint _e175 = c;
        if (_e175 < 6u) {
        } else {
            break;
        }
        {
            uint _e182 = c;
            uint _e186 = c;
            float _e190 = F.cascInvL.inner[_e182 >> 2u][_e186 & 3u];
            float lod = metal::log2(metal::max((spacing * TEX_N) * _e190, 1.0));
            if (lod < 8.0) {
                uint _e199 = c;
                uint _e203 = c;
                float _e207 = F.cascInvL.inner[_e199 >> 2u][_e203 & 3u];
                metal::float2 uv_3 = xz_1 * _e207;
                uint _e211 = c;
                metal::float4 _e212 = dispTex.sample(sampR, uv_3, _e211, metal::level(lod));
                wave = _e212;
                uint _e214 = c;
                if (_e214 < 2u) {
                    local_1 = lod < 1.0;
                } else {
                    local_1 = false;
                }
                bool _e222 = local_1;
                if (_e222) {
                    uint _e224 = c;
                    metal::float4 _e225 = cubicWave(dispTex, uv_3, _e224, sampR);
                    metal::float4 _e226 = wave;
                    wave = metal::mix(_e225, _e226, metal::smoothstep(0.0, 1.0, lod));
                }
                metal::float3 _e231 = disp;
                metal::float4 _e232 = wave;
                disp = _e231 + _e232.xyz;
            }
        }
    }
    float _e242 = disp.x;
    float _e245 = disp.y;
    float _e248 = disp.z;
    metal::float4 _e253 = F.camPos;
    o.rel = metal::float3(xz_1.x + _e242, _e245, xz_1.y + _e248) - _e253.xyz;
    metal::float4x4 _e259 = F.viewProj;
    metal::float3 _e261 = o.rel;
    o.pos = _e259 * metal::float4(_e261, 1.0);
    o.xz = xz_1;
    float _e268 = disp.y;
    o.height = _e268;
    VSOut _e269 = o;
    const auto _tmp = _e269;
    return vsOutput { _tmp.pos, _tmp.rel, _tmp.xz, _tmp.height };
}


struct fsInput {
    metal::float3 rel [[user(loc0), center_perspective]];
    metal::float2 xz_1 [[user(loc1), center_perspective]];
    float height [[user(loc2), center_perspective]];
};
struct fsOutput {
    metal::float4 member_1 [[color(0)]];
};
fragment fsOutput fs(
  const device metal::float4* water [[buffer(13)]]
,  fsInput varyings_1 [[stage_in]]
, metal::float4 pos [[position]]
, constant Frame& F [[buffer(0)]]
, metal::texture2d<float, metal::access::sample> transLUT [[texture(1)]]
, metal::texture2d<float, metal::access::sample> skyLUT [[texture(2)]]
, metal::sampler sampC [[sampler(3)]]
, metal::texture2d_array<float, metal::access::sample> dispTex [[texture(4)]]
, metal::texture2d_array<float, metal::access::sample> derivTex [[texture(5)]]
, metal::texture2d_array<float, metal::access::sample> momTex [[texture(6)]]
, metal::texture2d<float, metal::access::sample> foamTex [[texture(7)]]
, metal::texturecube<float, metal::access::sample> envCube [[texture(8)]]
, metal::sampler sampR [[sampler(9)]]
, metal::texture2d_array<float, metal::access::sample> foamWorld [[texture(10)]]
, device type_11 const& sunVis [[buffer(11)]]
, metal::texture2d<float,metal::access::read> sharedLighting [[texture(12)]]
) {
#if OCEAN_COVERAGE
    return fsOutput { metal::float4(1.0) };
#endif
    const VSOut in = { pos, varyings_1.rel, varyings_1.xz_1, varyings_1.height };
    bool local_2 = {};
    metal::float2 s = metal::float2(0.0);
    float jxx = 0.0;
    float jzz = 0.0;
    float jxz = 0.0;
    metal::float3 cov = metal::float3(0.0);
    uint c_1 = 0u;
    metal::float4 dv = {};
    metal::float4 mv = {};
    metal::float4 av = {};
    metal::float3 R = {};
    metal::float3 body = {};
    float cover = {};
    float foamMask = {};
    bool local_3 = {};
    bool local_4 = {};
    bool local_5 = {};
    bool local_6 = {};
    bool local_7 = {};
    metal::float3 col = {};
    float _e4 = F.post.w;
    if (_e4 > 7.5) {
        float _e12 = F.post.w;
        local_2 = _e12 < 8.5;
    } else {
        local_2 = false;
    }
    bool _e16 = local_2;
    if (_e16) {
        return fsOutput { metal::float4(0.01, 0.02, 0.03, 1.0) };
    }
    metal::float2 xz_2 = in.xz;
    float _e28 = F.screen.z;
    float _e39 = F.screen.w;
    metal::float2 ndc_1 = metal::float2(((in.pos.x * _e28) * 2.0) - 1.0, 1.0 - ((in.pos.y * _e39) * 2.0));
    metal::float4 _e48 = F.camFwd;
    metal::float4 _e53 = F.camRight;
    metal::float4 _e60 = F.camUp;
    metal::float3 ray_1 = (_e48.xyz + (ndc_1.x * _e53.xyz)) + (ndc_1.y * _e60.xyz);
    float rayY = metal::min(ray_1.y, -0.005);
    float rayT = metal::length(in.rel) / metal::length(ray_1);
    metal::float4 _e73 = F.camRight;
    float _e79 = F.camRight.y;
    float _e88 = F.screen.z;
    metal::float2 oceanDx = (rayT * (_e73.xz - ((ray_1.xz * _e79) / metal::float2(rayY)))) * (2.0 * _e88);
    metal::float4 _e94 = F.camUp;
    float _e100 = F.camUp.y;
    float _e109 = F.screen.w;
    metal::float2 oceanDy = (rayT * (_e94.xz - ((ray_1.xz * _e100) / metal::float2(rayY)))) * (2.0 * _e109);
    // The mean-plane differential diverges for raised crests looking upward.
    // Use the actual rasterized surface footprint there to retain wave detail.
    float raised=1.0-metal::smoothstep(-0.04,-0.01,ray_1.y);
    oceanDx=metal::mix(metal::dfdx(xz_2),oceanDx,raised);
    oceanDy=metal::mix(metal::dfdy(xz_2),oceanDy,raised);
    metal::float4 _e132 = F.windP.inner[0];
    float _e137 = F.camPos.w;
#if OCEAN_STABLE_TIME
    metal::float4 _e142 = foamTex.sample(sampR,(xz_2*0.011)+F.windP.inner[1].xy);
#else
    metal::float4 _e142 = foamTex.sample(sampR, (xz_2 * 0.011) + (_e132.xy * (_e137 * 0.0004)));
#endif
    float gustN = _e142.z;
    float gust = metal::mix(0.35, 1.2, metal::smoothstep(0.3, 0.72, gustN));
    bool loop_init_1 = true;
    while(true) {
        if (!loop_init_1) {
            uint _e300 = c_1;
            c_1 = _e300 + 1u;
        }
        loop_init_1 = false;
        uint _e152 = c_1;
        if (_e152 < 6u) {
        } else {
            break;
        }
        {
            uint _e157 = c_1;
            uint _e161 = c_1;
            float _e165 = F.cascInvL.inner[_e157 >> 2u][_e161 & 3u];
            metal::float2 uv_4 = xz_2 * _e165;
            uint _e167 = c_1;
            uint _e173 = c_1;
            float gk = metal::mix(1.0, gust, (_e173 >= 3u) ? ((_e167 >= 4u) ? 1.0 : 0.5) : 0.0);
            uint _e182 = c_1;
            uint _e186 = c_1;
            float _e190 = F.cascInvL.inner[_e182 >> 2u][_e186 & 3u];
            metal::float2 dx_1 = oceanDx * _e190;
            uint _e194 = c_1;
            uint _e198 = c_1;
            float _e202 = F.cascInvL.inner[_e194 >> 2u][_e198 & 3u];
            metal::float2 dy_1 = oceanDy * _e202;
            const float footprint = metal::max(metal::length(dx_1),metal::length(dy_1))*TEX_N;
            // At zero blend, gradient reads are unused; at full blend, all
            // twelve cubic taps are unused. Preserve the exact transition.
            if (c_1 < 2u && footprint <= 1.0f) {
#if OCEAN_SHARED_CUBIC
                const auto stencil = cubicStencil(uv_4,metal::float2(derivTex.get_width(0),derivTex.get_height(0)));
                dv = applyCubic(derivTex,stencil,c_1,sampR);
                mv = applyCubic(momTex,stencil,c_1,sampR);
#else
                dv = cubicWave(derivTex,uv_4,c_1,sampR);
                mv = cubicWave(momTex,uv_4,c_1,sampR);
#endif
#if !OCEAN_PACKED_JACOBIAN
                av = cubicWave(dispTex,uv_4,c_1,sampR);
#endif
            } else {
                dv = derivTex.sample(sampR,uv_4,c_1,metal::gradient2d(dx_1,dy_1));
                mv = momTex.sample(sampR,uv_4,c_1,metal::gradient2d(dx_1,dy_1));
#if !OCEAN_PACKED_JACOBIAN
                av = dispTex.sample(sampR,uv_4,c_1,metal::gradient2d(dx_1,dy_1));
#endif
                if (c_1 < 2u && footprint < 2.0f) {
                    const float blend = metal::smoothstep(1.0f,2.0f,footprint);
#if OCEAN_SHARED_CUBIC
                    const auto stencil = cubicStencil(uv_4,metal::float2(derivTex.get_width(0),derivTex.get_height(0)));
                    dv = metal::mix(applyCubic(derivTex,stencil,c_1,sampR),dv,blend);
                    mv = metal::mix(applyCubic(momTex,stencil,c_1,sampR),mv,blend);
#else
                    dv = metal::mix(cubicWave(derivTex,uv_4,c_1,sampR),dv,blend);
                    mv = metal::mix(cubicWave(momTex,uv_4,c_1,sampR),mv,blend);
#endif
#if !OCEAN_PACKED_JACOBIAN
                    av = metal::mix(cubicWave(dispTex,uv_4,c_1,sampR),av,blend);
#endif
                }
            }
#if OCEAN_PACKED_JACOBIAN
            // The moment texture's fourth channel duplicates displacement.w
            // with exactly the same half precision, mip reduction and filtering.
            const float packedJxz = mv.w*gk;
#endif
            metal::float4 _e245 = dv;
            dv = _e245 * gk;
            metal::float4 _e247 = mv;
            mv = _e247 * (gk * gk);
#if !OCEAN_PACKED_JACOBIAN
            metal::float4 _e250 = av;
            av = _e250 * gk;
#endif
            metal::float2 _e252 = s;
            metal::float4 _e253 = dv;
            s = _e252 + _e253.xy;
            float _e256 = jxx;
            float _e258 = dv.z;
            jxx = _e256 + _e258;
            float _e260 = jzz;
            float _e262 = dv.w;
            jzz = _e260 + _e262;
            float _e264 = jxz;
#if OCEAN_PACKED_JACOBIAN
            float _e266 = packedJxz;
#else
            float _e266 = av.w;
#endif
            jxz = _e264 + _e266;
            metal::float3 _e268 = cov;
            float _e270 = mv.x;
            float _e272 = dv.x;
            float _e274 = dv.x;
            float _e280 = mv.y;
            float _e282 = dv.y;
            float _e284 = dv.y;
            float _e290 = mv.z;
            float _e292 = dv.x;
            float _e294 = dv.y;
            cov = _e268 + metal::float3(metal::max(_e270 - (_e272 * _e274), 0.0), metal::max(_e280 - (_e282 * _e284), 0.0), _e290 - (_e292 * _e294));
        }
    }
    float dist = metal::length(in.rel);
    metal::float3 V = -(in.rel) / metal::float3(dist);
    metal::float4 _e310 = F.sunDir;
    metal::float3 Ld = F.celestial.w>0.5 ? F.lightDir.xyz : _e310.xyz;
    float _e315 = F.waterCol.w;
    float unres = _e315 + (0.0035 * metal::smoothstep(30.0, 500.0, dist));
    float _e323 = cov.x;
    cov.x = _e323 + unres;
    float _e326 = cov.y;
    cov.y = _e326 + unres;
    float _e328 = jxx;
    float jx = metal::max(1.0 + _e328, 0.15);
    float _e333 = jzz;
    float jz = metal::max(1.0 + _e333, 0.15);
    float _e339 = s.x;
    float _e342 = s.y;
    metal::float2 sl_1 = metal::float2(_e339 / jx, _e342 / jz);
    metal::float3 nrm = metal::normalize(metal::float3(-(sl_1.x), 1.0, -(sl_1.y)));
    float _e352 = jxx;
    float _e355 = jzz;
    float _e359 = jxz;
    float _e360 = jxz;
    float J = ((1.0 + _e352) * (1.0 + _e355)) - (_e359 * _e360);
    metal::float3 _e363 = sunIlluminance(F, transLUT, sampC);
    float _e366 = sunVis.inner[0];
    metal::float3 sunE = _e363 * _e366;
#if OCEAN_PER_PIXEL_LIGHTING
    metal::float4 _e375 = envCube.sample(sampC, metal::float3(0.0, 1.0, 0.0), metal::level(ENV_MAXMIP));
    metal::float3 skyUp = _e375.xyz;
    metal::float4 _e386 = envCube.sample(sampC, metal::float3(0.94, 0.34, 0.0), metal::level(6.0));
    metal::float4 _e395 = envCube.sample(sampC, metal::float3(-0.94, 0.34, 0.0), metal::level(6.0));
    metal::float4 _e405 = envCube.sample(sampC, metal::float3(0.0, 0.34, 0.94), metal::level(6.0));
    metal::float4 _e415 = envCube.sample(sampC, metal::float3(0.0, 0.34, -0.94), metal::level(6.0));
    metal::float3 skyHemi = (skyUp * 0.4) + (0.15 * (((_e386.xyz + _e395.xyz) + _e405.xyz) + _e415.xyz));
#else
    const metal::float3 skyUp = sharedLighting.read(metal::uint2(0,0)).xyz;
    const metal::float4 _e386 = sharedLighting.read(metal::uint2(1,0));
    const metal::float4 _e395 = sharedLighting.read(metal::uint2(2,0));
    const metal::float4 _e405 = sharedLighting.read(metal::uint2(3,0));
    const metal::float4 _e415 = sharedLighting.read(metal::uint2(4,0));
    const metal::float3 skyHemi = (skyUp*0.4)+(0.15*(((_e386.xyz+_e395.xyz)+_e405.xyz)+_e415.xyz));
#endif
    metal::float4 _e424 = envCube.sample(sampC, nrm, metal::level(6.0));
    metal::float3 skyN = _e424.xyz;
    metal::float3 Hv = metal::normalize(V + Ld);
    metal::float2 hs = -(Hv.xz) / metal::float2(metal::max(Hv.y, 0.001));
    metal::float2 dsl = hs - sl_1;
    float _e437 = cov.x;
    float _e439 = cov.y;
    float _e442 = cov.z;
    float _e444 = cov.z;
    float det = metal::max((_e437 * _e439) - (_e442 * _e444), 0.0000000001);
    float _e453 = cov.y;
    float _e459 = cov.x;
    float _e468 = cov.z;
    float e = ((((dsl.x * dsl.x) * _e453) + ((dsl.y * dsl.y) * _e459)) - (((2.0 * dsl.x) * dsl.y) * _e468)) / det;
    float pdf = metal::exp(-0.5 * e) / (6.2831855 * metal::sqrt(det));
    float hy2_ = Hv.y * Hv.y;
    float Dm = pdf / metal::max(hy2_ * hy2_, 0.000001);
    metal::float3 _e486 = cov;
    float _e487 = lambdaSmith(V, _e486);
    metal::float3 _e490 = cov;
    float _e491 = lambdaSmith(Ld, _e490);
    float G = 1.0 / ((1.0 + _e487) + _e491);
    float _e496 = fresnelWater(metal::dot(V, Hv));
    metal::float3 spec = (sunE * (((_e496 * Dm) * G) / (4.0 * metal::max(V.y, 0.02)))) * (F.celestial.w>0.5 ? 1.0 : metal::step(0.0, Ld.y));
    float _e511 = cov.x;
    float _e513 = cov.y;
    float sig = metal::sqrt(metal::max(_e511 + _e513, 0.000001) * 0.5);
    metal::float3 vh = metal::normalize(metal::float3(V.x, 0.0, V.z) + metal::float3(0.00001, 0.0, 0.0));
    float _e534 = cov.x;
    float _e540 = cov.y;
    float _e549 = cov.z;
    float sigV = metal::sqrt(metal::max((((vh.x * vh.x) * _e534) + ((vh.z * vh.z) * _e540)) + (((2.0 * vh.x) * vh.z) * _e549), 0.000001));
    float aV = (metal::max(V.y, 0.001) / metal::max(metal::sqrt(1.0 - (V.y * V.y)), 0.001)) / (1.4142 * sigV);
    float tilt = (0.32 * sigV) * (1.0 - metal::smoothstep(0.0, 2.5, aV));
    metal::float3 nV = metal::normalize(nrm + (vh * tilt));
    R = metal::reflect(-(V), nV);
    float _e586 = R.y;
    float _e591 = R.y;
    R.y = (metal::abs(_e586) * 0.4) + (metal::max(_e591, 0.0) * 0.6);
    metal::float3 _e597 = R;
    R = metal::normalize(_e597);
    float envLod = metal::clamp(metal::log2(metal::max((2.0 * sig) * ENV_TEXELS_PER_RAD, 1.0)), 0.0, ENV_MAXMIP);
    metal::float3 _e611 = R;
    metal::float4 _e612 = envCube.sample(sampC, _e611, metal::level(envLod));
    metal::float3 refl = _e612.xyz;
    float NdV = metal::max(metal::dot(nV, V), 0.0);
    metal::float3 nF = metal::normalize(metal::mix(nrm, metal::float3(0.0, 1.0, 0.0), 0.45*metal::smoothstep(-0.05,0.0,V.y)));
    float _e627 = fresnelWater(metal::abs(metal::dot(nF, V)));
    metal::float3 ambient = (skyUp * 1.3) + (skyN * 0.5);
    float NdL = metal::max(metal::dot(nrm, Ld), 0.0);
    metal::float4 _e638 = F.waterCol;
    body = _e638.xyz * ((skyHemi * 1.6) + ((sunE * metal::max(Ld.y, 0.0)) * 0.8));
    float crest = metal::clamp((in.height - 0.05) / 0.9, 0.0, 1.0);
    float toSun = metal::max(metal::dot(Ld, -(V)), 0.0);
    float thin = metal::pow(metal::clamp(0.5 - (0.5 * metal::dot(Ld, nrm)), 0.0, 1.0), 3.0);
    float _e676 = F.sssCol.w;
    float k1_ = ((((_e676 * crest) * crest) * metal::pow(toSun, 4.0)) * thin) * metal::exp(-(dist) / 600.0);
    metal::float3 _e688 = body;
    metal::float4 _e691 = F.sssCol;
    body = _e688 + ((_e691.xyz * sunE) * k1_);
    metal::float4 _e698 = F.camPos;
    metal::float2 dc = metal::abs(xz_2 - _e698.xz);
    float cheb = metal::max(dc.x, dc.y);
    float _e708 = F.lodP.z;
    float _e714 = F.lodP.z;
    float w0_1 = 1.0 - metal::smoothstep(0.3 * _e708, 0.45 * _e714, cheb);
    float _e723 = F.lodP.w;
    float _e729 = F.lodP.w;
    float w1_1 = 1.0 - metal::smoothstep(0.3 * _e723, 0.45 * _e729, cheb);
    float _e740 = F.lodP.z;
    metal::float4 fw0_ = foamWorld.sample(sampR, xz_2 / metal::float2(_e740), 0u);
    float _e750 = F.lodP.w;
    metal::float4 fw1_ = foamWorld.sample(sampR, xz_2 / metal::float2(_e750), 1u);
    metal::float4 fwl = metal::mix(fw1_, fw0_, w0_1) * w1_1;
    float _e760 = F.foamP.x;
    float _e765 = F.foamP.y;
    float fresh = metal::clamp((_e760 - J) * _e765, 0.0, 1.0);
    float _e784 = F.foamP.z;
    cover = metal::clamp((metal::max(fwl.x, fresh * (1.0 - (w1_1 * 0.7))) + (fwl.y * 0.6)) * _e784, 0.0, 1.5);
    metal::float4 _e793 = F.windP.inner[0];
    metal::float2 wd = _e793.xy;
    metal::float2 ws = metal::float2(metal::dot(xz_2, wd), metal::dot(xz_2, metal::float2(-(wd.y), wd.x)));
    metal::float4 _e808 = foamTex.sample(sampR, ws * metal::float2(0.035, 0.11));
    float streak = _e808.w;
    float freshK = metal::clamp((fwl.y * 2.0) + fresh, 0.0, 1.0);
    float _e817 = cover;
    cover = _e817 * metal::mix(metal::smoothstep(0.25, 0.75, streak) * 1.5, 1.0, freshK);
    float _e829 = F.camPos.w;
#if OCEAN_STABLE_TIME
    float _e830 = foamPatternPhase(xz_2,F.windP.inner[1].z,foamTex,sampR);
#else
    float _e830 = foamPattern(xz_2, _e829, foamTex, sampR);
#endif
    float _e831 = metal::fwidth(_e830);
    float fw = _e831 + 0.03;
    float _e834 = cover;
    float soft = 0.04 + (0.14 * (1.0 - metal::clamp(_e834, 0.0, 1.0)));
    float _e844 = cover;
    float _e849 = cover;
    float fm = metal::smoothstep(((1.0 - _e844) - fw) - soft, ((1.0 - _e849) + fw) + soft, _e830);
    float _e855 = cover;
    float _e863 = cover;
    foamMask = metal::clamp(fm * metal::smoothstep(0.0, 0.5, _e855), 0.0, 1.0) * (0.68 + (0.32 * metal::smoothstep(0.3, 0.9, _e863)));
    float _e873 = foamMask;
    foamMask = metal::max(_e873, (metal::smoothstep(0.35, 0.9, fwl.y) * metal::smoothstep(0.25, 0.6, _e830 + 0.25)) * 0.95);
    metal::float3 _e887 = body;
    metal::float4 _e890 = F.sssCol;
    float _e898 = cover;
    body = _e887 + ((_e890.xyz * ((sunE * 0.05) + (ambient * 0.35))) * metal::clamp(_e898, 0.0, 1.0));
    metal::float3 _e904 = body;
    body = _e904 + (((metal::float3(0.1, 0.32, 0.3) * skyUp) * fwl.y) * 0.35);
    metal::float4 _e923 = foamTex.sample(sampR, (xz_2 * 1.9) + metal::float2(0.21, 0.53));
    float bub = _e923.y;
    metal::float3 foamAlb = metal::float3(0.82, 0.87, 0.92) * (0.78 + (0.3 * bub));
    metal::float3 foamAmb = (skyHemi * 1.0) + (skyN * 0.3);
    metal::float3 foamAmbN = metal::mix(foamAmb, metal::float3(metal::dot(foamAmb, metal::float3(0.2126, 0.7152, 0.0722))), 0.85);
    metal::float3 foamLit = foamAlb * ((((sunE * metal::max(metal::dot(nrm, Ld), 0.0)) * 0.318) * 0.5) + (foamAmbN * 1.55));
    if (F.celestial.w>0.5 && F.celestial.z>0.001) {
        metal::float3 key=metal::normalize(metal::float3(-0.6,0.32,-0.73));
        float face=metal::max(0.0,metal::dot(nrm,key));
        // Deep water absorbs broad diffuse fill. Keep the directional BRDF
        // and reflected sky intact so moving wave faces catch silver light.
        body*=1.0-0.65*F.celestial.z;
        body+=metal::float3(0.0030,0.0045,0.0065)*(0.04+2.0*face*face)*F.celestial.z;
        // Foam scatters the same fill as the water, with neutral diffuse color.
        // Its normal response preserves crest shape instead of a flat gray coat.
        foamLit+=foamAlb*metal::float3(0.0045,0.0055,0.007)*(0.18+1.2*face)*F.celestial.z;
    }
    // Foam sits on the air side, not on the underside of an overtaking crest.
    foamMask*=metal::smoothstep(-0.1,0.15,metal::dot(nrm,V));
    if (F.post.w>8.5 && F.post.w<9.5) {
        // Native geometry/foam mask used by the overtaking-wave regression.
        return fsOutput {metal::float4(metal::step(V.y,0.0),foamMask,water[0].z,1.0)};
    }
    float _e962 = F.post.w;
    if (_e962 > 0.5) {
        float _e968 = F.post.w;
        if (_e968 < 1.5) {
            float _e971 = cover;
            return fsOutput { metal::float4(_e971, metal::clamp(J * 0.5, 0.0, 1.0), w0_1 * 0.3, 1.0) * 0.2 };
        }
        float _e986 = F.post.w;
        if (_e986 > 2.5) {
            float _e994 = F.post.w;
            local_3 = _e994 < 3.5;
        } else {
            local_3 = false;
        }
        bool _e998 = local_3;
        if (_e998) {
            return fsOutput { metal::float4(refl, 1.0) };
        }
        float _e1004 = F.post.w;
        if (_e1004 > 3.5) {
            float _e1012 = F.post.w;
            local_4 = _e1012 < 4.5;
        } else {
            local_4 = false;
        }
        bool _e1016 = local_4;
        if (_e1016) {
            return fsOutput { metal::float4(metal::float3(_e627), 1.0) * 0.5 };
        }
        float _e1025 = F.post.w;
        if (_e1025 > 4.5) {
            float _e1033 = F.post.w;
            local_5 = _e1033 < 5.5;
        } else {
            local_5 = false;
        }
        bool _e1037 = local_5;
        if (_e1037) {
            metal::float3 _e1038 = body;
            return fsOutput { metal::float4(_e1038 * (1.0 - _e627), 1.0) };
        }
        float _e1047 = F.post.w;
        if (_e1047 > 5.5) {
            float _e1055 = F.post.w;
            local_6 = _e1055 < 6.5;
        } else {
            local_6 = false;
        }
        bool _e1059 = local_6;
        if (_e1059) {
            return fsOutput { metal::float4(foamLit, 1.0) };
        }
        float _e1065 = F.post.w;
        if (_e1065 > 6.5) {
            float _e1073 = F.post.w;
            local_7 = _e1073 < 7.5;
        } else {
            local_7 = false;
        }
        bool _e1077 = local_7;
        if (_e1077) {
            return fsOutput { metal::float4(skyUp, 1.0) };
        }
        return fsOutput { metal::float4(fwl.x, fwl.y, fresh, 1.0) * 0.2 };
    }
    metal::float3 _e1086 = body;
    col = ((_e1086 * (1.0 - _e627)) + (refl * _e627)) + spec;
    metal::float3 _e1094 = col;
    float _e1095 = foamMask;
    col = metal::mix(_e1094, foamLit, _e1095 * 0.95);
    metal::float4 _e1101 = F.fogExt;
    float _e1106 = F.fogExt.w;
    metal::float3 T = metal::exp(-(metal::max(_e1101.xyz, metal::float3(_e1106))) * dist);
    metal::float3 hz = metal::normalize(metal::float3(-(V.x), 0.002, -(V.z)));
    metal::float3 _e1119 = skyAtmo(hz, F, skyLUT, sampC);
    metal::float3 _e1120 = col;
    col = (_e1120 * T) + (_e1119 * (metal::float3(1.0) - T));
    if (water[0].z>0.0) {
        float path=dist*water[0].z;
        metal::float3 waterT=metal::exp(-metal::float3(0.18,0.075,0.045)*path);
        metal::float3 volume=waterVolumeRadiance(F.celestial.z,-V.y,water[0].y);
        col=col*waterT+volume*(1.0-waterT);
    }
    metal::float3 _e1127 = col;
    return fsOutput { metal::float4(_e1127, 1.0) };
}

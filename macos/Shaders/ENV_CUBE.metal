// Native Metal shaders migrated from the original ocean equations using Naga.
// Edit this file for native rendering; no WGSL or JavaScript runs in the app.
// language: metal2.3
#include <metal_stdlib>
#include <simd/simd.h>

using metal::uint;

struct type_2 {
    metal::float4 inner[2];
};
struct NoiseShift { metal::float2 fraction; metal::uint2 origin; };
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
    NoiseShift cloudShift[14];
    metal::float4 cloudMotion;
    metal::float4 moonDir;
    metal::float4 celestial; // sun radius, moon radius, night factor, enabled
    metal::float4 lightDir; // dominant directional light and illuminance
    metal::float4 sunDiskDir; // apparent direction, angular radius
    metal::float4 starX;
    metal::float4 starY;
    metal::float4 starZ;
    metal::float4 cloudEvolution;
    metal::float4 weather; // severity, rain, mist, reserved
    metal::float4 nightFx; // aurora, seconds, meteor rate, bioluminescence

};
struct Medium {
    metal::float3 ext;
    metal::packed_float3 rayS;
    float mieS;
};
struct CloudHit {
    float t;
    char _pad1[4];
    metal::float2 q;
    float mu;
    char _pad3[12];
    metal::float3 up;
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
constant metal::float2x2 CLOUD_ROT = metal::float2x2(metal::float2(0.8, 0.6), metal::float2(-0.6, 0.8));
constant float ENV = 128.0;

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
    float R
) {
    float l = metal::length(ro);
    float b = metal::dot(ro, rd);
    float c_3 = (l - R) * (l + R);
    float d_1 = (b * b) - c_3;
    if (d_1 < 0.0) {
        return metal::float2(-1.0, -1.0);
    }
    float s_1 = metal::sqrt(d_1);
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
    float d_2 = metal::max(0.0, (-(r_1) * mu) + metal::sqrt(metal::max(disc, 0.0)));
    float dMin = RT - r_1;
    float dMax = _e3 + 1132.2544;
    float x = (d_2 - dMin) / (dMax - dMin);
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
    float d_3 = dMin_1 + (uv.x * (dMax_1 - dMin_1));
    if (d_3 > 0.0) {
        mu_1 = (((1132.2544 * 1132.2544) - (rho * rho)) - (d_3 * d_3)) / ((2.0 * r_4) * d_3);
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
    float c
) {
    return 0.059683103 * (1.0 + (c * c));
}

float phaseMie(
    float c_1,
    float g
) {
    float g2_ = g * g;
    return (0.119366206 * ((1.0 - g2_) * (1.0 + (c_1 * c_1)))) / ((2.0 + g2_) * metal::pow(metal::max((1.0 + g2_) - ((2.0 * g) * c_1), 0.0001), 1.5));
}

float phaseHG(
    float c_2,
    float g_1
) {
    float g2_1 = g_1 * g_1;
    return (1.0 - g2_1) / (12.566371 * metal::pow(metal::max((1.0 + g2_1) - ((2.0 * g_1) * c_2), 0.0001), 1.5));
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
    uint w = ((s_2 >> ((s_2 >> 28u) + 4u)) ^ s_2) * 277803737u;
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
    metal::int2 i_2 = naga_f2i32(metal::floor(p));
    metal::float2 f_1 = p - metal::floor(p);
    metal::float2 u_2 = ((f_1 * f_1) * f_1) * ((f_1 * ((f_1 * 6.0) - metal::float2(15.0))) + metal::float2(10.0));
    metal::float2 _e17 = hashGrad(i_2);
    float a_2 = metal::dot(_e17, f_1);
    metal::float2 _e23 = hashGrad(as_type<metal::int2>(as_type<metal::uint2>(i_2) + as_type<metal::uint2>(metal::int2(1, 0))));
    float b_1 = metal::dot(_e23, f_1 - metal::float2(1.0, 0.0));
    metal::float2 _e33 = hashGrad(as_type<metal::int2>(as_type<metal::uint2>(i_2) + as_type<metal::uint2>(metal::int2(0, 1))));
    float c_4 = metal::dot(_e33, f_1 - metal::float2(0.0, 1.0));
    metal::float2 _e43 = hashGrad(as_type<metal::int2>(as_type<metal::uint2>(i_2) + as_type<metal::uint2>(metal::int2(1, 1))));
    float d_4 = metal::dot(_e43, f_1 - metal::float2(1.0, 1.0));
    return metal::mix(metal::mix(a_2, b_1, u_2.x), metal::mix(c_4, d_4, u_2.x), u_2.y);
}

#if CLOUD_STABLE_TIME
float shiftedNoise(metal::float2 p, NoiseShift shift) {
    metal::float2 q = p+shift.fraction;
    metal::float2 whole = metal::floor(q);
    metal::int2 lattice = as_type<metal::int2>(shift.origin+as_type<metal::uint2>(naga_f2i32(whole)));
    metal::float2 f_1 = q-whole;
    metal::float2 u_2 = ((f_1 * f_1) * f_1) * ((f_1 * ((f_1 * 6.0) - metal::float2(15.0))) + metal::float2(10.0));
    metal::float2 _e17 = hashGrad(lattice);
    float a_2 = metal::dot(_e17, f_1);
    metal::float2 _e23 = hashGrad(as_type<metal::int2>(as_type<metal::uint2>(lattice) + as_type<metal::uint2>(metal::int2(1, 0))));
    float b_1 = metal::dot(_e23, f_1 - metal::float2(1.0, 0.0));
    metal::float2 _e33 = hashGrad(as_type<metal::int2>(as_type<metal::uint2>(lattice) + as_type<metal::uint2>(metal::int2(0, 1))));
    float c_4 = metal::dot(_e33, f_1 - metal::float2(0.0, 1.0));
    metal::float2 _e43 = hashGrad(as_type<metal::int2>(as_type<metal::uint2>(lattice) + as_type<metal::uint2>(metal::int2(1, 1))));
    float d_4 = metal::dot(_e43, f_1 - metal::float2(1.0, 1.0));
    return metal::mix(metal::mix(a_2, b_1, u_2.x), metal::mix(c_4, d_4, u_2.x), u_2.y);
}

#endif

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
    bool local_1 = {};
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
        local_1 = sl > 0.000001;
    } else {
        local_1 = false;
    }
    bool _e64 = local_1;
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
#include "AURORA.metalinc"
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

float cloudFbm(
    metal::float2 p_1,
    float fp,
    int oct,
    float billow
#if CLOUD_STABLE_TIME
, constant Frame& F, uint shiftStart
#endif
) {
    float s = 0.0;
    float a = 0.5;
    metal::float2 q = {};
    float f = 1.0;
    int i_1 = 0;
    float n = {};
    q = p_1;
    bool loop_init = true;
    while(true) {
        if (!loop_init) {
            int _e58 = i_1;
            i_1 = as_type<int>(as_type<uint>(_e58) + as_type<uint>(1));
        }
        loop_init = false;
        int _e13 = i_1;
        if (_e13 < oct) {
        } else {
            break;
        }
        {
            float _e15 = f;
            float w_1 = 1.0 - metal::smoothstep(0.08, 0.28, fp * _e15);
#if CLOUD_SKIP_ZERO
            // Keep the coordinate recurrence unchanged; omit only noise and
            // accumulation when the octave contributes exactly zero.
            if (w_1 != 0.0) {
#endif
            metal::float2 _e22 = q;
#if CLOUD_STABLE_TIME
            float _e23 = shiftedNoise(_e22,F.cloudShift[shiftStart+uint(i_1)]);
#else
            float _e23 = gnoise(_e22);
#endif
            n = _e23;
            int _e25 = i_1;
            if (_e25 >= 2) {
                float _e28 = n;
                float _e29 = n;
                n = metal::mix(_e28, (metal::abs(_e29) * 2.0) - 0.38, billow);
            }
            float _e36 = s;
            float _e37 = a;
            float _e38 = n;
            s = _e36 + ((_e37 * _e38) * w_1);
#if CLOUD_SKIP_ZERO
            }
#endif
            metal::float2 _e43 = q;
            q = ((CLOUD_ROT * _e43) * 2.03) + metal::float2(13.1, 7.7);
            float _e51 = f;
            f = _e51 * 2.03;
            float _e54 = a;
            a = _e54 * 0.5;
        }
    }
    float _e60 = s;
    return _e60;
}

float lowEdge(
    metal::float2 q_1,
    float fp_1,
    int oct_1,
    constant Frame& F
) {
    metal::float2 p_2 = {};
    float t = F.cloudP.w;
#if CLOUD_STABLE_TIME
    p_2 = q_1*0.38;
#else
    p_2 = (q_1 * 0.38) + metal::float2(t * 0.004, t * 0.0012);
#endif
    metal::float2 _e16 = p_2;
#if CLOUD_STABLE_TIME
    float _e23 = shiftedNoise((_e16 * 0.3) + metal::float2(1.7, 9.2),F.cloudShift[0]);
#else
    float _e23 = gnoise((_e16 * 0.3) + metal::float2(1.7, 9.2));
#endif
    metal::float2 _e24 = p_2;
#if CLOUD_STABLE_TIME
    float _e31 = shiftedNoise((_e24 * 0.3) + metal::float2(8.3, 2.8),F.cloudShift[0]);
#else
    float _e31 = gnoise((_e24 * 0.3) + metal::float2(8.3, 2.8));
#endif
    metal::float2 w_2 = metal::float2(_e23, _e31);
    metal::float2 _e33 = p_2;
    p_2 = _e33 + (w_2 * 1.4);
    metal::float2 _e37 = p_2;
#if CLOUD_STABLE_TIME
    float _e45 = cloudFbm(_e37 * metal::float2(1.0, 1.7), fp_1 * 0.65, oct_1, 0.35,F,1);
#else
    float _e45 = cloudFbm(_e37 * metal::float2(1.0, 1.7), fp_1 * 0.65, oct_1, 0.35);
#endif
    float base = (_e45 * 1.3) + 0.5;
    float _e56 = gnoise((q_1 * 0.05) + metal::float2(3.1, 1.3));
    float large = _e56 * 0.7;
    float _e63 = F.cloudP.y;
    return (base + large) - (1.0 - _e63);
}

float lowSoft(
    float fp_2
) {
    return 0.38 + (metal::min(fp_2 * 0.65, 1.0) * 0.3);
}

float lowDensity(
    metal::float2 q_2,
    float fp_3,
    int oct_2,
    constant Frame& F
) {
    float _e3 = lowEdge(q_2, fp_3, oct_2, F);
    float _e4 = lowSoft(fp_3);
    return metal::clamp(_e3 / _e4, 0.0, 1.0);
}

float highEdge(
    metal::float2 q_3,
    float fp_4,
    int oct_3,
    constant Frame& F
) {
    float t_1 = F.cloudP.w;
#if CLOUD_STABLE_TIME
    metal::float2 p_3 = CLOUD_ROT * (q_3 * metal::float2(0.09,0.2));
#else
    metal::float2 p_3 = (CLOUD_ROT * (q_3 * metal::float2(0.09, 0.2))) + metal::float2(t_1 * 0.0015, 0.0);
#endif
#if CLOUD_STABLE_TIME
    float _e21 = cloudFbm(p_3, fp_4 * 0.2, oct_3, 0.0,F,8);
#else
    float _e21 = cloudFbm(p_3, fp_4 * 0.2, oct_3, 0.0);
#endif
    float n_1 = (_e21 * 1.25) + 0.5;
    float _e32 = gnoise((q_3 * 0.012) + metal::float2(7.0, 3.0));
    float big = _e32 * 0.6;
    float _e39 = F.atmo.z;
    return (n_1 + big) - (1.0 - _e39);
}

float highSoft(
    float fp_5
) {
    return 0.85 + (metal::min(fp_5 * 0.2, 1.0) * 0.3);
}

float highDensity(
    metal::float2 q_4,
    float fp_6,
    int oct_4,
    constant Frame& F
) {
    float _e3 = highEdge(q_4, fp_6, oct_4, F);
    float _e4 = highSoft(fp_6);
    return metal::clamp(_e3 / _e4, 0.0, 1.0);
}

CloudHit hitLayer(
    metal::float3 dir_2,
    float hc,
    constant Frame& F
) {
    CloudHit h_1 = {};
    float _e3 = camR(F);
    metal::float3 ro_1 = metal::float3(0.0, _e3, 0.0);
    metal::float2 _e10 = raySphere(ro_1, dir_2, RG + hc);
    h_1.t = _e10.y;
    float _e13 = h_1.t;
    metal::float3 p_4 = ro_1 + (dir_2 * _e13);
    h_1.up = p_4 / metal::float3(metal::length(p_4));
    metal::float4 _e24 = F.camPos;
    h_1.q = p_4.xz + (_e24.xz * 0.001);
    metal::float3 _e31 = h_1.up;
    h_1.mu = metal::max(metal::dot(_e31, dir_2), 0.03);
    CloudHit _e35 = h_1;
    return _e35;
}

metal::float4 shadeLayer(
    metal::float3 dir_3,
    CloudHit h_2,
    float hc_1,
    float d,
    float s1_,
    float s2_,
    float s3_,
    float sigma,
    float g_2,
    constant Frame& F,
    metal::texture2d<float, metal::access::sample> transLUT,
    metal::texture2d<float, metal::access::sample> skyLUT,
    metal::sampler sampC
) {
    float tau = (d * sigma) / h_2.mu;
    float alpha = 1.0 - metal::exp(-(tau));
    float tauS = (((((d * 0.5) + (s1_ * 0.6)) + s2_) + (s3_ * 0.7)) * sigma) * 0.55;
    float Ts = metal::exp(-(tauS));
    metal::float4 _e35 = F.sunDir;
    metal::float3 _e38 = sampleTrans(RG + hc_1, metal::dot(h_2.up, _e35.xyz), transLUT, sampC);
    float _e42 = F.sunDir.w;
    metal::float3 sunC = _e38 * _e42;
    metal::float4 _e46 = F.sunDir;
    float cosT = metal::dot(dir_3, _e46.xyz);
    float _e49 = phaseHG(cosT, g_2);
    float _e51 = phaseHG(cosT, -0.2);
    float ph = metal::mix(_e49, _e51, 0.25);
    float fwd = metal::smoothstep(-0.2, 0.7, cosT);
    metal::float3 single = (((sunC * Ts) * ph) * metal::mix(alpha * 0.55, (tau * metal::exp(-(tau))) * 2.2, fwd)) * 3.0;
    float rim = metal::clamp((d - s1_) * 2.5, 0.0, 1.0);
    float toward = metal::smoothstep(-0.3, 0.9, cosT);
    metal::float3 ms = (((sunC * (0.025 + (0.22 * rim))) * metal::mix(1.0, Ts, 0.5)) * alpha) * (0.25 + (0.75 * toward));
    metal::float3 _e99 = skyAtmo(metal::normalize(metal::float3(dir_3.x, 0.03, dir_3.z)), F, skyLUT, sampC);
    metal::float3 _e106 = skyAtmo(metal::float3(0.0, 1.0, 0.0), F, skyLUT, sampC);
    metal::float3 amb = (((_e99 * 0.26) + (_e106 * 0.42)) * alpha) * (1.0 - (0.35 * d));
    return metal::float4((single + ms) + amb, alpha);
}

// VOLUMETRIC_CLOUD_IMPLEMENTATION
metal::float4 cloudLayers(
    metal::float3 dir_4,
    float pixAng,
    metal::float2 aa,
    thread float& sunT,
    constant Frame& F,
    metal::texture2d<float, metal::access::sample> transLUT,
    metal::texture2d<float, metal::access::sample> skyLUT,
    metal::sampler sampC
, metal::texture3d<float> cloudNoise
) {
    metal::float4 lo = metal::float4(0.0);
    float loVis = 1.0;
    metal::float4 hi = metal::float4(0.0);
    float hiVis = 1.0;
    sunT = 1.0;
    if (dir_4.y <= 0.0) {
        return metal::float4(0.0);
    }
    metal::float4 _e12 = F.sunDir;
    metal::float4 _e16 = F.sunDir;
    metal::float2 sxz = _e12.xz / metal::float2(metal::max(metal::length(_e16.xz), 0.0001));
    float _e31 = F.cloudP.y;
#if VOLUMETRIC_CLOUDS
    float lowSunTransmission=1.0;
    lo = volumeClouds(dir_4,pixAng,F,transLUT,skyLUT,sampC,cloudNoise,lowSunTransmission);
#else
    if (_e31 > 0.001) {
        float hc_2 = F.cloudP.x;
        CloudHit _e38 = hitLayer(dir_4, hc_2, F);
        float far = 1.0 - metal::smoothstep(18.0, 36.0, _e38.t);
        if (far > 0.0) {
            float fp_7 = (_e38.t * pixAng) / _e38.mu;
            float _e53 = lowEdge(_e38.q, fp_7, 7, F);
            float _e54 = lowSoft(fp_7);
            float d_5 = metal::clamp(_e53 / _e54, 0.0, 1.0) * far;
            if (d_5 > 0.002) {
                float _e67 = lowDensity(_e38.q + (sxz * 0.08), fp_7, 5, F);
                float s1_1 = _e67 * far;
                float _e74 = lowDensity(_e38.q + (sxz * 0.25), fp_7, 4, F);
                float s2_1 = _e74 * far;
                float _e81 = lowDensity(_e38.q + (sxz * 0.6), fp_7, 3, F);
                float s3_1 = _e81 * far;
                float _e86 = F.cloudP.z;
                metal::float4 _e88 = shadeLayer(dir_4, _e38, hc_2, d_5, s1_1, s2_1, s3_1, _e86, 0.75, F, transLUT, skyLUT, sampC);
                lo = _e88;
                float aw = (aa.x >= 0.0) ? aa.x : ((fp_7 * 0.38) * 2.5);
                metal::float4 _e98 = lo;
                lo = _e98 * metal::smoothstep(0.0, (aw * 1.5) + 0.000001, _e53);
                float _e113 = F.atmo.x;
                loVis = metal::exp((-(_e38.t) * 0.02) * (0.6 + (0.4 * _e113)));
            }
        }
    }
#endif
    float _e128 = F.atmo.z;
#if VOLUMETRIC_CLOUDS
    if (_e128 > 0.001) hi=volumeWisps(dir_4,F,transLUT,skyLUT,sampC,cloudNoise);
#else
    if (_e128 > 0.001) {
        CloudHit _e132 = hitLayer(dir_4, 4.5, F);
        float far_1 = 1.0 - metal::smoothstep(30.0, 70.0, _e132.t);
        if (far_1 > 0.0) {
            float fp_8 = (_e132.t * pixAng) / _e132.mu;
            float _e147 = highEdge(_e132.q, fp_8, 6, F);
            float _e148 = highSoft(fp_8);
            float d_6 = metal::clamp(_e147 / _e148, 0.0, 1.0) * far_1;
            if (d_6 > 0.002) {
                float _e161 = highDensity(_e132.q + (sxz * 0.15), fp_8, 4, F);
                float s1_2 = _e161 * far_1;
                float _e168 = highDensity(_e132.q + (sxz * 0.5), fp_8, 3, F);
                float s2_2 = _e168 * far_1;
                float _e173 = F.atmo.w;
                metal::float4 _e175 = shadeLayer(dir_4, _e132, 4.5, d_6, s1_2, s2_2, s2_2, _e173, 0.8, F, transLUT, skyLUT, sampC);
                hi = _e175;
                float aw_1 = (aa.y >= 0.0) ? aa.y : ((fp_8 * 0.2) * 2.5);
                metal::float4 _e185 = hi;
                hi = _e185 * metal::smoothstep(0.0, (aw_1 * 1.5) + 0.000001, _e147);
                float _e200 = F.atmo.x;
                hiVis = metal::exp((-(_e132.t) * 0.01) * (0.6 + (0.4 * _e200)));
            }
        }
    }
#endif
    float _e208 = lo.w;
    float _e212 = hi.w;
    sunT = (1.0 - _e208) * (1.0 - _e212);
    metal::float4 _e216 = lo;
    float _e218 = loVis;
    metal::float4 _e220 = hi;
    float _e222 = hiVis;
    float _e225 = lo.w;
    metal::float3 col = (_e216.xyz * _e218) + ((_e220.xyz * _e222) * (1.0 - _e225));
    float _e231 = lo.w;
    float _e232 = loVis;
    float _e235 = hi.w;
    float _e236 = hiVis;
    float _e239 = lo.w;
    float hidden = (_e231 * _e232) + ((_e235 * _e236) * (1.0 - _e239));
    return metal::float4(col, hidden);
}

metal::float3 sunDisk(
    metal::float3 dir_5,
    constant Frame& F,
    metal::texture2d<float, metal::access::sample> transLUT,
    metal::sampler sampC
) {
    metal::float4 _e3 = F.celestial.w>0.5 ? F.sunDiskDir : F.sunDir;
    float c_5 = metal::dot(dir_5, _e3.xyz);
    float ang = metal::sqrt(metal::max(2.0 * (1.0 - c_5), 0.0));
    float _e16 = F.screen.w;
    metal::float4 _e21 = F.camUp;
    float pix = ((_e16 * 2.0) * metal::length(_e21.xyz)) * 0.75;
    float diskRadius=F.celestial.w>0.5 ? F.celestial.x : SUN_ANG_R;
    float edge = 1.0 - metal::smoothstep(diskRadius - pix, diskRadius + pix, ang);
    if (edge <= 0.0) {
        return metal::float3(0.0);
    }
    float x_1 = metal::min(ang / diskRadius, 1.0);
    float mu_4 = metal::sqrt(metal::max(1.0 - (x_1 * x_1), 0.0));
    metal::float3 limb = metal::float3(1.0) - (metal::float3(0.397, 0.503, 0.652) * (1.0 - mu_4));
    float _e61 = F.sunDir.w;
    float rad = _e61 / 0.00006866147;
    float _e66 = camR(F);
    metal::float3 _e70 = sampleTrans(_e66, metal::max(dir_5.y, -0.01), transLUT, sampC);
    return ((rad * limb) * edge) * _e70;
}

metal::float3 skyRadiance(
    metal::float3 dirIn,
    bool withSun,
    float pixAng_1,
    constant Frame& F,
    metal::texture2d<float, metal::access::sample> transLUT,
    metal::texture2d<float, metal::access::sample> skyLUT,
    metal::sampler sampC
, metal::texture3d<float> cloudNoise
, metal::texture2d<float> starAtlas
, metal::texture2d<float> galaxyAtlas
) {
    metal::float3 dir_6 = {};
    metal::float3 L_1 = {};
    float sunT_1 = 1.0;
    dir_6 = dirIn;
    float _e6 = dir_6.y;
    dir_6.y = metal::max(_e6, 0.0005);
    metal::float3 _e9 = dir_6;
    dir_6 = metal::normalize(_e9);
    metal::float3 _e11 = dir_6;
    metal::float3 _e12 = skyAtmo(_e11, F, skyLUT, sampC);
    L_1 = _e12;
    metal::float3 _e16 = dir_6;
    metal::float4 _e19 = cloudLayers(_e16, pixAng_1, metal::float2(-1.0), sunT_1, F, transLUT, skyLUT, sampC, cloudNoise);
    metal::float3 _e20 = L_1;
    L_1 = (_e20 * (1.0 - _e19.w)) + _e19.xyz;
    L_1 += celestialStarfield(dir_6,pixAng_1,F,starAtlas,galaxyAtlas,true)*stellarCloudVisibility(sunT_1);
    L_1 += auroraRadiance(dir_6,F.nightFx,F.celestial.w>0.5 ? F.celestial.z : 0.0,6,0.5)*sunT_1;
    if (withSun) {
        metal::float3 _e27 = L_1;
        metal::float3 _e28 = dir_6;
        metal::float3 _e29 = sunDisk(_e28, F, transLUT, sampC);
        float _e30 = sunT_1;
        L_1 = _e27 + (_e29 * _e30);
    }
    metal::float3 _e33 = L_1;
    return _e33;
}

metal::float3 faceDir(
    uint face,
    metal::float2 uv_2
) {
    float u_3 = (uv_2.x * 2.0) - 1.0;
    float v_1 = (uv_2.y * 2.0) - 1.0;
    switch(face) {
        case 0u: {
            return metal::float3(1.0, -(v_1), -(u_3));
        }
        case 1u: {
            return metal::float3(-1.0, -(v_1), u_3);
        }
        case 2u: {
            return metal::float3(u_3, 1.0, v_1);
        }
        case 3u: {
            return metal::float3(u_3, -1.0, -(v_1));
        }
        case 4u: {
            return metal::float3(u_3, -(v_1), 1.0);
        }
        default: {
            return metal::float3(-(u_3), -(v_1), -1.0);
        }
    }
}
uint naga_f2u32(float value) {
    return static_cast<uint>(metal::clamp(value, 0.0, 4294967000.0));
}


struct main_Input {
};
[[max_total_threads_per_threadgroup(64)]] kernel void main_(
  metal::uint3 id [[thread_position_in_grid]]
, constant Frame& F [[buffer(0)]]
, metal::texture2d<float, metal::access::sample> transLUT [[texture(1)]]
, metal::texture2d<float, metal::access::sample> skyLUT [[texture(2)]]
, metal::sampler sampC [[sampler(3)]]
, metal::texture3d<float> cloudNoise [[texture(5)]]
, metal::texture2d<float> starAtlas [[texture(6)]]
, metal::texture2d<float> galaxyAtlas [[texture(7)]]
, metal::texture2d_array<float, metal::access::write> dst [[texture(4)]]
) {

    bool local = {};
    metal::float3 L = {};
    if (!((static_cast<float>(id.x) >= ENV))) {
        local = static_cast<float>(id.y) >= ENV;
    } else {
        local = true;
    }
    bool _e13 = local;
    if (_e13) {
        return;
    }
    float _e17 = F.camRight.w;
    uint face_1 = (naga_f2u32(_e17) + id.z) % 6u;
    metal::float3 _e31 = faceDir(face_1, (static_cast<metal::float2>(id.xy) + metal::float2(0.5)) / metal::float2(128.0));
    metal::float3 dir_7 = metal::normalize(_e31);
    if (dir_7.y >= 0.0) {
        metal::float3 _e39 = skyRadiance(dir_7, false, 0.018407812, F, transLUT, skyLUT, sampC, cloudNoise, starAtlas, galaxyAtlas);
        L = _e39;
    } else {
        metal::float3 _e47 = skyRadiance(metal::normalize(metal::float3(dir_7.x, 0.004, dir_7.z)), false, 0.018407812, F, transLUT, skyLUT, sampC, cloudNoise, starAtlas, galaxyAtlas);
        metal::float4 _e50 = F.waterCol;
        metal::float3 _e52 = sunIlluminance(F, transLUT, sampC);
        float _e56 = F.sunDir.y;
        metal::float3 _e64 = skyAtmo(metal::float3(0.0, 1.0, 0.0), F, skyLUT, sampC);
        metal::float3 body = _e50.xyz * ((_e52 * metal::max(_e56, 0.0)) + (_e64 * 2.0));
        L = metal::mix(_e47 * 0.75, body, metal::clamp(-(dir_7.y) * 6.0, 0.0, 1.0));
    }
    metal::float3 _e81 = L;
    dst.write(metal::float4(_e81, 1.0), metal::uint2(id.xy), face_1);
    return;
}

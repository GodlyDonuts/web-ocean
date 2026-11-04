// Native Metal shaders migrated from the original ocean equations using Naga.
// Edit this file for native rendering; no WGSL or JavaScript runs in the app.
// language: metal2.3
#include <metal_stdlib>
#include <simd/simd.h>

using metal::uint;

struct Medium {
    metal::float3 ext;
    metal::packed_float3 rayS;
    float mieS;
};
struct AtmoP {
    metal::float4 haze;
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
    float b_1 = metal::dot(ro, rd);
    float c_3 = (l - R) * (l + R);
    float d = (b_1 * b_1) - c_3;
    if (d < 0.0) {
        return metal::float2(-1.0, -1.0);
    }
    float s_1 = metal::sqrt(d);
    return metal::float2(-(b_1) - s_1, -(b_1) + s_1);
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
    metal::float2 uv_1
) {
    float mu_1 = 1.0;
    float rho = 1132.2544 * uv_1.y;
    float r_4 = metal::sqrt((rho * rho) + 40449600.0);
    float dMin_1 = RT - r_4;
    float dMax_1 = rho + 1132.2544;
    float d_2 = dMin_1 + (uv_1.x * (dMax_1 - dMin_1));
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

struct main_Input {
};
[[max_total_threads_per_threadgroup(64)]] kernel void main_(
  metal::uint3 id [[thread_position_in_grid]]
, constant AtmoP& A [[buffer(0)]]
, metal::texture2d<float, metal::access::sample> transLUT [[texture(1)]]
, metal::sampler sampC [[sampler(2)]]
, metal::texture2d<float, metal::access::write> dst [[texture(3)]]
) {

    bool local = {};
    metal::float2 uv = {};
    metal::float3 Lsum = metal::float3(0.0);
    metal::float3 Fsum = metal::float3(0.0);
    uint a = 0u;
    uint b = {};
    float tMax = {};
    metal::float3 T = {};
    metal::float3 L = {};
    metal::float3 Fms = {};
    uint s = {};
    metal::float3 sunT = {};
    if (!((static_cast<float>(id.x) >= MS_SIZE))) {
        local = static_cast<float>(id.y) >= MS_SIZE;
    } else {
        local = true;
    }
    bool _e13 = local;
    if (_e13) {
        return;
    }
    uv = (static_cast<metal::float2>(id.xy) + metal::float2(0.5)) / metal::float2(32.0);
    float _e24 = uv.x;
    float _e26 = fromSubUvsToUnit(_e24, MS_SIZE);
    float _e28 = uv.y;
    float _e30 = fromSubUvsToUnit(_e28, MS_SIZE);
    uv = metal::float2(_e26, _e30);
    float _e33 = uv.x;
    float cosSun = (_e33 * 2.0) - 1.0;
    float _e39 = uv.y;
    float h_1 = metal::max(_e39 * 100.0, 0.01);
    float r_5 = RG + h_1;
    metal::float3 ro_1 = metal::float3(0.0, r_5, 0.0);
    metal::float3 sun = metal::float3(metal::sqrt(metal::max(0.0, 1.0 - (cosSun * cosSun))), cosSun, 0.0);
    bool loop_init = true;
    while(true) {
        if (!loop_init) {
            uint _e213 = a;
            a = _e213 + 1u;
        }
        loop_init = false;
        uint _e67 = a;
        if (_e67 < 8u) {
        } else {
            break;
        }
        {
            b = 0u;
            bool loop_init_1 = true;
            while(true) {
                if (!loop_init_1) {
                    uint _e210 = b;
                    b = _e210 + 1u;
                }
                loop_init_1 = false;
                uint _e71 = b;
                if (_e71 < 8u) {
                } else {
                    break;
                }
                {
                    uint _e73 = b;
                    float th = metal::acos(1.0 - ((2.0 * (static_cast<float>(_e73) + 0.5)) / static_cast<float>(8u)));
                    uint _e85 = a;
                    float ph = (6.2831855 * (static_cast<float>(_e85) + 0.5)) / static_cast<float>(8u);
                    metal::float3 rd_1 = metal::float3(metal::sin(th) * metal::cos(ph), metal::cos(th), metal::sin(th) * metal::sin(ph));
                    metal::float2 _e101 = raySphere(ro_1, rd_1, RT);
                    metal::float2 _e103 = raySphere(ro_1, rd_1, RG);
                    tMax = _e101.y;
                    bool hitG = _e103.x > 0.0;
                    if (hitG) {
                        tMax = _e103.x;
                    }
                    float _e110 = tMax;
                    float dt = _e110 / static_cast<float>(20u);
                    T = metal::float3(1.0);
                    L = metal::float3(0.0);
                    Fms = metal::float3(0.0);
                    s = 0u;
                    bool loop_init_2 = true;
                    while(true) {
                        if (!loop_init_2) {
                            uint _e182 = s;
                            s = _e182 + 1u;
                        }
                        loop_init_2 = false;
                        uint _e124 = s;
                        if (_e124 < 20u) {
                        } else {
                            break;
                        }
                        {
                            uint _e126 = s;
                            metal::float3 p = ro_1 + (rd_1 * ((static_cast<float>(_e126) + 0.5) * dt));
                            float pr = metal::length(p);
                            float _e139 = A.haze.x;
                            Medium _e140 = medium(pr - RG, _e139);
                            metal::float3 scat = _e140.rayS + metal::float3(_e140.mieS);
                            metal::float3 Ts = metal::exp(-(_e140.ext) * dt);
                            float smu = metal::dot(p, sun) / pr;
                            metal::float3 _e151 = sampleTrans(pr, smu, transLUT, sampC);
                            sunT = _e151;
                            bool _e153 = sunBelowHorizon(pr, smu);
                            if (_e153) {
                                sunT = metal::float3(0.0);
                            }
                            metal::float3 ext = metal::max(_e140.ext, metal::float3(0.000000001));
                            metal::float3 _e160 = sunT;
                            metal::float3 S = (scat * _e160) / metal::float3(12.566371);
                            metal::float3 _e165 = L;
                            metal::float3 _e166 = T;
                            L = _e165 + ((_e166 * (S - (S * Ts))) / ext);
                            metal::float3 _e172 = Fms;
                            metal::float3 _e173 = T;
                            Fms = _e172 + ((_e173 * (scat - (scat * Ts))) / ext);
                            metal::float3 _e179 = T;
                            T = _e179 * Ts;
                        }
                    }
                    if (hitG) {
                        float _e184 = tMax;
                        metal::float3 pg = ro_1 + (rd_1 * _e184);
                        metal::float3 ng = metal::normalize(pg);
                        float smu_1 = metal::dot(ng, sun);
                        metal::float3 _e189 = L;
                        metal::float3 _e190 = T;
                        metal::float3 _e192 = sampleTrans(RG, smu_1, transLUT, sampC);
                        L = _e189 + ((((_e190 * _e192) * metal::max(smu_1, 0.0)) * 0.06) / metal::float3(3.1415927));
                    }
                    metal::float3 _e203 = Lsum;
                    metal::float3 _e204 = L;
                    Lsum = _e203 + _e204;
                    metal::float3 _e206 = Fsum;
                    metal::float3 _e207 = Fms;
                    Fsum = _e206 + _e207;
                }
            }
        }
    }
    float invN = 1.0 / static_cast<float>(8u * 8u);
    metal::float3 _e219 = Lsum;
    metal::float3 L2_ = _e219 * invN;
    metal::float3 _e221 = Fsum;
    metal::float3 fms = _e221 * invN;
    dst.write(metal::float4(L2_ / (metal::float3(1.0) - fms), 1.0), metal::uint2(id.xy));
    return;
}

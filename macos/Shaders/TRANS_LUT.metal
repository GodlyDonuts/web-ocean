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
    float b = metal::dot(ro, rd);
    float c_3 = (l - R) * (l + R);
    float d = (b * b) - c_3;
    if (d < 0.0) {
        return metal::float2(-1.0, -1.0);
    }
    float s = metal::sqrt(d);
    return metal::float2(-(b) - s, -(b) + s);
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
    float r_3 = metal::sqrt((rho * rho) + 40449600.0);
    float dMin_1 = RT - r_3;
    float dMax_1 = rho + 1132.2544;
    float d_2 = dMin_1 + (uv.x * (dMax_1 - dMin_1));
    if (d_2 > 0.0) {
        mu_1 = (((1132.2544 * 1132.2544) - (rho * rho)) - (d_2 * d_2)) / ((2.0 * r_3) * d_2);
    }
    float _e28 = mu_1;
    return metal::float2(r_3, metal::clamp(_e28, -1.0, 1.0));
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

struct main_Input {
};
[[max_total_threads_per_threadgroup(64)]] kernel void main_(
  metal::uint3 id [[thread_position_in_grid]]
, constant AtmoP& A [[buffer(0)]]
, metal::texture2d<float, metal::access::write> dst [[texture(1)]]
) {

    bool local = {};
    metal::float3 od = metal::float3(0.0);
    uint i = 0u;
    if (!((static_cast<float>(id.x) >= TRANS_W))) {
        local = static_cast<float>(id.y) >= TRANS_H;
    } else {
        local = true;
    }
    bool _e13 = local;
    if (_e13) {
        return;
    }
    metal::float2 uv_1 = (static_cast<metal::float2>(id.xy) + metal::float2(0.5)) / metal::float2(256.0, 64.0);
    metal::float2 _e23 = transUVToRMu(uv_1);
    metal::float3 ro_1 = metal::float3(0.0, _e23.x, 0.0);
    metal::float3 rd_1 = metal::float3(metal::sqrt(metal::max(0.0, 1.0 - (_e23.y * _e23.y))), _e23.y, 0.0);
    metal::float2 _e40 = raySphere(ro_1, rd_1, RT);
    float tMax = _e40.y;
    float dt = tMax / static_cast<float>(64u);
    bool loop_init = true;
    while(true) {
        if (!loop_init) {
            uint _e72 = i;
            i = _e72 + 1u;
        }
        loop_init = false;
        uint _e50 = i;
        if (_e50 < 64u) {
        } else {
            break;
        }
        {
            uint _e52 = i;
            metal::float3 p = ro_1 + (rd_1 * ((static_cast<float>(_e52) + 0.5) * dt));
            metal::float3 _e59 = od;
            float _e66 = A.haze.x;
            Medium _e67 = medium(metal::length(p) - RG, _e66);
            od = _e59 + (_e67.ext * dt);
        }
    }
    metal::float3 _e76 = od;
    dst.write(metal::float4(metal::exp(-(_e76)), 1.0), metal::uint2(id.xy));
    return;
}

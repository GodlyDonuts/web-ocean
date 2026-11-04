// Native Metal shaders migrated from the original ocean equations using Naga.
// Edit this file for native rendering; no WGSL or JavaScript runs in the app.
// language: metal2.3
#include <metal_stdlib>
#include <simd/simd.h>

using metal::uint;

struct type_2 {
    metal::int4 inner[2];
};
struct type_4 {
    metal::float4 inner[2];
};
struct FoamU {
    type_2 snap;
    metal::float4 p0_;
    metal::float4 p1_;
    type_4 cascL;
    type_4 cascInvL;
    metal::float4 drift;
};
constant int RES = 512;

int wrapIdx(
    int i,
    int lo
) {
    return as_type<int>(as_type<uint>(lo) + as_type<uint>(as_type<int>(as_type<uint>(as_type<int>(as_type<uint>(i) - as_type<uint>(lo)) % RES) + as_type<uint>(RES)) % RES));
}

struct main_Input {
};
[[max_total_threads_per_threadgroup(64)]] kernel void main_(
  metal::uint3 id [[thread_position_in_grid]]
, constant FoamU& U [[buffer(0)]]
, metal::texture2d_array<float, metal::access::sample> prevTex [[texture(1)]]
, metal::texture2d_array<float, metal::access::write> dst [[texture(2)]]
, metal::texture2d_array<float, metal::access::sample> dispTex [[texture(3)]]
, metal::texture2d_array<float, metal::access::sample> derivTex [[texture(4)]]
, metal::sampler samp [[sampler(5)]]
, metal::sampler sampPrev [[sampler(6)]]
) {

    bool local = {};
    bool local_1 = {};
    float jxx = 0.0;
    float jzz = 0.0;
    float jxz = 0.0;
    uint c = 0u;
    metal::float4 prev = metal::float4(0.0);
    float f = {};
    uint lvl = id.z;
    metal::int4 sn = U.snap.inner[lvl];
    float _e9 = U.p0_.x;
    float _e13 = U.p0_.y;
    float ts = (lvl == 1u) ? _e13 : _e9;
    metal::int2 lo_1 = as_type<metal::int2>(as_type<metal::uint2>(sn.xy) - as_type<metal::uint2>(metal::int2(256)));
    int _e24 = wrapIdx(static_cast<int>(id.x), lo_1.x);
    int _e28 = wrapIdx(static_cast<int>(id.y), lo_1.y);
    metal::int2 g = metal::int2(_e24, _e28);
    metal::int2 plo = as_type<metal::int2>(as_type<metal::uint2>(sn.zw) - as_type<metal::uint2>(metal::int2(256)));
    if (metal::all(g >= plo)) {
        local = metal::all(g < as_type<metal::int2>(as_type<metal::uint2>(plo) + as_type<metal::uint2>(metal::int2(512))));
    } else {
        local = false;
    }
    bool inPrev = local;
    metal::float2 p = (static_cast<metal::float2>(g) + metal::float2(0.5)) * ts;
    if (!((p.y > 16.0))) {
        float _e65 = U.p1_.w;
        local_1 = metal::abs(p.x) > (16.0 + (metal::max(-(p.y), 0.0) * _e65));
    } else {
        local_1 = true;
    }
    bool _e71 = local_1;
    if (_e71) {
        dst.write(metal::float4(0.0), metal::uint2(id.xy), lvl);
        return;
    }
    bool loop_init = true;
    while(true) {
        if (!loop_init) {
            uint _e136 = c;
            c = _e136 + 1u;
        }
        loop_init = false;
        uint _e84 = c;
        if (_e84 < 6u) {
        } else {
            break;
        }
        {
            uint _e89 = c;
            uint _e93 = c;
            float _e97 = U.cascL.inner[_e89 >> 2u][_e93 & 3u];
            float texel = _e97 / 256.0;
            float lod = metal::log2(metal::max(ts / texel, 1.0));
            if (lod < 7.5) {
                uint _e108 = c;
                uint _e112 = c;
                float _e116 = U.cascInvL.inner[_e108 >> 2u][_e112 & 3u];
                metal::float2 uv = p * _e116;
                uint _e120 = c;
                metal::float4 d = derivTex.sample(samp, uv, _e120, metal::level(lod));
                uint _e124 = c;
                metal::float4 a = dispTex.sample(samp, uv, _e124, metal::level(lod));
                float _e126 = jxx;
                jxx = _e126 + d.z;
                float _e129 = jzz;
                jzz = _e129 + d.w;
                float _e132 = jxz;
                jxz = _e132 + a.w;
            }
        }
    }
    float _e138 = jxx;
    float _e141 = jzz;
    float _e145 = jxz;
    float _e146 = jxz;
    float J = ((1.0 + _e138) * (1.0 + _e141)) - (_e145 * _e146);
    if (inPrev) {
        metal::float4 _e159 = U.drift;
        float _e164 = U.p0_.z;
        metal::float2 back = ((static_cast<metal::float2>(id.xy) + metal::float2(0.5)) - ((_e159.xy * _e164) / metal::float2(ts))) / metal::float2(512.0);
        metal::float4 _e175 = prevTex.sample(sampPrev, back, lvl, metal::level(0.0));
        prev = _e175;
    }
    float dt = U.p0_.z;
    float _e183 = U.p1_.x;
    float _e188 = U.p1_.y;
    float inject = metal::clamp((_e183 - J) * _e188, 0.0, 1.0);
    float _e194 = prev.x;
    float _e199 = U.p0_.w;
    f = _e194 * metal::exp(-(dt) * _e199);
    float _e204 = f;
    f = metal::max(_e204, inject);
    float _e206 = f;
    float _e211 = U.p1_.z;
    f = metal::min(_e206 + ((inject * dt) * _e211), 1.6);
    float _e217 = prev.y;
    float fresh = metal::max(_e217 * metal::exp(-(dt) * 1.6), inject);
    float _e226 = f;
    dst.write(metal::float4(_e226, fresh, J, 1.0), metal::uint2(id.xy), lvl);
    return;
}

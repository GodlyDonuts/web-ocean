// Native Metal shaders migrated from the original ocean equations using Naga.
// Edit this file for native rendering; no WGSL or JavaScript runs in the app.
// language: metal2.3
#include <metal_stdlib>
#include <simd/simd.h>

using metal::uint;

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
};
uint naga_f2u32(float value) {
    return static_cast<uint>(metal::clamp(value, 0.0, 4294967000.0));
}


struct main_Input {
};
[[max_total_threads_per_threadgroup(64)]] kernel void main_(
  metal::uint3 id [[thread_position_in_grid]]
, constant Frame& F [[buffer(2)]]
, metal::texture2d_array<float, metal::access::sample> src [[texture(0)]]
, metal::texture2d_array<float, metal::access::write> dst [[texture(1)]]
) {

    bool local = {};
    metal::float4 acc = metal::float4(0.0);
    float wsum = 0.0;
    int j = -1;
    int i = {};
    bool local_1 = {};
    bool local_2 = {};
    metal::uint2 size = metal::uint2(dst.get_width(), dst.get_height());
    if (!((id.x >= size.x))) {
        local = id.y >= size.y;
    } else {
        local = true;
    }
    bool _e13 = local;
    if (_e13) {
        return;
    }
    metal::int2 srcSize = static_cast<metal::int2>(metal::uint2(src.get_width(), src.get_height()));
    metal::int2 p = as_type<metal::int2>(as_type<metal::uint2>(static_cast<metal::int2>(id.xy)) * as_type<uint>(2));
    bool loop_init = true;
    while(true) {
        if (!loop_init) {
            int _e96 = j;
            j = as_type<int>(as_type<uint>(_e96) + as_type<uint>(1));
        }
        loop_init = false;
        int _e28 = j;
        if (_e28 <= 2) {
        } else {
            break;
        }
        {
            i = -1;
            bool loop_init_1 = true;
            while(true) {
                if (!loop_init_1) {
                    int _e93 = i;
                    i = as_type<int>(as_type<uint>(_e93) + as_type<uint>(1));
                }
                loop_init_1 = false;
                int _e33 = i;
                if (_e33 <= 2) {
                } else {
                    break;
                }
                {
                    int _e36 = i;
                    int _e37 = j;
                    metal::int2 q = metal::clamp(as_type<metal::int2>(as_type<metal::uint2>(p) + as_type<metal::uint2>(metal::int2(_e36, _e37))), metal::int2(0), as_type<metal::int2>(as_type<metal::uint2>(srcSize) - as_type<metal::uint2>(metal::int2(1))));
                    int _e46 = i;
                    if (!((_e46 == 0))) {
                        int _e52 = i;
                        local_1 = _e52 == 1;
                    } else {
                        local_1 = true;
                    }
                    bool _e56 = local_1;
                    int _e60 = j;
                    if (!((_e60 == 0))) {
                        int _e66 = j;
                        local_2 = _e66 == 1;
                    } else {
                        local_2 = true;
                    }
                    bool _e70 = local_2;
                    float w = (_e56 ? 3.0 : 1.0) * (_e70 ? 3.0 : 1.0);
                    metal::float4 _e75 = acc;
                    float _e80 = F.camRight.w;
                    metal::float4 _e87 = src.read(metal::uint2(q), (naga_f2u32(_e80) + id.z) % 6u, 0);
                    acc = _e75 + (_e87 * w);
                    float _e90 = wsum;
                    wsum = _e90 + w;
                }
            }
        }
    }
    float _e103 = F.camRight.w;
    metal::float4 _e109 = acc;
    float _e110 = wsum;
    dst.write(_e109 / metal::float4(_e110), metal::uint2(id.xy), (naga_f2u32(_e103) + id.z) % 6u);
    return;
}

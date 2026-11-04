// Native Metal shaders migrated from the original ocean equations using Naga.
// Edit this file for native rendering; no WGSL or JavaScript runs in the app.
// language: metal2.3
#include <metal_stdlib>
#include <simd/simd.h>

using metal::uint;


struct main_Input {
};
[[max_total_threads_per_threadgroup(64)]] kernel void main_(
  metal::uint3 id [[thread_position_in_grid]]
, metal::texture2d<float, metal::access::sample> src [[texture(0)]]
, metal::texture2d<float, metal::access::write> dst [[texture(1)]]
) {

    bool local = {};
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
    metal::int2 p = as_type<metal::int2>(as_type<metal::uint2>(static_cast<metal::int2>(id.xy)) * as_type<uint>(2));
    metal::float4 _e20 = src.read(metal::uint2(p), 0);
    metal::float4 _e27 = src.read(metal::uint2(as_type<metal::int2>(as_type<metal::uint2>(p) + as_type<metal::uint2>(metal::int2(1, 0)))), 0);
    metal::float4 _e35 = src.read(metal::uint2(as_type<metal::int2>(as_type<metal::uint2>(p) + as_type<metal::uint2>(metal::int2(0, 1)))), 0);
    metal::float4 _e43 = src.read(metal::uint2(as_type<metal::int2>(as_type<metal::uint2>(p) + as_type<metal::uint2>(metal::int2(1, 1)))), 0);
    metal::float4 v = 0.25 * (((_e20 + _e27) + _e35) + _e43);
    dst.write(v, metal::uint2(id.xy));
    return;
}

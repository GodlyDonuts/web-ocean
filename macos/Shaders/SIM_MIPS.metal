// Native Metal shaders migrated from the original ocean equations using Naga.
// Edit this file for native rendering; no WGSL or JavaScript runs in the app.
// language: metal2.3
#include <metal_stdlib>
#include <simd/simd.h>

using metal::uint;


metal::float4 box(
    metal::texture2d_array<float, metal::access::sample> t,
    metal::int2 p,
    uint l
) {
    metal::float4 _e4 = t.read(metal::uint2(p), l, 0);
    metal::float4 _e10 = t.read(metal::uint2(as_type<metal::int2>(as_type<metal::uint2>(p) + as_type<metal::uint2>(metal::int2(1, 0)))), l, 0);
    metal::float4 _e17 = t.read(metal::uint2(as_type<metal::int2>(as_type<metal::uint2>(p) + as_type<metal::uint2>(metal::int2(0, 1)))), l, 0);
    metal::float4 _e24 = t.read(metal::uint2(as_type<metal::int2>(as_type<metal::uint2>(p) + as_type<metal::uint2>(metal::int2(1, 1)))), l, 0);
    return 0.25 * (((_e4 + _e10) + _e17) + _e24);
}

struct main_Input {
};
[[max_total_threads_per_threadgroup(64)]] kernel void main_(
  metal::uint3 id [[thread_position_in_grid]]
, metal::texture2d_array<float, metal::access::sample> srcA [[texture(0)]]
, metal::texture2d_array<float, metal::access::sample> srcB [[texture(1)]]
, metal::texture2d_array<float, metal::access::sample> srcC [[texture(2)]]
, metal::texture2d_array<float, metal::access::write> dstA [[texture(3)]]
, metal::texture2d_array<float, metal::access::write> dstB [[texture(4)]]
, metal::texture2d_array<float, metal::access::write> dstC [[texture(5)]]
) {

    bool local = {};
    metal::uint2 size = metal::uint2(dstA.get_width(), dstA.get_height());
    if (!((id.x >= size.x))) {
        local = id.y >= size.y;
    } else {
        local = true;
    }
    bool _e13 = local;
    if (_e13) {
        return;
    }
    metal::int2 p_1 = as_type<metal::int2>(as_type<metal::uint2>(static_cast<metal::int2>(id.xy)) * as_type<uint>(2));
    metal::float4 _e23 = box(srcA, p_1, id.z);
    dstA.write(_e23, metal::uint2(id.xy), id.z);
    metal::float4 _e29 = box(srcB, p_1, id.z);
    dstB.write(_e29, metal::uint2(id.xy), id.z);
    metal::float4 _e35 = box(srcC, p_1, id.z);
    dstC.write(_e35, metal::uint2(id.xy), id.z);
    return;
}

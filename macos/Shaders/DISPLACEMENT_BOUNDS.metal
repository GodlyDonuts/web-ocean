#include <metal_stdlib>
using namespace metal;

// Per-cascade absolute displacement bounds. The current B-spline and linear
// reconstruction weights are nonnegative, so filtered samples remain bounded.
[[max_total_threads_per_threadgroup(256)]] kernel void main_(
    texture2d_array<float,access::read> displacement [[texture(0)]],
    device float4* partial [[buffer(1)]],
    uint3 pixel [[thread_position_in_grid]],
    uint3 group [[threadgroup_position_in_grid]],
    uint lane [[thread_index_in_threadgroup]]) {
    threadgroup float4 values[256];
    values[lane] = abs(displacement.read(pixel.xy,pixel.z));
    threadgroup_barrier(mem_flags::mem_threadgroup);
    for (uint stride=128; stride>0; stride>>=1) {
        if (lane<stride) values[lane] = max(values[lane],values[lane+stride]);
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }
    if (lane==0) partial[group.z*256+group.y*16+group.x] = values[0];
}

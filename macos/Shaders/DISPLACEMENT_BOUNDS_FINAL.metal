#include <metal_stdlib>
using namespace metal;

[[max_total_threads_per_threadgroup(8)]] kernel void main_(
    const device float4* partial [[buffer(0)]],
    device float4* output [[buffer(1)]],
    uint lane [[thread_index_in_threadgroup]]) {
    threadgroup float4 cascades[8];
    float4 bound = 0;
    if (lane<6) {
        for (uint i=0;i<256;++i) bound = max(bound,partial[lane*256+i]);
    }
    cascades[lane] = bound;
    threadgroup_barrier(mem_flags::mem_threadgroup);
    if (lane==0) {
        float4 total = 0;
        for (uint i=0;i<6;++i) total += cascades[i];
        output[0] = total*1.01f+float4(0.001f);
    }
}

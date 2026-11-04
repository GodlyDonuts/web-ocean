#include <metal_stdlib>
using namespace metal;

// Match the original stage/lane expression on the GPU. Repeated entries keep
// its evaluation context identical while remaining only 8 KiB in total.
[[max_total_threads_per_threadgroup(128)]] kernel void main_(
    device float2* table [[buffer(0)]],
    uint lane [[thread_index_in_threadgroup]]) {
    const float PI = 3.1415927;
    uint s = 0u;
    bool loop_init = true;
    while (true) {
        if (!loop_init) s = s+1u;
        loop_init = false;
        if (s>=8u) break;
        uint halfSize = 1u<<s;
        uint position = lane&(halfSize-1u);
        float angle = (PI*float(position))/float(halfSize);
        table[s*128u+lane] = float2(cos(angle),sin(angle));
    }
}

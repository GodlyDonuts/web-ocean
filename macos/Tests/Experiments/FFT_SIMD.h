// 256-point inverse FFT specialized for Apple GPU 32-lane SIMD groups.
// The butterfly order and arithmetic match the shared-memory reference.
#include <metal_stdlib>
using namespace metal;

inline float4 fftMultiply(float4 value, float2 rotation) {
    return float4(value.x*rotation.x-value.y*rotation.y,
                  value.x*rotation.y+value.y*rotation.x,
                  value.z*rotation.x-value.w*rotation.y,
                  value.z*rotation.y+value.w*rotation.x);
}

inline float4 fftLaneStage(float4 value, uint index, uint distance, float2 rotation) {
    const float4 partner = simd_shuffle_xor(value, distance);
    const bool upper = (index & distance) != 0;
    const float4 lowerValue = upper ? partner : value;
    const float4 upperValue = upper ? value : partner;
    const float4 rotated = fftMultiply(upperValue, rotation);
    return upper ? lowerValue-rotated : lowerValue+rotated;
}

inline void fft256(uint index, threadgroup float4* a, threadgroup float4* b) {
    float4 a0 = a[index], a1 = a[index+128];
    float4 b0 = b[index], b1 = b[index+128];
    // These five stages remain entirely in registers, with lane exchange.
    for (uint stage = 0; stage < 5; ++stage) {
        const uint distance = 1u << stage;
        const float angle = 3.1415927f * float(index & (distance-1u)) / float(distance);
        const float2 rotation(cos(angle), sin(angle));
        a0 = fftLaneStage(a0, index, distance, rotation);
        a1 = fftLaneStage(a1, index, distance, rotation);
        b0 = fftLaneStage(b0, index, distance, rotation);
        b1 = fftLaneStage(b1, index, distance, rotation);
    }
    a[index] = a0; a[index+128] = a1;
    b[index] = b0; b[index+128] = b1;
    threadgroup_barrier(mem_flags::mem_threadgroup);
    // Only the final three stages exchange data across SIMD groups.
    for (uint stage = 5; stage < 8; ++stage) {
        const uint distance = 1u << stage;
        const uint position = index & (distance-1u);
        const uint i0 = ((index >> stage) << (stage+1u)) + position;
        const uint i1 = i0+distance;
        const float angle = 3.1415927f * float(position) / float(distance);
        const float2 rotation(cos(angle), sin(angle));
        const float4 a0 = a[i0], a1 = fftMultiply(a[i1], rotation);
        const float4 b0 = b[i0], b1 = fftMultiply(b[i1], rotation);
        a[i0] = a0+a1; a[i1] = a0-a1;
        b[i0] = b0+b1; b[i1] = b0-b1;
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }
}

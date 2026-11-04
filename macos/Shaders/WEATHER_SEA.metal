#include <metal_stdlib>
using namespace metal;
// Relax complex amplitudes, retaining every oscillator's phase and random seed.
kernel void main_(uint3 id [[thread_position_in_grid]],
    device float4* current [[buffer(0)]],device const float4* target [[buffer(1)]],
    constant float4& response [[buffer(2)]]) {
    uint index=(id.z*256+id.y)*256+id.x;
    current[index]=mix(current[index],target[index],response.x);
}

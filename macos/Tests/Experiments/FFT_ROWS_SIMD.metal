// Register-resident first five FFT stages; see FFT_SIMD.h.
#include "FFT_SIMD.h"
kernel void main_(uint3 group [[threadgroup_position_in_grid]],
                  uint index [[thread_index_in_threadgroup]],
                  const device float4* inA [[buffer(0)]],
                  const device float4* inB [[buffer(1)]],
                  device float4* outA [[buffer(2)]],
                  device float4* outB [[buffer(3)]]) {
    threadgroup float4 a[256], b[256];
    const uint base = (group.z*256u+group.x)*256u;
    const uint upper = index+128u;
    const uint reverse0 = reverse_bits(index) >> 24u;
    const uint reverse1 = reverse_bits(upper) >> 24u;
    a[reverse0] = inA[base+index]; a[reverse1] = inA[base+upper];
    b[reverse0] = inB[base+index]; b[reverse1] = inB[base+upper];
    threadgroup_barrier(mem_flags::mem_threadgroup);
    fft256(index,a,b);
    outA[base+index] = a[index]; outA[base+upper] = a[upper];
    outB[base+index] = b[index]; outB[base+upper] = b[upper];
}

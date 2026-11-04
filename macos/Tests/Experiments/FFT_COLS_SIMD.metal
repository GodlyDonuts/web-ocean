// Register-resident first five FFT stages; see FFT_SIMD.h.
#include "FFT_SIMD.h"
inline void storeWave(uint x, uint y, uint layer, float4 a, float4 b,
                      texture2d_array<float,access::write> displacement,
                      texture2d_array<float,access::write> derivative,
                      texture2d_array<float,access::write> moments) {
    displacement.write(float4(a.x,a.z,a.y,a.w),uint2(x,y),layer);
    derivative.write(b,uint2(x,y),layer);
    moments.write(float4(b.x*b.x,b.y*b.y,b.x*b.y,0),uint2(x,y),layer);
}
kernel void main_(uint3 group [[threadgroup_position_in_grid]],
                  uint index [[thread_index_in_threadgroup]],
                  const device float4* inA [[buffer(0)]],
                  const device float4* inB [[buffer(1)]],
                  texture2d_array<float,access::write> displacement [[texture(2)]],
                  texture2d_array<float,access::write> derivative [[texture(3)]],
                  texture2d_array<float,access::write> moments [[texture(4)]]) {
    threadgroup float4 a[256], b[256];
    const uint base = group.z*256u*256u+group.x;
    const uint upper = index+128u;
    const uint reverse0 = reverse_bits(index) >> 24u;
    const uint reverse1 = reverse_bits(upper) >> 24u;
    a[reverse0] = inA[base+index*256u]; a[reverse1] = inA[base+upper*256u];
    b[reverse0] = inB[base+index*256u]; b[reverse1] = inB[base+upper*256u];
    threadgroup_barrier(mem_flags::mem_threadgroup);
    fft256(index,a,b);
    storeWave(group.x,index,group.z,a[index],b[index],displacement,derivative,moments);
    storeWave(group.x,upper,group.z,a[upper],b[upper],displacement,derivative,moments);
}

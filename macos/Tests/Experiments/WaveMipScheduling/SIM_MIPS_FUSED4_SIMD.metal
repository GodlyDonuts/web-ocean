#include <metal_stdlib>
using namespace metal;
constant bool textureStoresRTZ [[function_constant(0)]];

// Match the native texture-store rounding detected at startup at every
// former texture boundary. A plain half cast rounds to nearest even; the M1
// texture-store path instead rounds toward zero.
half4 textureHalf(float4 value) {
    half4 rounded = half4(value);
    if (!textureStoresRTZ) return rounded;
    ushort4 correction = select(ushort4(0),ushort4(1),abs(float4(rounded)) > abs(value));
    return as_type<half4>(as_type<ushort4>(rounded)-correction);
}

[[max_total_threads_per_threadgroup(64)]] kernel void main_(
    uint simdLane [[thread_index_in_simdgroup]],
    uint simdGroup [[simdgroup_index_in_threadgroup]],
    uint3 group [[threadgroup_position_in_grid]],
    texture2d_array<float,access::read> t0_0 [[texture(0)]],
    texture2d_array<float,access::write> t0_1 [[texture(1)]],
    texture2d_array<float,access::write> t0_2 [[texture(2)]],
    texture2d_array<float,access::write> t0_3 [[texture(3)]],
    texture2d_array<float,access::write> t0_4 [[texture(4)]],
    texture2d_array<float,access::read> t1_0 [[texture(5)]],
    texture2d_array<float,access::write> t1_1 [[texture(6)]],
    texture2d_array<float,access::write> t1_2 [[texture(7)]],
    texture2d_array<float,access::write> t1_3 [[texture(8)]],
    texture2d_array<float,access::write> t1_4 [[texture(9)]],
    texture2d_array<float,access::read> t2_0 [[texture(10)]],
    texture2d_array<float,access::write> t2_1 [[texture(11)]],
    texture2d_array<float,access::write> t2_2 [[texture(12)]],
    texture2d_array<float,access::write> t2_3 [[texture(13)]],
    texture2d_array<float,access::write> t2_4 [[texture(14)]]
) {
    // Pipeline admission requires threadExecutionWidth == 32. Derive a
    // logical 8x8 tile explicitly from SIMD IDs, independent of host mapping.
    const uint3 lane = uint3(simdLane & 7u,(simdLane >> 3u)+simdGroup*4u,0u);
    threadgroup half4 values0[64];
    threadgroup half4 values1[64];
    threadgroup half4 values2[64];
    if (lane.x < 8 && lane.y < 8) {
        uint2 p = (group.xy*8+lane.xy)*2;
        float4 value = 0.25f*(((t0_0.read(p,group.z)+t0_0.read(p+uint2(1,0),group.z))+t0_0.read(p+uint2(0,1),group.z))+t0_0.read(p+uint2(1,1),group.z));
        t0_1.write(value,group.xy*8+lane.xy,group.z);
        values0[0+lane.y*8+lane.x] = textureHalf(value);
    }
    if (lane.x < 8 && lane.y < 8) {
        uint2 p = (group.xy*8+lane.xy)*2;
        float4 value = 0.25f*(((t1_0.read(p,group.z)+t1_0.read(p+uint2(1,0),group.z))+t1_0.read(p+uint2(0,1),group.z))+t1_0.read(p+uint2(1,1),group.z));
        t1_1.write(value,group.xy*8+lane.xy,group.z);
        values1[0+lane.y*8+lane.x] = textureHalf(value);
    }
    if (lane.x < 8 && lane.y < 8) {
        uint2 p = (group.xy*8+lane.xy)*2;
        float4 value = 0.25f*(((t2_0.read(p,group.z)+t2_0.read(p+uint2(1,0),group.z))+t2_0.read(p+uint2(0,1),group.z))+t2_0.read(p+uint2(1,1),group.z));
        t2_1.write(value,group.xy*8+lane.xy,group.z);
        values2[0+lane.y*8+lane.x] = textureHalf(value);
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);
    // This is a whole-SIMD-group return after the only threadgroup barrier.
    // The first group computes the final three levels. Shuffles below execute
    // with all 32 lanes participating, including lanes whose store is masked.
    if (simdGroup != 0u) return;
    {
        float4 level2 = float4(0.0f);
    if (lane.x < 4 && lane.y < 4) {
        uint base = 0+lane.y*16+lane.x*2;
        float4 value = 0.25f*(((float4(values0[base])+float4(values0[base+1]))+float4(values0[base+8]))+float4(values0[base+9]));
        t0_2.write(value,group.xy*4+lane.xy,group.z);
        level2 = float4(textureHalf(value));
    }
        const ushort parent = ushort(((simdLane & 1u)*2u)+(((simdLane >> 3u)&1u)*16u));
        const float4 a = simd_shuffle(level2,parent);
        const float4 b = simd_shuffle(level2,ushort(parent+1));
        const float4 c = simd_shuffle(level2,ushort(parent+8));
        const float4 d = simd_shuffle(level2,ushort(parent+9));
        const float4 value3 = 0.25f*(((a+b)+c)+d);
        float4 level3 = float4(0.0f);
        if (lane.x < 2 && lane.y < 2) {
            t0_3.write(value3,group.xy*2+lane.xy,group.z);
            level3 = float4(textureHalf(value3));
        }
        const float4 e = simd_shuffle(level3,ushort(0));
        const float4 f = simd_shuffle(level3,ushort(1));
        const float4 g = simd_shuffle(level3,ushort(8));
        const float4 h = simd_shuffle(level3,ushort(9));
        const float4 value4 = 0.25f*(((e+f)+g)+h);
        if (lane.x < 1 && lane.y < 1) {
            t0_4.write(value4,group.xy+lane.xy,group.z);
        }
    }
    {
        float4 level2 = float4(0.0f);
    if (lane.x < 4 && lane.y < 4) {
        uint base = 0+lane.y*16+lane.x*2;
        float4 value = 0.25f*(((float4(values1[base])+float4(values1[base+1]))+float4(values1[base+8]))+float4(values1[base+9]));
        t1_2.write(value,group.xy*4+lane.xy,group.z);
        level2 = float4(textureHalf(value));
    }
        const ushort parent = ushort(((simdLane & 1u)*2u)+(((simdLane >> 3u)&1u)*16u));
        const float4 a = simd_shuffle(level2,parent);
        const float4 b = simd_shuffle(level2,ushort(parent+1));
        const float4 c = simd_shuffle(level2,ushort(parent+8));
        const float4 d = simd_shuffle(level2,ushort(parent+9));
        const float4 value3 = 0.25f*(((a+b)+c)+d);
        float4 level3 = float4(0.0f);
        if (lane.x < 2 && lane.y < 2) {
            t1_3.write(value3,group.xy*2+lane.xy,group.z);
            level3 = float4(textureHalf(value3));
        }
        const float4 e = simd_shuffle(level3,ushort(0));
        const float4 f = simd_shuffle(level3,ushort(1));
        const float4 g = simd_shuffle(level3,ushort(8));
        const float4 h = simd_shuffle(level3,ushort(9));
        const float4 value4 = 0.25f*(((e+f)+g)+h);
        if (lane.x < 1 && lane.y < 1) {
            t1_4.write(value4,group.xy+lane.xy,group.z);
        }
    }
    {
        float4 level2 = float4(0.0f);
    if (lane.x < 4 && lane.y < 4) {
        uint base = 0+lane.y*16+lane.x*2;
        float4 value = 0.25f*(((float4(values2[base])+float4(values2[base+1]))+float4(values2[base+8]))+float4(values2[base+9]));
        t2_2.write(value,group.xy*4+lane.xy,group.z);
        level2 = float4(textureHalf(value));
    }
        const ushort parent = ushort(((simdLane & 1u)*2u)+(((simdLane >> 3u)&1u)*16u));
        const float4 a = simd_shuffle(level2,parent);
        const float4 b = simd_shuffle(level2,ushort(parent+1));
        const float4 c = simd_shuffle(level2,ushort(parent+8));
        const float4 d = simd_shuffle(level2,ushort(parent+9));
        const float4 value3 = 0.25f*(((a+b)+c)+d);
        float4 level3 = float4(0.0f);
        if (lane.x < 2 && lane.y < 2) {
            t2_3.write(value3,group.xy*2+lane.xy,group.z);
            level3 = float4(textureHalf(value3));
        }
        const float4 e = simd_shuffle(level3,ushort(0));
        const float4 f = simd_shuffle(level3,ushort(1));
        const float4 g = simd_shuffle(level3,ushort(8));
        const float4 h = simd_shuffle(level3,ushort(9));
        const float4 value4 = 0.25f*(((e+f)+g)+h);
        if (lane.x < 1 && lane.y < 1) {
            t2_4.write(value4,group.xy+lane.xy,group.z);
        }
    }
}

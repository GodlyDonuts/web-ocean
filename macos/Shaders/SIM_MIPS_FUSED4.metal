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
    uint3 lane [[thread_position_in_threadgroup]],
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
    threadgroup half4 values0[84];
    if (lane.x < 8 && lane.y < 8) {
        uint2 p = (group.xy*8+lane.xy)*2;
        float4 value = 0.25f*(((t0_0.read(p,group.z)+t0_0.read(p+uint2(1,0),group.z))+t0_0.read(p+uint2(0,1),group.z))+t0_0.read(p+uint2(1,1),group.z));
        t0_1.write(value,group.xy*8+lane.xy,group.z);
        values0[0+lane.y*8+lane.x] = textureHalf(value);
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);
    if (lane.x < 4 && lane.y < 4) {
        uint base = 0+lane.y*16+lane.x*2;
        float4 value = 0.25f*(((float4(values0[base])+float4(values0[base+1]))+float4(values0[base+8]))+float4(values0[base+9]));
        t0_2.write(value,group.xy*4+lane.xy,group.z);
        values0[64+lane.y*4+lane.x] = textureHalf(value);
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);
    if (lane.x < 2 && lane.y < 2) {
        uint base = 64+lane.y*8+lane.x*2;
        float4 value = 0.25f*(((float4(values0[base])+float4(values0[base+1]))+float4(values0[base+4]))+float4(values0[base+5]));
        t0_3.write(value,group.xy*2+lane.xy,group.z);
        values0[80+lane.y*2+lane.x] = textureHalf(value);
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);
    if (lane.x < 1 && lane.y < 1) {
        uint base = 80+lane.y*4+lane.x*2;
        float4 value = 0.25f*(((float4(values0[base])+float4(values0[base+1]))+float4(values0[base+2]))+float4(values0[base+3]));
        t0_4.write(value,group.xy*1+lane.xy,group.z);
    }
    threadgroup half4 values1[84];
    if (lane.x < 8 && lane.y < 8) {
        uint2 p = (group.xy*8+lane.xy)*2;
        float4 value = 0.25f*(((t1_0.read(p,group.z)+t1_0.read(p+uint2(1,0),group.z))+t1_0.read(p+uint2(0,1),group.z))+t1_0.read(p+uint2(1,1),group.z));
        t1_1.write(value,group.xy*8+lane.xy,group.z);
        values1[0+lane.y*8+lane.x] = textureHalf(value);
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);
    if (lane.x < 4 && lane.y < 4) {
        uint base = 0+lane.y*16+lane.x*2;
        float4 value = 0.25f*(((float4(values1[base])+float4(values1[base+1]))+float4(values1[base+8]))+float4(values1[base+9]));
        t1_2.write(value,group.xy*4+lane.xy,group.z);
        values1[64+lane.y*4+lane.x] = textureHalf(value);
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);
    if (lane.x < 2 && lane.y < 2) {
        uint base = 64+lane.y*8+lane.x*2;
        float4 value = 0.25f*(((float4(values1[base])+float4(values1[base+1]))+float4(values1[base+4]))+float4(values1[base+5]));
        t1_3.write(value,group.xy*2+lane.xy,group.z);
        values1[80+lane.y*2+lane.x] = textureHalf(value);
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);
    if (lane.x < 1 && lane.y < 1) {
        uint base = 80+lane.y*4+lane.x*2;
        float4 value = 0.25f*(((float4(values1[base])+float4(values1[base+1]))+float4(values1[base+2]))+float4(values1[base+3]));
        t1_4.write(value,group.xy*1+lane.xy,group.z);
    }
    threadgroup half4 values2[84];
    if (lane.x < 8 && lane.y < 8) {
        uint2 p = (group.xy*8+lane.xy)*2;
        float4 value = 0.25f*(((t2_0.read(p,group.z)+t2_0.read(p+uint2(1,0),group.z))+t2_0.read(p+uint2(0,1),group.z))+t2_0.read(p+uint2(1,1),group.z));
        t2_1.write(value,group.xy*8+lane.xy,group.z);
        values2[0+lane.y*8+lane.x] = textureHalf(value);
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);
    if (lane.x < 4 && lane.y < 4) {
        uint base = 0+lane.y*16+lane.x*2;
        float4 value = 0.25f*(((float4(values2[base])+float4(values2[base+1]))+float4(values2[base+8]))+float4(values2[base+9]));
        t2_2.write(value,group.xy*4+lane.xy,group.z);
        values2[64+lane.y*4+lane.x] = textureHalf(value);
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);
    if (lane.x < 2 && lane.y < 2) {
        uint base = 64+lane.y*8+lane.x*2;
        float4 value = 0.25f*(((float4(values2[base])+float4(values2[base+1]))+float4(values2[base+4]))+float4(values2[base+5]));
        t2_3.write(value,group.xy*2+lane.xy,group.z);
        values2[80+lane.y*2+lane.x] = textureHalf(value);
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);
    if (lane.x < 1 && lane.y < 1) {
        uint base = 80+lane.y*4+lane.x*2;
        float4 value = 0.25f*(((float4(values2[base])+float4(values2[base+1]))+float4(values2[base+2]))+float4(values2[base+3]));
        t2_4.write(value,group.xy*1+lane.xy,group.z);
    }
}

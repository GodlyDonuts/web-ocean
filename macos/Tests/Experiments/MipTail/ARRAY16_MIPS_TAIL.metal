#include <metal_stdlib>
using namespace metal;

// Fuse only the 8 -> 4 -> 2 -> 1 tail. Every reduction uses the original
// float32 addition order and rounds to half at each former texture boundary.
half4 textureHalf(float4 value) {
    half4 rounded = half4(value);
    ushort4 correction = select(ushort4(0),ushort4(1),abs(float4(rounded)) > abs(value));
    return as_type<half4>(as_type<ushort4>(rounded)-correction);
}

void reduceTail(uint2 lane, uint layer,
                texture2d_array<float,access::read> source,
                texture2d_array<float,access::write> level4,
                texture2d_array<float,access::write> level2,
                texture2d_array<float,access::write> level1,
                threadgroup half4* values) {
    uint index = lane.y*4+lane.x;
    uint2 p = lane*2;
    float4 a = source.read(p,layer);
    float4 b = source.read(p+uint2(1,0),layer);
    float4 c = source.read(p+uint2(0,1),layer);
    float4 d = source.read(p+uint2(1,1),layer);
    float4 first = 0.25f*(((a+b)+c)+d);
    level4.write(first,lane,layer);
    values[index] = textureHalf(first);
    threadgroup_barrier(mem_flags::mem_threadgroup);
    if (lane.x < 2 && lane.y < 2) {
        uint base = lane.y*8+lane.x*2;
        float4 second = 0.25f*(((float4(values[base])+float4(values[base+1]))+float4(values[base+4]))+float4(values[base+5]));
        level2.write(second,lane,layer);
        values[16+lane.y*2+lane.x] = textureHalf(second);
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);
    if (index == 0) {
        float4 last = 0.25f*(((float4(values[16])+float4(values[17]))+float4(values[18]))+float4(values[19]));
        level1.write(last,uint2(0),layer);
    }
}

[[max_total_threads_per_threadgroup(16)]] kernel void main_(
    uint3 lane [[thread_position_in_threadgroup]],
    uint3 group [[threadgroup_position_in_grid]],
    texture2d_array<float,access::read> t0_0 [[texture(0)]],
    texture2d_array<float,access::write> t0_1 [[texture(1)]],
    texture2d_array<float,access::write> t0_2 [[texture(2)]],
    texture2d_array<float,access::write> t0_3 [[texture(3)]]
) {
    threadgroup half4 values0[20];
    reduceTail(lane.xy,group.z,t0_0,t0_1,t0_2,t0_3,values0);
}

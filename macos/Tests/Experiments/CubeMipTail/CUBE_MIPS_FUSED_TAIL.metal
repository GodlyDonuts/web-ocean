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

// Six whole-face mip levels share a threadgroup. Each former texture
// boundary is rounded independently; disjoint scratch ranges avoid races.
float4 filterTexture(texture2d_array<float,access::read> source, uint2 dst, uint face) {
    float4 acc = float4(0);
    float wsum = 0;
    const int size = int(source.get_width());
    for (int j=-1; j<=2; ++j) for (int i=-1; i<=2; ++i) {
        int2 q = clamp(int2(dst)*2+int2(i,j),int2(0),int2(size-1));
        float w = ((i==0 || i==1) ? 3.0f : 1.0f)*((j==0 || j==1) ? 3.0f : 1.0f);
        acc = acc + source.read(uint2(q),face)*w;
        wsum = wsum + w;
    }
    return acc/float4(wsum);
}
void filterShared(uint tid, uint outSize, uint inputOffset, uint outputOffset,
                  uint face, threadgroup half4* values,
                  texture2d_array<float,access::write> destination) {
    if (tid >= outSize*outSize) return;
    const uint2 dst = uint2(tid%outSize,tid/outSize);
    const int size = int(outSize*2);
    float4 acc = float4(0);
    float wsum = 0;
    for (int j=-1; j<=2; ++j) for (int i=-1; i<=2; ++i) {
        int2 q = clamp(int2(dst)*2+int2(i,j),int2(0),int2(size-1));
        float w = ((i==0 || i==1) ? 3.0f : 1.0f)*((j==0 || j==1) ? 3.0f : 1.0f);
        acc = acc + float4(values[inputOffset+uint(q.y)*uint(size)+uint(q.x)])*w;
        wsum = wsum + w;
    }
    float4 value = acc/float4(wsum);
    destination.write(value,dst,face);
    if (outSize > 1) values[outputOffset+tid] = textureHalf(value);
}
[[max_total_threads_per_threadgroup(256)]] kernel void main_(
    uint tid [[thread_index_in_threadgroup]], uint3 group [[threadgroup_position_in_grid]],
    texture2d_array<float,access::read> source [[texture(0)]],
    texture2d_array<float,access::write> level32 [[texture(1)]],
    texture2d_array<float,access::write> level16 [[texture(2)]],
    texture2d_array<float,access::write> level8 [[texture(3)]],
    texture2d_array<float,access::write> level4 [[texture(4)]],
    texture2d_array<float,access::write> level2 [[texture(5)]],
    texture2d_array<float,access::write> level1 [[texture(6)]],
    constant float4* frame [[buffer(7)]]
) {
    const uint face = (uint(clamp(frame[5].w,0.0f,4294967000.0f))+group.z)%6u;
    threadgroup half4 values[1364];
    for (uint index=tid; index<1024; index+=256) {
        uint2 dst = uint2(index%32,index/32);
        float4 value = filterTexture(source,dst,face);
        level32.write(value,dst,face);
        values[index] = textureHalf(value);
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);
    filterShared(tid,16,0,1024,face,values,level16);
    threadgroup_barrier(mem_flags::mem_threadgroup);
    filterShared(tid,8,1024,1280,face,values,level8);
    threadgroup_barrier(mem_flags::mem_threadgroup);
    filterShared(tid,4,1280,1344,face,values,level4);
    threadgroup_barrier(mem_flags::mem_threadgroup);
    filterShared(tid,2,1344,1360,face,values,level2);
    threadgroup_barrier(mem_flags::mem_threadgroup);
    filterShared(tid,1,1360,0,face,values,level1);
}

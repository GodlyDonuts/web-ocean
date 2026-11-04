#include <metal_stdlib>
using namespace metal;
// One GPU thread follows the displaced height field at the fixed camera.
// Invert horizontal chop as well as sampling height; no CPU readback.
kernel void main_(constant float4* F [[buffer(0)]],
    texture2d_array<float> displacement [[texture(1)]],sampler repeatSampler [[sampler(2)]],
    device float4* state [[buffer(3)]]) {
    float2 camera=F[4].xz, q=camera;
    float3 wave=0;
    for (uint iteration=0;iteration<8;iteration++) {
        wave=0;
        for (uint c=0;c<6;c++)
            wave+=displacement.sample(repeatSampler,q*F[12+c/4][c%4],c,level(0)).xyz;
        q=mix(q,camera-wave.xz,0.5);
    }
    wave=0;
    for (uint c=0;c<6;c++)
        wave+=displacement.sample(repeatSampler,q*F[12+c/4][c%4],c,level(0)).xyz;
    float depth=wave.y-F[4].y;
    state[0]=float4(wave.y,depth,smoothstep(-0.12,0.25,depth),0);
}

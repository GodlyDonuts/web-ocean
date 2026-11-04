// Frame-invariant lighting, calculated with the same sampling and arithmetic as
// the ocean fragment shader. Float32 storage preserves the sampled radiance.
#include <metal_stdlib>
using namespace metal;

kernel void main_(constant float4* frame [[buffer(0)]],
                  texture2d<float> transmittance [[texture(1)]],
                  texturecube<float> environment [[texture(2)]],
                  sampler linearClamp [[sampler(3)]],
                  const device float* sunVisibility [[buffer(4)]],
                  texture2d<float,access::write> output [[texture(5)]]) {
    // Only cache raw cube samples; retain downstream fragment arithmetic.
    output.write(environment.sample(linearClamp,float3(0,1,0),level(7.0f)),uint2(0,0));
    output.write(environment.sample(linearClamp,float3(0.94f,0.34f,0),level(6.0f)),uint2(1,0));
    output.write(environment.sample(linearClamp,float3(-0.94f,0.34f,0),level(6.0f)),uint2(2,0));
    output.write(environment.sample(linearClamp,float3(0,0.34f,0.94f),level(6.0f)),uint2(3,0));
    output.write(environment.sample(linearClamp,float3(0,0.34f,-0.94f),level(6.0f)),uint2(4,0));
}

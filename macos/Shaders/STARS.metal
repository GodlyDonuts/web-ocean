#include <metal_stdlib>
using namespace metal;
struct StarVertex {
    float4 position [[position]];
    float2 uv;
    float3 color [[flat]];
};
vertex StarVertex vs(uint vertexIndex [[vertex_id]],uint starIndex [[instance_id]],
    constant float4* F [[buffer(0)]],const device float4* catalogue [[buffer(1)]]) {
    float4 star=catalogue[starIndex];
    float3 dir=F[43].xyz*star.x+F[44].xyz*star.y+F[45].xyz*star.z;
    float forward=dot(dir,F[7].xyz);
    StarVertex out;
    out.uv=vertexIndex==0 ? float2(-1,-1) : vertexIndex==1 ? float2(3,-1) : float2(-1,3);
    if (forward<=0.0 || dir.y<=0.0) { out.position=float4(2,2,0,1);out.color=0;return out; }
    float radius=1.55+sqrt(star.w)*0.16;
    float2 clip=float2(dot(dir,F[5].xyz)/dot(F[5].xyz,F[5].xyz),dot(dir,F[6].xyz)/dot(F[6].xyz,F[6].xyz));
    out.position=float4(clip+out.uv*radius*2.0*F[9].zw*forward,0.0,forward);
    float pixelAngle=2.0*length(F[6].xyz)*F[9].w;
    float flux=star.w*0.0000068/(pixelAngle*pixelAngle);
    float sigma=radius*0.30;
    float peak=flux/(6.283185307*sigma*sigma);
    float temperature=fract(sin(float(starIndex)*12.9898+0.31)*43758.5453);
    float3 tint=mix(float3(1.0,0.84,0.69),float3(0.77,0.86,1.0),smoothstep(0.12,0.82,temperature));
    float moonWash=F[39].w*F[39].w*smoothstep(0.0,0.15,F[39].y)*pow(max(0.0,dot(dir,F[39].xyz)),8.0);
    out.color=mix(tint,float3(1.0),0.35)*peak*pow(F[40].z,3.0)*exp(-0.06/max(dir.y,0.015))*(1.0-moonWash*0.5);
    return out;
}
fragment float4 fs(StarVertex in [[stage_in]],
    constant float4* F [[buffer(0)]],const device float4* water [[buffer(1)]],texture2d<float> cloudMask [[texture(2)]],sampler linearClamp [[sampler(3)]]) {
    float r2=dot(in.uv,in.uv);
    float profile=exp(-r2/(2.0*0.30*0.30))*(1.0-smoothstep(0.75,1.0,r2));
    float transmission=cloudMask.sample(linearClamp,in.position.xy*F[9].zw).a;
    float visibility=transmission*smoothstep(0.45,0.95,transmission);
    return float4(in.color*profile*visibility*(1.0-water[0].z),0.0);
}

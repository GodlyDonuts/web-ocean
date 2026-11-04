#include <metal_stdlib>
using namespace metal;
struct RainVertex {
    float4 position [[position]];
    float2 uv;
    float opacity [[flat]];
    float distance [[flat]];
};
uint rainHash(uint x) { x^=x>>16;x*=2246822519u;x^=x>>13;x*=3266489917u;return x^(x>>16); }
float randomRain(uint x) { return float(rainHash(x)&0xffffffu)/16777216.0; }
vertex RainVertex vs(uint v [[vertex_id]],uint id [[instance_id]],
    constant float4* F [[buffer(0)]],constant float4* R [[buffer(1)]]) {
    RainVertex out;
    float seed=randomRain(id*7u+1u);
    float density=R[3].y;
    float opacity=smoothstep(seed-0.03,seed+0.03,density)*smoothstep(0.0,0.03,density);
    float3 p=float3(randomRain(id*7u+2u)*200.0,randomRain(id*7u+3u)*64.0,randomRain(id*7u+4u)*200.0);
    uint bucket=id&7u;
    p.x=fract((p.x+R[0].x)/200.0)*200.0-100.0;
    p.z=-(fract((p.z-R[0].y)/200.0)*200.0+1.5);
    p.y=fract((p.y-R[1+bucket/4][bucket&3u])/64.0)*64.0-4.0;
    float3 rel=p-float3(0,F[4].y,0);
    float3 velocity=float3(R[0].z,-(20.0+float(bucket)),R[0].w);
    float shutter=0.009+randomRain(id*7u+5u)*0.009;
    float4x4 projection=float4x4(F[0],F[1],F[2],F[3]);
    float4 head=projection*float4(rel,1);
    float4 tail=projection*float4(rel-velocity*shutter,1);
    float2 corners[6]={float2(-1,0),float2(1,0),float2(-1,1),float2(-1,1),float2(1,0),float2(1,1)};
    float2 c=corners[v];out.uv=c;
    out.distance=length(rel);
    float fade=smoothstep(2.0,8.0,-p.z)*(1.0-smoothstep(150.0,200.0,-p.z))
        *(1.0-smoothstep(85.0,100.0,abs(p.x)))*(1.0-smoothstep(50.0,60.0,p.y));
    if (head.w<0.2 || tail.w<0.2 || opacity*fade<0.001) {
        out.position=float4(2,2,0,1);out.opacity=0;return out;
    }
    float2 line=(tail.xy/tail.w-head.xy/head.w)*F[9].xy;
    float2 across=normalize(float2(-line.y,line.x)+float2(0.00001,0));
    float4 clip=mix(head,tail,c.y);
    float worldPixels=0.0025*F[9].y/(2.0*length(F[6].xyz)*head.w);
    float radius=max(0.5,worldPixels);
    clip.xy+=across*c.x*radius*2.0*F[9].zw*clip.w;
    out.position=clip;
    // Conserve energy for subpixel drops instead of painting every far drop
    // with the same opaque screen-space dash.
    out.opacity=opacity*fade*min(1.0,worldPixels/radius)*exp(-out.distance*0.006)*0.9;
    return out;
}
fragment float4 fs(RainVertex in [[stage_in]],constant float4* F [[buffer(0)]],
    constant float4* R [[buffer(1)]],texturecube<float> environment [[texture(2)]],sampler clampSampler [[sampler(3)]],const device float4* water [[buffer(4)]]) {
    float cross=exp(-in.uv.x*in.uv.x*3.0);
    float tail=smoothstep(0.0,0.10,in.uv.y)*(1.0-smoothstep(0.5,1.0,in.uv.y));
    float alpha=in.opacity*cross*tail*(1.0-water[0].z);
    // Refraction/scattering borrows the surrounding HDR sky's illumination.
    float3 illumination=environment.sample(clampSampler,float3(0,0.25,-1),level(3)).rgb;
    illumination=illumination*2.5+mix(float3(0.08,0.10,0.12),float3(0.012,0.020,0.030),F[40].z);
    illumination+=R[3].x*float3(0.7,0.8,1.0);
    return float4(illumination*alpha,alpha);
}

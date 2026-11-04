// Crepuscular rays: a radial march toward the sun over the quarter-resolution
// scene, added into the 1/8 bloom level so the bloom up-chain smooths it.
// Skipped on the CPU whenever the sun is not near the frame.
#include <metal_stdlib>
using namespace metal;

struct ShaftParams {
    float4 sun;   // sun uv, strength, horizon v
    float4 shape; // aspect, threshold, decay, unused
};
struct VSOut {
    float4 pos [[position]];
    float2 uv;
};
vertex VSOut vs(uint i [[vertex_id]]) {
    float2 p = float2(float((i << 1u) & 2u), float(i & 2u));
    VSOut o;
    o.pos = float4(p * 2.0 - 1.0, 0.0, 1.0);
    o.uv = float2(p.x, 1.0 - p.y);
    return o;
}
fragment float4 fs(VSOut in [[stage_in]],
                   texture2d<float, access::sample> scene [[texture(0)]],
                   sampler samp [[sampler(1)]],
                   constant ShaftParams& S [[buffer(2)]]) {
    const int taps = 28;
    float2 sun = S.sun.xy;
    float horizon = S.sun.w;
    float aspect = S.shape.x;
    float2 delta = (sun - in.uv) / float(taps);
    float jitter = fract(52.982918 * fract(dot(in.pos.xy, float2(0.06711056, 0.00583715))));
    float2 p = in.uv + delta * jitter;
    float3 sum = float3(0.0);
    float weight = 1.0;
    for (int k = 0; k < taps; ++k) {
        if (p.y < horizon && all(p >= 0.0) && all(p <= 1.0)) {
            float3 c = scene.sample(samp, p, level(0.0)).xyz;
            float lum = dot(c, float3(0.2126, 0.7152, 0.0722));
            float2 d = (p - sun) * float2(aspect, 1.0);
            float lit = min(max(lum - S.shape.y, 0.0), 6.0 * S.shape.y);
            sum += c * (lit / max(lum, 1e-4)) * exp(-dot(d, d) * 5.0) * weight;
        }
        weight *= S.shape.z;
        p += delta;
    }
    float2 d = (in.uv - sun) * float2(aspect, 1.0);
    float reach = exp(-length(d) * 1.4);
    float below = in.uv.y > horizon ? 0.45 : 1.0;
    return float4(sum * (S.sun.z / float(taps)) * reach * below, 0.0);
}

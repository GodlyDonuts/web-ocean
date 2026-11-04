// Seabird flocks: a loose V of gull silhouettes crossing the view at dawn,
// dusk and occasionally by day. Geometry is generated in the vertex shader
// (3 triangles per wing, one instance per bird); the CPU only schedules flocks.
#include <metal_stdlib>
using namespace metal;

struct Flock {
    float4 a; // crossing seconds from mid-view, seed, direction, animation seconds
    float4 b; // silhouette radiance, opacity
};
struct BirdOut {
    float4 position [[position]];
};
constant float3 kWing[5] = {
    float3(0.0, 0.14, 0.0), float3(0.0, -0.12, 0.0), float3(0.42, 0.0, 0.0),
    float3(0.40, -0.13, 0.0), float3(0.78, -0.2, 0.0)
};
constant ushort kWingIndex[9] = {0, 1, 2, 2, 1, 3, 2, 3, 4};

inline float birdHash(float x, float y) {
    return fract(sin(x * 12.9898 + y * 78.233) * 43758.5453);
}
vertex BirdOut vs(uint v [[vertex_id]], uint id [[instance_id]],
                  constant float4* F [[buffer(0)]], constant Flock& B [[buffer(1)]]) {
    float4x4 viewProj = float4x4(F[0], F[1], F[2], F[3]);
    float3 cam = F[4].xyz;
    float3 fwd = normalize(float3(F[7].x, 0.0, F[7].z) + float3(0.0, 0.0, -1e-4));
    float3 right = normalize(float3(F[5].x, 0.0, F[5].z) + float3(1e-4, 0.0, 0.0));
    float s = B.a.y, t = B.a.w;
    float distance = 70.0 + 70.0 * birdHash(s, 1.0);
    float height = 14.0 + 22.0 * birdHash(s, 2.0);
    float3 head = normalize(right * B.a.z + fwd * (birdHash(s, 3.0) - 0.5) * 0.7);
    float3 side = normalize(cross(float3(0.0, 1.0, 0.0), head));
    float3 center = float3(cam.x, 0.0, cam.z) + fwd * distance + float3(0.0, height, 0.0) + head * (B.a.x * 11.0);
    float fi = float(id);
    float r1 = birdHash(fi, s + 4.0), r2 = birdHash(fi, s + 5.0), r3 = birdHash(fi, s + 6.0);
    float lane = (r1 - 0.5) * 2.0;
    float along = -abs(lane) * 16.0 + (r2 - 0.5) * 6.0 + sin(t * 0.31 + fi * 1.7) * 1.5;
    float lateral = lane * 24.0 + sin(t * 0.23 + fi * 2.3) * 1.2;
    float rise = (r3 - 0.5) * 7.0 + sin(t * 0.4 + fi) * 1.0;
    float3 body = center + head * along + side * lateral + float3(0.0, rise, 0.0);
    // Bursts of flapping between glides; gliding wings hold a slight dihedral.
    float phase = t * (2.4 + 1.2 * r2) * 6.2831853 + r1 * 40.0;
    float flapping = smoothstep(-0.2, 0.4, sin(t * 0.35 + r3 * 20.0));
    float amp = mix(0.08, 1.0, flapping);
    float elbow = 0.12 * sin(phase) * amp + 0.04;
    float tip = 0.34 * sin(phase - 0.7) * amp + 0.08 * (1.0 - flapping);
    uint k = kWingIndex[v % 9u];
    float3 p = kWing[k];
    p.z = k >= 4u ? tip : (k >= 2u ? elbow : 0.0);
    float sx = v < 9u ? -1.0 : 1.0;
    float span = 1.5 * (0.8 + 0.4 * r1);
    float3 world = body + side * (p.x * sx * span) + head * (p.y * span) + float3(0.0, p.z * span, 0.0);
    BirdOut out;
    out.position = viewProj * float4(world, 1.0);
    return out;
}
fragment float4 fs(BirdOut in [[stage_in]], constant Flock& B [[buffer(1)]]) {
    return float4(B.b.xyz * B.b.w, B.b.w);
}

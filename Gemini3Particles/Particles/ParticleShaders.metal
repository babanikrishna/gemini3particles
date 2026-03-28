#include <metal_stdlib>
using namespace metal;

// MARK: - Shared Types

struct Particle {
    float2 position;
    float2 velocity;
    float2 startPos;
    float2 targetPos;
    float4 color;
    float4 startColor;
    float4 targetColor;
    float size;
    float wobble;
    float alpha;
    float fadeTarget;
};

struct Uniforms {
    float2 touchPos;
    float2 viewSize;
    float2 parallaxOffset;
    float time;
    float elapsed;
    float touchRadius;
    float touchForce;
    float returnSpeed;
    float friction;
    float formationDurationMs;
    float wobbleScale;
    float audioLevel;
    float soundReactive;
    uint particleCount;
    uint _pad;
};

struct StarData {
    float2 position;
    float size;
    float speed;
    float phase;
    float baseAlpha;
};

// MARK: - Helpers

float easeInOutCubic(float x) {
    return x < 0.5 ? 4.0 * x * x * x : 1.0 - pow(-2.0 * x + 2.0, 3.0) / 2.0;
}

// MARK: - Compute: Update Particles

kernel void updateParticles(
    device Particle *particles [[buffer(0)]],
    constant Uniforms &u [[buffer(1)]],
    uint id [[thread_position_in_grid]]
) {
    if (id >= u.particleCount) return;

    device Particle &p = particles[id];

    // Smooth fade in/out — always runs
    if (p.alpha != p.fadeTarget) {
        p.alpha += (p.fadeTarget - p.alpha) * 0.08;
        if (abs(p.alpha - p.fadeTarget) < 0.01) p.alpha = p.fadeTarget;
    }

    // Skip fully invisible particles
    if (p.alpha < 0.001 && p.fadeTarget < 0.001) return;

    // Formation phase
    if (u.elapsed < u.formationDurationMs) {
        float progress = u.elapsed / u.formationDurationMs;
        float t = easeInOutCubic(progress);

        p.color = mix(p.startColor, p.targetColor, t);
        p.position = mix(p.startPos, p.targetPos, t);
        p.position.x += sin(u.time * 0.002 + p.wobble) * 0.2;
        p.position.y += cos(u.time * 0.003 + p.wobble) * 0.2;
        p.velocity = float2(0);
        return;
    }

    // Post-formation: color is at target
    p.color = p.targetColor;

    float2 center = u.viewSize * 0.5;
    float distCenter = length(p.position - center);
    float maxDist = min(u.viewSize.x, u.viewSize.y) * 0.8;
    float stability = clamp(distCenter / maxDist, 0.0, 1.0);
    stability *= stability;

    float2 diff = p.targetPos - p.position;

    float wobbleAmp = (0.01 + stability * 0.5) * u.wobbleScale;
    float wx = sin(u.time * 0.0002 + p.wobble) * wobbleAmp;
    float wy = cos(u.time * 0.0003 + p.wobble) * wobbleAmp;
    float2 accel = diff * u.returnSpeed + float2(wx, wy);

    // Touch repulsion
    float2 toTouch = p.position - u.touchPos;
    float touchDist = length(toTouch);
    if (touchDist < u.touchRadius && touchDist > 0) {
        float force = (u.touchRadius - touchDist) / u.touchRadius;
        float2 dir = normalize(toTouch);
        float pushMag = 0.1 + stability * 0.1;
        float pushForce = force * u.touchForce * 2.5 * pushMag;
        accel += dir * pushForce;
    }

    p.velocity = (p.velocity + accel) * u.friction;
    p.position += p.velocity;

    // Sound reactive — uniform pulse
    if (u.soundReactive > 0.5 && u.audioLevel > 0.05) {
        float pulse = 1.0 + u.audioLevel * 0.08;
        p.position = center + (p.position - center) * pulse;
    }
}

// MARK: - Vertex/Fragment: Particle Rendering

struct ParticleVertexOut {
    float4 position [[position]];
    float pointSize [[point_size]];
    float4 color;
    float alpha;
};

vertex ParticleVertexOut particleVertex(
    const device Particle *particles [[buffer(0)]],
    constant float2 &viewSize [[buffer(1)]],
    constant float2 &parallax [[buffer(2)]],
    constant float &displayScale [[buffer(3)]],
    uint vid [[vertex_id]]
) {
    ParticleVertexOut out;
    const device Particle &p = particles[vid];

    float depthFactor = clamp((p.size - 1.5) / 2.0, 0.0, 1.0);
    float2 pos = p.position;
    pos += parallax * depthFactor;

    // Pixel coords to NDC
    float2 ndc;
    ndc.x = (pos.x / viewSize.x) * 2.0 - 1.0;
    ndc.y = 1.0 - (pos.y / viewSize.y) * 2.0;

    out.position = float4(ndc, 0.0, 1.0);
    float drawSize = p.size * (0.85 + depthFactor * 0.3);
    out.pointSize = max(drawSize * 2.0 * displayScale, 1.0);
    out.color = p.color;
    out.alpha = p.alpha;
    return out;
}

fragment float4 particleFragment(
    ParticleVertexOut in [[stage_in]],
    float2 pointCoord [[point_coord]]
) {
    float dist = length(pointCoord - float2(0.5));
    if (dist > 0.5) discard_fragment();
    float softness = smoothstep(0.5, 0.42, dist);
    return float4(in.color.rgb, softness * in.alpha);
}

// MARK: - Background Stars

struct StarVertexOut {
    float4 position [[position]];
    float pointSize [[point_size]];
    float alpha;
};

vertex StarVertexOut starVertex(
    const device StarData *stars [[buffer(0)]],
    constant float2 &viewSize [[buffer(1)]],
    constant float &time [[buffer(2)]],
    constant float2 &parallax [[buffer(3)]],
    constant float &displayScale [[buffer(4)]],
    uint vid [[vertex_id]]
) {
    StarVertexOut out;
    const device StarData &s = stars[vid];

    float pulse = sin(time * 0.002 * s.speed + s.phase) * 0.5 + 0.5;
    float a = s.baseAlpha * (0.2 + pulse * 0.8);

    float2 pos = s.position - parallax * 0.2;
    float2 ndc;
    ndc.x = (pos.x / viewSize.x) * 2.0 - 1.0;
    ndc.y = 1.0 - (pos.y / viewSize.y) * 2.0;

    out.position = float4(ndc, 0.0, 1.0);
    out.pointSize = max(s.size * 2.0 * displayScale, 1.0);
    out.alpha = a;
    return out;
}

fragment float4 starFragment(
    StarVertexOut in [[stage_in]],
    float2 pointCoord [[point_coord]]
) {
    float dist = length(pointCoord - float2(0.5));
    if (dist > 0.5) discard_fragment();
    float softness = smoothstep(0.5, 0.15, dist);
    return float4(1.0, 1.0, 1.0, softness * in.alpha);
}

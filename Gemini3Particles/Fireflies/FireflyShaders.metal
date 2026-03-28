#include <metal_stdlib>
using namespace metal;

// MARK: - Structs

struct Firefly {
    float2 position;
    float2 velocity;
    float4 color;
    float phase;
    float frequency;
    float size;
    float brightness;
    float2 target;
    float hasTarget;
    float padding;
};

struct FireflyUniforms {
    float2 viewSize;
    float time;
    float displayScale;
};

struct FireflySimUniforms {
    float2 viewSize;
    float time;
    float deltaTime;
    float2 touchPos;
    float isTouching;
    uint particleCount;
};

struct FireflyVertexOut {
    float4 position [[position]];
    float pointSize [[point_size]];
    float4 color;
    float brightness;
};

// MARK: - Compute: GPU Simulation

kernel void updateFireflies(
    device Firefly *flies [[buffer(0)]],
    constant FireflySimUniforms &u [[buffer(1)]],
    uint id [[thread_position_in_grid]]
) {
    if (id >= u.particleCount) return;

    Firefly f = flies[id];
    float t = u.time;

    // Per-fly deterministic random values (from phase) — 6 unique randoms
    float r1 = fract(sin(f.phase * 127.1) * 43758.5);
    float r2 = fract(sin(f.phase * 311.7) * 43758.5);
    float r3 = fract(sin(f.phase * 269.3) * 43758.5);
    float r4 = fract(sin(f.phase * 419.2) * 43758.5);
    float r5 = fract(sin(f.phase * 631.5) * 43758.5);
    float r6 = fract(sin(f.phase * 547.9) * 43758.5);

    // === BRIGHTNESS ===
    float targetB;
    if (f.hasTarget > 0.5) {
        // Targeted: smooth glow with gentle variation
        float pulse  = sin(t * f.frequency * (1.2 + r1 * 1.6) + f.phase);
        float pulse2 = sin(t * f.frequency * (0.3 + r2 * 0.8) + f.phase * 2.1);
        float flashSeed = sin(t * (6.0 + r3 * 8.0) + f.phase * 13.7 + r4 * 100.0);
        float flash = flashSeed > 0.92 ? 1.0 : 0.0;
        targetB = 0.5 + 0.35 * ((pulse + 1.0) * 0.5)
                + 0.1 * ((pulse2 + 1.0) * 0.5) + flash * 0.25;
    } else {
        // Scattered: real firefly flash — mostly dark, brief bright flashes
        // Each fly has a unique flash period (2–7 seconds) using multiple randoms
        float flashPeriod = 2.0 + r1 * 3.0 + r4 * 2.0;
        // Unique phase offset from multiple sources to prevent sync
        float flashPhase = r2 + r5 * 0.37 + r3 * 0.61;
        float flashCycle = fract(t / flashPeriod + flashPhase);

        // Sharp flash: dark most of the time, brief bright peak (~12% of cycle)
        float flashOn = smoothstep(0.0, 0.03, flashCycle)
                      * (1.0 - smoothstep(0.08, 0.12, flashCycle));

        // Some flies do double-flash (real fireflies often pulse twice)
        // Unique gap between first and second flash per fly
        float dblStart = 0.15 + r6 * 0.05;
        float dblEnd = dblStart + 0.07 + r1 * 0.04;
        float doubleFlash = smoothstep(dblStart, dblStart + 0.03, flashCycle)
                          * (1.0 - smoothstep(dblEnd, dblEnd + 0.04, flashCycle));
        float doDouble = step(0.4, r3);  // ~60% of flies do double flash
        flashOn = max(flashOn, doubleFlash * doDouble);

        // Dim ambient glow between flashes so they don't disappear completely
        float ambient = 0.03 + r4 * 0.05;

        targetB = ambient + flashOn * (0.7 + r5 * 0.3);
    }

    f.brightness += (targetB - f.brightness) * 0.12;

    // === MOVEMENT ===
    // Per-fly movement personality
    float moveSpeed = 0.3 + r5 * 1.4;          // some crawl (0.3x), some zip (1.7x)
    float moveDamp  = 0.984 + r6 * 0.012;      // damping 0.984–0.996
    float moveAmp   = 0.04 + r5 * 0.16;        // amplitude 0.04–0.20 (wide range)

    // Per-fly directional preference (some drift left, some right, some up...)
    float biasAngle = r4 * 6.283;
    float2 driftBias = float2(cos(biasAngle), sin(biasAngle)) * 0.004 * moveSpeed;

    // Per-fly unique drift frequencies
    float driftF1 = 0.4 + r1 * 0.8;
    float driftF2 = 0.8 + r2 * 1.2;
    float driftF3 = 0.3 + r3 * 0.6;
    float driftF4 = 0.5 + r4 * 1.0;

    float wx = sin(t * driftF1 * moveSpeed + f.phase * 2.3) * moveAmp
             + sin(t * driftF2 * moveSpeed + f.phase * 0.7) * moveAmp * 0.5;
    float wy = cos(t * driftF3 * moveSpeed + f.phase * 1.7) * moveAmp * 0.85
             + cos(t * driftF4 * moveSpeed + f.phase * 3.1) * moveAmp * 0.4;

    if (f.hasTarget > 0.5) {
        // --- Naturalistic firefly flight toward target ---
        // Real fireflies: unhurried, arc-like paths, gentle flutter,
        // soft approach with tiny overshoot + self-correct (critically damped)
        float2 toTarget = f.target - f.position;
        float dist = length(toTarget);

        if (dist > 1.5) {
            float2 dir = toTarget / max(dist, 0.001);

            // Perpendicular vector for lateral drift (fireflies arc, not beeline)
            float2 perp = float2(-dir.y, dir.x);

            // Per-fly cruise speed — moderate, unhurried (real fireflies ~0.3 m/s)
            float cruiseSpeed = 2.0 + r1 * 1.5;

            // Gentle S-curve: gradual ramp up, soft ease down on approach
            float rampUp = smoothstep(0.0, 30.0, dist);      // soft start if just spawned nearby
            float easeDown = smoothstep(0.0, 20.0, dist);     // gentle slow-down on approach
            float speed = cruiseSpeed * rampUp * easeDown;

            // Lateral flutter while traveling — sine drift perpendicular to heading
            // Creates that characteristic meandering arc
            float flutterFreq = 2.5 + r2 * 2.0;
            float flutterAmp = (0.3 + r3 * 0.4) * min(dist / 15.0, 1.0); // fade near target
            float flutter = sin(t * flutterFreq + f.phase * 5.3) * flutterAmp;

            float2 desired = dir * speed + perp * flutter;

            // Smooth steering — low value = gradual turns (natural)
            float steer = 0.08 + r4 * 0.04; // 0.08–0.12
            f.velocity = mix(f.velocity, desired, steer);
        } else {
            // Arrived — gentle critically-damped settle (tiny overshoot OK)
            float2 correction = toTarget * 0.06; // soft pull to exact spot
            f.velocity = f.velocity * 0.88 + correction;
        }

        // Elliptical orbit around target (unique per fly)
        float orbitSpeed = 0.5 + r1 * 0.7;
        float orbitAngle = t * orbitSpeed + f.phase;
        float2 orbit = float2(cos(orbitAngle) * (1.2 + r2 * 2.8),
                              sin(orbitAngle * 0.7 + f.phase) * (0.8 + r3 * 2.0));
        float hoverCycle = t * (0.25 + r1 * 0.2) + f.phase;
        float hoverAct = pow(max(sin(hoverCycle), 0.0), 4.0);
        float orbitStr = 0.3 + hoverAct * 0.7;
        float2 hoverDrift = orbit * 0.06 * orbitStr;

        // Vertical bob — fireflies bob gently in air
        float bob = sin(t * (0.4 + r6 * 0.5) + f.phase * 2.7) * 0.6;

        // Occasional wander burst
        float arcAngle = t * (0.3 + r2 * 0.7) + f.phase * 6.283;
        float2 wander = float2(cos(arcAngle), sin(arcAngle)) * hoverAct * 0.15;

        f.position += f.velocity + hoverDrift + float2(0.0, bob * 0.03) + wander;
    } else {
        // --- Free scatter: per-fly unique speed, damping, direction ---
        f.velocity += float2(wx, wy) * 0.08 + driftBias;
        f.velocity *= moveDamp;
        f.position += f.velocity;
    }

    // Touch scatter + flash
    if (u.isTouching > 0.5) {
        float2 toFly = f.position - u.touchPos;
        float touchDist = length(toFly);
        if (touchDist < 120.0 && touchDist > 0.1) {
            float force = (120.0 - touchDist) / 120.0;
            f.velocity += (toFly / touchDist) * force * 3.0;
            f.brightness = min(f.brightness + force * 0.5, 1.0);
        }
    }

    // Edge wrap
    float margin = 40.0;
    float w = u.viewSize.x;
    float h = u.viewSize.y;
    if (f.position.x < -margin) f.position.x += w + margin * 2.0;
    if (f.position.x > w + margin) f.position.x -= w + margin * 2.0;
    if (f.position.y < -margin) f.position.y += h + margin * 2.0;
    if (f.position.y > h + margin) f.position.y -= h + margin * 2.0;

    // Speed limit
    float speed = length(f.velocity);
    if (speed > 4.0) f.velocity = (f.velocity / speed) * 4.0;

    flies[id] = f;
}

// MARK: - Vertex Shader (point sprites — 1 vertex per firefly)

vertex FireflyVertexOut fireflyVertex(
    const device Firefly *flies [[buffer(0)]],
    constant FireflyUniforms &u [[buffer(1)]],
    uint vid [[vertex_id]]
) {
    FireflyVertexOut out;
    const device Firefly &f = flies[vid];

    float2 ndc;
    ndc.x = (f.position.x / u.viewSize.x) * 2.0 - 1.0;
    ndc.y = 1.0 - (f.position.y / u.viewSize.y) * 2.0;
    out.position = float4(ndc, 0.0, 1.0);

    float radius = f.size * (0.5 + f.brightness * 0.5);
    out.pointSize = max(radius * 2.0 * u.displayScale, 1.0);

    out.color = f.color;
    out.brightness = f.brightness;
    return out;
}

// MARK: - Fragment Shader (point_coord: 0-1 range)

fragment float4 fireflyFragment(
    FireflyVertexOut in [[stage_in]],
    float2 pointCoord [[point_coord]]
) {
    float dist = length(pointCoord - float2(0.5)) * 2.0; // 0 at center, 1 at edge
    if (dist > 1.0) discard_fragment();

    float d2 = dist * dist;
    float b = in.brightness;

    // Crisp glow — punchy core, tight ring, clean falloff
    float core  = exp(-d2 * 50.0);
    float inner = exp(-d2 * 14.0);
    float outer = exp(-d2 * 4.0);

    float3 glowColor = in.color.rgb;
    float3 coreColor = mix(glowColor, float3(1.0), 0.25);

    float3 color = coreColor * core * 1.2 * b
                 + glowColor * inner * 0.9 * b
                 + glowColor * outer * 0.3 * b;

    float alpha = (core * 1.2 + inner * 0.7 + outer * 0.15) * b;
    alpha = min(alpha, 1.0);

    return float4(color, alpha);
}

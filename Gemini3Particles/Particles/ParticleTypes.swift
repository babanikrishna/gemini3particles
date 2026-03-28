//
//  ParticleTypes.swift
//  Gemini3Particles
//

import simd

// MARK: - GPU-Matching Structs

struct ParticleData {
    var position: SIMD2<Float>
    var velocity: SIMD2<Float>
    var startPos: SIMD2<Float>
    var targetPos: SIMD2<Float>
    var color: SIMD4<Float>
    var startColor: SIMD4<Float>
    var targetColor: SIMD4<Float>
    var size: Float
    var wobble: Float
    var alpha: Float
    var fadeTarget: Float
}

struct ParticleUniforms {
    var touchPos: SIMD2<Float>
    var viewSize: SIMD2<Float>
    var parallaxOffset: SIMD2<Float>
    var time: Float
    var elapsed: Float
    var touchRadius: Float
    var touchForce: Float
    var returnSpeed: Float
    var friction: Float
    var formationDurationMs: Float
    var wobbleScale: Float
    var audioLevel: Float
    var soundReactive: Float
    var particleCount: UInt32
    var _pad: UInt32 = 0
}

struct StarData {
    var position: SIMD2<Float>
    var size: Float
    var speed: Float
    var phase: Float
    var baseAlpha: Float
}

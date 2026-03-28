//
//  FireflyTypes.swift
//  Gemini3Particles
//

import simd

// MARK: - GPU-Matching Structs

struct FireflyData {
    var position: SIMD2<Float>     // 0
    var velocity: SIMD2<Float>     // 8
    var color: SIMD4<Float>        // 16
    var phase: Float               // 32
    var frequency: Float           // 36
    var size: Float                // 40
    var brightness: Float          // 44
    var target: SIMD2<Float>       // 48
    var hasTarget: Float           // 56
    var padding: Float = 0         // 60  → 64 bytes total
}

struct FireflyUniforms {
    var viewSize: SIMD2<Float>
    var time: Float
    var displayScale: Float
}

struct FireflySimUniforms {
    var viewSize: SIMD2<Float>
    var time: Float
    var deltaTime: Float
    var touchPos: SIMD2<Float>
    var isTouching: Float
    var particleCount: UInt32
}

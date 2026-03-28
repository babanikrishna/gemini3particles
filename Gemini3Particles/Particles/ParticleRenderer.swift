//
//  ParticleRenderer.swift
//  Gemini3Particles
//

import MetalKit
import UIKit

// MARK: - Typed Buffer Access

private extension MTLBuffer {
    func particles(capacity: Int) -> UnsafeMutablePointer<ParticleData> {
        contents().bindMemory(to: ParticleData.self, capacity: capacity)
    }
    func stars(capacity: Int) -> UnsafeMutablePointer<StarData> {
        contents().bindMemory(to: StarData.self, capacity: capacity)
    }
}

// MARK: - Particle Renderer

final class ParticleRenderer: NSObject, MTKViewDelegate {

    private enum Defaults {
        static let maxParticles = 200_000
        static let starCount = 400
        static let maxShootingStars = 3
        static let particleBatchSize = 200

        static let touchRadius: Float = 60
        static let touchForce: Float = 2.5
        static let returnSpeed: Float = 0.014
        static let friction: Float = 0.95
        static let formationDuration: Float = 4000

        static let particleSizeRange: ClosedRange<Float> = 1.5...3.5
        static let wobbleRange: ClosedRange<Float> = 0...100
        static let starSizeRange: ClosedRange<Float> = 0.4...1.5
        static let starSpeedRange: ClosedRange<Float> = 0.3...2.0
        static let starAlphaRange: ClosedRange<Float> = 0.15...0.5

        static let hapticFormInterval: Double = 80
        static let hapticIdleInterval: Double = 300
        static let hapticIdleIntensity: Double = 0.04
        static let hapticPauseThreshold: Double = 500

        static let shootingStarSpawnChance: Float = 0.003
        static let shootingStarSpeedRange: ClosedRange<Float> = 3.0...6.0
        static let shootingStarLifeRange: ClosedRange<Float> = 0.6...1.2
        static let shootingStarBrightnessRange: ClosedRange<Float> = 0.6...1.0
        static let shootingStarTrailLength = 25

        static let backgroundColor = MTLClearColor(red: 0.02, green: 0.02, blue: 0.02, alpha: 1)
        static let offscreen: SIMD2<Float> = .init(-9999, -9999)
    }

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let computePipeline: MTLComputePipelineState
    private let particleRenderPipeline: MTLRenderPipelineState
    private let starRenderPipeline: MTLRenderPipelineState

    private var particleBuffer: MTLBuffer
    private var starBuffer: MTLBuffer

    var liveCount: Int = 0
    var desiredCount: Int = 5000

    private var startTime: Double?
    private var lastUpdateTime: Double?
    var viewSize: CGSize = .zero
    var displayScale: Float = 3.0
    var touchLocation: SIMD2<Float> = Defaults.offscreen

    // Haptics
    private let softHaptic = UIImpactFeedbackGenerator(style: .soft)
    private var lastFormHaptic: Double = 0
    private var lastIdleHaptic: Double = 0

    // Shooting stars
    private struct ShootingStar {
        var position: SIMD2<Float>
        var velocity: SIMD2<Float>
        var life: Float        // 1.0 → 0.0
        var maxLife: Float
        var brightness: Float
        var trail: [SIMD2<Float>]
    }
    private var shootingStars: [ShootingStar] = []

    // Shape data caches
    private var glyphPointsCache: [SIMD2<Float>] = []
    private var photoPointsCache: [(pos: SIMD2<Float>, color: SIMD4<Float>)] = []

    // State
    var glyphIndex = 15
    var customText = ""
    var isPhotoMode = false

    // External deps
    var config: ParticleConfig?

    var isCustomMode: Bool { !isPhotoMode && glyphIndex >= glyphs.count }
    private var currentGlyph: Glyph { isCustomMode ? .text(customText) : glyphs[glyphIndex] }

    var currentScheme: ParticleColorScheme {
        if isPhotoMode {
            return ParticleColorScheme(name: "Photo", colors: [
                (0.9, 0.9, 0.95), (0.7, 0.8, 1.0), (1.0, 0.85, 0.7), (0.8, 0.7, 1.0)
            ])
        } else if isCustomMode {
            return ParticleColorScheme(name: "Custom", colors: [
                (0.6, 0.8, 1.0), (0.8, 0.6, 1.0), (1.0, 0.7, 0.8), (0.7, 1.0, 0.9)
            ])
        } else if glyphIndex < 10 {
            return digitColorSchemes[glyphIndex]
        } else {
            return symbolColorSchemes[glyphIndex - 10]
        }
    }

    init?(metalView: MTKView) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary() else { return nil }

        self.device = device
        self.commandQueue = queue

        // Compute pipeline
        guard let computeFunc = library.makeFunction(name: "updateParticles"),
              let computePS = try? device.makeComputePipelineState(function: computeFunc) else { return nil }
        self.computePipeline = computePS

        // Particle render pipeline
        let particleDesc = MTLRenderPipelineDescriptor()
        particleDesc.vertexFunction = library.makeFunction(name: "particleVertex")
        particleDesc.fragmentFunction = library.makeFunction(name: "particleFragment")
        particleDesc.configureAlphaBlending(pixelFormat: metalView.colorPixelFormat)
        guard let particlePS = try? device.makeRenderPipelineState(descriptor: particleDesc) else { return nil }
        self.particleRenderPipeline = particlePS

        // Star render pipeline
        let starDesc = MTLRenderPipelineDescriptor()
        starDesc.vertexFunction = library.makeFunction(name: "starVertex")
        starDesc.fragmentFunction = library.makeFunction(name: "starFragment")
        starDesc.configureAlphaBlending(pixelFormat: metalView.colorPixelFormat)
        guard let starPS = try? device.makeRenderPipelineState(descriptor: starDesc) else { return nil }
        self.starRenderPipeline = starPS

        // Allocate buffers
        let particleBufSize = MemoryLayout<ParticleData>.stride * Defaults.maxParticles
        guard let pBuf = device.makeBuffer(length: particleBufSize, options: .storageModeShared) else { return nil }
        self.particleBuffer = pBuf

        let starBufSize = MemoryLayout<StarData>.stride * Defaults.starCount
        guard let sBuf = device.makeBuffer(length: starBufSize, options: .storageModeShared) else { return nil }
        self.starBuffer = sBuf

        super.init()
        metalView.delegate = self
    }

    // MARK: - Setup

    func setup(size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        viewSize = size
        setupStars(width: Float(size.width), height: Float(size.height))

        let points = sampleGlyphPoints(glyph: currentGlyph, size: size)
        guard !points.isEmpty else { return }
        glyphPointsCache = points.map { SIMD2<Float>(Float($0.x), Float($0.y)) }

        let count = min(desiredCount, Defaults.maxParticles)
        let scheme = currentScheme
        let ptr = particleBuffer.particles(capacity: Defaults.maxParticles)
        let w = Float(size.width), h = Float(size.height)

        for i in 0..<count {
            let target = glyphPointsCache[Int.random(in: 0..<glyphPointsCache.count)]
            let c = scheme.colors.randomElement()!
            let color = SIMD4<Float>(Float(c.r), Float(c.g), Float(c.b), 1)
            let pos = SIMD2<Float>(Float.random(in: 0...w), Float.random(in: 0...h))
            ptr[i] = ParticleData(
                position: pos, velocity: .zero,
                startPos: pos, targetPos: target,
                color: color, startColor: color, targetColor: color,
                size: Float.random(in: Defaults.particleSizeRange),
                wobble: Float.random(in: Defaults.wobbleRange),
                alpha: 1.0, fadeTarget: 1.0
            )
        }
        liveCount = count
        startTime = nil
    }

    private func setupStars(width: Float, height: Float) {
        let ptr = starBuffer.stars(capacity: Defaults.starCount)
        for i in 0..<Defaults.starCount {
            ptr[i] = StarData(
                position: SIMD2<Float>(Float.random(in: 0...width), Float.random(in: 0...height)),
                size: Float.random(in: Defaults.starSizeRange),
                speed: Float.random(in: Defaults.starSpeedRange),
                phase: Float.random(in: 0...(2 * .pi)),
                baseAlpha: Float.random(in: Defaults.starAlphaRange)
            )
        }
    }

    // MARK: - Shape Changes

    func goToGlyph(index: Int) {
        let maxIndex = customText.isEmpty ? glyphs.count - 1 : glyphs.count
        guard index >= 0, index <= maxIndex else { return }
        isPhotoMode = false
        glyphIndex = index
        retargetParticles()
    }

    func showCustomText(_ text: String) {
        guard !text.isEmpty else { return }
        customText = text
        isPhotoMode = false
        glyphIndex = glyphs.count
        retargetParticles()
    }

    func showPhoto(_ image: UIImage) {
        isPhotoMode = true
        let size = viewSize
        DispatchQueue.global(qos: .userInitiated).async {
            let coloredPoints = samplePhotoSubject(from: image, targetSize: size)
            guard !coloredPoints.isEmpty else { return }
            DispatchQueue.main.async { [self] in
                photoPointsCache = coloredPoints.map {
                    (pos: SIMD2<Float>(Float($0.x), Float($0.y)),
                     color: SIMD4<Float>(Float($0.r), Float($0.g), Float($0.b), 1))
                }
                desiredCount = 10000
                retargetExistingToPhoto()
                startTime = nil
            }
        }
    }

    private func retargetParticles() {
        let points = sampleGlyphPoints(glyph: currentGlyph, size: viewSize)
        guard !points.isEmpty else { return }
        glyphPointsCache = points.map { SIMD2<Float>(Float($0.x), Float($0.y)) }

        let scheme = currentScheme
        let ptr = particleBuffer.particles(capacity: Defaults.maxParticles)

        for i in 0..<liveCount {
            let target = glyphPointsCache[Int.random(in: 0..<glyphPointsCache.count)]
            let c = scheme.colors.randomElement()!
            let color = SIMD4<Float>(Float(c.r), Float(c.g), Float(c.b), 1)
            ptr[i].startPos = ptr[i].position
            ptr[i].startColor = ptr[i].color
            ptr[i].targetPos = target
            ptr[i].targetColor = color
            ptr[i].velocity = .zero
        }
        startTime = nil
    }

    private func retargetExistingToPhoto() {
        guard !photoPointsCache.isEmpty else { return }
        let ptr = particleBuffer.particles(capacity: Defaults.maxParticles)
        for i in 0..<liveCount {
            let cp = photoPointsCache[Int.random(in: 0..<photoPointsCache.count)]
            ptr[i].startPos = ptr[i].position
            ptr[i].startColor = ptr[i].color
            ptr[i].targetPos = cp.pos
            ptr[i].targetColor = cp.color
            ptr[i].velocity = .zero
        }
    }

    // MARK: - Gradual Particle Management

    private func updateParticleCounts() {
        let ptr = particleBuffer.particles(capacity: Defaults.maxParticles)

        // Sync desired count from config
        if let cfg = config {
            let cfgCount = Int(cfg.particleCount)
            if cfgCount != desiredCount { desiredCount = cfgCount }
        }

        // Count active particles
        var activeCount = 0
        for i in 0..<liveCount {
            if ptr[i].fadeTarget > 0 { activeCount += 1 }
        }

        let batchSize = Defaults.particleBatchSize

        if activeCount < desiredCount {
            let toAdd = min(batchSize, desiredCount - activeCount)
            let scheme = currentScheme
            let w = Float(viewSize.width), h = Float(viewSize.height)

            for _ in 0..<toAdd {
                guard liveCount < Defaults.maxParticles else { break }
                if isPhotoMode, !photoPointsCache.isEmpty {
                    let cp = photoPointsCache[Int.random(in: 0..<photoPointsCache.count)]
                    ptr[liveCount] = ParticleData(
                        position: cp.pos, velocity: .zero,
                        startPos: cp.pos, targetPos: cp.pos,
                        color: cp.color, startColor: cp.color, targetColor: cp.color,
                        size: Float.random(in: Defaults.particleSizeRange),
                        wobble: Float.random(in: Defaults.wobbleRange),
                        alpha: 0, fadeTarget: 1.0
                    )
                } else if !glyphPointsCache.isEmpty {
                    let target = glyphPointsCache[Int.random(in: 0..<glyphPointsCache.count)]
                    let c = scheme.colors.randomElement()!
                    let color = SIMD4<Float>(Float(c.r), Float(c.g), Float(c.b), 1)
                    ptr[liveCount] = ParticleData(
                        position: target, velocity: .zero,
                        startPos: target, targetPos: target,
                        color: color, startColor: color, targetColor: color,
                        size: Float.random(in: Defaults.particleSizeRange),
                        wobble: Float.random(in: Defaults.wobbleRange),
                        alpha: 0, fadeTarget: 1.0
                    )
                } else {
                    break
                }
                liveCount += 1
            }
        } else if activeCount > desiredCount {
            var toMark = min(batchSize, activeCount - desiredCount)
            for i in stride(from: liveCount - 1, through: 0, by: -1) where toMark > 0 {
                if ptr[i].fadeTarget > 0 {
                    ptr[i].fadeTarget = 0
                    toMark -= 1
                }
            }
        }

        // Compact: remove dead particles from the end
        while liveCount > 0 && ptr[liveCount - 1].alpha < 0.01 && ptr[liveCount - 1].fadeTarget == 0 {
            liveCount -= 1
        }
    }

    // MARK: - Shooting Stars

    private func updateShootingStars() {
        let w = Float(viewSize.width), h = Float(viewSize.height)
        guard w > 0 && h > 0 else { return }

        // Update existing
        shootingStars = shootingStars.compactMap { star in
            var s = star
            s.life -= 1.0 / (s.maxLife * 120.0)  // decay over maxLife seconds at 120fps
            if s.life <= 0 { return nil }
            s.position += s.velocity
            // Keep trail history
            s.trail.insert(s.position, at: 0)
            if s.trail.count > Defaults.shootingStarTrailLength { s.trail.removeLast() }
            return s
        }

        // Spawn new ones randomly (~once every 3-5 seconds)
        if shootingStars.count < Defaults.maxShootingStars && Float.random(in: 0...1) < Defaults.shootingStarSpawnChance {
            // Pick a random start edge and angle
            let edge = Int.random(in: 0...1)  // 0 = top, 1 = right
            var pos: SIMD2<Float>
            var angle: Float

            if edge == 0 {
                // From top, going down-left or down-right
                pos = SIMD2<Float>(Float.random(in: w * 0.1...w * 0.9), Float.random(in: -10...0))
                angle = Float.random(in: 0.5...1.0) // roughly downward diagonal
            } else {
                // From right, going left-down
                pos = SIMD2<Float>(Float.random(in: w * 0.8...w + 10), Float.random(in: 0...h * 0.4))
                angle = Float.random(in: 2.0...2.8)
            }

            let speed = Float.random(in: Defaults.shootingStarSpeedRange)
            let vel = SIMD2<Float>(cos(angle) * speed, sin(angle) * speed)
            let life = Float.random(in: Defaults.shootingStarLifeRange)

            shootingStars.append(ShootingStar(
                position: pos, velocity: vel,
                life: 1.0, maxLife: life,
                brightness: Float.random(in: Defaults.shootingStarBrightnessRange),
                trail: [pos]
            ))
        }
    }

    private func buildShootingStarPoints() -> [StarData] {
        var points: [StarData] = []
        for star in shootingStars {
            let count = star.trail.count
            for (i, pos) in star.trail.enumerated() {
                let t = Float(i) / Float(max(count - 1, 1))
                let fadeAlpha = star.life * star.brightness * (1.0 - t * t)
                let size = (1.0 - t * 0.7) * 0.8
                points.append(StarData(
                    position: pos,
                    size: size,
                    speed: 0,
                    phase: .pi / 2,  // makes pulse=1 in shader so alpha=baseAlpha
                    baseAlpha: fadeAlpha
                ))
            }
        }
        return points
    }

    // MARK: - MTKViewDelegate

    nonisolated func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        MainActor.assumeIsolated {
            let scale = view.contentScaleFactor
            displayScale = Float(scale)
            let scaledSize = CGSize(width: size.width / scale, height: size.height / scale)
            viewSize = scaledSize
            if liveCount == 0 && scaledSize.width > 0 && scaledSize.height > 0 {
                setup(size: scaledSize)
            }
        }
    }

    nonisolated func draw(in view: MTKView) {
        MainActor.assumeIsolated {
            drawFrame(in: view)
        }
    }

    // MARK: - Frame Rendering

    private func drawFrame(in view: MTKView) {
        autoSetupIfNeeded(in: view)

        guard liveCount > 0,
              let drawable = view.currentDrawable,
              let passDesc = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        let timing = updateTiming()
        tickHaptics(elapsed: timing.elapsed, time: timing.time)
        updateParticleCounts()
        updateShootingStars()

        guard liveCount > 0 else { return }

        var uniforms = buildUniforms(elapsed: timing.elapsed)
        dispatchCompute(commandBuffer: commandBuffer, uniforms: &uniforms)
        renderFrame(commandBuffer: commandBuffer, passDesc: passDesc, elapsed: timing.elapsed, uniforms: uniforms)

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func autoSetupIfNeeded(in view: MTKView) {
        guard liveCount == 0 else { return }
        let w = view.bounds.width, h = view.bounds.height
        guard w > 0, h > 0 else { return }
        viewSize = CGSize(width: w, height: h)
        setup(size: viewSize)
    }

    private func updateTiming() -> (time: Double, elapsed: Double) {
        let time = Date.timeIntervalSinceReferenceDate * 1000
        if startTime == nil { startTime = time }
        if let last = lastUpdateTime, time - last > Defaults.hapticPauseThreshold {
            startTime! += (time - last)
        }
        lastUpdateTime = time
        return (time, time - startTime!)
    }

    private func tickHaptics(elapsed: Double, time: Double) {
        if elapsed < Double(Defaults.formationDuration) {
            if time - lastFormHaptic > Defaults.hapticFormInterval {
                lastFormHaptic = time
                let progress = elapsed / Double(Defaults.formationDuration)
                softHaptic.impactOccurred(intensity: sin(progress * .pi) * 0.5 + 0.1)
            }
        } else if time - lastIdleHaptic > Defaults.hapticIdleInterval {
            lastIdleHaptic = time
            softHaptic.impactOccurred(intensity: Defaults.hapticIdleIntensity)
        }
    }

    private func buildUniforms(elapsed: Double) -> ParticleUniforms {
        let cfg = config ?? ParticleConfig()
        let wobble: Float = cfg.wobbleEnabled
            ? (isCustomMode || isPhotoMode || glyphIndex >= 10 ? 0.4 : 1.0)
            : 0.0

        return ParticleUniforms(
            touchPos: touchLocation,
            viewSize: SIMD2<Float>(Float(viewSize.width), Float(viewSize.height)),
            parallaxOffset: .zero,
            time: Float(elapsed),
            elapsed: Float(elapsed),
            touchRadius: Defaults.touchRadius,
            touchForce: Defaults.touchForce,
            returnSpeed: Defaults.returnSpeed,
            friction: Defaults.friction,
            formationDurationMs: Defaults.formationDuration,
            wobbleScale: wobble,
            audioLevel: 0,
            soundReactive: 0,
            particleCount: UInt32(liveCount)
        )
    }

    private func dispatchCompute(commandBuffer: MTLCommandBuffer, uniforms: inout ParticleUniforms) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.setComputePipelineState(computePipeline)
        encoder.setBuffer(particleBuffer, offset: 0, index: 0)
        encoder.setBytes(&uniforms, length: MemoryLayout<ParticleUniforms>.stride, index: 1)

        let threadgroupSize = min(computePipeline.maxTotalThreadsPerThreadgroup, 256)
        let threadgroups = (liveCount + threadgroupSize - 1) / threadgroupSize
        encoder.dispatchThreadgroups(
            MTLSize(width: threadgroups, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: threadgroupSize, height: 1, depth: 1))
        encoder.endEncoding()
    }

    private func renderFrame(commandBuffer: MTLCommandBuffer, passDesc: MTLRenderPassDescriptor,
                             elapsed: Double, uniforms: ParticleUniforms) {
        passDesc.colorAttachments[0].clearColor = Defaults.backgroundColor
        passDesc.colorAttachments[0].loadAction = .clear

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDesc) else { return }
        var scale = displayScale
        var vs = uniforms.viewSize
        var timeFloat = Float(elapsed)

        // Stars
        encoder.setRenderPipelineState(starRenderPipeline)
        encoder.setVertexBuffer(starBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(&vs, length: MemoryLayout<SIMD2<Float>>.stride, index: 1)
        encoder.setVertexBytes(&timeFloat, length: MemoryLayout<Float>.stride, index: 2)
        var starParallax = SIMD2<Float>.zero
        encoder.setVertexBytes(&starParallax, length: MemoryLayout<SIMD2<Float>>.stride, index: 3)
        encoder.setVertexBytes(&scale, length: MemoryLayout<Float>.stride, index: 4)
        encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: Defaults.starCount)

        // Shooting stars
        var shootingPoints = buildShootingStarPoints()
        if !shootingPoints.isEmpty {
            encoder.setVertexBytes(&shootingPoints, length: MemoryLayout<StarData>.stride * shootingPoints.count, index: 0)
            encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: shootingPoints.count)
        }

        // Particles
        encoder.setRenderPipelineState(particleRenderPipeline)
        encoder.setVertexBuffer(particleBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(&vs, length: MemoryLayout<SIMD2<Float>>.stride, index: 1)
        var parallax = uniforms.parallaxOffset
        encoder.setVertexBytes(&parallax, length: MemoryLayout<SIMD2<Float>>.stride, index: 2)
        encoder.setVertexBytes(&scale, length: MemoryLayout<Float>.stride, index: 3)
        encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: liveCount)

        encoder.endEncoding()
    }
}

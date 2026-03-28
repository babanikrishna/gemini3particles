//
//  FireflyRenderer.swift
//  Gemini3Particles
//

import MetalKit
import UIKit

// MARK: - Typed Buffer Access

private extension MTLBuffer {
    func fireflies(capacity: Int) -> UnsafeMutablePointer<FireflyData> {
        contents().bindMemory(to: FireflyData.self, capacity: capacity)
    }
}

// MARK: - Firefly Renderer

final class FireflyRenderer: NSObject, MTKViewDelegate {

    private enum Defaults {
        static let minBufferCapacity = 100_000
        static let mainSizeRange: ClosedRange<Float> = 6...18
        static let driftSizeRange: ClosedRange<Float> = 4...10
        static let velocityRange: ClosedRange<Float> = -0.4...0.4
        static let phaseRange: ClosedRange<Float> = 0...(Float.pi * 2)
        static let frequencyRange: ClosedRange<Float> = 0.4...2.8
        static let scatterForceRange: ClosedRange<Float> = 1.5...3.5
        static let scatterJitterRange: ClosedRange<Float> = -1.5...1.5
        static let backgroundColor = MTLClearColor(red: 0.015, green: 0.025, blue: 0.065, alpha: 1)
        static let offscreen: SIMD2<Float> = .init(-9999, -9999)
    }

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let renderPipeline: MTLRenderPipelineState
    private let computePipeline: MTLComputePipelineState

    private var flyBuffer: MTLBuffer?
    private var bufferCapacity: Int = 0
    private var activeFlyCount: Int = 0
    var viewSize: CGSize = .zero
    var displayScale: Float = 3.0

    private var startTime: Double = 0
    private var lastFrameTime: Double = 0
    var glyphFlyCount = 1500

    private var cachedTargets: [ColoredPoint] = []
    private var lastTargets: [ColoredPoint] = []

    var glyphIndex = 15
    var customText = ""
    var isCustomMode: Bool { glyphIndex >= glyphs.count }
    private var currentGlyph: Glyph { isCustomMode ? .text(customText) : glyphs[glyphIndex] }

    var touchLocation: SIMD2<Float> = Defaults.offscreen
    var isTouching = false

    private var hasSetup = false

    init?(metalView: MTKView) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary() else { return nil }

        self.device = device
        self.commandQueue = queue

        // Standard alpha blend — same as particle mode, glow comes from the fragment shader
        let renderDesc = MTLRenderPipelineDescriptor()
        renderDesc.vertexFunction = library.makeFunction(name: "fireflyVertex")
        renderDesc.fragmentFunction = library.makeFunction(name: "fireflyFragment")
        renderDesc.configureAlphaBlending(pixelFormat: metalView.colorPixelFormat)
        guard let rps = try? device.makeRenderPipelineState(descriptor: renderDesc) else { return nil }
        self.renderPipeline = rps

        // Compute pipeline
        guard let computeFunc = library.makeFunction(name: "updateFireflies"),
              let cps = try? device.makeComputePipelineState(function: computeFunc) else { return nil }
        self.computePipeline = cps

        super.init()
        metalView.delegate = self
        startTime = Date.timeIntervalSinceReferenceDate
        lastFrameTime = startTime
    }

    // MARK: - Color Scheme (matches particle mode)

    private func currentColorScheme() -> ParticleColorScheme {
        if isCustomMode {
            return (digitColorSchemes + symbolColorSchemes).randomElement()!
        } else if glyphIndex < digitColorSchemes.count {
            return digitColorSchemes[glyphIndex]
        } else {
            let symIdx = (glyphIndex - digitColorSchemes.count) % symbolColorSchemes.count
            return symbolColorSchemes[symIdx]
        }
    }

    private func schemeToSIMD(_ scheme: ParticleColorScheme) -> [SIMD4<Float>] {
        scheme.colors.map { SIMD4<Float>(Float($0.0), Float($0.1), Float($0.2), 1) }
    }

    // MARK: - Setup

    func setup(size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        viewSize = size
        createGlyphFlies()
        cacheGlyphTargets()
        hasSetup = true
    }

    private func ensureBufferCapacity(_ needed: Int) {
        guard needed > bufferCapacity || flyBuffer == nil else { return }
        // Allocate 2x what's needed (or 100K, whichever is larger) to avoid frequent reallocs
        let newCapacity = max(needed, min(Defaults.minBufferCapacity, needed * 2))
        let byteSize = MemoryLayout<FireflyData>.stride * newCapacity
        flyBuffer = device.makeBuffer(length: byteSize, options: .storageModeShared)
        bufferCapacity = newCapacity
    }

    private func createGlyphFlies() {
        let w = Float(viewSize.width)
        let h = Float(viewSize.height)
        let colors = schemeToSIMD(currentColorScheme())
        let sr = Defaults.mainSizeRange

        ensureBufferCapacity(glyphFlyCount)
        guard let buffer = flyBuffer else { return }
        let ptr = buffer.fireflies(capacity: bufferCapacity)

        for i in 0..<glyphFlyCount {
            ptr[i] = FireflyData(
                position: SIMD2(Float.random(in: 0...w), Float.random(in: 0...h)),
                velocity: SIMD2(Float.random(in: Defaults.velocityRange), Float.random(in: Defaults.velocityRange)),
                color: colors.randomElement()!,
                phase: Float.random(in: Defaults.phaseRange),
                frequency: Float.random(in: Defaults.frequencyRange),
                size: Float.random(in: sr),
                brightness: 0,
                target: SIMD2(0, 0),
                hasTarget: 0
            )
        }
        activeFlyCount = glyphFlyCount
    }

    // MARK: - Shape Morphing

    func goToGlyph(index: Int) {
        guard index >= 0, index < glyphs.count else { return }
        glyphIndex = index
        cacheGlyphTargets()
        morphToShape()
    }

    func showCustomText(_ text: String) {
        guard !text.isEmpty else { return }
        customText = text
        glyphIndex = glyphs.count
        cacheGlyphTargets()
        morphToShape()
    }

    func showPhoto(_ image: UIImage) {
        let size = viewSize
        DispatchQueue.global(qos: .userInitiated).async {
            let coloredPoints = samplePhotoSubject(from: image, targetSize: size)
            guard !coloredPoints.isEmpty else { return }
            DispatchQueue.main.async { [self] in
                cachedTargets = coloredPoints
                morphToShape()
            }
        }
    }

    /// Convert glyph/text sample points into ColoredPoint using the current color scheme
    private func cacheGlyphTargets() {
        let points = sampleGlyphPoints(glyph: currentGlyph, size: viewSize)
        let colors = schemeToSIMD(currentColorScheme())
        cachedTargets = points.map { pt in
            let c = colors.randomElement()!
            return ColoredPoint(x: pt.x, y: pt.y, r: Double(c.x), g: Double(c.y), b: Double(c.z))
        }
    }

    func updateFlyCount(_ count: Int) {
        let oldCount = activeFlyCount
        glyphFlyCount = count

        // Ensure buffer is big enough without reallocating when shrinking
        ensureBufferCapacity(count)
        guard let buffer = flyBuffer else { return }
        let ptr = buffer.fireflies(capacity: bufferCapacity)

        // Initialize any NEW entries (old ones keep their positions)
        if count > oldCount {
            let w = Float(viewSize.width)
            let h = Float(viewSize.height)
            let colors = schemeToSIMD(currentColorScheme())
            let sr = Defaults.mainSizeRange
            for i in oldCount..<count {
                ptr[i] = FireflyData(
                    position: SIMD2(Float.random(in: 0...w), Float.random(in: 0...h)),
                    velocity: SIMD2(0, 0),
                    color: colors.randomElement()!,
                    phase: Float.random(in: Defaults.phaseRange),
                    frequency: Float.random(in: Defaults.frequencyRange),
                    size: Float.random(in: sr),
                    brightness: 0,
                    target: SIMD2(0, 0),
                    hasTarget: 0
                )
            }
        }
        activeFlyCount = count
        morphToShape()
    }

    func clearShape() {
        if !cachedTargets.isEmpty { lastTargets = cachedTargets }
        cachedTargets = []
        guard let buffer = flyBuffer else { return }
        let ptr = buffer.fireflies(capacity: activeFlyCount)
        let cx = Float(viewSize.width) * 0.5
        let cy = Float(viewSize.height) * 0.5
        for i in 0..<activeFlyCount {
            ptr[i].hasTarget = 0
            ptr[i].size = Float.random(in: Defaults.mainSizeRange)
            // Push outward from shape center so they visibly spread apart
            let dx = ptr[i].position.x - cx
            let dy = ptr[i].position.y - cy
            let dist = max(sqrt(dx * dx + dy * dy), 1.0)
            let outward = SIMD2<Float>(dx / dist, dy / dist) * Float.random(in: Defaults.scatterForceRange)
            ptr[i].velocity = outward + SIMD2(
                Float.random(in: Defaults.scatterJitterRange),
                Float.random(in: Defaults.scatterJitterRange)
            )
            ptr[i].phase = Float.random(in: Defaults.phaseRange)
            ptr[i].frequency = Float.random(in: Defaults.frequencyRange)
        }
    }

    func reformShape() {
        guard !lastTargets.isEmpty else { return }
        cachedTargets = lastTargets
        morphToShape()
    }

    private func morphToShape() {
        guard viewSize.width > 0 else { return }

        if activeFlyCount != glyphFlyCount {
            createGlyphFlies()
        }

        guard let buffer = flyBuffer, !cachedTargets.isEmpty else { return }
        let ptr = buffer.fireflies(capacity: activeFlyCount)

        let sr = Defaults.mainSizeRange
        let targets = cachedTargets.shuffled()

        // Unified: assign target points, extras drift free
        for i in 0..<activeFlyCount {
            if i < targets.count {
                let p = targets[i]
                ptr[i].target = SIMD2(Float(p.x), Float(p.y))
                ptr[i].hasTarget = 1
                ptr[i].color = SIMD4(Float(p.r), Float(p.g), Float(p.b), 1)
                ptr[i].size = Float.random(in: sr)
            } else {
                // More flies than target points — pick a random target to cluster near
                let p = targets[Int.random(in: 0..<targets.count)]
                ptr[i].target = SIMD2(Float(p.x), Float(p.y))
                ptr[i].hasTarget = 1
                ptr[i].color = SIMD4(Float(p.r), Float(p.g), Float(p.b), 1)
                ptr[i].size = Float.random(in: sr)
            }
        }
    }

    // MARK: - MTKViewDelegate

    nonisolated func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        MainActor.assumeIsolated {
            let scale = view.contentScaleFactor
            displayScale = Float(scale)
            let scaledSize = CGSize(width: size.width / scale, height: size.height / scale)
            if !hasSetup && scaledSize.width > 0 && scaledSize.height > 0 {
                setup(size: scaledSize)
                morphToShape()
            }
        }
    }

    nonisolated func draw(in view: MTKView) {
        MainActor.assumeIsolated {
            drawFrame(in: view)
        }
    }

    private func drawFrame(in view: MTKView) {
        if !hasSetup {
            let w = view.bounds.width, h = view.bounds.height
            if w > 0 && h > 0 {
                viewSize = CGSize(width: w, height: h)
                setup(size: viewSize)
                morphToShape()
            }
        }

        guard activeFlyCount > 0,
              let flyBuffer,
              let drawable = view.currentDrawable,
              let passDesc = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        let now = Date.timeIntervalSinceReferenceDate
        let time = Float(now - startTime)
        let dt = Float(now - lastFrameTime)
        lastFrameTime = now

        // === COMPUTE PASS ===
        var simUniforms = FireflySimUniforms(
            viewSize: SIMD2<Float>(Float(viewSize.width), Float(viewSize.height)),
            time: time,
            deltaTime: min(dt, 1.0 / 30.0),
            touchPos: touchLocation,
            isTouching: isTouching ? 1.0 : 0.0,
            particleCount: UInt32(activeFlyCount)
        )

        if let computeEncoder = commandBuffer.makeComputeCommandEncoder() {
            computeEncoder.setComputePipelineState(computePipeline)
            computeEncoder.setBuffer(flyBuffer, offset: 0, index: 0)
            computeEncoder.setBytes(&simUniforms, length: MemoryLayout<FireflySimUniforms>.stride, index: 1)

            let threadsPerGroup = min(computePipeline.maxTotalThreadsPerThreadgroup, 256)
            let threadGroups = (activeFlyCount + threadsPerGroup - 1) / threadsPerGroup
            computeEncoder.dispatchThreadgroups(
                MTLSize(width: threadGroups, height: 1, depth: 1),
                threadsPerThreadgroup: MTLSize(width: threadsPerGroup, height: 1, depth: 1)
            )
            computeEncoder.endEncoding()
        }

        // === RENDER PASS ===
        passDesc.colorAttachments[0].clearColor = Defaults.backgroundColor
        passDesc.colorAttachments[0].loadAction = .clear

        var renderUniforms = FireflyUniforms(
            viewSize: SIMD2<Float>(Float(viewSize.width), Float(viewSize.height)),
            time: time,
            displayScale: displayScale
        )

        if let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDesc) {
            renderEncoder.setRenderPipelineState(renderPipeline)
            renderEncoder.setVertexBuffer(flyBuffer, offset: 0, index: 0)
            renderEncoder.setVertexBytes(&renderUniforms, length: MemoryLayout<FireflyUniforms>.stride, index: 1)
            renderEncoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: activeFlyCount)
            renderEncoder.endEncoding()
        }

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

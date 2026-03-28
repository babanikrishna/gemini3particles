//
//  ParticleEffectView.swift
//  Gemini3Particles
//

import SwiftUI
import MetalKit
import PhotosUI

// MARK: - Particle View Representable

struct ParticleViewRepresentable: UIViewRepresentable {
    let renderer: ParticleRenderer
    let config: ParticleConfig

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = MTLCreateSystemDefaultDevice()
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(red: 0.02, green: 0.02, blue: 0.02, alpha: 1)
        view.preferredFramesPerSecond = 120
        view.isPaused = false
        view.enableSetNeedsDisplay = false

        renderer.config = config
        view.delegate = renderer
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        let size = CGSize(width: uiView.bounds.width, height: uiView.bounds.height)
        if size.width > 0 && size.height > 0 && renderer.viewSize == .zero {
            renderer.viewSize = size
            renderer.setup(size: size)
        }
    }
}

// MARK: - Particle Effect View

struct ParticleEffectView: View {
    var config: ParticleConfig

    @State private var renderer: ParticleRenderer?
    @State private var hasSetup = false
    @State private var showSettings = false
    @State private var showCustomInput = false
    @State private var customInputText = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var lastTouchLocation = CGPoint(x: -1, y: -1)
    @State private var lastHapticTime: Date = .distantPast
    @State private var glyphIndex: Int = 15
    @State private var isPhotoMode: Bool = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topTrailing) {
                if let renderer {
                    ParticleViewRepresentable(renderer: renderer, config: config)
                        .ignoresSafeArea()
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    renderer.touchLocation = SIMD2<Float>(
                                        Float(value.location.x),
                                        Float(value.location.y)
                                    )
                                    let now = Date()
                                    let dt = now.timeIntervalSince(lastHapticTime)
                                    if dt > 0.06 {
                                        if lastTouchLocation.x < 0 {
                                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        } else {
                                            let dx = value.location.x - lastTouchLocation.x
                                            let dy = value.location.y - lastTouchLocation.y
                                            let speed = sqrt(dx * dx + dy * dy) / dt
                                            let intensity = min(max(speed / 800.0, 0.1), 0.8)
                                            UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: intensity)
                                        }
                                        lastHapticTime = now
                                        lastTouchLocation = value.location
                                    }
                                }
                                .onEnded { _ in
                                    renderer.touchLocation = .init(-9999, -9999)
                                    lastTouchLocation = CGPoint(x: -1, y: -1)
                                }
                        )
                } else {
                    Color(red: 0.02, green: 0.02, blue: 0.02)
                        .ignoresSafeArea()
                }

                ShapeControlsOverlay(
                    selectedPhoto: $selectedPhoto,
                    onGlyphSelected: { i in
                        renderer?.goToGlyph(index: i)
                        glyphIndex = i
                        isPhotoMode = false
                    },
                    onCustomTextTapped: { showCustomInput = true },
                    onSettingsTapped: { showSettings = true }
                ) {
                    glyphIcon(glyphIndex: glyphIndex, isPhotoMode: isPhotoMode, isCustomMode: glyphIndex >= glyphs.count)
                        .foregroundStyle(.white)
                }

            }
            .onAppear {
                if !hasSetup {
                    let mtkView = MTKView()
                    mtkView.device = MTLCreateSystemDefaultDevice()
                    mtkView.colorPixelFormat = .bgra8Unorm
                    if let r = ParticleRenderer(metalView: mtkView) {
                        r.config = config
                        r.desiredCount = Int(config.particleCount)
                        renderer = r
                    }
                    hasSetup = true
                }
            }
            .onChange(of: selectedPhoto) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let uiImage = UIImage(data: data) {
                        let normalized = normalizeOrientation(uiImage)
                        renderer?.showPhoto(normalized)
                        isPhotoMode = true
                    }
                }
            }
            .alert("Custom Text", isPresented: $showCustomInput) {
                TextField("Your name or text", text: $customInputText)
                Button("Show") {
                    if !customInputText.isEmpty {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        renderer?.showCustomText(customInputText)
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Enter text to display as particles")
            }
            .sheet(isPresented: $showSettings) {
                ParticleSettingsSheet(config: config)
                    .presentationDetents([.medium, .large])
            }
            .onReceive(NotificationCenter.default.publisher(for: .deviceDidShake)) { _ in
                let randomIndex = Int.random(in: 0..<glyphs.count)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                renderer?.goToGlyph(index: randomIndex)
                glyphIndex = randomIndex
                isPhotoMode = false
            }
        }
    }

}

// MARK: - Particle Settings Sheet

struct ParticleSettingsSheet: View {
    @Bindable var config: ParticleConfig
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Particles") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Count: \(Int(config.particleCount))")
                            .font(.subheadline)
                        Slider(value: $config.particleCount, in: 500...100000, step: 500)
                    }
                }
                Section("Effects") {
                    Toggle("Idle Wobble", isOn: $config.wobbleEnabled)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

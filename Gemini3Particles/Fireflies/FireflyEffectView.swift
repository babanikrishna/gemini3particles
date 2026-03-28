//
//  FireflyEffectView.swift
//  Gemini3Particles
//

import SwiftUI
import MetalKit
import PhotosUI

// MARK: - Firefly View Representable

struct FireflyViewRepresentable: UIViewRepresentable {
    let renderer: FireflyRenderer

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = MTLCreateSystemDefaultDevice()
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(red: 0.015, green: 0.025, blue: 0.065, alpha: 1)
        view.preferredFramesPerSecond = 120
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.delegate = renderer
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {}
}

// MARK: - Firefly Effect View

struct FireflyEffectView: View {
    var config: ParticleConfig

    @State private var renderer: FireflyRenderer?
    @State private var hasSetup = false
    @State private var showCustomInput = false
    @State private var customInputText = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var glyphIndex: Int = 15
    @State private var isPhotoMode = false
    @State private var showSettings = false
    @State private var flyCount: Double = 1500
    @State private var isScattered = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topTrailing) {
                if let renderer {
                    FireflyViewRepresentable(renderer: renderer)
                        .ignoresSafeArea()
                        .onTapGesture(count: 2) {
                            isScattered.toggle()
                            if isScattered {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                renderer.clearShape()
                            } else {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                renderer.reformShape()
                            }
                        }
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 5)
                                .onChanged { value in
                                    let point = SIMD2<Float>(
                                        Float(value.location.x),
                                        Float(value.location.y)
                                    )
                                    renderer.touchLocation = point
                                    renderer.isTouching = true
                                }
                                .onEnded { _ in
                                    renderer.isTouching = false
                                    renderer.touchLocation = SIMD2<Float>(-9999, -9999)
                                }
                        )
                } else {
                    Color(red: 0.015, green: 0.025, blue: 0.065)
                        .ignoresSafeArea()
                }

                ShapeControlsOverlay(
                    selectedPhoto: $selectedPhoto,
                    onGlyphSelected: { i in
                        renderer?.goToGlyph(index: i)
                        glyphIndex = i
                        isPhotoMode = false
                        isScattered = false
                    },
                    onCustomTextTapped: { showCustomInput = true },
                    onSettingsTapped: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        showSettings = true
                    }
                ) {
                    Group {
                        if isScattered {
                            Image(systemName: "sparkles").font(.system(size: 16, weight: .bold))
                        } else {
                            glyphIcon(
                                glyphIndex: glyphIndex,
                                isPhotoMode: isPhotoMode,
                                isCustomMode: glyphIndex >= glyphs.count
                            )
                        }
                    }
                    .foregroundStyle(.white)
                }
            }
            .onAppear {
                if !hasSetup {
                    let mtkView = MTKView()
                    mtkView.device = MTLCreateSystemDefaultDevice()
                    mtkView.colorPixelFormat = .bgra8Unorm
                    if let r = FireflyRenderer(metalView: mtkView) {
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
                        isScattered = false
                    }
                }
            }
            .alert("Custom Text", isPresented: $showCustomInput) {
                TextField("Your name or text", text: $customInputText)
                Button("Show") {
                    if !customInputText.isEmpty {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        renderer?.showCustomText(customInputText)
                        isPhotoMode = false
                        isScattered = false
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Enter text to display as fireflies")
            }
            .sheet(isPresented: $showSettings) {
                FireflySettingsSheet(
                    flyCount: $flyCount,
                    onCountChanged: { newCount in
                        renderer?.updateFlyCount(newCount)
                    }
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: .deviceDidShake)) { _ in
                let randomIndex = Int.random(in: 0..<glyphs.count)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                renderer?.goToGlyph(index: randomIndex)
                glyphIndex = randomIndex
                isPhotoMode = false
                isScattered = false
            }
        }
    }

}

// MARK: - Settings Sheet

struct FireflySettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var flyCount: Double
    var onCountChanged: (Int) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Firefly Count")
                            Spacer()
                            Text("\(Int(flyCount))")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $flyCount, in: 200...100000, step: 100) {
                            Text("Firefly Count")
                        }
                        .onChange(of: flyCount) { _, newValue in
                            onCountChanged(Int(newValue))
                        }
                    }
                } header: {
                    Text("Fireflies")
                } footer: {
                    Text("Controls the number of fireflies used to form shapes and photos.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

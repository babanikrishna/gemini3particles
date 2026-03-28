//
//  ShapeControls.swift
//  Gemini3Particles
//
//  Created by Krishna Babani on 2/19/26.
//

import SwiftUI
import PhotosUI

// MARK: - Shared Helpers

func symbolDisplayName(_ name: String) -> String {
    name.replacingOccurrences(of: ".fill", with: "")
        .replacingOccurrences(of: ".", with: " ").capitalized
}

@ViewBuilder
func glyphIcon(glyphIndex: Int, isPhotoMode: Bool, isCustomMode: Bool) -> some View {
    if isPhotoMode {
        Image(systemName: "photo.fill").font(.system(size: 16, weight: .bold))
    } else if isCustomMode {
        Image(systemName: "character.cursor.ibeam").font(.system(size: 16, weight: .bold))
    } else if glyphIndex < glyphs.count {
        switch glyphs[glyphIndex] {
        case .text(let t):
            Text(t).font(.system(size: 18, weight: .bold, design: .rounded))
        case .symbol(let name):
            Image(systemName: name).resizable().scaledToFit()
                .frame(width: 20, height: 20).fontWeight(.bold)
        }
    } else {
        Image(systemName: "sparkles").font(.system(size: 16, weight: .bold))
    }
}

// MARK: - Shape Controls Overlay

struct ShapeControlsOverlay<Icon: View>: View {
    @Binding var selectedPhoto: PhotosPickerItem?
    let onGlyphSelected: (Int) -> Void
    let onCustomTextTapped: () -> Void
    let onSettingsTapped: () -> Void
    let icon: Icon

    init(
        selectedPhoto: Binding<PhotosPickerItem?>,
        onGlyphSelected: @escaping (Int) -> Void,
        onCustomTextTapped: @escaping () -> Void,
        onSettingsTapped: @escaping () -> Void,
        @ViewBuilder icon: () -> Icon
    ) {
        self._selectedPhoto = selectedPhoto
        self.onGlyphSelected = onGlyphSelected
        self.onCustomTextTapped = onCustomTextTapped
        self.onSettingsTapped = onSettingsTapped
        self.icon = icon()
    }

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            VStack(spacing: 12) {
                Menu {
                    Section {
                        Button(action: onCustomTextTapped) {
                            Label("Enter Text...", systemImage: "character.cursor.ibeam")
                        }
                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            onGlyphSelected(Int.random(in: 0..<glyphs.count))
                        } label: {
                            Label("Random", systemImage: "dice.fill")
                        }
                    }
                    Section("Numbers") {
                        ForEach(0..<10, id: \.self) { i in
                            Button {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                onGlyphSelected(i)
                            } label: {
                                Label("\(i)", systemImage: "\(i).circle")
                            }
                        }
                    }
                    ForEach(glyphCategories) { category in
                        Section(category.name) {
                            ForEach(category.indices, id: \.self) { i in
                                Button {
                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                    onGlyphSelected(i)
                                } label: {
                                    switch glyphs[i] {
                                    case .text(let t):
                                        Label(t, systemImage: "\(t).circle")
                                    case .symbol(let name):
                                        Label(symbolDisplayName(name), systemImage: name)
                                    }
                                }
                            }
                        }
                    }
                } label: {
                    controlCircle { icon }
                }

                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    controlCircle {
                        Image(systemName: "photo.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }

                Button(action: onSettingsTapped) {
                    controlCircle {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .padding(.top, 54)
            .padding(.trailing, 16)
        }
    }

    private func controlCircle<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(width: 44, height: 44)
            .glassEffect(.regular.interactive(), in: .circle)
    }
}

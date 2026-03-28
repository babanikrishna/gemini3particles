//
//  ColorSchemes.swift
//  Gemini3Particles
//
//  Created by Krishna Babani on 2/19/26.
//

import SwiftUI

// MARK: - Color Scheme

struct ParticleColorScheme: Identifiable {
    let id = UUID()
    let name: String
    let colors: [(r: Double, g: Double, b: Double)]

    var swiftUIColors: [Color] {
        colors.map { Color(red: $0.r, green: $0.g, blue: $0.b) }
    }
}

// MARK: - Digit Schemes (0-9)

let digitColorSchemes: [ParticleColorScheme] = [
    ParticleColorScheme(name: "Nebula Fire", colors: [
        (1.0, 0.30, 0.30), (1.0, 0.62, 0.30), (1.0, 0.92, 0.30), (1.0, 0.30, 0.58)
    ]),
    ParticleColorScheme(name: "Oceanic Depth", colors: [
        (0.30, 1.0, 0.92), (0.30, 0.58, 1.0), (0.30, 0.30, 1.0), (0.62, 0.30, 1.0)
    ]),
    ParticleColorScheme(name: "Forest Spirit", colors: [
        (0.30, 1.0, 0.62), (0.68, 1.0, 0.30), (0.30, 1.0, 0.30), (0.30, 1.0, 0.85)
    ]),
    ParticleColorScheme(name: "Solar Gold", colors: [
        (1.0, 0.85, 0.20), (1.0, 0.70, 0.15), (0.95, 0.60, 0.10), (1.0, 0.95, 0.40)
    ]),
    ParticleColorScheme(name: "Electric Violet", colors: [
        (0.70, 0.30, 1.0), (0.85, 0.40, 0.95), (0.50, 0.20, 1.0), (0.95, 0.50, 0.80)
    ]),
    ParticleColorScheme(name: "Arctic Frost", colors: [
        (0.70, 0.90, 1.0), (0.85, 0.95, 1.0), (0.50, 0.80, 1.0), (0.90, 0.95, 1.0)
    ]),
    ParticleColorScheme(name: "Coral Reef", colors: [
        (1.0, 0.50, 0.45), (1.0, 0.65, 0.50), (0.95, 0.40, 0.55), (1.0, 0.75, 0.60)
    ]),
    ParticleColorScheme(name: "Emerald", colors: [
        (0.15, 0.85, 0.55), (0.20, 0.95, 0.65), (0.10, 0.75, 0.45), (0.30, 1.0, 0.70)
    ]),
    ParticleColorScheme(name: "Cyber Pink", colors: [
        (1.0, 0.20, 0.60), (1.0, 0.35, 0.75), (0.90, 0.15, 0.50), (1.0, 0.50, 0.85)
    ]),
    ParticleColorScheme(name: "Sunset", colors: [
        (1.0, 0.45, 0.20), (1.0, 0.30, 0.35), (0.95, 0.55, 0.15), (1.0, 0.40, 0.50)
    ])
]

// MARK: - Symbol Schemes

let symbolColorSchemes: [ParticleColorScheme] = [
    ParticleColorScheme(name: "Gold Sparkle", colors: [
        (1.0, 0.84, 0.0), (1.0, 0.93, 0.40), (0.95, 0.75, 0.10), (1.0, 0.88, 0.55)
    ]),
    ParticleColorScheme(name: "Ruby", colors: [
        (0.90, 0.10, 0.20), (1.0, 0.20, 0.35), (0.80, 0.05, 0.15), (1.0, 0.35, 0.45)
    ]),
    ParticleColorScheme(name: "Electric", colors: [
        (0.30, 0.85, 1.0), (0.50, 0.95, 1.0), (0.15, 0.70, 1.0), (0.70, 1.0, 1.0)
    ]),
    ParticleColorScheme(name: "Inferno", colors: [
        (1.0, 0.35, 0.0), (1.0, 0.55, 0.0), (1.0, 0.20, 0.0), (1.0, 0.75, 0.15)
    ]),
    ParticleColorScheme(name: "Midnight", colors: [
        (0.40, 0.40, 1.0), (0.60, 0.50, 1.0), (0.80, 0.75, 1.0), (0.30, 0.30, 0.90)
    ]),
    ParticleColorScheme(name: "Prismatic", colors: [
        (1.0, 0.40, 0.70), (0.40, 1.0, 0.85), (1.0, 0.90, 0.30), (0.55, 0.40, 1.0)
    ]),
    ParticleColorScheme(name: "Royal", colors: [
        (1.0, 0.78, 0.0), (0.85, 0.60, 0.0), (1.0, 0.90, 0.45), (0.75, 0.50, 0.0)
    ]),
    ParticleColorScheme(name: "Mystic", colors: [
        (0.20, 0.90, 0.70), (0.10, 0.75, 0.60), (0.30, 1.0, 0.80), (0.15, 0.85, 0.90)
    ]),
    ParticleColorScheme(name: "Quantum", colors: [
        (0.45, 0.70, 1.0), (0.60, 0.85, 1.0), (0.30, 0.55, 1.0), (0.75, 0.90, 1.0)
    ]),
    ParticleColorScheme(name: "Cosmic", colors: [
        (0.85, 0.50, 1.0), (1.0, 0.60, 0.90), (0.65, 0.35, 1.0), (1.0, 0.75, 1.0)
    ]),
    ParticleColorScheme(name: "Enigma", colors: [
        (0.55, 0.30, 0.95), (0.70, 0.45, 1.0), (0.40, 0.20, 0.85), (0.80, 0.55, 1.0)
    ]),
    ParticleColorScheme(name: "Graphite", colors: [
        (0.70, 0.72, 0.78), (0.82, 0.84, 0.88), (0.60, 0.62, 0.68), (0.90, 0.92, 0.95)
    ]),
    ParticleColorScheme(name: "Spatial", colors: [
        (0.40, 0.50, 1.0), (0.55, 0.40, 0.95), (0.30, 0.60, 1.0), (0.70, 0.50, 1.0)
    ]),
    ParticleColorScheme(name: "Neon Arcade", colors: [
        (0.20, 1.0, 0.45), (0.30, 0.95, 1.0), (0.10, 0.85, 0.35), (0.40, 1.0, 0.80)
    ]),
    ParticleColorScheme(name: "Neural", colors: [
        (1.0, 0.65, 0.25), (1.0, 0.80, 0.40), (0.95, 0.55, 0.15), (1.0, 0.90, 0.55)
    ]),
    ParticleColorScheme(name: "Titanium", colors: [
        (0.85, 0.87, 0.92), (0.92, 0.94, 0.97), (0.75, 0.78, 0.85), (1.0, 1.0, 1.0)
    ]),
    ParticleColorScheme(name: "Matrix", colors: [
        (0.10, 0.90, 0.20), (0.20, 1.0, 0.30), (0.05, 0.75, 0.15), (0.30, 1.0, 0.40)
    ]),
    ParticleColorScheme(name: "Spectrum", colors: [
        (1.0, 0.30, 0.30), (0.30, 1.0, 0.40), (0.30, 0.50, 1.0), (1.0, 0.90, 0.20)
    ]),
    ParticleColorScheme(name: "Swift", colors: [
        (1.0, 0.60, 0.20), (1.0, 0.75, 0.35), (0.95, 0.50, 0.10), (1.0, 0.85, 0.50)
    ]),
    ParticleColorScheme(name: "Earth", colors: [
        (0.45, 0.65, 0.30), (0.55, 0.50, 0.30), (0.35, 0.55, 0.25), (0.65, 0.70, 0.40)
    ]),
    ParticleColorScheme(name: "Sky", colors: [
        (0.50, 0.80, 1.0), (0.65, 0.90, 1.0), (0.40, 0.70, 0.95), (0.80, 0.95, 1.0)
    ]),
    ParticleColorScheme(name: "Ladybug", colors: [
        (0.95, 0.15, 0.10), (1.0, 0.30, 0.20), (0.20, 0.20, 0.22), (0.85, 0.10, 0.05)
    ]),
    ParticleColorScheme(name: "Nautical", colors: [
        (0.15, 0.55, 0.85), (0.20, 0.70, 0.95), (0.10, 0.45, 0.75), (0.35, 0.80, 1.0)
    ]),
    ParticleColorScheme(name: "Cinema", colors: [
        (0.90, 0.75, 0.45), (0.85, 0.65, 0.35), (0.95, 0.85, 0.55), (0.80, 0.60, 0.30)
    ]),
    ParticleColorScheme(name: "Explorer", colors: [
        (0.55, 0.60, 0.35), (0.65, 0.70, 0.45), (0.45, 0.50, 0.28), (0.75, 0.78, 0.55)
    ]),
]

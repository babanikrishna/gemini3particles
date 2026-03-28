//
//  ContentView.swift
//  Gemini3Particles
//
//  Created by Krishna Babani on 2/19/26.
//

import SwiftUI

enum AppMode: String, CaseIterable {
    case particles = "Particles"
    case fireflies = "Fireflies"
}

struct ContentView: View {
    @State private var config = ParticleConfig()
    @State private var appMode: AppMode = .particles

    var body: some View {
        ZStack(alignment: .bottom) {
            switch appMode {
            case .particles:
                ParticleEffectView(config: config)
                    .ignoresSafeArea()
            case .fireflies:
                FireflyEffectView(config: config)
                    .ignoresSafeArea()
            }

            Picker("Mode", selection: $appMode) {
                ForEach(AppMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 100)
            .padding(.bottom, 40)
        }
        .preferredColorScheme(.dark)
    }
}

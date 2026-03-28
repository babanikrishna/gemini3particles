//
//  GlyphCatalog.swift
//  Gemini3Particles
//
//  Created by Krishna Babani on 2/19/26.
//

import SwiftUI

// MARK: - Glyph Layout Constants

private enum GlyphLayout {
    static let fontSizeRatio: CGFloat = 0.75
    static let singleCharMargin: CGFloat = 40
    static let multiCharMargin: CGFloat = 10
    static let multiCharWidthRatio: CGFloat = 0.85
    static let symbolMargin: CGFloat = 30
    static let pixelScanStep = 4
    static let brightnessThreshold: UInt8 = 128
    static let gridBrightnessThreshold: UInt8 = 60
    static let gridCoverageRatio = 3
}

// MARK: - Glyph

enum Glyph {
    case text(String)
    case symbol(String)
}

let glyphs: [Glyph] = [
    // 0-9 digits
    .text("0"), .text("1"), .text("2"), .text("3"), .text("4"),
    .text("5"), .text("6"), .text("7"), .text("8"), .text("9"),
    // SF Symbols
    .symbol("star.fill"),
    .symbol("heart.fill"),
    .symbol("bolt.fill"),
    .symbol("flame.fill"),
    .symbol("moon.stars.fill"),
    .symbol("sparkles"),
    .symbol("crown.fill"),
    .symbol("eye.fill"),
    .symbol("atom"),
    .symbol("infinity"),
    .symbol("questionmark"),
    .symbol("command"),
    .symbol("visionpro.fill"),
    .symbol("gamecontroller.fill"),
    .symbol("apple.intelligence"),
    .symbol("apple.logo"),
    .symbol("apple.terminal"),
    .symbol("rainbow"),
    .symbol("hare.fill"),
    .symbol("tortoise.fill"),
    .symbol("bird.fill"),
    .symbol("ladybug.fill"),
    .symbol("sailboat.fill"),
    .symbol("film.stack"),
    .symbol("binoculars.fill"),
]

// MARK: - Glyph Categories

struct GlyphCategory: Identifiable {
    let id = UUID()
    let name: String
    let indices: [Int]
}

let glyphCategories: [GlyphCategory] = [
    GlyphCategory(name: "Popular",      indices: [10, 11, 15, 12, 16]),
    GlyphCategory(name: "Nature",       indices: [13, 14, 27]),
    GlyphCategory(name: "Animals",      indices: [28, 29, 30, 31]),
    GlyphCategory(name: "Abstract",     indices: [17, 18, 19, 20]),
    GlyphCategory(name: "Apple & Tech", indices: [21, 22, 23, 24, 25, 26]),
    GlyphCategory(name: "Objects",      indices: [32, 33, 34]),
]

// MARK: - Glyph Rendering

private func renderGlyphBitmap(glyph: Glyph, size: CGSize) -> UIImage {
    let w = Int(size.width), h = Int(size.height)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1.0
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: format)

    return renderer.image { ctx in
        UIColor.black.setFill()
        ctx.fill(CGRect(origin: .zero, size: CGSize(width: w, height: h)))

        switch glyph {
        case .text(let text):
            let nsText = text as NSString
            let isMultiChar = text.count > 1
            let margin = isMultiChar ? GlyphLayout.multiCharMargin : GlyphLayout.singleCharMargin
            let maxW = CGFloat(w) - margin
            let maxH = CGFloat(h) - margin

            var fontSize = isMultiChar
                ? size.width * GlyphLayout.multiCharWidthRatio
                : min(size.width, size.height) * GlyphLayout.fontSizeRatio

            var font: UIFont = isMultiChar
                ? .monospacedDigitSystemFont(ofSize: fontSize, weight: .bold)
                : .systemFont(ofSize: fontSize, weight: .bold)

            var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
            let unlimited = CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
            var textSize = nsText.boundingRect(with: unlimited,
                options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs, context: nil).size

            if textSize.width > maxW || textSize.height > maxH {
                fontSize *= min(maxW / textSize.width, maxH / textSize.height)
                font = isMultiChar
                    ? .monospacedDigitSystemFont(ofSize: fontSize, weight: .bold)
                    : .systemFont(ofSize: fontSize, weight: .bold)
                attrs[.font] = font
                textSize = nsText.boundingRect(with: unlimited,
                    options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs, context: nil).size
            }

            let drawRect = CGRect(
                x: (CGFloat(w) - textSize.width) / 2, y: (CGFloat(h) - textSize.height) / 2,
                width: textSize.width + 1, height: textSize.height + 1)
            nsText.draw(with: drawRect, options: [.usesLineFragmentOrigin, .usesFontLeading],
                        attributes: attrs, context: nil)

        case .symbol(let name):
            let symbolSize = min(size.width, size.height) * GlyphLayout.fontSizeRatio
            let config = UIImage.SymbolConfiguration(pointSize: symbolSize, weight: .bold)
            guard let symbol = UIImage(systemName: name, withConfiguration: config)?
                .withTintColor(.white, renderingMode: .alwaysOriginal) else { return }
            let imgSize = symbol.size
            let margin = GlyphLayout.symbolMargin
            let availW = CGFloat(w) - margin * 2
            let availH = CGFloat(h) - margin * 2
            let scale = min(availW / imgSize.width, availH / imgSize.height, 1.0)
            let drawW = imgSize.width * scale, drawH = imgSize.height * scale
            symbol.draw(in: CGRect(
                x: (CGFloat(w) - drawW) / 2, y: (CGFloat(h) - drawH) / 2,
                width: drawW, height: drawH))
        }
    }
}

// MARK: - Glyph Point Sampling

func sampleGlyphPoints(glyph: Glyph, size: CGSize) -> [CGPoint] {
    let w = Int(size.width), h = Int(size.height)
    guard w > 0, h > 0 else { return [] }

    let image = renderGlyphBitmap(glyph: glyph, size: size)

    guard let cgImage = image.cgImage,
          let data = cgImage.dataProvider?.data,
          let ptr = CFDataGetBytePtr(data) else { return [] }

    let bytesPerRow = cgImage.bytesPerRow
    let bytesPerPixel = cgImage.bitsPerPixel / 8
    let step = GlyphLayout.pixelScanStep
    var points: [CGPoint] = []

    for y in stride(from: 0, to: h, by: step) {
        for x in stride(from: 0, to: w, by: step) {
            let offset = y * bytesPerRow + x * bytesPerPixel
            if ptr[offset] > GlyphLayout.brightnessThreshold {
                points.append(CGPoint(x: Double(x), y: Double(y)))
            }
        }
    }
    return points
}

// MARK: - Glyph Grid Sampling

func sampleGlyphGrid(glyph: Glyph, viewSize: CGSize, columns: Int, rows: Int, tileSize: CGFloat) -> [Bool] {
    let w = Int(viewSize.width), h = Int(viewSize.height)
    guard w > 0, h > 0, columns > 0, rows > 0 else {
        return Array(repeating: false, count: columns * rows)
    }

    let image = renderGlyphBitmap(glyph: glyph, size: viewSize)

    guard let cgImage = image.cgImage,
          let data = cgImage.dataProvider?.data,
          let ptr = CFDataGetBytePtr(data) else {
        return Array(repeating: false, count: columns * rows)
    }

    let bytesPerRow = cgImage.bytesPerRow
    let bytesPerPixel = cgImage.bitsPerPixel / 8
    var grid = Array(repeating: false, count: columns * rows)
    let sampleOffsets: [CGFloat] = [0.25, 0.5, 0.75]

    for row in 0..<rows {
        for col in 0..<columns {
            var hitCount = 0
            let totalSamples = sampleOffsets.count * sampleOffsets.count

            for sy in sampleOffsets {
                for sx in sampleOffsets {
                    let px = Int(CGFloat(col) * tileSize + tileSize * sx)
                    let py = Int(CGFloat(row) * tileSize + tileSize * sy)
                    if px >= 0, px < w, py >= 0, py < h {
                        let offset = py * bytesPerRow + px * bytesPerPixel
                        if ptr[offset] > GlyphLayout.gridBrightnessThreshold {
                            hitCount += 1
                        }
                    }
                }
            }

            if hitCount >= max(1, totalSamples * GlyphLayout.gridCoverageRatio / 10) {
                grid[row * columns + col] = true
            }
        }
    }

    return grid
}

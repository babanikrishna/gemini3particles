//
//  PhotoSampler.swift
//  Gemini3Particles
//
//  Created by Krishna Babani on 2/19/26.
//

import UIKit
import Vision

// MARK: - Colored Point

struct ColoredPoint {
    let x: Double
    let y: Double
    let r: Double
    let g: Double
    let b: Double
}

// MARK: - Photo Subject Sampling

func samplePhotoSubject(from image: UIImage, targetSize: CGSize) -> [ColoredPoint] {
    let w = Int(targetSize.width)
    let h = Int(targetSize.height)
    guard w > 0, h > 0 else { return [] }

    let margin: CGFloat = 30
    let availW = CGFloat(w) - margin * 2
    let availH = CGFloat(h) - margin * 2
    let imgAspect = image.size.width / image.size.height
    let canvasAspect = availW / availH
    let drawW: CGFloat, drawH: CGFloat
    if imgAspect > canvasAspect {
        drawW = availW
        drawH = availW / imgAspect
    } else {
        drawH = availH
        drawW = availH * imgAspect
    }
    let offsetX = (CGFloat(w) - drawW) / 2
    let offsetY = (CGFloat(h) - drawH) / 2

    guard let sourceCG = image.cgImage else { return [] }

    var cutoutCG: CGImage?

    let request = VNGenerateForegroundInstanceMaskRequest()
    let handler = VNImageRequestHandler(cgImage: sourceCG, options: [:])
    do {
        try handler.perform([request])
        if let result = request.results?.first {
            let maskedBuffer = try result.generateMaskedImage(
                ofInstances: result.allInstances,
                from: handler,
                croppedToInstancesExtent: false
            )
            let ciImage = CIImage(cvPixelBuffer: maskedBuffer)
            let ciCtx = CIContext()
            cutoutCG = ciCtx.createCGImage(ciImage, from: ciImage.extent)
        }
    } catch {}

    let samplingCG: CGImage = cutoutCG ?? sourceCG

    guard let sampleData = samplingCG.dataProvider?.data,
          let samplePtr = CFDataGetBytePtr(sampleData) else { return [] }
    let sampleBPR = samplingCG.bytesPerRow
    let sampleBPP = samplingCG.bitsPerPixel / 8
    let srcW = samplingCG.width
    let srcH = samplingCG.height

    let step = 4
    var points: [ColoredPoint] = []

    for sy in stride(from: 0, to: srcH, by: step) {
        for sx in stride(from: 0, to: srcW, by: step) {
            let offset = sy * sampleBPR + sx * sampleBPP
            let cr = Double(samplePtr[offset]) / 255.0
            let cg = Double(samplePtr[offset + 1]) / 255.0
            let cb = Double(samplePtr[offset + 2]) / 255.0
            if cr + cg + cb > 0.15 {
                let canvasX = offsetX + (Double(sx) / Double(srcW)) * drawW
                let canvasY = offsetY + (Double(sy) / Double(srcH)) * drawH
                points.append(ColoredPoint(x: canvasX, y: canvasY, r: cr, g: cg, b: cb))
            }
        }
    }

    return points
}

// MARK: - Image Orientation

func normalizeOrientation(_ image: UIImage) -> UIImage {
    let maxDim: CGFloat = 2048
    let size = image.size
    let needsResize = max(size.width, size.height) > maxDim
    guard image.imageOrientation != .up || needsResize else { return image }
    let scale = needsResize ? maxDim / max(size.width, size.height) : 1.0
    let newSize = CGSize(width: size.width * scale, height: size.height * scale)
    let renderer = UIGraphicsImageRenderer(size: newSize)
    return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
}

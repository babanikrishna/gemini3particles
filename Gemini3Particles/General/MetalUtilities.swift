//
//  MetalUtilities.swift
//  Gemini3Particles
//

import MetalKit

extension MTLRenderPipelineDescriptor {
    func configureAlphaBlending(pixelFormat: MTLPixelFormat) {
        colorAttachments[0].pixelFormat = pixelFormat
        colorAttachments[0].isBlendingEnabled = true
        colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        colorAttachments[0].sourceAlphaBlendFactor = .one
        colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
    }
}

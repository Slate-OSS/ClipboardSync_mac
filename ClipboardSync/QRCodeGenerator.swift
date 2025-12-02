//
//  QRCodeGenerator.swift
//  ClipboardSync
//
//  Created by Atharva on 02/12/25.
//

import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

class QRCodeGenerator {
    static func generateQRCode(from string: String) -> NSImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        let data = Data(string.utf8)
        
        filter.setValue(data, forKey: "inputMessage")
        
        guard let outputImage = filter.outputImage else {
            return nil
        }
        
        // Scale the image
        let scaleX = 400 / outputImage.extent.size.width
        let scaleY = 400 / outputImage.extent.size.height
        let transformedImage = outputImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        
        do {
            if let cgImage = context.createCGImage(transformedImage, from: transformedImage.extent) {
                return NSImage(cgImage: cgImage, size: NSSize(width: 400, height: 400))
            } else {
                return nil
            }
        } catch {
            print("QR Code generation failed: \(error)")
            return nil
        }
    }
}

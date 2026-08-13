//
//  RectangleRectifier.swift
//  QueenRight
//
//  §5.3 — Vision finds the frame's edges and the app rectifies the perspective, so a
//  photo taken at an angle over an open hive still measures correctly. Tolerance is
//  about 30° off square (acceptance 6).
//
//  When no rectangle is detectable this returns nil and the capture screen offers the
//  estimate-by-eye slider instead — the app stays fully usable (acceptance 7).
//

import UIKit
import Vision
import CoreImage

enum RectangleRectifier {

    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    struct Result {
        let image: UIImage
        /// Confidence Vision reported for the rectangle it found.
        let confidence: Float
    }

    /// Find the dominant rectangle and flatten it to square.
    static func rectify(_ image: UIImage) async -> Result? {
        guard let cgImage = image.cgImage else { return nil }

        let observation: VNRectangleObservation? = await withCheckedContinuation { continuation in
            let request = VNDetectRectanglesRequest { request, _ in
                let best = (request.results as? [VNRectangleObservation])?
                    .max(by: { $0.confidence < $1.confidence })
                continuation.resume(returning: best)
            }
            // A brood frame is a wide rectangle; allow generous skew so a shot taken
            // leaning over the box still resolves.
            request.minimumAspectRatio = 0.3
            request.maximumAspectRatio = 1.0
            request.minimumSize = 0.25
            request.minimumConfidence = 0.6
            request.quadratureTolerance = 30      // ~30° off square
            request.maximumObservations = 8

            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: nil)
            }
        }

        guard let observation else { return nil }
        guard let corrected = perspectiveCorrect(cgImage: cgImage, observation: observation) else {
            return nil
        }
        return Result(image: corrected, confidence: observation.confidence)
    }

    private static func perspectiveCorrect(cgImage: CGImage,
                                           observation: VNRectangleObservation) -> UIImage? {
        let ci = CIImage(cgImage: cgImage)
        let w = ci.extent.width, h = ci.extent.height

        // Vision reports normalised coordinates with the origin bottom-left, which is
        // already CoreImage's convention — no flip needed.
        func point(_ p: CGPoint) -> CIVector {
            CIVector(x: p.x * w, y: p.y * h)
        }

        guard let filter = CIFilter(name: "CIPerspectiveCorrection") else { return nil }
        filter.setValue(ci, forKey: kCIInputImageKey)
        filter.setValue(point(observation.topLeft), forKey: "inputTopLeft")
        filter.setValue(point(observation.topRight), forKey: "inputTopRight")
        filter.setValue(point(observation.bottomLeft), forKey: "inputBottomLeft")
        filter.setValue(point(observation.bottomRight), forKey: "inputBottomRight")

        guard let output = filter.outputImage,
              let cg = context.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

import Foundation
import Vision
import CoreGraphics

enum OCRError: LocalizedError {
    case noText
    case visionFailure(String)

    var errorDescription: String? {
        switch self {
        case .noText:
            String(localized: "No text recognized in the captured region.")
        case .visionFailure(let msg):
            "Vision OCR failed: \(msg)"
        }
    }
}

enum OCRService {
    /// Recognize text in the given image. Returns the joined recognized strings,
    /// preserving block order from top-to-bottom. Throws `OCRError.noText` if Vision
    /// finds nothing.
    static func recognize(_ image: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: OCRError.visionFailure(error.localizedDescription))
                    return
                }
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                let joined = lines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                if joined.isEmpty {
                    continuation.resume(throwing: OCRError.noText)
                } else {
                    continuation.resume(returning: joined)
                }
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            // English first; Vision's mixed-script handling does the rest. Setting Chinese
            // explicitly improves zh recognition without hurting English accuracy.
            request.recognitionLanguages = ["en-US", "zh-Hans", "zh-Hant"]

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: OCRError.visionFailure(error.localizedDescription))
                }
            }
        }
    }
}

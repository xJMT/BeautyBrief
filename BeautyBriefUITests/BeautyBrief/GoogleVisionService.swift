import UIKit
import Foundation

// ─────────────────────────────────────────────
//  GoogleVisionService
//  Reads text off a product photo using the
//  Google Cloud Vision API (TEXT_DETECTION).
//
//  Setup — takes ~10 minutes:
//  1. Go to https://console.cloud.google.com
//  2. Create a project (or use an existing one)
//  3. Enable "Cloud Vision API" in the API Library
//  4. Go to Credentials → Create API Key
//  5. Copy the key and paste it below in APIKeys.swift
//     (or set GOOGLE_VISION_API_KEY in your .xcconfig)
//
//  Cost: $1.50 per 1,000 images.
//  First 1,000 images per month are FREE.
// ─────────────────────────────────────────────

@MainActor
final class GoogleVisionService {

    static let shared = GoogleVisionService()

    private let endpoint = "https://vision.googleapis.com/v1/images:annotate"
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest  = 15
        config.timeoutIntervalForResource = 30
        session = URLSession(configuration: config)
    }

    // MARK: — Public

    /// Detects and returns all text lines from a product photo.
    /// Throws `VisionError.apiKeyMissing` if no key is configured.
    func detectText(in image: UIImage) async throws -> [String] {
        let key = APIKeys.googleVision
        guard !key.isEmpty else {
            throw VisionError.apiKeyMissing
        }

        guard let jpegData = prepareImage(image) else {
            throw VisionError.imagePreparationFailed
        }

        guard let url = URL(string: "\(endpoint)?key=\(key)") else {
            throw VisionError.networkError("Invalid API URL")
        }

        let body = VisionRequestBody(base64Image: jpegData.base64EncodedString())
        let bodyData = try JSONEncoder().encode(body)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw VisionError.networkError("No HTTP response")
        }
        guard http.statusCode == 200 else {
            throw VisionError.networkError("HTTP \(http.statusCode)")
        }

        let decoded = try JSONDecoder().decode(VisionResponse.self, from: data)

        // Check for API-level error (e.g. invalid key)
        if let error = decoded.responses.first?.error {
            throw VisionError.apiError(error.message ?? "Unknown API error")
        }

        return extractLines(from: decoded)
    }

    /// Builds a search query from raw Vision text lines.
    /// Filters out measurements, legal text, directions, etc.
    func extractProductQuery(from lines: [String]) -> String? {
        let noisePatterns: [String] = [
            "^\\d+[\\s]*(ml|oz|g|kg|fl|l)$",  // pure measurements
            "^[\\d\\s\\.]+$",                   // just numbers
            "www\\.",                            // websites
            "made in",
            "manufactured",
            "distributed by",
            "directions",
            "how to use",
            "ingredients:",
            "warning",
            "caution",
            "keep out",
            "for external use",
            "avoid contact",
            "if irritation",
            "net wt",
            "net weight",
            "©", "®", "™",
            "upc",
            "lot no",
            "batch",
            "exp date",
        ]

        let meaningful = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { line in
                guard line.count >= 3 else { return false }
                let lower = line.lowercased()
                for pattern in noisePatterns {
                    if lower.range(of: pattern, options: .regularExpression) != nil {
                        return false
                    }
                    if lower.contains(pattern) { return false }
                }
                return true
            }

        guard !meaningful.isEmpty else { return nil }
        // First 3 meaningful lines make a good search query
        return Array(meaningful.prefix(3)).joined(separator: " ")
    }

    // MARK: — Private

    /// Resize to max 1024px and compress — keeps Vision API calls fast and cheap
    private func prepareImage(_ image: UIImage) -> Data? {
        let maxDimension: CGFloat = 1024
        let scale = min(maxDimension / image.size.width,
                        maxDimension / image.size.height, 1.0)
        let newSize = CGSize(width:  image.size.width  * scale,
                             height: image.size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized  = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        return resized.jpegData(compressionQuality: 0.75)
    }

    private func extractLines(from response: VisionResponse) -> [String] {
        // fullTextAnnotation.text is the cleanest source
        if let text = response.responses.first?.fullTextAnnotation?.text {
            return text
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        // Fall back to the first textAnnotation (whole-image description)
        if let description = response.responses.first?.textAnnotations?.first?.description {
            return description
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        return []
    }
}

// MARK: — Errors

enum VisionError: LocalizedError {
    case apiKeyMissing
    case imagePreparationFailed
    case networkError(String)
    case apiError(String)
    case noTextDetected

    var errorDescription: String? {
        switch self {
        case .apiKeyMissing:
            return "Google Vision API key not set. Add your key to APIKeys.swift."
        case .imagePreparationFailed:
            return "Could not prepare image for upload."
        case .networkError(let msg):
            return "Network error: \(msg)"
        case .apiError(let msg):
            return "Vision API error: \(msg)"
        case .noTextDetected:
            return "No text detected on product label. Try better lighting or move closer."
        }
    }
}

// MARK: — Request / Response Codable Structs

private struct VisionRequestBody: Encodable {
    let requests: [AnnotateImageRequest]

    init(base64Image: String) {
        requests = [AnnotateImageRequest(base64Image: base64Image)]
    }
}

private struct AnnotateImageRequest: Encodable {
    let image: ImageContent
    let features: [Feature]
    let imageContext: ImageContext

    init(base64Image: String) {
        image        = ImageContent(content: base64Image)
        features     = [Feature(type: "TEXT_DETECTION", maxResults: 1)]
        imageContext = ImageContext(languageHints: ["en"])
    }
}

private struct ImageContent: Encodable {
    let content: String
}

private struct Feature: Encodable {
    let type: String
    let maxResults: Int
}

private struct ImageContext: Encodable {
    let languageHints: [String]
}

private struct VisionResponse: Decodable {
    let responses: [AnnotateResponse]
}

private struct AnnotateResponse: Decodable {
    let textAnnotations: [TextAnnotation]?
    let fullTextAnnotation: FullTextAnnotation?
    let error: VisionAPIError?
}

private struct TextAnnotation: Decodable {
    let description: String?
}

private struct FullTextAnnotation: Decodable {
    let text: String?
}

private struct VisionAPIError: Decodable {
    let code: Int?
    let message: String?
}

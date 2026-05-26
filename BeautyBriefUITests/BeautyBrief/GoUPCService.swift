import Foundation

// ─────────────────────────────────────────────
//  GoUPCService
//  500M+ global product database with barcode lookup.
//  Returns product name, brand, category, image — AND
//  ingredient text for millions of products including
//  cosmetics, personal care, and food.
//
//  No scraping. Quality curated data.
//
//  Sign up / free trial: https://go-upc.com/account/sign-up?planId=developer
//  Docs:                  https://go-upc.com/docs
//  Pricing:               $74.95/month → 5,000 lookups
//                         $245/month   → 45,000 lookups
//
//  Auth: Bearer token in Authorization header
//  Endpoint: GET https://go-upc.com/api/v1/code/:barcode
//
//  Paste your API key into APIKeys.goUPC, or set
//  the GO_UPC_API_KEY environment variable.
// ─────────────────────────────────────────────

@MainActor
final class GoUPCService {

    static let shared = GoUPCService()

    private let baseURL = "https://go-upc.com/api/v1"
    private var apiKey: String { APIKeys.goUPC }

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest  = 12
        config.timeoutIntervalForResource = 25
        config.httpAdditionalHeaders = ["User-Agent": "BeautyBrief-iOS/1.0"]
        session = URLSession(configuration: config)
    }

    // MARK: — Barcode Lookup

    /// Looks up a product by barcode. Returns nil if not found, key missing, or quota exceeded.
    func fetchProduct(barcode: String) async -> Product? {
        guard !apiKey.isEmpty else { return nil }

        guard let url = URL(string: "\(baseURL)/code/\(barcode)") else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  http.statusCode == 200 else { return nil }
            let decoded = try JSONDecoder().decode(GoUPCResponse.self, from: data)
            guard let p = decoded.product else { return nil }
            return buildProduct(from: p, barcode: barcode)
        } catch {
            return nil
        }
    }

    // MARK: — Product Builder

    private func buildProduct(from p: GoUPCProduct, barcode: String) -> Product? {
        let name = (p.name ?? "").trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }

        let brand    = p.brand ?? "Unknown Brand"
        let imageURL = p.imageUrl
        let category = mapCategory(path: p.categoryPath ?? [], single: p.category ?? "")

        // Parse ingredient text if present
        let ingredients = parseIngredients(from: p.ingredients?.text)

        return Product(
            id: barcode,
            name: name,
            brand: brand,
            category: category,
            imageURL: imageURL,
            ingredients: ingredients,
            batchCode: nil,
            expiryInfo: nil,
            dataLastVerified: .now,
            dataSource: "Go-UPC"
        )
    }

    // MARK: — Ingredient Parsing

    /// Parses a raw comma/semicolon-separated ingredient string into [Ingredient].
    /// Enriches each entry from IngredientKnowledgeBase where possible.
    private func parseIngredients(from text: String?) -> [Ingredient] {
        guard let text, !text.isEmpty else { return [] }

        // Strip parenthetical sub-ingredients: e.g. "Fragrance (Linalool, Limonene)"
        let stripped = text.replacingOccurrences(
            of: "\\s*\\([^)]*\\)", with: "", options: .regularExpression
        )

        return stripped
            .components(separatedBy: CharacterSet(charactersIn: ",;|"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count > 1 }
            .enumerated()
            .compactMap { index, name in
                let key   = normalise(name)
                let known = IngredientKnowledgeBase.lookup(key)

                return Ingredient(
                    id: key.nilIfEmpty() ?? "ingredient-\(index + 1)",
                    inciName: name.capitalisingFirst(),
                    commonName: known?.commonName,
                    function: known?.functions ?? [.other],
                    description: known?.description ?? "Ingredient from product label.",
                    irritancyRisk: known?.irritancy ?? .low,
                    isCommonAllergen: known?.isAllergen ?? false,
                    allergenTags: known?.allergenTags ?? [],
                    concentrationRank: index + 1,
                    source: "Go-UPC"
                )
            }
    }

    // MARK: — Helpers

    private func normalise(_ raw: String) -> String {
        raw.lowercased()
           .replacingOccurrences(of: "/", with: " ")
           .components(separatedBy: .whitespaces)
           .filter { !$0.isEmpty }
           .joined(separator: " ")
    }

    private func mapCategory(path: [String], single: String) -> ProductCategory {
        // Use the full category path for better signal, fall back to single category
        let joined = (path + [single]).joined(separator: " ").lowercased()
        if joined.contains("hair")                                        { return .haircare  }
        if joined.contains("fragrance") || joined.contains("perfume")    { return .fragrance }
        if joined.contains("sun") || joined.contains("spf")              { return .suncare   }
        if joined.contains("makeup") || joined.contains("foundation") ||
           joined.contains("lipstick") || joined.contains("mascara") ||
           joined.contains("cosmetic")                                    { return .makeup    }
        if joined.contains("body lotion") || joined.contains("body wash") ||
           joined.contains("body care")                                   { return .bodycare  }
        if joined.contains("skin care") || joined.contains("skincare") ||
           joined.contains("face") || joined.contains("moistur") ||
           joined.contains("serum") || joined.contains("toner") ||
           joined.contains("cleanser") || joined.contains("beauty") ||
           joined.contains("personal care")                               { return .skincare  }
        if joined.contains("body")                                        { return .bodycare  }
        return .unknown
    }
}

// MARK: — String helpers (private extension, mirrors OBF style)

private extension String {
    func nilIfEmpty() -> String? { isEmpty ? nil : self }

    func capitalisingFirst() -> String {
        guard let first = first else { return self }
        return first.uppercased() + dropFirst()
    }
}

// MARK: — Response Models

private struct GoUPCResponse: Decodable {
    let code: String?
    let codeType: String?
    let product: GoUPCProduct?
    let inferred: Bool?
}

private struct GoUPCProduct: Decodable {
    let name: String?
    let description: String?
    let imageUrl: String?
    let brand: String?
    let specs: [[String]]?       // Array of [key, value] pairs
    let category: String?
    let categoryPath: [String]?
    let ingredients: GoUPCIngredients?
}

private struct GoUPCIngredients: Decodable {
    let text: String?
}

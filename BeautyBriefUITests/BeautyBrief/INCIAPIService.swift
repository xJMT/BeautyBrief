import Foundation

// ─────────────────────────────────────────────
//  INCIAPIService
//  Beauty ingredient intelligence from inciapi.com.
//  Returns the full INCI list for a barcode with
//  safety scores, allergens, and skin compatibility.
//
//  Sign up (free): https://inciapi.com/register
//  Docs:           https://inciapi.com/docs
//
//  Tiers:
//    Free    — 100 requests / month
//    Starter — 5,000 requests / month
//
//  Paste your key into APIKeys.inciAPI below,
//  or set the INCI_API_KEY environment variable.
// ─────────────────────────────────────────────

@MainActor
final class INCIAPIService {

    static let shared = INCIAPIService()

    private let baseURL = "https://api.inciapi.com/v1"
    private var apiKey: String { APIKeys.inciAPI }

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest  = 12
        config.timeoutIntervalForResource = 25
        config.httpAdditionalHeaders = ["User-Agent": "BeautyBrief-iOS/1.0"]
        session = URLSession(configuration: config)
    }

    // MARK: — Barcode Lookup

    /// Looks up a product by barcode. Returns nil if not found, key missing, or rate limited.
    func fetchProduct(barcode: String) async -> Product? {
        guard !apiKey.isEmpty else { return nil }

        guard let url = URL(string: "\(baseURL)/products/\(barcode)") else { return nil }
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  http.statusCode == 200 else { return nil }
            let decoded = try JSONDecoder().decode(INCIProductResponse.self, from: data)
            guard decoded.success, let p = decoded.data else { return nil }
            return buildProduct(from: p, barcode: barcode)
        } catch {
            return nil
        }
    }

    // MARK: — Product Builder

    private func buildProduct(from p: INCIProduct, barcode: String) -> Product? {
        let name = p.name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }

        // Map INCI list → Ingredient array, enriched from our local knowledge base
        var seenIDs = Set<String>()
        let ingredients: [Ingredient] = p.inciList.enumerated().compactMap { index, raw in
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }

            let key   = normalise(trimmed)
            let known = IngredientKnowledgeBase.lookup(key)

            // Ensure unique IDs within the product (rare but possible in some formulas)
            var uniqueID = key.isEmpty ? "ingredient-\(index + 1)" : key
            if !seenIDs.insert(uniqueID).inserted {
                uniqueID = "\(uniqueID)-\(index + 1)"
            }

            return Ingredient(
                id: uniqueID,
                inciName: trimmed,
                commonName: known?.commonName,
                function: known?.functions ?? [.other],
                description: known?.description ?? "Cosmetic ingredient from INCI list.",
                irritancyRisk: known?.irritancy ?? .low,
                isCommonAllergen: known?.isAllergen ?? false,
                allergenTags: known?.allergenTags ?? [],
                concentrationRank: index + 1,
                source: "INCI API"
            )
        }

        return Product(
            id: barcode,
            name: name,
            brand: p.brand,
            category: mapCategory(p.category ?? []),
            imageURL: p.imageUrls?.first,
            ingredients: ingredients,
            batchCode: nil,
            expiryInfo: nil,
            dataLastVerified: .now,
            dataSource: "INCI API"
        )
    }

    // MARK: — Helpers

    /// Lowercases and normalises whitespace for knowledge base lookup.
    private func normalise(_ raw: String) -> String {
        raw.lowercased()
           .replacingOccurrences(of: "/", with: " ")
           .components(separatedBy: .whitespaces)
           .filter { !$0.isEmpty }
           .joined(separator: " ")
    }

    private func mapCategory(_ categories: [String]) -> ProductCategory {
        let joined = categories.joined(separator: " ").lowercased()
        if joined.contains("hair")                                     { return .haircare  }
        if joined.contains("fragrance") || joined.contains("perfume")  { return .fragrance }
        if joined.contains("sun") || joined.contains("spf")            { return .suncare   }
        if joined.contains("makeup") || joined.contains("foundation") ||
           joined.contains("lipstick") || joined.contains("mascara")   { return .makeup    }
        if joined.contains("body")                                     { return .bodycare  }
        if joined.contains("skin") || joined.contains("face") ||
           joined.contains("moistur") || joined.contains("serum") ||
           joined.contains("cleanser") || joined.contains("toner")     { return .skincare  }
        return .unknown
    }
}

// MARK: — Response Models

private struct INCIProductResponse: Decodable {
    let success: Bool
    let data: INCIProduct?
}

private struct INCIProduct: Decodable {
    let barcode: String?
    let name: String
    let brand: String
    let category: [String]?
    let imageUrls: [String]?
    let inciList: [String]
    let qualityScore: Int?
}

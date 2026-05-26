import Foundation

// ─────────────────────────────────────────────
//  OpenBeautyFactsService
//  Free cosmetic product database — no API key.
//  https://world.openbeautyfacts.org/api
//
//  Usage:
//    let product = await OpenBeautyFactsService.shared.fetchProduct(barcode: "301871194994")
// ─────────────────────────────────────────────

// Not @MainActor — this is a pure network service.
// URLSession is thread-safe; keeping this off the main actor means async let calls
// from ScannerViewModel and ProductDatabaseService run truly in parallel.
final class OpenBeautyFactsService {

    static let shared = OpenBeautyFactsService()

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest  = 12
        config.timeoutIntervalForResource = 25
        // OBF asks developers to identify their app
        config.httpAdditionalHeaders = [
            "User-Agent": "BeautyBrief-iOS/1.0 (iOS; https://beautybrief.app)"
        ]
        session = URLSession(configuration: config)
    }

    // Shared fields parameter
    private let fields = "product_name,brands,image_front_url,image_url," +
                         "ingredients,ingredients_text,categories_tags,periods_after_opening"

    // MARK: — Public API

    /// Looks up a barcode in Open Beauty Facts. Returns nil if not found.
    func fetchProduct(barcode: String) async -> Product? {
        return await fetchFromBase("https://world.openbeautyfacts.org", barcode: barcode)
    }

    /// Looks up a barcode in Open Food Facts (sister project — 4M+ food products).
    func fetchFromOpenFoodFacts(barcode: String) async -> Product? {
        return await fetchFromBase("https://world.openfoodfacts.org", barcode: barcode)
    }

    /// Looks up a barcode in Open Products Facts (general consumer products — personal care,
    /// cleaning, pet food, etc. Same API format, different database from the same team).
    func fetchFromOpenProductsFacts(barcode: String) async -> Product? {
        return await fetchFromBase("https://world.openproductsfacts.org", barcode: barcode)
    }

    /// Internal lookup against any Open*Facts base URL.
    private func fetchFromBase(_ base: String, barcode: String) async -> Product? {
        let urlString = "\(base)/api/v2/product/\(barcode).json?fields=\(fields)"
        guard let url = URL(string: urlString) else { return nil }

        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            let decoded = try JSONDecoder().decode(OBFResponse.self, from: data)
            guard decoded.status == 1, let obfProduct = decoded.product else { return nil }
            return buildProduct(from: obfProduct, barcode: barcode)
        } catch {
            return nil
        }
    }

    /// Searches by product name across both Open Beauty Facts and Open Food Facts.
    /// Returns up to 5 matches, deduped by product name.
    func searchByName(_ query: String) async -> [Product] {
        async let obfResults  = searchByName(query, base: "https://world.openbeautyfacts.org")
        async let offResults  = searchByName(query, base: "https://world.openfoodfacts.org")
        let (beauty, food) = await (obfResults, offResults)

        // Merge, preferring OBF results, dedup by normalised name
        var seen  = Set<String>()
        var merged: [Product] = []
        for product in (beauty + food) {
            let key = product.name.lowercased().trimmingCharacters(in: .whitespaces)
            if seen.insert(key).inserted { merged.append(product) }
            if merged.count >= 5 { break }
        }
        return merged
    }

    private func searchByName(_ query: String, base: String) async -> [Product] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let urlString = "\(base)/cgi/search.pl" +
                        "?search_terms=\(encoded)&search_simple=1&action=process" +
                        "&json=1&page_size=5&fields=\(fields)"

        guard let url = URL(string: urlString) else { return [] }

        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }
            let decoded = try JSONDecoder().decode(OBFSearchResponse.self, from: data)
            return decoded.products.compactMap { buildProduct(from: $0, barcode: $0.code ?? UUID().uuidString) }
        } catch {
            return []
        }
    }
}

// MARK: — JSON Structures

private struct OBFResponse: Decodable {
    let status: Int
    let product: OBFProduct?
}

private struct OBFProduct: Decodable {
    let code: String?              // barcode (present in search results)
    let product_name: String?
    let brands: String?
    let image_front_url: String?
    let image_url: String?
    let ingredients: [OBFIngredient]?
    let ingredients_text: String?
    let categories_tags: [String]?
    let periods_after_opening: String?
}

private struct OBFSearchResponse: Decodable {
    let products: [OBFProduct]
}

private struct OBFIngredient: Decodable {
    let id: String?        // e.g. "en:water"
    let text: String?      // e.g. "Aqua"
    let percent_min: Double?
    let percent_max: Double?
}

// MARK: — Product Builder

extension OpenBeautyFactsService {

    private func buildProduct(from p: OBFProduct, barcode: String) -> Product? {
        let name  = (p.product_name ?? "").trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }

        // Take first brand if multiple are listed
        let brand = p.brands?
            .components(separatedBy: ",").first?
            .trimmingCharacters(in: .whitespaces) ?? "Unknown Brand"

        // Prefer front image, fall back to any image
        let imageURL = p.image_front_url ?? p.image_url

        let category    = mapCategory(tags: p.categories_tags ?? [])
        let ingredients = buildIngredients(from: p)
        let pao         = parsePAO(p.periods_after_opening)

        let expiryInfo: ExpiryInfo? = pao.map { months in
            ExpiryInfo(
                manufacturingDate: nil,
                expiryDate: nil,
                periodAfterOpening: months,
                batchCode: "",
                isExpired: false,
                isNearExpiry: false
            )
        }

        return Product(
            id: barcode,
            name: name,
            brand: brand,
            category: category,
            imageURL: imageURL,
            ingredients: ingredients,
            batchCode: nil,
            expiryInfo: expiryInfo,
            dataLastVerified: .now,
            dataSource: "Open Beauty Facts"
        )
    }

    // MARK: — Ingredients

    private func buildIngredients(from p: OBFProduct) -> [Ingredient] {
        // Prefer OBF structured list when available
        if let structured = p.ingredients, !structured.isEmpty {
            return structured.enumerated().compactMap { index, ing in
                ingredient(from: ing, rank: index + 1)
            }
        }
        // Fall back to parsing the raw ingredients text
        if let text = p.ingredients_text, !text.isEmpty {
            return parseIngredientsText(text)
        }
        return []
    }

    private func ingredient(from obf: OBFIngredient, rank: Int) -> Ingredient? {
        // Derive a display name: prefer text, fall back to id
        let rawName = (obf.text?.trimmingCharacters(in: .whitespaces) ?? "")
            .nilIfEmpty()
            ?? obf.id.flatMap { extractLabel(fromID: $0) }
            ?? ""
        guard !rawName.isEmpty else { return nil }

        let key   = normalise(rawName)
        let known = IngredientKnowledgeBase.lookup(key)

        return Ingredient(
            id: key.nilIfEmpty() ?? "ingredient-\(rank)",
            inciName: rawName.capitalisingFirst(),
            commonName: known?.commonName,
            function: known?.functions ?? [.other],
            description: known?.description ?? "Ingredient from product label.",
            irritancyRisk: known?.irritancy ?? .low,
            isCommonAllergen: known?.isAllergen ?? false,
            allergenTags: known?.allergenTags ?? [],
            concentrationRank: rank,
            source: "Open Beauty Facts"
        )
    }

    private func parseIngredientsText(_ text: String) -> [Ingredient] {
        // Expand parenthetical sub-ingredients rather than strip them.
        // "Fragrance (Linalool, Limonene)" → ["Fragrance", "Linalool", "Limonene"]
        // This preserves EU-regulated fragrance allergens and other declared sub-components.
        let parentPattern = try? NSRegularExpression(pattern: "([^,;(]+)\\(([^)]+)\\)")
        var processed = text

        if let pattern = parentPattern {
            let range = NSRange(text.startIndex..., in: text)
            let matches = pattern.matches(in: text, range: range)
            for match in matches.reversed() {
                guard let fullRange  = Range(match.range(at: 0), in: text),
                      let parentRange = Range(match.range(at: 1), in: text),
                      let subRange   = Range(match.range(at: 2), in: text) else { continue }
                let parent = String(text[parentRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                let subs   = String(text[subRange]).components(separatedBy: ",").map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                }.filter { !$0.isEmpty }
                // Replace the matched region with parent + subs joined by comma
                let replacement = ([parent] + subs).joined(separator: ", ")
                processed = processed.replacingCharacters(in: fullRange, with: replacement)
            }
        }

        return processed
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
                    source: "Open Beauty Facts"
                )
            }
    }

    // MARK: — Helpers

    /// "en:shea-butter" → "Shea Butter"
    private func extractLabel(fromID id: String) -> String? {
        let parts = id.components(separatedBy: ":")
        guard parts.count >= 2 else { return nil }
        return parts.last?
            .replacingOccurrences(of: "-", with: " ")
            .capitalisingFirst()
    }

    /// Lowercases, collapses whitespace, strips slashes for KB lookup
    private func normalise(_ raw: String) -> String {
        raw.lowercased()
           .replacingOccurrences(of: "/", with: " ")
           .components(separatedBy: .whitespaces)
           .filter { !$0.isEmpty }
           .joined(separator: " ")
    }

    private func mapCategory(tags: [String]) -> ProductCategory {
        let joined = tags.joined(separator: " ").lowercased()
        if joined.contains("hair")                                { return .haircare  }
        if joined.contains("fragrance") || joined.contains("perfume") { return .fragrance }
        if joined.contains("sun") || joined.contains("spf")       { return .suncare   }
        if joined.contains("makeup")   || joined.contains("foundation") ||
           joined.contains("lipstick") || joined.contains("mascara")   { return .makeup    }
        if joined.contains("body")                                { return .bodycare  }
        if joined.contains("skin") || joined.contains("face") ||
           joined.contains("serum") || joined.contains("cleanser") ||
           joined.contains("moisturiser") || joined.contains("moisturizer") { return .skincare }
        return .unknown
    }

    /// Parses "12 months", "24M" → Int months
    private func parsePAO(_ raw: String?) -> Int? {
        guard let raw else { return nil }
        return raw.components(separatedBy: CharacterSet.decimalDigits.inverted)
                  .compactMap { Int($0) }
                  .first
    }
}

// MARK: — String helpers

private extension String {
    func nilIfEmpty() -> String? { isEmpty ? nil : self }

    func capitalisingFirst() -> String {
        guard let first = first else { return self }
        return first.uppercased() + dropFirst()
    }
}

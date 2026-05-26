import Foundation

// ─────────────────────────────────────────────
//  ProductWebSearchService
//
//  When no database has a product, this service
//  searches the open web to find ingredient data.
//
//  Pipeline (in order):
//    Step 1 — Vision already read brand + name
//    Step 2 — Search INCIDecoder  (free, no key)
//    Step 3 — Search SkinSafe     (free, no key)
//    Step 4 — Search brand site   (Google Custom Search if configured)
//    Step 5 — Return enriched Product
//
//  No extra API keys required for steps 2 & 3.
//  Steps 2 & 3 cover the vast majority of products.
// ─────────────────────────────────────────────

final class ProductWebSearchService {

    static let shared = ProductWebSearchService()

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest  = 12
        config.timeoutIntervalForResource = 25
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15"
        ]
        session = URLSession(configuration: config)
    }

    // MARK: — Public Entry Point

    /// Full web ingredient search. Tries INCIDecoder → SkinSafe → brand site.
    /// Returns a partial Product with ingredients populated, or nil.
    func searchIngredients(
        brand: String,
        productName: String,
        existingImageURL: String? = nil
    ) async -> Product? {
        let query = "\(brand) \(productName)"

        // Step 2: INCIDecoder — largest cosmetic ingredient database
        if let result = await searchINCIDecoder(query: query) {
            return buildProduct(from: result, brand: brand,
                                productName: productName,
                                fallbackImageURL: existingImageURL)
        }

        // Step 3: SkinSafe — strong on safety ratings, good coverage
        if let result = await searchSkinSafe(query: query) {
            return buildProduct(from: result, brand: brand,
                                productName: productName,
                                fallbackImageURL: existingImageURL)
        }

        // Step 4: Brand's own website (requires Google Custom Search)
        if let result = await searchBrandSite(brand: brand, productName: productName) {
            return buildProduct(from: result, brand: brand,
                                productName: productName,
                                fallbackImageURL: existingImageURL)
        }

        return nil
    }

    // MARK: — Step 2: INCIDecoder

    private func searchINCIDecoder(query: String) async -> WebIngredientResult? {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let searchURL = "https://incidecoder.com/search?query=\(encoded)"

        guard let html = await fetchHTML(from: searchURL) else { return nil }

        // Extract first product link — try both the standard href pattern and the
        // data-* attribute variant INCIDecoder sometimes uses
        let productPath = firstMatch(in: html,
                pattern: #"href="(/products/[^"?#]+)""#, group: 1)
            ?? firstMatch(in: html,
                pattern: #"data-href="(/products/[^"?#]+)""#, group: 1)
            ?? firstMatch(in: html,
                pattern: #"/products/([\w-]+)"#, group: 0).map { "/products/" + $0.components(separatedBy: "/products/").last! }

        guard let path = productPath else { return nil }

        let productURL = "https://incidecoder.com\(path)"
        guard let productHTML = await fetchHTML(from: productURL) else { return nil }

        // INCIDecoder ingredient extraction — try several patterns in case they update their markup
        // Pattern A: original anchor with class="ingred-link"
        var ingredients = extractTagContent(
            from: productHTML,
            pattern: #"class="ingred-link[^"]*"[^>]*>([^<]+)<"#
        )

        // Pattern B: span inside ingredient list items (used in some redesigns)
        if ingredients.isEmpty {
            ingredients = extractTagContent(
                from: productHTML,
                pattern: #"<span[^>]+class="[^"]*ingredient[^"]*"[^>]*>([^<]{3,60})<"#
            )
        }

        // Pattern C: ingredient list as plain comma-separated text in a known container
        if ingredients.isEmpty {
            let stripped = stripHTML(productHTML)
            ingredients = extractIngredientSection(from: stripped)
        }

        guard !ingredients.isEmpty else { return nil }

        // Product image — try og:image meta first (most reliable), then inline img tag
        let imageURL = firstMatch(in: productHTML,
                pattern: #"property="og:image"[^>]+content="([^"]+)""#, group: 1)
            ?? firstMatch(in: productHTML,
                pattern: #"<img[^>]+class="product-image[^"]*"[^>]+src="([^"]+)""#, group: 1)

        return WebIngredientResult(
            ingredientNames: ingredients,
            imageURL: imageURL,
            source: "INCIDecoder",
            sourceURL: productURL
        )
    }

    // MARK: — Step 3: SkinSafe

    private func searchSkinSafe(query: String) async -> WebIngredientResult? {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let searchURL = "https://www.skinsafeproducts.com/search?q=\(encoded)"

        guard let html = await fetchHTML(from: searchURL) else { return nil }

        // Find first product link in search results
        guard let productPath = firstMatch(in: html,
              pattern: #"href="(/[a-z0-9][^"]*)"[^>]*>[^<]*<img"#, group: 1) else { return nil }

        let productURL = "https://www.skinsafeproducts.com\(productPath)"
        guard let productHTML = await fetchHTML(from: productURL) else { return nil }

        // SkinSafe lists ingredients as plain text in a specific section
        // Look for the ingredients block between "Ingredients" header and next section
        let stripped = stripHTML(productHTML)
        let ingredients = extractIngredientSection(from: stripped)
        guard !ingredients.isEmpty else { return nil }

        return WebIngredientResult(
            ingredientNames: ingredients,
            imageURL: nil,
            source: "SkinSafe",
            sourceURL: productURL
        )
    }

    // MARK: — Step 4: Brand Site (Google Custom Search)

    private func searchBrandSite(brand: String, productName: String) async -> WebIngredientResult? {
        let key = APIKeys.googleCustomSearch
        let cx  = APIKeys.googleCustomSearchCX
        guard !key.isEmpty, !cx.isEmpty else { return nil }

        // Build a site-restricted query if we know the brand domain
        var queryBase = "\(brand) \(productName) ingredients"
        if let domain = BrandDirectory.domain(for: brand) {
            queryBase += " site:\(domain)"
        }

        let encoded = queryBase.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? queryBase
        let apiURL  = "https://www.googleapis.com/customsearch/v1?key=\(key)&cx=\(cx)&q=\(encoded)&num=3"

        guard let url = URL(string: apiURL) else { return nil }

        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            let decoded = try JSONDecoder().decode(GoogleSearchResponse.self, from: data)

            // Try each result until we find one with ingredient data
            for item in (decoded.items ?? []).prefix(3) {
                guard let pageURL = URL(string: item.link),
                      let html    = await fetchHTML(from: item.link) else { continue }
                let stripped     = stripHTML(html)
                let ingredients  = extractIngredientSection(from: stripped)
                if !ingredients.isEmpty {
                    return WebIngredientResult(
                        ingredientNames: ingredients,
                        imageURL: nil,
                        source: pageURL.host ?? "Brand Website",
                        sourceURL: item.link
                    )
                }
            }
        } catch { }
        return nil
    }

    // MARK: — Build Product from Result

    private func buildProduct(
        from result: WebIngredientResult,
        brand: String,
        productName: String,
        fallbackImageURL: String?
    ) -> Product {
        let ingredients = result.ingredientNames
            .enumerated()
            .map { index, name -> Ingredient in
                let key   = normalise(name)
                let known = IngredientKnowledgeBase.lookup(key)
                return Ingredient(
                    id: key.isEmpty ? "web-\(index)" : key,
                    inciName: name.capitalisingFirst(),
                    commonName: known?.commonName,
                    function: known?.functions ?? [.other],
                    description: known?.description ?? "Ingredient sourced from \(result.source).",
                    irritancyRisk: known?.irritancy ?? .low,
                    isCommonAllergen: known?.isAllergen ?? false,
                    allergenTags: known?.allergenTags ?? [],
                    concentrationRank: index + 1,
                    source: result.source
                )
            }

        return Product(
            id: UUID().uuidString,
            name: productName,
            brand: brand,
            category: .unknown,
            imageURL: result.imageURL ?? fallbackImageURL,
            ingredients: ingredients,
            batchCode: nil,
            expiryInfo: nil,
            dataLastVerified: .now,
            dataSource: result.source
        )
    }

    // MARK: — HTML Fetching

    private func fetchHTML(from urlString: String) async -> String? {
        guard let url = URL(string: urlString) else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else { return nil }
            return String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1)
        } catch {
            return nil
        }
    }

    // MARK: — HTML Parsing Helpers

    /// Strips all HTML tags and decodes common entities
    private func stripHTML(_ html: String) -> String {
        var result = html
        // Remove script and style blocks entirely
        result = result.replacingOccurrences(
            of: "<(script|style)[^>]*>[\\s\\S]*?</\\1>",
            with: " ", options: .regularExpression)
        // Remove all remaining tags
        result = result.replacingOccurrences(
            of: "<[^>]+>", with: " ", options: .regularExpression)
        // Decode common HTML entities
        result = result
            .replacingOccurrences(of: "&amp;",  with: "&")
            .replacingOccurrences(of: "&lt;",   with: "<")
            .replacingOccurrences(of: "&gt;",   with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;",  with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
        // Collapse whitespace
        result = result.replacingOccurrences(
            of: "\\s+", with: " ", options: .regularExpression)
        return result
    }

    /// Finds the ingredient list section in stripped plain text
    private func extractIngredientSection(from text: String) -> [String] {
        let lower = text.lowercased()

        // Find "ingredients" keyword
        guard let range = lower.range(of: #"\bingredients?\s*:?\s*"#,
                                       options: .regularExpression) else { return [] }
        let afterKeyword = String(text[range.upperBound...])

        // Take everything up to the next section-like boundary
        let boundaries = ["directions", "how to use", "warnings", "caution",
                          "about this product", "description", "reviews",
                          "you may also", "related products", "free of"]
        var end = afterKeyword.endIndex
        for b in boundaries {
            if let r = afterKeyword.lowercased().range(of: b) {
                if r.lowerBound < end { end = r.lowerBound }
            }
        }

        let ingredientBlock = String(afterKeyword[..<end])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Split by comma or bullet points
        return ingredientBlock
            .components(separatedBy: CharacterSet(charactersIn: ",•·"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count > 2 && $0.count < 80 }
            .filter { !$0.lowercased().contains("ingredients") }
    }

    /// Extracts captured group from first regex match
    private func firstMatch(in text: String, pattern: String, group: Int) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: group), in: text) else { return nil }
        return String(text[range])
    }

    /// Extracts all captured groups from all regex matches
    private func extractTagContent(from text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        return matches.compactMap { match -> String? in
            guard let range = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func normalise(_ raw: String) -> String {
        raw.lowercased()
           .replacingOccurrences(of: "/", with: " ")
           .components(separatedBy: .whitespaces)
           .filter { !$0.isEmpty }
           .joined(separator: " ")
    }
}

// MARK: — Supporting Types

struct WebIngredientResult {
    let ingredientNames: [String]
    let imageURL: String?
    let source: String
    let sourceURL: String
}

// MARK: — Google Custom Search Response

private struct GoogleSearchResponse: Decodable {
    let items: [SearchItem]?
    struct SearchItem: Decodable {
        let title: String
        let link: String
        let snippet: String?
    }
}

// MARK: — String helper

private extension String {
    func capitalisingFirst() -> String {
        guard let first = first else { return self }
        return first.uppercased() + dropFirst()
    }
}

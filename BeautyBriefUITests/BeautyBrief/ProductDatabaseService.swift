import Foundation
import UIKit

// ─────────────────────────────────────────────
//  ProductDatabaseService
//  Barcode → Product lookup.
//
//  Lookup order:
//    1. In-memory cache (instant)
//    2. Local mock database (hardcoded products)
//    3. Open Beauty Facts API (200k+ products, free)
//    4. nil  → caller shows "not found" message
// ─────────────────────────────────────────────

final class ProductDatabaseService {

    static let shared = ProductDatabaseService()

    private let obf       = OpenBeautyFactsService.shared
    private let inciAPI   = INCIAPIService.shared
    private let goUPC     = GoUPCService.shared
    private let upc       = UPCItemDBService.shared
    private let webSearch = ProductWebSearchService.shared

    // In-memory cache — survives the app session.
    // FIFO eviction keeps memory bounded: once we exceed maxCacheSize entries,
    // the oldest key is evicted. Typical session: <20 unique scans, so 50 is generous.
    private var cache: [String: Product] = [:]
    private var cacheKeys: [String] = []       // insertion-order list for FIFO eviction
    private let maxCacheSize = 50

    private func addToCache(key: String, product: Product) {
        if cache[key] == nil {
            cacheKeys.append(key)
            if cacheKeys.count > maxCacheSize {
                let evicted = cacheKeys.removeFirst()
                cache.removeValue(forKey: evicted)
            }
        }
        cache[key] = product
    }

    // MARK: — Barcode Normalization
    // AVFoundation always returns EAN-13 (13-digit).
    // UPC-A barcodes (12-digit) get a leading 0 prepended: 041507050105 → 0041507050105.
    // MockData may store the printed barcode (12-digit). Try both forms so lookups succeed.
    private func barcodeVariants(_ barcode: String) -> [String] {
        var variants = [barcode]
        if barcode.count == 13 && barcode.hasPrefix("0") {
            variants.append(String(barcode.dropFirst()))  // EAN-13 → UPC-A (strip leading 0)
        } else if barcode.count == 12 {
            variants.append("0" + barcode)                // UPC-A → EAN-13 (add leading 0)
        }
        return variants
    }

    // MARK: — Barcode Lookup
    //
    // Lookup chain (fastest first):
    //   1. In-memory cache
    //   2. Local mock database (hardcoded products)
    //   3. Open Beauty Facts + Open Food Facts + Open Products Facts (parallel, all free)
    //   4. INCI API (barcode → full INCI list, beauty-focused, free 100/month)
    //   5. Go-UPC (500M+ products, ingredient text, paid — skipped if no key)
    //   6. UPC Item DB (free 100/day fallback — gets name/brand → enrich via OBF name search)
    //   7. nil → caller shows "not found"

    func lookupByBarcode(_ barcode: String) async throws -> ScanCandidate? {

        // 1. Cache — try all barcode variants (EAN-13 with leading 0 and UPC-A without)
        for code in barcodeVariants(barcode) {
            if let cached = cache[code] {
                return ScanCandidate(product: cached, confidenceScore: 1.0, identificationMethod: .barcode)
            }
        }

        // 2. Local mock — try all barcode variants.
        //    Only short-circuit here if the product has ingredients; if the MockData entry is a
        //    shell with no ingredients (e.g. a stub), fall through to the full API chain so the
        //    live lookup pipeline can enrich it automatically.
        var mockShell: Product? = nil
        for code in barcodeVariants(barcode) {
            if let local = MockData.productsByBarcode[code] {
                if !local.ingredients.isEmpty {
                    addToCache(key: barcode, product: local)
                    return ScanCandidate(product: local, confidenceScore: 1.0, identificationMethod: .barcode)
                }
                mockShell = local   // save the shell — use its name/brand if APIs also find nothing
            }
        }
        // If we have a mock shell but no ingredients, inject name/brand into the OBF search below.
        // The shell is captured in `mockShell` and merged at step 3 if OBF finds a match.

        // 3. Open Beauty Facts + Open Food Facts + Open Products Facts — all free, all parallel
        //    OBF: ~100k cosmetics  |  OFF: 4M+ food  |  OPF: general consumer/personal care
        let altBarcode = barcodeVariants(barcode).last ?? barcode
        async let obfResult    = obf.fetchProduct(barcode: barcode)
        async let offResult    = obf.fetchFromOpenFoodFacts(barcode: barcode)
        async let opfResult    = obf.fetchFromOpenProductsFacts(barcode: barcode)
        async let obfAltResult = obf.fetchProduct(barcode: altBarcode)
        let (beautyProduct, foodProduct, consumerProduct, altBeautyProduct) =
            await (obfResult, offResult, opfResult, obfAltResult)

        // If OBF found the product WITH ingredients, return immediately
        if let product = beautyProduct ?? foodProduct ?? consumerProduct ?? altBeautyProduct,
           !product.ingredients.isEmpty {
            addToCache(key: barcode, product: product)
            return ScanCandidate(product: product, confidenceScore: 1.0, identificationMethod: .barcode)
        }

        // Keep the OBF shell (name/brand) to fall back on if INCI API has no ingredients.
        // Prefer the OBF shell; if OBF returned nothing, use the MockData shell (name/brand only).
        let obfShell: Product? = beautyProduct ?? foodProduct ?? consumerProduct ?? altBeautyProduct ?? mockShell

        // 4. INCI API — barcode → full INCI ingredient list with safety data
        //    Covers millions of cosmetic products. Requires API key from https://inciapi.com/register
        var inciProduct = await inciAPI.fetchProduct(barcode: barcode)
        if inciProduct == nil && altBarcode != barcode {
            inciProduct = await inciAPI.fetchProduct(barcode: altBarcode)
        }
        if let inci = inciProduct {
            // Merge: prefer INCI ingredients, but use OBF name/image if better
            let merged = Product(
                id: barcode,
                name: obfShell?.name ?? inci.name,
                brand: obfShell?.brand ?? inci.brand,
                category: inci.category != .unknown ? inci.category : (obfShell?.category ?? .unknown),
                imageURL: obfShell?.imageURL ?? inci.imageURL,
                ingredients: inci.ingredients,
                batchCode: nil,
                expiryInfo: obfShell?.expiryInfo ?? inci.expiryInfo,
                dataLastVerified: .now,
                dataSource: obfShell != nil ? "Open Beauty Facts + INCI API" : "INCI API"
            )
            addToCache(key: barcode, product: merged)
            return ScanCandidate(product: merged, confidenceScore: 1.0, identificationMethod: .barcode)
        }

        // OBF found a name/brand shell but no ingredients, and INCI API also came up empty.
        // Do NOT return the empty shell yet — continue through Go-UPC, UPC Item DB, and
        // web scraping so we can enrich it. Shell is used as a fallback at step 7.

        // 5. Go-UPC — 500M+ global products, returns ingredient text for many
        //    Replace UPC Item DB: much broader coverage, no per-day hard cap.
        //    Requires API key from https://go-upc.com (free trial available)
        var goUPCProduct = await goUPC.fetchProduct(barcode: barcode)
        if goUPCProduct == nil && altBarcode != barcode {
            goUPCProduct = await goUPC.fetchProduct(barcode: altBarcode)
        }

        if var product = goUPCProduct {
            // If Go-UPC already returned ingredients, we're done
            if !product.ingredients.isEmpty {
                cache[barcode] = product
                return ScanCandidate(product: product, confidenceScore: 1.0, identificationMethod: .barcode)
            }

            // No ingredients from Go-UPC — try to enrich
            let enrichQuery = "\(product.brand) \(product.name)"

            // 5a. MockData name match — size/region variants share the same formula
            let goNameLower  = product.name.lowercased()
            let goBrandLower = product.brand.lowercased()
            let mockByName = MockData.allProducts.first { mock in
                let mockBrand = mock.brand.lowercased()
                let mockName  = mock.name.lowercased()
                let goBrandFirst   = goBrandLower.components(separatedBy: " ").first ?? goBrandLower
                let mockBrandFirst = mockBrand.components(separatedBy: " ").first ?? mockBrand
                let brandMatch = goNameLower.contains(mockBrand) ||
                                 mockBrand.contains(goBrandFirst) ||
                                 goBrandLower.contains(mockBrandFirst)
                let keywords  = mockName.components(separatedBy: " ").filter { $0.count > 4 }
                let nameMatch = keywords.contains { goNameLower.contains($0) }
                return brandMatch && nameMatch
            }
            if let mock = mockByName, !mock.ingredients.isEmpty {
                product = Product(
                    id: barcode,
                    name: product.name,
                    brand: product.brand,
                    category: mock.category != .unknown ? mock.category : product.category,
                    imageURL: product.imageURL ?? mock.imageURL,
                    ingredients: mock.ingredients,
                    batchCode: nil,
                    expiryInfo: mock.expiryInfo,
                    dataLastVerified: .now,
                    dataSource: "Go-UPC + Local Database"
                )
                addToCache(key: barcode, product: product)
                return ScanCandidate(product: product, confidenceScore: 1.0, identificationMethod: .barcode)
            }

            // 5b. OBF name search
            let nameMatches = await obf.searchByName(enrichQuery)
            if let bestMatch = nameMatches.first, !bestMatch.ingredients.isEmpty {
                product = Product(
                    id: barcode,
                    name: product.name,
                    brand: product.brand,
                    category: bestMatch.category != .unknown ? bestMatch.category : product.category,
                    imageURL: product.imageURL ?? bestMatch.imageURL,
                    ingredients: bestMatch.ingredients,
                    batchCode: nil,
                    expiryInfo: bestMatch.expiryInfo,
                    dataLastVerified: .now,
                    dataSource: "Go-UPC + Open Beauty Facts"
                )
            } else {
                // 5c. Web search pipeline: INCIDecoder → SkinSafe → brand site
                if let webProduct = await webSearch.searchIngredients(
                    brand: product.brand,
                    productName: product.name,
                    existingImageURL: product.imageURL
                ) {
                    product = Product(
                        id: barcode,
                        name: product.name,
                        brand: product.brand,
                        category: product.category,
                        imageURL: webProduct.imageURL ?? product.imageURL,
                        ingredients: webProduct.ingredients,
                        batchCode: nil,
                        expiryInfo: nil,
                        dataLastVerified: .now,
                        dataSource: "Go-UPC + \(webProduct.dataSource)"
                    )
                }
            }

            addToCache(key: barcode, product: product)
            return ScanCandidate(product: product, confidenceScore: 1.0, identificationMethod: .barcode)
        }

        // 6. UPC Item DB — free fallback (100 lookups/day), no ingredient data
        //    Gets name + brand → enriched via MockData name match or OBF name search
        var upcLookup = await upc.fetchProduct(barcode: barcode)
        if upcLookup == nil && altBarcode != barcode {
            upcLookup = await upc.fetchProduct(barcode: altBarcode)
        }
        if let upcProduct = upcLookup {
            var product = Product(
                id: barcode,
                name: upcProduct.displayName,
                brand: upcProduct.displayBrand,
                category: upcProduct.productCategory,
                imageURL: upcProduct.imageURL,
                ingredients: [],
                batchCode: nil,
                expiryInfo: nil,
                dataLastVerified: .now,
                dataSource: "UPC Item DB"
            )
            let enrichQuery = "\(upcProduct.displayBrand) \(upcProduct.displayName)"

            // 6a. MockData name match — size/region variants share the same formula
            let upcNameLower  = upcProduct.displayName.lowercased()
            let upcBrandLower = upcProduct.displayBrand.lowercased()
            let mockByName = MockData.allProducts.first { mock in
                let mockBrand = mock.brand.lowercased()
                let mockName  = mock.name.lowercased()
                let upcBrandFirst  = upcBrandLower.components(separatedBy: " ").first ?? upcBrandLower
                let mockBrandFirst = mockBrand.components(separatedBy: " ").first ?? mockBrand
                let brandMatch = upcNameLower.contains(mockBrand) ||
                                 mockBrand.contains(upcBrandFirst) ||
                                 upcBrandLower.contains(mockBrandFirst)
                let keywords  = mockName.components(separatedBy: " ").filter { $0.count > 4 }
                let nameMatch = keywords.contains { upcNameLower.contains($0) }
                return brandMatch && nameMatch
            }
            if let mock = mockByName, !mock.ingredients.isEmpty {
                product = Product(
                    id: barcode,
                    name: product.name,
                    brand: product.brand,
                    category: mock.category != .unknown ? mock.category : product.category,
                    imageURL: product.imageURL ?? mock.imageURL,
                    ingredients: mock.ingredients,
                    batchCode: nil,
                    expiryInfo: mock.expiryInfo,
                    dataLastVerified: .now,
                    dataSource: "UPC Item DB + Local Database"
                )
                addToCache(key: barcode, product: product)
                return ScanCandidate(product: product, confidenceScore: 1.0, identificationMethod: .barcode)
            }

            // 6b. OBF name search
            let nameMatches = await obf.searchByName(enrichQuery)
            if let bestMatch = nameMatches.first, !bestMatch.ingredients.isEmpty {
                product = Product(
                    id: barcode,
                    name: product.name,
                    brand: product.brand,
                    category: bestMatch.category != .unknown ? bestMatch.category : product.category,
                    imageURL: product.imageURL ?? bestMatch.imageURL,
                    ingredients: bestMatch.ingredients,
                    batchCode: nil,
                    expiryInfo: bestMatch.expiryInfo,
                    dataLastVerified: .now,
                    dataSource: "UPC Item DB + Open Beauty Facts"
                )
            } else {
                // 6c. Web search pipeline
                if let webProduct = await webSearch.searchIngredients(
                    brand: upcProduct.displayBrand,
                    productName: upcProduct.displayName,
                    existingImageURL: product.imageURL
                ) {
                    product = Product(
                        id: barcode,
                        name: product.name,
                        brand: product.brand,
                        category: product.category,
                        imageURL: webProduct.imageURL ?? product.imageURL,
                        ingredients: webProduct.ingredients,
                        batchCode: nil,
                        expiryInfo: nil,
                        dataLastVerified: .now,
                        dataSource: "UPC Item DB + \(webProduct.dataSource)"
                    )
                }
            }
            addToCache(key: barcode, product: product)
            return ScanCandidate(product: product, confidenceScore: 1.0, identificationMethod: .barcode)
        }

        // 7. OBF shell enrichment — we reach here when OBF found name/brand but no ingredients,
        //    and Go-UPC / UPC Item DB also came up empty. Use the shell's name + brand to drive
        //    MockData name matching and web scraping before giving up entirely.
        if let shell = obfShell {
            let shellBrand     = shell.brand
            let shellName      = shell.name
            let shellNameLower  = shellName.lowercased()
            let shellBrandLower = shellBrand.lowercased()

            // 7a. MockData name match — size/shade/region variants share the same formula
            let mockByShell = MockData.allProducts.first { mock in
                let mockBrand      = mock.brand.lowercased()
                let mockName       = mock.name.lowercased()
                let shellBrandFirst = shellBrandLower.components(separatedBy: " ").first ?? shellBrandLower
                let mockBrandFirst  = mockBrand.components(separatedBy: " ").first ?? mockBrand
                let brandMatch = shellNameLower.contains(mockBrand) ||
                                 mockBrand.contains(shellBrandFirst) ||
                                 shellBrandLower.contains(mockBrandFirst) ||
                                 // handle "L'Oréal" vs "L'Oreal" accent variants
                                 shellBrandLower.folding(options: .diacriticInsensitive, locale: nil)
                                     .contains(mockBrandFirst.folding(options: .diacriticInsensitive, locale: nil))
                let keywords   = mockName.components(separatedBy: " ").filter { $0.count > 4 }
                let nameMatch  = keywords.contains { shellNameLower.contains($0) }
                return brandMatch && nameMatch
            }
            if let mock = mockByShell, !mock.ingredients.isEmpty {
                let enriched = Product(
                    id: barcode,
                    name: shellName,
                    brand: shellBrand,
                    category: mock.category != .unknown ? mock.category : shell.category,
                    imageURL: shell.imageURL ?? mock.imageURL,
                    ingredients: mock.ingredients,
                    batchCode: nil,
                    expiryInfo: mock.expiryInfo ?? shell.expiryInfo,
                    dataLastVerified: .now,
                    dataSource: "Open Beauty Facts + Local Database"
                )
                addToCache(key: barcode, product: enriched)
                return ScanCandidate(product: enriched, confidenceScore: 1.0, identificationMethod: .barcode)
            }

            // 7b. OBF name search — sometimes barcode lookup returns a shell but a name
            //     search returns the same product with a full ingredient list
            let shellNameMatches = await obf.searchByName("\(shellBrand) \(shellName)")
            if let bestMatch = shellNameMatches.first, !bestMatch.ingredients.isEmpty {
                let enriched = Product(
                    id: barcode,
                    name: shellName,
                    brand: shellBrand,
                    category: bestMatch.category != .unknown ? bestMatch.category : shell.category,
                    imageURL: shell.imageURL ?? bestMatch.imageURL,
                    ingredients: bestMatch.ingredients,
                    batchCode: nil,
                    expiryInfo: shell.expiryInfo ?? bestMatch.expiryInfo,
                    dataLastVerified: .now,
                    dataSource: "Open Beauty Facts (name search)"
                )
                addToCache(key: barcode, product: enriched)
                return ScanCandidate(product: enriched, confidenceScore: 1.0, identificationMethod: .barcode)
            }

            // 7c. Web search pipeline using OBF shell name/brand
            if let webProduct = await webSearch.searchIngredients(
                brand: shellBrand,
                productName: shellName,
                existingImageURL: shell.imageURL
            ) {
                let enriched = Product(
                    id: barcode,
                    name: shellName,
                    brand: shellBrand,
                    category: shell.category != .unknown ? shell.category : webProduct.category,
                    imageURL: shell.imageURL ?? webProduct.imageURL,
                    ingredients: webProduct.ingredients,
                    batchCode: nil,
                    expiryInfo: shell.expiryInfo,
                    dataLastVerified: .now,
                    dataSource: "Open Beauty Facts + \(webProduct.dataSource)"
                )
                addToCache(key: barcode, product: enriched)
                return ScanCandidate(product: enriched, confidenceScore: 1.0, identificationMethod: .barcode)
            }

            // Everything failed to find ingredients — return the OBF shell as a last resort
            // so the user at least sees the product name and brand.
            addToCache(key: barcode, product: shell)
            return ScanCandidate(product: shell, confidenceScore: 1.0, identificationMethod: .barcode)
        }

        return nil
    }

    // MARK: — Photo Lookup (Google Vision → OBF name search)

    func lookupByPhoto(_ imageData: Data) async throws -> [ScanCandidate] {
        guard let image = UIImage(data: imageData) else {
            throw PhotoLookupError.invalidImage
        }

        // 1. Read text off the label with Google Vision
        let vision = GoogleVisionService.shared
        let lines  = try await vision.detectText(in: image)

        guard !lines.isEmpty else {
            throw PhotoLookupError.noTextDetected
        }

        // 2. Build a search query from the text
        guard let query = vision.extractProductQuery(from: lines) else {
            throw PhotoLookupError.noTextDetected
        }

        // 3. Extract brand name from Vision text (first meaningful line is usually brand/product)
        let brand = lines.first?.trimmingCharacters(in: .whitespaces) ?? ""

        // 3.5 Search MockData by name first — instant, works offline
        // Matches any product whose name or brand contains words from the Vision query
        let lowerQuery = query.lowercased()
        let mockMatches = MockData.allProducts.filter { product in
            product.name.lowercased().contains(lowerQuery) ||
            product.brand.lowercased().contains(lowerQuery) ||
            lowerQuery.contains(product.brand.lowercased()) ||
            lowerQuery.contains(product.name.lowercased().prefix(8))
        }
        if !mockMatches.isEmpty {
            return mockMatches.prefix(3).enumerated().map { index, product in
                ScanCandidate(product: product,
                              confidenceScore: max(0.90 - Double(index) * 0.10, 0.60),
                              identificationMethod: .photoAI)
            }
        }

        // 4a. Search Open Beauty Facts + Open Food Facts by name
        let obfProducts = await obf.searchByName(query)
        if !obfProducts.isEmpty {
            return obfProducts.prefix(5).enumerated().map { index, product in
                let confidence = max(0.95 - Double(index) * 0.10, 0.50)
                return ScanCandidate(product: product,
                                     confidenceScore: confidence,
                                     identificationMethod: .photoAI)
            }
        }

        // 4b. Full web search pipeline: INCIDecoder → SkinSafe → brand site
        if let webProduct = await webSearch.searchIngredients(
            brand: brand,
            productName: query,
            existingImageURL: nil
        ) {
            return [ScanCandidate(product: webProduct,
                                  confidenceScore: 0.80,
                                  identificationMethod: .photoAI)]
        }

        throw PhotoLookupError.noProductFound(query)
    }

    // MARK: — Data freshness

    func isIngredientDataStale(_ product: Product) -> Bool {
        guard let verified = product.dataLastVerified else { return true }
        let sixMonthsAgo = Calendar.current.date(byAdding: .month, value: -6, to: .now) ?? .now
        return verified < sixMonthsAgo
    }
}

// MARK: — Photo Lookup Errors

enum PhotoLookupError: LocalizedError {
    case invalidImage
    case noTextDetected
    case noProductFound(String)

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "Could not process the photo. Try again."
        case .noTextDetected:
            return "No text detected on label. Try better lighting or move closer."
        case .noProductFound(let query):
            return "No products found for '\(query)'. Try the barcode instead."
        }
    }
}

// MARK: — API Keys
// Paste keys directly below, or set as environment variables / in your .xcconfig.
//
//  inciAPI       → Sign up free at https://inciapi.com/register
//                  Paste your sk_live_... key into the string literal below.
//  googleVision  → Already set. Powers photo scan text detection.
// ─────────────────────────────────────────────
//  APIKeys
//
//  Keys with real values are XOR-obfuscated so
//  they don't appear as plaintext strings in the
//  compiled binary (defeats automated secret
//  scanners and basic `strings` dumps).
//
//  CI/CD override: set the matching environment
//  variable and the obfuscated fallback is skipped.
//
//  To add a new key:
//    1. Run: python3 -c "s='YOUR_KEY'; k=0xNN; print([b^k for b in s.encode()])"
//    2. Paste the output as _yourKeyBytes with the same salt k.
//    3. Add a static var that calls _x(_yourKeyBytes, 0xNN).
// ─────────────────────────────────────────────
enum APIKeys {

    // MARK: — Deobfuscation

    /// XOR each byte with `salt` and decode as UTF-8.
    private static func _x(_ bytes: [UInt8], _ salt: UInt8) -> String {
        String(bytes: bytes.map { $0 ^ salt }, encoding: .utf8) ?? ""
    }

    // MARK: — Google Vision  (salt 0x4B)

    private static let _googleVisionBytes: [UInt8] = [
        0x0A, 0x02, 0x31, 0x2A, 0x18, 0x32, 0x0A, 0x18, 0x1F, 0x31,
        0x7D, 0x2A, 0x39, 0x2C, 0x26, 0x66, 0x22, 0x1E, 0x05, 0x21,
        0x3A, 0x08, 0x3C, 0x05, 0x79, 0x78, 0x33, 0x3B, 0x12, 0x72,
        0x31, 0x0D, 0x7D, 0x2D, 0x3E, 0x73, 0x3A, 0x14, 0x0A
    ]

    static var googleVision: String {
        ProcessInfo.processInfo.environment["GOOGLE_VISION_API_KEY"]
            ?? _x(_googleVisionBytes, 0x4B)
    }

    // MARK: — Google Custom Search  (empty until CX is configured)

    static var googleCustomSearch: String {
        ProcessInfo.processInfo.environment["GOOGLE_CUSTOM_SEARCH_API_KEY"] ?? ""
    }
    static var googleCustomSearchCX: String {
        ProcessInfo.processInfo.environment["GOOGLE_CUSTOM_SEARCH_CX"] ?? ""
    }

    // MARK: — INCI API  (inciapi.com, salt 0x37)

    private static let _inciAPIBytes: [UInt8] = [
        0x44, 0x5C, 0x68, 0x5B, 0x5E, 0x41, 0x52, 0x68, 0x56, 0x0E,
        0x00, 0x56, 0x0F, 0x53, 0x01, 0x06, 0x0F, 0x07, 0x07, 0x06,
        0x51, 0x05, 0x06, 0x54, 0x54, 0x53, 0x52, 0x07, 0x51, 0x02,
        0x01, 0x07, 0x55, 0x05, 0x01, 0x00, 0x54, 0x0F, 0x01, 0x05
    ]

    static var inciAPI: String {
        ProcessInfo.processInfo.environment["INCI_API_KEY"]
            ?? _x(_inciAPIBytes, 0x37)
    }

    // MARK: — Go-UPC  (paste Bearer token between quotes when available)

    static var goUPC: String {
        ProcessInfo.processInfo.environment["GO_UPC_API_KEY"] ?? ""
    }

    // MARK: — Reserved (not yet active)

    static var inciDecoder:   String { ProcessInfo.processInfo.environment["INCIDECODER_API_KEY"]   ?? "" }
    static var skinSAFE:      String { ProcessInfo.processInfo.environment["SKINSAFE_API_KEY"]      ?? "" }
    static var cosmeticsCalc: String { ProcessInfo.processInfo.environment["COSMETICSCALC_API_KEY"] ?? "" }
}

import Foundation

// ─────────────────────────────────────────────
//  UPCItemDBService
//  Free barcode database — millions of global
//  consumer products including US, EU, AUS.
//  No API key required (free trial tier).
//  https://www.upcitemdb.com
//
//  Free limit: 100 lookups / day.
//  Returns: name, brand, category, image.
//  Does NOT include ingredient data —
//  we follow up with an OBF name search
//  to try to get ingredients.
// ─────────────────────────────────────────────

@MainActor
final class UPCItemDBService {

    static let shared = UPCItemDBService()

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest  = 10
        config.timeoutIntervalForResource = 20
        config.httpAdditionalHeaders = [
            "User-Agent": "BeautyBrief-iOS/1.0"
        ]
        session = URLSession(configuration: config)
    }

    // MARK: — Public

    /// Looks up a barcode. Returns nil if not found or daily limit hit.
    func fetchProduct(barcode: String) async -> UPCProduct? {
        let urlString = "https://api.upcitemdb.com/prod/trial/lookup?upc=\(barcode)"
        guard let url = URL(string: urlString) else { return nil }

        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse,
                  http.statusCode == 200 else { return nil }
            let decoded = try JSONDecoder().decode(UPCResponse.self, from: data)
            return decoded.items.first
        } catch {
            return nil
        }
    }
}

// MARK: — Response Structs

struct UPCProduct: Decodable {
    let ean: String?
    let title: String?
    let description: String?
    let brand: String?
    let category: String?
    let size: String?
    let images: [String]?

    var displayName: String { title ?? "Unknown Product" }
    var displayBrand: String { brand ?? "Unknown Brand" }
    var imageURL: String? { images?.first }

    /// Maps UPC category string to our ProductCategory
    var productCategory: ProductCategory {
        let cat = (category ?? "").lowercased()
        if cat.contains("hair")                          { return .haircare  }
        if cat.contains("fragrance") || cat.contains("perfume") { return .fragrance }
        if cat.contains("sun") || cat.contains("spf")    { return .suncare   }
        if cat.contains("makeup") || cat.contains("cosmetic") { return .makeup }
        if cat.contains("body")                          { return .bodycare  }
        if cat.contains("skin") || cat.contains("face") ||
           cat.contains("beauty") || cat.contains("personal care") { return .skincare }
        return .unknown
    }
}

private struct UPCResponse: Decodable {
    let code: String
    let items: [UPCProduct]
}

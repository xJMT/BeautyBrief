import Foundation
import SwiftUI

// ─────────────────────────────────────────────
//  Product  —  a confirmed beauty product
// ─────────────────────────────────────────────

struct Product: Identifiable, Codable, Equatable {
    let id: String                    // barcode or UUID
    let name: String
    let brand: String
    let category: ProductCategory
    let imageURL: String?

    var ingredients: [Ingredient]
    var batchCode: String?
    var expiryInfo: ExpiryInfo?

    var dataLastVerified: Date?
    var dataSource: String            // e.g. "INCIDecoder + Brand Page"

    // MARK: — Computed
    var fullName: String { "\(brand) \(name)" }

    /// Returns nil if brand is an unknown/placeholder so UI can hide it or substitute the product name.
    var knownBrand: String? {
        let trimmed = brand.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              trimmed.lowercased() != "unknown brand",
              trimmed.lowercased() != "unknown" else { return nil }
        return trimmed
    }
}

// MARK: — Enums
enum ProductCategory: String, Codable, CaseIterable {
    case skincare   = "Skincare"
    case makeup     = "Makeup"
    case haircare   = "Haircare"
    case fragrance  = "Fragrance"
    case bodycare   = "Body Care"
    case suncare    = "Sun Care"
    case unknown    = "Unknown"

    var icon: String {
        switch self {
        case .skincare:  return "💧"
        case .makeup:    return "💄"
        case .haircare:  return "💆‍♀️"
        case .fragrance: return "🌸"
        case .bodycare:  return "🧴"
        case .suncare:   return "☀️"
        case .unknown:   return "✨"
        }
    }

    var sfSymbol: String {
        switch self {
        case .skincare:  return "drop.fill"
        case .makeup:    return "paintbrush.fill"
        case .haircare:  return "wind"
        case .fragrance: return "sparkles"
        case .bodycare:  return "figure.arms.open"
        case .suncare:   return "sun.max.fill"
        case .unknown:   return "square.grid.2x2"
        }
    }

    var color: Color {
        switch self {
        case .skincare:  return Color(hex: "#7A9EBE")
        case .makeup:    return Color(hex: "#C97070")
        case .haircare:  return Color(hex: "#9B7060")
        case .fragrance: return Color(hex: "#E592A8")
        case .bodycare:  return Color(hex: "#7BAE8F")
        case .suncare:   return Color(hex: "#D4A96A")
        case .unknown:   return Color(hex: "#9B7060")
        }
    }
}

// MARK: — ScanCandidate (pre-confirmation)
struct ScanCandidate: Identifiable {
    let id = UUID()
    let product: Product
    let confidenceScore: Double   // 0.0 – 1.0
    let identificationMethod: IdentificationMethod

    var isHighConfidence: Bool { confidenceScore >= 0.95 }
    var confidencePercent: Int  { Int(confidenceScore * 100) }
}

enum IdentificationMethod: String {
    case barcode = "Barcode"
    case photoAI = "Photo AI"
    case combined = "Barcode + AI"
}

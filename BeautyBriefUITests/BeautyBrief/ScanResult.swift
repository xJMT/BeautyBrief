import Foundation

// ─────────────────────────────────────────────
//  ScanResult  —  a completed, confirmed scan
//  stored in history
// ─────────────────────────────────────────────

struct ScanResult: Identifiable, Codable {
    let id: UUID
    let product: Product
    let scannedAt: Date
    let allergyMatches: [AllergyMatchRecord]
    let expiryWarning: Bool
    let confidenceScore: Double
    let identificationMethod: String

    init(product: Product,
         allergyMatches: [AllergyMatchRecord] = [],
         expiryWarning: Bool = false,
         confidenceScore: Double = 1.0,
         identificationMethod: String = "Barcode") {
        self.id                     = UUID()
        self.product                = product
        self.scannedAt              = .now
        self.allergyMatches         = allergyMatches
        self.expiryWarning          = expiryWarning
        self.confidenceScore        = confidenceScore
        self.identificationMethod   = identificationMethod
    }

    var hasAlerts: Bool {
        !allergyMatches.isEmpty || expiryWarning
    }
    var alertCount: Int {
        allergyMatches.count + (expiryWarning ? 1 : 0)
    }
}

// Codable-safe version of AllergyMatch
struct AllergyMatchRecord: Codable, Identifiable {
    let id: UUID
    let ingredientName: String
    let matchedAllergen: String
    let severity: String

    init(from match: AllergyMatch) {
        self.id              = UUID()
        self.ingredientName  = match.ingredient.inciName
        self.matchedAllergen = match.matchedAllergen
        self.severity        = match.severity.rawValue
    }
}


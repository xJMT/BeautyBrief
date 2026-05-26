import Foundation

// ─────────────────────────────────────────────
//  Ingredient  —  single INCI ingredient entry
// ─────────────────────────────────────────────

struct Ingredient: Identifiable, Codable, Equatable {
    let id: String                        // INCI name (canonical)
    let inciName: String                  // official INCI name
    let commonName: String?               // human-readable alias
    let function: [IngredientFunction]
    let description: String               // what it does for skin
    let irritancyRisk: IrritancyLevel
    let isCommonAllergen: Bool
    let allergenTags: [String]            // e.g. ["fragrance", "nuts", "gluten"]
    let concentrationRank: Int            // position in INCI list (1 = highest)
    let source: String                    // "INCIDecoder", "SkinSAFE", "Brand Page"
    let riskProfile: IngredientRiskProfile? // 5-dimension chemical risk (nil = no data)

    var isHighRisk: Bool { irritancyRisk == .high }

    // Backward-compatible init — riskProfile defaults to nil so all
    // existing MockData and service call sites compile unchanged.
    init(id: String,
         inciName: String,
         commonName: String? = nil,
         function: [IngredientFunction],
         description: String,
         irritancyRisk: IrritancyLevel,
         isCommonAllergen: Bool,
         allergenTags: [String],
         concentrationRank: Int,
         source: String,
         riskProfile: IngredientRiskProfile? = nil) {
        self.id                = id
        self.inciName          = inciName
        self.commonName        = commonName
        self.function          = function
        self.description       = description
        self.irritancyRisk     = irritancyRisk
        self.isCommonAllergen  = isCommonAllergen
        self.allergenTags      = allergenTags
        self.concentrationRank = concentrationRank
        self.source            = source
        self.riskProfile       = riskProfile
    }
}

// MARK: — Function
enum IngredientFunction: String, Codable, CaseIterable {
    case moisturiser     = "Moisturiser"
    case emollient       = "Emollient"
    case humectant       = "Humectant"
    case surfactant      = "Surfactant"
    case preservative    = "Preservative"
    case fragrance       = "Fragrance"
    case exfoliant       = "Exfoliant"
    case antioxidant     = "Antioxidant"
    case sunscreen       = "UV Filter"
    case colorant        = "Colorant"
    case emulsifier      = "Emulsifier"
    case solvent         = "Solvent"
    case activeIngredient = "Active"
    case thickener       = "Thickener"
    case occlusive       = "Occlusive"
    case phAdjustor      = "pH Adjustor"
    case other           = "Other"

    var color: String {
        switch self {
        case .moisturiser, .humectant, .emollient: return "#7BAE8F"
        case .fragrance:                            return "#E592A8"
        case .preservative:                         return "#D4A96A"
        case .activeIngredient:                     return "#7A9EBE"
        case .sunscreen:                            return "#F2B8C6"
        default:                                    return "#9B7060"
        }
    }
}

// MARK: — Irritancy
enum IrritancyLevel: Int, Codable, CaseIterable, Comparable {
    case low    = 1
    case medium = 2
    case high   = 3

    static func < (lhs: IrritancyLevel, rhs: IrritancyLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var label: String {
        switch self {
        case .low:    return "Low Risk"
        case .medium: return "Moderate"
        case .high:   return "High Risk"
        }
    }
    var color: String {
        switch self {
        case .low:    return "#7BAE8F"
        case .medium: return "#D4A96A"
        case .high:   return "#C97070"
        }
    }
}

// MARK: — Expiry Info
struct ExpiryInfo: Codable, Equatable {
    let manufacturingDate: Date?
    let expiryDate: Date?
    let periodAfterOpening: Int?    // months (PAO)
    let batchCode: String
    let isExpired: Bool
    let isNearExpiry: Bool          // within 3 months

    var shelfLifeDescription: String {
        if let pao = periodAfterOpening {
            return "\(pao)M after opening"
        }
        return "See packaging"
    }
}

// MARK: — Allergy Match
struct AllergyMatch: Identifiable {
    let id = UUID()
    let ingredient: Ingredient
    let matchedAllergen: String    // which profile allergen triggered it
    let severity: AllergySeverity
}

enum AllergySeverity: String {
    case confirmed = "Your allergen"
    case highRisk  = "High irritant"
    case caution   = "Use caution"
}

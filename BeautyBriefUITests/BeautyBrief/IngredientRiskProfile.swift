import Foundation

// ─────────────────────────────────────────────
//  IngredientRiskProfile
//  Five-dimension chemical risk classification
//  for cosmetic ingredients.
//
//  Evidence sources (cited per entry in KB):
//    IARC  — International Agency for Research on Cancer
//    SCCS  — EU Scientific Committee on Consumer Safety
//    ECHA  — European Chemicals Agency (REACH/CLP)
//    EU    — EU Cosmetics Regulation 1223/2009 Annexes
//    FDA   — US Food & Drug Administration
//    WHO   — World Health Organization endocrine criteria
//    CIR   — Cosmetic Ingredient Review
//    SVHC  — ECHA Substances of Very High Concern list
// ─────────────────────────────────────────────

// MARK: — Risk Profile Container

struct IngredientRiskProfile: Codable, Equatable {

    /// Potential to interfere with hormonal systems (thyroid, oestrogen, androgen)
    let endocrineDisruption:  SpecialRiskLevel

    /// Developmental or fertility harm in animal or human studies
    let reproductiveToxicity: SpecialRiskLevel

    /// Cancer risk classification per IARC or EU CLP
    let carcinogenicity:      SpecialRiskLevel

    /// Contact sensitisation / anaphylaxis risk
    let allergyRisk:          AllergyRiskLevel

    /// Safe-use concentration limit (nil = no documented threshold concern)
    let concentrationAlert:   String?

    /// Short regulatory or classification flags, e.g. "IARC 2B", "EU Banned"
    let regulatoryFlags:      [String]

    /// One-sentence scientific evidence note
    let evidenceSummary:      String

    // Convenience: true if any special risk is suspected or confirmed
    var hasChemicalConcern: Bool {
        endocrineDisruption >= .suspected ||
        reproductiveToxicity >= .suspected ||
        carcinogenicity >= .suspected
    }

    // Worst single risk level across the three chemical hazard axes
    var worstChemicalLevel: SpecialRiskLevel {
        [endocrineDisruption, reproductiveToxicity, carcinogenicity].max() ?? .none
    }
}

// MARK: — Special Risk Level (endocrine / repro / carcinogenicity)

enum SpecialRiskLevel: String, Codable, CaseIterable, Comparable {
    case none      = "none"       // no established concern
    case low       = "low"        // minor or theoretical; limited animal data
    case suspected = "suspected"  // credible evidence; under regulatory review
    case confirmed = "confirmed"  // established by IARC, ECHA, EU, or FDA

    private var order: Int {
        switch self {
        case .none: return 0; case .low: return 1
        case .suspected: return 2; case .confirmed: return 3
        }
    }
    static func < (l: Self, r: Self) -> Bool { l.order < r.order }

    var label: String {
        switch self {
        case .none:      return "None"
        case .low:       return "Low concern"
        case .suspected: return "Suspected"
        case .confirmed: return "Confirmed"
        }
    }

    var shortLabel: String {
        switch self {
        case .none:      return "–"
        case .low:       return "Low"
        case .suspected: return "Suspected"
        case .confirmed: return "Confirmed"
        }
    }

    var color: String {
        switch self {
        case .none:      return "#7BAE8F"   // green
        case .low:       return "#C8A030"   // amber
        case .suspected: return "#D4853A"   // orange
        case .confirmed: return "#8B2020"   // red
        }
    }

    var icon: String {
        switch self {
        case .none:      return "checkmark.circle"
        case .low:       return "exclamationmark.circle"
        case .suspected: return "exclamationmark.triangle"
        case .confirmed: return "xmark.octagon.fill"
        }
    }
}

// MARK: — Allergy Risk Level

enum AllergyRiskLevel: String, Codable, CaseIterable {
    case low      = "low"      // rare sensitisation; <1% population affected
    case moderate = "moderate" // notable rate; ~1–5% patch-test positive
    case high     = "high"     // common cause of contact dermatitis; >5%
    case severe   = "severe"   // anaphylaxis or life-threatening reactions reported

    var label: String { rawValue.capitalized }

    var color: String {
        switch self {
        case .low:      return "#7BAE8F"
        case .moderate: return "#C8A030"
        case .high:     return "#D4853A"
        case .severe:   return "#8B2020"
        }
    }

    var icon: String {
        switch self {
        case .low:      return "checkmark.circle"
        case .moderate: return "exclamationmark.circle"
        case .high:     return "exclamationmark.triangle.fill"
        case .severe:   return "bolt.trianglebadge.exclamationmark.fill"
        }
    }
}

import Foundation

// ─────────────────────────────────────────────
//  AllergyProfile  —  user's personal profile
// ─────────────────────────────────────────────

struct AllergyProfile: Codable {
    // Personal
    var name: String

    // Allergens & sensitivities
    var allergens:     Set<KnownAllergen>
    var sensitivities: Set<KnownAllergen>

    // Skin
    var skinTypes:    Set<SkinType>
    var skinConcerns: Set<SkinConcern>

    // Health modes
    var pregnancyMode:     Bool
    var breastfeedingMode: Bool

    // Lifestyle preferences
    var lifestylePreferences: Set<LifestylePreference>

    // Personal ingredient blacklist (INCI names, lowercased)
    var blacklistedIngredients: [String]

    var lastUpdated: Date

    init() {
        name                   = ""
        allergens              = []
        sensitivities          = []
        skinTypes              = []
        skinConcerns           = []
        pregnancyMode          = false
        breastfeedingMode      = false
        lifestylePreferences   = []
        blacklistedIngredients = []
        lastUpdated            = .now
    }
}

// MARK: — Known Allergens
enum KnownAllergen: String, Codable, CaseIterable, Identifiable {
    var id: String { rawValue }

    // ── Preservatives & Fragrance ──────────────────────────────────
    case fragrance               = "Fragrance / Parfum"
    case linalool                = "Linalool"
    case limonene                = "Limonene"
    case geraniol                = "Geraniol"
    case eugenol                 = "Eugenol"
    case cinnamal                = "Cinnamal / Cinnamaldehyde"
    case isoeugenol              = "Isoeugenol"
    case benzylAlcohol           = "Benzyl Alcohol"
    case methylisothiazolinone   = "Methylisothiazolinone (MI / MCI)"
    case benzisothiazolinone     = "Benzisothiazolinone (BIT)"
    case formaldehyde            = "Formaldehyde Releasers"
    case parabens                = "Parabens"
    case phenoxyethanol          = "Phenoxyethanol"
    case chlorphenesin           = "Chlorphenesin"

    // ── Surfactants ────────────────────────────────────────────────
    case sulfates                = "Sulfates (SLS / SLES)"
    case cocamidopropylBetaine   = "Cocamidopropyl Betaine (CAPB)"
    case alkylGlucosides         = "Alkyl Glucosides (Coco / Decyl Glucoside)"
    case cocamideDea             = "Cocamide DEA / MEA"
    case polysorbates            = "Polysorbates (20, 60, 80)"
    case quaternaryAmmonium      = "Quaternary Ammonium Compounds"

    // ── Botanicals & Proteins ──────────────────────────────────────
    case nuts                    = "Nut Derivatives (Peanut, Almond, etc.)"
    case latex                   = "Latex / Rubber"
    case gluten                  = "Gluten / Wheat"
    case lanolin                 = "Lanolin (Wool Wax)"
    case propolis                = "Propolis / Bee Products"

    // ── Metals ─────────────────────────────────────────────────────
    case nickel                  = "Nickel"
    case cobalt                  = "Cobalt"
    case chromium                = "Chromium / Chromate"
    case gold                    = "Gold (Sodium Thiosulfate)"
    case palladium               = "Palladium"
    case mercury                 = "Mercury / Thimerosal"
    case aluminium               = "Aluminium / Aluminum"
    case bismuth                 = "Bismuth Oxychloride"
    case copper                  = "Copper Compounds"
    case silver                  = "Silver"

    // ── Actives & Filters ──────────────────────────────────────────
    case oxybenzone              = "Oxybenzone"
    case avobenzone              = "Avobenzone (UVA Filter)"
    case octocrylene             = "Octocrylene"
    case octinoxate              = "Octinoxate / Ethylhexyl Methoxycinnamate"
    case alphaHydroxyAcids       = "Alpha Hydroxy Acids (AHA)"
    case salicylicAcid           = "Salicylic Acid (BHA)"
    case retinol                 = "Retinol / Vitamin A"
    case benzoylPeroxide         = "Benzoyl Peroxide"
    case hydroquinone            = "Hydroquinone"
    case kojicAcid               = "Kojic Acid"
    case niacinamide             = "Niacinamide / Vitamin B3"

    // ── Dyes & Colorants ───────────────────────────────────────────
    case pPD                     = "p-Phenylenediamine (Hair Dye)"
    case pTolueneDiamine         = "p-Toluylenediamine (PTD)"
    case carmine                 = "Carmine / Cochineal (Red 4)"
    case redDye                  = "Red Dyes (Red 40 / CI 16035)"
    case yellowDye               = "Yellow Dyes (Yellow 5 / Tartrazine)"
    case blueDye                 = "Blue Dyes (Blue 1 / Brilliant Blue)"
    case disperseDyes            = "Disperse Dyes (Textile / Nail)"
    case resorcinol              = "Resorcinol (Hair Colour Developer)"

    var category: AllergenCategory {
        switch self {
        case .fragrance, .linalool, .limonene, .geraniol, .eugenol, .cinnamal, .isoeugenol,
             .benzylAlcohol, .methylisothiazolinone, .benzisothiazolinone,
             .formaldehyde, .parabens, .phenoxyethanol, .chlorphenesin:
            return .preservativesFragrance
        case .sulfates, .cocamidopropylBetaine, .alkylGlucosides, .cocamideDea,
             .polysorbates, .quaternaryAmmonium:
            return .surfactants
        case .nuts, .latex, .gluten, .lanolin, .propolis:
            return .botanicalsProteins
        case .nickel, .cobalt, .chromium, .gold, .palladium, .mercury,
             .aluminium, .bismuth, .copper, .silver:
            return .metals
        case .oxybenzone, .avobenzone, .octocrylene, .octinoxate, .alphaHydroxyAcids,
             .salicylicAcid, .retinol, .benzoylPeroxide, .hydroquinone, .kojicAcid, .niacinamide:
            return .activesFilters
        case .pPD, .pTolueneDiamine, .carmine, .redDye, .yellowDye, .blueDye,
             .disperseDyes, .resorcinol:
            return .dyes
        }
    }

    var icon: String {
        switch category {
        case .preservativesFragrance: return "🌿"
        case .surfactants:            return "🫧"
        case .botanicalsProteins:     return "🥜"
        case .metals:                 return "🔩"
        case .activesFilters:         return "🧬"
        case .dyes:                   return "🎨"
        }
    }

    var sfSymbol: String {
        switch category {
        case .preservativesFragrance: return "leaf.fill"
        case .surfactants:            return "bubbles.and.sparkles.fill"
        case .botanicalsProteins:     return "allergens"
        case .metals:                 return "wand.and.stars"
        case .activesFilters:         return "flask.fill"
        case .dyes:                   return "paintpalette.fill"
        }
    }
}

enum AllergenCategory: String, CaseIterable {
    case preservativesFragrance = "Preservatives & Fragrance"
    case surfactants            = "Surfactants"
    case botanicalsProteins     = "Botanicals & Proteins"
    case metals                 = "Metals"
    case activesFilters         = "Actives & Filters"
    case dyes                   = "Dyes & Colorants"
}

// MARK: — Skin Type
enum SkinType: String, Codable, CaseIterable, Identifiable {
    var id: String { rawValue }
    case normal       = "Normal"
    case dry          = "Dry"
    case oily         = "Oily"
    case combination  = "Combination"
    case sensitive    = "Sensitive"
    case dehydrated   = "Dehydrated"
    case acneProne    = "Acne-Prone"
    case mature       = "Mature"
    case reactive     = "Reactive"
    case unknown      = "Not Set"

    /// Ingredient tags that should be flagged for this skin type.
    /// Tags must match allergenTags values used in IngredientKnowledgeBase.
    var triggerTags: [String] {
        switch self {
        case .dry, .dehydrated:
            // Drying alcohols and stripping surfactants worsen dryness
            return ["alcohol", "sulfates", "salicylicAcid"]
        case .oily:
            // Pore-clogging & comedogenic ingredients aggravate oily skin
            return ["comedogenic", "isopropylMyristate", "coconutOil", "petrolatum"]
        case .acneProne:
            // Comedogenic ingredients trigger breakouts
            return ["comedogenic", "isopropylMyristate", "coconutOil"]
        case .combination:
            // Moderate comedogenic concern
            return ["comedogenic", "isopropylMyristate"]
        case .sensitive:
            // Fragrance, strong preservatives, and acids irritate sensitive skin
            return ["fragrance", "methylisothiazolinone", "aha", "menthol", "peppermint"]
        case .reactive:
            // Similar to sensitive but also flags parabens and more preservatives
            return ["fragrance", "methylisothiazolinone", "aha", "menthol", "peppermint", "parabens"]
        case .mature:
            // Harsh stripping ingredients accelerate moisture loss in mature skin
            return ["alcohol", "sulfates"]
        case .normal, .unknown:
            return []
        }
    }

    var sfSymbol: String {
        switch self {
        case .normal:      return "checkmark.circle"
        case .dry:         return "drop.fill"
        case .oily:        return "humidity.fill"
        case .combination: return "circle.lefthalf.filled"
        case .sensitive:   return "leaf.fill"
        case .dehydrated:  return "drop"
        case .acneProne:   return "bubbles.and.sparkles"
        case .mature:      return "hourglass"
        case .reactive:    return "exclamationmark.triangle"
        case .unknown:     return "questionmark.circle"
        }
    }
}

// MARK: — Skin Concerns
enum SkinConcern: String, Codable, CaseIterable, Identifiable {
    var id: String { rawValue }
    case acne           = "Acne / Breakouts"
    case rosacea        = "Rosacea"
    case eczema         = "Eczema"
    case pigmentation   = "Hyperpigmentation"
    case ageing         = "Ageing / Fine Lines"
    case dryness        = "Dryness"
    case sensitivity    = "Sensitivity"

    var icon: String {
        switch self {
        case .acne:         return "🫧"
        case .rosacea:      return "🌹"
        case .eczema:       return "🩹"
        case .pigmentation: return "☀️"
        case .ageing:       return "⏳"
        case .dryness:      return "💧"
        case .sensitivity:  return "🌸"
        }
    }

    var sfSymbol: String {
        switch self {
        case .acne:         return "bubbles.and.sparkles"
        case .rosacea:      return "thermometer.medium"
        case .eczema:       return "bandage.fill"
        case .pigmentation: return "sun.max.fill"
        case .ageing:       return "hourglass"
        case .dryness:      return "drop.fill"
        case .sensitivity:  return "leaf.fill"
        }
    }

    // Ingredient tags to watch out for per condition
    var triggerTags: [String] {
        switch self {
        case .eczema:
            return ["fragrance", "methylisothiazolinone", "sulfates", "lanolin", "propyleneGlycol"]
        case .rosacea:
            return ["fragrance", "alcohol", "aha", "menthol", "peppermint"]
        case .acne:
            return ["comedogenic", "isopropylMyristate", "coconutOil"]
        case .sensitivity:
            return ["fragrance", "methylisothiazolinone", "aha", "retinol"]
        default:
            return []
        }
    }
}

// MARK: — Lifestyle Preferences
enum LifestylePreference: String, Codable, CaseIterable, Identifiable {
    var id: String { rawValue }

    case vegan          = "Vegan"
    case crueltyFree    = "Cruelty-Free"
    case fragranceFree  = "Fragrance-Free"
    case cleanBeauty    = "Clean Beauty"
    case noParabens     = "Paraben-Free"
    case noSulfates     = "Sulfate-Free"
    case noSilicones    = "Silicone-Free"

    var icon: String {
        switch self {
        case .vegan:         return "🌱"
        case .crueltyFree:   return "🐰"
        case .fragranceFree: return "🚫"
        case .cleanBeauty:   return "✨"
        case .noParabens:    return "⚗️"
        case .noSulfates:    return "🫧"
        case .noSilicones:   return "💎"
        }
    }

    var sfSymbol: String {
        switch self {
        case .vegan:         return "leaf.fill"
        case .crueltyFree:   return "pawprint.fill"
        case .fragranceFree: return "nose.fill"
        case .cleanBeauty:   return "sparkles"
        case .noParabens:    return "flask.fill"
        case .noSulfates:    return "bubbles.and.sparkles"
        case .noSilicones:   return "diamond.fill"
        }
    }

    var description: String {
        switch self {
        case .vegan:         return "Flags animal-derived ingredients"
        case .crueltyFree:   return "Notes animal-tested ingredients"
        case .fragranceFree: return "Flags all fragrance ingredients"
        case .cleanBeauty:   return "Flags EU-banned & controversial ingredients"
        case .noParabens:    return "Flags all paraben preservatives"
        case .noSulfates:    return "Flags sulfate surfactants"
        case .noSilicones:   return "Flags silicone ingredients"
        }
    }

    // Ingredient tags this preference watches for
    var watchTags: [String] {
        switch self {
        case .vegan:         return ["animalDerived", "carmine", "lanolin", "collagen", "keratin", "beeswax", "honey", "squalene"]
        case .crueltyFree:   return ["animalTested"]
        case .fragranceFree: return ["fragrance"]
        case .cleanBeauty:   return ["parabens", "formaldehydeReleasers", "phthalates", "petrolatum"]
        case .noParabens:    return ["parabens"]
        case .noSulfates:    return ["sulfates"]
        case .noSilicones:   return ["silicones", "dimethicone", "cyclopentasiloxane"]
        }
    }
}

// MARK: — Pregnancy-unsafe ingredient tags
// Used by IngredientAnalysisService when pregnancyMode or breastfeedingMode is on
extension AllergyProfile {
    static let pregnancyWatchTags: [String] = [
        "retinol", "retinaldehyde", "salicylicAcid", "benzoylPeroxide",
        "hydroquinone", "formaldehydeReleasers", "oxybenzone",
        "dihydroxyacetone", "thioglycolicAcid"
    ]
}

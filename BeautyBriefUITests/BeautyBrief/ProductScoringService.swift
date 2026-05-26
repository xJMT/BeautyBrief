import SwiftUI

// ─────────────────────────────────────────────
//  ProductScoringService
//  Computes 8 specialised ingredient scores
//  beyond the core formula score.
// ─────────────────────────────────────────────

// MARK: — Score Model

struct ProductScores {
    /// How well the ingredient list suits the user's skin type(s). nil if no skin types set.
    let skinTypeFitScore: Int?
    /// How "clean" the formula is — low synthetic load, no controversial chemicals. 0–100.
    let cleannessScore: Int
    /// Inverse fragrance load — 100 means effectively fragrance-free. 0–100.
    let fragranceLoadScore: Int
    /// Pregnancy / breastfeeding safety tier.
    let pregnancySafetyLevel: PregnancySafetyTier
    /// Pore-clogging likelihood. 0.0 (none) – 5.0 (very high).
    let comedogenicRating: Double
    /// How eco-friendly the ingredient list is (no microplastics, reef-safe, biodegradable). 0–100.
    let environmentalScore: Int
    /// How evidence-backed the active ingredients are for this product's category. nil if unmappable.
    let efficacyScore: Int?
    /// Gentleness percentile vs typical products in this category — 100 = gentlest. 0–100.
    let irritancyPercentile: Int
}

enum PregnancySafetyTier: Equatable {
    case safe, caution, avoid

    var label: String {
        switch self {
        case .safe:    return "Generally Considered Safe"
        case .caution: return "Use with Caution"
        case .avoid:   return "Consult Your Doctor"
        }
    }
    var subtitle: String {
        switch self {
        case .safe:    return "No known pregnancy-restricted ingredients detected"
        case .caution: return "One or more cautionary ingredients found"
        case .avoid:   return "Multiple ingredients advised against in pregnancy"
        }
    }
    var color: Color {
        switch self {
        case .safe:    return Color(hex: "#7BAE8F")
        case .caution: return Color(hex: "#D4A96A")
        case .avoid:   return Color(hex: "#C97070")
        }
    }
    var icon: String {
        switch self {
        case .safe:    return "checkmark.circle.fill"
        case .caution: return "exclamationmark.triangle.fill"
        case .avoid:   return "xmark.circle.fill"
        }
    }
    var tier: Int { switch self { case .safe: return 3; case .caution: return 2; case .avoid: return 1 } }
}

// MARK: — Scoring Service

struct ProductScoringService {

    static func computeScores(product: Product,
                               profile: AllergyProfile,
                               analysis: AnalysisResult) -> ProductScores {
        ProductScores(
            skinTypeFitScore:      skinTypeFitScore(product: product, profile: profile, analysis: analysis),
            cleannessScore:        cleannessScore(product: product),
            fragranceLoadScore:    fragranceLoadScore(product: product),
            pregnancySafetyLevel:  pregnancySafety(analysis: analysis),
            comedogenicRating:     comedogenicRating(product: product),
            environmentalScore:    environmentalScore(product: product),
            efficacyScore:         efficacyScore(product: product),
            irritancyPercentile:   irritancyPercentile(product: product)
        )
    }

    // ─────────────────────────────────────────────
    // 1. Skin-type fit score
    // Starts at 100; deducts for each ingredient that
    // triggers any of the user's selected skin types,
    // weighted by concentration rank.
    // ─────────────────────────────────────────────
    private static func skinTypeFitScore(product: Product,
                                          profile: AllergyProfile,
                                          analysis: AnalysisResult) -> Int? {
        guard !profile.skinTypes.isEmpty else { return nil }
        var deductions = 0.0
        for flag in analysis.skinTypeFlags {
            let rank   = max(1, flag.ingredient.concentrationRank)
            let weight = max(0.1, 1.0 - Double(rank - 1) * 0.025)
            deductions += weight * 12.0
        }
        return max(5, min(100, 100 - Int(deductions.rounded())))
    }

    // ─────────────────────────────────────────────
    // 2. Cleanness score
    // Penalises ingredients with confirmed/suspected
    // endocrine, reproductive, or carcinogenic risk,
    // plus known controversial synthetic classes.
    // ─────────────────────────────────────────────
    private static func cleannessScore(product: Product) -> Int {
        let syntheticTags: Set<String> = [
            "silicones", "dimethicone", "cyclopentasiloxane",
            "petrolatum", "phthalates", "formaldehydeReleasers",
            "parabens", "disperseDyes", "ppd", "ptd", "quats"
        ]
        var deductions = 0.0
        for ing in product.ingredients {
            let rank   = max(1, ing.concentrationRank)
            let weight = max(0.1, 1.0 - Double(rank - 1) * 0.025)

            // Chemical risk profile deductions
            let rp = ing.riskProfile
                ?? IngredientKnowledgeBase.lookup(ing.inciName.lowercased())?.riskProfile
            if let rp = rp {
                switch rp.worstChemicalLevel {
                case .confirmed: deductions += weight * 10.0
                case .suspected: deductions += weight * 6.0
                case .low:       deductions += weight * 2.0
                case .none:      break
                }
            }
            // Controversial synthetic class tags
            if ing.allergenTags.contains(where: { syntheticTags.contains($0) }) {
                deductions += weight * 4.0
            }
        }
        return max(5, min(100, 100 - Int(deductions.rounded())))
    }

    // ─────────────────────────────────────────────
    // 3. Fragrance load score (higher = less fragrance)
    // Counts fragrance and known fragrance-allergen
    // ingredients, weighted by position in formula.
    // ─────────────────────────────────────────────
    private static func fragranceLoadScore(product: Product) -> Int {
        let fragranceTags: Set<String> = [
            "fragrance", "linalool", "limonene", "geraniol",
            "eugenol", "cinnamal", "isoeugenol", "benzylAlcohol"
        ]
        var load = 0.0
        for ing in product.ingredients {
            let hasFragrance = ing.allergenTags.contains(where: { fragranceTags.contains($0) })
                || ing.inciName.lowercased().contains("parfum")
                || ing.inciName.lowercased().contains("fragrance")
            if hasFragrance {
                let rank   = max(1, ing.concentrationRank)
                let weight = max(0.1, 1.0 - Double(rank - 1) * 0.025)
                load += weight * 18.0
            }
        }
        return max(0, min(100, 100 - Int(load.rounded())))
    }

    // ─────────────────────────────────────────────
    // 4. Pregnancy safety
    // Tiered based on number of pregnancy watch-list hits.
    // ─────────────────────────────────────────────
    private static func pregnancySafety(analysis: AnalysisResult) -> PregnancySafetyTier {
        if analysis.pregnancyAlerts.count >= 2 { return .avoid }
        if !analysis.pregnancyAlerts.isEmpty   { return .caution }
        return .safe
    }

    // ─────────────────────────────────────────────
    // 5. Comedogenic rating (0.0 – 5.0)
    // Measures pore-clogging potential by scoring
    // known comedogenic ingredients weighted by rank.
    // ─────────────────────────────────────────────
    private static func comedogenicRating(product: Product) -> Double {
        let comedogenicTags: Set<String> = [
            "comedogenic", "isopropylMyristate", "coconutOil", "petrolatum", "cocoButter"
        ]
        let comedogenicNames = ["isopropyl myristate", "coconut oil", "petrolatum",
                                "cocoa butter", "isopropyl palmitate", "sodium lauryl sulfate"]

        var totalWeight  = 0.0
        var flaggedWeight = 0.0
        for ing in product.ingredients {
            let rank   = max(1, ing.concentrationRank)
            let weight = max(0.1, 1.0 - Double(rank - 1) * 0.025)
            totalWeight += weight
            let inciLower = ing.inciName.lowercased()
            let isComedogenic = ing.allergenTags.contains(where: { comedogenicTags.contains($0) })
                || comedogenicNames.contains(where: { inciLower.contains($0) })
            if isComedogenic { flaggedWeight += weight }
        }
        guard totalWeight > 0 else { return 0.0 }
        let raw = (flaggedWeight / totalWeight) * 5.0 * 2.5
        return min(5.0, (raw * 10).rounded() / 10.0)   // round to 1dp, cap at 5
    }

    // ─────────────────────────────────────────────
    // 6. Environmental score
    // Flags microplastics, non-biodegradable polymers,
    // and reef-damaging UV filters.
    // ─────────────────────────────────────────────
    private static func environmentalScore(product: Product) -> Int {
        let badTags: Set<String>  = ["oxybenzone", "octinoxate", "cyclopentasiloxane"]
        let badNames = [
            "polyethylene", "polypropylene", "polymethylmethacrylate",
            "nylon-12", "polyester", "acrylates copolymer",
            "sodium laureth sulfate"          // poor biodegradability
        ]
        var deductions = 0.0
        for ing in product.ingredients {
            let rank     = max(1, ing.concentrationRank)
            let weight   = max(0.1, 1.0 - Double(rank - 1) * 0.025)
            let inciLower = ing.inciName.lowercased()

            if ing.allergenTags.contains(where: { badTags.contains($0) }) {
                deductions += weight * 16.0
            }
            if badNames.contains(where: { inciLower.contains($0) }) {
                deductions += weight * 12.0
            }
        }
        return max(5, min(100, 100 - Int(deductions.rounded())))
    }

    // ─────────────────────────────────────────────
    // 7. Efficacy score
    // Checks whether evidence-backed actives for this
    // product's category are present in the formula.
    // Returns nil for categories with no reference actives.
    // ─────────────────────────────────────────────
    private static func efficacyScore(product: Product) -> Int? {
        let actives = efficacyActives(for: product.category)
        guard !actives.isEmpty else { return nil }

        let inciNames   = product.ingredients.map { $0.inciName.lowercased() }
        let allTags     = Set(product.ingredients.flatMap { $0.allergenTags })

        var matchCount = 0
        for active in actives {
            if inciNames.contains(where: { $0.contains(active) }) || allTags.contains(active) {
                matchCount += 1
            }
        }
        let ratio = Double(matchCount) / Double(actives.count)
        // Scale: at least one active = 35+, full match = 95
        return max(10, min(100, Int((ratio * 85).rounded()) + 10))
    }

    private static func efficacyActives(for category: ProductCategory) -> [String] {
        let raw = category.rawValue.lowercased()
        if raw.contains("moisturis") || raw.contains("moisturiz") || raw.contains("cream") || raw.contains("lotion") {
            return ["hyaluronic", "ceramide", "niacinamide", "glycerin", "peptide", "squalane", "panthenol"]
        }
        if raw.contains("serum") {
            return ["hyaluronic", "niacinamide", "retinol", "ascorbic", "vitamin c", "peptide", "aha"]
        }
        if raw.contains("sun") || raw.contains("spf") {
            return ["oxybenzone", "avobenzone", "titanium dioxide", "zinc oxide", "octocrylene", "tinosorb"]
        }
        if raw.contains("shampoo") {
            return ["panthenol", "keratin", "biotin", "arginine", "hydrolyzed"]
        }
        if raw.contains("condition") {
            return ["panthenol", "keratin", "cetearyl", "dimethicone", "quaternium"]
        }
        if raw.contains("cleanse") || raw.contains("wash") || raw.contains("cleanser") {
            return ["salicylicAcid", "glycolic", "gluconolactone", "niacinamide", "ceramide"]
        }
        if raw.contains("toner") {
            return ["niacinamide", "aha", "salicylicAcid", "hyaluronic", "centella"]
        }
        if raw.contains("eye") {
            return ["retinol", "peptide", "caffeine", "hyaluronic", "vitamin k"]
        }
        return []
    }

    // ─────────────────────────────────────────────
    // 8. Irritancy percentile
    // Represents how gentle this formula is vs a
    // typical product — 100 means no irritants at all.
    // Weighted by concentration: earlier irritants matter more.
    // ─────────────────────────────────────────────
    private static func irritancyPercentile(product: Product) -> Int {
        let total = product.ingredients.count
        guard total > 0 else { return 60 }
        var irritancyLoad = 0.0
        var totalWeight   = 0.0
        for ing in product.ingredients {
            let rank   = max(1, ing.concentrationRank)
            let weight = max(0.1, 1.0 - Double(rank - 1) * 0.025)
            totalWeight += weight
            switch ing.irritancyRisk {
            case .high:   irritancyLoad += weight * 1.0
            case .medium: irritancyLoad += weight * 0.4
            case .low:    break
            }
        }
        guard totalWeight > 0 else { return 60 }
        let ratio = irritancyLoad / totalWeight
        // Typical product has ~15% irritancy load — calibrate around that
        return max(10, min(100, 100 - Int((ratio * 120).rounded())))
    }
}

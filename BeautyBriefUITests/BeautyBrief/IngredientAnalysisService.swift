import Foundation

// ─────────────────────────────────────────────
//  IngredientAnalysisService
//  Cross-checks product ingredients against a
//  user's allergy profile and flags matches.
// ─────────────────────────────────────────────

struct IngredientAnalysisService {

    // MARK: — Main analysis function
    static func analyse(product: Product, profile: AllergyProfile) -> AnalysisResult {
        var allergyMatches:    [AllergyMatch] = []
        var highRiskIngreds:   [Ingredient]   = []
        var warningIngredients: [Ingredient]  = []
        var pregnancyAlerts:   [Ingredient]   = []
        var lifestyleFlags:    [LifestyleFlag] = []
        var skinConditionFlags: [SkinConditionFlag] = []
        var skinTypeFlags:     [SkinTypeFlag]  = []
        var blacklistMatches:  [Ingredient]   = []

        let inPregnancyMode = profile.pregnancyMode || profile.breastfeedingMode

        for ingredient in product.ingredients {
            let inciLower = ingredient.inciName.lowercased()

            // 1. Check against confirmed allergens
            for allergen in profile.allergens {
                if ingredient.allergenTags.contains(allergenKey(for: allergen)) {
                    allergyMatches.append(AllergyMatch(
                        ingredient: ingredient,
                        matchedAllergen: allergen.rawValue,
                        severity: .confirmed
                    ))
                }
            }
            // 2. Check against sensitivities
            for sensitivity in profile.sensitivities {
                if ingredient.allergenTags.contains(allergenKey(for: sensitivity)),
                   !allergyMatches.contains(where: { $0.ingredient.id == ingredient.id }) {
                    allergyMatches.append(AllergyMatch(
                        ingredient: ingredient,
                        matchedAllergen: sensitivity.rawValue,
                        severity: .caution
                    ))
                }
            }
            // 3. Flag high irritancy regardless of profile
            if ingredient.irritancyRisk == .high,
               !allergyMatches.contains(where: { $0.ingredient.id == ingredient.id }) {
                highRiskIngreds.append(ingredient)
            }
            // 4. Moderate irritancy warnings
            if ingredient.irritancyRisk == .medium {
                warningIngredients.append(ingredient)
            }
            // 5. Pregnancy / breastfeeding caution ingredients
            if inPregnancyMode {
                let matchesPregnancy = AllergyProfile.pregnancyWatchTags.contains { tag in
                    inciLower.contains(tag.lowercased()) || ingredient.allergenTags.contains(tag)
                }
                if matchesPregnancy { pregnancyAlerts.append(ingredient) }
            }
            // 6. Lifestyle preference conflicts
            for pref in profile.lifestylePreferences {
                let matches = pref.watchTags.contains { tag in
                    inciLower.contains(tag.lowercased()) || ingredient.allergenTags.contains(tag)
                }
                if matches {
                    lifestyleFlags.append(LifestyleFlag(ingredient: ingredient, matchedPreference: pref))
                }
            }
            // 7. Skin condition trigger ingredients
            for concern in profile.skinConcerns {
                let matches = concern.triggerTags.contains { tag in
                    inciLower.contains(tag.lowercased()) || ingredient.allergenTags.contains(tag)
                }
                if matches {
                    skinConditionFlags.append(SkinConditionFlag(ingredient: ingredient, matchedConcern: concern))
                }
            }
            // 7b. Skin type trigger ingredients
            for skinType in profile.skinTypes {
                let matches = skinType.triggerTags.contains { tag in
                    inciLower.contains(tag.lowercased()) || ingredient.allergenTags.contains(tag)
                }
                if matches {
                    skinTypeFlags.append(SkinTypeFlag(ingredient: ingredient, matchedSkinType: skinType))
                }
            }
            // 8. Personal ingredient blacklist
            if profile.blacklistedIngredients.contains(where: { inciLower.contains($0) }) {
                blacklistMatches.append(ingredient)
            }
        }

        let overallSafety = computeSafety(
            allergyMatches: allergyMatches,
            highRisk: highRiskIngreds,
            pregnancyAlerts: pregnancyAlerts,
            blacklistMatches: blacklistMatches,
            product: product
        )

        let score = computeScore(
            ingredients: product.ingredients,
            allergyMatches: allergyMatches,
            blacklistMatches: blacklistMatches,
            pregnancyAlerts: pregnancyAlerts
        )

        // Ingredients with .low irritancy that aren't already flagged
        let flaggedIDs = Set(
            allergyMatches.map { $0.ingredient.id } +
            highRiskIngreds.map { $0.id } +
            warningIngredients.map { $0.id }
        )
        let lowRiskIngreds = product.ingredients.filter {
            $0.irritancyRisk == .low && !flaggedIDs.contains($0.id)
        }

        // Chemical concern ingredients
        let chemicalConcerns = product.ingredients.filter { ing in
            let rp = ing.riskProfile
                ?? IngredientKnowledgeBase.lookup(ing.inciName.lowercased())?.riskProfile
            return rp?.hasChemicalConcern == true
        }

        return AnalysisResult(
            ingredients:                product.ingredients.sorted { $0.concentrationRank < $1.concentrationRank },
            allergyMatches:             allergyMatches,
            highRiskIngredients:        highRiskIngreds,
            warningIngredients:         warningIngredients,
            lowRiskIngredients:         lowRiskIngreds,
            chemicalConcernIngredients: chemicalConcerns,
            pregnancyAlerts:            pregnancyAlerts,
            lifestyleFlags:             lifestyleFlags,
            skinConditionFlags:         skinConditionFlags,
            skinTypeFlags:              skinTypeFlags,
            blacklistMatches:           blacklistMatches,
            formulaScore:               score,
            overallSafety:              overallSafety,
            patchTestRecommended:       !highRiskIngreds.isEmpty || !allergyMatches.isEmpty
        )
    }

    // MARK: — Formula score (0–100)
    // Weighted by concentration rank — higher-ranked (earlier) ingredients penalise more.
    // Deducts for irritancy AND chemical risk profile (endocrine, repro, carcinogenicity, allergenicity).
    private static func computeScore(ingredients: [Ingredient],
                                     allergyMatches: [AllergyMatch],
                                     blacklistMatches: [Ingredient] = [],
                                     pregnancyAlerts: [Ingredient] = []) -> Int {
        var deductions = 0.0
        for ing in ingredients {
            let rank   = max(1, ing.concentrationRank)
            let weight = max(0.1, 1.0 - Double(rank - 1) * 0.025)

            // Irritancy deduction (skin irritation risk)
            switch ing.irritancyRisk {
            case .high:   deductions += weight * 15.0
            case .medium: deductions += weight * 5.0
            case .low:    break
            }

            // Chemical risk deduction (systemic / regulatory / allergenicity from risk profile)
            // Prefer the ingredient's own stored riskProfile; fall back to KB lookup.
            let rp = ing.riskProfile
                ?? IngredientKnowledgeBase.lookup(ing.inciName.lowercased())?.riskProfile
            if let rp = rp {
                // Worst level across endocrine disruption, reproductive toxicity, carcinogenicity
                switch rp.worstChemicalLevel {
                case .confirmed:  deductions += weight * 10.0
                case .suspected:  deductions += weight * 5.0
                case .low:        deductions += weight * 1.5
                case .none:       break
                }
                // Allergenicity from the scientific risk profile (separate from personal matches)
                switch rp.allergyRisk {
                case .severe:   deductions += weight * 8.0
                case .high:     deductions += weight * 4.0
                case .moderate: deductions += weight * 1.0
                case .low:      break
                }
            }
        }
        // Personal allergen matches
        let confirmed = allergyMatches.filter { $0.severity == .confirmed }.count
        let caution   = allergyMatches.filter { $0.severity == .caution }.count
        deductions += Double(confirmed) * 12.0
        deductions += Double(caution)   * 4.0
        // Blacklisted ingredients — hard penalty
        deductions += Double(blacklistMatches.count) * 15.0
        // Pregnancy alerts — moderate penalty
        deductions += Double(pregnancyAlerts.count) * 8.0
        return max(5, min(100, 100 - Int(deductions.rounded())))
    }

    // MARK: — Safety score
    private static func computeSafety(allergyMatches: [AllergyMatch],
                                       highRisk: [Ingredient],
                                       pregnancyAlerts: [Ingredient] = [],
                                       blacklistMatches: [Ingredient] = [],
                                       product: Product) -> SafetyLevel {
        // Blacklisted ingredients → immediate .notice
        if !blacklistMatches.isEmpty                                { return .notice }
        // Confirmed allergen from the user's personal profile → .notice
        let confirmed = allergyMatches.filter { $0.severity == .confirmed }
        if !confirmed.isEmpty                                       { return .notice }
        // Pregnancy alerts → .caution
        if !pregnancyAlerts.isEmpty                                 { return .caution }
        if !allergyMatches.isEmpty || highRisk.count >= 2          { return .caution }
        if !highRisk.isEmpty                                        { return .monitor }
        return .clear
    }

    // MARK: — Allergen tag → profile key mapping
    // These strings must exactly match the allergenTags values in IngredientKnowledgeBase.
    private static func allergenKey(for allergen: KnownAllergen) -> String {
        switch allergen {
        // Preservatives & Fragrance
        case .fragrance:              return "fragrance"
        case .linalool:               return "linalool"
        case .limonene:               return "limonene"
        case .geraniol:               return "geraniol"
        case .eugenol:                return "eugenol"
        case .cinnamal:               return "cinnamal"
        case .isoeugenol:             return "isoeugenol"
        case .benzylAlcohol:          return "benzylAlcohol"
        case .methylisothiazolinone:  return "methylisothiazolinone"
        case .benzisothiazolinone:    return "benzisothiazolinone"
        case .formaldehyde:           return "formaldehydeReleasers"
        case .parabens:               return "parabens"
        case .phenoxyethanol:         return "phenoxyethanol"
        case .chlorphenesin:          return "chlorphenesin"
        // Surfactants
        case .sulfates:               return "sulfates"
        case .cocamidopropylBetaine:  return "cocamidopropylBetaine"
        case .alkylGlucosides:        return "alkylGlucosides"
        case .cocamideDea:            return "cocamideDea"
        case .polysorbates:           return "polysorbates"
        case .quaternaryAmmonium:     return "quats"
        // Botanicals & Proteins
        case .nuts:                   return "nuts"
        case .latex:                  return "latex"
        case .gluten:                 return "gluten"
        case .lanolin:                return "lanolin"
        case .propolis:               return "propolis"
        // Metals
        case .nickel:                 return "nickel"
        case .cobalt:                 return "cobalt"
        case .chromium:               return "chromium"
        case .gold:                   return "gold"
        case .palladium:              return "palladium"
        case .mercury:                return "mercury"
        case .aluminium:              return "aluminium"
        case .bismuth:                return "bismuth"
        case .copper:                 return "copper"
        case .silver:                 return "silver"
        // Actives & Filters
        case .oxybenzone:             return "oxybenzone"
        case .avobenzone:             return "avobenzone"
        case .octocrylene:            return "octocrylene"
        case .octinoxate:             return "octinoxate"
        case .alphaHydroxyAcids:      return "aha"
        case .salicylicAcid:          return "salicylicAcid"
        case .retinol:                return "retinol"
        case .benzoylPeroxide:        return "benzoylPeroxide"
        case .hydroquinone:           return "hydroquinone"
        case .kojicAcid:              return "kojicAcid"
        case .niacinamide:            return "niacinamide"
        // Dyes & Colorants
        case .pPD:                    return "ppd"
        case .pTolueneDiamine:        return "ptd"
        case .carmine:                return "carmine"
        case .redDye:                 return "redDye"
        case .yellowDye:              return "yellowDye"
        case .blueDye:                return "blueDye"
        case .disperseDyes:           return "disperseDyes"
        case .resorcinol:             return "resorcinol"
        }
    }
}

// MARK: — Supporting flag types

struct LifestyleFlag {
    let ingredient: Ingredient
    let matchedPreference: LifestylePreference
}

struct SkinConditionFlag {
    let ingredient: Ingredient
    let matchedConcern: SkinConcern
}

struct SkinTypeFlag {
    let ingredient: Ingredient
    let matchedSkinType: SkinType
}

// MARK: — Analysis Result
struct AnalysisResult {
    let ingredients:                [Ingredient]   // full list sorted by concentration rank
    let allergyMatches:             [AllergyMatch]
    let highRiskIngredients:        [Ingredient]
    let warningIngredients:         [Ingredient]
    let lowRiskIngredients:         [Ingredient]
    let chemicalConcernIngredients: [Ingredient]  // endocrine / repro / carcinogenicity flags
    let pregnancyAlerts:            [Ingredient]  // pregnancy/breastfeeding watch-list matches
    let lifestyleFlags:             [LifestyleFlag]     // lifestyle preference conflicts
    let skinConditionFlags:         [SkinConditionFlag] // skin concern trigger ingredients
    let skinTypeFlags:              [SkinTypeFlag]      // skin type trigger ingredients
    let blacklistMatches:           [Ingredient]  // user's personal blacklist hits
    let formulaScore:               Int            // 0–100
    let overallSafety:              SafetyLevel
    let patchTestRecommended:       Bool

    var hasAlerts: Bool {
        !allergyMatches.isEmpty || !highRiskIngredients.isEmpty ||
        !pregnancyAlerts.isEmpty || !blacklistMatches.isEmpty
    }
    var totalFlagCount: Int { allergyMatches.count + highRiskIngredients.count }
    var hasChemicalConcerns: Bool { !chemicalConcernIngredients.isEmpty }
    var hasLifestyleConflicts: Bool { !lifestyleFlags.isEmpty }
    var hasSkinConditionFlags: Bool { !skinConditionFlags.isEmpty }
    var hasSkinTypeFlags: Bool { !skinTypeFlags.isEmpty }

    var scoreLabel: String {
        switch formulaScore {
        case 85...100: return "Excellent"
        case 70..<85:  return "Good"
        case 55..<70:  return "Fair"
        case 40..<55:  return "Not great"
        default:       return "Poor"
        }
    }

    var scoreColor: String {
        switch formulaScore {
        case 85...100: return "#7BAE8F"   // green
        case 70..<85:  return "#7A9EBE"   // blue
        case 55..<70:  return "#C8A030"   // amber
        case 40..<55:  return "#D4853A"   // orange
        default:       return "#8B2020"   // red
        }
    }
}

enum SafetyLevel {
    case clear    // no flags
    case monitor  // one mild flag
    case caution  // multiple flags or sensitivity match
    case notice   // confirmed allergen match from personal profile

    var label: String {
        switch self {
        case .clear:   return "Looks Good"
        case .monitor: return "Use with Care"
        case .caution: return "Caution Advised"
        case .notice:  return "Ingredient Notice"
        }
    }
    var subtitle: String {
        switch self {
        case .clear:   return "No allergens or high-risk ingredients detected"
        case .monitor: return "One ingredient worth monitoring"
        case .caution: return "Sensitivities or multiple flagged ingredients"
        case .notice:  return "Some ingredients match your profile — check the Safety tab"
        }
    }
    var color: String {
        switch self {
        case .clear:   return "#7BAE8F"
        case .monitor: return "#7A9EBE"
        case .caution: return "#D4A96A"
        case .notice:  return "#C8A030"
        }
    }
    var icon: String {
        switch self {
        case .clear:   return "checkmark.shield.fill"
        case .monitor: return "eye.fill"
        case .caution: return "exclamationmark.triangle.fill"
        case .notice:  return "exclamationmark.circle.fill"
        }
    }
}

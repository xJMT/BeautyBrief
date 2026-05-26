import Foundation

// ─────────────────────────────────────────────
//  SimilarProductsService
//  Finds products with similar ingredient profiles
//  using a concentration-weighted Jaccard similarity.
//
//  Similarity is computed purely from MockData so
//  it works fully offline with no API calls.
// ─────────────────────────────────────────────

struct SimilarProductResult: Identifiable {
    let id            = UUID()
    let product: Product
    let similarityScore: Double       // 0.0–1.0  (weighted Jaccard)
    let sharedIngredients: Int        // raw shared ingredient count
    let isSafeForProfile: Bool        // true if no allergen / sensitivity conflicts
    let allergenConflicts: [String]   // INCI names that clash with the user's profile
}

@MainActor
final class SimilarProductsService {

    static let shared = SimilarProductsService()

    // MARK: — Public API

    /// Returns products from MockData ranked by ingredient similarity to `product`.
    /// - Parameters:
    ///   - product: The source product to match against.
    ///   - profile: The user's allergy profile (used for safety flagging). Pass nil to skip safety check.
    ///   - limit: Maximum number of results to return.
    ///   - minimumScore: Minimum similarity score (0–1) to include a result. Default 0.08 (~8% overlap).
    func findSimilar(
        to product: Product,
        profile: AllergyProfile?,
        limit: Int = 8,
        minimumScore: Double = 0.08
    ) -> [SimilarProductResult] {

        // Build a weighted ingredient set for the target product
        let targetWeights = weightedIngredients(for: product)
        guard !targetWeights.isEmpty else { return [] }

        let targetKeys = Set(targetWeights.keys)

        return MockData.allProducts
            .filter { $0.id != product.id && !$0.ingredients.isEmpty }
            .compactMap { candidate -> SimilarProductResult? in

                let candidateWeights = weightedIngredients(for: candidate)
                let candidateKeys    = Set(candidateWeights.keys)

                let intersection = targetKeys.intersection(candidateKeys)
                let union        = targetKeys.union(candidateKeys)
                guard !union.isEmpty, !intersection.isEmpty else { return nil }

                // Weighted Jaccard: sum of min-weights in intersection / sum of max-weights in union
                let intersectionWeight = intersection.reduce(0.0) { sum, key in
                    sum + min(targetWeights[key]!, candidateWeights[key]!)
                }
                let unionWeight = union.reduce(0.0) { sum, key in
                    sum + max(targetWeights[key] ?? 0, candidateWeights[key] ?? 0)
                }

                var score = unionWeight > 0 ? intersectionWeight / unionWeight : 0.0

                // Small category boost — same category = more relevant swap
                if candidate.category == product.category { score += 0.04 }

                guard score >= minimumScore else { return nil }

                // Allergen conflict detection
                var conflicts: [String] = []
                if let profile = profile {
                    for ing in candidate.ingredients {
                        for tag in ing.allergenTags {
                            let isAllergen   = profile.allergens.contains    { allergenKey(for: $0) == tag }
                            let isSensitive  = profile.sensitivities.contains { allergenKey(for: $0) == tag }
                            if (isAllergen || isSensitive) && !conflicts.contains(ing.inciName) {
                                conflicts.append(ing.inciName)
                            }
                        }
                    }
                }

                return SimilarProductResult(
                    product: candidate,
                    similarityScore: min(score, 1.0),
                    sharedIngredients: intersection.count,
                    isSafeForProfile: conflicts.isEmpty,
                    allergenConflicts: conflicts
                )
            }
            .sorted { $0.similarityScore > $1.similarityScore }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: — Helpers

    /// Builds a normalised key → weight dictionary for a product's ingredient list.
    /// Weight decays with concentration rank so earlier (more concentrated)
    /// ingredients have more influence on the similarity score.
    private func weightedIngredients(for product: Product) -> [String: Double] {
        var result: [String: Double] = [:]
        let total = Double(product.ingredients.count)
        for ing in product.ingredients {
            let key    = normalise(ing.inciName)
            guard !key.isEmpty else { continue }
            // Weight: ingredient at rank 1 gets weight 1.0, last gets ~0.1
            let rank   = Double(ing.concentrationRank)
            let weight = max(0.1, 1.0 - (rank - 1.0) / max(total, 1.0) * 0.9)
            result[key] = weight
        }
        return result
    }

    /// Normalises an INCI name for consistent matching.
    /// Handles "Aqua/Water/Eau" style multi-name entries by keeping only the first name.
    private func normalise(_ raw: String) -> String {
        let first = raw
            .components(separatedBy: "/").first ?? raw
        return first
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Maps a `KnownAllergen` to the tag string used in `Ingredient.allergenTags`.
    /// Must match the tags in IngredientKnowledgeBase exactly.
    private func allergenKey(for allergen: KnownAllergen) -> String {
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

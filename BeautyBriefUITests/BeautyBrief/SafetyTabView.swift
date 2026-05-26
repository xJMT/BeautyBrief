import SwiftUI

// ─────────────────────────────────────────────
//  SafetyTabView
//  Shows allergen matches and high-risk ingredients.
// ─────────────────────────────────────────────

struct SafetyTabView: View {

    let analysisResult: AnalysisResult?
    let ingredientCount: Int   // passed in so we can warn when 0

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.spacingMd) {

                // Warn when no ingredients were found for this product
                if ingredientCount == 0 {
                    NoIngredientsWarningCard()
                        .padding(.horizontal)
                }

                if let analysis = analysisResult {

                    // ── 1. Personal blacklist hits ─────────────────────────
                    if !analysis.blacklistMatches.isEmpty {
                        BlacklistMatchCard(ingredients: analysis.blacklistMatches)
                            .padding(.horizontal)
                    }

                    // ── 2. Personal allergen matches ───────────────────────
                    if !analysis.allergyMatches.isEmpty {
                        AllergenMatchesSection(matches: analysis.allergyMatches)
                            .padding(.horizontal)
                    } else if analysis.blacklistMatches.isEmpty {
                        NoAllergenMatchCard(ingredientCount: ingredientCount)
                            .padding(.horizontal)
                    }

                    // ── 3. Pregnancy / breastfeeding alerts ───────────────
                    if !analysis.pregnancyAlerts.isEmpty {
                        PregnancyAlertCard(ingredients: analysis.pregnancyAlerts)
                            .padding(.horizontal)
                    }

                    // ── 4. Lifestyle preference conflicts ─────────────────
                    if analysis.hasLifestyleConflicts {
                        LifestyleFlagCard(flags: analysis.lifestyleFlags)
                            .padding(.horizontal)
                    }

                    // ── 5. Skin condition triggers ─────────────────────────
                    if analysis.hasSkinConditionFlags {
                        SkinConditionCard(flags: analysis.skinConditionFlags)
                            .padding(.horizontal)
                    }

                    // ── 5b. Skin type triggers ─────────────────────────────
                    if analysis.hasSkinTypeFlags {
                        SkinTypeCard(flags: analysis.skinTypeFlags)
                            .padding(.horizontal)
                    }

                    // ── 6. Tiered ingredient risk breakdown ───────────────
                    IngredientRiskBreakdown(analysis: analysis)
                        .padding(.horizontal)

                    // ── 7. Chemical concern card ──────────────────────────
                    if analysis.hasChemicalConcerns {
                        ChemicalRiskCard(ingredients: analysis.chemicalConcernIngredients)
                            .padding(.horizontal)
                    }
                } else {
                    // No allergy profile set
                    NoProfileCard()
                        .padding(.horizontal)
                }

                // EU vs US note
                RegionNote()
                    .padding(.horizontal)

                Spacer(minLength: 40)
            }
            .padding(.top, AppTheme.spacingMd)
        }
        .background(AppTheme.beige)
    }
}

// MARK: — Allergen Matches Section
struct AllergenMatchesSection: View {
    let matches: [AllergyMatch]

    // Confirmed allergens first, then caution — within each group keep original order
    private var sortedMatches: [AllergyMatch] {
        matches.sorted { a, b in
            if a.severity == b.severity { return false }
            return a.severity == .confirmed
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(
                icon: "exclamationmark.triangle.fill",
                title: "\(matches.count) Allergen\(matches.count == 1 ? "" : "s") Found",
                color: AppTheme.danger
            )
            ForEach(sortedMatches) { match in
                AllergenMatchRow(match: match)
            }
        }
        .padding(14)
        .beautyCard()
    }
}

struct AllergenMatchRow: View {
    let match: AllergyMatch
    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(match.severity == .confirmed ? AppTheme.danger : AppTheme.warning)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(match.ingredient.inciName)
                    .font(AppTheme.sans(14, weight: .semibold))
                    .foregroundStyle(AppTheme.textMain)
                Text("Matches: \(match.matchedAllergen)")
                    .font(AppTheme.sans(12))
                    .foregroundStyle(AppTheme.textSoft)
            }
            Spacer()
            Text(match.severity.rawValue)
                .font(AppTheme.sans(11, weight: .semibold))
                .foregroundStyle(match.severity == .confirmed ? AppTheme.danger : AppTheme.warning)
        }
        .padding(10)
        .background(match.severity == .confirmed ? Color(hex: "#FEF0F0") : Color(hex: "#FBF3E6"))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusSm))
    }
}

// MARK: — No Ingredients Warning Card
struct NoIngredientsWarningCard: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AppTheme.warning)
                .font(.title3)
            VStack(alignment: .leading, spacing: 4) {
                Text("Ingredient List Unavailable")
                    .font(AppTheme.sans(14, weight: .semibold))
                    .foregroundStyle(AppTheme.textMain)
                Text("We couldn't retrieve the ingredients for this product. Allergen analysis cannot be performed. Check the physical label or the brand's website before use.")
                    .font(AppTheme.sans(12))
                    .foregroundStyle(AppTheme.textSoft)
            }
        }
        .padding(14)
        .background(Color(hex: "#FBF3E6"))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusMd))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.radiusMd)
            .stroke(AppTheme.warning.opacity(0.4), lineWidth: 1)
        }
    }
}

// MARK: — No Allergen Match Card
struct NoAllergenMatchCard: View {
    let ingredientCount: Int
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: ingredientCount > 0 ? "checkmark.circle.fill" : "questionmark.circle.fill")
                .foregroundStyle(ingredientCount > 0 ? AppTheme.success : AppTheme.mochaLight)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(ingredientCount > 0 ? "No profile allergens detected" : "Cannot verify allergens")
                    .font(AppTheme.sans(14, weight: .semibold))
                    .foregroundStyle(AppTheme.textMain)
                Text(ingredientCount > 0
                    ? "None of your flagged allergens appear in this product's ingredient list."
                    : "No ingredient data is available — we can't confirm this product is safe for your profile.")
                    .font(AppTheme.sans(12))
                    .foregroundStyle(AppTheme.textSoft)
            }
        }
        .padding(14)
        .background(ingredientCount > 0 ? Color(hex: "#F0F8F4") : AppTheme.beigeMid)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusMd))
    }
}

// MARK: — High Risk Section
struct HighRiskSection: View {
    let ingredients: [Ingredient]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(icon: "flame.fill",
                          title: "High Irritancy Ingredients",
                          color: AppTheme.danger)
            ForEach(ingredients) { ingredient in
                HStack(spacing: 10) {
                    Circle().fill(AppTheme.danger).frame(width: 6, height: 6)
                    Text(ingredient.inciName)
                        .font(AppTheme.sans(13, weight: .medium))
                        .foregroundStyle(AppTheme.textMain)
                    Spacer()
                    Text("High Risk")
                        .font(AppTheme.sans(11))
                        .foregroundStyle(AppTheme.danger)
                }
                Text(ingredient.description)
                    .font(AppTheme.sans(12))
                    .foregroundStyle(AppTheme.textSoft)
                    .padding(.leading, 16)
            }
        }
        .padding(14)
        .beautyCard()
    }
}

// MARK: — Moderate Risk Section
struct ModerateRiskSection: View {
    let ingredients: [Ingredient]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(icon: "exclamationmark.circle",
                          title: "Moderate Irritancy",
                          color: AppTheme.warning)
            ForEach(ingredients) { ingredient in
                HStack {
                    Circle().fill(AppTheme.warning).frame(width: 6, height: 6)
                    Text(ingredient.inciName)
                        .font(AppTheme.sans(13))
                        .foregroundStyle(AppTheme.textMain)
                    Spacer()
                }
            }
        }
        .padding(14)
        .beautyCard()
    }
}

// MARK: — Ingredient Risk Breakdown (tiered score card)
struct IngredientRiskBreakdown: View {
    let analysis: AnalysisResult

    private var scoreColor: Color { Color(hex: analysis.scoreColor) }

    var body: some View {
        VStack(spacing: AppTheme.spacingMd) {

            // ── Score Badge ───────────────────────────────────────────
            HStack(spacing: 10) {
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text("\(analysis.formulaScore)")
                        .font(AppTheme.sans(20, weight: .bold))
                        .foregroundStyle(.white)
                    Text("/100")
                        .font(AppTheme.sans(12))
                        .foregroundStyle(.white.opacity(0.75))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                Text("·")
                    .font(AppTheme.sans(16))
                    .foregroundStyle(.white.opacity(0.6))
                Text(analysis.scoreLabel)
                    .font(AppTheme.sans(16, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(scoreColor)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusMd))

            // ── High Risk Tier ────────────────────────────────────────
            if !analysis.highRiskIngredients.isEmpty {
                RiskTierCard(
                    title: "High risk",
                    iconColor: Color(hex: "#C97070"),
                    iconName: "circle.fill",
                    ingredients: analysis.highRiskIngredients,
                    previewLimit: 8,
                    tintHex: "#FEF0F0"
                )
            }

            // ── Moderate Risk Tier ────────────────────────────────────
            if !analysis.warningIngredients.isEmpty {
                RiskTierCard(
                    title: "Moderate risk",
                    iconColor: Color(hex: "#D4A96A"),
                    iconName: "circle.fill",
                    ingredients: analysis.warningIngredients,
                    previewLimit: 8,
                    tintHex: "#FBF3E6"
                )
            }

            // ── No Risk Tier ──────────────────────────────────────────
            if !analysis.lowRiskIngredients.isEmpty {
                RiskTierCard(
                    title: "No risk",
                    iconColor: Color(hex: "#7BAE8F"),
                    iconName: "checkmark.circle.fill",
                    ingredients: analysis.lowRiskIngredients,
                    previewLimit: 5,
                    tintHex: "#F0F8F4"
                )
            }
        }
    }
}

struct RiskTierCard: View {
    let title: String
    let iconColor: Color
    let iconName: String
    let ingredients: [Ingredient]
    let previewLimit: Int
    let tintHex: String

    private var preview: [Ingredient] { Array(ingredients.prefix(previewLimit)) }
    private var overflow: Int { max(0, ingredients.count - previewLimit) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header row
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .font(.system(size: 18))
                    .foregroundStyle(iconColor)
                Text(title)
                    .font(AppTheme.sans(14, weight: .semibold))
                    .foregroundStyle(AppTheme.textMain)
                Spacer()
                Text("\(ingredients.count)")
                    .font(AppTheme.sans(12, weight: .medium))
                    .foregroundStyle(iconColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(iconColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            // Ingredient list
            VStack(alignment: .leading, spacing: 6) {
                ForEach(preview) { ingredient in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(iconColor)
                            .frame(width: 5, height: 5)
                        Text(ingredient.inciName)
                            .font(AppTheme.sans(13))
                            .foregroundStyle(AppTheme.textMain)
                            .lineLimit(1)
                        Spacer()
                    }
                }
                if overflow > 0 {
                    Text("+ \(overflow) more")
                        .font(AppTheme.sans(12))
                        .foregroundStyle(AppTheme.textSoft)
                        .padding(.leading, 13)
                }
            }
        }
        .padding(14)
        .background(Color(hex: tintHex))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusMd))
        .overlay {

            RoundedRectangle(cornerRadius: AppTheme.radiusMd)
            .stroke(iconColor.opacity(0.2), lineWidth: 1)
        }
    }
}

// MARK: — Chemical Risk Card
// Shows ingredients with confirmed/suspected endocrine disruption, reproductive toxicity, or carcinogenicity.
struct ChemicalRiskCard: View {
    let ingredients: [Ingredient]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color(hex: "#D4853A"))
                Text("Chemical Concerns")
                    .font(AppTheme.sans(14, weight: .semibold))
                    .foregroundStyle(AppTheme.textMain)
                Spacer()
                Text("\(ingredients.count)")
                    .font(AppTheme.sans(12, weight: .medium))
                    .foregroundStyle(Color(hex: "#D4853A"))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color(hex: "#D4853A").opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            Text("Ingredients with scientific evidence of endocrine disruption, reproductive toxicity, or carcinogenicity.")
                .font(AppTheme.sans(11))
                .foregroundStyle(AppTheme.textSoft)

            // Ingredient rows
            VStack(spacing: 8) {
                ForEach(ingredients) { ing in
                    if let rp = ing.riskProfile
                        ?? IngredientKnowledgeBase.lookup(ing.inciName.lowercased())?.riskProfile {
                        ChemicalRiskRow(ingredient: ing, profile: rp)
                    }
                }
            }
        }
        .padding(14)
        .background(Color(hex: "#FFF8F0"))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusMd))
        .overlay {

            RoundedRectangle(cornerRadius: AppTheme.radiusMd)
            .stroke(Color(hex: "#D4853A").opacity(0.25), lineWidth: 1)
        }
    }
}

struct ChemicalRiskRow: View {
    let ingredient: Ingredient
    let profile: IngredientRiskProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(ingredient.inciName)
                    .font(AppTheme.sans(13, weight: .semibold))
                    .foregroundStyle(AppTheme.textMain)
                    .lineLimit(1)
                Spacer()
                // Worst level badge
                Text(profile.worstChemicalLevel.shortLabel)
                    .font(AppTheme.sans(10, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(hex: profile.worstChemicalLevel.color))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            // Risk dimension tags (only show dimensions that are .suspected or above)
            let dims = activeDimensions(for: profile)
            if !dims.isEmpty {
                HStack(spacing: 6) {
                    ForEach(dims, id: \.label) { dim in
                        Text(dim.label)
                            .font(AppTheme.sans(10))
                            .foregroundStyle(Color(hex: dim.color))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color(hex: dim.color).opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
            }

            // First regulatory flag
            if let flag = profile.regulatoryFlags.first {
                Text(flag)
                    .font(AppTheme.sans(11))
                    .foregroundStyle(AppTheme.textSoft)
                    .lineLimit(2)
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.65))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusSm))
    }

    private struct DimInfo { let label: String; let color: String }

    private func activeDimensions(for rp: IngredientRiskProfile) -> [DimInfo] {
        var result: [DimInfo] = []
        if rp.endocrineDisruption >= .suspected {
            result.append(DimInfo(label: "Endocrine", color: rp.endocrineDisruption.color))
        }
        if rp.reproductiveToxicity >= .suspected {
            result.append(DimInfo(label: "Repro Tox", color: rp.reproductiveToxicity.color))
        }
        if rp.carcinogenicity >= .suspected {
            result.append(DimInfo(label: "Carcinogen", color: rp.carcinogenicity.color))
        }
        return result
    }
}

// MARK: — No Profile Card
struct NoProfileCard: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.largeTitle)
                .foregroundStyle(AppTheme.mochaLight)
            Text("No allergy profile set")
                .font(AppTheme.sans(15, weight: .semibold))
                .foregroundStyle(AppTheme.textMain)
            Text("Go to My Profile to add your allergens. We'll flag them automatically on every scan.")
                .font(AppTheme.sans(13))
                .foregroundStyle(AppTheme.textSoft)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .beautyCard()
    }
}

// MARK: — Region Note
struct RegionNote: View {
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "globe")
                .foregroundStyle(AppTheme.info)
                .font(.caption)
            Text("Some ingredients are banned in the EU but permitted in the US. This app flags EU-restricted ingredients where data is available.")
                .font(AppTheme.sans(12))
                .foregroundStyle(AppTheme.textSoft)
        }
        .padding(12)
        .background(AppTheme.pinkLight)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusSm))
    }
}

// MARK: — High Risk Summary Card (used in Overview)
struct HighRiskSummaryCard: View {
    let ingredients: [Ingredient]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("\(ingredients.count) high-risk ingredient\(ingredients.count == 1 ? "" : "s")",
                  systemImage: "flame.fill")
                .font(AppTheme.sans(13, weight: .semibold))
                .foregroundStyle(AppTheme.danger)
            Text(ingredients.map { $0.inciName }.joined(separator: " · "))
                .font(AppTheme.sans(12))
                .foregroundStyle(AppTheme.textSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(hex: "#FFF0F0"))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusMd))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.radiusMd)
            .stroke(AppTheme.danger.opacity(0.2), lineWidth: 1)
        }
    }
}

// MARK: — Allergen Alert Card (used in Overview)
struct AllergenAlertCard: View {
    let matches: [AllergyMatch]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.white)
                Text("Your allergens detected!")
                    .font(AppTheme.sans(14, weight: .bold))
                    .foregroundStyle(.white)
            }
            Text(matches.map { $0.ingredient.inciName }.joined(separator: ", "))
                .font(AppTheme.sans(13))
                .foregroundStyle(.white.opacity(0.9))
            Text("Go to the Safety tab for full details.")
                .font(AppTheme.sans(12))
                .foregroundStyle(.white.opacity(0.8))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AppTheme.danger)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusMd))
    }
}

// MARK: — Blacklist Match Card
struct BlacklistMatchCard: View {
    let ingredients: [Ingredient]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "slash.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(AppTheme.danger)
                Text("Blacklisted Ingredient\(ingredients.count == 1 ? "" : "s") Detected")
                    .font(AppTheme.sans(14, weight: .semibold))
                    .foregroundStyle(AppTheme.textMain)
                Spacer()
                Text("\(ingredients.count)")
                    .font(AppTheme.sans(12, weight: .medium))
                    .foregroundStyle(AppTheme.danger)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(AppTheme.danger.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            Text("You've personally blacklisted the following ingredient\(ingredients.count == 1 ? "" : "s"). Avoid this product.")
                .font(AppTheme.sans(12))
                .foregroundStyle(AppTheme.textSoft)

            ForEach(ingredients) { ing in
                HStack(spacing: 8) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(AppTheme.danger)
                        .font(.caption)
                    Text(ing.inciName)
                        .font(AppTheme.sans(13, weight: .semibold))
                        .foregroundStyle(AppTheme.textMain)
                    Spacer()
                }
                .padding(10)
                .background(Color(hex: "#FEF0F0"))
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusSm))
            }
        }
        .padding(14)
        .background(Color(hex: "#FFF5F5"))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusMd))
        .overlay {

            RoundedRectangle(cornerRadius: AppTheme.radiusMd)
            .stroke(AppTheme.danger.opacity(0.35), lineWidth: 1)
        }
    }
}

// MARK: — Pregnancy Alert Card
struct PregnancyAlertCard: View {
    let ingredients: [Ingredient]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color(hex: "#C97070"))
                Text("Pregnancy/Breastfeeding Caution")
                    .font(AppTheme.sans(14, weight: .semibold))
                    .foregroundStyle(AppTheme.textMain)
                Spacer()
                Text("\(ingredients.count)")
                    .font(AppTheme.sans(12, weight: .medium))
                    .foregroundStyle(Color(hex: "#C97070"))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color(hex: "#C97070").opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            Text("The following ingredients are commonly advised against during pregnancy or breastfeeding. Consult your healthcare provider before use.")
                .font(AppTheme.sans(12))
                .foregroundStyle(AppTheme.textSoft)

            ForEach(ingredients) { ing in
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color(hex: "#C97070"))
                        .frame(width: 6, height: 6)
                    Text(ing.inciName)
                        .font(AppTheme.sans(13))
                        .foregroundStyle(AppTheme.textMain)
                    Spacer()
                }
            }
        }
        .padding(14)
        .background(Color(hex: "#FFF5F5"))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusMd))
        .overlay {

            RoundedRectangle(cornerRadius: AppTheme.radiusMd)
            .stroke(Color(hex: "#C97070").opacity(0.3), lineWidth: 1)
        }
    }
}

// MARK: — Lifestyle Flag Card
struct LifestyleFlagCard: View {
    let flags: [LifestyleFlag]

    // Group flags by preference for tidier display
    private var grouped: [(LifestylePreference, [Ingredient])] {
        var dict: [LifestylePreference: [Ingredient]] = [:]
        for flag in flags {
            dict[flag.matchedPreference, default: []].append(flag.ingredient)
        }
        return LifestylePreference.allCases.compactMap { pref in
            guard let ings = dict[pref], !ings.isEmpty else { return nil }
            return (pref, ings)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color(hex: "#6B9E78"))
                Text("Lifestyle Conflicts")
                    .font(AppTheme.sans(14, weight: .semibold))
                    .foregroundStyle(AppTheme.textMain)
                Spacer()
                Text("\(flags.count)")
                    .font(AppTheme.sans(12, weight: .medium))
                    .foregroundStyle(Color(hex: "#6B9E78"))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color(hex: "#6B9E78").opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            ForEach(grouped, id: \.0) { pref, ingredients in
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Image(systemName: pref.sfSymbol)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color(hex: "#6B9E78"))
                        Text(pref.rawValue)
                            .font(AppTheme.sans(12, weight: .semibold))
                            .foregroundStyle(AppTheme.mochaDark)
                    }
                    ForEach(ingredients) { ing in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color(hex: "#6B9E78"))
                                .frame(width: 4, height: 4)
                            Text(ing.inciName)
                                .font(AppTheme.sans(12))
                                .foregroundStyle(AppTheme.textMain)
                            Spacer()
                        }
                        .padding(.leading, 4)
                    }
                }
                .padding(10)
                .background(Color(hex: "#F1F8F3"))
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusSm))
            }
        }
        .padding(14)
        .background(Color(hex: "#F5FAF6"))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusMd))
        .overlay {

            RoundedRectangle(cornerRadius: AppTheme.radiusMd)
            .stroke(Color(hex: "#6B9E78").opacity(0.3), lineWidth: 1)
        }
    }
}

// MARK: — Skin Condition Card
struct SkinConditionCard: View {
    let flags: [SkinConditionFlag]

    private var grouped: [(SkinConcern, [Ingredient])] {
        var dict: [SkinConcern: [Ingredient]] = [:]
        for flag in flags {
            dict[flag.matchedConcern, default: []].append(flag.ingredient)
        }
        return SkinConcern.allCases.compactMap { concern in
            guard let ings = dict[concern], !ings.isEmpty else { return nil }
            return (concern, ings)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 16))
                    .foregroundStyle(AppTheme.warning)
                Text("Skin Condition Triggers")
                    .font(AppTheme.sans(14, weight: .semibold))
                    .foregroundStyle(AppTheme.textMain)
                Spacer()
                Text("\(flags.count)")
                    .font(AppTheme.sans(12, weight: .medium))
                    .foregroundStyle(AppTheme.warning)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(AppTheme.warning.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            Text("Ingredients that commonly trigger your registered skin conditions.")
                .font(AppTheme.sans(12))
                .foregroundStyle(AppTheme.textSoft)

            ForEach(grouped, id: \.0) { concern, ingredients in
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Image(systemName: concern.sfSymbol)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppTheme.warning)
                        Text(concern.rawValue)
                            .font(AppTheme.sans(12, weight: .semibold))
                            .foregroundStyle(AppTheme.mochaDark)
                    }
                    ForEach(ingredients) { ing in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(AppTheme.warning)
                                .frame(width: 4, height: 4)
                            Text(ing.inciName)
                                .font(AppTheme.sans(12))
                                .foregroundStyle(AppTheme.textMain)
                            Spacer()
                        }
                        .padding(.leading, 4)
                    }
                }
                .padding(10)
                .background(Color(hex: "#FBF6E6"))
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusSm))
            }
        }
        .padding(14)
        .background(Color(hex: "#FDFAF0"))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusMd))
        .overlay {

            RoundedRectangle(cornerRadius: AppTheme.radiusMd)
            .stroke(AppTheme.warning.opacity(0.3), lineWidth: 1)
        }
    }
}

// MARK: — Skin Type Card
struct SkinTypeCard: View {
    let flags: [SkinTypeFlag]

    private var grouped: [(SkinType, [Ingredient])] {
        var dict: [SkinType: [Ingredient]] = [:]
        for flag in flags {
            dict[flag.matchedSkinType, default: []].append(flag.ingredient)
        }
        return SkinType.allCases.compactMap { type in
            guard let ings = dict[type], !ings.isEmpty else { return nil }
            return (type, ings)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "person.fill.viewfinder")
                    .font(.system(size: 16))
                    .foregroundStyle(AppTheme.pinkDark)
                Text("Skin Type Triggers")
                    .font(AppTheme.sans(14, weight: .semibold))
                    .foregroundStyle(AppTheme.textMain)
                Spacer()
                Text("\(flags.count)")
                    .font(AppTheme.sans(12, weight: .medium))
                    .foregroundStyle(AppTheme.pinkDark)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(AppTheme.pinkDark.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            Text("Ingredients that may not suit your skin type.")
                .font(AppTheme.sans(12))
                .foregroundStyle(AppTheme.textSoft)

            ForEach(grouped, id: \.0) { skinType, ingredients in
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Image(systemName: skinType.sfSymbol)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppTheme.pinkDark)
                        Text(skinType.rawValue)
                            .font(AppTheme.sans(12, weight: .semibold))
                            .foregroundStyle(AppTheme.mochaDark)
                    }
                    ForEach(ingredients) { ing in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(AppTheme.pinkDark)
                                .frame(width: 4, height: 4)
                            Text(ing.inciName)
                                .font(AppTheme.sans(12))
                                .foregroundStyle(AppTheme.textMain)
                            Spacer()
                        }
                        .padding(.leading, 4)
                    }
                }
                .padding(10)
                .background(AppTheme.pinkLight)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusSm))
            }
        }
        .padding(14)
        .background(Color(hex: "#FDF5F8"))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusMd))
        .overlay {

            RoundedRectangle(cornerRadius: AppTheme.radiusMd)
            .stroke(AppTheme.pinkDark.opacity(0.25), lineWidth: 1)
        }
    }
}

// MARK: — Section Header
struct SectionHeader: View {
    let icon: String
    let title: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.subheadline)
            Text(title)
                .font(AppTheme.sans(14, weight: .semibold))
                .foregroundStyle(AppTheme.textMain)
        }
    }
}

#Preview {
    SafetyTabView(analysisResult: nil, ingredientCount: 5)
}

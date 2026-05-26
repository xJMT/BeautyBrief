import SwiftUI

// ─────────────────────────────────────────────
//  IngredientsTabView
//  Full ingredient list with functions, risks,
//  and personal allergy highlighting.
// ─────────────────────────────────────────────

struct IngredientsTabView: View {

    let ingredients: [Ingredient]
    let allergyMatches: [AllergyMatch]

    @State private var searchText    = ""
    @State private var selectedFilter: IrritancyLevel? = nil

    private var filteredIngredients: [Ingredient] {
        var list = ingredients
        if !searchText.isEmpty {
            list = list.filter {
                $0.inciName.localizedCaseInsensitiveContains(searchText) ||
                ($0.commonName?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
        if let filter = selectedFilter {
            list = list.filter { $0.irritancyRisk == filter }
        }
        return list
    }

    private func isAllergyFlag(_ ingredient: Ingredient) -> AllergyMatch? {
        allergyMatches.first { $0.ingredient.id == ingredient.id }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search + filter
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(AppTheme.textSoft)
                    TextField("Search ingredients…", text: $searchText)
                        .font(AppTheme.sans(14))
                }
                .padding(10)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusSm))
                .padding(.horizontal)

                // Risk filter chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        FilterChip(label: "All", isSelected: selectedFilter == nil) {
                            selectedFilter = nil
                        }
                        ForEach(IrritancyLevel.allCases, id: \.rawValue) { level in
                            FilterChip(label: level.label,
                                       isSelected: selectedFilter == level,
                                       color: Color(hex: level.color)) {
                                selectedFilter = selectedFilter == level ? nil : level
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical, 10)
            .background(AppTheme.beigeMid)

            // Legend
            HStack(spacing: 16) {
                Text("INCI order = concentration (highest first)")
                    .font(AppTheme.sans(11))
                    .foregroundStyle(AppTheme.textSoft)
                Spacer()
                Text("\(filteredIngredients.count) ingredients")
                    .font(AppTheme.sans(11))
                    .foregroundStyle(AppTheme.textSoft)
            }
            .padding(.horizontal, AppTheme.spacingMd)
            .padding(.vertical, 8)
            .background(Color.white)

            // Ingredient list
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(filteredIngredients) { ingredient in
                        IngredientRow(
                            ingredient: ingredient,
                            allergyMatch: isAllergyFlag(ingredient)
                        )
                    }
                }
                .padding(.bottom, 40)
            }
            .background(AppTheme.beige)
        }
    }
}

// MARK: — Ingredient Row
struct IngredientRow: View {

    let ingredient: Ingredient
    let allergyMatch: AllergyMatch?
    @State private var isExpanded = false

    private var rowBackground: Color {
        if allergyMatch?.severity == .confirmed { return Color(hex: "#FEF0F0") }
        if allergyMatch?.severity == .caution   { return Color(hex: "#FBF3E6") }
        if ingredient.irritancyRisk == .high    { return Color(hex: "#FFF8F0") }
        return .white
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    // Rank number
                    Text("\(ingredient.concentrationRank)")
                        .font(AppTheme.sans(11))
                        .foregroundStyle(AppTheme.textSoft)
                        .frame(width: 22, alignment: .trailing)

                    VStack(alignment: .leading, spacing: 4) {
                        // Name
                        HStack(alignment: .center, spacing: 6) {
                            Text(ingredient.inciName)
                                .font(AppTheme.sans(14, weight: allergyMatch != nil ? .semibold : .regular))
                                .foregroundStyle(AppTheme.textMain)
                            if let common = ingredient.commonName {
                                Text("(\(common))")
                                    .font(AppTheme.sans(12))
                                    .foregroundStyle(AppTheme.textSoft)
                            }
                        }
                        // Function chips
                        HStack(spacing: 4) {
                            ForEach(ingredient.function, id: \.rawValue) { fn in
                                Text(fn.rawValue)
                                    .font(AppTheme.sans(10))
                                    .foregroundStyle(Color(hex: fn.color))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color(hex: fn.color).opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                        }
                    }

                    Spacer()

                    // Right side badges
                    VStack(alignment: .trailing, spacing: 4) {
                        if let match = allergyMatch {
                            AllergenBadge(severity: match.severity)
                        } else {
                            IrritancyBadge(level: ingredient.irritancyRisk)
                        }
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSoft)
                    }
                }
                .padding(.horizontal, AppTheme.spacingMd)
                .padding(.vertical, 12)
                .background(rowBackground)
            }
            .buttonStyle(.plain)

            // Expanded detail
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Divider().padding(.horizontal, AppTheme.spacingMd)

                    Text(ingredient.description)
                        .font(AppTheme.sans(13))
                        .foregroundStyle(AppTheme.textSoft)
                        .padding(.horizontal, AppTheme.spacingMd)

                    if let match = allergyMatch {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(AppTheme.danger)
                                .font(.caption)
                            Text("Matches your profile: \(match.matchedAllergen)")
                                .font(AppTheme.sans(12, weight: .semibold))
                                .foregroundStyle(AppTheme.danger)
                        }
                        .padding(.horizontal, AppTheme.spacingMd)
                    }

                    Text("Source: \(ingredient.source)")
                        .font(AppTheme.sans(11))
                        .foregroundStyle(AppTheme.mochaLight)
                        .padding(.horizontal, AppTheme.spacingMd)
                        .padding(.bottom, 10)
                }
                .background(rowBackground.opacity(0.6))
            }
        }
    }
}

// MARK: — Small Badges
struct AllergenBadge: View {
    let severity: AllergySeverity
    var body: some View {
        Text(severity.rawValue)
            .font(AppTheme.sans(10, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(severity == .confirmed ? AppTheme.danger : AppTheme.warning)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct IrritancyBadge: View {
    let level: IrritancyLevel
    var body: some View {
        if level == .low { EmptyView() } else {
            Text(level.label)
                .font(AppTheme.sans(10))
                .foregroundStyle(Color(hex: level.color))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color(hex: level.color).opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}

struct FilterChip: View {
    let label: String
    let isSelected: Bool
    var color: Color = AppTheme.mocha
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(AppTheme.sans(12, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .white : AppTheme.mocha)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? color : AppTheme.beige)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay {

                    Capsule()
                    .stroke(AppTheme.beigeDark, lineWidth: isSelected ? 0 : 1)
                }
        }
    }
}

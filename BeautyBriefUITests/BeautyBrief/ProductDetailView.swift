import SwiftUI

// ─────────────────────────────────────────────
//  ProductDetailView  —  full product intelligence
//  Tabbed: Overview · Ingredients · Safety · Expiry · Similar
// ─────────────────────────────────────────────

struct ProductDetailView: View {

    let product: Product
    let analysisResult: AnalysisResult?
    let batchResult: BatchDecodeResult?
    let confidenceScore: Double

    @EnvironmentObject private var allergyVM: AllergyProfileViewModel
    @State private var selectedTab = 0

    private let tabLabels = ["Overview", "Ingredients", "Safety", "Scores", "Expiry", "Similar"]

    private var productScores: ProductScores? {
        guard let analysis = analysisResult else { return nil }
        return ProductScoringService.computeScores(
            product: product,
            profile: allergyVM.profile,
            analysis: analysis
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                productHeader

                // Ingredient score bar (if analysis present)
                if let analysis = analysisResult {
                    IngredientScoreBar(score: analysis.formulaScore, label: analysis.scoreLabel)
                }

                // Tab picker — scrollable so all 6 fit without clipping
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(Array(tabLabels.enumerated()), id: \.offset) { idx, label in
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) { selectedTab = idx }
                            } label: {
                                VStack(spacing: 4) {
                                    Text(label)
                                        .font(AppTheme.sans(13, weight: selectedTab == idx ? .semibold : .regular))
                                        .foregroundStyle(selectedTab == idx ? AppTheme.mochaDark : AppTheme.textSoft)
                                        .padding(.horizontal, 14)
                                        .padding(.top, 10)
                                    Rectangle()
                                        .fill(selectedTab == idx ? AppTheme.mocha : Color.clear)
                                        .frame(height: 2)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .background(Color.white)

                Divider()

                // Tab content
                TabView(selection: $selectedTab) {
                    OverviewTabView(product: product,
                                   confidenceScore: confidenceScore,
                                   analysisResult: analysisResult)
                        .tag(0)
                    IngredientsTabView(ingredients: product.ingredients,
                                       allergyMatches: analysisResult?.allergyMatches ?? [])
                        .tag(1)
                    SafetyTabView(analysisResult: analysisResult,
                                  ingredientCount: product.ingredients.count)
                        .tag(2)
                    if let scores = productScores {
                        ScoresTabView(scores: scores, profile: allergyVM.profile)
                            .tag(3)
                    } else {
                        ScoresUnavailableView()
                            .tag(3)
                    }
                    ExpiryTabView(expiryInfo: product.expiryInfo,
                                  batchResult: batchResult,
                                  category: product.category)
                        .tag(4)
                    SimilarProductsTabView(product: product,
                                           allergyProfile: allergyVM.profile)
                        .tag(5)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .background(AppTheme.beige.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    // Show brand if we have one, otherwise fall back to product name
                    Text(product.knownBrand ?? product.name)
                        .font(AppTheme.serif(16, weight: .semibold))
                        .foregroundStyle(AppTheme.mochaDark)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        // Error report
                    } label: {
                        Image(systemName: "exclamationmark.bubble")
                            .foregroundStyle(AppTheme.mocha)
                    }
                }
            }
        }
    }

    // MARK: — Product Header
    private var productHeader: some View {
        HStack(spacing: 16) {
            // Product image (from API) or category icon fallback
            productThumbnail

            VStack(alignment: .leading, spacing: 4) {
                Text(product.name)
                    .font(AppTheme.serif(18, weight: .semibold))
                    .foregroundStyle(AppTheme.mochaDark)
                    .lineLimit(2)
                // Only show brand if it's a real value
                if let knownBrand = product.knownBrand {
                    Text(knownBrand)
                        .font(AppTheme.sans(14))
                        .foregroundStyle(AppTheme.textSoft)
                }
                // Only show category chip if it's a known category
                if product.category != .unknown {
                    Text(product.category.rawValue)
                        .font(AppTheme.sans(12))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(AppTheme.mocha)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            Spacer()
            ConfidenceBadge(score: confidenceScore, compact: true)
        }
        .padding(AppTheme.spacingMd)
        .background(Color.white)
    }

    @ViewBuilder
    private var productThumbnail: some View {
        if let urlString = product.imageURL, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                case .failure(_), .empty:
                    categoryIconPlaceholder
                @unknown default:
                    categoryIconPlaceholder
                }
            }
        } else {
            categoryIconPlaceholder
        }
    }

    private var categoryIconPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(product.category.color.opacity(0.14))
                .frame(width: 64, height: 64)
            Image(systemName: product.category.sfSymbol)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(product.category.color)
        }
    }
}

// MARK: — Ingredient Score Bar
struct IngredientScoreBar: View {
    let score: Int
    let label: String

    private var barColor: Color {
        switch score {
        case 85...100: return Color(hex: "#7BAE8F")
        case 70..<85:  return Color(hex: "#7A9EBE")
        case 55..<70:  return Color(hex: "#C8A030")
        case 40..<55:  return Color(hex: "#D4853A")
        default:       return Color(hex: "#8B2020")
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            // Score pill
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text("\(score)")
                    .font(AppTheme.sans(18, weight: .bold))
                    .foregroundStyle(.white)
                Text("/100")
                    .font(AppTheme.sans(11))
                    .foregroundStyle(.white.opacity(0.75))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Text("·")
                .font(AppTheme.sans(14))
                .foregroundStyle(.white.opacity(0.6))

            Text(label)
                .font(AppTheme.sans(14, weight: .semibold))
                .foregroundStyle(.white)

            Spacer()

            Text("Ingredient Score")
                .font(AppTheme.sans(11))
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.horizontal, AppTheme.spacingMd)
        .padding(.vertical, 10)
        .background(barColor)
    }
}

// MARK: — Scores Unavailable
struct ScoresUnavailableView: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 44))
                .foregroundStyle(AppTheme.mochaLight)
            Text("Scores Unavailable")
                .font(AppTheme.serif(17, weight: .semibold))
                .foregroundStyle(AppTheme.mochaDark)
            Text("Scan a product with a full ingredient list to see all 8 specialised scores.")
                .font(AppTheme.sans(14))
                .foregroundStyle(AppTheme.textSoft)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
        .background(AppTheme.beige)
    }
}

// MARK: — Overview Tab
struct OverviewTabView: View {
    let product: Product
    let confidenceScore: Double
    let analysisResult: AnalysisResult?

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.spacingMd) {

                // Quick stats row
                HStack(spacing: 12) {
                    StatCard(icon: "list.bullet",
                             value: "\(product.ingredients.count)",
                             label: "Ingredients")
                    StatCard(icon: "exclamationmark.triangle",
                             value: "\(analysisResult?.allergyMatches.count ?? 0)",
                             label: "Flags",
                             valueColor: (analysisResult?.allergyMatches.isEmpty ?? true) ? AppTheme.success : AppTheme.danger)
                }
                .padding(.horizontal)

                // Allergy alerts (if any)
                if let analysis = analysisResult, !analysis.allergyMatches.isEmpty {
                    AllergenAlertCard(matches: analysis.allergyMatches)
                        .padding(.horizontal)
                }

                // High-risk ingredients summary
                if let analysis = analysisResult, !analysis.highRiskIngredients.isEmpty {
                    HighRiskSummaryCard(ingredients: analysis.highRiskIngredients)
                        .padding(.horizontal)
                }

                // Patch test recommendation
                if analysisResult?.patchTestRecommended == true {
                    PatchTestCard()
                        .padding(.horizontal)
                }

                // Data source info
                DataSourceCard(source: product.dataSource,
                               verified: product.dataLastVerified)
                    .padding(.horizontal)

                Spacer(minLength: 40)
            }
            .padding(.top, AppTheme.spacingMd)
        }
    }
}

// MARK: — Stat Card
struct StatCard: View {
    let icon: String
    let value: String
    let label: String
    var valueColor: Color = AppTheme.mochaDark

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(AppTheme.mochaLight)
            Text(value)
                .font(AppTheme.sans(16, weight: .bold))
                .foregroundStyle(valueColor)
            Text(label)
                .font(AppTheme.sans(11))
                .foregroundStyle(AppTheme.textSoft)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .beautyCard()
    }
}

// MARK: — Patch Test Card
struct PatchTestCard: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "hand.raised.fill")
                .font(.title3)
                .foregroundStyle(AppTheme.warning)
            VStack(alignment: .leading, spacing: 4) {
                Text("Patch Test Recommended")
                    .font(AppTheme.sans(14, weight: .semibold))
                    .foregroundStyle(AppTheme.textMain)
                Text("This product contains high-irritancy or flagged ingredients. Apply a small amount to your inner arm and wait 24 hours before full use.")
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

// MARK: — Data Source Card
struct DataSourceCard: View {
    let source: String
    let verified: Date?

    private var verifiedString: String {
        guard let d = verified else { return "Not verified" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return "Verified " + formatter.localizedString(for: d, relativeTo: .now)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Data Source", systemImage: "checkmark.seal.fill")
                .font(AppTheme.sans(13, weight: .semibold))
                .foregroundStyle(AppTheme.success)
            Text(source)
                .font(AppTheme.sans(13))
                .foregroundStyle(AppTheme.textMain)
            Text(verifiedString)
                .font(AppTheme.sans(12))
                .foregroundStyle(AppTheme.textSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .beautyCard()
    }
}

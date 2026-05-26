import SwiftUI

// ─────────────────────────────────────────────
//  SimilarProductsTabView
//  Shows products with similar ingredient profiles,
//  ranked by weighted Jaccard similarity.
//  Each card flags whether the product is safe
//  for the user's personal allergen profile.
// ─────────────────────────────────────────────

struct SimilarProductsTabView: View {

    let product: Product
    let allergyProfile: AllergyProfile?

    @State private var results: [SimilarProductResult] = []
    @State private var isLoading = true

    private let service = SimilarProductsService.shared

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.spacingMd) {

                if isLoading {
                    loadingView
                } else if results.isEmpty {
                    emptyView
                } else {
                    // Header explanation
                    explanationCard
                        .padding(.horizontal)

                    // Result cards
                    ForEach(results) { result in
                        SimilarProductCard(result: result, allergyProfile: allergyProfile)
                            .padding(.horizontal)
                    }
                }

                Spacer(minLength: 40)
            }
            .padding(.top, AppTheme.spacingMd)
        }
        .background(AppTheme.beige)
        .task {
            // Compute similarity off the main thread to avoid any stutter
            let found = service.findSimilar(to: product, profile: allergyProfile, limit: 8)
            results   = found
            isLoading = false
        }
    }

    // MARK: — Sub-views

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(AppTheme.mocha)
            Text("Finding similar products…")
                .font(AppTheme.sans(13))
                .foregroundStyle(AppTheme.textSoft)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.stack.3d.up.slash")
                .font(.largeTitle)
                .foregroundStyle(AppTheme.mochaLight)
            Text("No similar products found")
                .font(AppTheme.sans(15, weight: .semibold))
                .foregroundStyle(AppTheme.textMain)
            Text("We couldn't find products in our database with enough ingredient overlap. Try scanning more products to build up comparisons.")
                .font(AppTheme.sans(13))
                .foregroundStyle(AppTheme.textSoft)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
    }

    private var explanationCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "flask.fill")
                .foregroundStyle(AppTheme.mocha)
                .font(.caption)
                .padding(.top, 2)
            Text("Ranked by how closely ingredient lists overlap. A green badge means no conflicts with your allergen profile.")
                .font(AppTheme.sans(12))
                .foregroundStyle(AppTheme.textSoft)
        }
        .padding(12)
        .background(AppTheme.pinkLight)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusSm))
    }
}

// MARK: — Similar Product Card

struct SimilarProductCard: View {

    let result: SimilarProductResult
    let allergyProfile: AllergyProfile?

    @State private var showDetail = false

    private var matchPercent: Int { Int((result.similarityScore * 100).rounded()) }
    private var matchColor: Color {
        switch matchPercent {
        case 70...: return AppTheme.success
        case 40...: return Color(hex: "#D4A96A")
        default:    return AppTheme.mochaLight
        }
    }

    var body: some View {
        Button {
            showDetail = true
        } label: {
            VStack(alignment: .leading, spacing: 0) {

                // Top row: name + match badge
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(result.product.brand)
                            .font(AppTheme.sans(11, weight: .semibold))
                            .foregroundStyle(AppTheme.mochaLight)
                            .lineLimit(1)
                        Text(result.product.name)
                            .font(AppTheme.sans(14, weight: .semibold))
                            .foregroundStyle(AppTheme.textMain)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer()
                    // Match % badge
                    Text("\(matchPercent)%")
                        .font(AppTheme.sans(13, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(matchColor)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .padding(.bottom, 10)

                Divider()
                    .padding(.bottom, 10)

                // Bottom row: shared ingredients + safety badge
                HStack(spacing: 8) {
                    // Category pill
                    Text(result.product.category.rawValue)
                        .font(AppTheme.sans(11))
                        .foregroundStyle(AppTheme.textSoft)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(AppTheme.beigeMid)
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                    // Shared ingredient count
                    HStack(spacing: 4) {
                        Image(systemName: "drop.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(AppTheme.mochaLight)
                        Text("\(result.sharedIngredients) shared")
                            .font(AppTheme.sans(11))
                            .foregroundStyle(AppTheme.textSoft)
                    }

                    Spacer()

                    // Safety badge
                    if allergyProfile != nil {
                        if result.isSafeForProfile {
                            Label("Safe for you", systemImage: "checkmark.shield.fill")
                                .font(AppTheme.sans(11, weight: .semibold))
                                .foregroundStyle(AppTheme.success)
                        } else {
                            Label("Contains allergens", systemImage: "exclamationmark.triangle.fill")
                                .font(AppTheme.sans(11, weight: .semibold))
                                .foregroundStyle(AppTheme.danger)
                        }
                    }
                }

                // Allergen conflict detail (if any)
                if !result.allergenConflicts.isEmpty {
                    Text("Conflicts: \(result.allergenConflicts.prefix(3).joined(separator: ", "))\(result.allergenConflicts.count > 3 ? " +\(result.allergenConflicts.count - 3) more" : "")")
                        .font(AppTheme.sans(11))
                        .foregroundStyle(AppTheme.danger.opacity(0.8))
                        .padding(.top, 6)
                }
            }
            .padding(14)
            .beautyCard()
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showDetail) {
            SimilarProductDetailSheet(product: result.product, allergyProfile: allergyProfile)
        }
    }
}

// MARK: — Similar Product Detail Sheet

/// Lightweight sheet showing the similar product's detail.
/// Computes a fresh analysis inline so no navigation plumbing is needed.
struct SimilarProductDetailSheet: View {

    let product: Product
    let allergyProfile: AllergyProfile?

    @Environment(\.dismiss) private var dismiss

    private var analysisResult: AnalysisResult? {
        guard let profile = allergyProfile else { return nil }
        return IngredientAnalysisService.analyse(product: product, profile: profile)
    }

    var body: some View {
        NavigationStack {
            ProductDetailView(
                product: product,
                analysisResult: analysisResult,
                batchResult: nil,
                confidenceScore: 1.0
            )
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(AppTheme.mocha)
                }
            }
        }
    }
}

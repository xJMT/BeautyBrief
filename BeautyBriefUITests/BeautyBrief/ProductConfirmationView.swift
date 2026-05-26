import SwiftUI

// ─────────────────────────────────────────────
//  ProductConfirmationView
//  Shown when scan returns candidates.
//  User must confirm the correct product before
//  ingredient / allergen data is unlocked.
// ─────────────────────────────────────────────

struct ProductConfirmationView: View {

    let candidates: [ScanCandidate]
    let onConfirm: (ScanCandidate) -> Void
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppTheme.spacingMd) {

                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(AppTheme.success)
                        Text("Is this the right product?")
                            .font(AppTheme.serif(22, weight: .semibold))
                            .foregroundStyle(AppTheme.mochaDark)
                        Text("Confirm before we unlock ingredient & safety data")
                            .font(AppTheme.sans(14))
                            .foregroundStyle(AppTheme.textSoft)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 24)
                    .padding(.horizontal)

                    // Disclaimer
                    DisclaimerBanner()
                        .padding(.horizontal)

                    // Candidates
                    ForEach(Array(candidates.enumerated()), id: \.element.id) { index, candidate in
                        CandidateCard(
                            candidate: candidate,
                            rank: index + 1,
                            onConfirm: { onConfirm(candidate) }
                        )
                        .padding(.horizontal)
                    }

                    // None of these
                    Button {
                        onDismiss()
                    } label: {
                        Text("None of these — try again")
                            .font(AppTheme.sans(15, weight: .medium))
                            .foregroundStyle(AppTheme.mocha)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(AppTheme.pinkLight)
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusMd))
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 40)
                }
            }
            .background(AppTheme.beige.ignoresSafeArea())
            .navigationTitle("Confirm Product")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDismiss() }
                        .foregroundStyle(AppTheme.mocha)
                }
            }
        }
    }
}

// MARK: — Candidate Card
struct CandidateCard: View {

    let candidate: ScanCandidate
    let rank: Int
    let onConfirm: () -> Void

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Pink accent bar for top candidate
            if rank == 1 {
                Rectangle()
                    .fill(LinearGradient(colors: [AppTheme.pinkDark, AppTheme.pink],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(height: 4)
            }

            VStack(alignment: .leading, spacing: 12) {
                // Product info row
                HStack(alignment: .top, spacing: 14) {
                    // Category icon
                    ZStack {
                        Circle()
                            .fill(candidate.product.category.color.opacity(0.12))
                            .frame(width: 50, height: 50)
                        Image(systemName: candidate.product.category.sfSymbol)
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(candidate.product.category.color)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        if rank == 1 {
                            Text("Best Match")
                                .font(AppTheme.sans(10, weight: .bold))
                                .foregroundStyle(AppTheme.pinkDark)
                                .textCase(.uppercase)
                                .kerning(1)
                        }
                        Text(candidate.product.name)
                            .font(AppTheme.serif(17, weight: .semibold))
                            .foregroundStyle(AppTheme.mochaDark)
                        Text(candidate.product.brand)
                            .font(AppTheme.sans(14))
                            .foregroundStyle(AppTheme.textSoft)
                        Text(candidate.product.category.rawValue)
                            .font(AppTheme.sans(12))
                            .foregroundStyle(AppTheme.mochaLight)
                    }
                    Spacer()

                    // Confidence badge
                    ConfidenceBadge(score: candidate.confidenceScore)
                }

                // Method tag
                HStack(spacing: 6) {
                    Image(systemName: candidate.identificationMethod == .barcode ? "barcode" : "viewfinder")
                        .font(.caption)
                    Text(candidate.identificationMethod.rawValue)
                        .font(AppTheme.sans(12))
                }
                .foregroundStyle(AppTheme.textSoft)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(AppTheme.beigeMid)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusSm))

                // Low confidence warning
                if !candidate.isHighConfidence {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(AppTheme.warning)
                        Text("Confidence below 95% — please verify this is correct")
                            .font(AppTheme.sans(12))
                            .foregroundStyle(AppTheme.textMain)
                    }
                    .padding(10)
                    .background(Color(hex: "#FBF3E6"))
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusSm))
                }

                // Confirm button
                Button {
                    onConfirm()
                } label: {
                    HStack {
                        Image(systemName: "checkmark")
                        Text("Yes, this is correct")
                            .font(AppTheme.sans(15, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(rank == 1 ? AppTheme.mocha : AppTheme.beigeDark)
                    .foregroundStyle(rank == 1 ? .white : AppTheme.mocha)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusMd))
                }
            }
            .padding(18)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusMd))
        .shadow(color: AppTheme.cardShadow, radius: AppTheme.shadowRadius, x: 0, y: AppTheme.shadowY)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusMd))
    }
}

// MARK: — Disclaimer Banner
struct DisclaimerBanner: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(AppTheme.mochaLight)
            Text("This app is informational only — not medical advice. Consult a dermatologist for personal skin concerns.")
                .font(AppTheme.sans(12))
                .foregroundStyle(AppTheme.textSoft)
        }
        .padding(12)
        .background(AppTheme.pinkLight)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusSm))
    }
}

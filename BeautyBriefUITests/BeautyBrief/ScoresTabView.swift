import SwiftUI

// ─────────────────────────────────────────────
//  ScoresTabView
//  8 specialised ingredient scores displayed
//  as beautiful, readable score cards.
// ─────────────────────────────────────────────

struct ScoresTabView: View {

    let scores: ProductScores
    let profile: AllergyProfile

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.spacingMd) {

                // Summary row — quick-glance tiles
                ScoreSummaryRow(scores: scores, profile: profile)
                    .padding(.horizontal)

                // ── 1. Skin-type fit ──────────────────────────────────
                if let fit = scores.skinTypeFitScore {
                    ScoreGaugeCard(
                        title:    "Skin-Type Fit",
                        subtitle: "How well this formula suits your skin type",
                        icon:     "person.fill.viewfinder",
                        iconColor: AppTheme.pinkDark,
                        score:    fit,
                        maxScore: 100,
                        tintHex:  "#FDF5F8",
                        borderColor: AppTheme.pinkDark
                    )
                    .padding(.horizontal)
                } else {
                    ScoreLockedCard(
                        title:    "Skin-Type Fit",
                        icon:     "person.fill.viewfinder",
                        message:  "Set your skin type in My Profile to unlock this score.",
                        tintHex:  "#FDF5F8"
                    )
                    .padding(.horizontal)
                }

                // ── 2. Cleanness score ────────────────────────────────
                ScoreGaugeCard(
                    title:    "Cleanness",
                    subtitle: "Low synthetic load, no controversial chemicals",
                    icon:     "sparkles",
                    iconColor: Color(hex: "#7BAE8F"),
                    score:    scores.cleannessScore,
                    maxScore: 100,
                    tintHex:  "#F3FAF5",
                    borderColor: Color(hex: "#7BAE8F")
                )
                .padding(.horizontal)

                // ── 3. Fragrance load ─────────────────────────────────
                ScoreGaugeCard(
                    title:    "Fragrance-Free Rating",
                    subtitle: "Higher score = lighter fragrance load",
                    icon:     "nose.fill",
                    iconColor: Color(hex: "#9B88C8"),
                    score:    scores.fragranceLoadScore,
                    maxScore: 100,
                    tintHex:  "#F6F3FC",
                    borderColor: Color(hex: "#9B88C8")
                )
                .padding(.horizontal)

                // ── 4. Pregnancy safety ───────────────────────────────
                PregnancySafetyCard(level: scores.pregnancySafetyLevel)
                    .padding(.horizontal)

                // ── 5. Comedogenic rating ─────────────────────────────
                ComedogenicCard(rating: scores.comedogenicRating)
                    .padding(.horizontal)

                // ── 6. Environmental score ────────────────────────────
                ScoreGaugeCard(
                    title:    "Environmental Score",
                    subtitle: "No microplastics, reef-safe, low eco-impact ingredients",
                    icon:     "leaf.fill",
                    iconColor: Color(hex: "#6B9E78"),
                    score:    scores.environmentalScore,
                    maxScore: 100,
                    tintHex:  "#F1F8F3",
                    borderColor: Color(hex: "#6B9E78")
                )
                .padding(.horizontal)

                // ── 7. Efficacy score ─────────────────────────────────
                if let eff = scores.efficacyScore {
                    ScoreGaugeCard(
                        title:    "Efficacy",
                        subtitle: "Evidence-backed actives for this product type",
                        icon:     "flask.fill",
                        iconColor: Color(hex: "#7A9EBE"),
                        score:    eff,
                        maxScore: 100,
                        tintHex:  "#F0F6FC",
                        borderColor: Color(hex: "#7A9EBE")
                    )
                    .padding(.horizontal)
                } else {
                    ScoreLockedCard(
                        title:    "Efficacy",
                        icon:     "flask.fill",
                        message:  "Not enough product category data to score actives.",
                        tintHex:  "#F0F6FC"
                    )
                    .padding(.horizontal)
                }

                // ── 8. Irritancy percentile ───────────────────────────
                ScoreGaugeCard(
                    title:    "Gentleness",
                    subtitle: "How gentle this formula is compared to typical products",
                    icon:     "hand.raised.fill",
                    iconColor: Color(hex: "#D4A96A"),
                    score:    scores.irritancyPercentile,
                    maxScore: 100,
                    tintHex:  "#FBF8F0",
                    borderColor: Color(hex: "#D4A96A")
                )
                .padding(.horizontal)

                // Disclaimer
                ScoresDisclaimerNote()
                    .padding(.horizontal)

                Spacer(minLength: 40)
            }
            .padding(.top, AppTheme.spacingMd)
        }
        .background(AppTheme.beige)
    }
}

// MARK: — Summary Row (quick-glance tiles)
struct ScoreSummaryRow: View {
    let scores: ProductScores
    let profile: AllergyProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Score Overview")
                .font(AppTheme.sans(13, weight: .semibold))
                .foregroundStyle(AppTheme.textSoft)
                .textCase(.uppercase)
                .kerning(0.5)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ScoreTile(value: scores.skinTypeFitScore.map { "\($0)" } ?? "—",
                          label: "Skin Fit",
                          color: AppTheme.pinkDark)
                ScoreTile(value: "\(scores.cleannessScore)",
                          label: "Cleanness",
                          color: Color(hex: "#7BAE8F"))
                ScoreTile(value: "\(scores.fragranceLoadScore)",
                          label: "Fragrance",
                          color: Color(hex: "#9B88C8"))
                ScoreTile(value: String(format: "%.1f", scores.comedogenicRating),
                          label: "Comedogen.",
                          color: comedogenicColor(scores.comedogenicRating))
                ScoreTile(value: "\(scores.environmentalScore)",
                          label: "Eco",
                          color: Color(hex: "#6B9E78"))
                ScoreTile(value: scores.efficacyScore.map { "\($0)" } ?? "—",
                          label: "Efficacy",
                          color: Color(hex: "#7A9EBE"))
                ScoreTile(value: "\(scores.irritancyPercentile)",
                          label: "Gentleness",
                          color: Color(hex: "#D4A96A"))
                ScoreTile(value: scores.pregnancySafetyLevel.tier == 3 ? "✓" : "!",
                          label: "Pregnancy",
                          color: scores.pregnancySafetyLevel.color)
            }
        }
        .padding(14)
        .beautyCard()
    }

    private func comedogenicColor(_ rating: Double) -> Color {
        switch rating {
        case 0..<1.5: return Color(hex: "#7BAE8F")
        case 1.5..<3: return Color(hex: "#D4A96A")
        default:      return Color(hex: "#C97070")
        }
    }
}

struct ScoreTile: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(AppTheme.sans(15, weight: .bold))
                .foregroundStyle(color)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(AppTheme.sans(9, weight: .medium))
                .foregroundStyle(AppTheme.textSoft)
                .textCase(.uppercase)
                .kerning(0.3)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusSm))
    }
}

// MARK: — Score Gauge Card
struct ScoreGaugeCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let iconColor: Color
    let score: Int
    let maxScore: Int
    let tintHex: String
    let borderColor: Color

    private var fraction: Double { Double(score) / Double(maxScore) }

    private var scoreLabel: String {
        switch score {
        case 85...100: return "Excellent"
        case 70..<85:  return "Good"
        case 55..<70:  return "Fair"
        case 40..<55:  return "Not Great"
        default:       return "Poor"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(iconColor)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(AppTheme.sans(14, weight: .semibold))
                        .foregroundStyle(AppTheme.textMain)
                    Text(subtitle)
                        .font(AppTheme.sans(11))
                        .foregroundStyle(AppTheme.textSoft)
                }
                Spacer()
                // Score badge
                VStack(alignment: .trailing, spacing: 0) {
                    HStack(alignment: .lastTextBaseline, spacing: 1) {
                        Text("\(score)")
                            .font(AppTheme.sans(22, weight: .bold))
                            .foregroundStyle(iconColor)
                        Text("/\(maxScore)")
                            .font(AppTheme.sans(11))
                            .foregroundStyle(AppTheme.textSoft)
                    }
                    Text(scoreLabel)
                        .font(AppTheme.sans(10, weight: .semibold))
                        .foregroundStyle(iconColor)
                }
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(iconColor.opacity(0.12))
                        .frame(height: 8)
                    Capsule()
                        .fill(iconColor)
                        .frame(width: geo.size.width * fraction, height: 8)
                        .animation(.spring(response: 0.6, dampingFraction: 0.75), value: fraction)
                }
            }
            .frame(height: 8)
        }
        .padding(14)
        .background(Color(hex: tintHex))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusMd))
        .overlay {

            RoundedRectangle(cornerRadius: AppTheme.radiusMd)
            .stroke(borderColor.opacity(0.22), lineWidth: 1)
        }
    }
}

// MARK: — Score Locked Card (when data unavailable)
struct ScoreLockedCard: View {
    let title: String
    let icon: String
    let message: String
    let tintHex: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(AppTheme.mochaLight)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(AppTheme.sans(14, weight: .semibold))
                    .foregroundStyle(AppTheme.textMain)
                Text(message)
                    .font(AppTheme.sans(12))
                    .foregroundStyle(AppTheme.textSoft)
            }
            Spacer()
            Text("N/A")
                .font(AppTheme.sans(14, weight: .semibold))
                .foregroundStyle(AppTheme.mochaLight)
        }
        .padding(14)
        .background(Color(hex: tintHex))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusMd))
        .overlay {

            RoundedRectangle(cornerRadius: AppTheme.radiusMd)
            .stroke(AppTheme.beigeDark.opacity(0.5), lineWidth: 1)
        }
    }
}

// MARK: — Pregnancy Safety Card
struct PregnancySafetyCard: View {
    let level: PregnancySafetyTier

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(level.color)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Pregnancy Safety")
                        .font(AppTheme.sans(14, weight: .semibold))
                        .foregroundStyle(AppTheme.textMain)
                    Text("Based on common pregnancy caution lists")
                        .font(AppTheme.sans(11))
                        .foregroundStyle(AppTheme.textSoft)
                }
                Spacer()
                Image(systemName: level.icon)
                    .font(.system(size: 26))
                    .foregroundStyle(level.color)
            }

            // Tier indicator
            HStack(spacing: 6) {
                ForEach(1...3, id: \.self) { tier in
                    Capsule()
                        .fill(tier <= level.tier ? level.color : level.color.opacity(0.15))
                        .frame(maxWidth: .infinity)
                        .frame(height: 6)
                }
            }

            HStack(spacing: 6) {
                Circle().fill(level.color).frame(width: 8, height: 8)
                Text(level.label)
                    .font(AppTheme.sans(13, weight: .semibold))
                    .foregroundStyle(level.color)
            }
            Text(level.subtitle)
                .font(AppTheme.sans(12))
                .foregroundStyle(AppTheme.textSoft)

            if level != .safe {
                Text("Always consult your healthcare provider before using beauty products during pregnancy or breastfeeding.")
                    .font(AppTheme.sans(11))
                    .foregroundStyle(AppTheme.textSoft)
                    .padding(10)
                    .background(level.color.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusSm))
            }
        }
        .padding(14)
        .background(level == .safe ? Color(hex: "#F3FAF5") : (level == .caution ? Color(hex: "#FBF8F0") : Color(hex: "#FFF5F5")))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusMd))
        .overlay {

            RoundedRectangle(cornerRadius: AppTheme.radiusMd)
            .stroke(level.color.opacity(0.25), lineWidth: 1)
        }
    }
}

// MARK: — Comedogenic Rating Card
struct ComedogenicCard: View {
    let rating: Double

    private var color: Color {
        switch rating {
        case 0..<1.5: return Color(hex: "#7BAE8F")
        case 1.5..<3: return Color(hex: "#D4A96A")
        default:      return Color(hex: "#C97070")
        }
    }

    private var label: String {
        switch rating {
        case 0..<1:   return "Non-Comedogenic"
        case 1..<2:   return "Low Risk"
        case 2..<3:   return "Moderate Risk"
        case 3..<4:   return "High Risk"
        default:      return "Very High Risk"
        }
    }

    private var subtitle: String {
        switch rating {
        case 0..<1:   return "Very unlikely to clog pores"
        case 1..<2:   return "Minimal pore-clogging potential"
        case 2..<3:   return "Some pore-clogging ingredients present"
        case 3..<4:   return "Contains notable comedogenic ingredients"
        default:      return "High concentration of pore-clogging ingredients"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "bubbles.and.sparkles")
                    .font(.system(size: 16))
                    .foregroundStyle(color)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Comedogenic Rating")
                        .font(AppTheme.sans(14, weight: .semibold))
                        .foregroundStyle(AppTheme.textMain)
                    Text("Pore-clogging potential (0 = none, 5 = very high)")
                        .font(AppTheme.sans(11))
                        .foregroundStyle(AppTheme.textSoft)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    HStack(alignment: .lastTextBaseline, spacing: 1) {
                        Text(String(format: "%.1f", rating))
                            .font(AppTheme.sans(22, weight: .bold))
                            .foregroundStyle(color)
                        Text("/5")
                            .font(AppTheme.sans(11))
                            .foregroundStyle(AppTheme.textSoft)
                    }
                    Text(label)
                        .font(AppTheme.sans(10, weight: .semibold))
                        .foregroundStyle(color)
                }
            }

            // 5-dot scale
            HStack(spacing: 6) {
                ForEach(1...5, id: \.self) { pip in
                    let filled = Double(pip) <= rating
                    Circle()
                        .fill(filled ? color : color.opacity(0.15))
                        .frame(width: 14, height: 14)
                }
                Spacer()
                Text(subtitle)
                    .font(AppTheme.sans(11))
                    .foregroundStyle(AppTheme.textSoft)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(14)
        .background(rating < 1.5 ? Color(hex: "#F3FAF5") : (rating < 3 ? Color(hex: "#FBF8F0") : Color(hex: "#FFF5F5")))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusMd))
        .overlay {

            RoundedRectangle(cornerRadius: AppTheme.radiusMd)
            .stroke(color.opacity(0.25), lineWidth: 1)
        }
    }
}

// MARK: — Disclaimer Note
struct ScoresDisclaimerNote: View {
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundStyle(AppTheme.mochaLight)
                .font(.caption)
            Text("Scores are algorithmically computed from ingredient data and are intended as guidance only. They do not constitute medical advice. Individual reactions vary.")
                .font(AppTheme.sans(11))
                .foregroundStyle(AppTheme.textSoft)
        }
        .padding(12)
        .background(AppTheme.pinkLight)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusSm))
    }
}

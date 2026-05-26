import SwiftUI

// ─────────────────────────────────────────────
//  ConfidenceBadge  —  shows scan confidence %
// ─────────────────────────────────────────────

struct ConfidenceBadge: View {

    let score: Double    // 0.0 – 1.0
    var compact: Bool = false

    private var percent: Int { Int(score * 100) }

    private var badgeColor: Color {
        if score >= 0.95 { return AppTheme.success }
        if score >= 0.80 { return AppTheme.warning }
        return AppTheme.danger
    }

    var body: some View {
        if compact {
            // Small inline version
            Text("\(percent)%")
                .font(AppTheme.sans(11, weight: .bold))
                .foregroundStyle(badgeColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(badgeColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            // Full badge with label
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .stroke(AppTheme.beigeDark, lineWidth: 3)
                        .frame(width: 52, height: 52)
                    Circle()
                        .trim(from: 0, to: score)
                        .stroke(badgeColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: 52, height: 52)
                        .rotationEffect(.degrees(-90))
                    Text("\(percent)%")
                        .font(AppTheme.sans(13, weight: .bold))
                        .foregroundStyle(badgeColor)
                }
                Text("Confidence")
                    .font(AppTheme.sans(10))
                    .foregroundStyle(AppTheme.textSoft)
            }
        }
    }
}


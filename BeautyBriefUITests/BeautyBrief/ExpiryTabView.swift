import SwiftUI

// ─────────────────────────────────────────────
//  ExpiryTabView
//  Batch code decode + expiry + PAO info
// ─────────────────────────────────────────────

struct ExpiryTabView: View {

    let expiryInfo: ExpiryInfo?
    let batchResult: BatchDecodeResult?
    let category: ProductCategory

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.spacingMd) {

                // Expiry status hero card
                ExpiryHeroCard(expiryInfo: expiryInfo, batchResult: batchResult)
                    .padding(.horizontal)

                // Batch code card
                if let batch = batchResult {
                    BatchCodeCard(result: batch)
                        .padding(.horizontal)
                }

                // PAO card
                PAOCard(category: category)
                    .padding(.horizontal)

                // Shelf life guide
                ShelfLifeGuide()
                    .padding(.horizontal)

                Spacer(minLength: 40)
            }
            .padding(.top, AppTheme.spacingMd)
        }
        .background(AppTheme.beige)
    }
}

// MARK: — Expiry Hero Card
struct ExpiryHeroCard: View {
    let expiryInfo: ExpiryInfo?
    let batchResult: BatchDecodeResult?

    private var isExpired: Bool {
        expiryInfo?.isExpired ?? batchResult?.isExpired ?? false
    }
    private var isNearExpiry: Bool {
        expiryInfo?.isNearExpiry ?? batchResult?.isNearExpiry ?? false
    }
    private var expiryDate: Date? {
        expiryInfo?.expiryDate ?? batchResult?.expiryDate
    }
    private var mfgDate: Date? {
        expiryInfo?.manufacturingDate ?? batchResult?.manufacturingDate
    }

    var body: some View {
        VStack(spacing: 16) {
            // Status icon
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.12))
                    .frame(width: 80, height: 80)
                Image(systemName: statusIcon)
                    .font(.system(size: 34))
                    .foregroundStyle(statusColor)
            }

            Text(statusTitle)
                .font(AppTheme.serif(20, weight: .semibold))
                .foregroundStyle(AppTheme.textMain)

            // Dates grid
            if mfgDate != nil || expiryDate != nil {
                HStack(spacing: 0) {
                    if let mfg = mfgDate {
                        DateCell(label: "Manufactured", date: mfg)
                        Divider().frame(height: 40)
                    }
                    if let exp = expiryDate {
                        DateCell(label: isExpired ? "Expired" : "Best Before", date: exp)
                    }
                }
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusSm))
            } else {
                Text("Unable to determine expiry from batch code.")
                    .font(AppTheme.sans(13))
                    .foregroundStyle(AppTheme.textSoft)
            }

            if isNearExpiry {
                Label("Expiring within 3 months — use soon", systemImage: "clock.badge.exclamationmark")
                    .font(AppTheme.sans(12, weight: .semibold))
                    .foregroundStyle(AppTheme.warning)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .beautyCard()
    }

    private var statusColor: Color {
        if isExpired    { return AppTheme.danger }
        if isNearExpiry { return AppTheme.warning }
        return AppTheme.success
    }
    private var statusIcon: String {
        if isExpired    { return "xmark.circle.fill" }
        if isNearExpiry { return "clock.fill" }
        return "checkmark.circle.fill"
    }
    private var statusTitle: String {
        if isExpired    { return "Product Expired" }
        if isNearExpiry { return "Expiring Soon" }
        return expiryDate != nil ? "In Date" : "Expiry Unknown"
    }
}

struct DateCell: View {
    let label: String
    let date: Date
    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(AppTheme.sans(11))
                .foregroundStyle(AppTheme.textSoft)
            Text(date.formatted(date: .abbreviated, time: .omitted))
                .font(AppTheme.sans(14, weight: .semibold))
                .foregroundStyle(AppTheme.textMain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }
}

// MARK: — Batch Code Card
struct BatchCodeCard: View {
    let result: BatchDecodeResult
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Batch Code Decode", systemImage: "barcode")
                .font(AppTheme.sans(14, weight: .semibold))
                .foregroundStyle(AppTheme.mochaDark)

            switch result.status {
            case .decoded:
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(AppTheme.success)
                    Text("Fully decoded").font(AppTheme.sans(13)).foregroundStyle(AppTheme.textMain)
                }
            case .partialDecode:
                HStack {
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(AppTheme.warning)
                    Text("Partial decode — estimate only").font(AppTheme.sans(13)).foregroundStyle(AppTheme.textMain)
                }
            case .unknown:
                HStack {
                    Image(systemName: "questionmark.circle.fill").foregroundStyle(AppTheme.mochaLight)
                    Text("Could not decode").font(AppTheme.sans(13)).foregroundStyle(AppTheme.textMain)
                }
            case .unreadable:
                HStack {
                    Image(systemName: "camera.fill").foregroundStyle(AppTheme.danger)
                    Text("Batch code not readable — retake photo").font(AppTheme.sans(13)).foregroundStyle(AppTheme.textMain)
                }
            }

            if let notes = result.notes {
                Text(notes)
                    .font(AppTheme.sans(12))
                    .foregroundStyle(AppTheme.textSoft)
            }
            if let message = result.message {
                Text(message)
                    .font(AppTheme.sans(12))
                    .foregroundStyle(AppTheme.textSoft)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .beautyCard()
    }
}

// MARK: — PAO Card
struct PAOCard: View {
    let category: ProductCategory
    private var pao: (months: Int, label: String) {
        BatchCodeService.periodAfterOpening(for: category)
    }
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(AppTheme.pinkLight).frame(width: 48, height: 48)
                Text("⏰").font(.title2)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Period After Opening")
                    .font(AppTheme.sans(14, weight: .semibold))
                    .foregroundStyle(AppTheme.mochaDark)
                Text(pao.label)
                    .font(AppTheme.sans(13))
                    .foregroundStyle(AppTheme.textMain)
                Text("Category default for \(category.rawValue)")
                    .font(AppTheme.sans(11))
                    .foregroundStyle(AppTheme.textSoft)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .beautyCard()
    }
}

// MARK: — Shelf Life Guide
struct ShelfLifeGuide: View {

    private let guidelines: [(product: String, life: String, pao: String)] = [
        ("Mascara",           "~2 years",   "3 months"),
        ("Liquid Eyeliner",   "~2 years",   "3 months"),
        ("Foundation",        "~3 years",   "12 months"),
        ("Lipstick",          "~3 years",   "18 months"),
        ("Moisturiser",       "~3 years",   "12 months"),
        ("Vitamin C Serum",   "~2 years",   "6 months"),
        ("Sunscreen",         "3 years",    "12 months"),
        ("Shampoo",           "~3 years",   "18 months"),
        ("Perfume",           "3–5 years",  "36 months"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("General Shelf Life Guide", systemImage: "clock.arrow.circlepath")
                .font(AppTheme.sans(14, weight: .semibold))
                .foregroundStyle(AppTheme.mochaDark)
            Text("(Unopened · Period after opening)")
                .font(AppTheme.sans(11))
                .foregroundStyle(AppTheme.textSoft)

            ForEach(guidelines, id: \.product) { item in
                HStack {
                    Text(item.product)
                        .font(AppTheme.sans(13))
                        .foregroundStyle(AppTheme.textMain)
                    Spacer()
                    Text(item.life)
                        .font(AppTheme.sans(12))
                        .foregroundStyle(AppTheme.textSoft)
                    Text("·")
                        .foregroundStyle(AppTheme.beigeDark)
                    Text(item.pao)
                        .font(AppTheme.sans(12, weight: .medium))
                        .foregroundStyle(AppTheme.mocha)
                }
                .padding(.vertical, 4)
                if item.product != guidelines.last?.product {
                    Divider()
                }
            }
        }
        .padding(14)
        .beautyCard()
    }
}

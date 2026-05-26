import Foundation

// ─────────────────────────────────────────────
//  MissingProductReporter
//  Fired whenever a scanned product has no ingredient data.
//  1. Saves the miss to UserDefaults (local log)
//  2. POSTs a report to Formspree → email to developer
//
//  SETUP (one-time):
//  1. Go to https://formspree.io and sign up (free)
//  2. Click "New Form", set the notification email to beautybriefapp@gmail.com
//  3. Copy your Form ID (looks like "xpwzgkab") and paste it below
// ─────────────────────────────────────────────

final class MissingProductReporter {

    static let shared = MissingProductReporter()
    private init() {}

    // ── Formspree Form ID ──────────────────────────────────────────
    private let formspreeID = "mkoezgyd"
    // ──────────────────────────────────────────────────────────────

    private let logKey = "beautybrief_missing_products_log"

    // MARK: — Public entry point

    func report(product: Product) {
        let entry = MissingProductEntry(
            productName: product.name,
            brand:       product.knownBrand ?? product.brand,
            barcode:     product.id,
            category:    product.category.rawValue,
            scannedAt:   Date()
        )
        saveLocally(entry)
        sendEmail(entry)
    }

    // MARK: — Local log

    private func saveLocally(_ entry: MissingProductEntry) {
        var log = loadLog()
        // Avoid duplicate entries for the same barcode
        if !log.contains(where: { $0.barcode == entry.barcode }) {
            log.append(entry)
        } else {
            // Update scan count for existing entry
            if let idx = log.firstIndex(where: { $0.barcode == entry.barcode }) {
                log[idx].scanCount += 1
                log[idx].lastScannedAt = entry.scannedAt
            }
        }
        if let data = try? JSONEncoder().encode(log) {
            UserDefaults.standard.set(data, forKey: logKey)
        }
    }

    func loadLog() -> [MissingProductEntry] {
        guard let data = UserDefaults.standard.data(forKey: logKey),
              let log = try? JSONDecoder().decode([MissingProductEntry].self, from: data)
        else { return [] }
        return log.sorted { $0.scanCount > $1.scanCount }
    }

    func clearLog() {
        UserDefaults.standard.removeObject(forKey: logKey)
    }

    // MARK: — Formspree email (async/await, fire-and-forget via Task)

    private func sendEmail(_ entry: MissingProductEntry) {
        Task { await sendEmailAsync(entry) }
    }

    private func sendEmailAsync(_ entry: MissingProductEntry) async {
        guard formspreeID != "YOUR_FORM_ID",
              let url = URL(string: "https://formspree.io/f/\(formspreeID)")
        else {
            print("[MissingProductReporter] Formspree ID not set — skipping email.")
            return
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        let payload: [String: String] = [
            "_subject":   "BeautyBrief — Missing Ingredients: \(entry.brand) \(entry.productName)",
            "Product":    entry.productName,
            "Brand":      entry.brand,
            "Barcode":    entry.barcode,
            "Category":   entry.category,
            "Scanned":    formatter.string(from: entry.scannedAt),
            "Scan count": "\(entry.scanCount)"
        ]

        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                print("[MissingProductReporter] Email sent for \(entry.barcode)")
            }
        } catch {
            print("[MissingProductReporter] Email failed: \(error.localizedDescription)")
        }
    }
}

// MARK: — Log Entry Model

struct MissingProductEntry: Codable, Identifiable {
    var id         = UUID()
    let productName: String
    let brand:       String
    let barcode:     String
    let category:    String
    var scanCount:   Int  = 1
    var scannedAt:   Date
    var lastScannedAt: Date

    init(productName: String, brand: String, barcode: String, category: String, scannedAt: Date) {
        self.productName   = productName
        self.brand         = brand
        self.barcode       = barcode
        self.category      = category
        self.scannedAt     = scannedAt
        self.lastScannedAt = scannedAt
    }
}

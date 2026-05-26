import Foundation

// ─────────────────────────────────────────────
//  BatchCodeService
//  Decodes batch/lot codes to manufacturing
//  and expiry dates using brand-specific rules.
//  Based on Cosmetics Calculator methodology.
//  Production: integrate Cosmetics Calculator API
// ─────────────────────────────────────────────

struct BatchCodeService {

    // MARK: — Decode a batch code for a given brand
    static func decode(batchCode: String, brand: String) -> BatchDecodeResult {
        let cleaned = batchCode.uppercased().trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty else {
            return BatchDecodeResult(status: .unreadable, message: "No batch code provided.")
        }
        // Try brand-specific decoder first
        if let result = brandSpecificDecode(code: cleaned, brand: brand.lowercased()) {
            return result
        }
        // Generic decode fallback
        return genericDecode(code: cleaned)
    }

    // MARK: — PAO (Period After Opening) by category
    static func periodAfterOpening(for category: ProductCategory) -> (months: Int, label: String) {
        switch category {
        case .skincare:   return (12,  "12M — use within 12 months of opening")
        case .makeup:     return (12,  "12M — use within 12 months of opening")
        case .haircare:   return (18,  "18M — use within 18 months of opening")
        case .fragrance:  return (36,  "36M — use within 36 months of opening")
        case .bodycare:   return (24,  "24M — use within 24 months of opening")
        case .suncare:    return (12,  "12M — use within 12 months of opening")
        case .unknown:    return (12,  "12M (estimated)")
        }
    }

    // MARK: — Known PAO exceptions (overrides category default)
    static let specificPAOExceptions: [String: Int] = [
        "mascara":            3,    // 3 months
        "liquid eyeliner":    3,
        "lip gloss":          12,
        "lipstick":           18,
        "foundation":         12,
        "concealer":          12,
        "moisturiser":        12,
        "eye cream":          12,
        "sunscreen":          12,
        "vitamin c serum":    6,    // oxidises quickly
        "retinol serum":      6,
    ]
}

// MARK: — Brand-specific decoders
private extension BatchCodeService {

    /// Brand-specific decoding rules
    static func brandSpecificDecode(code: String, brand: String) -> BatchDecodeResult? {
        switch brand {
        case "cerave":
            // Format: L##X### → L = lot, digits = year+day, X = plant, digits = sequence
            // e.g. L23B041 → year 2023, plant B, sequence 041
            return decodeCeraveLot(code)
        case "neutrogena", "johnson & johnson":
            return decodeJnJFormat(code)
        case "l'oréal paris", "loreal", "l'oreal":
            return decodeLoréalFormat(code)
        case "maybelline":
            return decodeMaybellineFormat(code)
        case "cetaphil", "galderma":
            return decodeCetaphilFormat(code)
        case "nivea", "beiersdorf":
            return decodeNiveaFormat(code)
        default:
            return nil
        }
    }

    // CeraVe: L##X### — year (2-digit) + plant letter + sequence
    static func decodeCeraveLot(_ code: String) -> BatchDecodeResult? {
        let pattern = /L(\d{2})([A-Z])(\d{3})/
        guard let match = code.firstMatch(of: pattern) else { return nil }
        guard let yearOffset = Int(match.output.1) else { return nil }
        let year = 2000 + yearOffset
        guard let mfgDate = DateComponents(calendar: .current, year: year, month: 1, day: 1).date else {
            return nil
        }
        let expiry = Calendar.current.date(byAdding: .year, value: 3, to: mfgDate)
        return BatchDecodeResult(
            status: .decoded,
            manufacturingDate: mfgDate,
            expiryDate: expiry,
            notes: "CeraVe standard 3-year shelf life. Plant code: \(match.output.2)"
        )
    }

    // J&J: YYDDD format (Julian date)
    static func decodeJnJFormat(_ code: String) -> BatchDecodeResult? {
        guard code.count >= 5,
              let year = Int(code.prefix(2)),
              let dayOfYear = Int(code.dropFirst(2).prefix(3)) else { return nil }
        var comps = DateComponents()
        comps.year = 2000 + year
        comps.day  = dayOfYear
        guard let mfgDate = Calendar.current.date(from: comps) else { return nil }
        let expiry = Calendar.current.date(byAdding: .year, value: 3, to: mfgDate)
        return BatchDecodeResult(
            status: .decoded,
            manufacturingDate: mfgDate,
            expiryDate: expiry,
            notes: "Julian date format. Year \(2000 + year), day \(dayOfYear)."
        )
    }

    // L'Oréal: LOR##X### — year + plant + sequence
    static func decodeLoréalFormat(_ code: String) -> BatchDecodeResult? {
        let pattern = /[A-Z]{2,3}(\d{2})([A-Z])(\d{3})/
        guard let match = code.firstMatch(of: pattern) else { return nil }
        guard let yearOffset = Int(match.output.1) else { return nil }
        let year = 2000 + yearOffset
        guard let mfgDate = DateComponents(calendar: .current, year: year, month: 1, day: 1).date else {
            return nil
        }
        let expiry = Calendar.current.date(byAdding: .year, value: 3, to: mfgDate)
        return BatchDecodeResult(status: .decoded, manufacturingDate: mfgDate, expiryDate: expiry,
                                  notes: "L'Oréal standard format.")
    }

    // Maybelline: MBL##X### (same group as L'Oréal)
    static func decodeMaybellineFormat(_ code: String) -> BatchDecodeResult? {
        decodeLoréalFormat(code)   // same parent company format
    }

    // Cetaphil: C##G### — year + G + sequence
    static func decodeCetaphilFormat(_ code: String) -> BatchDecodeResult? {
        let pattern = /C(\d{2})[A-Z](\d{3})/
        guard let match = code.firstMatch(of: pattern) else { return nil }
        guard let yearOffset = Int(match.output.1) else { return nil }
        let year = 2000 + yearOffset
        guard let mfgDate = DateComponents(calendar: .current, year: year, month: 1, day: 1).date else {
            return nil
        }
        let expiry = Calendar.current.date(byAdding: .year, value: 3, to: mfgDate)
        return BatchDecodeResult(status: .decoded, manufacturingDate: mfgDate, expiryDate: expiry,
                                  notes: "Cetaphil standard format.")
    }

    // Nivea: NIV##X### or numeric
    static func decodeNiveaFormat(_ code: String) -> BatchDecodeResult? {
        let pattern = /[A-Z]{3}(\d{2})([A-Z])(\d{3})/
        guard let match = code.firstMatch(of: pattern) else { return nil }
        guard let yearOffset = Int(match.output.1) else { return nil }
        let year = 2000 + yearOffset
        guard let mfgDate = DateComponents(calendar: .current, year: year, month: 1, day: 1).date else {
            return nil
        }
        let expiry = Calendar.current.date(byAdding: .year, value: 3, to: mfgDate)
        return BatchDecodeResult(status: .decoded, manufacturingDate: mfgDate, expiryDate: expiry,
                                  notes: "Beiersdorf standard format.")
    }

    // Generic: try to find a 4-digit year anywhere in the code
    static func genericDecode(code: String) -> BatchDecodeResult {
        let yearPattern = /20(\d{2})/
        if let match = code.firstMatch(of: yearPattern),
           let year = Int("20\(match.output.1)"),
           year >= 2015 && year <= 2035 {
            let mfgDate = DateComponents(calendar: .current, year: year, month: 1, day: 1).date
            let expiry  = mfgDate.flatMap { Calendar.current.date(byAdding: .year, value: 3, to: $0) }
            return BatchDecodeResult(
                status: .partialDecode,
                manufacturingDate: mfgDate,
                expiryDate: expiry,
                notes: "Estimated from year found in batch code. Verify with brand directly."
            )
        }
        return BatchDecodeResult(
            status: .unknown,
            message: "Unable to decode batch code '\(code)'. Visit Cosmetics Calculator for manual lookup."
        )
    }
}

// MARK: — Result Model
struct BatchDecodeResult {
    let status: DecodeStatus
    var manufacturingDate: Date?
    var expiryDate: Date?
    var notes: String?
    var message: String?

    var isExpired: Bool {
        guard let expiry = expiryDate else { return false }
        return expiry < .now
    }
    var isNearExpiry: Bool {
        guard let expiry = expiryDate, !isExpired else { return false }
        let threeMonthsFromNow = Calendar.current.date(byAdding: .month, value: 3, to: .now) ?? .now
        return expiry < threeMonthsFromNow
    }

    enum DecodeStatus {
        case decoded        // full decode, high confidence
        case partialDecode  // year found, but estimate
        case unknown        // can't decode — manual lookup needed
        case unreadable     // no code found
    }
}

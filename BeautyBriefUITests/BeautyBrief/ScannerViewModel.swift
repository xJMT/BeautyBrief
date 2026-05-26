import SwiftUI
import AVFoundation
import Combine

// ─────────────────────────────────────────────
//  ScannerViewModel
//  Manages the full scan → confirm → analyse flow
// ─────────────────────────────────────────────

@MainActor
final class ScannerViewModel: ObservableObject {

    // MARK: — State
    @Published var scanState: ScanState = .idle
    @Published var candidates: [ScanCandidate] = []
    @Published var confirmedProduct: Product?
    @Published var analysisResult: AnalysisResult?
    @Published var batchResult: BatchDecodeResult?
    @Published var errorMessage: String?
    @Published var showManualEntry = false

    // Services
    private let productDB   = ProductDatabaseService.shared
    private let obf         = OpenBeautyFactsService.shared
    private let webSearch   = ProductWebSearchService.shared

    // Stored so we can cancel both on reset().
    private var lookupTask:     Task<Void, Never>?   // barcodeDetected / photoTaken
    private var enrichmentTask: Task<Void, Never>?   // enrichIngredients

    // MARK: — Barcode detected by camera
    func barcodeDetected(_ barcode: String) {
        guard scanState == .scanning else { return }
        scanState = .lookingUp
        lookupTask?.cancel()
        lookupTask = Task {
            do {
                if let candidate = try await productDB.lookupByBarcode(barcode) {
                    guard !Task.isCancelled else { return }
                    candidates = [candidate]
                    scanState  = .needsConfirmation
                } else {
                    guard !Task.isCancelled else { return }
                    // Barcode not in database — stay on scanning screen so user can try again
                    scanState    = .scanning
                    errorMessage = "Product not found. Try again or switch to Photo mode."
                }
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
                scanState = .scanning
            }
        }
    }

    // MARK: — Photo captured for AI identification
    func photoTaken(_ imageData: Data) {
        guard scanState == .scanning || scanState == .idle else { return }
        scanState = .analysingPhoto
        lookupTask?.cancel()
        lookupTask = Task {
            do {
                let results = try await productDB.lookupByPhoto(imageData)
                guard !Task.isCancelled else { return }
                if results.isEmpty {
                    errorMessage = "Couldn't identify this product. Try barcode or manual entry."
                    scanState = .scanning
                } else {
                    candidates = results
                    scanState  = .needsConfirmation
                }
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
                scanState = .scanning
            }
        }
    }

    // MARK: — User confirms a candidate
    func confirm(_ candidate: ScanCandidate, allergyProfile: AllergyProfile) {
        let product = candidate.product
        confirmedProduct = product

        // If we already have ingredients, go straight to results
        guard product.ingredients.isEmpty else {
            finishWithIngredients(product: product, allergyProfile: allergyProfile)
            return
        }

        // No ingredients yet — show "searching online" state and try to enrich
        scanState = .enriching(product)
        enrichmentTask = Task { await enrichIngredients(for: product, allergyProfile: allergyProfile) }
    }

    // MARK: — Online ingredient enrichment
    // Called when a product is confirmed but has no ingredient data.
    // Runs OBF barcode lookup, OBF name search, and web scraping in parallel.
    // On success: merges ingredients into confirmed product and shows results.
    // On failure: fires MissingProductReporter and shows the apology screen.
    private func enrichIngredients(for product: Product, allergyProfile: AllergyProfile) async {
        guard !Task.isCancelled else { return }

        let query = "\(product.brand) \(product.name)"

        // Fire all three sources in parallel
        async let obfBarcode  = obf.fetchProduct(barcode: product.id)
        async let obfName     = obf.searchByName(query)
        async let webResult   = webSearch.searchIngredients(
            brand: product.brand,
            productName: product.name,
            existingImageURL: product.imageURL
        )

        let (barcodeHit, nameHits, webHit) = await (obfBarcode, obfName, webResult)

        // Bail out if the user cancelled while we were waiting
        guard !Task.isCancelled else { return }

        // Priority 1: OBF barcode exact match
        if let found = barcodeHit, !found.ingredients.isEmpty {
            applyEnrichment(source: found, onto: product, allergyProfile: allergyProfile,
                            dataSource: "Open Beauty Facts")
            return
        }

        // Priority 2: OBF name search best match
        if let found = nameHits.first, !found.ingredients.isEmpty {
            applyEnrichment(source: found, onto: product, allergyProfile: allergyProfile,
                            dataSource: "Open Beauty Facts")
            return
        }

        // Priority 3: Web scrape (INCIDecoder / SkinSafe / brand site)
        if let found = webHit, !found.ingredients.isEmpty {
            applyEnrichment(source: found, onto: product, allergyProfile: allergyProfile,
                            dataSource: found.dataSource)
            return
        }

        guard !Task.isCancelled else { return }

        // All sources returned nil — check for a network problem before giving up
        let isOffline = await isNetworkUnavailable()
        guard !Task.isCancelled else { return }

        if isOffline {
            errorMessage = "No internet connection. Connect and try again."
            scanState = .scanning
        } else {
            // Genuinely not in any database — log the miss and show the apology screen
            MissingProductReporter.shared.report(product: product)
            scanState = .noIngredients(product)
        }
    }

    /// Fast HEAD request to OBF. Returns true if we appear to be offline.
    private func isNetworkUnavailable() async -> Bool {
        guard let url = URL(string: "https://world.openbeautyfacts.org") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 4
        do {
            let (_, _) = try await URLSession.shared.data(for: request)
            return false   // got a response — we're online
        } catch {
            return true    // timed out or no route — treat as offline
        }
    }

    // Merges live ingredient data onto the confirmed product shell and navigates to results.
    private func applyEnrichment(
        source: Product,
        onto shell: Product,
        allergyProfile: AllergyProfile,
        dataSource: String
    ) {
        let enriched = Product(
            id: shell.id,
            name: shell.name,
            brand: shell.brand,
            category: shell.category != .unknown ? shell.category : source.category,
            imageURL: shell.imageURL ?? source.imageURL,
            ingredients: source.ingredients,
            batchCode: shell.batchCode,
            expiryInfo: shell.expiryInfo ?? source.expiryInfo,
            dataLastVerified: .now,
            dataSource: dataSource
        )
        confirmedProduct = enriched
        finishWithIngredients(product: enriched, allergyProfile: allergyProfile)
    }

    // Runs analysis synchronously and navigates to the result screen.
    private func finishWithIngredients(product: Product, allergyProfile: AllergyProfile) {
        analysisResult = IngredientAnalysisService.analyse(product: product, profile: allergyProfile)
        if let code = product.batchCode {
            batchResult = BatchCodeService.decode(batchCode: code, brand: product.brand)
        }
        scanState = .showingResult
    }

    // MARK: — Reset for a new scan
    func reset() {
        lookupTask?.cancel()       // stop any in-flight barcode / photo lookup
        lookupTask       = nil
        enrichmentTask?.cancel()   // stop any in-flight ingredient search
        enrichmentTask   = nil
        scanState        = .idle
        candidates       = []
        confirmedProduct = nil
        analysisResult   = nil
        batchResult      = nil
        errorMessage     = nil
    }

    func startScanning() {
        errorMessage = nil
        scanState    = .scanning
    }
}

// MARK: — Scan State Machine
enum ScanState: Equatable {
    case idle
    case scanning
    case lookingUp
    case analysingPhoto
    case needsConfirmation
    case loadingDetails
    case enriching(Product)       // Found product name/brand — now searching online for ingredients
    case showingResult
    case noIngredients(Product)
    case error(String)

    var isLoading: Bool {
        switch self {
        case .lookingUp, .analysingPhoto, .loadingDetails, .enriching: return true
        default: return false
        }
    }

    var statusMessage: String {
        switch self {
        case .idle:              return "Tap Scan to start"
        case .scanning:          return "Point camera at product or barcode"
        case .lookingUp:         return "Looking up product…"
        case .analysingPhoto:    return "Analysing photo (AI)…"
        case .needsConfirmation: return "Is this the right product?"
        case .loadingDetails:    return "Loading ingredient data…"
        case .enriching:         return "Searching for ingredients online…"
        case .showingResult:     return "Scan complete"
        case .noIngredients:     return "Ingredient data unavailable"
        case .error(let msg):    return msg
        }
    }

    static func == (lhs: ScanState, rhs: ScanState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.scanning, .scanning),
             (.lookingUp, .lookingUp), (.analysingPhoto, .analysingPhoto),
             (.needsConfirmation, .needsConfirmation), (.loadingDetails, .loadingDetails),
             (.showingResult, .showingResult):
            return true
        case (.enriching(let a), .enriching(let b)):
            return a.id == b.id
        case (.noIngredients(let a), .noIngredients(let b)):
            return a.id == b.id
        case (.error(let a), .error(let b)):
            return a == b
        default:
            return false
        }
    }
}

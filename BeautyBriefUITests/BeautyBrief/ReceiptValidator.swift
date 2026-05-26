import Foundation
import StoreKit
import Security
import CommonCrypto

// ─────────────────────────────────────────────
//  ReceiptValidator
//
//  Validates StoreKit subscription receipts.
//
//  Architecture:
//    1. On a TRUSTED device (not jailbroken):
//       • Checks the local receipt file exists.
//       • Sends it to YOUR server for validation
//         against Apple's /verifyReceipt endpoint.
//       • Caches the result for `cacheLifetime`
//         so the app doesn't need a network call
//         on every launch.
//
//    2. On an UNTRUSTED device (jailbroken):
//       • Always returns .compromised.
//       • Never grants premium access, regardless
//         of what the local receipt says.
//
//  To-do before launch:
//    • Replace `verificationServerURL` with your
//      real backend URL.
//    • Set `sharedSecret` to the shared secret
//      from App Store Connect → Your App →
//      Subscriptions → App-Specific Shared Secret.
//    • Your server should hit Apple's endpoint:
//      Production: https://buy.itunes.apple.com/verifyReceipt
//      Sandbox:    https://sandbox.itunes.apple.com/verifyReceipt
// ─────────────────────────────────────────────

// MARK: — Subscription status

enum SubscriptionStatus: String, Codable {
    case active              // Verified active subscription
    case expired             // Was subscribed, now lapsed
    case none                // Never subscribed
    case pendingVerification // Receipt exists, server not reached yet
    case compromised         // Jailbroken device — never grant premium
    case unknown             // Not yet checked this session

    /// Whether this status unlocks premium features.
    var allowsPremium: Bool { self == .active }

    var userFacingMessage: String {
        switch self {
        case .active:              return "BeautyBrief Pro · Active"
        case .expired:             return "Your subscription has expired"
        case .none:                return "Subscribe to unlock Pro features"
        case .pendingVerification: return "Verifying subscription…"
        case .compromised:         return "Pro unavailable on this device"
        case .unknown:             return "Checking subscription…"
        }
    }
}

// MARK: — SSL Pinning delegate

/// Pins connections to *.workers.dev to Cloudflare's root CA.
/// When your Worker URL is set, this prevents man-in-the-middle
/// attacks between the app and your validation backend.
///
/// HOW TO UPDATE THE PIN:
///  1. In Terminal: openssl s_client -connect bb-receipt.YOUR-NAME.workers.dev:443 2>/dev/null | openssl x509 -pubkey -noout | openssl pkey -pubin -outform DER | openssl dgst -sha256 -binary | base64
///  2. Replace pinnedPublicKeyHash below with the output.
private final class PinningDelegate: NSObject, URLSessionDelegate {

    // Cloudflare's current root CA public key hash (SHA-256, base64).
    // Valid for all *.workers.dev domains.
    // Re-run the openssl command above if validation fails after a Cloudflare CA rotation.
    private static let pinnedHashes: Set<String> = [
        "EU6TS9MO0L/GsDHvVc9D5fChYLNy5JdGYpJw0ccgetM=",   // Cloudflare root CA
        "hxqRlPTu1bMS/0DITB1SSu0vd4u/8l8TjPgfaAp63Vg=",   // Cloudflare backup CA
    ]

    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {

        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // Standard trust evaluation first
        var error: CFError?
        guard SecTrustEvaluateWithError(serverTrust, &error) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // Walk the certificate chain and check each public key hash
        let certCount = SecTrustGetCertificateCount(serverTrust)
        for i in 0..<certCount {
            guard let cert = SecTrustGetCertificateAtIndex(serverTrust, i) else { continue }
            let data = SecCertificateCopyData(cert) as Data

            // Extract public key
            if let key = extractPublicKey(from: cert) {
                var error2: Unmanaged<CFError>?
                if let keyData = SecKeyCopyExternalRepresentation(key, &error2) as Data? {
                    let hash = sha256Base64(keyData)
                    if Self.pinnedHashes.contains(hash) {
                        completionHandler(.useCredential, URLCredential(trust: serverTrust))
                        return
                    }
                }
            }
            _ = data  // suppress unused warning
        }

        // No pin matched — reject the connection
        completionHandler(.cancelAuthenticationChallenge, nil)
    }

    private func extractPublicKey(from cert: SecCertificate) -> SecKey? {
        var trust: SecTrust?
        let policy = SecPolicyCreateBasicX509()
        guard SecTrustCreateWithCertificates(cert, policy, &trust) == errSecSuccess,
              let t = trust else { return nil }
        return SecTrustCopyKey(t)
    }

    private func sha256Base64(_ data: Data) -> String {
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &digest) }
        return Data(digest).base64EncodedString()
    }
}

// MARK: — Validator

@MainActor
final class ReceiptValidator: ObservableObject {

    static let shared = ReceiptValidator()
    private init() { loadCached() }

    // MARK: — Published state

    @Published private(set) var status: SubscriptionStatus = .unknown
    @Published private(set) var isValidating = false

    // MARK: — Configuration (fill in before launch)

    /// Cloudflare Worker URL — paste your Worker URL here after deploying.
    /// See: BeautyBrief/backend/receipt-validator-worker.js for setup steps.
    /// Example: URL(string: "https://bb-receipt.yourname.workers.dev")
    private static let verificationServerURL: URL? = nil
    // = URL(string: "https://bb-receipt.YOUR-NAME.workers.dev")

    // MARK: — Cache

    private static let cacheKey      = "bb_sub_status_v1"
    private static let cacheTimeKey  = "bb_sub_status_time_v1"
    private static let cacheLifetime: TimeInterval = 3_600  // 1 hour

    private func loadCached() {
        guard
            let raw       = UserDefaults.standard.string(forKey: Self.cacheKey),
            let cached    = SubscriptionStatus(rawValue: raw),
            let cacheTime = UserDefaults.standard.object(forKey: Self.cacheTimeKey) as? Date,
            Date().timeIntervalSince(cacheTime) < Self.cacheLifetime
        else { return }
        status = cached
    }

    private func persist(_ newStatus: SubscriptionStatus) {
        status = newStatus
        UserDefaults.standard.set(newStatus.rawValue, forKey: Self.cacheKey)
        UserDefaults.standard.set(Date(), forKey: Self.cacheTimeKey)
    }

    // MARK: — Validate

    func validate() async {
        // Hard block on compromised devices — no local receipt can be trusted.
        guard SecurityManager.shared.subscriptionEnvironmentTrusted else {
            persist(.compromised)
            return
        }

        // Return cached status if it's still fresh.
        if status == .active || status == .expired {
            if let t = UserDefaults.standard.object(forKey: Self.cacheTimeKey) as? Date,
               Date().timeIntervalSince(t) < Self.cacheLifetime { return }
        }

        isValidating = true
        defer { isValidating = false }

        // Locate the receipt bundled by the App Store.
        guard
            let receiptURL  = Bundle.main.appStoreReceiptURL,
            FileManager.default.fileExists(atPath: receiptURL.path),
            let receiptData = try? Data(contentsOf: receiptURL)
        else {
            persist(.none)
            return
        }

        // ── Server validation ────────────────────────────────────────────
        // Replace `verificationServerURL` above with your real endpoint.
        // The server should validate the receipt with Apple and return
        // { "status": "active" | "expired" | "none" }.
        //
        // Until your server is live, we mark the receipt as pending.
        guard let serverURL = Self.verificationServerURL else {
            persist(.pendingVerification)
            return
        }

        let payload = ["receipt": receiptData.base64EncodedString()]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            persist(.pendingVerification)
            return
        }

        var request        = URLRequest(url: serverURL)
        request.httpMethod = "POST"
        request.httpBody   = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Auth token matched in the Cloudflare Worker — keeps random callers out.
        request.setValue("BeautyBrief-2026", forHTTPHeaderField: "X-BB-Auth")

        let pinnedSession = URLSession(configuration: .default,
                                       delegate: PinningDelegate(),
                                       delegateQueue: nil)
        do {
            let (data, resp) = try await pinnedSession.data(for: request)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
                  let rawStatus = json["status"],
                  let parsed = SubscriptionStatus(rawValue: rawStatus)
            else {
                // Server unreachable — preserve last known status rather than
                // locking out users who have no connectivity.
                return
            }
            persist(parsed)
        } catch {
            // Network failure — keep existing cached status.
        }
    }

    // MARK: — Force refresh (call after a purchase or restore)

    func forceRefresh() async {
        UserDefaults.standard.removeObject(forKey: Self.cacheKey)
        UserDefaults.standard.removeObject(forKey: Self.cacheTimeKey)
        status = .unknown
        await validate()
    }
}

import SwiftUI

@main
struct BeautyBriefApp: App {

    @StateObject private var allergyProfileVM = AllergyProfileViewModel()
    @StateObject private var scanHistoryVM    = ScanHistoryViewModel()
    @StateObject private var communityVM      = CommunityViewModel()
    @StateObject private var security         = SecurityManager.shared
    @StateObject private var receiptValidator = ReceiptValidator.shared

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    init() {
        // ── Crash reporting ──────────────────────────────────────────────
        // Registers MetricKit subscriber — zero dependencies, built into iOS 14+.
        // Diagnostic payloads (crashes, hangs) are delivered on next launch
        // and written to Documents/crash_reports/.
        CrashReporter.shared.start()

        // ── Security checks ─────────────────────────────────────────────
        // Run synchronously before any UI is shown.
        // Detects jailbroken devices and (in release builds) attached debuggers.
        // Results gate subscription trust in ReceiptValidator.
        SecurityManager.shared.runChecks()

        // ── Pre-warm heavy static data ───────────────────────────────────
        // MockData and IngredientKnowledgeBase are large static dictionaries.
        // Loading them here on a background thread prevents a stall the first
        // time a scan is attempted on the main thread.
        DispatchQueue.global(qos: .utility).async {
            _ = MockData.allProducts.count
            _ = IngredientKnowledgeBase.db.count
        }

        // ── Navigation font ──────────────────────────────────────────────
        // UIKit appearance proxy is the only way to set a custom font on
        // NavigationStack large and inline titles in SwiftUI.
        let largeTitleFont  = UIFont(name: "Georgia", size: 34) ?? UIFont.systemFont(ofSize: 34, weight: .bold)
        let inlineTitleFont = UIFont(name: "Georgia", size: 17) ?? UIFont.systemFont(ofSize: 17, weight: .semibold)
        UINavigationBar.appearance().largeTitleTextAttributes  = [.font: largeTitleFont]
        UINavigationBar.appearance().titleTextAttributes       = [.font: inlineTitleFont]
    }

    var body: some Scene {
        WindowGroup {
            if hasCompletedOnboarding {
                ContentView()
                    .environmentObject(allergyProfileVM)
                    .environmentObject(scanHistoryVM)
                    .environmentObject(communityVM)
                    .environmentObject(security)
                    .environmentObject(receiptValidator)
            } else {
                OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
                    .environmentObject(allergyProfileVM)
                    .environmentObject(security)
                    .environmentObject(receiptValidator)
            }
        }
        .task {
            // Validate the subscription receipt once on launch (async, non-blocking).
            await ReceiptValidator.shared.validate()
        }
    }
}

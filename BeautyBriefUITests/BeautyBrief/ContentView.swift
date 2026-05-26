import SwiftUI

// ─────────────────────────────────────────────
//  ContentView  —  app root
//  Routes between onboarding and main app
// ─────────────────────────────────────────────

// ContentView receives ViewModels from BeautyBriefApp via the environment.
// They are created once in BeautyBriefApp — no duplicate instantiation here.
struct ContentView: View {

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @EnvironmentObject private var allergyVM: AllergyProfileViewModel
    @EnvironmentObject private var historyVM: ScanHistoryViewModel

    var body: some View {
        Group {
            if hasCompletedOnboarding {
                MainTabView()
                    .environmentObject(allergyVM)
                    .environmentObject(historyVM)
            } else {
                OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
                    .environmentObject(allergyVM)
            }
        }
    }
}

// MARK: — Main Tab View
struct MainTabView: View {
    @EnvironmentObject private var communityVM: CommunityViewModel

    var body: some View {
        TabView {
            ScannerView()
                .tabItem { Label("Scan",      systemImage: "viewfinder") }

            ScanHistoryView()
                .tabItem { Label("History",   systemImage: "clock") }

            CommunityView()
                .environmentObject(communityVM)
                .tabItem { Label("Community", systemImage: "person.2.fill") }

            AllergyProfileView()
                .tabItem { Label("Profile",   systemImage: "person.circle") }
        }
        .tint(AppTheme.mocha)
    }
}

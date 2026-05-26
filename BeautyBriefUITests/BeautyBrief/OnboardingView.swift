import SwiftUI

// ─────────────────────────────────────────────
//  OnboardingView
//  First-run setup: skin type + common allergens
// ─────────────────────────────────────────────

struct OnboardingView: View {

    @Binding var hasCompletedOnboarding: Bool
    @EnvironmentObject var allergyVM: AllergyProfileViewModel

    @State private var currentPage = 0
    private let totalPages = 4

    var body: some View {
        ZStack {
            AppTheme.beige.ignoresSafeArea()

            VStack(spacing: 0) {
                // Progress dots
                HStack(spacing: 6) {
                    ForEach(0..<totalPages, id: \.self) { i in
                        Capsule()
                            .fill(i == currentPage ? AppTheme.mocha : AppTheme.beigeDark)
                            .frame(width: i == currentPage ? 20 : 6, height: 6)
                            .animation(.spring(), value: currentPage)
                    }
                }
                .padding(.top, 60)

                TabView(selection: $currentPage) {
                    OnboardingPage0().tag(0)
                    OnboardingPage1(vm: allergyVM).tag(1)
                    OnboardingPage2(vm: allergyVM).tag(2)
                    OnboardingPage3(vm: allergyVM).tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: currentPage)

                // Navigation buttons
                HStack(spacing: 12) {
                    if currentPage > 0 {
                        Button("Back") { currentPage -= 1 }
                            .font(AppTheme.sans(15))
                            .foregroundStyle(AppTheme.mocha)
                            .frame(width: 80)
                    }
                    Spacer()
                    Button(currentPage < totalPages - 1 ? "Next" : "Get Started") {
                        if currentPage < totalPages - 1 {
                            currentPage += 1
                        } else {
                            hasCompletedOnboarding = true
                        }
                    }
                    .font(AppTheme.sans(16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 14)
                    .background(AppTheme.mocha)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusMd))
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 16)

                // Privacy footnote — visible on the final page only
                if currentPage == totalPages - 1 {
                    Link("Privacy Policy", destination: URL(string: "https://beautybrief.app/privacy-policy")!)
                        .font(AppTheme.sans(12))
                        .foregroundStyle(AppTheme.mocha)
                        .padding(.bottom, 32)
                }
            }
        }
    }
}

// MARK: — Page 0: Welcome
struct OnboardingPage0: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [AppTheme.pinkLight, AppTheme.beigeMid],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 140, height: 140)
                Image(systemName: "leaf.fill")
                    .font(.system(size: 52, weight: .light))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [AppTheme.pinkDark, AppTheme.mocha],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            VStack(spacing: 12) {
                Text("Welcome to BeautyBrief")
                    .font(AppTheme.serif(28, weight: .bold))
                    .foregroundStyle(AppTheme.mochaDark)
                    .multilineTextAlignment(.center)
                Text("Scan any beauty product to instantly know what's in it, whether it's safe for your skin, and when it expires.")
                    .font(AppTheme.sans(16))
                    .foregroundStyle(AppTheme.textSoft)
                    .multilineTextAlignment(.center)
            }
            Spacer()
            // Feature pills
            VStack(spacing: 8) {
                FeaturePill(icon: "barcode.viewfinder", text: "Barcode + photo scanning")
                FeaturePill(icon: "exclamationmark.triangle", text: "Personal allergen alerts")
                FeaturePill(icon: "flask.fill", text: "Chemical risk analysis")
                FeaturePill(icon: "calendar.badge.clock", text: "Expiry date decoder")
            }
            Spacer()
        }
        .padding(.horizontal, 28)
    }
}

struct FeaturePill: View {
    let icon: String
    let text: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(AppTheme.pinkDark)
                .frame(width: 22)
            Text(text)
                .font(AppTheme.sans(14))
                .foregroundStyle(AppTheme.textMain)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusSm))
    }
}

// MARK: — Page 1: Disclaimer
struct OnboardingPage1: View {
    @ObservedObject var vm: AllergyProfileViewModel
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "info.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(AppTheme.mochaLight)
            Text("A quick note")
                .font(AppTheme.serif(26, weight: .semibold))
                .foregroundStyle(AppTheme.mochaDark)
            Text("BeautyBrief is for informational purposes only. It is not a medical device and should not replace professional dermatological advice.")
                .font(AppTheme.sans(15))
                .foregroundStyle(AppTheme.textSoft)
                .multilineTextAlignment(.center)
            VStack(spacing: 10) {
                DisclaimerItem(icon: "exclamationmark.triangle", text: "Always do a patch test with new products")
                DisclaimerItem(icon: "person.crop.circle", text: "Consult a dermatologist for skin concerns")
                DisclaimerItem(icon: "checkmark.seal", text: "We only use verified Tier 1 data sources")
            }
            Spacer()
        }
        .padding(.horizontal, 28)
    }
}

struct DisclaimerItem: View {
    let icon: String
    let text: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(AppTheme.mocha)
            Text(text).font(AppTheme.sans(14)).foregroundStyle(AppTheme.textMain)
            Spacer()
        }
        .padding(12)
        .background(AppTheme.pinkLight)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusSm))
    }
}

// MARK: — Page 2: Skin type
struct OnboardingPage2: View {
    @ObservedObject var vm: AllergyProfileViewModel
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("What's your skin type?")
                .font(AppTheme.serif(26, weight: .semibold))
                .foregroundStyle(AppTheme.mochaDark)
                .multilineTextAlignment(.center)
            Text("(You can change this any time in My Profile)")
                .font(AppTheme.sans(13))
                .foregroundStyle(AppTheme.textSoft)

            VStack(spacing: 8) {
                ForEach(SkinType.allCases.filter { $0 != .unknown }) { type in
                    Button {
                        vm.toggleSkinType(type)
                    } label: {
                        HStack {
                            Text(type.rawValue)
                                .font(AppTheme.sans(15, weight: vm.profile.skinTypes.contains(type) ? .semibold : .regular))
                                .foregroundStyle(vm.profile.skinTypes.contains(type) ? AppTheme.pinkDark : AppTheme.mocha)
                            Spacer()
                            if vm.profile.skinTypes.contains(type) {
                                Image(systemName: "checkmark").foregroundStyle(AppTheme.pinkDark)
                            }
                        }
                        .padding(16)
                        .background(vm.profile.skinTypes.contains(type) ? AppTheme.pinkLight : AppTheme.beigeMid)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusMd))
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 28)
    }
}

// MARK: — Page 3: Common allergens
struct OnboardingPage3: View {
    @ObservedObject var vm: AllergyProfileViewModel
    private let common: [KnownAllergen] = [
        .fragrance, .parabens, .sulfates, .phenoxyethanol,
        .nuts, .nickel, .formaldehyde, .gluten
    ]
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("Any known allergens?")
                .font(AppTheme.serif(26, weight: .semibold))
                .foregroundStyle(AppTheme.mochaDark)
            Text("Tap to add. You can add more in My Profile later.")
                .font(AppTheme.sans(13))
                .foregroundStyle(AppTheme.textSoft)
                .multilineTextAlignment(.center)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130))], spacing: 8) {
                ForEach(common) { allergen in
                    let isSelected = vm.profile.allergens.contains(allergen)
                    Button { vm.toggleAllergen(allergen) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: allergen.sfSymbol)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(isSelected ? .white : AppTheme.mochaLight)
                                .frame(width: 18)
                            Text(allergen.rawValue.components(separatedBy: "(").first!.trimmingCharacters(in: .whitespaces))
                                .font(AppTheme.sans(12, weight: isSelected ? .semibold : .regular))
                                .foregroundStyle(isSelected ? .white : AppTheme.textMain)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(isSelected ? AppTheme.danger : AppTheme.beigeMid)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusSm))
                    }
                }
            }
            Text("Skip this step if you don't have known allergies.")
                .font(AppTheme.sans(12))
                .foregroundStyle(AppTheme.textSoft)
            Spacer()
        }
        .padding(.horizontal, 28)
    }
}

import SwiftUI
import PhotosUI

// ─────────────────────────────────────────────
//  AllergyProfileView  —  user allergy settings
// ─────────────────────────────────────────────

// MARK: — Profile Photo Store

/// Saves and loads the user's custom profile photo from the app's Documents directory.
/// Stored as a compressed JPEG — no UserDefaults size limits, survives app updates.
enum ProfilePhotoStore {

    private static var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("profile_photo.jpg")
    }

    static func save(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.72) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    static func load() -> UIImage? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return UIImage(data: data)
    }

    static func delete() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    static var exists: Bool { FileManager.default.fileExists(atPath: fileURL.path) }
}

// MARK: — Profile Avatar View
// Shows the user's custom photo (if set) or the chosen BeautyProduct illustration.

struct ProfileAvatarView: View {
    let size: CGFloat
    @AppStorage("profile_uses_custom_photo") private var usesCustomPhoto: Bool = false

    // Loaded once on appear, refreshed when custom photo changes.
    @State private var customImage: UIImage? = nil

    private var avatarIndex: Int {
        UserDefaults.standard.integer(forKey: "profile_avatar_index")
    }

    var body: some View {
        Group {
            if usesCustomPhoto, let img = customImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .overlay(
                        Circle().strokeBorder(
                            LinearGradient(
                                colors: [AppTheme.pinkLight, AppTheme.pinkDark.opacity(0.55)],
                                startPoint: .topLeading, endPoint: .bottomTrailing),
                            lineWidth: 2))
            } else {
                let config = beautyProductConfigs[min(avatarIndex, beautyProductConfigs.count - 1)]
                PremiumAvatarCircle(config: config, size: size)
            }
        }
        .onAppear { if usesCustomPhoto { customImage = ProfilePhotoStore.load() } }
        .onChange(of: usesCustomPhoto) { _, uses in
            customImage = uses ? ProfilePhotoStore.load() : nil
        }
    }
}

struct AllergyProfileView: View {

    @EnvironmentObject var vm: AllergyProfileViewModel
    @State private var showingClearConfirm = false
    @AppStorage("profile_welcome_dismissed") private var welcomeDismissed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppTheme.spacingMd) {

                    // Welcome guide (shown until dismissed)
                    if !welcomeDismissed {
                        ProfileWelcomeCard {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                welcomeDismissed = true
                            }
                        }
                        .padding(.horizontal)
                    }

                    // Profile summary card (includes name input)
                    ProfileSummaryCard(vm: vm)
                        .padding(.horizontal)

                    // Lifestyle preferences
                    LifestyleSection(vm: vm)
                        .padding(.horizontal)

                    // Skin Type
                    SkinTypeSection(vm: vm)
                        .padding(.horizontal)

                    // Skin Concerns
                    SkinConcernsSection(vm: vm)
                        .padding(.horizontal)

                    // Allergens by category
                    ForEach(AllergenCategory.allCases, id: \.rawValue) { category in
                        AllergenCategorySection(
                            category: category,
                            allergens: KnownAllergen.allCases.filter { $0.category == category },
                            vm: vm
                        )
                        .padding(.horizontal)
                    }

                    // Ingredient blacklist
                    BlacklistSection(vm: vm)
                        .padding(.horizontal)

                    // Health modes (pregnancy / breastfeeding)
                    HealthModeSection(vm: vm)
                        .padding(.horizontal)

                    // Clear all
                    Button(role: .destructive) {
                        showingClearConfirm = true
                    } label: {
                        Label("Clear All Profile Data", systemImage: "trash")
                            .font(AppTheme.sans(14))
                            .foregroundStyle(AppTheme.danger)
                    }
                    .padding(.top, 8)

                    // Legal footer
                    ProfileLegalFooter()
                        .padding(.bottom, 40)
                }
                .padding(.top, AppTheme.spacingMd)
            }
            .background(AppTheme.beige.ignoresSafeArea())
            .navigationTitle("Your Profile")
            .navigationBarTitleDisplayMode(.large)
            .confirmationDialog(
                "Clear all profile data?",
                isPresented: $showingClearConfirm,
                titleVisibility: .visible
            ) {
                Button("Clear All", role: .destructive) { vm.clearAll() }
            } message: {
                Text("This will remove all your allergens, sensitivities, skin preferences, and lifestyle settings.")
            }
        }
    }
}

// MARK: — Profile Welcome Card

struct ProfileWelcomeCard: View {
    let onDismiss: () -> Void

    private let steps: [(icon: String, title: String, detail: String)] = [
        ("person.crop.circle",       "Your Details",     "Add your name so BeautyBrief can personalise your experience."),
        ("exclamationmark.shield",   "Allergens",        "Toggle any ingredients you're allergic or sensitive to — we'll flag them on every scan."),
        ("drop.fill",                "Skin Type",        "Tell us your skin type so we can tailor safety warnings to you."),
        ("sparkles",                 "Skin Concerns",    "Select your concerns (acne, ageing, sensitivity…) for smarter product insights."),
        ("leaf.fill",                "Lifestyle",        "Mark vegan, fragrance-free, or pregnancy mode to filter results accordingly."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Welcome to your Profile 👋")
                        .font(AppTheme.serif(17, weight: .semibold))
                        .foregroundStyle(AppTheme.mochaDark)
                    Text("Set this up once and every scan becomes personalised to you.")
                        .font(AppTheme.sans(13))
                        .foregroundStyle(AppTheme.textSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppTheme.mochaLight)
                        .padding(8)
                        .background(AppTheme.beigeMid)
                        .clipShape(Circle())
                }
            }
            .padding(16)

            Divider()
                .background(AppTheme.beigeDark.opacity(0.5))

            // Step list
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(AppTheme.pinkLight)
                                .frame(width: 32, height: 32)
                            Image(systemName: step.icon)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(AppTheme.pinkDark)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(step.title)
                                .font(AppTheme.sans(13, weight: .semibold))
                                .foregroundStyle(AppTheme.mochaDark)
                            Text(step.detail)
                                .font(AppTheme.sans(12))
                                .foregroundStyle(AppTheme.textSoft)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                    if index < steps.count - 1 {
                        Divider()
                            .padding(.leading, 60)
                            .background(AppTheme.beigeDark.opacity(0.3))
                    }
                }
            }

            // Footer CTA
            Button(action: onDismiss) {
                Text("Got it, let's get started")
                    .font(AppTheme.sans(14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(AppTheme.mocha)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusMd))
            }
            .padding(16)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusMd))
        .overlay {

            RoundedRectangle(cornerRadius: AppTheme.radiusMd)
            .stroke(AppTheme.pinkLight, lineWidth: 1.5)
        }
        .shadow(color: AppTheme.mocha.opacity(0.07), radius: 12, x: 0, y: 4)
    }
}

// MARK: — Beauty Product Avatar System

enum BeautyProductType: Int {
    case lipstick = 0, perfume = 1, nailPolish = 2, foundation = 3, eyeShadow = 4
    case mascara = 5, blush = 6, serum = 7, faceCream = 8, lipGloss = 9
}

struct BeautyProductConfig: Identifiable {
    let id: Int
    let name: String
    let productType: BeautyProductType
    let outerGradient: LinearGradient
    let primary: Color      // main product body / liquid colour
    let secondary: Color    // case / cap / body shell
    let highlight: Color    // specular shine
    let shadow: Color       // dark shading / base
    let accent: Color       // gold trim / label detail
}

private let beautyProductConfigs: [BeautyProductConfig] = [
    // 0 — Baby Pink · Rose Hip Oil (dropper bottle)
    BeautyProductConfig(id: 0, name: "Rose Hip Oil", productType: .serum,
        outerGradient: LinearGradient(colors: [Color(red:1.00,green:0.94,blue:0.96), Color(red:0.95,green:0.71,blue:0.77), Color(red:0.84,green:0.50,blue:0.60)], startPoint: .topLeading, endPoint: .bottomTrailing),
        primary:   Color(red:0.93,green:0.62,blue:0.72),
        secondary: Color(red:0.99,green:0.93,blue:0.96),
        highlight: Color(red:1.00,green:0.98,blue:0.99),
        shadow:    Color(red:0.72,green:0.36,blue:0.47),
        accent:    Color(red:0.95,green:0.82,blue:0.78)),
    // 1 — Baby Peach · Vitamin C (vial)
    BeautyProductConfig(id: 1, name: "Vitamin C", productType: .nailPolish,
        outerGradient: LinearGradient(colors: [Color(red:1.00,green:0.96,blue:0.90), Color(red:0.97,green:0.79,blue:0.63), Color(red:0.90,green:0.58,blue:0.34)], startPoint: .topLeading, endPoint: .bottomTrailing),
        primary:   Color(red:0.95,green:0.72,blue:0.47),
        secondary: Color(red:1.00,green:0.96,blue:0.90),
        highlight: Color(red:1.00,green:0.99,blue:0.97),
        shadow:    Color(red:0.76,green:0.44,blue:0.22),
        accent:    Color(red:0.96,green:0.86,blue:0.60)),
    // 2 — Baby Yellow · Glow Mask (wide jar)
    BeautyProductConfig(id: 2, name: "Glow Mask", productType: .faceCream,
        outerGradient: LinearGradient(colors: [Color(red:0.99,green:0.99,blue:0.86), Color(red:0.96,green:0.91,blue:0.61), Color(red:0.88,green:0.74,blue:0.22)], startPoint: .topLeading, endPoint: .bottomTrailing),
        primary:   Color(red:0.99,green:0.98,blue:0.80),
        secondary: Color(red:0.99,green:0.98,blue:0.88),
        highlight: Color(red:1.00,green:1.00,blue:0.97),
        shadow:    Color(red:0.76,green:0.62,blue:0.12),
        accent:    Color(red:0.92,green:0.82,blue:0.40)),
    // 3 — Baby Mint · Matcha Gel (slim tube)
    BeautyProductConfig(id: 3, name: "Matcha Gel", productType: .lipGloss,
        outerGradient: LinearGradient(colors: [Color(red:0.86,green:0.98,blue:0.92), Color(red:0.66,green:0.88,blue:0.77), Color(red:0.32,green:0.72,blue:0.56)], startPoint: .topLeading, endPoint: .bottomTrailing),
        primary:   Color(red:0.52,green:0.84,blue:0.70),
        secondary: Color(red:0.88,green:0.98,blue:0.93),
        highlight: Color(red:0.96,green:1.00,blue:0.98),
        shadow:    Color(red:0.18,green:0.60,blue:0.44),
        accent:    Color(red:0.72,green:0.92,blue:0.80)),
    // 4 — Baby Blue · HA Serum (pump bottle)
    BeautyProductConfig(id: 4, name: "HA Serum", productType: .foundation,
        outerGradient: LinearGradient(colors: [Color(red:0.86,green:0.94,blue:1.00), Color(red:0.67,green:0.79,blue:0.94), Color(red:0.34,green:0.56,blue:0.88)], startPoint: .topLeading, endPoint: .bottomTrailing),
        primary:   Color(red:0.78,green:0.88,blue:0.97),
        secondary: Color(red:0.90,green:0.96,blue:1.00),
        highlight: Color(red:0.97,green:0.99,blue:1.00),
        shadow:    Color(red:0.24,green:0.48,blue:0.78),
        accent:    Color(red:0.72,green:0.86,blue:0.96)),
    // 5 — Baby Periwinkle · Night Cream (compact)
    BeautyProductConfig(id: 5, name: "Night Cream", productType: .blush,
        outerGradient: LinearGradient(colors: [Color(red:0.90,green:0.90,blue:1.00), Color(red:0.75,green:0.75,blue:0.91), Color(red:0.50,green:0.50,blue:0.80)], startPoint: .topLeading, endPoint: .bottomTrailing),
        primary:   Color(red:0.68,green:0.68,blue:0.90),
        secondary: Color(red:0.92,green:0.92,blue:0.98),
        highlight: Color(red:0.98,green:0.98,blue:1.00),
        shadow:    Color(red:0.34,green:0.34,blue:0.66),
        accent:    Color(red:0.84,green:0.78,blue:0.96)),
    // 6 — Baby Lilac · Lavender Mist (atomiser bottle)
    BeautyProductConfig(id: 6, name: "Lavender Mist", productType: .perfume,
        outerGradient: LinearGradient(colors: [Color(red:0.96,green:0.88,blue:1.00), Color(red:0.83,green:0.67,blue:0.93), Color(red:0.62,green:0.38,blue:0.82)], startPoint: .topLeading, endPoint: .bottomTrailing),
        primary:   Color(red:0.86,green:0.68,blue:0.96),
        secondary: Color(red:0.96,green:0.90,blue:1.00),
        highlight: Color(red:0.99,green:0.97,blue:1.00),
        shadow:    Color(red:0.48,green:0.20,blue:0.70),
        accent:    Color(red:0.88,green:0.74,blue:0.98)),
]

// MARK: — Beauty Product View (Canvas renderer)

struct BeautyProductView: View {
    let config: BeautyProductConfig

    var body: some View {
        Canvas { ctx, size in
            let s  = min(size.width, size.height)
            let ox = (size.width  - s) / 2
            let oy = (size.height - s) / 2

            func pt(_ rx: CGFloat, _ ry: CGFloat) -> CGPoint {
                CGPoint(x: ox + rx * s, y: oy + ry * s)
            }
            func box(_ rx: CGFloat, _ ry: CGFloat, _ rw: CGFloat, _ rh: CGFloat) -> CGRect {
                CGRect(x: ox + rx * s, y: oy + ry * s, width: rw * s, height: rh * s)
            }
            func rr(_ rx: CGFloat, _ ry: CGFloat, _ rw: CGFloat, _ rh: CGFloat, _ cr: CGFloat) -> Path {
                Path(roundedRect: CGRect(x: ox + rx * s, y: oy + ry * s, width: rw * s, height: rh * s),
                     cornerRadius: cr * s)
            }

            switch config.productType {

            // ─────────────────────────────────────────────────────────
            case .lipstick:
                // cast shadow
                ctx.fill(Path(ellipseIn: box(0.33, 0.83, 0.34, 0.07)),
                         with: .color(Color.black.opacity(0.22)))
                // metal case — silver cylinder
                ctx.fill(rr(0.37, 0.50, 0.26, 0.34, 0.04),
                         with: .linearGradient(
                            Gradient(colors: [config.shadow.opacity(0.85), config.secondary,
                                              config.highlight, config.secondary, config.shadow.opacity(0.70)]),
                            startPoint: pt(0.37, 0.67), endPoint: pt(0.63, 0.67)))
                // gold rim band at top of case
                ctx.fill(rr(0.37, 0.50, 0.26, 0.038, 0.02),
                         with: .color(config.accent.opacity(0.92)))
                ctx.fill(rr(0.37, 0.535, 0.26, 0.018, 0.01),
                         with: .color(config.highlight.opacity(0.55)))
                // bullet body
                var bullet = Path()
                bullet.move(to: pt(0.41, 0.50))
                bullet.addLine(to: pt(0.59, 0.50))
                bullet.addLine(to: pt(0.59, 0.24))
                bullet.addCurve(to: pt(0.41, 0.21),
                    control1: pt(0.59, 0.16), control2: pt(0.48, 0.16))
                bullet.closeSubpath()
                ctx.fill(bullet, with: .linearGradient(
                    Gradient(colors: [config.shadow.opacity(0.75), config.primary, config.highlight.opacity(0.52)]),
                    startPoint: pt(0.41, 0.35), endPoint: pt(0.59, 0.35)))
                // bullet gloss shine stripe
                var bs = Path()
                bs.move(to: pt(0.440, 0.48))
                bs.addLine(to: pt(0.475, 0.48))
                bs.addLine(to: pt(0.460, 0.23))
                bs.addLine(to: pt(0.434, 0.27))
                bs.closeSubpath()
                ctx.fill(bs, with: .color(config.highlight.opacity(0.40)))

            // ─────────────────────────────────────────────────────────
            case .perfume:
                // cast shadow
                ctx.fill(Path(ellipseIn: box(0.28, 0.82, 0.44, 0.08)),
                         with: .color(Color.black.opacity(0.20)))
                // atomizer nozzle stem (vertical gold rod)
                ctx.fill(rr(0.47, 0.08, 0.06, 0.15, 0.025),
                         with: .color(config.accent))
                // atomizer horizontal bar
                ctx.fill(rr(0.35, 0.12, 0.30, 0.055, 0.025),
                         with: .color(config.accent))
                // cap
                ctx.fill(rr(0.39, 0.21, 0.22, 0.12, 0.04),
                         with: .linearGradient(
                            Gradient(colors: [config.highlight, config.accent, config.shadow.opacity(0.65)]),
                            startPoint: pt(0.39, 0.21), endPoint: pt(0.61, 0.33)))
                // bottle body (curved glass flacon)
                var bottle = Path()
                bottle.move(to: pt(0.33, 0.33))
                bottle.addCurve(to: pt(0.33, 0.80),
                    control1: pt(0.26, 0.46), control2: pt(0.26, 0.66))
                bottle.addCurve(to: pt(0.67, 0.80),
                    control1: pt(0.33, 0.87), control2: pt(0.67, 0.87))
                bottle.addCurve(to: pt(0.67, 0.33),
                    control1: pt(0.74, 0.66), control2: pt(0.74, 0.46))
                bottle.addCurve(to: pt(0.33, 0.33),
                    control1: pt(0.67, 0.22), control2: pt(0.33, 0.22))
                bottle.closeSubpath()
                // glass body — golden liquid fill
                ctx.fill(bottle, with: .linearGradient(
                    Gradient(colors: [config.secondary.opacity(0.90), config.primary.opacity(0.78),
                                      config.secondary.opacity(0.68)]),
                    startPoint: pt(0.28, 0.50), endPoint: pt(0.72, 0.74)))
                // glass reflection stripe (left edge)
                var ref = Path()
                ref.move(to: pt(0.35, 0.35))
                ref.addLine(to: pt(0.42, 0.35))
                ref.addLine(to: pt(0.39, 0.78))
                ref.addLine(to: pt(0.34, 0.78))
                ref.closeSubpath()
                ctx.fill(ref, with: .color(config.highlight.opacity(0.42)))
                // label band
                ctx.fill(rr(0.33, 0.52, 0.34, 0.17, 0.01),
                         with: .color(config.highlight.opacity(0.22)))

            // ─────────────────────────────────────────────────────────
            case .nailPolish:
                // cast shadow
                ctx.fill(Path(ellipseIn: box(0.30, 0.82, 0.40, 0.07)),
                         with: .color(Color.black.opacity(0.22)))
                // cap / brush handle
                ctx.fill(rr(0.43, 0.07, 0.14, 0.26, 0.05),
                         with: .linearGradient(
                            Gradient(colors: [config.highlight, config.secondary, config.shadow.opacity(0.55)]),
                            startPoint: pt(0.43, 0.20), endPoint: pt(0.57, 0.20)))
                // neck
                ctx.fill(rr(0.455, 0.31, 0.09, 0.05, 0.02),
                         with: .color(config.shadow.opacity(0.48)))
                // bottle body (vase shape)
                var nb = Path()
                nb.move(to: pt(0.455, 0.35))
                nb.addCurve(to: pt(0.30, 0.57),
                    control1: pt(0.33, 0.35), control2: pt(0.28, 0.45))
                nb.addCurve(to: pt(0.33, 0.79),
                    control1: pt(0.28, 0.67), control2: pt(0.27, 0.75))
                nb.addCurve(to: pt(0.67, 0.79),
                    control1: pt(0.37, 0.87), control2: pt(0.63, 0.87))
                nb.addCurve(to: pt(0.70, 0.57),
                    control1: pt(0.73, 0.75), control2: pt(0.72, 0.67))
                nb.addCurve(to: pt(0.545, 0.35),
                    control1: pt(0.72, 0.45), control2: pt(0.67, 0.35))
                nb.closeSubpath()
                ctx.fill(nb, with: .linearGradient(
                    Gradient(colors: [config.shadow.opacity(0.78), config.primary, config.highlight.opacity(0.58)]),
                    startPoint: pt(0.28, 0.57), endPoint: pt(0.72, 0.57)))
                // glass shine stripe
                var ns = Path()
                ns.move(to: pt(0.34, 0.43))
                ns.addLine(to: pt(0.41, 0.38))
                ns.addLine(to: pt(0.40, 0.74))
                ns.addLine(to: pt(0.34, 0.74))
                ns.closeSubpath()
                ctx.fill(ns, with: .color(config.highlight.opacity(0.40)))

            // ─────────────────────────────────────────────────────────
            case .foundation:
                // cast shadow
                ctx.fill(Path(ellipseIn: box(0.33, 0.83, 0.34, 0.07)),
                         with: .color(Color.black.opacity(0.20)))
                // pump nozzle (drops down left)
                ctx.fill(rr(0.34, 0.23, 0.19, 0.055, 0.03),
                         with: .color(config.secondary.opacity(0.95)))
                // pump vertical stem
                ctx.fill(rr(0.49, 0.10, 0.07, 0.18, 0.03),
                         with: .color(config.secondary.opacity(0.95)))
                // small nozzle tip drop
                ctx.fill(Path(ellipseIn: box(0.33, 0.22, 0.06, 0.05)),
                         with: .color(config.primary.opacity(0.85)))
                // bottle body
                ctx.fill(rr(0.37, 0.27, 0.26, 0.58, 0.06),
                         with: .linearGradient(
                            Gradient(colors: [config.highlight, config.secondary, config.primary.opacity(0.88)]),
                            startPoint: pt(0.37, 0.50), endPoint: pt(0.63, 0.50)))
                // label band
                ctx.fill(rr(0.37, 0.50, 0.26, 0.10, 0.02),
                         with: .color(config.accent.opacity(0.28)))
                // vertical shine stripe
                ctx.fill(rr(0.39, 0.29, 0.055, 0.52, 0.028),
                         with: .color(config.highlight.opacity(0.36)))

            // ─────────────────────────────────────────────────────────
            case .eyeShadow:
                // cast shadow
                ctx.fill(Path(ellipseIn: box(0.16, 0.80, 0.68, 0.09)),
                         with: .color(Color.black.opacity(0.20)))
                // compact base body
                ctx.fill(rr(0.16, 0.44, 0.68, 0.38, 0.07),
                         with: .linearGradient(
                            Gradient(colors: [config.highlight, config.secondary, config.shadow.opacity(0.58)]),
                            startPoint: pt(0.18, 0.44), endPoint: pt(0.84, 0.82)))
                // compact lid
                ctx.fill(rr(0.16, 0.22, 0.68, 0.24, 0.07),
                         with: .linearGradient(
                            Gradient(colors: [config.secondary, config.secondary.opacity(0.72)]),
                            startPoint: pt(0.18, 0.22), endPoint: pt(0.84, 0.46)))
                // lid shine
                ctx.fill(rr(0.20, 0.24, 0.32, 0.07, 0.03),
                         with: .color(config.highlight.opacity(0.54)))
                // hinge line
                ctx.stroke(Path { p in
                    p.move(to: pt(0.16, 0.46))
                    p.addLine(to: pt(0.84, 0.46))
                }, with: .color(config.shadow.opacity(0.38)), lineWidth: s * 0.012)
                // 4 shadow pans (2×2 grid)
                let panColors: [Color] = [
                    config.accent.opacity(0.92),
                    config.primary.opacity(0.88),
                    config.secondary.opacity(0.82),
                    config.highlight.opacity(0.72)
                ]
                let panPositions: [(CGFloat, CGFloat)] = [
                    (0.20, 0.49), (0.50, 0.49),
                    (0.20, 0.64), (0.50, 0.64)
                ]
                for (idx, pos) in panPositions.enumerated() {
                    ctx.fill(Path(roundedRect: CGRect(
                        x: ox + pos.0 * s, y: oy + pos.1 * s,
                        width: 0.24 * s, height: 0.135 * s),
                        cornerRadius: 0.03 * s),
                             with: .color(panColors[idx]))
                    // pan specular
                    ctx.fill(Path(ellipseIn: CGRect(
                        x: ox + (pos.0 + 0.01) * s, y: oy + (pos.1 + 0.01) * s,
                        width: 0.07 * s, height: 0.034 * s)),
                             with: .color(Color.white.opacity(0.32)))
                }

            // ─────────────────────────────────────────────────────────
            case .mascara:
                // cast shadow
                ctx.fill(Path(ellipseIn: box(0.35, 0.84, 0.30, 0.07)),
                         with: .color(Color.black.opacity(0.25)))
                // wand bristles
                for i in 0..<8 {
                    let bx = 0.375 + CGFloat(i) * 0.035
                    ctx.fill(Path(roundedRect: CGRect(
                        x: ox + bx * s, y: oy + 0.09 * s,
                        width: 0.016 * s, height: 0.085 * s),
                        cornerRadius: 0.006 * s),
                             with: .color(config.primary))
                }
                // wand stem
                ctx.fill(rr(0.463, 0.07, 0.074, 0.18, 0.028),
                         with: .color(config.shadow.opacity(0.88)))
                // tube body
                ctx.fill(rr(0.37, 0.25, 0.26, 0.61, 0.06),
                         with: .linearGradient(
                            Gradient(colors: [config.secondary, config.primary, config.shadow.opacity(0.82)]),
                            startPoint: pt(0.37, 0.55), endPoint: pt(0.63, 0.55)))
                // metallic logo band near top
                ctx.fill(rr(0.37, 0.31, 0.26, 0.065, 0.02),
                         with: .color(config.accent.opacity(0.82)))
                // tube shine stripe
                ctx.fill(rr(0.39, 0.27, 0.063, 0.57, 0.03),
                         with: .color(config.highlight.opacity(0.28)))
                // cap / body split line
                ctx.stroke(Path { p in
                    p.move(to: pt(0.37, 0.44))
                    p.addLine(to: pt(0.63, 0.44))
                }, with: .color(config.shadow.opacity(0.50)), lineWidth: s * 0.015)

            // ─────────────────────────────────────────────────────────
            case .blush:
                // cast shadow
                ctx.fill(Path(ellipseIn: box(0.18, 0.80, 0.64, 0.09)),
                         with: .color(Color.black.opacity(0.20)))
                // compact base (bottom half depth)
                ctx.fill(Path(ellipseIn: box(0.19, 0.60, 0.62, 0.24)),
                         with: .linearGradient(
                            Gradient(colors: [config.secondary, config.shadow.opacity(0.68)]),
                            startPoint: pt(0.21, 0.60), endPoint: pt(0.79, 0.84)))
                // compact lid (upper disc)
                ctx.fill(Path(ellipseIn: box(0.19, 0.30, 0.62, 0.38)),
                         with: .linearGradient(
                            Gradient(colors: [config.highlight, config.secondary, config.shadow.opacity(0.48)]),
                            startPoint: pt(0.21, 0.30), endPoint: pt(0.79, 0.68)))
                // gold outer rim
                ctx.stroke(Path(ellipseIn: box(0.19, 0.30, 0.62, 0.38)),
                           with: .color(config.accent.opacity(0.82)),
                           style: StrokeStyle(lineWidth: s * 0.024))
                // pressed powder circle
                ctx.fill(Path(ellipseIn: box(0.27, 0.36, 0.46, 0.26)),
                         with: .color(config.primary.opacity(0.96)))
                // embossed centre
                ctx.fill(Path(ellipseIn: box(0.43, 0.44, 0.14, 0.10)),
                         with: .color(config.highlight.opacity(0.48)))
                // lid specular
                ctx.fill(Path(ellipseIn: box(0.23, 0.32, 0.22, 0.10)),
                         with: .color(config.highlight.opacity(0.46)))
                // hinge hint
                ctx.fill(rr(0.36, 0.66, 0.28, 0.028, 0.01),
                         with: .color(config.shadow.opacity(0.28)))

            // ─────────────────────────────────────────────────────────
            case .serum:
                // cast shadow
                ctx.fill(Path(ellipseIn: box(0.30, 0.83, 0.40, 0.07)),
                         with: .color(Color.black.opacity(0.20)))
                // rubber dropper bulb
                ctx.fill(Path(ellipseIn: box(0.37, 0.07, 0.26, 0.17)),
                         with: .linearGradient(
                            Gradient(colors: [config.highlight.opacity(0.82), config.secondary.opacity(0.88),
                                              config.shadow.opacity(0.58)]),
                            startPoint: pt(0.37, 0.07), endPoint: pt(0.63, 0.24)))
                // dropper stem
                ctx.fill(rr(0.455, 0.22, 0.09, 0.12, 0.035),
                         with: .color(config.secondary.opacity(0.88)))
                // bottle neck
                ctx.fill(rr(0.435, 0.32, 0.13, 0.07, 0.035),
                         with: .color(config.secondary.opacity(0.84)))
                // bottle body
                var sb = Path()
                sb.move(to: pt(0.435, 0.38))
                sb.addCurve(to: pt(0.29, 0.58),
                    control1: pt(0.33, 0.38), control2: pt(0.28, 0.47))
                sb.addCurve(to: pt(0.31, 0.81),
                    control1: pt(0.27, 0.68), control2: pt(0.27, 0.77))
                sb.addCurve(to: pt(0.69, 0.81),
                    control1: pt(0.35, 0.87), control2: pt(0.65, 0.87))
                sb.addCurve(to: pt(0.71, 0.58),
                    control1: pt(0.73, 0.77), control2: pt(0.73, 0.68))
                sb.addCurve(to: pt(0.565, 0.38),
                    control1: pt(0.72, 0.47), control2: pt(0.67, 0.38))
                sb.closeSubpath()
                ctx.fill(sb, with: .linearGradient(
                    Gradient(colors: [config.secondary.opacity(0.86), config.primary.opacity(0.72),
                                      config.secondary.opacity(0.64)]),
                    startPoint: pt(0.27, 0.58), endPoint: pt(0.73, 0.68)))
                // golden liquid fill (inner glow)
                var liq = Path()
                liq.move(to: pt(0.45, 0.43))
                liq.addCurve(to: pt(0.35, 0.60),
                    control1: pt(0.38, 0.43), control2: pt(0.33, 0.51))
                liq.addLine(to: pt(0.35, 0.77))
                liq.addLine(to: pt(0.65, 0.77))
                liq.addLine(to: pt(0.65, 0.60))
                liq.addCurve(to: pt(0.55, 0.43),
                    control1: pt(0.67, 0.51), control2: pt(0.62, 0.43))
                liq.closeSubpath()
                ctx.fill(liq, with: .color(config.primary.opacity(0.54)))
                // glass shine
                var ss = Path()
                ss.move(to: pt(0.33, 0.47))
                ss.addLine(to: pt(0.39, 0.43))
                ss.addLine(to: pt(0.38, 0.77))
                ss.addLine(to: pt(0.33, 0.77))
                ss.closeSubpath()
                ctx.fill(ss, with: .color(config.highlight.opacity(0.38)))
                // gold label band
                ctx.fill(rr(0.31, 0.54, 0.38, 0.10, 0.01),
                         with: .color(config.accent.opacity(0.30)))

            // ─────────────────────────────────────────────────────────
            case .faceCream:
                // cast shadow
                ctx.fill(Path(ellipseIn: box(0.15, 0.80, 0.70, 0.09)),
                         with: .color(Color.black.opacity(0.20)))
                // jar base body
                ctx.fill(Path(roundedRect: CGRect(
                    x: ox + 0.17 * s, y: oy + 0.47 * s,
                    width: 0.66 * s, height: 0.35 * s), cornerRadius: 0.06 * s),
                         with: .linearGradient(
                    Gradient(colors: [config.secondary.opacity(0.88), config.shadow.opacity(0.68)]),
                    startPoint: pt(0.19, 0.47), endPoint: pt(0.81, 0.82)))
                // jar lid
                ctx.fill(Path(roundedRect: CGRect(
                    x: ox + 0.17 * s, y: oy + 0.25 * s,
                    width: 0.66 * s, height: 0.26 * s), cornerRadius: 0.06 * s),
                         with: .linearGradient(
                    Gradient(colors: [config.highlight, config.secondary, config.primary.opacity(0.82)]),
                    startPoint: pt(0.19, 0.25), endPoint: pt(0.81, 0.51)))
                // lid gold rim
                ctx.stroke(Path(roundedRect: CGRect(
                    x: ox + 0.17 * s, y: oy + 0.25 * s,
                    width: 0.66 * s, height: 0.26 * s), cornerRadius: 0.06 * s),
                           with: .color(config.accent.opacity(0.62)),
                           style: StrokeStyle(lineWidth: s * 0.018))
                // lid specular
                ctx.fill(Path(roundedRect: CGRect(
                    x: ox + 0.21 * s, y: oy + 0.27 * s,
                    width: 0.24 * s, height: 0.08 * s), cornerRadius: 0.04 * s),
                         with: .color(config.highlight.opacity(0.54)))
                // cream visible at jar opening
                ctx.fill(Path(roundedRect: CGRect(
                    x: ox + 0.21 * s, y: oy + 0.47 * s,
                    width: 0.58 * s, height: 0.11 * s), cornerRadius: 0.02 * s),
                         with: .color(config.primary.opacity(0.92)))
                // cream swirl
                ctx.fill(Path(ellipseIn: box(0.33, 0.47, 0.18, 0.065)),
                         with: .color(config.highlight.opacity(0.48)))
                // embossed logo on lid
                ctx.fill(Path(ellipseIn: box(0.36, 0.30, 0.28, 0.13)),
                         with: .color(config.accent.opacity(0.22)))

            // ─────────────────────────────────────────────────────────
            case .lipGloss:
                // cast shadow
                ctx.fill(Path(ellipseIn: box(0.33, 0.83, 0.34, 0.07)),
                         with: .color(Color.black.opacity(0.22)))
                // tube body (slim glossy cylinder)
                ctx.fill(rr(0.37, 0.24, 0.26, 0.62, 0.07),
                         with: .linearGradient(
                            Gradient(colors: [config.shadow.opacity(0.78), config.primary.opacity(0.88),
                                              config.highlight.opacity(0.58)]),
                            startPoint: pt(0.37, 0.55), endPoint: pt(0.63, 0.55)))
                // translucent gloss colour fill
                ctx.fill(rr(0.395, 0.26, 0.195, 0.58, 0.055),
                         with: .color(config.primary.opacity(0.48)))
                // top cap
                ctx.fill(rr(0.37, 0.13, 0.26, 0.14, 0.06),
                         with: .linearGradient(
                            Gradient(colors: [config.highlight, config.secondary.opacity(0.88)]),
                            startPoint: pt(0.37, 0.13), endPoint: pt(0.63, 0.27)))
                // cap specular
                ctx.fill(Path(ellipseIn: box(0.40, 0.15, 0.11, 0.05)),
                         with: .color(config.highlight.opacity(0.56)))
                // applicator wand hint (bottom)
                ctx.fill(rr(0.455, 0.74, 0.09, 0.14, 0.03),
                         with: .color(config.accent.opacity(0.72)))
                // glass shine stripe
                ctx.fill(rr(0.393, 0.26, 0.055, 0.56, 0.027),
                         with: .color(config.highlight.opacity(0.44)))
                // bottom endcap
                ctx.fill(rr(0.37, 0.81, 0.26, 0.055, 0.03),
                         with: .color(config.secondary.opacity(0.88)))
            }
        }
    }
}

// MARK: — Premium Avatar Circle (wraps BeautyProductView)

struct PremiumAvatarCircle: View {
    let config: BeautyProductConfig
    let size: CGFloat

    var body: some View {
        ZStack {
            // Jewel gradient base
            Circle().fill(config.outerGradient)
            // Product illustration fills the circle
            BeautyProductView(config: config)
                .frame(width: size, height: size)
                .clipShape(Circle())
            // Top-left specular glass gloss
            Circle().fill(
                LinearGradient(
                    stops: [
                        .init(color: Color.white.opacity(0.38), location: 0.00),
                        .init(color: Color.white.opacity(0.10), location: 0.42),
                        .init(color: Color.white.opacity(0.00), location: 0.70),
                    ],
                    startPoint: .init(x: 0.14, y: 0.05),
                    endPoint:   .init(x: 0.72, y: 0.72)
                )
            )
            // Bottom depth vignette
            Circle().fill(
                LinearGradient(
                    colors: [Color.clear, Color.black.opacity(0.16)],
                    startPoint: .center, endPoint: .bottom
                )
            )
            // Per-colour darker border ring
            Circle()
                .strokeBorder(config.shadow.opacity(0.72), lineWidth: 2)
        }
        .frame(width: size, height: size)
    }
}

// MARK: — Profile Summary Card

struct ProfileSummaryCard: View {
    @ObservedObject var vm: AllergyProfileViewModel
    @State private var nameText: String = ""
    @FocusState private var nameFocused: Bool
    @AppStorage("profile_avatar_index") private var avatarIndex: Int = 0
    @State private var showingAvatarPicker = false

    private var currentAvatar: BeautyProductConfig {
        beautyProductConfigs[min(avatarIndex, beautyProductConfigs.count - 1)]
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {

                // ── Avatar (tap to change) ──────────────────────────
                Button { showingAvatarPicker = true } label: {
                    ZStack(alignment: .bottomTrailing) {
                        ProfileAvatarView(size: 64)
                            .shadow(color: Color.black.opacity(0.22), radius: 10, x: 0, y: 5)
                        // Edit badge
                        ZStack {
                            Circle().fill(AppTheme.mocha).frame(width: 20, height: 20)
                            Image(systemName: "pencil")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        .offset(x: 2, y: 2)
                    }
                }
                .buttonStyle(.plain)

                // ── Name + stats + health mode indicators ───────────
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        TextField("Your name (optional)", text: $nameText)
                            .font(AppTheme.serif(22, weight: .semibold))
                            .foregroundStyle(AppTheme.mochaDark)
                            .focused($nameFocused)
                            .onSubmit { vm.updateName(nameText) }
                            .onChange(of: nameFocused) { _, focused in
                                if !focused { vm.updateName(nameText) }
                            }
                        // Pencil + health mode icons stacked vertically
                        VStack(spacing: 6) {
                            Image(systemName: "pencil")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(AppTheme.mochaLight)
                                .onTapGesture { nameFocused = true }
                            Image(systemName: "cross.circle.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(vm.profile.pregnancyMode
                                    ? AppTheme.pinkDark
                                    : AppTheme.mochaLight.opacity(0.6))
                            Image(systemName: "heart.circle.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(vm.profile.breastfeedingMode
                                    ? AppTheme.pinkDark
                                    : AppTheme.mochaLight.opacity(0.6))
                        }
                        .frame(minWidth: 22)
                    }
                    if vm.hasProfile {
                        Text("\(vm.allergenCount) allergen\(vm.allergenCount == 1 ? "" : "s") · \(vm.sensitivityCount) sensitivit\(vm.sensitivityCount == 1 ? "y" : "ies")")
                            .font(AppTheme.sans(13))
                            .foregroundStyle(AppTheme.textSoft)
                        Text("Updated \(vm.profile.lastUpdated.formatted(date: .abbreviated, time: .omitted))")
                            .font(AppTheme.sans(12))
                            .foregroundStyle(AppTheme.mochaLight)
                    } else {
                        Text("Tap your name to edit")
                            .font(AppTheme.sans(12))
                            .foregroundStyle(AppTheme.mochaLight)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .pinkAccentBar()
        .beautyCard()
        .onAppear { nameText = vm.profile.name }
        .sheet(isPresented: $showingAvatarPicker) {
            AvatarPickerSheet(selectedIndex: $avatarIndex)
        }
    }
}


// MARK: — Avatar Picker Sheet

struct AvatarPickerSheet: View {
    @Binding var selectedIndex: Int
    @Environment(\.dismiss) private var dismiss
    @State private var pressedId: Int? = nil
    @State private var photoItem: PhotosPickerItem? = nil
    @State private var isProcessingPhoto = false
    @AppStorage("profile_uses_custom_photo") private var usesCustomPhoto: Bool = false

    // Local mirror of selectedIndex — updates instantly on tap so the
    // selection ring appears immediately (AppStorage/Binding writes aren't
    // guaranteed to re-render in the same pass as withAnimation).
    @State private var localSelected: Int = 0
    // Local mirror of usesCustomPhoto for the same reason.
    @State private var localUsesCustom: Bool = false

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        ZStack {
            // White → warm beige gradient background
            LinearGradient(
                colors: [
                    Color.white,
                    Color(red: 0.96, green: 0.92, blue: 0.87)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {

                // ── Handle ────────────────────────────────────────────
                Capsule()
                    .fill(Color(red: 0.82, green: 0.78, blue: 0.80).opacity(0.50))
                    .frame(width: 32, height: 3)
                    .padding(.top, 12)

                // ── Header ────────────────────────────────────────────
                VStack(spacing: 0) {
                    Text("Your Signature Look")
                        .font(AppTheme.serif(24, weight: .semibold))
                        .foregroundStyle(AppTheme.mochaDark)
                        .padding(.top, 22)

                    Rectangle()
                        .fill(AppTheme.pinkDark.opacity(0.18))
                        .frame(width: 32, height: 1)
                        .padding(.top, 14)
                }
                .padding(.bottom, 28)

                // ── Grid ──────────────────────────────────────────────
                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: columns, spacing: 24) {

                        // ── Custom photo slot ─────────────────────────
                        PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                            VStack(spacing: 8) {
                                ZStack {
                                    // Avatar circle
                                    if localUsesCustom, let img = ProfilePhotoStore.load() {
                                        Image(uiImage: img)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 70, height: 70)
                                            .clipShape(Circle())
                                    } else {
                                        Circle()
                                            .fill(Color(red: 0.96, green: 0.92, blue: 0.94))
                                            .frame(width: 70, height: 70)
                                        Image(systemName: isProcessingPhoto ? "hourglass" : "person.crop.circle.badge.plus")
                                            .font(.system(size: 22, weight: .light))
                                            .foregroundStyle(AppTheme.pinkDark.opacity(0.70))
                                    }

                                    // Always-visible border (matches PremiumAvatarCircle style)
                                    Circle()
                                        .strokeBorder(Color(red: 0.72, green: 0.36, blue: 0.47).opacity(0.72), lineWidth: 2)
                                        .frame(width: 70, height: 70)

                                    // Outer selection ring
                                    if localUsesCustom {
                                        Circle()
                                            .strokeBorder(AppTheme.pinkDark.opacity(0.65), lineWidth: 2)
                                            .frame(width: 76, height: 76)
                                    }
                                }

                                Text("My Photo")
                                    .font(AppTheme.sans(11))
                                    .foregroundStyle(localUsesCustom ? AppTheme.pinkDark : Color(red: 0.56, green: 0.50, blue: 0.53))
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                        .onChange(of: photoItem) { _, item in
                            guard let item else { return }
                            isProcessingPhoto = true
                            Task {
                                if let data = try? await item.loadTransferable(type: Data.self),
                                   let uiImage = UIImage(data: data) {
                                    ProfilePhotoStore.save(uiImage)
                                    await MainActor.run {
                                        usesCustomPhoto = true
                                        localUsesCustom = true
                                        isProcessingPhoto = false
                                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { dismiss() }
                                } else {
                                    await MainActor.run { isProcessingPhoto = false }
                                }
                            }
                        }

                        // ── Illustration slots ────────────────────────
                        ForEach(beautyProductConfigs) { option in
                            let isSelected = !localUsesCustom && localSelected == option.id
                            let isPressed  = pressedId == option.id

                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                // Update local state immediately — ring appears on this frame.
                                localSelected    = option.id
                                localUsesCustom  = false
                                // Write through to persisted storage.
                                selectedIndex    = option.id
                                usesCustomPhoto  = false
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { dismiss() }
                            } label: {
                                VStack(spacing: 8) {
                                    ZStack {
                                        PremiumAvatarCircle(config: option, size: 70)

                                        // Thin selection ring
                                        if isSelected {
                                            Circle()
                                                .strokeBorder(AppTheme.pinkDark.opacity(0.65), lineWidth: 2)
                                                .frame(width: 76, height: 76)
                                        }
                                    }

                                    Text(option.name)
                                        .font(AppTheme.sans(11))
                                        .foregroundStyle(isSelected ? AppTheme.pinkDark : Color(red: 0.56, green: 0.50, blue: 0.53))
                                        .lineLimit(1)
                                }
                            }
                            .buttonStyle(.plain)
                        .scaleEffect(isPressed ? 0.93 : 1.0)
                        .animation(.spring(response: 0.22, dampingFraction: 0.70), value: isPressed)
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { _ in
                                    withAnimation(.easeInOut(duration: 0.08)) { pressedId = option.id }
                                }
                                .onEnded { _ in
                                    withAnimation(.easeInOut(duration: 0.10)) { pressedId = nil }
                                }
                        )
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        }  // closes ZStack
        .onAppear {
            localSelected   = selectedIndex
            localUsesCustom = usesCustomPhoto
        }
        .presentationDetents([.height(510)])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(32)
    }
}

// MARK: — Health Mode Section
struct HealthModeSection: View {
    @ObservedObject var vm: AllergyProfileViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Health Modes")
                .font(AppTheme.sans(13, weight: .semibold))
                .foregroundStyle(AppTheme.textSoft)
                .textCase(.uppercase)
                .kerning(0.5)

            Text("Activates stricter ingredient screening for the selected mode.")
                .font(AppTheme.sans(12))
                .foregroundStyle(AppTheme.mochaLight)

            HealthModeRow(
                icon: "heart.text.square.fill",
                title: "Pregnancy Mode",
                subtitle: "Flags retinol, salicylic acid & other pregnancy-caution ingredients",
                isOn: vm.profile.pregnancyMode,
                tint: AppTheme.pinkDark,
                onToggle: { vm.togglePregnancyMode() }
            )

            HealthModeRow(
                icon: "drop.fill",
                title: "Breastfeeding Mode",
                subtitle: "Applies same cautions as pregnancy mode",
                isOn: vm.profile.breastfeedingMode,
                tint: AppTheme.pinkDark,
                onToggle: { vm.toggleBreastfeedingMode() }
            )
        }
        .padding(14)
        .beautyCard()
    }
}

struct HealthModeRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let isOn: Bool
    let tint: Color
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(systemName: icon, color: AppTheme.pinkDark, size: 36, iconSize: 15)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppTheme.sans(14, weight: .medium))
                    .foregroundStyle(AppTheme.textMain)
                Text(subtitle)
                    .font(AppTheme.sans(12))
                    .foregroundStyle(AppTheme.textSoft)
                    .lineLimit(2)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { isOn },
                set: { _ in onToggle() }
            ))
            .toggleStyle(SwitchToggleStyle(tint: tint))
            .labelsHidden()
        }
        .padding(.vertical, 4)
    }
}

// MARK: — Lifestyle Preferences Section
struct LifestyleSection: View {
    @ObservedObject var vm: AllergyProfileViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Lifestyle Preferences")
                .font(AppTheme.sans(13, weight: .semibold))
                .foregroundStyle(AppTheme.textSoft)
                .textCase(.uppercase)
                .kerning(0.5)

            Text("Scan results will flag ingredients that conflict with your chosen preferences.")
                .font(AppTheme.sans(12))
                .foregroundStyle(AppTheme.mochaLight)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 8) {
                ForEach(LifestylePreference.allCases) { pref in
                    let isOn = vm.profile.lifestylePreferences.contains(pref)
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) {
                            vm.toggleLifestyle(pref)
                        }
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: pref.sfSymbol)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(isOn ? AppTheme.pinkDark : AppTheme.mochaLight)
                                .frame(width: 16)
                            Text(pref.rawValue)
                                .font(AppTheme.sans(12, weight: isOn ? .semibold : .regular))
                                .foregroundStyle(isOn ? AppTheme.mochaDark : AppTheme.textMain)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            if isOn {
                                Image(systemName: "checkmark")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(AppTheme.pinkDark)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 9)
                        .background(isOn ? AppTheme.pinkLight : AppTheme.beigeMid)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusSm))
                        .overlay {

                            RoundedRectangle(cornerRadius: AppTheme.radiusSm)
                            .stroke(isOn ? AppTheme.pinkDark.opacity(0.4) : Color.clear, lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .beautyCard()
    }
}

// MARK: — Allergen Category Section
struct AllergenCategorySection: View {
    let category: AllergenCategory
    let allergens: [KnownAllergen]
    @ObservedObject var vm: AllergyProfileViewModel

    @State private var isExpanded = false

    private var activeCount: Int {
        allergens.filter { vm.status(for: $0) != .none }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Tappable header ──────────────────────────────────
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: allergens.first?.sfSymbol ?? "tag.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppTheme.mocha)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(category.rawValue)
                            .font(AppTheme.sans(14, weight: .semibold))
                            .foregroundStyle(AppTheme.mochaDark)
                        Text("\(allergens.count) ingredient\(allergens.count == 1 ? "" : "s")")
                            .font(AppTheme.sans(11))
                            .foregroundStyle(AppTheme.textSoft)
                    }

                    Spacer()

                    if activeCount > 0 {
                        Text("\(activeCount) flagged")
                            .font(AppTheme.sans(11, weight: .semibold))
                            .foregroundStyle(AppTheme.danger)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(AppTheme.danger.opacity(0.1))
                            .clipShape(Capsule())
                    }

                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.mochaLight)
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isExpanded)
                }
                .contentShape(Rectangle())
                .padding(14)
            }
            .buttonStyle(.plain)

            // ── Expandable content ───────────────────────────────
            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    Divider().padding(.horizontal, 14)

                    HStack {
                        Spacer()
                        AllergenLegend()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                    ForEach(allergens) { allergen in
                        AllergenRow(allergen: allergen, vm: vm)
                            .padding(.horizontal, 14)
                        if allergen.id != allergens.last?.id {
                            Divider()
                                .padding(.leading, 54)
                                .padding(.trailing, 14)
                        }
                    }
                }
                .padding(.bottom, 10)
                .transition(.opacity)
            }
        }
        .beautyCard()
    }
}

// MARK: — Allergen Row
struct AllergenRow: View {
    let allergen: KnownAllergen
    @ObservedObject var vm: AllergyProfileViewModel

    private var status: AllergyProfileViewModel.AllergenStatus {
        vm.status(for: allergen)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: allergen.sfSymbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppTheme.mochaLight)
                .frame(width: 20)

            Text(allergen.rawValue)
                .font(AppTheme.sans(14))
                .foregroundStyle(AppTheme.textMain)
                .lineLimit(2)

            Spacer()

            // Sensitivity toggle — inner position
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) {
                    vm.toggleSensitivity(allergen)
                }
            } label: {
                ZStack {
                    Image(systemName: "eye")
                        .foregroundStyle(AppTheme.beigeDark)
                        .opacity(status == .sensitivity ? 0 : 1)
                    Image(systemName: "eye.fill")
                        .foregroundStyle(AppTheme.warning)
                        .opacity(status == .sensitivity ? 1 : 0)
                }
                .font(.system(size: 16))
                .frame(width: 24, height: 24)
                .scaleEffect(status == .sensitivity ? 1.12 : 1.0)
            }
            .buttonStyle(.plain)

            // Allergen toggle — outer position
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) {
                    vm.toggleAllergen(allergen)
                }
            } label: {
                ZStack {
                    Image(systemName: "xmark.circle")
                        .foregroundStyle(AppTheme.beigeDark)
                        .opacity(status == .allergen ? 0 : 1)
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(AppTheme.danger)
                        .opacity(status == .allergen ? 1 : 0)
                }
                .font(.system(size: 22))
                .frame(width: 30, height: 30)
                .scaleEffect(status == .allergen ? 1.12 : 1.0)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}

// MARK: — Legend view
struct AllergenLegend: View {
    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                Image(systemName: "eye.fill").foregroundStyle(AppTheme.warning).font(.caption)
                Text("Caution").font(AppTheme.sans(11)).foregroundStyle(AppTheme.textSoft)
            }
            HStack(spacing: 4) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(AppTheme.danger).font(.caption)
                Text("Allergen").font(AppTheme.sans(11)).foregroundStyle(AppTheme.textSoft)
            }
        }
    }
}

// MARK: — Skin Type Section
struct SkinTypeSection: View {
    @ObservedObject var vm: AllergyProfileViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Skin Type")
                .font(AppTheme.sans(13, weight: .semibold))
                .foregroundStyle(AppTheme.textSoft)
                .textCase(.uppercase)
                .kerning(0.5)

            Text("Select all that apply.")
                .font(AppTheme.sans(12))
                .foregroundStyle(AppTheme.mochaLight)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 8) {
                ForEach(SkinType.allCases.filter { $0 != .unknown }) { type in
                    let isSelected = vm.profile.skinTypes.contains(type)
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) {
                            vm.toggleSkinType(type)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(type.rawValue)
                                .font(AppTheme.sans(12, weight: isSelected ? .semibold : .regular))
                                .foregroundStyle(isSelected ? AppTheme.pinkDark : AppTheme.textMain)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(AppTheme.pinkDark)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 9)
                        .background(isSelected ? AppTheme.pinkLight : AppTheme.beigeMid)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusSm))
                        .overlay {

                            RoundedRectangle(cornerRadius: AppTheme.radiusSm)
                            .stroke(isSelected ? AppTheme.pinkDark.opacity(0.4) : Color.clear, lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .beautyCard()
    }
}

// MARK: — Skin Concerns Section
struct SkinConcernsSection: View {
    @ObservedObject var vm: AllergyProfileViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Skin Concerns")
                .font(AppTheme.sans(13, weight: .semibold))
                .foregroundStyle(AppTheme.textSoft)
                .textCase(.uppercase)
                .kerning(0.5)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130))], spacing: 8) {
                ForEach(SkinConcern.allCases) { concern in
                    let isSelected = vm.profile.skinConcerns.contains(concern)
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) {
                            vm.toggleConcern(concern)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: concern.sfSymbol)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(isSelected ? AppTheme.pinkDark : AppTheme.mochaLight)
                                .frame(width: 16)
                            Text(concern.rawValue)
                                .font(AppTheme.sans(12, weight: isSelected ? .semibold : .regular))
                                .foregroundStyle(AppTheme.textMain)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(isSelected ? AppTheme.pinkLight : AppTheme.beigeMid)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusSm))
                        .overlay {

                            RoundedRectangle(cornerRadius: AppTheme.radiusSm)
                            .stroke(isSelected ? AppTheme.pinkDark.opacity(0.35) : Color.clear, lineWidth: 1)
                        }
                    }
                }
            }
        }
        .padding(14)
        .beautyCard()
    }
}

// MARK: — Ingredient Blacklist Section
struct BlacklistSection: View {
    @ObservedObject var vm: AllergyProfileViewModel
    @State private var newIngredient = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Ingredient Blacklist")
                    .font(AppTheme.sans(13, weight: .semibold))
                    .foregroundStyle(AppTheme.textSoft)
                    .textCase(.uppercase)
                    .kerning(0.5)
                Text("Any product containing these ingredients will be flagged.")
                    .font(AppTheme.sans(12))
                    .foregroundStyle(AppTheme.mochaLight)
            }

            // Add field
            HStack(spacing: 8) {
                TextField("Add ingredient (e.g. mineral oil)", text: $newIngredient)
                    .font(AppTheme.sans(13))
                    .foregroundStyle(AppTheme.textMain)
                    .focused($fieldFocused)
                    .onSubmit { addCurrent() }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(AppTheme.beigeMid)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusSm))

                Button { addCurrent() } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(newIngredient.trimmingCharacters(in: .whitespaces).isEmpty
                                         ? AppTheme.beigeDark : AppTheme.mocha)
                }
                .disabled(newIngredient.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            // Listed ingredients
            if vm.profile.blacklistedIngredients.isEmpty {
                Text("No ingredients blacklisted yet.")
                    .font(AppTheme.sans(13))
                    .foregroundStyle(AppTheme.mochaLight)
                    .padding(.top, 4)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(vm.profile.blacklistedIngredients, id: \.self) { ingredient in
                        BlacklistChip(ingredient: ingredient) {
                            vm.removeFromBlacklist(ingredient)
                        }
                    }
                }
            }
        }
        .padding(14)
        .beautyCard()
    }

    private func addCurrent() {
        vm.addToBlacklist(newIngredient)
        newIngredient = ""
        fieldFocused = false
    }
}

struct BlacklistChip: View {
    let ingredient: String
    let onRemove: () -> Void
    var body: some View {
        HStack(spacing: 5) {
            Text(ingredient)
                .font(AppTheme.sans(12))
                .foregroundStyle(AppTheme.mochaDark)
                .lineLimit(1)
            Button { onRemove() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(AppTheme.mochaLight)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(AppTheme.beigeMid)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay {

            Capsule().stroke(AppTheme.beigeDark.opacity(0.5), lineWidth: 1)
        }
    }
}

// MARK: — Flow Layout (wrapping chip grid)
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        let height = rows.map { $0.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0 }
            .reduce(0) { $0 + $1 + spacing } - spacing
        return CGSize(width: proposal.width ?? 0, height: max(height, 0))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposal: ProposedViewSize(width: bounds.width, height: nil), subviews: subviews)
        var y = bounds.minY
        for row in rows {
            let rowHeight = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            var x = bounds.minX
            for view in row {
                let size = view.sizeThatFits(.unspecified)
                view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += rowHeight + spacing
        }
    }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [[LayoutSubview]] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [[LayoutSubview]] = [[]]
        var rowWidth: CGFloat = 0
        for view in subviews {
            let w = view.sizeThatFits(.unspecified).width
            if rowWidth + w > maxWidth, !rows[rows.count - 1].isEmpty {
                rows.append([])
                rowWidth = 0
            }
            rows[rows.count - 1].append(view)
            rowWidth += w + spacing
        }
        return rows
    }
}

// MARK: — Legal Footer

struct ProfileLegalFooter: View {

    private let privacyURL = URL(string: "https://beautybrief.app/privacy-policy")!
    private let termsURL   = URL(string: "https://beautybrief.app/terms-of-service")!
    private let supportURL = URL(string: "mailto:beautybriefapp@gmail.com")!

    var body: some View {
        VStack(spacing: 6) {
            Divider()
                .padding(.bottom, 4)

            HStack(spacing: 10) {
                Link(destination: privacyURL) {
                    Text("Privacy Policy")
                        .font(AppTheme.sans(12))
                        .foregroundStyle(AppTheme.mocha)
                }
                Text("·")
                    .font(AppTheme.sans(12))
                    .foregroundStyle(AppTheme.textSoft)
                Link(destination: termsURL) {
                    Text("Terms of Service")
                        .font(AppTheme.sans(12))
                        .foregroundStyle(AppTheme.mocha)
                }
                Text("·")
                    .font(AppTheme.sans(12))
                    .foregroundStyle(AppTheme.textSoft)
                Link(destination: supportURL) {
                    Text("Contact")
                        .font(AppTheme.sans(12))
                        .foregroundStyle(AppTheme.mocha)
                }
            }

            if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
               let build   = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                Text("BeautyBrief \(version) (\(build))")
                    .font(AppTheme.sans(11))
                    .foregroundStyle(AppTheme.textSoft)
            }
        }
        .padding(.top, 16)
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    AllergyProfileView()
        .environmentObject(AllergyProfileViewModel.preview)
}

import SwiftUI
import PhotosUI

// ─────────────────────────────────────────────
//  CreatePostView  —  new community post sheet
//  Features:
//   • Post type selector
//   • Product link (from scan history or manual)
//   • Star rating (reviews only)
//   • Body text
//   • Photo picker
//   • Allergen flags (reaction alerts only)
//   • Skin types auto-filled from profile
// ─────────────────────────────────────────────

struct CreatePostView: View {

    @EnvironmentObject private var vm: CommunityViewModel
    @EnvironmentObject private var allergyVM: AllergyProfileViewModel
    @EnvironmentObject private var historyVM: ScanHistoryViewModel

    @Environment(\.dismiss) private var dismiss

    // Form state
    @State private var draft       = NewPostData()
    @State private var isSubmitting = false
    @State private var showError    = false

    // Photo picker
    @State private var pickerItem: PhotosPickerItem? = nil
    @State private var selectedImage: UIImage?       = nil

    // Product link
    @State private var showProductPicker = false
    @State private var manualProductName = ""
    @State private var manualBrand       = ""

    // Allergen flag entry
    @State private var newAllergen = ""

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.beige.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: AppTheme.spacingMd) {

                        // ── Post type ──────────────────────────────
                        postTypeSection

                        // ── Product link ───────────────────────────
                        productSection

                        // ── Star rating (reviews) ──────────────────
                        if draft.postType.allowsRating {
                            ratingSection
                        }

                        // ── Body text ──────────────────────────────
                        bodySection

                        // ── Photo ──────────────────────────────────
                        photoSection

                        // ── Allergen flags (alerts) ────────────────
                        if draft.postType.allowsAllergenFlags {
                            allergenSection
                        }

                        // ── Submit ─────────────────────────────────
                        Button {
                            Task { await submit() }
                        } label: {
                            HStack(spacing: 8) {
                                if isSubmitting {
                                    ProgressView().tint(.white).scaleEffect(0.85)
                                } else {
                                    Image(systemName: "paperplane.fill")
                                }
                                Text(isSubmitting ? "Posting…" : "Post to Community")
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(!draft.isValid || isSubmitting)
                        .opacity(draft.isValid ? 1 : 0.55)
                        .padding(.horizontal)
                        .padding(.bottom, 32)
                    }
                    .padding(.top, AppTheme.spacingMd)
                }
            }
            .navigationTitle("New Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(AppTheme.mocha)
                }
            }
            .alert("Couldn't Post", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(vm.errorMessage ?? "Please try again.")
            }
            .sheet(isPresented: $showProductPicker) {
                ProductPickerSheet(
                    history: historyVM.scans,
                    onSelect: { result in
                        draft.productName    = result.product.name
                        draft.productBrand   = result.product.brand
                        draft.productBarcode = result.product.id
                    }
                )
            }
            .onChange(of: pickerItem) { _, item in
                Task { await loadPhoto(from: item) }
            }
            .onAppear { prefillAuthor() }
        }
    }

    // MARK: — Sections

    private var postTypeSection: some View {
        CardSection(title: "Post Type", icon: "tag.fill") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(PostType.allCases) { type in
                    PostTypeButton(type: type, isSelected: draft.postType == type) {
                        draft.postType = type
                        // Clear rating / flags that don't apply
                        if !type.allowsRating    { draft.starRating    = 0 }
                        if !type.allowsAllergenFlags { draft.allergenFlags = [] }
                    }
                }
            }
        }
    }

    private var productSection: some View {
        CardSection(title: "Product", icon: "barcode.viewfinder") {
            VStack(spacing: 10) {
                // Link from scan history
                Button {
                    showProductPicker = true
                } label: {
                    HStack {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 13))
                            .foregroundStyle(AppTheme.mocha)
                        Text(draft.productName.isEmpty
                             ? "Link from Scan History"
                             : "\(draft.productBrand) \(draft.productName)".trimmingCharacters(in: .whitespaces))
                            .font(AppTheme.sans(13, weight: draft.productName.isEmpty ? .regular : .semibold))
                            .foregroundStyle(draft.productName.isEmpty ? AppTheme.textSoft : AppTheme.mocha)
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.beigeDark)
                    }
                    .padding(12)
                    .background(AppTheme.beige)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusSm))
                    .overlay {
                        RoundedRectangle(cornerRadius: AppTheme.radiusSm)
                            .stroke(AppTheme.beigeDark, lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)

                Text("— or type manually —")
                    .font(AppTheme.sans(11))
                    .foregroundStyle(AppTheme.textSoft)

                HStack(spacing: 10) {
                    TextField("Brand", text: $manualBrand)
                        .font(AppTheme.sans(13))
                        .padding(10)
                        .background(AppTheme.beige)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusSm))
                        .overlay {
                            RoundedRectangle(cornerRadius: AppTheme.radiusSm)
                                .stroke(AppTheme.beigeDark, lineWidth: 1)
                        }
                        .onChange(of: manualBrand) { _, v in draft.productBrand = v }

                    TextField("Product name", text: $manualProductName)
                        .font(AppTheme.sans(13))
                        .padding(10)
                        .background(AppTheme.beige)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusSm))
                        .overlay {
                            RoundedRectangle(cornerRadius: AppTheme.radiusSm)
                                .stroke(AppTheme.beigeDark, lineWidth: 1)
                        }
                        .onChange(of: manualProductName) { _, v in draft.productName = v }
                }
            }
        }
    }

    private var ratingSection: some View {
        CardSection(title: "Your Rating", icon: "star.fill") {
            HStack(spacing: 12) {
                ForEach(1...5, id: \.self) { star in
                    Button {
                        draft.starRating = star
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Image(systemName: star <= draft.starRating ? "star.fill" : "star")
                            .font(.system(size: 32))
                            .foregroundStyle(star <= draft.starRating ? AppTheme.warning : AppTheme.beigeDark)
                            .scaleEffect(star <= draft.starRating ? 1.1 : 1.0)
                            .animation(.spring(response: 0.2), value: draft.starRating)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                if draft.starRating > 0 {
                    Text(ratingLabel(draft.starRating))
                        .font(AppTheme.sans(12))
                        .foregroundStyle(AppTheme.textSoft)
                }
            }
        }
    }

    private var bodySection: some View {
        CardSection(title: "Your Experience", icon: "text.alignleft") {
            TextEditor(text: $draft.bodyText)
                .font(AppTheme.sans(14))
                .foregroundStyle(AppTheme.textMain)
                .frame(minHeight: 120)
                .scrollContentBackground(.hidden)
                .background(AppTheme.beige)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusSm))
                .overlay(alignment: .topLeading) {
                    if draft.bodyText.isEmpty {
                        Text(bodyPlaceholder)
                            .font(AppTheme.sans(14))
                            .foregroundStyle(AppTheme.textSoft.opacity(0.6))
                            .padding(8)
                            .allowsHitTesting(false)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: AppTheme.radiusSm)
                        .stroke(AppTheme.beigeDark, lineWidth: 1)
                }
        }
    }

    private var photoSection: some View {
        CardSection(title: "Add Photo (optional)", icon: "camera.fill") {
            VStack(spacing: 12) {
                if let img = selectedImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 160)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusSm))
                    Button(role: .destructive) {
                        selectedImage  = nil
                        draft.photoData = nil
                        pickerItem     = nil
                    } label: {
                        Label("Remove photo", systemImage: "trash")
                            .font(AppTheme.sans(13))
                            .foregroundStyle(AppTheme.danger)
                    }
                } else {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        HStack(spacing: 8) {
                            Image(systemName: "photo.badge.plus")
                                .font(.system(size: 16))
                            Text("Choose from library")
                                .font(AppTheme.sans(14))
                        }
                        .foregroundStyle(AppTheme.mocha)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(AppTheme.pinkLight)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusSm))
                    }
                }
            }
        }
    }

    private var allergenSection: some View {
        CardSection(title: "Allergen Flags", icon: "exclamationmark.triangle.fill") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Which ingredients caused the reaction?")
                    .font(AppTheme.sans(12))
                    .foregroundStyle(AppTheme.textSoft)

                // Existing flags
                if !draft.allergenFlags.isEmpty {
                    FlowLayout(spacing: 8) {
                        ForEach(draft.allergenFlags, id: \.self) { flag in
                            HStack(spacing: 4) {
                                Text(flag)
                                    .font(AppTheme.sans(12, weight: .semibold))
                                Button {
                                    draft.allergenFlags.removeAll { $0 == flag }
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 9, weight: .bold))
                                }
                            }
                            .foregroundStyle(AppTheme.danger)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(AppTheme.danger.opacity(0.08))
                            .clipShape(Capsule())
                        }
                    }
                }

                // Add new flag
                HStack(spacing: 8) {
                    TextField("e.g. Fragrance, Parabens…", text: $newAllergen)
                        .font(AppTheme.sans(13))
                        .padding(10)
                        .background(AppTheme.beige)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusSm))
                        .overlay {
                            RoundedRectangle(cornerRadius: AppTheme.radiusSm)
                                .stroke(AppTheme.beigeDark, lineWidth: 1)
                        }
                        .submitLabel(.done)
                        .onSubmit { addAllergen() }

                    Button {
                        addAllergen()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(AppTheme.danger)
                    }
                    .disabled(newAllergen.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    // MARK: — Helpers

    private func prefillAuthor() {
        let p = allergyVM.profile
        draft.authorName        = p.name.isEmpty ? "Anonymous" : p.name
        draft.authorAvatarIndex = 0   // no avatar field on AllergyProfile; default to index 0
        draft.authorSkinTypes   = p.skinTypes.map { $0.rawValue }
    }

    private func addAllergen() {
        let trimmed = newAllergen.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !draft.allergenFlags.contains(trimmed) else { return }
        draft.allergenFlags.append(trimmed)
        newAllergen = ""
    }

    private func loadPhoto(from item: PhotosPickerItem?) async {
        guard let item else { return }
        if let data = try? await item.loadTransferable(type: Data.self),
           let image = UIImage(data: data) {
            selectedImage   = image
            // Compress to ≤ 800 KB for CloudKit
            draft.photoData = image.jpegData(compressionQuality: 0.75)
        }
    }

    private func submit() async {
        isSubmitting = true
        let success  = await vm.submit(post: draft)
        isSubmitting = false
        if success {
            dismiss()
        } else {
            showError = true
        }
    }

    private var bodyPlaceholder: String {
        switch draft.postType {
        case .review:        return "Share your honest experience with this product…"
        case .reactionAlert: return "Describe the reaction you had and when it occurred…"
        case .question:      return "Ask the community about an ingredient or product…"
        case .routine:       return "Share your skincare or beauty routine step by step…"
        }
    }

    private func ratingLabel(_ r: Int) -> String {
        ["", "Poor", "Fair", "Good", "Great", "Amazing"][r]
    }
}

// MARK: — Card Section wrapper

struct CardSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.mochaLight)
                Text(title.uppercased())
                    .font(AppTheme.sans(11, weight: .semibold))
                    .foregroundStyle(AppTheme.mochaLight)
                    .tracking(0.8)
            }
            content()
        }
        .padding(14)
        .beautyCard()
        .padding(.horizontal)
    }
}

// MARK: — Post Type Button

struct PostTypeButton: View {
    let type: PostType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: type.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : type.color)
                Text(type.label)
                    .font(AppTheme.sans(12, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : AppTheme.textMain)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isSelected ? type.color : type.color.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusSm))
            .animation(.spring(response: 0.2), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

// MARK: — Product Picker Sheet

struct ProductPickerSheet: View {
    let history: [ScanResult]
    let onSelect: (ScanResult) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(history) { result in
                Button {
                    onSelect(result)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(result.product.name)
                            .font(AppTheme.sans(14, weight: .semibold))
                            .foregroundStyle(AppTheme.textMain)
                        Text(result.product.brand)
                            .font(AppTheme.sans(12))
                            .foregroundStyle(AppTheme.textSoft)
                    }
                    .padding(.vertical, 4)
                }
            }
            .listStyle(.plain)
            .navigationTitle("Link a Product")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(AppTheme.mocha)
                }
            }
        }
    }
}

// FlowLayout is defined in AllergyProfileView.swift (shared across the module).

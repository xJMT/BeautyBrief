import SwiftUI

// ─────────────────────────────────────────────
//  CommunityView  —  main community tab
//  Features:
//   • Trending products carousel
//   • Filter bar (post type + skin type)
//   • Full post feed with cards
//   • iCloud availability banner
//   • New post sheet
// ─────────────────────────────────────────────

struct CommunityView: View {

    @EnvironmentObject private var vm: CommunityViewModel
    @EnvironmentObject private var allergyVM: AllergyProfileViewModel
    @EnvironmentObject private var historyVM: ScanHistoryViewModel

    @State private var showCreatePost = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.beige.ignoresSafeArea()

                if vm.isLoading && vm.posts.isEmpty {
                    LoadingStateView(message: "Loading community…")
                } else {
                    ScrollView {
                        VStack(spacing: 0) {

                            // ── iCloud banner ────────────────────────
                            if !vm.iCloudAvailable {
                                iCloudBanner
                                    .padding(.horizontal)
                                    .padding(.top, AppTheme.spacingSm)
                            }

                            // ── Trending carousel ────────────────────
                            if !vm.trendingProducts.isEmpty {
                                trendingSection
                                    .padding(.top, AppTheme.spacingSm)
                            }

                            // ── Filter bar ───────────────────────────
                            filterBar
                                .padding(.top, AppTheme.spacingSm)

                            // ── Post feed ────────────────────────────
                            if vm.filteredPosts.isEmpty {
                                emptyFeed
                            } else {
                                LazyVStack(spacing: 14) {
                                    ForEach(vm.filteredPosts) { post in
                                        CommunityPostCard(post: post)
                                            .padding(.horizontal)
                                    }
                                }
                                .padding(.top, AppTheme.spacingSm)
                                .padding(.bottom, 32)
                            }
                        }
                    }
                    .refreshable { await vm.load() }
                }
            }
            .navigationTitle("Community")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showCreatePost = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(AppTheme.mocha)
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    if vm.hasActiveFilters {
                        Button("Clear") { vm.clearFilters() }
                            .font(AppTheme.sans(14))
                            .foregroundStyle(AppTheme.danger)
                    }
                }
            }
            .sheet(isPresented: $showCreatePost) {
                CreatePostView()
                    .environmentObject(vm)
                    .environmentObject(allergyVM)
                    .environmentObject(historyVM)
            }
            .task { if vm.posts.isEmpty { await vm.load() } }
        }
    }

    // MARK: — iCloud Banner

    private var iCloudBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "icloud.slash")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppTheme.textSoft)
            Text("Sign in to iCloud in Settings to post and see live community content.")
                .font(AppTheme.sans(12))
                .foregroundStyle(AppTheme.textSoft)
        }
        .padding(12)
        .background(AppTheme.beigeMid)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusSm))
    }

    // MARK: — Trending Section

    private var trendingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ThemedSectionHeader(title: "Trending This Week", systemImage: "flame.fill")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(Array(vm.trendingProducts.enumerated()), id: \.offset) { rank, item in
                        TrendingProductCard(
                            rank: rank + 1,
                            name: item.name,
                            brand: item.brand,
                            postCount: item.count,
                            imageURL: vm.trendingImageURLs[item.name]
                        ) {
                            // Tap to filter the feed to this product
                            vm.selectedType = nil
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 6)
            }
        }
    }

    // MARK: — Filter Bar

    private var filterBar: some View {
        VStack(spacing: 8) {
            // Post type filter
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    FilterPill(label: "All",
                               icon: "square.grid.2x2",
                               isSelected: vm.selectedType == nil) {
                        vm.selectedType = nil
                    }
                    ForEach(PostType.allCases) { type in
                        FilterPill(label: type.label,
                                   icon: type.icon,
                                   isSelected: vm.selectedType == type,
                                   color: type.color) {
                            vm.selectedType = vm.selectedType == type ? nil : type
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 2)
            }

            // Skin type filter
            if !vm.availableSkinTypes.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(vm.availableSkinTypes, id: \.self) { skin in
                            FilterPill(label: skin,
                                       icon: "drop.fill",
                                       isSelected: vm.selectedSkinType == skin,
                                       color: AppTheme.mochaLight) {
                                vm.selectedSkinType = vm.selectedSkinType == skin ? nil : skin
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 2)
                }
            }
        }
    }

    // MARK: — Empty Feed

    private var emptyFeed: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 60)
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 44, weight: .thin))
                .foregroundStyle(AppTheme.beigeDark)
            Text("No posts yet")
                .font(AppTheme.serif(18, weight: .semibold))
                .foregroundStyle(AppTheme.mochaDark)
            Text(vm.hasActiveFilters
                 ? "Try clearing the filters to see more posts."
                 : "Be the first to share your experience!")
                .font(AppTheme.sans(14))
                .foregroundStyle(AppTheme.textSoft)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer(minLength: 40)
        }
    }
}

// MARK: — Community Post Card

struct CommunityPostCard: View {

    let post: CommunityPost
    @EnvironmentObject private var vm: CommunityViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Header ──────────────────────────────────────────────
            HStack(alignment: .top, spacing: 10) {
                // Avatar
                CommunityAvatar(index: post.authorAvatarIndex, size: 38)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(post.authorName)
                            .font(AppTheme.sans(13, weight: .semibold))
                            .foregroundStyle(AppTheme.textMain)

                        // Post type badge
                        HStack(spacing: 3) {
                            Image(systemName: post.postType.icon)
                                .font(.system(size: 9, weight: .bold))
                            Text(post.postType.label)
                                .font(AppTheme.sans(10, weight: .semibold))
                        }
                        .foregroundStyle(post.postType.color)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(post.postType.color.opacity(0.10))
                        .clipShape(Capsule())
                    }

                    // Skin type tags + time
                    HStack(spacing: 4) {
                        ForEach(post.authorSkinTypes.prefix(2), id: \.self) { skin in
                            Text(skin)
                                .font(AppTheme.sans(10))
                                .foregroundStyle(AppTheme.textSoft)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(AppTheme.beigeMid)
                                .clipShape(Capsule())
                        }
                        Spacer()
                        Text(post.createdAt.relativeDescription)
                            .font(AppTheme.sans(11))
                            .foregroundStyle(AppTheme.textSoft)
                    }
                }
            }
            .padding([.horizontal, .top], 14)

            // ── Product pill ────────────────────────────────────────
            if !post.productName.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "barcode.viewfinder")
                        .font(.system(size: 10))
                        .foregroundStyle(AppTheme.mochaLight)
                    Text(post.productBrand.isEmpty
                         ? post.productName
                         : "\(post.productBrand) · \(post.productName)")
                        .font(AppTheme.sans(11, weight: .semibold))
                        .foregroundStyle(AppTheme.mocha)
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(AppTheme.pinkLight)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 14)
                .padding(.top, 10)
            }

            // ── Star rating ─────────────────────────────────────────
            if post.postType.allowsRating && post.starRating > 0 {
                StarRatingDisplay(rating: post.starRating)
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
            }

            // ── Allergen alert banner ───────────────────────────────
            if post.postType == .reactionAlert && !post.allergenFlags.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.danger)
                    Text("Contains: \(post.allergenFlags.joined(separator: ", "))")
                        .font(AppTheme.sans(12, weight: .semibold))
                        .foregroundStyle(AppTheme.danger)
                }
                .padding(10)
                .background(AppTheme.danger.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 14)
                .padding(.top, 10)
            }

            // ── Body text ───────────────────────────────────────────
            Text(post.bodyText)
                .font(AppTheme.sans(14))
                .foregroundStyle(AppTheme.textMain)
                .lineSpacing(3)
                .padding(.horizontal, 14)
                .padding(.top, 10)

            // ── Photo ───────────────────────────────────────────────
            if let url = post.photoURL {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: 200)
                            .clipped()
                    }
                }
                .padding(.top, 10)
            }

            Divider()
                .padding(.top, 12)
                .padding(.horizontal, 14)

            // ── Reaction bar ────────────────────────────────────────
            HStack(spacing: 0) {
                ForEach(ReactionType.allCases, id: \.rawValue) { reaction in
                    reactionButton(reaction, count: count(for: reaction, in: post))
                }
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
        .beautyCard()
    }

    // MARK: — Reaction button

    @ViewBuilder
    private func reactionButton(_ reaction: ReactionType, count: Int) -> some View {
        let isSelected = vm.hasReacted(to: post.id, reaction: reaction)
        Button {
            guard !vm.hasReacted(to: post.id, reaction: reaction) else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            vm.react(to: post, reaction: reaction)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: reaction.icon)
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? reaction.color : AppTheme.textSoft)
                Text("\(count)")
                    .font(AppTheme.sans(12, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? reaction.color : AppTheme.textSoft)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? reaction.color.opacity(0.10) : Color.clear)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.25), value: isSelected)
    }

    private func count(for reaction: ReactionType, in post: CommunityPost) -> Int {
        switch reaction {
        case .heart:   return post.heartCount
        case .thumb:   return post.thumbCount
        case .warning: return post.warningCount
        }
    }
}

// MARK: — Trending Product Card (gallery style)

struct TrendingProductCard: View {
    let rank: Int
    let name: String
    let brand: String
    let postCount: Int
    let imageURL: URL?
    let action: () -> Void

    // Per-rank fallback gradient colors — shown while image loads or if OBF has none.
    private var fallbackColors: [Color] {
        switch rank {
        case 1: return [AppTheme.pinkDark, AppTheme.mocha]
        case 2: return [AppTheme.mocha, AppTheme.mochaLight]
        case 3: return [AppTheme.mochaLight, AppTheme.beigeMid]
        default: return [AppTheme.beigeMid, Color(white: 0.88)]
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {

                // ── Photo / gradient panel ────────────────────────────
                ZStack(alignment: .bottom) {

                    // Fallback gradient (also visible around transparent image edges)
                    LinearGradient(
                        colors: fallbackColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    if let imageURL {
                        AsyncImage(url: imageURL) { phase in
                            if case .success(let img) = phase {
                                img
                                    .resizable()
                                    .scaledToFill()
                            }
                        }
                        .clipped()
                    }

                    // Gradient vignette so text reads cleanly over the photo
                    LinearGradient(
                        colors: [Color.clear, Color.black.opacity(0.50)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .frame(height: 148)
                .clipped()
                .overlay(alignment: .topLeading) {
                    // Rank badge
                    Text("#\(rank)")
                        .font(AppTheme.sans(11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(rank == 1 ? AppTheme.pinkDark : Color.black.opacity(0.40))
                        .clipShape(Capsule())
                        .padding(8)
                }
                .overlay(alignment: .bottomLeading) {
                    // Post-count pill over the photo bottom
                    HStack(spacing: 3) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 9, weight: .semibold))
                        Text("\(postCount) post\(postCount == 1 ? "" : "s")")
                            .font(AppTheme.sans(10, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.35))
                    .clipShape(Capsule())
                    .padding(8)
                }

                // ── Text info ──────────────────────────────────────────
                VStack(alignment: .leading, spacing: 3) {
                    if !brand.isEmpty {
                        Text(brand.uppercased())
                            .font(AppTheme.sans(9, weight: .bold))
                            .foregroundStyle(AppTheme.pinkDark)
                            .lineLimit(1)
                    }
                    Text(name)
                        .font(AppTheme.sans(12, weight: .semibold))
                        .foregroundStyle(AppTheme.textMain)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.white)
            }
            .frame(width: 152)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusSm))
            .shadow(color: AppTheme.cardShadow, radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: — Filter Pill

struct FilterPill: View {
    let label: String
    let icon: String
    let isSelected: Bool
    var color: Color = AppTheme.mocha
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(label)
                    .font(AppTheme.sans(12, weight: isSelected ? .semibold : .regular))
            }
            .foregroundStyle(isSelected ? .white : AppTheme.textSoft)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isSelected ? color : AppTheme.beigeMid)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.2), value: isSelected)
    }
}

// MARK: — Community Avatar

struct CommunityAvatar: View {
    let index: Int
    var size: CGFloat = 36

    // Palette cycles through AppTheme colours
    private let palettes: [(bg: Color, fg: Color)] = [
        (AppTheme.pinkLight, AppTheme.pinkDark),
        (AppTheme.beigeMid,  AppTheme.mocha),
        (AppTheme.mocha,     AppTheme.pinkLight),
        (AppTheme.info.opacity(0.15), AppTheme.info),
        (AppTheme.success.opacity(0.15), AppTheme.success),
        (AppTheme.warning.opacity(0.15), AppTheme.warning),
        (AppTheme.danger.opacity(0.12), AppTheme.danger),
    ]

    private let icons = [
        "person.fill", "leaf.fill", "star.fill", "heart.fill",
        "sparkles", "drop.fill", "moon.fill"
    ]

    var body: some View {
        let p = palettes[index % palettes.count]
        let i = icons[index % icons.count]
        ZStack {
            Circle()
                .fill(p.bg)
                .frame(width: size, height: size)
            Image(systemName: i)
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(p.fg)
        }
    }
}

// MARK: — Star Rating Display

struct StarRatingDisplay: View {
    let rating: Int
    var body: some View {
        HStack(spacing: 3) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: star <= rating ? "star.fill" : "star")
                    .font(.system(size: 12))
                    .foregroundStyle(star <= rating ? AppTheme.warning : AppTheme.beigeDark)
            }
        }
    }
}

// MARK: — Date helper

private extension Date {
    var relativeDescription: String {
        let seconds = Int(Date().timeIntervalSince(self))
        switch seconds {
        case ..<60:       return "just now"
        case ..<3_600:    return "\(seconds / 60)m ago"
        case ..<86_400:   return "\(seconds / 3_600)h ago"
        case ..<604_800:  return "\(seconds / 86_400)d ago"
        default:
            let f = DateFormatter()
            f.dateStyle = .medium
            return f.string(from: self)
        }
    }
}

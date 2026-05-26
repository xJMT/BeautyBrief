import SwiftUI
import Combine

// ─────────────────────────────────────────────
//  CommunityViewModel
//  Drives CommunityView. Handles loading,
//  filtering, posting, and reactions.
//  Falls back to rich mock data when iCloud
//  is unavailable so the UI always looks great.
//
//  NOTE: No CloudKit import here — CloudKit is
//  intentionally isolated to CommunityService.
//  This file only uses plain Swift/SwiftUI types.
// ─────────────────────────────────────────────

@MainActor
final class CommunityViewModel: ObservableObject {

    // MARK: — Published state

    @Published var posts: [CommunityPost] = [] {
        didSet { _recomputeTrending() }
    }
    @Published var isLoading                    = false
    @Published var errorMessage: String?        = nil
    @Published var iCloudAvailable              = false

    // Filters
    @Published var selectedType: PostType?      = nil
    @Published var selectedSkinType: String?    = nil

    // Cached: recomputed only when posts changes (not on every view access).
    @Published private(set) var trendingProducts: [(name: String, brand: String, count: Int)] = []

    // MARK: — Trending image cache
    //
    // Keyed by product name. Populated lazily when trendingProducts changes.
    // @Published so TrendingProductCard re-renders once the image URL arrives.

    @Published private(set) var trendingImageURLs: [String: URL] = [:]
    private var _imageLoadTask: Task<Void, Never>?

    // MARK: — Reaction deduplication
    //
    // Tracks which reactions this device has already cast, keyed by post ID.
    // Persisted to UserDefaults so the guard survives app restarts.
    // @Published so CommunityPostCard re-renders when a reaction is recorded.

    @Published private(set) var reactedPosts: [String: Set<ReactionType>] = [:]
    private static let reactedPostsKey = "bb_reacted_posts_v1"

    // MARK: — Private

    private let service = CommunityService.shared

    // MARK: — Init

    init() { _loadReactions() }

    // MARK: — Reaction persistence helpers

    private func _loadReactions() {
        let raw = UserDefaults.standard.dictionary(forKey: Self.reactedPostsKey) as? [String: [String]] ?? [:]
        reactedPosts = raw.mapValues { Set($0.compactMap { ReactionType(rawValue: $0) }) }
    }

    private func _saveReactions() {
        let raw = reactedPosts.mapValues { $0.map(\.rawValue) }
        UserDefaults.standard.set(raw, forKey: Self.reactedPostsKey)
    }

    /// Returns true if this device has already cast `reaction` on `postID`.
    func hasReacted(to postID: String, reaction: ReactionType) -> Bool {
        reactedPosts[postID]?.contains(reaction) ?? false
    }

    private func _recomputeTrending() {
        let recent  = posts.filter {
            $0.postType != .routine &&
            !$0.productName.isEmpty &&
            $0.createdAt > Date().addingTimeInterval(-7 * 86_400)
        }
        let grouped = Dictionary(grouping: recent, by: { $0.productName })
        trendingProducts = grouped
            .map { name, items in
                (name: name,
                 brand: items.first?.productBrand ?? "",
                 count: items.count)
            }
            .sorted { $0.count > $1.count }
            .prefix(8)
            .map { $0 }

        // Kick off image loading for the new list, cancelling any in-flight fetch.
        _imageLoadTask?.cancel()
        _imageLoadTask = Task { await _loadTrendingImages() }
    }

    /// Concurrently fetches one OBF image per trending product.
    /// Results are cached — already-fetched names are skipped on re-runs.
    private func _loadTrendingImages() async {
        let obf = OpenBeautyFactsService.shared
        await withTaskGroup(of: (String, URL?).self) { group in
            for item in trendingProducts {
                guard !Task.isCancelled else { break }
                if trendingImageURLs[item.name] != nil { continue }   // already cached
                let name = item.name
                group.addTask {
                    let results = await obf.searchByName(name)
                    let urlStr  = results.first?.imageURL
                    return (name, urlStr.flatMap { URL(string: $0) })
                }
            }
            for await (name, url) in group {
                guard !Task.isCancelled else { break }
                if let url { trendingImageURLs[name] = url }
            }
        }
    }

    // MARK: — Derived

    var filteredPosts: [CommunityPost] {
        posts.filter { post in
            let typeMatch = selectedType == nil || post.postType == selectedType
            let skinMatch: Bool = {
                guard let st = selectedSkinType, !st.isEmpty else { return true }
                return post.authorSkinTypes.contains(st)
            }()
            return typeMatch && skinMatch
        }
    }

    /// All unique skin types present in the loaded posts (for the filter pill).
    var availableSkinTypes: [String] {
        Array(Set(posts.flatMap { $0.authorSkinTypes })).sorted()
    }

    // MARK: — Load

    func load() async {
        isLoading    = true
        errorMessage = nil

        // Uses Bool wrapper — no CKAccountStatus in this file.
        iCloudAvailable = await service.isCloudAvailable()

        if iCloudAvailable {
            do {
                posts = try await service.fetchPosts(limit: 100)
                // Always seed mock posts when CloudKit returns nothing
                // (first-launch, empty container) so the feed looks rich.
                if posts.isEmpty { posts = CommunityPost.mockPosts }
            } catch {
                posts        = CommunityPost.mockPosts
                errorMessage = "Couldn't reach the community right now. Showing sample posts."
            }
        } else {
            posts        = CommunityPost.mockPosts
            errorMessage = "Sign in to iCloud in Settings to see and post real community content."
        }

        isLoading = false
    }

    // MARK: — Submit

    func submit(post data: NewPostData) async -> Bool {
        guard iCloudAvailable else {
            errorMessage = "Sign in to iCloud to post."
            return false
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let saved = try await service.save(post: data)
            posts.insert(saved, at: 0)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: — React

    /// Optimistic local update + background CloudKit sync.
    /// No-ops if this device has already cast the same reaction on this post.
    /// post.id is a plain String (CloudKit recordName) — no CloudKit import needed here.
    func react(to post: CommunityPost, reaction: ReactionType) {
        guard !hasReacted(to: post.id, reaction: reaction) else { return }
        guard let idx = posts.firstIndex(where: { $0.id == post.id }) else { return }

        // Record locally before the optimistic UI update.
        reactedPosts[post.id, default: []].insert(reaction)
        _saveReactions()

        switch reaction {
        case .heart:   posts[idx].heartCount   += 1
        case .thumb:   posts[idx].thumbCount   += 1
        case .warning: posts[idx].warningCount += 1
        }
        guard iCloudAvailable else { return }
        Task { try? await service.react(to: post.id, reaction: reaction) }
    }

    // MARK: — Helpers

    func clearFilters() {
        selectedType     = nil
        selectedSkinType = nil
    }

    var hasActiveFilters: Bool {
        selectedType != nil || selectedSkinType != nil
    }
}

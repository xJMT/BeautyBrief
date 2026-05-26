import CloudKit
import SwiftUI

// ─────────────────────────────────────────────
//  CommunityPost  —  data model
//  Backed by CloudKit CKPublicDatabase.
//  CKRecord type: "CommunityPost"
// ─────────────────────────────────────────────

// MARK: — Post Type

enum PostType: String, CaseIterable, Identifiable {
    case review        = "review"
    case reactionAlert = "alert"
    case question      = "question"
    case routine       = "routine"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .review:        return "Review"
        case .reactionAlert: return "Reaction Alert"
        case .question:      return "Ingredient Q&A"
        case .routine:       return "My Routine"
        }
    }

    var icon: String {
        switch self {
        case .review:        return "star.fill"
        case .reactionAlert: return "exclamationmark.triangle.fill"
        case .question:      return "questionmark.circle.fill"
        case .routine:       return "list.bullet.clipboard.fill"
        }
    }

    var color: Color {
        switch self {
        case .review:        return AppTheme.mocha
        case .reactionAlert: return AppTheme.danger
        case .question:      return AppTheme.info
        case .routine:       return AppTheme.success
        }
    }

    var allowsRating: Bool { self == .review }
    var allowsAllergenFlags: Bool { self == .reactionAlert }
}

// MARK: — Reaction Type

enum ReactionType: String, CaseIterable {
    case heart   = "heart"
    case thumb   = "thumb"
    case warning = "warning"

    var icon: String {
        switch self {
        case .heart:   return "heart.fill"
        case .thumb:   return "hand.thumbsup.fill"
        case .warning: return "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .heart:   return Color(hex: "#E08098")
        case .thumb:   return AppTheme.mocha
        case .warning: return AppTheme.warning
        }
    }
}

// MARK: — Community Post Model

struct CommunityPost: Identifiable {
    let id: String           // CloudKit recordName — no CKRecord.ID dependency in ViewModel
    var postType: PostType
    var productBarcode: String?
    var productName: String
    var productBrand: String
    var authorName: String
    var authorAvatarIndex: Int
    var authorSkinTypes: [String]
    var starRating: Int          // 1–5 for reviews; 0 otherwise
    var bodyText: String
    var photoURL: URL?           // local file URL from CKAsset
    var allergenFlags: [String]
    var heartCount: Int
    var thumbCount: Int
    var warningCount: Int
    var createdAt: Date

    var totalReactions: Int { heartCount + thumbCount + warningCount }

    // MARK: — CloudKit initialiser
    init?(record: CKRecord) {
        guard
            let postTypeRaw = record["postType"]    as? String,
            let postType    = PostType(rawValue: postTypeRaw),
            let productName = record["productName"] as? String,
            let authorName  = record["authorName"]  as? String,
            let bodyText    = record["bodyText"]    as? String
        else { return nil }

        self.id               = record.recordID.recordName
        self.postType         = postType
        self.productName      = productName
        self.productBrand     = record["productBrand"]     as? String ?? ""
        self.productBarcode   = record["productBarcode"]   as? String
        self.authorName       = authorName
        self.authorAvatarIndex = Int(record["authorAvatarIndex"] as? Int64 ?? 0)
        self.authorSkinTypes  = record["authorSkinTypes"]  as? [String] ?? []
        self.starRating       = Int(record["starRating"]   as? Int64 ?? 0)
        self.bodyText         = bodyText
        self.allergenFlags    = record["allergenFlags"]    as? [String] ?? []
        self.heartCount       = Int(record["heartCount"]   as? Int64 ?? 0)
        self.thumbCount       = Int(record["thumbCount"]   as? Int64 ?? 0)
        self.warningCount     = Int(record["warningCount"] as? Int64 ?? 0)
        self.createdAt        = record.creationDate ?? Date()
        self.photoURL         = (record["photo"] as? CKAsset)?.fileURL
    }

    // MARK: — Direct initialiser (mock / preview)
    init(
        id: String                  = UUID().uuidString,
        postType: PostType,
        productName: String,
        productBrand: String        = "",
        productBarcode: String?     = nil,
        authorName: String,
        authorAvatarIndex: Int      = 0,
        authorSkinTypes: [String]   = [],
        starRating: Int             = 0,
        bodyText: String,
        photoURL: URL?              = nil,
        allergenFlags: [String]     = [],
        heartCount: Int             = 0,
        thumbCount: Int             = 0,
        warningCount: Int           = 0,
        createdAt: Date             = Date()
    ) {
        self.id               = id
        self.postType         = postType
        self.productName      = productName
        self.productBrand     = productBrand
        self.productBarcode   = productBarcode
        self.authorName       = authorName
        self.authorAvatarIndex = authorAvatarIndex
        self.authorSkinTypes  = authorSkinTypes
        self.starRating       = starRating
        self.bodyText         = bodyText
        self.photoURL         = photoURL
        self.allergenFlags    = allergenFlags
        self.heartCount       = heartCount
        self.thumbCount       = thumbCount
        self.warningCount     = warningCount
        self.createdAt        = createdAt
    }
}

// MARK: — New Post Input

struct NewPostData {
    var postType: PostType       = .review
    var productName: String      = ""
    var productBrand: String     = ""
    var productBarcode: String?  = nil
    var authorName: String       = ""
    var authorAvatarIndex: Int   = 0
    var authorSkinTypes: [String] = []
    var starRating: Int          = 0
    var bodyText: String         = ""
    var photoData: Data?         = nil
    var allergenFlags: [String]  = []

    var isValid: Bool {
        !productName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !bodyText.trimmingCharacters(in: .whitespaces).isEmpty &&
        (postType != .review || starRating > 0)
    }
}

// MARK: — Mock Data (preview + iCloud fallback)

extension CommunityPost {
    static let mockPosts: [CommunityPost] = [
        CommunityPost(
            postType: .review,
            productName: "Vitamin C Brightening Serum",
            productBrand: "The Ordinary",
            authorName: "Sofia R.",
            authorAvatarIndex: 2,
            authorSkinTypes: ["Oily", "Combination"],
            starRating: 5,
            bodyText: "I've been using this for 3 weeks and my dark spots have visibly faded. The texture is lightweight and doesn't pill under SPF. Highly recommend for anyone dealing with hyperpigmentation!",
            heartCount: 42,
            thumbCount: 18,
            warningCount: 0,
            createdAt: Date().addingTimeInterval(-3_600 * 2)
        ),
        CommunityPost(
            postType: .reactionAlert,
            productName: "Hydrating Toner",
            productBrand: "Laneige",
            authorName: "Maya K.",
            authorAvatarIndex: 5,
            authorSkinTypes: ["Sensitive"],
            starRating: 0,
            bodyText: "Heads up — this contains phenoxyethanol which isn't listed prominently. I had redness and itching after two uses. Sensitive skin folks please patch test first!",
            allergenFlags: ["Phenoxyethanol", "Fragrance"],
            heartCount: 88,
            thumbCount: 31,
            warningCount: 12,
            createdAt: Date().addingTimeInterval(-3_600 * 5)
        ),
        CommunityPost(
            postType: .question,
            productName: "Niacinamide 10% + Zinc 1%",
            productBrand: "The Ordinary",
            authorName: "Alex T.",
            authorAvatarIndex: 1,
            authorSkinTypes: ["Oily"],
            starRating: 0,
            bodyText: "Has anyone mixed niacinamide with their vitamin C serum? I've heard conflicting things about whether they cancel each other out. What's been your experience?",
            heartCount: 15,
            thumbCount: 29,
            warningCount: 0,
            createdAt: Date().addingTimeInterval(-3_600 * 8)
        ),
        CommunityPost(
            postType: .routine,
            productName: "My Winter Morning Routine",
            productBrand: "",
            authorName: "Priya S.",
            authorAvatarIndex: 3,
            authorSkinTypes: ["Dry", "Sensitive"],
            starRating: 0,
            bodyText: "My winter dry-skin routine that's been a game changer:\n1. Gentle cream cleanser\n2. Hyaluronic acid serum (apply to damp skin!)\n3. Ceramide moisturiser\n4. SPF 50 mineral sunscreen\n\nThe key is layering thinnest to thickest and never skipping SPF.",
            heartCount: 67,
            thumbCount: 44,
            warningCount: 0,
            createdAt: Date().addingTimeInterval(-3_600 * 24)
        ),
        CommunityPost(
            postType: .review,
            productName: "Moisturising Cream",
            productBrand: "CeraVe",
            authorName: "Jordan L.",
            authorAvatarIndex: 4,
            authorSkinTypes: ["Normal", "Dry"],
            starRating: 4,
            bodyText: "Solid everyday moisturiser. The ceramide complex is genuinely effective and it layers well under makeup without pilling. Only gripe is the heavy jar packaging — wish it came in a pump.",
            heartCount: 33,
            thumbCount: 27,
            warningCount: 1,
            createdAt: Date().addingTimeInterval(-3_600 * 36)
        ),
        CommunityPost(
            postType: .reactionAlert,
            productName: "AHA 30% + BHA 2% Peeling Solution",
            productBrand: "The Ordinary",
            authorName: "Sam W.",
            authorAvatarIndex: 0,
            authorSkinTypes: ["Sensitive"],
            starRating: 0,
            bodyText: "Left on too long and experienced a chemical burn. The instructions say 10 minutes max — please follow them! Not suitable for sensitive or compromised skin barriers.",
            allergenFlags: ["Glycolic Acid", "Salicylic Acid"],
            heartCount: 104,
            thumbCount: 56,
            warningCount: 38,
            createdAt: Date().addingTimeInterval(-3_600 * 48)
        ),
        CommunityPost(
            postType: .question,
            productName: "Retinol 0.2% in Squalane",
            productBrand: "The Ordinary",
            authorName: "Chloe M.",
            authorAvatarIndex: 6,
            authorSkinTypes: ["Combination"],
            starRating: 0,
            bodyText: "Can I use retinol while pregnant? I know prescription retinoids are off-limits but what about OTC concentrations like this? My dermatologist is booked out for weeks.",
            heartCount: 22,
            thumbCount: 41,
            warningCount: 5,
            createdAt: Date().addingTimeInterval(-3_600 * 60)
        ),
    ]
}

import CloudKit
import SwiftUI

// ─────────────────────────────────────────────
//  CommunityService  —  CloudKit backend
//
//  Setup required in Xcode (one-time):
//  Target → Signing & Capabilities → + Capability
//  → iCloud → enable CloudKit
//  → Container: iCloud.BB.BeautyBrief
//
//  Uses CKContainer.default() which maps to the
//  container declared in the app's entitlements.
// ─────────────────────────────────────────────

final class CommunityService {

    static let shared = CommunityService()
    private init() {}

    // Lazily created — only accessed after confirming the CloudKit entitlement exists.
    // CKContainer.default() traps (crashes) if the iCloud+CloudKit capability is missing
    // from Signing & Capabilities. Making it lazy means the app launches safely and the
    // Community tab falls back to mock data until the capability is properly configured.
    private lazy var container: CKContainer = CKContainer.default()
    private var publicDB: CKDatabase { container.publicCloudDatabase }

    // MARK: — Entitlement check (crash-safe)

    /// True only when the embedded provisioning profile contains the CloudKit entitlement.
    /// Reads the profile file — no CloudKit API call, so it never crashes.
    private static let cloudKitEntitlementPresent: Bool = {
        guard let url  = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .isoLatin1) else {
            // No provisioning profile found — running on Simulator without entitlements.
            return false
        }
        return text.contains("com.apple.developer.icloud-services") &&
               (text.contains("\"CloudKit\"") || text.contains("CloudKit-Anonymous"))
    }()

    // MARK: — iCloud account check

    /// Returns true when the user is signed in to iCloud and CloudKit is available.
    /// Returns false immediately (without touching CloudKit) if the entitlement is missing.
    func isCloudAvailable() async -> Bool {
        guard Self.cloudKitEntitlementPresent else { return false }
        let status = (try? await container.accountStatus()) ?? .noAccount
        return status == .available
    }

    // MARK: — Fetch

    /// Most recent posts, optionally filtered by PostType.
    func fetchPosts(type: PostType? = nil, limit: Int = 60) async throws -> [CommunityPost] {
        let predicate: NSPredicate = type.map {
            NSPredicate(format: "postType == %@", $0.rawValue)
        } ?? NSPredicate(value: true)

        let query = CKQuery(recordType: "CommunityPost", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        let (results, _) = try await publicDB.records(matching: query,
                                                      resultsLimit: limit)
        return results.compactMap { _, result in
            guard case .success(let record) = result else { return nil }
            return CommunityPost(record: record)
        }
    }

    /// Posts for a specific product barcode.
    func fetchPosts(forBarcode barcode: String, limit: Int = 20) async throws -> [CommunityPost] {
        let predicate = NSPredicate(format: "productBarcode == %@", barcode)
        let query     = CKQuery(recordType: "CommunityPost", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        let (results, _) = try await publicDB.records(matching: query, resultsLimit: limit)
        return results.compactMap { _, result in
            guard case .success(let record) = result else { return nil }
            return CommunityPost(record: record)
        }
    }

    // MARK: — Save

    func save(post data: NewPostData) async throws -> CommunityPost {
        let record = CKRecord(recordType: "CommunityPost")
        record["postType"]          = data.postType.rawValue        as CKRecordValue
        record["productName"]       = data.productName              as CKRecordValue
        record["productBrand"]      = data.productBrand             as CKRecordValue
        record["authorName"]        = data.authorName               as CKRecordValue
        record["authorAvatarIndex"] = Int64(data.authorAvatarIndex) as CKRecordValue
        record["authorSkinTypes"]   = data.authorSkinTypes          as CKRecordValue
        record["starRating"]        = Int64(data.starRating)        as CKRecordValue
        record["bodyText"]          = data.bodyText                 as CKRecordValue
        record["allergenFlags"]     = data.allergenFlags            as CKRecordValue
        record["heartCount"]        = Int64(0)                      as CKRecordValue
        record["thumbCount"]        = Int64(0)                      as CKRecordValue
        record["warningCount"]      = Int64(0)                      as CKRecordValue

        if let barcode = data.productBarcode {
            record["productBarcode"] = barcode as CKRecordValue
        }
        if let imageData = data.photoData,
           let tempURL = try? writeToTemp(imageData) {
            record["photo"] = CKAsset(fileURL: tempURL)
        }

        let saved = try await publicDB.save(record)
        guard let post = CommunityPost(record: saved) else {
            throw CommunityError.invalidRecord
        }
        return post
    }

    // MARK: — React

    /// Increments a reaction counter on the given post.
    /// Accepts the post's String id (CKRecord recordName) so callers
    /// don't need to import CloudKit.
    func react(to postID: String, reaction: ReactionType) async throws {
        let recordID = CKRecord.ID(recordName: postID)
        let record = try await publicDB.record(for: recordID)
        let field: String
        switch reaction {
        case .heart:   field = "heartCount"
        case .thumb:   field = "thumbCount"
        case .warning: field = "warningCount"
        }
        let current = record[field] as? Int64 ?? 0
        record[field] = (current + 1) as CKRecordValue
        _ = try await publicDB.save(record)
    }

    // MARK: — Helpers

    private func writeToTemp(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("jpg")
        try data.write(to: url)
        return url
    }
}

// MARK: — Errors

enum CommunityError: LocalizedError {
    case invalidRecord
    case notSignedIn

    var errorDescription: String? {
        switch self {
        case .invalidRecord: return "The post data was invalid."
        case .notSignedIn:   return "Please sign in to iCloud to post to the community."
        }
    }
}

import Foundation

enum PersistenceSchema {
    static let currentIndexVersion = 2
    static let currentAuthorMetaVersion = 1
    static let currentAlbumMetaVersion = 1
}

// MARK: - index.json

struct IndexFile: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var authors: [AuthorSummaryDTO]
    /// Keyed by `authorId`.
    var albumsByAuthor: [String: [AlbumSummaryDTO]]
    /// Encoded as `authorId/albumId`.
    var favoriteAlbums: [String]
    var recentlyViewed: [RecentlyViewedEntryDTO]
    /// Deprecated: schema v1 single-slot continue-reading.
    var continueReading: ContinueReadingDTO?
    /// Per-album progress, keyed by `authorId/albumId` → last `imageIndex`.
    var continueReadingProgress: [String: Int]
    var recentlyAdded: [RecentlyAddedAlbumDTO]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case authors
        case albumsByAuthor
        case favoriteAlbums
        case recentlyViewed
        case continueReading
        case continueReadingProgress
        case recentlyAdded
    }

    init(
        schemaVersion: Int,
        authors: [AuthorSummaryDTO],
        albumsByAuthor: [String: [AlbumSummaryDTO]],
        favoriteAlbums: [String],
        recentlyViewed: [RecentlyViewedEntryDTO],
        continueReading: ContinueReadingDTO?,
        continueReadingProgress: [String: Int],
        recentlyAdded: [RecentlyAddedAlbumDTO]
    ) {
        self.schemaVersion = schemaVersion
        self.authors = authors
        self.albumsByAuthor = albumsByAuthor
        self.favoriteAlbums = favoriteAlbums
        self.recentlyViewed = recentlyViewed
        self.continueReading = continueReading
        self.continueReadingProgress = continueReadingProgress
        self.recentlyAdded = recentlyAdded
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        authors = try c.decode([AuthorSummaryDTO].self, forKey: .authors)
        albumsByAuthor = try c.decode([String: [AlbumSummaryDTO]].self, forKey: .albumsByAuthor)
        favoriteAlbums = try c.decode([String].self, forKey: .favoriteAlbums)
        recentlyViewed = try c.decode([RecentlyViewedEntryDTO].self, forKey: .recentlyViewed)
        continueReading = try c.decodeIfPresent(ContinueReadingDTO.self, forKey: .continueReading)
        continueReadingProgress = try c.decodeIfPresent([String: Int].self, forKey: .continueReadingProgress) ?? [:]
        recentlyAdded = try c.decode([RecentlyAddedAlbumDTO].self, forKey: .recentlyAdded)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(authors, forKey: .authors)
        try c.encode(albumsByAuthor, forKey: .albumsByAuthor)
        try c.encode(favoriteAlbums, forKey: .favoriteAlbums)
        try c.encode(recentlyViewed, forKey: .recentlyViewed)
        try c.encodeIfPresent(continueReading, forKey: .continueReading)
        try c.encode(continueReadingProgress, forKey: .continueReadingProgress)
        try c.encode(recentlyAdded, forKey: .recentlyAdded)
    }

    static let empty = IndexFile(
        schemaVersion: PersistenceSchema.currentIndexVersion,
        authors: [],
        albumsByAuthor: [:],
        favoriteAlbums: [],
        recentlyViewed: [],
        continueReading: nil,
        continueReadingProgress: [:],
        recentlyAdded: []
    )
}

struct AuthorSummaryDTO: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var albumCount: Int
    var avatarFileName: String?
}

struct AlbumSummaryDTO: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var displayTitle: String
    var order: Int
    var imageCount: Int
    var coverThumbnailFileName: String?
    var createdAt: Date
    var updatedAt: Date
    var lastOpenedAt: Date?
    var coverAspectRatio: Double?
}

struct RecentlyViewedEntryDTO: Codable, Equatable, Sendable {
    var authorId: String
    var albumId: String
    var viewedAt: Date
}

struct ContinueReadingDTO: Codable, Equatable, Sendable {
    var authorId: String
    var albumId: String
    var imageIndex: Int
}

struct RecentlyAddedAlbumDTO: Codable, Equatable, Sendable {
    var authorId: String
    var albumId: String
    var touchedAt: Date
}

// MARK: - author meta.json

struct AuthorMetaFile: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var id: String
    var displayName: String
    var avatarFileName: String?
}

// MARK: - album meta.json

struct AlbumMetaFile: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var id: String
    var order: Int
    var displayTitle: String
    var createdAt: Date
    var updatedAt: Date
    var lastOpenedAt: Date?
    var images: [String]
}

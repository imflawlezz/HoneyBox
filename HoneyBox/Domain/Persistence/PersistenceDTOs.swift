import Foundation

enum PersistenceSchema: Sendable {
    nonisolated static let currentIndexVersion = 2
    nonisolated static let currentAuthorMetaVersion = 1
    nonisolated static let currentAlbumMetaVersion = 1
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

    nonisolated init(
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

    nonisolated init(from decoder: Decoder) throws {
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

    nonisolated func encode(to encoder: Encoder) throws {
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

    nonisolated static let empty = IndexFile(
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

    nonisolated init(id: String, name: String, albumCount: Int, avatarFileName: String?) {
        self.id = id
        self.name = name
        self.albumCount = albumCount
        self.avatarFileName = avatarFileName
    }

    enum CodingKeys: String, CodingKey {
        case id, name, albumCount, avatarFileName
    }

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        albumCount = try c.decode(Int.self, forKey: .albumCount)
        avatarFileName = try c.decodeIfPresent(String.self, forKey: .avatarFileName)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(albumCount, forKey: .albumCount)
        try c.encodeIfPresent(avatarFileName, forKey: .avatarFileName)
    }
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

    nonisolated init(
        id: String,
        displayTitle: String,
        order: Int,
        imageCount: Int,
        coverThumbnailFileName: String?,
        createdAt: Date,
        updatedAt: Date,
        lastOpenedAt: Date?,
        coverAspectRatio: Double?
    ) {
        self.id = id
        self.displayTitle = displayTitle
        self.order = order
        self.imageCount = imageCount
        self.coverThumbnailFileName = coverThumbnailFileName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastOpenedAt = lastOpenedAt
        self.coverAspectRatio = coverAspectRatio
    }

    enum CodingKeys: String, CodingKey {
        case id, displayTitle, order, imageCount, coverThumbnailFileName, createdAt, updatedAt, lastOpenedAt, coverAspectRatio
    }

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        displayTitle = try c.decode(String.self, forKey: .displayTitle)
        order = try c.decode(Int.self, forKey: .order)
        imageCount = try c.decode(Int.self, forKey: .imageCount)
        coverThumbnailFileName = try c.decodeIfPresent(String.self, forKey: .coverThumbnailFileName)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        lastOpenedAt = try c.decodeIfPresent(Date.self, forKey: .lastOpenedAt)
        coverAspectRatio = try c.decodeIfPresent(Double.self, forKey: .coverAspectRatio)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(displayTitle, forKey: .displayTitle)
        try c.encode(order, forKey: .order)
        try c.encode(imageCount, forKey: .imageCount)
        try c.encodeIfPresent(coverThumbnailFileName, forKey: .coverThumbnailFileName)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encodeIfPresent(lastOpenedAt, forKey: .lastOpenedAt)
        try c.encodeIfPresent(coverAspectRatio, forKey: .coverAspectRatio)
    }
}

struct RecentlyViewedEntryDTO: Codable, Equatable, Sendable {
    var authorId: String
    var albumId: String
    var viewedAt: Date

    nonisolated init(authorId: String, albumId: String, viewedAt: Date) {
        self.authorId = authorId
        self.albumId = albumId
        self.viewedAt = viewedAt
    }

    enum CodingKeys: String, CodingKey {
        case authorId, albumId, viewedAt
    }

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        authorId = try c.decode(String.self, forKey: .authorId)
        albumId = try c.decode(String.self, forKey: .albumId)
        viewedAt = try c.decode(Date.self, forKey: .viewedAt)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(authorId, forKey: .authorId)
        try c.encode(albumId, forKey: .albumId)
        try c.encode(viewedAt, forKey: .viewedAt)
    }
}

struct ContinueReadingDTO: Codable, Equatable, Sendable {
    var authorId: String
    var albumId: String
    var imageIndex: Int

    nonisolated init(authorId: String, albumId: String, imageIndex: Int) {
        self.authorId = authorId
        self.albumId = albumId
        self.imageIndex = imageIndex
    }

    enum CodingKeys: String, CodingKey {
        case authorId, albumId, imageIndex
    }

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        authorId = try c.decode(String.self, forKey: .authorId)
        albumId = try c.decode(String.self, forKey: .albumId)
        imageIndex = try c.decode(Int.self, forKey: .imageIndex)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(authorId, forKey: .authorId)
        try c.encode(albumId, forKey: .albumId)
        try c.encode(imageIndex, forKey: .imageIndex)
    }
}

struct RecentlyAddedAlbumDTO: Codable, Equatable, Sendable {
    var authorId: String
    var albumId: String
    var touchedAt: Date

    nonisolated init(authorId: String, albumId: String, touchedAt: Date) {
        self.authorId = authorId
        self.albumId = albumId
        self.touchedAt = touchedAt
    }

    enum CodingKeys: String, CodingKey {
        case authorId, albumId, touchedAt
    }

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        authorId = try c.decode(String.self, forKey: .authorId)
        albumId = try c.decode(String.self, forKey: .albumId)
        touchedAt = try c.decode(Date.self, forKey: .touchedAt)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(authorId, forKey: .authorId)
        try c.encode(albumId, forKey: .albumId)
        try c.encode(touchedAt, forKey: .touchedAt)
    }
}

// MARK: - author meta.json

struct AuthorMetaFile: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var id: String
    var displayName: String
    var avatarFileName: String?

    nonisolated init(schemaVersion: Int, id: String, displayName: String, avatarFileName: String?) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.displayName = displayName
        self.avatarFileName = avatarFileName
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion, id, displayName, avatarFileName
    }

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        id = try c.decode(String.self, forKey: .id)
        displayName = try c.decode(String.self, forKey: .displayName)
        avatarFileName = try c.decodeIfPresent(String.self, forKey: .avatarFileName)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(id, forKey: .id)
        try c.encode(displayName, forKey: .displayName)
        try c.encodeIfPresent(avatarFileName, forKey: .avatarFileName)
    }
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

    nonisolated init(
        schemaVersion: Int,
        id: String,
        order: Int,
        displayTitle: String,
        createdAt: Date,
        updatedAt: Date,
        lastOpenedAt: Date?,
        images: [String]
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.order = order
        self.displayTitle = displayTitle
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastOpenedAt = lastOpenedAt
        self.images = images
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion, id, order, displayTitle, createdAt, updatedAt, lastOpenedAt, images
    }

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        id = try c.decode(String.self, forKey: .id)
        order = try c.decode(Int.self, forKey: .order)
        displayTitle = try c.decode(String.self, forKey: .displayTitle)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        lastOpenedAt = try c.decodeIfPresent(Date.self, forKey: .lastOpenedAt)
        images = try c.decode([String].self, forKey: .images)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(id, forKey: .id)
        try c.encode(order, forKey: .order)
        try c.encode(displayTitle, forKey: .displayTitle)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encodeIfPresent(lastOpenedAt, forKey: .lastOpenedAt)
        try c.encode(images, forKey: .images)
    }
}

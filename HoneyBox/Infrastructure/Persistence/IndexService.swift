import Foundation

actor IndexService: LibraryIndexing {
    private let storage: StorageService
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var index: IndexFile

    init(storage: StorageService) throws {
        self.storage = storage
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.encoder = encoder
        self.decoder = decoder

        let url = StoragePaths.indexURL(root: storage.rootURL)
        if let data = storage.readDataIfPresent(at: url) {
            var loaded = try decoder.decode(IndexFile.self, from: data)
            if loaded.schemaVersion < 2 {
                if let cr = loaded.continueReading {
                    let key = Self.globalAlbumKey(authorId: cr.authorId, albumId: cr.albumId)
                    loaded.continueReadingProgress[key] = cr.imageIndex
                    loaded.continueReading = nil
                }
                loaded.schemaVersion = 2
            }
            if loaded.schemaVersion < PersistenceSchema.currentIndexVersion {
                loaded.schemaVersion = PersistenceSchema.currentIndexVersion
            }
            self.index = loaded
        } else {
            self.index = .empty
        }
    }

    nonisolated static func globalAlbumKey(authorId: String, albumId: String) -> String {
        ImageRef.globalAlbumKey(authorId: authorId, albumId: albumId)
    }

    func snapshot() -> IndexFile {
        index
    }

    func author(withId id: String) -> AuthorSummaryDTO? {
        index.authors.first { $0.id == id }
    }

    func albums(for authorId: String, sort: AlbumsSortOrder, filter: AlbumsFilter) -> [AlbumSummaryDTO] {
        var list = index.albumsByAuthor[authorId] ?? []
        switch filter {
        case .all:
            break
        case .favoritesOnly:
            let fav = Set(index.favoriteAlbums)
            list = list.filter { fav.contains(Self.globalAlbumKey(authorId: authorId, albumId: $0.id)) }
        case .notViewedOnly:
            list = list.filter { $0.lastOpenedAt == nil }
        }
        switch sort {
        case .latestFirst:
            list.sort { $0.updatedAt > $1.updatedAt }
        case .oldestFirst:
            list.sort { $0.updatedAt < $1.updatedAt }
        }
        return list
    }

    func isFavorite(authorId: String, albumId: String) -> Bool {
        index.favoriteAlbums.contains(Self.globalAlbumKey(authorId: authorId, albumId: albumId))
    }

    func albumSummary(authorId: String, albumId: String) -> AlbumSummaryDTO? {
        index.albumsByAuthor[authorId]?.first { $0.id == albumId }
    }

    func loadAlbumMeta(authorId: String, albumId: String) throws -> AlbumMetaFile {
        let url = StoragePaths.albumMetaURL(root: storage.rootURL, authorId: authorId, albumId: albumId)
        let data = try storage.readData(at: url)
        return try decoder.decode(AlbumMetaFile.self, from: data)
    }

    func saveAlbumMeta(_ meta: AlbumMetaFile, authorId: String, albumId: String) throws {
        let url = StoragePaths.albumMetaURL(root: storage.rootURL, authorId: authorId, albumId: albumId)
        let data = try encoder.encode(meta)
        try storage.atomicWrite(data, to: url)
    }

    func loadAuthorMeta(authorId: String) throws -> AuthorMetaFile {
        let url = StoragePaths.authorMetaURL(root: storage.rootURL, authorId: authorId)
        let data = try storage.readData(at: url)
        return try decoder.decode(AuthorMetaFile.self, from: data)
    }

    func saveAuthorMeta(_ meta: AuthorMetaFile, authorId: String) throws {
        let url = StoragePaths.authorMetaURL(root: storage.rootURL, authorId: authorId)
        let data = try encoder.encode(meta)
        try storage.atomicWrite(data, to: url)
    }

    private func persistIndex() throws {
        let url = StoragePaths.indexURL(root: storage.rootURL)
        let data = try encoder.encode(index)
        try storage.atomicWrite(data, to: url)
    }

    func createAuthor(displayName: String) throws -> String {
        let id = "author_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12))"
        let dir = StoragePaths.authorDirectory(root: storage.rootURL, authorId: id)
        try storage.createDirectory(at: dir)
        let meta = AuthorMetaFile(
            schemaVersion: PersistenceSchema.currentAuthorMetaVersion,
            id: id,
            displayName: displayName,
            avatarFileName: nil
        )
        try saveAuthorMeta(meta, authorId: id)
        var authors = index.authors
        authors.append(AuthorSummaryDTO(id: id, name: displayName, albumCount: 0, avatarFileName: nil))
        index.authors = authors.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        index.albumsByAuthor[id] = index.albumsByAuthor[id] ?? []
        try persistIndex()
        return id
    }

    func renameAuthor(authorId: String, newName: String) throws {
        guard var meta = try? loadAuthorMeta(authorId: authorId) else { return }
        meta.displayName = newName
        try saveAuthorMeta(meta, authorId: authorId)
        if let idx = index.authors.firstIndex(where: { $0.id == authorId }) {
            index.authors[idx].name = newName
        }
        try persistIndex()
    }

    func setAuthorAvatar(authorId: String, fileName: String) throws {
        var meta = try loadAuthorMeta(authorId: authorId)
        meta.avatarFileName = fileName
        try saveAuthorMeta(meta, authorId: authorId)
        if let idx = index.authors.firstIndex(where: { $0.id == authorId }) {
            index.authors[idx].avatarFileName = fileName
        }
        try persistIndex()
    }

    func deleteAuthorCascade(authorId: String) throws {
        let albumIds = (index.albumsByAuthor[authorId] ?? []).map(\.id)
        let albumKeys = Set(albumIds.map { Self.globalAlbumKey(authorId: authorId, albumId: $0) })

        index.authors.removeAll { $0.id == authorId }
        index.albumsByAuthor.removeValue(forKey: authorId)
        index.favoriteAlbums.removeAll { albumKeys.contains($0) }
        index.recentlyViewed.removeAll { $0.authorId == authorId }
        index.recentlyAdded.removeAll { $0.authorId == authorId }
        for key in albumKeys {
            index.continueReadingProgress.removeValue(forKey: key)
        }
        if index.continueReading?.authorId == authorId {
            index.continueReading = nil
        }

        let dir = StoragePaths.authorDirectory(root: storage.rootURL, authorId: authorId)
        try storage.removeItem(at: dir)
        try persistIndex()
    }

    private func bumpAuthorAlbumCount(authorId: String, delta: Int) throws {
        guard let idx = index.authors.firstIndex(where: { $0.id == authorId }) else { return }
        index.authors[idx].albumCount = max(0, index.authors[idx].albumCount + delta)
        try persistIndex()
    }

    func upsertAlbumSummary(_ summary: AlbumSummaryDTO, authorId: String) throws {
        var list = index.albumsByAuthor[authorId] ?? []
        if let i = list.firstIndex(where: { $0.id == summary.id }) {
            list[i] = summary
        } else {
            list.append(summary)
        }
        list.sort { $0.order < $1.order }
        index.albumsByAuthor[authorId] = list
        try persistIndex()
    }

    func addOrUpdateAlbumSummary(_ summary: AlbumSummaryDTO, authorId: String) throws {
        var list = index.albumsByAuthor[authorId] ?? []
        if let i = list.firstIndex(where: { $0.id == summary.id }) {
            list[i] = summary
        } else {
            list.append(summary)
            if let idx = index.authors.firstIndex(where: { $0.id == authorId }) {
                index.authors[idx].albumCount += 1
            }
        }
        list.sort { $0.order < $1.order }
        index.albumsByAuthor[authorId] = list
        try persistIndex()
    }

    func removeAlbumSummary(authorId: String, albumId: String) throws {
        var list = index.albumsByAuthor[authorId] ?? []
        list.removeAll { $0.id == albumId }
        index.albumsByAuthor[authorId] = list
        let key = Self.globalAlbumKey(authorId: authorId, albumId: albumId)
        index.favoriteAlbums.removeAll { $0 == key }
        index.recentlyViewed.removeAll { $0.authorId == authorId && $0.albumId == albumId }
        index.recentlyAdded.removeAll { $0.authorId == authorId && $0.albumId == albumId }
        index.continueReadingProgress.removeValue(forKey: key)
        if index.continueReading?.authorId == authorId && index.continueReading?.albumId == albumId {
            index.continueReading = nil
        }
        try bumpAuthorAlbumCount(authorId: authorId, delta: -1)
        try persistIndex()
    }

    func touchRecentlyAdded(authorId: String, albumId: String) throws {
        index.recentlyAdded.removeAll { $0.authorId == authorId && $0.albumId == albumId }
        index.recentlyAdded.insert(RecentlyAddedAlbumDTO(authorId: authorId, albumId: albumId, touchedAt: Date()), at: 0)
        if index.recentlyAdded.count > 200 {
            index.recentlyAdded = Array(index.recentlyAdded.prefix(200))
        }
        try persistIndex()
    }

    func toggleFavorite(authorId: String, albumId: String) throws {
        let key = Self.globalAlbumKey(authorId: authorId, albumId: albumId)
        if let idx = index.favoriteAlbums.firstIndex(of: key) {
            index.favoriteAlbums.remove(at: idx)
        } else {
            index.favoriteAlbums.append(key)
        }
        try persistIndex()
    }

    func markAlbumOpened(authorId: String, albumId: String) throws {
        let now = Date()
        if let idx = index.albumsByAuthor[authorId]?.firstIndex(where: { $0.id == albumId }) {
            index.albumsByAuthor[authorId]?[idx].lastOpenedAt = now
        }
        index.recentlyViewed.removeAll { $0.authorId == authorId && $0.albumId == albumId }
        index.recentlyViewed.insert(RecentlyViewedEntryDTO(authorId: authorId, albumId: albumId, viewedAt: now), at: 0)
        if index.recentlyViewed.count > 100 {
            index.recentlyViewed = Array(index.recentlyViewed.prefix(100))
        }
        var meta = try loadAlbumMeta(authorId: authorId, albumId: albumId)
        meta.lastOpenedAt = now
        try saveAlbumMeta(meta, authorId: authorId, albumId: albumId)
        try persistIndex()
    }

    func setContinueReading(authorId: String, albumId: String, imageIndex: Int) throws {
        let key = Self.globalAlbumKey(authorId: authorId, albumId: albumId)
        index.continueReadingProgress[key] = imageIndex
        try persistIndex()
    }

    func clearContinueReading() throws {
        index.continueReading = nil
        index.continueReadingProgress = [:]
        try persistIndex()
    }

    func updateAlbumDisplayTitle(authorId: String, albumId: String, title: String) throws {
        var meta = try loadAlbumMeta(authorId: authorId, albumId: albumId)
        meta.displayTitle = title
        meta.updatedAt = Date()
        try saveAlbumMeta(meta, authorId: authorId, albumId: albumId)
        if let idx = index.albumsByAuthor[authorId]?.firstIndex(where: { $0.id == albumId }) {
            index.albumsByAuthor[authorId]?[idx].displayTitle = title
            index.albumsByAuthor[authorId]?[idx].updatedAt = meta.updatedAt
        }
        try persistIndex()
    }

    func updateAlbumSummaryFromMeta(authorId: String, albumId: String) throws {
        let meta = try loadAlbumMeta(authorId: authorId, albumId: albumId)
        let coverThumb: String?
        if let first = meta.images.first {
            let stem = (first as NSString).deletingPathExtension.replacingOccurrences(of: "img_", with: "")
            coverThumb = "thumb_\(stem).jpg"
        } else {
            coverThumb = nil
        }
        guard let idx = index.albumsByAuthor[authorId]?.firstIndex(where: { $0.id == albumId }) else { return }
        index.albumsByAuthor[authorId]?[idx].displayTitle = meta.displayTitle
        index.albumsByAuthor[authorId]?[idx].imageCount = meta.images.count
        index.albumsByAuthor[authorId]?[idx].coverThumbnailFileName = coverThumb
        index.albumsByAuthor[authorId]?[idx].updatedAt = meta.updatedAt
        index.albumsByAuthor[authorId]?[idx].lastOpenedAt = meta.lastOpenedAt
        try persistIndex()
    }

    func deleteImage(authorId: String, albumId: String, fileName: String) throws {
        var meta = try loadAlbumMeta(authorId: authorId, albumId: albumId)
        meta.images.removeAll { $0 == fileName }
        meta.updatedAt = Date()
        let ref = ImageRef(authorId: authorId, albumId: albumId, fileName: fileName)
        let imgURL = StoragePaths.imagesDirectory(root: storage.rootURL, authorId: authorId, albumId: albumId)
            .appendingPathComponent(fileName, isDirectory: false)
        let thumbURL = StoragePaths.thumbnailsDirectory(root: storage.rootURL, authorId: authorId, albumId: albumId)
            .appendingPathComponent(ref.thumbnailFileName, isDirectory: false)
        try storage.removeItem(at: imgURL)
        try storage.removeItem(at: thumbURL)
        try saveAlbumMeta(meta, authorId: authorId, albumId: albumId)
        try updateAlbumSummaryFromMeta(authorId: authorId, albumId: albumId)
        try touchRecentlyAdded(authorId: authorId, albumId: albumId)
    }

    func setAlbumImageOrder(authorId: String, albumId: String, images: [String]) throws {
        var meta = try loadAlbumMeta(authorId: authorId, albumId: albumId)
        meta.images = images
        meta.updatedAt = Date()
        try saveAlbumMeta(meta, authorId: authorId, albumId: albumId)
        try updateAlbumSummaryFromMeta(authorId: authorId, albumId: albumId)
    }

    func continueReadingState() -> ContinueReadingDTO? {
        index.continueReading
    }

    func allImageRefs() throws -> [ImageRef] {
        var refs: [ImageRef] = []
        for author in index.authors {
            guard let albums = index.albumsByAuthor[author.id] else { continue }
            for album in albums {
                let meta = try loadAlbumMeta(authorId: author.id, albumId: album.id)
                for name in meta.images {
                    refs.append(ImageRef(authorId: author.id, albumId: album.id, fileName: name))
                }
            }
        }
        return refs
    }

    func replaceIndex(_ newIndex: IndexFile) throws {
        index = newIndex
        try persistIndex()
    }

    func reloadFromDisk() throws {
        let url = StoragePaths.indexURL(root: storage.rootURL)
        guard let data = storage.readDataIfPresent(at: url) else {
            index = .empty
            return
        }
        index = try decoder.decode(IndexFile.self, from: data)
    }
}

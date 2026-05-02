import Combine
import Foundation
import SwiftUI

@MainActor
final class HoneyBoxEnvironment: ObservableObject {
    private let storage: StorageService
    private let index: IndexService
    private let imageLoader: ImageLoader
    private let importPipeline: ImportService
    private let zip: ZipLibraryService
    private let shuffleImpl: ShuffleManager

    @Published private(set) var librarySnapshot: LibrarySnapshot = .empty

    /// Image loading (thumbnails, full bleed, animated).
    var images: any ImageLoading { imageLoader }

    /// Shuffle gallery queue.
    var shuffle: any ShuffleManaging { shuffleImpl }

    private init(
        storage: StorageService,
        index: IndexService,
        imageLoader: ImageLoader,
        importPipeline: ImportService,
        zip: ZipLibraryService,
        shuffle: ShuffleManager
    ) {
        self.storage = storage
        self.index = index
        self.imageLoader = imageLoader
        self.importPipeline = importPipeline
        self.zip = zip
        self.shuffleImpl = shuffle
    }

    func refreshLibrarySnapshot() async {
        librarySnapshot = await index.snapshot()
    }

    static func bootstrap() async throws -> HoneyBoxEnvironment {
        let storage = try StorageService()
        try storage.ensureLayoutExists()
        let index = try IndexService(storage: storage)
        let imageLoader = ImageLoader(storage: storage)
        let importPipeline = ImportService(storage: storage, index: index, images: imageLoader)
        let zip = ZipLibraryService(storage: storage)
        let shuffle = ShuffleManager(index: index, images: imageLoader)
        let env = HoneyBoxEnvironment(
            storage: storage,
            index: index,
            imageLoader: imageLoader,
            importPipeline: importPipeline,
            zip: zip,
            shuffle: shuffle
        )
        await env.refreshLibrarySnapshot()
        return env
    }

    func invalidateImageCaches() {
        imageLoader.invalidateCaches()
    }

    // MARK: - Library paths (filesystem layout; keep Presentation free of StoragePaths)

    var libraryRootURL: URL { storage.rootURL }

    func authorDirectoryURL(authorId: String) -> URL {
        StoragePaths.authorDirectory(root: storage.rootURL, authorId: authorId)
    }

    func albumDirectoryURL(authorId: String, albumId: String) -> URL {
        StoragePaths.albumDirectory(root: storage.rootURL, authorId: authorId, albumId: albumId)
    }

    func removeLibraryItem(at url: URL) throws {
        try storage.removeItem(at: url)
    }

    // MARK: - Index reads

    func loadAlbumMeta(authorId: String, albumId: String) async throws -> AlbumMetaFile {
        try await index.loadAlbumMeta(authorId: authorId, albumId: albumId)
    }

    // MARK: - Index mutations + snapshot

    func markAlbumOpened(authorId: String, albumId: String) async throws {
        try await index.markAlbumOpened(authorId: authorId, albumId: albumId)
        await refreshLibrarySnapshot()
    }

    func toggleAlbumFavorite(authorId: String, albumId: String) async throws {
        try await index.toggleFavorite(authorId: authorId, albumId: albumId)
        await refreshLibrarySnapshot()
    }

    func deleteAlbumImage(authorId: String, albumId: String, fileName: String) async throws {
        try await index.deleteImage(authorId: authorId, albumId: albumId, fileName: fileName)
        await refreshLibrarySnapshot()
    }

    func setContinueReading(authorId: String, albumId: String, imageIndex: Int) async throws {
        try await index.setContinueReading(authorId: authorId, albumId: albumId, imageIndex: imageIndex)
        await refreshLibrarySnapshot()
    }

    func createAuthor(displayName: String) async throws -> String {
        let id = try await index.createAuthor(displayName: displayName)
        await refreshLibrarySnapshot()
        return id
    }

    func renameAuthor(authorId: String, newName: String) async throws {
        try await index.renameAuthor(authorId: authorId, newName: newName)
        await refreshLibrarySnapshot()
    }

    func deleteAuthorCascade(authorId: String) async throws {
        try await index.deleteAuthorCascade(authorId: authorId)
        await refreshLibrarySnapshot()
    }

    func updateAlbumDisplayTitle(authorId: String, albumId: String, title: String) async throws {
        try await index.updateAlbumDisplayTitle(authorId: authorId, albumId: albumId, title: title)
        await refreshLibrarySnapshot()
    }

    func setAlbumImageOrder(authorId: String, albumId: String, images: [String]) async throws {
        try await index.setAlbumImageOrder(authorId: authorId, albumId: albumId, images: images)
        await refreshLibrarySnapshot()
    }

    func removeAlbumFromLibrary(authorId: String, albumId: String) async throws {
        try await index.removeAlbumSummary(authorId: authorId, albumId: albumId)
        await refreshLibrarySnapshot()
    }

    func setAuthorAvatarFromAlbumImage(authorId: String, albumId: String, fileName: String) async throws {
        let source = imageLoader.imageURL(authorId: authorId, albumId: albumId, fileName: fileName)
        let destName = "avatar.jpg"
        let dest = StoragePaths.authorDirectory(root: storage.rootURL, authorId: authorId)
            .appendingPathComponent(destName, isDirectory: false)
        try storage.copyItem(from: source, to: dest)
        try await index.setAuthorAvatar(authorId: authorId, fileName: destName)
        await refreshLibrarySnapshot()
    }

    // MARK: - Import

    func importFiles(
        authorId: String,
        fileURLs: [URL],
        onProgress: (@MainActor (ImportProgressPhase, Int, Int, String) -> Void)? = nil
    ) async throws -> ImportReport {
        let report = try await importPipeline.importFiles(authorId: authorId, fileURLs: fileURLs, onProgress: onProgress)
        await refreshLibrarySnapshot()
        return report
    }

    func importNewGallery(
        authorId: String,
        displayTitle: String,
        fileURLs: [URL],
        onProgress: (@MainActor (ImportProgressPhase, Int, Int, String) -> Void)? = nil
    ) async throws -> ImportReport {
        let report = try await importPipeline.importNewGallery(
            authorId: authorId,
            displayTitle: displayTitle,
            fileURLs: fileURLs,
            onProgress: onProgress
        )
        await refreshLibrarySnapshot()
        return report
    }

    func appendLooseImages(authorId: String, albumId: String, fileURLs: [URL]) async throws -> ImportReport {
        let report = try await importPipeline.appendLooseImages(authorId: authorId, albumId: albumId, fileURLs: fileURLs)
        await refreshLibrarySnapshot()
        return report
    }

    // MARK: - Backup / restore

    func exportLibrary(
        to url: URL,
        onProgress: (@MainActor (Int, Int, String) -> Void)? = nil
    ) async throws {
        try await zip.exportLibrary(to: url, onProgress: onProgress)
    }

    func restoreLibrary(
        from url: URL,
        onProgress: (@MainActor (ZipRestorePhase, Int, Int, String) -> Void)? = nil
    ) async throws {
        try await zip.restoreLibrary(from: url, indexService: index, onProgress: onProgress)
        invalidateImageCaches()
        await refreshLibrarySnapshot()
    }
}

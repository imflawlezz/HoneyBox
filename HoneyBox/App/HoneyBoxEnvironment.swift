import Combine
import SwiftUI

@MainActor
final class HoneyBoxEnvironment: ObservableObject {
    let storage: StorageService
    let index: IndexService
    let imageLoader: ImageLoader
    let importPipeline: ImportService
    let zip: ZipLibraryService
    let shuffle: ShuffleManager
    let lock: AppLockManager

    @Published private(set) var indexSnapshot: IndexFile = .empty

    private init(
        storage: StorageService,
        index: IndexService,
        imageLoader: ImageLoader,
        importPipeline: ImportService,
        zip: ZipLibraryService,
        shuffle: ShuffleManager,
        lock: AppLockManager
    ) {
        self.storage = storage
        self.index = index
        self.imageLoader = imageLoader
        self.importPipeline = importPipeline
        self.zip = zip
        self.shuffle = shuffle
        self.lock = lock
    }

    func refreshIndex() async {
        indexSnapshot = await index.snapshot()
    }

    static func bootstrap(lock: AppLockManager) async throws -> HoneyBoxEnvironment {
        let storage = try StorageService()
        try storage.ensureLayoutExists()
        let index = try await IndexService(storage: storage)
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
            shuffle: shuffle,
            lock: lock
        )
        await env.refreshIndex()
        return env
    }

    func invalidateImageCaches() {
        imageLoader.invalidateCaches()
    }

    func setAuthorAvatarFromAlbumImage(authorId: String, albumId: String, fileName: String) async throws {
        let source = imageLoader.imageURL(authorId: authorId, albumId: albumId, fileName: fileName)
        let destName = "avatar.jpg"
        let dest = StoragePaths.authorDirectory(root: storage.rootURL, authorId: authorId)
            .appendingPathComponent(destName, isDirectory: false)
        try storage.copyItem(from: source, to: dest)
        try await index.setAuthorAvatar(authorId: authorId, fileName: destName)
        await refreshIndex()
    }
}

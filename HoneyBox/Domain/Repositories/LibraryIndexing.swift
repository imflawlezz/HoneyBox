import Foundation

/// Library index persistence and mutations (JSON index + per-album meta on disk).
protocol LibraryIndexing: Actor {
    nonisolated static func globalAlbumKey(authorId: String, albumId: String) -> String

    func snapshot() -> IndexFile
    func author(withId id: String) -> AuthorSummaryDTO?
    func albums(for authorId: String, sort: AlbumsSortOrder, filter: AlbumsFilter) -> [AlbumSummaryDTO]
    func isFavorite(authorId: String, albumId: String) -> Bool
    func albumSummary(authorId: String, albumId: String) -> AlbumSummaryDTO?

    func loadAlbumMeta(authorId: String, albumId: String) throws -> AlbumMetaFile
    func saveAlbumMeta(_ meta: AlbumMetaFile, authorId: String, albumId: String) throws
    func loadAuthorMeta(authorId: String) throws -> AuthorMetaFile
    func saveAuthorMeta(_ meta: AuthorMetaFile, authorId: String) throws

    func createAuthor(displayName: String) throws -> String
    func renameAuthor(authorId: String, newName: String) throws
    func setAuthorAvatar(authorId: String, fileName: String) throws
    func deleteAuthorCascade(authorId: String) throws

    func upsertAlbumSummary(_ summary: AlbumSummaryDTO, authorId: String) throws
    func addOrUpdateAlbumSummary(_ summary: AlbumSummaryDTO, authorId: String) throws
    func removeAlbumSummary(authorId: String, albumId: String) throws

    func touchRecentlyAdded(authorId: String, albumId: String) throws
    func toggleFavorite(authorId: String, albumId: String) throws
    func markAlbumOpened(authorId: String, albumId: String) throws
    func setContinueReading(authorId: String, albumId: String, imageIndex: Int) throws
    func clearContinueReading() throws

    func updateAlbumDisplayTitle(authorId: String, albumId: String, title: String) throws
    func updateAlbumSummaryFromMeta(authorId: String, albumId: String) throws
    func deleteImage(authorId: String, albumId: String, fileName: String) throws
    func setAlbumImageOrder(authorId: String, albumId: String, images: [String]) throws

    func continueReadingState() -> ContinueReadingDTO?
    func allImageRefs() throws -> [ImageRef]
    func replaceIndex(_ newIndex: IndexFile) throws
    func reloadFromDisk() throws
}

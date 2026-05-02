import Foundation

/// Pure path helpers; safe from any isolation domain (actors, background tasks).
enum StoragePaths: Sendable {
    nonisolated static let authorsFolderName = "authors"
    nonisolated static let indexFileName = "index.json"
    nonisolated static let albumsFolderName = "albums"
    nonisolated static let imagesFolderName = "images"
    nonisolated static let thumbnailsFolderName = "thumbnails"

    nonisolated static func indexURL(root: URL) -> URL {
        root.appendingPathComponent(indexFileName, isDirectory: false)
    }

    nonisolated static func authorsDirectory(root: URL) -> URL {
        root.appendingPathComponent(authorsFolderName, isDirectory: true)
    }

    nonisolated static func authorDirectory(root: URL, authorId: String) -> URL {
        authorsDirectory(root: root).appendingPathComponent(authorId, isDirectory: true)
    }

    nonisolated static func authorMetaURL(root: URL, authorId: String) -> URL {
        authorDirectory(root: root, authorId: authorId).appendingPathComponent("meta.json", isDirectory: false)
    }

    nonisolated static func albumsDirectory(root: URL, authorId: String) -> URL {
        authorDirectory(root: root, authorId: authorId).appendingPathComponent(albumsFolderName, isDirectory: true)
    }

    nonisolated static func albumDirectory(root: URL, authorId: String, albumId: String) -> URL {
        albumsDirectory(root: root, authorId: authorId).appendingPathComponent(albumId, isDirectory: true)
    }

    nonisolated static func albumMetaURL(root: URL, authorId: String, albumId: String) -> URL {
        albumDirectory(root: root, authorId: authorId, albumId: albumId).appendingPathComponent("meta.json", isDirectory: false)
    }

    nonisolated static func imagesDirectory(root: URL, authorId: String, albumId: String) -> URL {
        albumDirectory(root: root, authorId: authorId, albumId: albumId).appendingPathComponent(imagesFolderName, isDirectory: true)
    }

    nonisolated static func thumbnailsDirectory(root: URL, authorId: String, albumId: String) -> URL {
        albumDirectory(root: root, authorId: authorId, albumId: albumId).appendingPathComponent(thumbnailsFolderName, isDirectory: true)
    }
}

import Foundation

enum StoragePaths {
    static let authorsFolderName = "authors"
    static let indexFileName = "index.json"
    static let albumsFolderName = "albums"
    static let imagesFolderName = "images"
    static let thumbnailsFolderName = "thumbnails"

    static func indexURL(root: URL) -> URL {
        root.appendingPathComponent(indexFileName, isDirectory: false)
    }

    static func authorsDirectory(root: URL) -> URL {
        root.appendingPathComponent(authorsFolderName, isDirectory: true)
    }

    static func authorDirectory(root: URL, authorId: String) -> URL {
        authorsDirectory(root: root).appendingPathComponent(authorId, isDirectory: true)
    }

    static func authorMetaURL(root: URL, authorId: String) -> URL {
        authorDirectory(root: root, authorId: authorId).appendingPathComponent("meta.json", isDirectory: false)
    }

    static func albumsDirectory(root: URL, authorId: String) -> URL {
        authorDirectory(root: root, authorId: authorId).appendingPathComponent(albumsFolderName, isDirectory: true)
    }

    static func albumDirectory(root: URL, authorId: String, albumId: String) -> URL {
        albumsDirectory(root: root, authorId: authorId).appendingPathComponent(albumId, isDirectory: true)
    }

    static func albumMetaURL(root: URL, authorId: String, albumId: String) -> URL {
        albumDirectory(root: root, authorId: authorId, albumId: albumId).appendingPathComponent("meta.json", isDirectory: false)
    }

    static func imagesDirectory(root: URL, authorId: String, albumId: String) -> URL {
        albumDirectory(root: root, authorId: authorId, albumId: albumId).appendingPathComponent(imagesFolderName, isDirectory: true)
    }

    static func thumbnailsDirectory(root: URL, authorId: String, albumId: String) -> URL {
        albumDirectory(root: root, authorId: authorId, albumId: albumId).appendingPathComponent(thumbnailsFolderName, isDirectory: true)
    }
}

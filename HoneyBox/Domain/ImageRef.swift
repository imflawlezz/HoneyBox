import Foundation

struct ImageRef: Codable, Sendable {
    var authorId: String
    var albumId: String
    var fileName: String

    nonisolated var thumbnailFileName: String {
        let base = (fileName as NSString).deletingPathExtension
        if base.hasPrefix("img_") {
            let suffix = String(base.dropFirst("img_".count))
            return "thumb_\(suffix).jpg"
        }
        return "thumb_\(base).jpg"
    }
}

extension ImageRef: Equatable {
    nonisolated static func == (lhs: ImageRef, rhs: ImageRef) -> Bool {
        lhs.authorId == rhs.authorId && lhs.albumId == rhs.albumId && lhs.fileName == rhs.fileName
    }
}

extension ImageRef: Hashable {
    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(authorId)
        hasher.combine(albumId)
        hasher.combine(fileName)
    }
}

extension ImageRef {
    nonisolated static func globalAlbumKey(authorId: String, albumId: String) -> String {
        "\(authorId)/\(albumId)"
    }

    nonisolated var globalAlbumKey: String {
        Self.globalAlbumKey(authorId: authorId, albumId: albumId)
    }
}

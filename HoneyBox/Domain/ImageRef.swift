import Foundation

struct ImageRef: Hashable, Codable, Sendable {
    var authorId: String
    var albumId: String
    var fileName: String

    var thumbnailFileName: String {
        let ext = (fileName as NSString).pathExtension.lowercased()
        let base = (fileName as NSString).deletingPathExtension
        if base.hasPrefix("img_") {
            let suffix = String(base.dropFirst("img_".count))
            return "thumb_\(suffix).jpg"
        }
        return "thumb_\(base).jpg"
    }
}

extension ImageRef {
    static func globalAlbumKey(authorId: String, albumId: String) -> String {
        "\(authorId)/\(albumId)"
    }

    var globalAlbumKey: String {
        Self.globalAlbumKey(authorId: authorId, albumId: albumId)
    }
}

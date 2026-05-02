import Foundation

struct HomeNavSelection: Identifiable, Hashable {
    enum Kind: Hashable {
        case albumDetail(authorId: String, authorName: String, albumId: String, albumTitle: String)
        case viewerEntry(authorId: String, authorName: String, albumId: String, albumTitle: String, startIndex: Int)
    }

    let kind: Kind

    var id: String {
        switch kind {
        case .albumDetail(let authorId, _, let albumId, _):
            return "album:\(authorId)/\(albumId)"
        case .viewerEntry(let authorId, _, let albumId, _, let startIndex):
            return "viewer:\(authorId)/\(albumId)#\(startIndex)"
        }
    }
}


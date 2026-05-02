import Foundation

enum AlbumsSortOrder: Sendable {
    case latestFirst
    case oldestFirst
}

enum AlbumsFilter: Sendable {
    case all
    case favoritesOnly
    case notViewedOnly
}

import Foundation

/// Pure queries over a library snapshot (published UI read model).
enum LibraryBrowseQueries {
    static func homeLatestAlbums(_ snapshot: LibrarySnapshot, limit: Int) -> [(authorId: String, summary: AlbumSummaryDTO)] {
        let keys = snapshot.recentlyAdded.prefix(limit)
        var out: [(String, AlbumSummaryDTO)] = []
        for entry in keys {
            if let s = albumSummary(snapshot, authorId: entry.authorId, albumId: entry.albumId) {
                out.append((entry.authorId, s))
            }
        }
        return out
    }

    static func homeFavoriteAlbums(_ snapshot: LibrarySnapshot, limit: Int) -> [(authorId: String, summary: AlbumSummaryDTO)] {
        var out: [(String, AlbumSummaryDTO)] = []
        for key in snapshot.favoriteAlbums {
            let parts = key.split(separator: "/", maxSplits: 1).map(String.init)
            guard parts.count == 2,
                  let s = albumSummary(snapshot, authorId: parts[0], albumId: parts[1]) else { continue }
            out.append((parts[0], s))
            if out.count >= limit { break }
        }
        return out
    }

    static func homeNotViewedAlbums(_ snapshot: LibrarySnapshot, limit: Int) -> [(authorId: String, summary: AlbumSummaryDTO)] {
        var collected: [(String, AlbumSummaryDTO)] = []
        for author in snapshot.authors {
            guard let albums = snapshot.albumsByAuthor[author.id] else { continue }
            for a in albums where a.lastOpenedAt == nil {
                collected.append((author.id, a))
            }
        }
        collected.sort { $0.1.updatedAt > $1.1.updatedAt }
        return Array(collected.prefix(limit))
    }

    private static func albumSummary(_ snapshot: LibrarySnapshot, authorId: String, albumId: String) -> AlbumSummaryDTO? {
        snapshot.albumsByAuthor[authorId]?.first { $0.id == albumId }
    }
}

struct HomeContinueReadingItem: Identifiable {
    var id: String { "\(authorId)/\(album.id)" }
    let authorId: String
    let authorName: String
    let album: AlbumSummaryDTO
    let startIndex: Int

    static func items(from snapshot: LibrarySnapshot, limit: Int) -> [HomeContinueReadingItem] {
        guard !snapshot.recentlyViewed.isEmpty else { return [] }
        var out: [HomeContinueReadingItem] = []
        out.reserveCapacity(min(limit, snapshot.recentlyViewed.count))

        for entry in snapshot.recentlyViewed.prefix(limit) {
            guard let author = snapshot.authors.first(where: { $0.id == entry.authorId }),
                  let album = snapshot.albumsByAuthor[entry.authorId]?.first(where: { $0.id == entry.albumId }) else {
                continue
            }
            let key = ImageRef.globalAlbumKey(authorId: entry.authorId, albumId: entry.albumId)
            let startIndex = snapshot.continueReadingProgress[key] ?? 0
            out.append(
                HomeContinueReadingItem(
                    authorId: entry.authorId,
                    authorName: author.name,
                    album: album,
                    startIndex: startIndex
                )
            )
        }
        return out
    }
}

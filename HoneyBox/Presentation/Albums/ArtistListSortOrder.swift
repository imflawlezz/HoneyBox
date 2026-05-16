import Foundation

enum ArtistListSortOrder: String, CaseIterable, Identifiable {
    case nameAscending
    case nameDescending
    case recentUpdatesDescending

    var id: String { rawValue }

    var menuTitle: String {
        switch self {
        case .nameAscending: "Name (A–Z)"
        case .nameDescending: "Name (Z–A)"
        case .recentUpdatesDescending: "Gallery updates"
        }
    }

    func sorted(_ authors: [AuthorSummaryDTO], snapshot: LibrarySnapshot) -> [AuthorSummaryDTO] {
        switch self {
        case .nameAscending:
            return authors.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        case .nameDescending:
            return authors.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedDescending
            }
        case .recentUpdatesDescending:
            return authors.sorted { a, b in
                let ua = Self.latestGalleryUpdate(authorId: a.id, snapshot: snapshot)
                let ub = Self.latestGalleryUpdate(authorId: b.id, snapshot: snapshot)
                if ua != ub { return ua > ub }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
        }
    }

    private static func latestGalleryUpdate(authorId: String, snapshot: LibrarySnapshot) -> Date {
        (snapshot.albumsByAuthor[authorId] ?? []).map(\.updatedAt).max() ?? .distantPast
    }
}

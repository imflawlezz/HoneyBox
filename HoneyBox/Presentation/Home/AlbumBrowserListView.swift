import SwiftUI

struct AlbumBrowserListView: View {
    @ObservedObject var env: HoneyBoxEnvironment
    let title: String
    let items: [HomeAlbumItem]

    @State private var navSelection: HomeNavSelection?

    var body: some View {
        Group {
            if items.isEmpty {
                ContentUnavailableView(emptyTitle, systemImage: emptySymbol, description: Text(emptyMessage))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(items) { item in
                            if let author = env.indexSnapshot.authors.first(where: { $0.id == item.authorId }) {
                                Button {
                                    navSelection = HomeNavSelection(
                                        kind: .albumDetail(
                                            authorId: item.authorId,
                                            authorName: author.name,
                                            albumId: item.album.id,
                                            albumTitle: item.album.displayTitle
                                        )
                                    )
                                } label: {
                                    AlbumCardRow(
                                        env: env,
                                        authorId: item.authorId,
                                        authorName: author.name,
                                        album: item.album
                                    )
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 24)
                }
            }
        }
        .navigationTitle(title)
        .navigationDestination(item: $navSelection) { sel in
            switch sel.kind {
            case .albumDetail(let authorId, let authorName, let albumId, let albumTitle):
                AlbumDetailView(
                    env: env,
                    authorId: authorId,
                    authorName: authorName,
                    albumId: albumId,
                    albumTitle: albumTitle
                )
            case .viewerEntry(let authorId, let authorName, let albumId, let albumTitle, let startIndex):
                ImageViewerEntryView(
                    env: env,
                    authorId: authorId,
                    authorName: authorName,
                    albumId: albumId,
                    albumTitle: albumTitle,
                    startIndex: startIndex
                )
                .id("\(authorId)/\(albumId)-\(startIndex)")
            }
        }
    }

    private var emptySymbol: String {
        switch title {
        case "Latest Galleries":
            return "tray.and.arrow.down"
        case "Favorite Galleries":
            return "heart"
        case "Not Viewed":
            return "eye"
        default:
            return "photo.on.rectangle.angled"
        }
    }

    private var emptyTitle: String {
        switch title {
        case "Latest Galleries":
            return "Nothing imported yet"
        case "Favorite Galleries":
            return "No favorites yet"
        case "Not Viewed":
            return "All caught up"
        default:
            return "Nothing here"
        }
    }

    private var emptyMessage: String {
        switch title {
        case "Latest Galleries":
            return "Import numbered files first to create galleries."
        case "Favorite Galleries":
            return "Tap the heart on an album to add it to favorites."
        case "Not Viewed":
            return "You have viewed all albums. Good job!"
        default:
            return "Try importing content first."
        }
    }
}

private struct AlbumCardRow: View {
    @ObservedObject var env: HoneyBoxEnvironment
    let authorId: String
    let authorName: String
    let album: AlbumSummaryDTO

    @Environment(\.displayScale) private var displayScale
    @State private var cg: CGImage?

    var body: some View {
        ZStack {
            Color(.secondarySystemFill)
            if let cg {
                Image(decorative: cg, scale: displayScale, orientation: .up)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            }
        }
        .frame(height: 128)
        .overlay {
            Color.black.opacity(0.25)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .bottom) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(authorName)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.88))
                    Text(album.displayTitle)
                        .font(.headline)
                        .foregroundStyle(.white)
                }
                Spacer()
                HStack(spacing: 6) {
                    Text("\(album.imageCount) Photos")
                        .font(.footnote)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                }
                .foregroundStyle(.white.opacity(0.9))
            }
            .padding(16)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .task(id: "\(authorId)-\(album.id)-\(album.coverThumbnailFileName ?? "")") {
            guard let name = album.coverThumbnailFileName else {
                cg = nil
                return
            }
            cg = try? await env.imageLoader.loadThumbnailCGImage(
                authorId: authorId,
                albumId: album.id,
                thumbFileName: name,
                decodeMaxEdge: 900
            )
        }
    }
}

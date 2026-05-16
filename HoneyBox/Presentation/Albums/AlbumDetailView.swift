import SwiftUI

struct AlbumDetailView: View {
    @ObservedObject var env: HoneyBoxEnvironment
    let authorId: String
    let authorName: String
    let albumId: String
    let albumTitle: String

    @State private var meta: AlbumMetaFile?
    @State private var viewerSelection: ViewerSelection?
    @State private var immersiveSelection: ImmersiveSelection?
    private var isFavorite: Bool {
        env.librarySnapshot.favoriteAlbums.contains(ImageRef.globalAlbumKey(authorId: authorId, albumId: albumId))
    }

    private var resolvedAlbumTitle: String {
        env.librarySnapshot.albumsByAuthor[authorId]?.first(where: { $0.id == albumId })?.displayTitle
            ?? meta?.displayTitle
            ?? albumTitle
    }

    var body: some View {
        mainContent
        .navigationTitle("\(resolvedAlbumTitle) by \(authorName)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text("\(resolvedAlbumTitle) by \(authorName)")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text("\((meta?.images.count ?? 0)) Photos")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await toggleFavorite() }
                } label: {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .foregroundStyle(isFavorite ? Color.red : Color.primary)
                }
                .tint(.primary)
                .accessibilityLabel(isFavorite ? "Unfavorite album" : "Favorite album")
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    AlbumEditView(env: env, authorId: authorId, authorName: authorName, albumId: albumId, albumTitle: resolvedAlbumTitle)
                } label: {
                    Image(systemName: "square.and.pencil")
                        .foregroundStyle(.primary)
                }
                .tint(.primary)
                .accessibilityLabel("Edit album")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    immersiveSelection = ImmersiveSelection(startIndex: 0)
                } label: {
                    Image(systemName: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .clipShape(Circle())
                .accessibilityLabel("Play")
            }
        }
        .task { await load() }
        .navigationDestination(item: $viewerSelection) { selection in
            let names = meta?.images ?? []
            ImageViewerShell(
                env: env,
                authorId: authorId,
                authorName: authorName,
                albumId: albumId,
                albumTitle: resolvedAlbumTitle,
                imageNames: names,
                startIndex: selection.startIndex
            )
        }
        .fullScreenCover(item: $immersiveSelection) { selection in
            let names = meta?.images ?? []
            ImmersiveViewerShell(
                env: env,
                authorId: authorId,
                authorName: authorName,
                albumId: albumId,
                albumTitle: resolvedAlbumTitle,
                imageNames: names,
                startIndex: selection.startIndex
            )
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        if let meta, !meta.images.isEmpty {
            albumGrid(meta: meta)
        } else {
            EmptyStateView(systemImage: "photo", title: "Empty album", message: "Import images or add files from edit mode.")
        }
    }

    private func albumGrid(meta: AlbumMetaFile) -> some View {
        let horizontalPadding: CGFloat = 12
        return GeometryReader { geo in
            let contentWidth = max(0, geo.size.width - horizontalPadding * 2)
            ScrollView {
                if contentWidth > 0 {
                    let spacing: CGFloat = 6
                    let tile = floor((contentWidth - spacing * 2) / 3)
                    let columns = Array(repeating: GridItem(.fixed(tile), spacing: spacing), count: 3)

                    LazyVGrid(columns: columns, spacing: spacing) {
                        ForEach(Array(meta.images.enumerated()), id: \.offset) { index, name in
                            Button {
                                viewerSelection = ViewerSelection(startIndex: index)
                            } label: {
                                AlbumImageThumbCell(
                                    env: env,
                                    authorId: authorId,
                                    albumId: albumId,
                                    fileName: name,
                                    decodeMaxEdge: 720
                                )
                                .frame(width: tile, height: tile)
                                .clipped()
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, 6)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
    }

    private func load() async {
        do {
            try await env.markAlbumOpened(authorId: authorId, albumId: albumId)
            let m = try await env.loadAlbumMeta(authorId: authorId, albumId: albumId)
            await MainActor.run { meta = m }
        } catch {
            await MainActor.run { meta = nil }
        }
    }

    private func toggleFavorite() async {
        do {
            try await env.toggleAlbumFavorite(authorId: authorId, albumId: albumId)
        } catch {}
    }
}

private struct ViewerSelection: Identifiable, Hashable {
    let id = UUID()
    let startIndex: Int
}

private struct ImmersiveSelection: Identifiable {
    let id = UUID()
    let startIndex: Int
}


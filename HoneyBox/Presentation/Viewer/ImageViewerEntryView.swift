import SwiftUI

struct ImageViewerEntryView: View {
    @ObservedObject var env: HoneyBoxEnvironment
    let authorId: String
    let authorName: String
    let albumId: String
    let albumTitle: String
    let startIndex: Int

    @State private var names: [String] = []
    @State private var failed = false

    var body: some View {
        Group {
            if failed {
                EmptyStateView(systemImage: "exclamationmark.triangle", title: "Could not load album", message: "Try again from the album list.")
            } else if names.isEmpty {
                ProgressView()
            } else {
                ImageViewerShell(
                    env: env,
                    authorId: authorId,
                    authorName: authorName,
                    albumId: albumId,
                    albumTitle: albumTitle,
                    imageNames: names,
                    startIndex: startIndex
                )
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await load()
        }
    }

    private func load() async {
        do {
            try await env.index.markAlbumOpened(authorId: authorId, albumId: albumId)
            await env.refreshIndex()
            let meta = try await env.index.loadAlbumMeta(authorId: authorId, albumId: albumId)
            await MainActor.run { names = meta.images }
        } catch {
            await MainActor.run { failed = true }
        }
    }
}

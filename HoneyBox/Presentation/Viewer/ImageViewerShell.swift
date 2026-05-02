import SwiftUI

struct ImageViewerShell: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var env: HoneyBoxEnvironment
    let authorId: String
    let authorName: String
    let albumId: String
    let albumTitle: String

    @State private var names: [String]
    @State private var index: Int
    @State private var scrollPosition: Int?
    @State private var showImmersive = false
    @State private var showDeleteConfirm = false
    @State private var chromeHidden: Bool = false
    @State private var lockHorizontalPaging = false

    init(
        env: HoneyBoxEnvironment,
        authorId: String,
        authorName: String,
        albumId: String,
        albumTitle: String,
        imageNames: [String],
        startIndex: Int
    ) {
        self.env = env
        self.authorId = authorId
        self.authorName = authorName
        self.albumId = albumId
        self.albumTitle = albumTitle
        _names = State(initialValue: imageNames)
        let initial = min(startIndex, max(0, imageNames.count - 1))
        _index = State(initialValue: initial)
        _scrollPosition = State(initialValue: initial)
    }

    private var isFavorite: Bool {
        env.indexSnapshot.favoriteAlbums.contains(ImageRef.globalAlbumKey(authorId: authorId, albumId: albumId))
    }

    private var currentFileName: String? {
        names.indices.contains(index) ? names[index] : nil
    }

    var body: some View {
        GeometryReader { geo in
            let activePage = scrollPosition ?? index
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView(.horizontal) {
                    LazyHStack(spacing: 0) {
                        ForEach(Array(names.enumerated()), id: \.offset) { i, name in
                            ImagePageView(
                                env: env,
                                ref: ImageRef(authorId: authorId, albumId: albumId, fileName: name),
                                isActivePage: i == activePage,
                                parentScrollLocked: $lockHorizontalPaging
                            )
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                            .id(i)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .scrollTargetLayout()
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $scrollPosition)
                .scrollDisabled(lockHorizontalPaging)
                .onChange(of: scrollPosition) { _, newValue in
                    guard let newValue else { return }
                    index = min(max(newValue, 0), max(0, names.count - 1))
                }
            }
            .contentShape(Rectangle())
            .simultaneousGesture(
                TapGesture().onEnded {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        chromeHidden.toggle()
                    }
                }
            )
            .onAppear {
                scrollPosition = index
            }
        }
        .ignoresSafeArea()
        .toolbar(.hidden, for: .tabBar)
        .toolbar(chromeHidden ? .hidden : .visible, for: .navigationBar)
        .statusBarHidden(chromeHidden)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text("\(albumTitle) by \(authorName)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text("\(index + 1) / \(max(names.count, 1))")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await toggleFavorite() }
                } label: {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .foregroundStyle(isFavorite ? Color.red : Color.white)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isFavorite ? "Unfavorite album" : "Favorite album")
                .disabled(names.isEmpty)
            }

            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        Task { await setAsAvatar() }
                    } label: {
                        Label("Set as artist avatar", systemImage: "person.crop.circle")
                            .symbolRenderingMode(.monochrome)
                    }
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("Delete photo", systemImage: "trash")
                            .symbolRenderingMode(.monochrome)
                            .foregroundStyle(.red)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .tint(.primary)
                .accessibilityLabel("More")
                .disabled(names.isEmpty)
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showImmersive = true
                } label: {
                    Image(systemName: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
                .clipShape(Circle())
                .accessibilityLabel("Play")
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .confirmationDialog("Delete photo?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete photo", role: .destructive) {
                Task { await deleteCurrentPhoto() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the photo from this device.")
        }
        .task { await persistContinueReading(index) }
        .onChange(of: index) { _, newValue in
            Task { await persistContinueReading(newValue) }
        }
        .fullScreenCover(isPresented: $showImmersive, onDismiss: {
            dismiss()
        }) {
            ImmersiveViewerShell(
                env: env,
                authorId: authorId,
                authorName: authorName,
                albumId: albumId,
                albumTitle: albumTitle,
                imageNames: names,
                startIndex: index
            )
        }
    }

    private func toggleFavorite() async {
        do {
            try await env.index.toggleFavorite(authorId: authorId, albumId: albumId)
            await env.refreshIndex()
        } catch {}
    }

    private func setAsAvatar() async {
        guard let fileName = currentFileName else { return }
        do {
            try await env.setAuthorAvatarFromAlbumImage(authorId: authorId, albumId: albumId, fileName: fileName)
        } catch {}
    }

    private func deleteCurrentPhoto() async {
        guard let fileName = currentFileName else { return }
        do {
            try await env.index.deleteImage(authorId: authorId, albumId: albumId, fileName: fileName)
            await env.refreshIndex()
            await MainActor.run {
                names.removeAll { $0 == fileName }
                index = min(index, max(0, names.count - 1))
                scrollPosition = index
            }
            if names.isEmpty {
                dismiss()
            }
        } catch {}
    }

    private func persistContinueReading(_ value: Int) async {
        guard !names.isEmpty else { return }
        do {
            try await env.index.setContinueReading(authorId: authorId, albumId: albumId, imageIndex: value)
            await env.refreshIndex()
        } catch {}
    }
}

private struct ImagePageView: View {
    @ObservedObject var env: HoneyBoxEnvironment
    let ref: ImageRef
    let isActivePage: Bool
    @Binding var parentScrollLocked: Bool
    @State private var still: CGImage?
    @State private var gif: AnimatedGIF?

    var body: some View {
        Group {
            if let gif {
                ZoomableGifView(gif: gif, playbackID: ref.fileName, isActive: isActivePage, parentScrollLocked: $parentScrollLocked)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .id(ref.fileName)
            } else if let still {
                ZoomableImageView(cgImage: still, isActive: isActivePage, parentScrollLocked: $parentScrollLocked)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .id(ref.fileName)
            } else {
                ProgressView().tint(.white)
            }
        }
        .task(id: ref.fileName) { await load() }
    }

    private func load() async {
        let ext = (ref.fileName as NSString).pathExtension.lowercased()
        if ImageLoader.supportsAnimatedPlaybackExtension(ext), let g = try? await env.imageLoader.loadAnimatedRaster(ref: ref) {
            do { try Task.checkCancellation() } catch { return }
            await MainActor.run {
                gif = g
                still = nil
            }
            return
        }
        let cg = try? await env.imageLoader.loadFullCGImage(ref: ref)
        do { try Task.checkCancellation() } catch { return }
        await MainActor.run {
            still = cg
            gif = nil
        }
    }
}


import SwiftUI

struct ImmersiveShuffleViewerShell: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var env: HoneyBoxEnvironment

    @AppStorage("immersiveSlideshowIntervalSeconds") private var intervalSeconds: Double = 2.5
    @State private var history: [ImageRef] = []
    @State private var cursor: Int = 0
    @State private var displayedStill: CGImage?
    @State private var displayedGIF: AnimatedGIF?
    @State private var displayedFileName: String?
    @State private var isPlaying: Bool = true
    @State private var isHolding: Bool = false
    @State private var toastTask: Task<Void, Never>?
    @State private var showToast: Bool = false
    @State private var toastText: String = ""
    @State private var albumDestination: ImmersiveOpenedAlbum?
    @State private var resumeSlideshowAfterAlbum = false
    @State private var sessionInitialized = false
    @State private var isBootstrapping = true

    private var current: ImageRef? {
        history.indices.contains(cursor) ? history[cursor] : nil
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ZStack {
                    Color.black.ignoresSafeArea()

                    if isBootstrapping {
                        ProgressView()
                            .controlSize(.large)
                            .tint(.white)
                    } else if let current {
                        Group {
                            if let displayedGIF {
                                GifPlaybackView(gif: displayedGIF, playbackID: displayedFileName ?? current.fileName)
                                    .frame(width: geo.size.width, height: geo.size.height)
                            } else if let displayedStill {
                                ZStack {
                                    Image(decorative: displayedStill, scale: displayScale, orientation: .up)
                                        .resizable()
                                        .interpolation(.low)
                                        .scaledToFill()
                                        .blur(radius: 26)
                                        .opacity(0.85)
                                        .frame(width: geo.size.width, height: geo.size.height)
                                        .clipped()
                                        .allowsHitTesting(false)

                                    Image(decorative: displayedStill, scale: displayScale, orientation: .up)
                                        .resizable()
                                        .interpolation(.high)
                                        .scaledToFit()
                                        .frame(width: geo.size.width)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                                }
                                .frame(width: geo.size.width, height: geo.size.height)
                            } else {
                                ProgressView().tint(.white)
                            }
                        }
                        .frame(width: geo.size.width, height: geo.size.height)
                        .task(id: current.fileName) {
                            await loadCurrent(current)
                        }
                    } else {
                        EmptyStateView(
                            systemImage: "shuffle",
                            title: "Nothing to shuffle",
                            message: "Import images first, then open shuffle from Home."
                        )
                        .padding()
                    }

                    VStack(spacing: 0) {
                        Color.clear
                            .frame(height: geo.safeAreaInsets.top + 64)
                        HStack(spacing: 0) {
                            Color.clear
                                .frame(width: geo.size.width / 2)
                                .contentShape(Rectangle())
                                .onTapGesture { Task { await nextTapped() } }
                            Color.clear
                                .frame(width: geo.size.width / 2)
                                .contentShape(Rectangle())
                                .onTapGesture { previousTapped() }
                        }
                        Spacer(minLength: 0)
                    }
                    .ignoresSafeArea()
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.35, maximumDistance: 30)
                            .onChanged { _ in isHolding = true }
                            .onEnded { _ in isHolding = false }
                    )

                    if showToast {
                        Text(toastText)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial.opacity(0.7))
                            .clipShape(Capsule(style: .continuous))
                            .overlay {
                                Capsule(style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.7)
                            }
                            .shadow(color: Color.black.opacity(0.35), radius: 18, x: 0, y: 8)
                            .padding(.bottom, 48)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
            }
            .ignoresSafeArea()
            .statusBarHidden(true)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.backward")
                            .symbolRenderingMode(.monochrome)
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { isPlaying.toggle() } label: {
                        Image(systemName: isPlaying ? "pause" : "play")
                            .symbolRenderingMode(.monochrome)
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if let current,
                       let author = env.librarySnapshot.authors.first(where: { $0.id == current.authorId }) {
                        Button {
                            isPlaying = false
                            resumeSlideshowAfterAlbum = true
                            albumDestination = ImmersiveOpenedAlbum(
                                authorId: current.authorId,
                                authorName: author.name,
                                albumId: current.albumId,
                                albumTitle: env.librarySnapshot.albumsByAuthor[current.authorId]?.first(where: { $0.id == current.albumId })?.displayTitle ?? current.albumId
                            )
                        } label: {
                            Image(systemName: "rectangle.stack")
                                .symbolRenderingMode(.monochrome)
                                .foregroundStyle(.primary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Open album")
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationDestination(item: $albumDestination) { dest in
                AlbumDetailView(
                    env: env,
                    authorId: dest.authorId,
                    authorName: dest.authorName,
                    albumId: dest.albumId,
                    albumTitle: dest.albumTitle
                )
            }
            .task {
                guard !sessionInitialized else { return }
                await bootstrapSession()
            }
            .task(id: slideshowKey) {
                guard isPlaying else { return }
                while isPlaying, !Task.isCancelled {
                    let clamped = min(max(intervalSeconds, 0.2), 30)
                    try? await Task.sleep(nanoseconds: UInt64(clamped * 1_000_000_000))
                    guard isPlaying, !isHolding else { continue }
                    await nextAuto()
                }
            }
        }
        .disablesIdleTimerWhilePresented()
        .onChange(of: albumDestination) { _, new in
            if new == nil, resumeSlideshowAfterAlbum {
                resumeSlideshowAfterAlbum = false
                isPlaying = true
            }
        }
    }

    @Environment(\.displayScale) private var displayScale

    private var slideshowKey: String {
        "\(isPlaying)-\(intervalSeconds)"
    }

    private func bootstrapSession() async {
        await MainActor.run { isBootstrapping = true }
        do {
            try await env.shuffle.reset()
            if let cur = await env.shuffle.current() {
                await MainActor.run {
                    history = [cur]
                    cursor = 0
                }
                await env.shuffle.preloadAroundCurrent(ahead: 20, behind: 2)
                await loadCurrent(cur)
            } else {
                await MainActor.run {
                    history = []
                    cursor = 0
                }
            }
        } catch {
            await MainActor.run {
                history = []
                cursor = 0
            }
        }
        await MainActor.run {
            isBootstrapping = false
            sessionInitialized = true
        }
    }

    private func previousTapped() {
        isPlaying = false
        isHolding = false
        guard cursor > 0 else { return }
        cursor -= 1
        if let cur = current {
            Task { await loadCurrent(cur) }
        }
    }

    private func nextTapped() async {
        isPlaying = false
        isHolding = false
        await nextStep()
    }

    private func nextAuto() async {
        await nextStep()
    }

    private func nextStep() async {
        if cursor + 1 < history.count {
            await MainActor.run { cursor += 1 }
            if let cur = current { await loadCurrent(cur) }
            return
        }
        do {
            if let next = try await env.shuffle.advance() {
                await MainActor.run {
                    history.append(next)
                    cursor += 1
                }
                await env.shuffle.preloadAroundCurrent(ahead: 20, behind: 2)
                await loadCurrent(next)
            }
        } catch {}
    }

    private func loadCurrent(_ ref: ImageRef) async {
        let requestedFileName = ref.fileName
        let ext = (ref.fileName as NSString).pathExtension.lowercased()
        if ImageLoader.supportsAnimatedPlaybackExtension(ext), let g = try? await env.images.loadAnimatedRaster(ref: ref) {
            do { try Task.checkCancellation() } catch { return }
            await MainActor.run {
                guard history.indices.contains(cursor), history[cursor].fileName == requestedFileName else { return }
                displayedGIF = g
                displayedStill = nil
                displayedFileName = requestedFileName
            }
            return
        }
        let cg = try? await env.images.loadFullCGImage(ref: ref)
        do { try Task.checkCancellation() } catch { return }
        await MainActor.run {
            guard history.indices.contains(cursor), history[cursor].fileName == requestedFileName else { return }
            displayedStill = cg
            displayedGIF = nil
            displayedFileName = requestedFileName
        }
    }

    private func toast(_ text: String) {
        toastText = text
        toastTask?.cancel()
        withAnimation(.easeInOut(duration: 0.35)) { showToast = true }
        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            withAnimation(.easeInOut(duration: 0.35)) { showToast = false }
        }
    }

}

private struct ImmersiveOpenedAlbum: Identifiable, Hashable {
    var id: String { "\(authorId)/\(albumId)" }
    let authorId: String
    let authorName: String
    let albumId: String
    let albumTitle: String
}

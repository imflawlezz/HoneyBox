import SwiftUI

struct ImmersiveViewerShell: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var env: HoneyBoxEnvironment
    let authorId: String
    let authorName: String
    let albumId: String
    let albumTitle: String
    let imageNames: [String]
    let startIndex: Int

    @AppStorage("immersiveSlideshowIntervalSeconds") private var intervalSeconds: Double = 2.5
    @State private var index: Int
    @State private var isPlaying: Bool = true
    @State private var isHolding: Bool = false
    @State private var showToast: Bool = false
    @State private var toastText: String = ""
    @State private var toastTask: Task<Void, Never>?

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
        self.imageNames = imageNames
        self.startIndex = startIndex
        _index = State(initialValue: min(startIndex, max(0, imageNames.count - 1)))
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ZStack {
                    Color.black.ignoresSafeArea()

                    if imageNames.indices.contains(index) {
                        let name = imageNames[index]
                        ImmersiveImagePage(
                            env: env,
                            ref: ImageRef(authorId: authorId, albumId: albumId, fileName: name)
                        )
                        .frame(width: geo.size.width, height: geo.size.height)
                    }

                    // Tap zones (exclude top toolbar so buttons always get taps).
                    VStack(spacing: 0) {
                        Color.clear
                            .frame(height: geo.safeAreaInsets.top + 64)
                        HStack(spacing: 0) {
                            Color.clear
                                .frame(width: geo.size.width / 2)
                                .contentShape(Rectangle())
                                .onTapGesture { next() }
                            Color.clear
                                .frame(width: geo.size.width / 2)
                                .contentShape(Rectangle())
                                .onTapGesture { previous() }
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
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .disablesIdleTimerWhilePresented()
        .task(id: slideshowKey) {
            guard isPlaying, !imageNames.isEmpty else { return }
            while isPlaying, !Task.isCancelled {
                let clamped = min(max(intervalSeconds, 0.2), 30)
                try? await Task.sleep(nanoseconds: UInt64(clamped * 1_000_000_000))
                guard isPlaying, !isHolding, !imageNames.isEmpty else { continue }
                await MainActor.run { advanceForward(showEndToast: true) }
            }
        }
    }

    private var slideshowKey: String {
        "\(isPlaying)-\(intervalSeconds)"
    }

    private func next() {
        guard !imageNames.isEmpty else { return }
        isPlaying = false
        isHolding = false
        advanceForward(showEndToast: true)
    }

    private func previous() {
        guard !imageNames.isEmpty else { return }
        isPlaying = false
        isHolding = false
        index = (index - 1 + imageNames.count) % imageNames.count
    }

    private func advanceForward(showEndToast: Bool) {
        guard !imageNames.isEmpty else { return }
        let last = max(0, imageNames.count - 1)
        if index >= last {
            if showEndToast {
                toast("End of gallery")
            }
            index = 0
            return
        }
        index += 1
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


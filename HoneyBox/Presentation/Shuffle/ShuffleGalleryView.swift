import SwiftUI

struct ShuffleGalleryView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var env: HoneyBoxEnvironment
    @State private var current: ImageRef?
    @State private var still: CGImage?
    @State private var gif: AnimatedGIF?
    @State private var chromeHidden = false
    @State private var positionLabel = "0 / 0"
    @State private var zoomLocksNavigation = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let current {
                Group {
                    if let gif {
                        ZoomableGifView(gif: gif, playbackID: current.fileName, parentScrollLocked: $zoomLocksNavigation)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let still {
                        ZoomableImageView(cgImage: still, parentScrollLocked: $zoomLocksNavigation)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ProgressView().tint(.white)
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 24)
                        .onEnded { value in
                            guard !zoomLocksNavigation else { return }
                            if value.translation.width < -40 {
                                Task { await advance() }
                            }
                        }
                )
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        chromeHidden.toggle()
                    }
                }
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

            if !chromeHidden, current != nil {
                VStack {
                    HStack {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "chevron.backward.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.white)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    Spacer()
                    Text(positionLabel)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.accentColor.opacity(0.9), in: Capsule())
                        .padding(.bottom, 32)
                }
                .transition(.opacity)
            }
        }
        .navigationTitle("Shuffle")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .task {
            await start()
        }
    }

    private func start() async {
        do {
            try await env.shuffle.reset()
            current = await env.shuffle.current()
            positionLabel = await env.shuffle.positionLabel()
            await env.shuffle.preloadAroundCurrent()
        } catch {
            current = nil
        }
    }

    private func advance() async {
        do {
            current = try await env.shuffle.advance()
            positionLabel = await env.shuffle.positionLabel()
            await env.shuffle.preloadAroundCurrent()
            still = nil
            gif = nil
        } catch {}
    }

    private func loadCurrent(_ ref: ImageRef) async {
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

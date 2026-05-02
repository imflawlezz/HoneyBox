import SwiftUI

struct ImmersiveImagePage: View {
    @ObservedObject var env: HoneyBoxEnvironment
    let ref: ImageRef
    @Environment(\.displayScale) private var displayScale

    @State private var displayedStill: CGImage?
    @State private var displayedGIF: AnimatedGIF?
    @State private var displayedFileName: String?

    private var pageId: String {
        "\(ref.authorId)/\(ref.albumId)/\(ref.fileName)"
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let displayedGIF {
                    GifPlaybackView(gif: displayedGIF, playbackID: displayedFileName ?? ref.fileName)
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .id(pageId)
        .task(id: pageId) {
            await load()
        }
    }

    private func load() async {
        let requestedFileName = ref.fileName
        let ext = (ref.fileName as NSString).pathExtension.lowercased()
        if ImageLoader.supportsAnimatedPlaybackExtension(ext), let g = try? await env.images.loadAnimatedRaster(ref: ref) {
            do { try Task.checkCancellation() } catch { return }
            await MainActor.run {
                guard requestedFileName == ref.fileName else { return }
                displayedGIF = g
                displayedStill = nil
                displayedFileName = requestedFileName
            }
            return
        }
        let cg = try? await env.images.loadFullCGImage(ref: ref)
        do { try Task.checkCancellation() } catch { return }
        await MainActor.run {
            guard requestedFileName == ref.fileName else { return }
            displayedStill = cg
            displayedGIF = nil
            displayedFileName = requestedFileName
        }
    }
}

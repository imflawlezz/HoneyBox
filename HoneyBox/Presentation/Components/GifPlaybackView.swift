import SwiftUI

struct GifPlaybackView: View {
    let gif: AnimatedGIF
    let playbackID: String

    @Environment(\.displayScale) private var displayScale

    @State private var playback: AnimatedRasterPlaybackSession?
    @State private var frontCGImage: CGImage?

    var body: some View {
        GeometryReader { geo in
            let maxW = max(gif.boundsPixelWidth, 1)
            let maxH = max(gif.boundsPixelHeight, 1)
            let fit = min(geo.size.width / maxW, geo.size.height / maxH)
            let canvasW = maxW * fit
            let canvasH = maxH * fit
            Group {
                if let frontCGImage {
                    Image(decorative: frontCGImage, scale: displayScale, orientation: .up)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: canvasW, height: canvasH)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .onDisappear {
            playback = nil
            frontCGImage = nil
        }
        .task(id: playbackID + gif.sourceURL.absoluteString) {
            await run(with: gif)
        }
    }

    @MainActor
    private func run(with gif: AnimatedGIF) async {
        guard let sess = try? AnimatedRasterPlaybackSession(descriptor: gif) else {
            frontCGImage = nil
            return
        }
        playback = sess
        defer {
            if playback === sess { playback = nil }
        }

        let firstPixel = await Task.detached(priority: .utility) {
            try? sess.decodedFrame(forLogicalIndex: 0)
        }.value
        if let firstPixel {
            frontCGImage = firstPixel
        }

        guard gif.frameCount > 1 else { return }

        var idx = 0
        while !Task.isCancelled {
            let pause = sess.delayAfterFrame(idx)
            do {
                try await Task.sleep(for: .seconds(pause), clock: .continuous)
            } catch {
                break
            }
            guard !Task.isCancelled else { break }
            idx = (idx + 1) % gif.frameCount
            let cg = await Task.detached(priority: .utility) {
                try? sess.decodedFrame(forLogicalIndex: idx)
            }.value
            if let cg { frontCGImage = cg }
        }
    }
}

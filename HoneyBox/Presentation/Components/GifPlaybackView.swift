import SwiftUI

struct GifPlaybackView: View {
    let gif: AnimatedGIF
    let playbackID: String

    @Environment(\.displayScale) private var displayScale
    @State private var frameIndex = 0

    var body: some View {
        GeometryReader { geo in
            let maxW = max(gif.boundsPixelWidth, 1)
            let maxH = max(gif.boundsPixelHeight, 1)
            let fit = min(geo.size.width / maxW, geo.size.height / maxH)
            let canvasW = maxW * fit
            let canvasH = maxH * fit
            Group {
                if gif.frames.indices.contains(frameIndex) {
                    Image(decorative: gif.frames[frameIndex], scale: displayScale, orientation: .up)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: canvasW, height: canvasH)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .task(id: playbackID) {
            await runPlayback()
        }
    }

    @MainActor
    private func runPlayback() async {
        guard gif.frames.count > 1 else { return }
        var idx = 0
        while !Task.isCancelled {
            let delay = idx < gif.delays.count ? gif.delays[idx] : 0.1
            let seconds = max(delay, 1.0 / 60.0)
            do {
                try await Task.sleep(for: .seconds(seconds), clock: .continuous)
            } catch {
                break
            }
            guard !Task.isCancelled else { break }
            idx = (idx + 1) % gif.frames.count
            frameIndex = idx
        }
    }
}

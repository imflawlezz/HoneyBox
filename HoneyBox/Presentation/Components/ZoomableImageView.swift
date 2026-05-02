import SwiftUI

struct ZoomableImageView: View {
    let cgImage: CGImage
    var isActive: Bool = true
    @Binding var parentScrollLocked: Bool

    init(cgImage: CGImage, isActive: Bool = true, parentScrollLocked: Binding<Bool> = .constant(false)) {
        self.cgImage = cgImage
        self.isActive = isActive
        _parentScrollLocked = parentScrollLocked
    }

    var body: some View {
        StaticCGImageZoomView(cgImage: cgImage, isActive: isActive, parentScrollLocked: $parentScrollLocked)
    }
}

struct ZoomableGifView: View {
    let gif: AnimatedGIF
    let playbackID: String
    var isActive: Bool = true
    @Binding var parentScrollLocked: Bool

    init(gif: AnimatedGIF, playbackID: String, isActive: Bool = true, parentScrollLocked: Binding<Bool> = .constant(false)) {
        self.gif = gif
        self.playbackID = playbackID
        self.isActive = isActive
        _parentScrollLocked = parentScrollLocked
    }

    var body: some View {
        AnimatedRasterZoomView(gif: gif, playbackID: playbackID, isActive: isActive, parentScrollLocked: $parentScrollLocked)
    }
}

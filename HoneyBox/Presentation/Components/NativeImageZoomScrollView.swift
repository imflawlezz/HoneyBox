import SwiftUI
import UIKit

// MARK: - Photos-style zoom helpers

private func bindImageViewBoundsToViewport(_ scrollView: UIScrollView, imageView: UIImageView) {
    guard scrollView.zoomScale <= 1.001 else { return }
    let b = scrollView.bounds
    guard b.width > 1, b.height > 1 else { return }
    imageView.frame = CGRect(origin: .zero, size: b.size)
    scrollView.contentSize = b.size
    scrollView.contentInset = .zero
    scrollView.contentOffset = .zero
}

private func insetZoomSubviewIfSmallerThanBounds(_ scrollView: UIScrollView, imageView: UIImageView) {
    let outer = scrollView.bounds.size
    guard outer.width > 0, outer.height > 0 else { return }
    let inner = imageView.frame.size
    let lx = max((outer.width - inner.width) * 0.5, 0)
    let ly = max((outer.height - inner.height) * 0.5, 0)
    scrollView.contentInset = UIEdgeInsets(top: ly, left: lx, bottom: ly, right: lx)
}

private func displayScale(for scrollView: UIScrollView) -> CGFloat {
    let s = scrollView.traitCollection.displayScale
    if s > 0 { return s }
    let c = UITraitCollection.current.displayScale
    return c > 0 ? c : 1
}

private final class LayoutReportingScrollView: UIScrollView {
    var onBoundsChange: ((LayoutReportingScrollView) -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onBoundsChange?(self)
    }
}

// MARK: - Still image

struct StaticCGImageZoomView: UIViewRepresentable {
    let cgImage: CGImage
    var isActive: Bool = true
    @Binding var parentScrollLocked: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIScrollView {
        let sv = LayoutReportingScrollView()
        sv.delegate = context.coordinator
        sv.backgroundColor = .black
        sv.showsHorizontalScrollIndicator = false
        sv.showsVerticalScrollIndicator = false
        sv.bouncesZoom = true
        sv.alwaysBounceVertical = false
        sv.alwaysBounceHorizontal = false
        sv.contentInsetAdjustmentBehavior = .never
        sv.minimumZoomScale = 1
        sv.maximumZoomScale = 4
        context.coordinator.scrollView = sv
        context.coordinator.imageView.contentMode = .scaleAspectFit
        sv.addSubview(context.coordinator.imageView)
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        sv.addGestureRecognizer(doubleTap)
        sv.onBoundsChange = { [weak c = context.coordinator] s in
            c?.viewportDidResize(s)
        }
        return sv
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        let c = context.coordinator
        c.parentScrollLocked = $parentScrollLocked
        c.isActive = isActive

        let pts = displayScale(for: scrollView)
        let img = UIImage(cgImage: cgImage, scale: pts, orientation: .up)
        if c.imageView.image?.cgImage !== cgImage {
            c.imageView.image = img
            scrollView.setZoomScale(1, animated: false)
        }

        if !isActive, scrollView.zoomScale > 1.001 {
            scrollView.setZoomScale(1, animated: false)
        }

        c.syncLayout(scrollView)
        c.syncLock(scrollView)

        scrollView.layoutIfNeeded()
        if scrollView.bounds.width > 1, scrollView.bounds.height > 1 {
            c.syncLayout(scrollView)
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var scrollView: UIScrollView?
        let imageView = UIImageView()
        var parentScrollLocked: Binding<Bool>?
        var isActive: Bool = true

        @objc func handleDoubleTap(_: UITapGestureRecognizer) {
            guard let sv = scrollView else { return }
            if sv.zoomScale > 1.01 {
                sv.setZoomScale(1, animated: true)
            } else {
                sv.setZoomScale(min(2, sv.maximumZoomScale), animated: true)
            }
        }

        func viewForZooming(in _: UIScrollView) -> UIView? {
            imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            insetZoomSubviewIfSmallerThanBounds(scrollView, imageView: imageView)
            syncLock(scrollView)
        }

        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with _: UIView?, atScale scale: CGFloat) {
            if scale <= 1.001 {
                bindImageViewBoundsToViewport(scrollView, imageView: imageView)
                scrollView.contentInset = .zero
            }
            insetZoomSubviewIfSmallerThanBounds(scrollView, imageView: imageView)
            syncLock(scrollView)
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            syncLock(scrollView)
        }

        func viewportDidResize(_ scrollView: UIScrollView) {
            syncLayout(scrollView)
        }

        func syncLayout(_ scrollView: UIScrollView) {
            if scrollView.zoomScale <= 1.001 {
                bindImageViewBoundsToViewport(scrollView, imageView: imageView)
            } else {
                insetZoomSubviewIfSmallerThanBounds(scrollView, imageView: imageView)
            }
        }

        func syncLock(_ scrollView: UIScrollView) {
            guard let parentScrollLocked else { return }
            if !isActive {
                DispatchQueue.main.async {
                    if parentScrollLocked.wrappedValue { parentScrollLocked.wrappedValue = false }
                }
                return
            }
            let locked = scrollView.zoomScale > 1.01
            DispatchQueue.main.async {
                if parentScrollLocked.wrappedValue != locked {
                    parentScrollLocked.wrappedValue = locked
                }
            }
        }
    }
}

// MARK: - Animated GIF / raster

struct AnimatedRasterZoomView: UIViewRepresentable {
    let gif: AnimatedGIF
    let playbackID: String
    var isActive: Bool = true
    @Binding var parentScrollLocked: Bool

    func makeCoordinator() -> AnimatedCoordinator {
        AnimatedCoordinator()
    }

    func makeUIView(context: Context) -> UIScrollView {
        let sv = LayoutReportingScrollView()
        sv.delegate = context.coordinator
        sv.backgroundColor = .black
        sv.showsHorizontalScrollIndicator = false
        sv.showsVerticalScrollIndicator = false
        sv.bouncesZoom = true
        sv.alwaysBounceVertical = false
        sv.alwaysBounceHorizontal = false
        sv.contentInsetAdjustmentBehavior = .never
        sv.minimumZoomScale = 1
        sv.maximumZoomScale = 4
        context.coordinator.scrollView = sv
        context.coordinator.imageView.contentMode = .scaleAspectFit
        sv.addSubview(context.coordinator.imageView)
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(AnimatedCoordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        sv.addGestureRecognizer(doubleTap)
        sv.onBoundsChange = { [weak c = context.coordinator] s in
            c?.viewportDidResize(s)
        }
        return sv
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        let c = context.coordinator
        c.parentScrollLocked = $parentScrollLocked
        c.isActive = isActive
        c.gif = gif

        if !isActive {
            c.stopAnimation()
        } else if c.playbackID != playbackID {
            c.playbackID = playbackID
            scrollView.setZoomScale(1, animated: false)
            c.restartAnimation()
        } else if c.stepTimer == nil, gif.frameCount > 1 {
            c.restartAnimation()
        }

        if !isActive, scrollView.zoomScale > 1.001 {
            scrollView.setZoomScale(1, animated: false)
        }

        c.syncLayout(scrollView)
        c.syncLock(scrollView)

        scrollView.layoutIfNeeded()
        if scrollView.bounds.width > 1, scrollView.bounds.height > 1 {
            c.syncLayout(scrollView)
        }
    }

    static func dismantleUIView(_ uiView: UIScrollView, coordinator: AnimatedCoordinator) {
        coordinator.stopAnimation()
    }

    final class AnimatedCoordinator: NSObject, UIScrollViewDelegate {
        weak var scrollView: UIScrollView?
        let imageView = UIImageView()
        var parentScrollLocked: Binding<Bool>?
        var isActive: Bool = true
        var gif: AnimatedGIF?
        var playbackID: String = ""

        private var frameIndex = 0
        private var decodeGeneration = 0
        var stepTimer: Timer?
        private var playback: AnimatedRasterPlaybackSession?

        @objc func handleDoubleTap(_: UITapGestureRecognizer) {
            guard let sv = scrollView else { return }
            if sv.zoomScale > 1.01 {
                sv.setZoomScale(1, animated: true)
            } else {
                sv.setZoomScale(min(2, sv.maximumZoomScale), animated: true)
            }
        }

        func viewForZooming(in _: UIScrollView) -> UIView? {
            imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            insetZoomSubviewIfSmallerThanBounds(scrollView, imageView: imageView)
            syncLock(scrollView)
        }

        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with _: UIView?, atScale scale: CGFloat) {
            if scale <= 1.001 {
                bindImageViewBoundsToViewport(scrollView, imageView: imageView)
                scrollView.contentInset = .zero
            }
            insetZoomSubviewIfSmallerThanBounds(scrollView, imageView: imageView)
            syncLock(scrollView)
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            syncLock(scrollView)
        }

        func viewportDidResize(_ scrollView: UIScrollView) {
            syncLayout(scrollView)
        }

        func syncLayout(_ scrollView: UIScrollView) {
            if scrollView.zoomScale <= 1.001 {
                bindImageViewBoundsToViewport(scrollView, imageView: imageView)
            } else {
                insetZoomSubviewIfSmallerThanBounds(scrollView, imageView: imageView)
            }
        }

        func syncLock(_ scrollView: UIScrollView) {
            guard let parentScrollLocked else { return }
            if !isActive {
                DispatchQueue.main.async {
                    if parentScrollLocked.wrappedValue { parentScrollLocked.wrappedValue = false }
                }
                return
            }
            let locked = scrollView.zoomScale > 1.01
            DispatchQueue.main.async {
                if parentScrollLocked.wrappedValue != locked {
                    parentScrollLocked.wrappedValue = locked
                }
            }
        }

        func restartAnimation() {
            stopAnimation()
            playback = nil
            decodeGeneration &+= 1
            guard let gif else {
                imageView.image = nil
                return
            }
            playback = try? AnimatedRasterPlaybackSession(descriptor: gif)
            guard let sv = scrollView else { return }
            let pts = displayScale(for: sv)
            if gif.frameCount <= 1 {
                decodeAndAssignFrame(gif: gif, viewportScale: pts, logicalIndex: 0, generation: decodeGeneration)
                bindImageViewBoundsToViewport(sv, imageView: imageView)
                return
            }
            frameIndex = 0
            decodeAndAssignFrame(gif: gif, viewportScale: pts, logicalIndex: 0, generation: decodeGeneration)
            bindImageViewBoundsToViewport(sv, imageView: imageView)
            scheduleStep()
        }

        private func decodeAndAssignFrame(gif: AnimatedGIF, viewportScale: CGFloat, logicalIndex: Int, generation: Int) {
            let session = playback
            DispatchQueue.global(qos: .userInitiated).async {
                let cg: CGImage?
                if let session {
                    cg = try? session.decodedFrame(forLogicalIndex: logicalIndex)
                } else {
                    cg = try? gif.decodeFrame(at: logicalIndex)
                }
                guard let cg else { return }
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    guard generation == self.decodeGeneration else { return }
                    imageView.image = UIImage(cgImage: cg, scale: viewportScale, orientation: .up)
                }
            }
        }

        private func scheduleStep() {
            stepTimer?.invalidate()
            guard let gif, gif.frameCount > 1 else { return }
            let idx = frameIndex
            let seconds: TimeInterval
            if let sess = playback {
                seconds = sess.delayAfterFrame(idx)
            } else {
                seconds = gif.delay(afterFrame: idx)
            }
            stepTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
                self?.advance()
            }
            if let t = stepTimer {
                RunLoop.main.add(t, forMode: .common)
            }
        }

        private func advance() {
            guard let gif, gif.frameCount > 1, let sv = scrollView else { return }
            frameIndex = (frameIndex + 1) % gif.frameCount
            let gen = decodeGeneration
            decodeAndAssignFrame(gif: gif, viewportScale: displayScale(for: sv), logicalIndex: frameIndex, generation: gen)
            scheduleStep()
        }

        func stopAnimation() {
            stepTimer?.invalidate()
            stepTimer = nil
            playback = nil
        }

        deinit {
            stopAnimation()
        }
    }
}

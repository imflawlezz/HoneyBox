import SwiftUI
import UIKit

private final class LayoutSyncScrollView: UIScrollView {
    var onCommitLayout: ((LayoutSyncScrollView) -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onCommitLayout?(self)
    }
}

struct StaticCGImageZoomView: UIViewRepresentable {
    let cgImage: CGImage
    var isActive: Bool = true
    @Binding var parentScrollLocked: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIScrollView {
        let sv = LayoutSyncScrollView()
        sv.delegate = context.coordinator
        sv.backgroundColor = .black
        sv.showsHorizontalScrollIndicator = false
        sv.showsVerticalScrollIndicator = false
        sv.bouncesZoom = true
        sv.minimumZoomScale = 1
        sv.maximumZoomScale = 4
        sv.alwaysBounceVertical = false
        sv.alwaysBounceHorizontal = false
        sv.contentInsetAdjustmentBehavior = .never
        context.coordinator.scrollView = sv
        context.coordinator.imageView.contentMode = .scaleAspectFit
        sv.addSubview(context.coordinator.imageView)

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        sv.addGestureRecognizer(doubleTap)

        sv.onCommitLayout = { [weak c = context.coordinator] scroll in
            c?.layoutImage(in: scroll)
            c?.recenter(scroll)
        }

        return sv
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        let c = context.coordinator
        c.parentScrollLocked = $parentScrollLocked
        c.isActive = isActive

        let scale = UIScreen.main.scale
        let img = UIImage(cgImage: cgImage, scale: scale, orientation: .up)
        if c.imageView.image?.cgImage !== cgImage {
            c.imageView.image = img
            c.lastLayoutBounds = .zero
        }

        if !isActive, scrollView.zoomScale > 1.001 {
            scrollView.setZoomScale(1, animated: false)
        }

        c.layoutImage(in: scrollView)
        c.recenter(scrollView)
        c.syncLock(scrollView)

        scrollView.layoutIfNeeded()
        if scrollView.bounds.width > 1, scrollView.bounds.height > 1 {
            c.layoutImage(in: scrollView)
            c.recenter(scrollView)
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var scrollView: UIScrollView?
        let imageView = UIImageView()
        var parentScrollLocked: Binding<Bool>?
        var isActive: Bool = true
        var lastLayoutBounds: CGSize = .zero

        @objc func handleDoubleTap(_: UITapGestureRecognizer) {
            guard let sv = scrollView else { return }
            if sv.zoomScale > 1.01 {
                sv.setZoomScale(1, animated: true)
            } else {
                sv.setZoomScale(min(2, sv.maximumZoomScale), animated: true)
            }
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            if scrollView.zoomScale <= 1.001 {
                lastLayoutBounds = .zero
                layoutImage(in: scrollView)
            }
            recenter(scrollView)
            syncLock(scrollView)
        }

        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with _: UIView?, atScale scale: CGFloat) {
            if scale <= 1.001 {
                lastLayoutBounds = .zero
                layoutImage(in: scrollView)
            }
            recenter(scrollView)
            syncLock(scrollView)
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            syncLock(scrollView)
        }

        func syncLock(_ scrollView: UIScrollView) {
            guard let parentScrollLocked else { return }
            if isActive {
                parentScrollLocked.wrappedValue = scrollView.zoomScale > 1.01
            } else {
                parentScrollLocked.wrappedValue = false
            }
        }

        func layoutImage(in scrollView: UIScrollView) {
            let bounds = scrollView.bounds
            guard bounds.width > 1, bounds.height > 1, let img = imageView.image else { return }

            let zoomed = scrollView.zoomScale > 1.001
            if zoomed {
                recenter(scrollView)
                return
            }

            let sameBounds = abs(bounds.width - lastLayoutBounds.width) < 0.5 && abs(bounds.height - lastLayoutBounds.height) < 0.5
            if sameBounds {
                recenter(scrollView)
                return
            }
            lastLayoutBounds = bounds.size

            let iw = img.size.width
            let ih = img.size.height
            guard iw > 0, ih > 0 else { return }

            let widthScale = bounds.width / iw
            let heightScale = bounds.height / ih
            let fit = min(widthScale, heightScale)
            let fw = iw * fit
            let fh = ih * fit

            let b = scrollView.bounds.size
            let contentW = max(fw, b.width)
            let contentH = max(fh, b.height)
            let ox = (contentW - fw) * 0.5
            let oy = (contentH - fh) * 0.5
            imageView.frame = CGRect(x: ox, y: oy, width: fw, height: fh)
            scrollView.contentSize = CGSize(width: contentW, height: contentH)
            scrollView.contentInset = .zero
            scrollView.contentOffset = .zero
        }

        func recenter(_ scrollView: UIScrollView) {
            if scrollView.zoomScale <= 1.001 {
                scrollView.contentInset = .zero
                return
            }
            let iv = imageView
            let W = scrollView.bounds.width
            let H = scrollView.bounds.height
            let w = iv.frame.width
            let h = iv.frame.height
            guard w > 0, h > 0 else {
                scrollView.contentInset = .zero
                return
            }
            let insetX = max((W - w) * 0.5, 0)
            let insetY = max((H - h) * 0.5, 0)
            scrollView.contentInset = UIEdgeInsets(top: insetY, left: insetX, bottom: insetY, right: insetX)
        }
    }
}

struct AnimatedRasterZoomView: UIViewRepresentable {
    let gif: AnimatedGIF
    let playbackID: String
    var isActive: Bool = true
    @Binding var parentScrollLocked: Bool

    func makeCoordinator() -> AnimatedCoordinator {
        AnimatedCoordinator()
    }

    func makeUIView(context: Context) -> UIScrollView {
        let sv = LayoutSyncScrollView()
        sv.delegate = context.coordinator
        sv.backgroundColor = .black
        sv.showsHorizontalScrollIndicator = false
        sv.showsVerticalScrollIndicator = false
        sv.bouncesZoom = true
        sv.minimumZoomScale = 1
        sv.maximumZoomScale = 4
        sv.contentInsetAdjustmentBehavior = .never
        context.coordinator.scrollView = sv
        context.coordinator.imageView.contentMode = .scaleAspectFit
        sv.addSubview(context.coordinator.imageView)

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(AnimatedCoordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        sv.addGestureRecognizer(doubleTap)

        sv.onCommitLayout = { [weak c = context.coordinator] scroll in
            c?.layoutCanvas(in: scroll)
            c?.recenter(scroll)
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
            c.restartAnimation()
        } else if c.stepTimer == nil && gif.frames.count > 1 {
            c.restartAnimation()
        }

        if !isActive, scrollView.zoomScale > 1.001 {
            scrollView.setZoomScale(1, animated: false)
        }

        c.layoutCanvas(in: scrollView)
        c.recenter(scrollView)
        c.syncLock(scrollView)

        scrollView.layoutIfNeeded()
        if scrollView.bounds.width > 1, scrollView.bounds.height > 1 {
            c.layoutCanvas(in: scrollView)
            c.recenter(scrollView)
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
        private var frameIndex: Int = 0
        var stepTimer: Timer?
        var lastLayoutBounds: CGSize = .zero

        @objc func handleDoubleTap(_: UITapGestureRecognizer) {
            guard let sv = scrollView else { return }
            if sv.zoomScale > 1.01 {
                sv.setZoomScale(1, animated: true)
            } else {
                sv.setZoomScale(min(2, sv.maximumZoomScale), animated: true)
            }
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            if scrollView.zoomScale <= 1.001 {
                lastLayoutBounds = .zero
                layoutCanvas(in: scrollView)
            }
            recenter(scrollView)
            syncLock(scrollView)
        }

        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with _: UIView?, atScale scale: CGFloat) {
            if scale <= 1.001 {
                lastLayoutBounds = .zero
                layoutCanvas(in: scrollView)
            }
            recenter(scrollView)
            syncLock(scrollView)
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            syncLock(scrollView)
        }

        func syncLock(_ scrollView: UIScrollView) {
            guard let parentScrollLocked else { return }
            if isActive {
                parentScrollLocked.wrappedValue = scrollView.zoomScale > 1.01
            } else {
                parentScrollLocked.wrappedValue = false
            }
        }

        func layoutCanvas(in scrollView: UIScrollView) {
            guard let gif else { return }
            let bounds = scrollView.bounds
            guard bounds.width > 1, bounds.height > 1 else { return }

            if scrollView.zoomScale > 1.001 {
                recenter(scrollView)
                return
            }

            let sameBounds = abs(bounds.width - lastLayoutBounds.width) < 0.5 && abs(bounds.height - lastLayoutBounds.height) < 0.5
            if sameBounds {
                recenter(scrollView)
                return
            }
            lastLayoutBounds = bounds.size

            let screenScale = UIScreen.main.scale
            let maxW = max(gif.boundsPixelWidth / screenScale, 1)
            let maxH = max(gif.boundsPixelHeight / screenScale, 1)
            let scale = min(bounds.width / maxW, bounds.height / maxH)
            let cw = maxW * scale
            let ch = maxH * scale

            let b = scrollView.bounds.size
            let contentW = max(cw, b.width)
            let contentH = max(ch, b.height)
            let ox = (contentW - cw) * 0.5
            let oy = (contentH - ch) * 0.5
            imageView.frame = CGRect(x: ox, y: oy, width: cw, height: ch)
            scrollView.contentSize = CGSize(width: contentW, height: contentH)
            scrollView.contentInset = .zero
            scrollView.contentOffset = .zero
        }

        func recenter(_ scrollView: UIScrollView) {
            if scrollView.zoomScale <= 1.001 {
                scrollView.contentInset = .zero
                return
            }
            let iv = imageView
            let W = scrollView.bounds.width
            let H = scrollView.bounds.height
            let w = iv.frame.width
            let h = iv.frame.height
            guard w > 0, h > 0 else {
                scrollView.contentInset = .zero
                return
            }
            let insetX = max((W - w) * 0.5, 0)
            let insetY = max((H - h) * 0.5, 0)
            scrollView.contentInset = UIEdgeInsets(top: insetY, left: insetX, bottom: insetY, right: insetX)
        }

        func restartAnimation() {
            stopAnimation()
            lastLayoutBounds = .zero
            guard let gif else {
                imageView.image = nil
                return
            }
            if gif.frames.count <= 1 {
                if let first = gif.frames.first {
                    imageView.image = UIImage(cgImage: first, scale: UIScreen.main.scale, orientation: .up)
                }
                return
            }
            frameIndex = 0
            applyFrame(gif, index: 0)
            scheduleStep()
        }

        private func applyFrame(_ gif: AnimatedGIF, index: Int) {
            guard gif.frames.indices.contains(index) else { return }
            imageView.image = UIImage(cgImage: gif.frames[index], scale: UIScreen.main.scale, orientation: .up)
        }

        private func scheduleStep() {
            stepTimer?.invalidate()
            guard let gif, gif.frames.count > 1 else { return }
            let idx = frameIndex
            let delay = idx < gif.delays.count ? gif.delays[idx] : 0.1
            let seconds = max(delay, 1.0 / 60.0)
            stepTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
                self?.advance()
            }
            if let t = stepTimer {
                RunLoop.main.add(t, forMode: .common)
            }
        }

        private func advance() {
            guard let gif, gif.frames.count > 1 else { return }
            frameIndex = (frameIndex + 1) % gif.frames.count
            applyFrame(gif, index: frameIndex)
            scheduleStep()
        }

        func stopAnimation() {
            stepTimer?.invalidate()
            stepTimer = nil
        }

        deinit {
            stopAnimation()
        }
    }
}

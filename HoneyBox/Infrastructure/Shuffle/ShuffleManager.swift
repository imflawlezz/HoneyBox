import Foundation

actor ShuffleManager: ShuffleManaging {
    private let index: IndexService
    private let images: ImageLoader

    private var queue: [ImageRef] = []
    private var position: Int = 0
    private var lastShown: ImageRef?

    init(index: IndexService, images: ImageLoader) {
        self.index = index
        self.images = images
    }

    func reset() async throws {
        var refs = try await index.allImageRefs()
        guard !refs.isEmpty else {
            queue = []
            position = 0
            return
        }
        refs.shuffle()
        if let last = lastShown, let first = refs.first, refs.count > 1,
           first.authorId == last.authorId, first.albumId == last.albumId, first.fileName == last.fileName {
            if let swapIdx = refs.indices.dropFirst().first {
                refs.swapAt(0, swapIdx)
            }
        }
        queue = refs
        position = 0
    }

    func current() -> ImageRef? {
        guard !queue.isEmpty, position < queue.count else { return nil }
        return queue[position]
    }

    func advance() async throws -> ImageRef? {
        guard !queue.isEmpty else { return nil }
        if position + 1 < queue.count {
            lastShown = queue[position]
            position += 1
            return queue[position]
        }
        lastShown = queue[position]
        try await reset()
        return queue.first
    }

    func preloadAroundCurrent() async {
        await preloadAroundCurrent(ahead: 1, behind: 0)
    }

    func preloadAroundCurrent(ahead: Int, behind: Int) async {
        guard !queue.isEmpty else { return }
        let start = max(0, position - max(0, behind))
        let end = min(queue.count - 1, position + max(0, ahead))
        guard start <= end else { return }
        for i in start...end {
            let ref = queue[i]
            _ = try? await images.loadFullUIImage(ref: ref)
        }
    }

    func positionLabel() -> String {
        guard !queue.isEmpty else { return "0 / 0" }
        return "\(position + 1) / \(queue.count)"
    }
}

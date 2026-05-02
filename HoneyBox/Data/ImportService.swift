import Foundation

struct ImportReport: Sendable {
    var importedImages: Int
    var skippedInvalidNames: Int
    var skippedDuplicates: Int
    var albumsTouched: Set<String>
    var messages: [String]
}

enum ImportProgressPhase: String, Sendable {
    case copying
    case thumbnails
}

enum ImportGalleryError: Error, LocalizedError {
    case emptyTitle
    case noImages

    var errorDescription: String? {
        switch self {
        case .emptyTitle: "Enter a gallery name."
        case .noImages: "No images to import."
        }
    }
}

private struct ImportParsedFile: Hashable, Sendable {
    var albumNum: Int
    var imageNum: Int
    var url: URL
    var ext: String
}

final class ImportProgressReporter: @unchecked Sendable {
    private let onProgress: (@MainActor (ImportProgressPhase, Int, Int, String) -> Void)?
    private let copyTotal: Int
    private var copyDone = 0
    private var thumbTotal = 0
    private var thumbDone = 0

    init(copyTotal: Int, onProgress: (@MainActor (ImportProgressPhase, Int, Int, String) -> Void)?) {
        let c = max(1, copyTotal)
        self.copyTotal = c
        self.onProgress = onProgress
    }

    func copyStep(_ message: String) async {
        copyDone = min(copyDone + 1, copyTotal)
        await report(.copying, copyDone, copyTotal, message)
    }

    func addPlannedThumbnails(_ count: Int) async {
        guard count > 0 else { return }
        thumbTotal += count
        await report(.thumbnails, thumbDone, max(1, thumbTotal), "Generating thumbnails…")
    }

    func thumbBatchCompleted(_ batchSize: Int) async {
        guard batchSize > 0 else { return }
        thumbDone = min(thumbDone + batchSize, max(thumbTotal, 1))
        await report(.thumbnails, thumbDone, max(1, thumbTotal), "Generating thumbnails…")
    }

    func thumbStatus(_ message: String) async {
        await report(.thumbnails, thumbDone, max(1, thumbTotal), message)
    }

    func finish(_ message: String) async {
        if thumbTotal > 0 {
            thumbDone = thumbTotal
            await report(.thumbnails, thumbDone, max(1, thumbTotal), message)
        } else {
            copyDone = copyTotal
            await report(.copying, copyDone, copyTotal, message)
        }
    }

    private func report(_ phase: ImportProgressPhase, _ done: Int, _ total: Int, _ msg: String) async {
        if let onProgress { await MainActor.run { onProgress(phase, done, total, msg) } }
    }
}

final class ImportService: Sendable {
    private let storage: StorageService
    private let index: IndexService
    private let images: ImageLoader

    init(storage: StorageService, index: IndexService, images: ImageLoader) {
        self.storage = storage
        self.index = index
        self.images = images
    }

    private static let fileNameRegex = try! NSRegularExpression(
        pattern: #"^(\d+)_(\d+)\.(jpg|jpeg|png|webp|gif)$"#,
        options: [.caseInsensitive]
    )

    private func metaEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private func transferIntoLibrary(from source: URL, to destination: URL) throws {
        if ImportSecurityStaging.isStagedFile(source) {
            try storage.moveItem(from: source, to: destination)
        } else {
            try storage.copyItem(from: source, to: destination)
        }
    }

    func importFiles(
        authorId: String,
        fileURLs: [URL],
        onProgress: (@MainActor (ImportProgressPhase, Int, Int, String) -> Void)? = nil
    ) async throws -> ImportReport {
        var report = ImportReport(
            importedImages: 0,
            skippedInvalidNames: 0,
            skippedDuplicates: 0,
            albumsTouched: [],
            messages: []
        )

        var parsed: [ImportParsedFile] = []
        var loose: [URL] = []
        let allowedLooseExts: Set<String> = ["jpg", "jpeg", "png", "webp", "gif"]
        for url in fileURLs {
            let name = url.lastPathComponent
            guard let match = Self.fileNameRegex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
                  match.numberOfRanges == 4,
                  let r1 = Range(match.range(at: 1), in: name),
                  let r2 = Range(match.range(at: 2), in: name),
                  let r3 = Range(match.range(at: 3), in: name),
                  let albumNum = Int(name[r1]),
                  let imageNum = Int(name[r2])
            else {
                let ext = url.pathExtension.lowercased()
                if allowedLooseExts.contains(ext) || allowedLooseExts.contains(ext == "jpeg" ? "jpg" : ext) {
                    loose.append(url)
                } else {
                    report.skippedInvalidNames += 1
                }
                continue
            }
            let ext = String(name[r3]).lowercased()
            parsed.append(ImportParsedFile(albumNum: albumNum, imageNum: imageNum, url: url, ext: ext))
        }

        let workUnits = parsed.count + loose.count
        let progress: ImportProgressReporter? = onProgress.map { cb in ImportProgressReporter(copyTotal: workUnits, onProgress: cb) }

        let grouped = Dictionary(grouping: parsed, by: \.albumNum)
        for (albumNum, items) in grouped.sorted(by: { $0.key < $1.key }) {
            let albumId = "album_\(albumNum)"
            let sorted = items.sorted { $0.imageNum < $1.imageNum }
            try await importAlbumGroup(
                authorId: authorId,
                albumId: albumId,
                albumNumber: albumNum,
                items: sorted,
                report: &report,
                progress: progress
            )
        }

        if !loose.isEmpty {
            let (albumId, displayTitle, order) = await nextLooseAlbumId(authorId: authorId)
            try await ensureAlbumMeta(authorId: authorId, albumId: albumId, order: order, displayTitle: displayTitle)
            let looseReport = try await appendLooseImages(
                authorId: authorId,
                albumId: albumId,
                fileURLs: loose,
                progress: progress
            )
            report.importedImages += looseReport.importedImages
            report.skippedDuplicates += looseReport.skippedDuplicates
            report.skippedInvalidNames += looseReport.skippedInvalidNames
            report.albumsTouched.formUnion(looseReport.albumsTouched)
            report.messages.append("Imported \(looseReport.importedImages) ungrouped photos into “\(displayTitle)”.")
        }

        await progress?.finish("Done")
        return report
    }

    func importNewGallery(
        authorId: String,
        displayTitle: String,
        fileURLs: [URL],
        onProgress: (@MainActor (ImportProgressPhase, Int, Int, String) -> Void)? = nil
    ) async throws -> ImportReport {
        let title = displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw ImportGalleryError.emptyTitle }
        guard !fileURLs.isEmpty else { throw ImportGalleryError.noImages }

        let snap = await index.snapshot()
        let existingOrders = (snap.albumsByAuthor[authorId] ?? []).map(\.order)
        let nextOrder = (existingOrders.max() ?? 0) + 1
        let albumId = "import_\(Int(Date().timeIntervalSince1970))_\(UUID().uuidString.prefix(6))"

        let progress: ImportProgressReporter? = onProgress.map { ImportProgressReporter(copyTotal: fileURLs.count, onProgress: $0) }
        try await ensureAlbumMeta(authorId: authorId, albumId: albumId, order: nextOrder, displayTitle: title)
        var report = try await appendLooseImages(
            authorId: authorId,
            albumId: albumId,
            fileURLs: fileURLs,
            progress: progress
        )
        report.messages = ["Created “\(title)” with \(report.importedImages) image(s)."]
        await progress?.finish("Done")
        return report
    }

    private func nextLooseAlbumId(authorId: String) async -> (albumId: String, displayTitle: String, order: Int) {
        let snap = await index.snapshot()
        let existingOrders = (snap.albumsByAuthor[authorId] ?? []).map(\.order)
        let nextOrder = (existingOrders.max() ?? 0) + 1
        let ts = Int(Date().timeIntervalSince1970)
        return ("import_\(ts)", "Imported", nextOrder)
    }

    private func ensureAlbumMeta(authorId: String, albumId: String, order: Int, displayTitle: String) async throws {
        let metaURL = StoragePaths.albumMetaURL(root: storage.rootURL, authorId: authorId, albumId: albumId)
        if storage.fileExists(at: metaURL) { return }
        let now = Date()
        let meta = AlbumMetaFile(
            schemaVersion: PersistenceSchema.currentAlbumMetaVersion,
            id: albumId,
            order: order,
            displayTitle: displayTitle,
            createdAt: now,
            updatedAt: now,
            lastOpenedAt: nil,
            images: []
        )
        let encoder = metaEncoder()
        try storage.atomicWrite(try encoder.encode(meta), to: metaURL)

        let summary = AlbumSummaryDTO(
            id: albumId,
            displayTitle: meta.displayTitle,
            order: meta.order,
            imageCount: 0,
            coverThumbnailFileName: nil,
            createdAt: meta.createdAt,
            updatedAt: meta.updatedAt,
            lastOpenedAt: meta.lastOpenedAt,
            coverAspectRatio: nil
        )
        try await index.addOrUpdateAlbumSummary(summary, authorId: authorId)
        try await index.touchRecentlyAdded(authorId: authorId, albumId: albumId)
    }

    func appendLooseImages(
        authorId: String,
        albumId: String,
        fileURLs: [URL],
        progress: ImportProgressReporter? = nil
    ) async throws -> ImportReport {
        var report = ImportReport(
            importedImages: 0,
            skippedInvalidNames: 0,
            skippedDuplicates: 0,
            albumsTouched: [albumId],
            messages: []
        )
        let allowed: Set<String> = ["jpg", "jpeg", "png", "webp", "gif"]
        let imagesDir = StoragePaths.imagesDirectory(root: storage.rootURL, authorId: authorId, albumId: albumId)
        let thumbsDir = StoragePaths.thumbnailsDirectory(root: storage.rootURL, authorId: authorId, albumId: albumId)
        try storage.createDirectory(at: imagesDir)
        try storage.createDirectory(at: thumbsDir)

        let metaURL = StoragePaths.albumMetaURL(root: storage.rootURL, authorId: authorId, albumId: albumId)
        let data = try storage.readData(at: metaURL)
        var meta = try JSONDecoder.iso8601.decode(AlbumMetaFile.self, from: data)
        var slot = meta.images.map { Self.indexFromFileName($0) }.max() ?? 0
        var thumbJobs: [(source: URL, dest: URL)] = []

        for url in fileURLs {
            let needsScope = !ImportSecurityStaging.isStagedFile(url)
            let started = needsScope && url.startAccessingSecurityScopedResource()
            defer { if started { url.stopAccessingSecurityScopedResource() } }

            var ext = url.pathExtension.lowercased()
            if ext == "jpeg" { ext = "jpg" }
            guard allowed.contains(ext) else {
                report.skippedInvalidNames += 1
                await progress?.copyStep("Skipped invalid type")
                continue
            }
            slot += 1
            let destName = String(format: "img_%04d.\(ext)", slot)
            let destURL = imagesDir.appendingPathComponent(destName, isDirectory: false)
            let thumbName = String(format: "thumb_%04d.jpg", slot)
            let thumbURL = thumbsDir.appendingPathComponent(thumbName, isDirectory: false)

            try transferIntoLibrary(from: url, to: destURL)
            thumbJobs.append((source: destURL, dest: thumbURL))
            if !meta.images.contains(destName) {
                meta.images.append(destName)
            }
            report.importedImages += 1
            await progress?.copyStep("Copied \(destName)")
        }

        await progress?.addPlannedThumbnails(thumbJobs.count)
        try await generateThumbnails(thumbJobs, maxConcurrent: 8, progress: progress)

        meta.updatedAt = Date()
        let encoder = metaEncoder()
        try storage.atomicWrite(try encoder.encode(meta), to: metaURL)

        let summaryId = meta.id
        let order = meta.order
        let coverThumb: String?
        if let first = meta.images.first {
            let stem = (first as NSString).deletingPathExtension.replacingOccurrences(of: "img_", with: "")
            coverThumb = "thumb_\(stem).jpg"
        } else {
            coverThumb = nil
        }
        let summary = AlbumSummaryDTO(
            id: summaryId,
            displayTitle: meta.displayTitle,
            order: order,
            imageCount: meta.images.count,
            coverThumbnailFileName: coverThumb,
            createdAt: meta.createdAt,
            updatedAt: meta.updatedAt,
            lastOpenedAt: meta.lastOpenedAt,
            coverAspectRatio: nil
        )
        try await index.addOrUpdateAlbumSummary(summary, authorId: authorId)
        try await index.updateAlbumSummaryFromMeta(authorId: authorId, albumId: albumId)
        try await index.touchRecentlyAdded(authorId: authorId, albumId: albumId)
        return report
    }

    private func importAlbumGroup(
        authorId: String,
        albumId: String,
        albumNumber: Int,
        items: [ImportParsedFile],
        report: inout ImportReport,
        progress: ImportProgressReporter?
    ) async throws {
        let imagesDir = StoragePaths.imagesDirectory(root: storage.rootURL, authorId: authorId, albumId: albumId)
        let thumbsDir = StoragePaths.thumbnailsDirectory(root: storage.rootURL, authorId: authorId, albumId: albumId)
        try storage.createDirectory(at: imagesDir)
        try storage.createDirectory(at: thumbsDir)

        let metaURL = StoragePaths.albumMetaURL(root: storage.rootURL, authorId: authorId, albumId: albumId)
        let now = Date()
        var meta: AlbumMetaFile
        if let data = storage.readDataIfPresent(at: metaURL) {
            meta = try JSONDecoder.iso8601.decode(AlbumMetaFile.self, from: data)
        } else {
            meta = AlbumMetaFile(
                schemaVersion: PersistenceSchema.currentAlbumMetaVersion,
                id: albumId,
                order: albumNumber,
                displayTitle: "#\(albumNumber)",
                createdAt: now,
                updatedAt: now,
                lastOpenedAt: nil,
                images: []
            )
        }

        var slot = meta.images.map { Self.indexFromFileName($0) }.max() ?? 0
        var thumbJobs: [(source: URL, dest: URL)] = []

        for item in items {
            let needsScope = !ImportSecurityStaging.isStagedFile(item.url)
            let started = needsScope && item.url.startAccessingSecurityScopedResource()
            defer { if started { item.url.stopAccessingSecurityScopedResource() } }

            slot += 1
            let destName = String(format: "img_%04d.\(item.ext)", slot)
            let destURL = imagesDir.appendingPathComponent(destName, isDirectory: false)
            let thumbName = String(format: "thumb_%04d.jpg", slot)
            let thumbURL = thumbsDir.appendingPathComponent(thumbName, isDirectory: false)

            let srcSize = storage.fileSize(at: item.url) ?? -1
            if storage.fileExists(at: destURL), storage.fileSize(at: destURL) == srcSize, srcSize >= 0 {
                report.skippedDuplicates += 1
                await progress?.copyStep("Skipped duplicate")
                continue
            }

            try transferIntoLibrary(from: item.url, to: destURL)
            thumbJobs.append((source: destURL, dest: thumbURL))

            if !meta.images.contains(destName) {
                meta.images.append(destName)
            }
            report.importedImages += 1
            await progress?.copyStep("Album \(albumNumber): \(destName)")
        }

        await progress?.addPlannedThumbnails(thumbJobs.count)
        try await generateThumbnails(thumbJobs, maxConcurrent: 8, progress: progress)

        meta.updatedAt = Date()
        let encoder = metaEncoder()
        let metaData = try encoder.encode(meta)
        try storage.atomicWrite(metaData, to: metaURL)

        let coverThumb: String?
        if let first = meta.images.first {
            let stem = (first as NSString).deletingPathExtension.replacingOccurrences(of: "img_", with: "")
            coverThumb = "thumb_\(stem).jpg"
        } else {
            coverThumb = nil
        }

        let summary = AlbumSummaryDTO(
            id: albumId,
            displayTitle: meta.displayTitle,
            order: albumNumber,
            imageCount: meta.images.count,
            coverThumbnailFileName: coverThumb,
            createdAt: meta.createdAt,
            updatedAt: meta.updatedAt,
            lastOpenedAt: meta.lastOpenedAt,
            coverAspectRatio: nil
        )

        try await index.addOrUpdateAlbumSummary(summary, authorId: authorId)
        try await index.updateAlbumSummaryFromMeta(authorId: authorId, albumId: albumId)
        try await index.touchRecentlyAdded(authorId: authorId, albumId: albumId)
        report.albumsTouched.insert(albumId)
    }

    private func generateThumbnails(
        _ jobs: [(source: URL, dest: URL)],
        maxConcurrent: Int,
        progress: ImportProgressReporter?
    ) async throws {
        guard !jobs.isEmpty else { return }
        let limit = max(1, maxConcurrent)
        var idx = 0
        while idx < jobs.count {
            let batch = Array(jobs[idx..<min(jobs.count, idx + limit)])
            try await withThrowingTaskGroup(of: Void.self) { group in
                for job in batch {
                    group.addTask {
                        try self.images.generateThumbnailJPEG(fromImageAt: job.source, to: job.dest, maxPixel: 1024, quality: 0.88)
                    }
                }
                try await group.waitForAll()
            }
            await progress?.thumbBatchCompleted(batch.count)
            idx += batch.count
        }
    }

    private static func indexFromFileName(_ name: String) -> Int {
        let base = (name as NSString).deletingPathExtension
        guard base.hasPrefix("img_"), let n = Int(base.dropFirst(4)) else { return 0 }
        return n
    }
}

private extension JSONDecoder {
    static var iso8601: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}

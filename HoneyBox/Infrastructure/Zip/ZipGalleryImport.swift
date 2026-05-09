import Foundation
import ZIPFoundation

enum ZipGalleryImportError: Error, LocalizedError {
    case invalidArchive
    case noImagesInArchive
    case honeyBoxBackupUseSettingsRestore

    var errorDescription: String? {
        switch self {
        case .invalidArchive:
            "The selected file is not a readable .zip archive."
        case .noImagesInArchive:
            "No supported images were found in the archive (jpg, png, webp, gif)."
        case .honeyBoxBackupUseSettingsRestore:
            "This .zip looks like a full HoneyBox library backup. Restore it from Settings instead."
        }
    }
}

enum ZipPreparedImport: Sendable {
    case looseOrderedGallery(files: [URL], sessionDirectory: URL, suggestedTitle: String)
    case honeyBoxNumbered(files: [URL], sessionDirectory: URL)
}

private struct StructuredImage: Comparable, Sendable {
    var album: Int
    var image: Int
    var entry: Entry
    var ext: String

    static func < (lhs: StructuredImage, rhs: StructuredImage) -> Bool {
        if lhs.album != rhs.album { return lhs.album < rhs.album }
        if lhs.image != rhs.image { return lhs.image < rhs.image }
        return false
    }
}

enum ZipGalleryImport {
    private static let allowedExts: Set<String> = ["jpg", "jpeg", "png", "webp", "gif"]

    private static let flatNameRegex = try! NSRegularExpression(
        pattern: #"^(\d+)_(\d+)\.(jpg|jpeg|png|webp|gif)$"#,
        options: [.caseInsensitive]
    )

    static func prepareImport(
        zipURL: URL,
        onProgress: (@Sendable (Int, Int, String) -> Void)? = nil
    ) throws -> ZipPreparedImport {
        let archive: Archive
        do {
            archive = try Archive(url: zipURL, accessMode: .read)
        } catch {
            throw ZipGalleryImportError.invalidArchive
        }

        if looksLikeHoneyBoxFullBackup(archive: archive) {
            throw ZipGalleryImportError.honeyBoxBackupUseSettingsRestore
        }

        let imageEntries = allImageFileEntriesInArchiveOrder(in: archive)
        guard !imageEntries.isEmpty else {
            throw ZipGalleryImportError.noImagesInArchive
        }

        if let structured = tryHoneyBoxUniformLayout(entries: imageEntries) {
            let (files, session) = try extractStructuredToStaging(archive: archive, structured: structured, onProgress: onProgress)
            return .honeyBoxNumbered(files: files, sessionDirectory: session)
        }

        let (files, session) = try extractLooseToStaging(archive: archive, entries: imageEntries, onProgress: onProgress)
        let suggested = zipURL.deletingPathExtension().lastPathComponent
        return .looseOrderedGallery(files: files, sessionDirectory: session, suggestedTitle: suggested)
    }

    // MARK: - Layout detection

    private static func tryHoneyBoxUniformLayout(entries: [Entry]) -> [StructuredImage]? {
        var parsed: [StructuredImage] = []
        parsed.reserveCapacity(entries.count)
        var seenKeys = Set<String>()

        for entry in entries {
            guard let triple = parseHoneyBoxIndices(path: entry.path) else { return nil }
            let key = "\(triple.album)_\(triple.image)"
            guard seenKeys.insert(key).inserted else { continue }
            parsed.append(StructuredImage(album: triple.album, image: triple.image, entry: entry, ext: triple.ext))
        }
        guard !parsed.isEmpty else { return nil }
        return parsed.sorted()
    }

    private static func parseHoneyBoxIndices(path: String) -> (album: Int, image: Int, ext: String)? {
        let base = (path as NSString).lastPathComponent
        let ns = base as NSString
        let len = ns.length
        if let match = flatNameRegex.firstMatch(in: base, range: NSRange(location: 0, length: len)),
           match.numberOfRanges == 4,
           let r1 = Range(match.range(at: 1), in: base),
           let r2 = Range(match.range(at: 2), in: base),
           let r3 = Range(match.range(at: 3), in: base),
           let album = Int(base[r1]),
           let image = Int(base[r2])
        {
            let ext = String(base[r3]).lowercased()
            return (album, image, ext)
        }

        let parts = path.split(separator: "/").map(String.init).filter { !$0.isEmpty }
        guard parts.count >= 2 else { return nil }
        let dirComponent = parts[parts.count - 2]
        let fileName = parts[parts.count - 1]
        guard let album = Int(dirComponent) else { return nil }

        let stem = (fileName as NSString).deletingPathExtension
        guard let image = Int(stem) else { return nil }

        let ext = (fileName as NSString).pathExtension.lowercased()
        guard allowedExts.contains(ext) else { return nil }
        return (album, image, ext)
    }

    // MARK: - Extract

    private static func extractLooseToStaging(
        archive: Archive,
        entries: [Entry],
        onProgress: (@Sendable (Int, Int, String) -> Void)?
    ) throws -> (files: [URL], sessionDirectory: URL) {
        let session = UUID().uuidString
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(ImportSecurityStaging.stagingFolderName, isDirectory: true)
            .appendingPathComponent(session, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let total = entries.count
        var files: [URL] = []
        files.reserveCapacity(total)

        do {
            for (i, entry) in entries.enumerated() {
                let slotDir = root.appendingPathComponent(String(format: "%06d", i), isDirectory: true)
                try FileManager.default.createDirectory(at: slotDir, withIntermediateDirectories: true)
                let destName = (entry.path as NSString).lastPathComponent
                let dest = slotDir.appendingPathComponent(destName, isDirectory: false)
                _ = try archive.extract(entry, to: dest)
                files.append(dest)
                onProgress?(i + 1, total, destName)
            }
        } catch {
            try? FileManager.default.removeItem(at: root)
            throw error
        }

        return (files, root)
    }

    private static func extractStructuredToStaging(
        archive: Archive,
        structured: [StructuredImage],
        onProgress: (@Sendable (Int, Int, String) -> Void)?
    ) throws -> (files: [URL], sessionDirectory: URL) {
        let session = UUID().uuidString
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(ImportSecurityStaging.stagingFolderName, isDirectory: true)
            .appendingPathComponent(session, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let total = structured.count
        var files: [URL] = []
        files.reserveCapacity(total)

        do {
            for (i, item) in structured.enumerated() {
                let slotDir = root.appendingPathComponent(String(format: "%06d", i), isDirectory: true)
                try FileManager.default.createDirectory(at: slotDir, withIntermediateDirectories: true)
                let destName = "\(item.album)_\(item.image).\(item.ext)"
                let dest = slotDir.appendingPathComponent(destName, isDirectory: false)
                _ = try archive.extract(item.entry, to: dest)
                files.append(dest)
                onProgress?(i + 1, total, destName)
            }
        } catch {
            try? FileManager.default.removeItem(at: root)
            throw error
        }

        return (files, root)
    }

    // MARK: - Archive helpers

    private static func looksLikeHoneyBoxFullBackup(archive: Archive) -> Bool {
        var hasRootIndex = false
        var hasAuthorsContent = false
        for entry in archive {
            let parts = entry.path.split(separator: "/").map(String.init).filter { !$0.isEmpty }
            if parts.count == 1, parts[0].lowercased() == StoragePaths.indexFileName.lowercased() {
                hasRootIndex = true
            }
            if let first = parts.first?.lowercased(), first == StoragePaths.authorsFolderName.lowercased() {
                if parts.count >= 2 || entry.type == .directory {
                    hasAuthorsContent = true
                }
            }
        }
        return hasRootIndex && hasAuthorsContent
    }

    private static func isJunkPath(_ path: String) -> Bool {
        let lower = path.lowercased()
        if lower.contains("__macosx") { return true }
        if (path as NSString).lastPathComponent.lowercased() == ".ds_store" { return true }
        return false
    }

    private static func allImageFileEntriesInArchiveOrder(in archive: Archive) -> [Entry] {
        var out: [Entry] = []
        for entry in archive {
            guard entry.type == .file else { continue }
            if isJunkPath(entry.path) { continue }
            let ext = (entry.path as NSString).pathExtension.lowercased()
            let norm = ext == "jpeg" ? "jpg" : ext
            guard allowedExts.contains(norm) else { continue }
            out.append(entry)
        }
        return out
    }
}

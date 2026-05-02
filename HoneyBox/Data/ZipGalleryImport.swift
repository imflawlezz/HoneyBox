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

enum ZipGalleryImport {
    private static let allowedExts: Set<String> = ["jpg", "jpeg", "png", "webp", "gif"]

    static func extractImagesToStaging(
        zipURL: URL,
        onProgress: (@Sendable (Int, Int, String) -> Void)? = nil
    ) throws -> (files: [URL], sessionDirectory: URL) {
        guard let archive = Archive(url: zipURL, accessMode: .read) else {
            throw ZipGalleryImportError.invalidArchive
        }

        if looksLikeHoneyBoxFullBackup(archive: archive) {
            throw ZipGalleryImportError.honeyBoxBackupUseSettingsRestore
        }

        let imageEntries = orderedImageEntries(in: archive)
        guard !imageEntries.isEmpty else {
            throw ZipGalleryImportError.noImagesInArchive
        }

        let session = UUID().uuidString
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(ImportSecurityStaging.stagingFolderName, isDirectory: true)
            .appendingPathComponent(session, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let total = imageEntries.count
        var files: [URL] = []
        files.reserveCapacity(total)

        do {
            for (i, entry) in imageEntries.enumerated() {
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

    private static func orderedImageEntries(in archive: Archive) -> [Entry] {
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

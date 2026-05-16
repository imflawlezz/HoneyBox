import Foundation

struct LibraryStorageStats: Sendable, Equatable {
    var imageFileCount: Int
    var totalByteCount: Int64
}

enum LibraryStorageInspector: Sendable {
    private nonisolated static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "webp", "gif", "heic", "heif"]

    nonisolated static func inspect(root: URL) -> LibraryStorageStats {
        let fm = FileManager.default
        var imageCount = 0
        var totalBytes: Int64 = 0

        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return LibraryStorageStats(imageFileCount: 0, totalByteCount: 0)
        }

        for case let url as URL in enumerator {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else { continue }

            let path = url.path
            if let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
                totalBytes += Int64(size)
            }

            if pathContainsImagesFolder(path), !pathContainsThumbnailsFolder(path), isImageFile(url) {
                imageCount += 1
            }
        }

        return LibraryStorageStats(imageFileCount: imageCount, totalByteCount: totalBytes)
    }

    private nonisolated static func pathContainsThumbnailsFolder(_ path: String) -> Bool {
        path.contains("/\(StoragePaths.thumbnailsFolderName)/")
    }

    private nonisolated static func pathContainsImagesFolder(_ path: String) -> Bool {
        path.contains("/\(StoragePaths.imagesFolderName)/")
    }

    private nonisolated static func isImageFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return imageExtensions.contains(ext)
    }

    nonisolated static func formattedByteCount(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

enum LibraryBackupPreferences {
    static let lastBackupTimestampKey = "libraryLastBackupTimestamp"
    static let reminderThresholdDays = 30

    static var lastBackupDate: Date? {
        let ts = UserDefaults.standard.double(forKey: lastBackupTimestampKey)
        guard ts > 0 else { return nil }
        return Date(timeIntervalSince1970: ts)
    }

    static func recordBackupCompleted(at date: Date = Date()) {
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: lastBackupTimestampKey)
    }

    static func shouldShowBackupReminder(hasLibraryContent: Bool) -> Bool {
        guard hasLibraryContent else { return false }
        guard let last = lastBackupDate else { return true }
        let days = Calendar.current.dateComponents([.day], from: last, to: Date()).day ?? 0
        return days >= reminderThresholdDays
    }

    static func formattedLastBackup(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    static func daysSinceLastBackup() -> Int? {
        guard let last = lastBackupDate else { return nil }
        return Calendar.current.dateComponents([.day], from: last, to: Date()).day
    }
}

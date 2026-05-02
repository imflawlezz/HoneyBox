import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct HomeView: View {
    @ObservedObject var env: HoneyBoxEnvironment

    @State private var showImportChoice = false
    @State private var showFileImport = false
    @State private var showZipGalleryImport = false
    @State private var showPhotosImport = false
    @State private var pendingPhotoItems: [PhotosPickerItem] = []
    @State private var importPayload: HomeImportPayload?
    @State private var zipGalleryImportPayload: HomeZipGalleryImportPayload?
    @State private var isPreparingImport = false
    @State private var showShuffle = false
    @State private var importMessage: String?
    @State private var showImportAlert = false
    @State private var navSelection: HomeNavSelection?
    @State private var favoritesShuffleSeed: UInt64 = UInt64.random(in: 0...UInt64.max)
    @State private var notViewedShuffleSeed: UInt64 = UInt64.random(in: 0...UInt64.max)

    private let sectionPadding: CGFloat = 16
    private let rowSpacing: CGFloat = 12
    private let cardWidth: CGFloat = 148
    private let tileCorner: CGFloat = 20
    private let maxCardsPerSection = 10

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                continueReading
                collectionRow(
                    title: "Latest Galleries",
                    previewItems: latestPreviewItems,
                    allItems: latestAllItems,
                    emptyTitle: "No recent galleries",
                    emptyMessage: "Import numbered files to create galleries."
                )
                collectionRow(
                    title: "Favorite Galleries",
                    previewItems: favoritesPreviewItems,
                    allItems: favoritesAllItems,
                    emptyTitle: "No favorites",
                    emptyMessage: "Tap the heart on an album to add it here."
                )
                collectionRow(
                    title: "Not Viewed",
                    previewItems: notViewedPreviewItems,
                    allItems: notViewedAllItems,
                    emptyTitle: "All caught up",
                    emptyMessage: "You have viewed all albums. Good job!"
                )
            }
            .padding(.horizontal, sectionPadding)
            .padding(.bottom, 8)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("HoneyBox")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    SettingsView(env: env)
                } label: {
                    Image(systemName: "slider.horizontal.2.square")
                        .foregroundStyle(.primary)
                }
                .tint(.primary)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showImportChoice = true
                } label: {
                    Image(systemName: "square.and.arrow.down")
                        .foregroundStyle(.primary)
                }
                .tint(.primary)
                .accessibilityLabel("Import photos")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showShuffle = true
                } label: {
                    Image(systemName: "shuffle")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Shuffle all")
            }
        }
        .alert("Import from", isPresented: $showImportChoice) {
            Button("Photos") { showPhotosImport = true }
            Button("Files") { showFileImport = true }
            Button(".zip Gallery") { showZipGalleryImport = true }
            Button("Cancel", role: .cancel) {}
        }
        .photosPicker(
            isPresented: $showPhotosImport,
            selection: $pendingPhotoItems,
            matching: .images
        )
        .onChange(of: pendingPhotoItems) { _, newValue in
            guard !newValue.isEmpty else { return }
            isPreparingImport = true
            Task {
                do {
                    let urls = try await exportPhotoItemsToTempFiles(newValue)
                    await MainActor.run {
                        pendingPhotoItems = []
                        isPreparingImport = false
                        importPayload = HomeImportPayload(id: UUID(), urls: urls, stagingSessionDirectory: nil)
                    }
                } catch {
                    await MainActor.run {
                        pendingPhotoItems = []
                        isPreparingImport = false
                        importMessage = error.localizedDescription
                        showImportAlert = true
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $showFileImport,
            allowedContentTypes: [.image, .jpeg, .png, .gif, UTType(filenameExtension: "webp") ?? .data],
            allowsMultipleSelection: true
        ) { result in
            Task { await handleFileImporterResult(result) }
        }
        .fileImporter(
            isPresented: $showZipGalleryImport,
            allowedContentTypes: [.zip],
            allowsMultipleSelection: false
        ) { result in
            Task { await handleZipGalleryImporterResult(result) }
        }
        .navigationDestination(item: $importPayload) { payload in
            ImportDestinationView(
                env: env,
                fileURLs: payload.urls,
                stagingSessionDirectory: payload.stagingSessionDirectory,
                onComplete: { _ in
                    importPayload = nil
                }
            )
        }
        .navigationDestination(item: $zipGalleryImportPayload) { payload in
            ZipGalleryImportDestinationView(
                env: env,
                extractedImageURLs: payload.extractedImageURLs,
                stagingSessionDirectory: payload.stagingSessionDirectory,
                suggestedGalleryTitle: payload.suggestedGalleryTitle,
                onComplete: { _ in
                    zipGalleryImportPayload = nil
                }
            )
        }
        .navigationDestination(item: $navSelection) { sel in
            switch sel.kind {
            case .albumDetail(let authorId, let authorName, let albumId, let albumTitle):
                AlbumDetailView(
                    env: env,
                    authorId: authorId,
                    authorName: authorName,
                    albumId: albumId,
                    albumTitle: albumTitle
                )
            case .viewerEntry(let authorId, let authorName, let albumId, let albumTitle, let startIndex):
                ImageViewerEntryView(
                    env: env,
                    authorId: authorId,
                    authorName: authorName,
                    albumId: albumId,
                    albumTitle: albumTitle,
                    startIndex: startIndex
                )
                .id("\(authorId)/\(albumId)-\(startIndex)")
            }
        }
        .fullScreenCover(isPresented: $showShuffle) {
            ImmersiveShuffleViewerShell(env: env)
        }
        .task { await env.refreshIndex() }
        .alert("Import", isPresented: $showImportAlert) {
            Button("OK", role: .cancel) { importMessage = nil }
        } message: {
            Text(importMessage ?? "")
        }
        .overlay {
            if isPreparingImport {
                ZStack {
                    Rectangle().fill(.black.opacity(0.35)).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Please wait…")
                            .font(.subheadline.weight(.semibold))
                    }
                    .padding(18)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .transition(.opacity)
            }
        }
    }

    private func handleFileImporterResult(_ result: Result<[URL], Error>) async {
        switch result {
        case .success(let urls):
            guard !urls.isEmpty else { return }
            await MainActor.run { isPreparingImport = true }
            do {
                let (staged, sessionDir) = try await ImportSecurityStaging.stageFilesForImport(urls)
                await MainActor.run {
                    isPreparingImport = false
                    importPayload = HomeImportPayload(id: UUID(), urls: staged, stagingSessionDirectory: sessionDir)
                }
            } catch {
                await MainActor.run {
                    isPreparingImport = false
                    importMessage = error.localizedDescription
                    showImportAlert = true
                }
            }
        case .failure(let error):
            await MainActor.run {
                importMessage = error.localizedDescription
                showImportAlert = true
            }
        }
    }

    private func handleZipGalleryImporterResult(_ result: Result<[URL], Error>) async {
        switch result {
        case .success(let urls):
            guard let zipURL = urls.first else { return }
            await MainActor.run { isPreparingImport = true }
            let started = zipURL.startAccessingSecurityScopedResource()
            defer {
                if started { zipURL.stopAccessingSecurityScopedResource() }
            }
            do {
                let (files, sessionDir) = try ZipGalleryImport.extractImagesToStaging(zipURL: zipURL)
                let suggested = zipURL.deletingPathExtension().lastPathComponent
                await MainActor.run {
                    isPreparingImport = false
                    zipGalleryImportPayload = HomeZipGalleryImportPayload(
                        id: UUID(),
                        extractedImageURLs: files,
                        stagingSessionDirectory: sessionDir,
                        suggestedGalleryTitle: suggested
                    )
                }
            } catch {
                await MainActor.run {
                    isPreparingImport = false
                    importMessage = error.localizedDescription
                    showImportAlert = true
                }
            }
        case .failure(let error):
            await MainActor.run {
                importMessage = error.localizedDescription
                showImportAlert = true
            }
        }
    }

    private func exportPhotoItemsToTempFiles(_ items: [PhotosPickerItem]) async throws -> [URL] {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("HoneyBoxPhotoImports", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var slots = Array<URL?>(repeating: nil, count: items.count)
        let concurrency = 5
        var start = 0
        while start < items.count {
            let end = min(start + concurrency, items.count)
            try await withThrowingTaskGroup(of: (Int, URL?).self) { group in
                for i in start..<end {
                    let item = items[i]
                    group.addTask {
                        guard let data = try await item.loadTransferable(type: Data.self) else { return (i, nil) }
                        let ext = preferredExtension(for: item)
                        let url = dir.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
                        try data.write(to: url, options: [.atomic])
                        return (i, url)
                    }
                }
                for try await (i, u) in group {
                    slots[i] = u
                }
            }
            start = end
        }
        return slots.compactMap { $0 }
    }

    private func preferredExtension(for item: PhotosPickerItem) -> String {
        let types = item.supportedContentTypes
        if types.contains(.gif) { return "gif" }
        if types.contains(.png) { return "png" }
        if types.contains(.heic) { return "heic" }
        if types.contains(.heif) { return "heif" }
        if types.contains(.jpeg) { return "jpg" }
        if let webp = UTType(filenameExtension: "webp"), types.contains(webp) { return "webp" }
        return "jpg"
    }

    @ViewBuilder
    private var continueReading: some View {
        continueReadingRow(
            title: "Continue Reading",
            items: continueReadingItems,
            emptyTitle: "No history yet",
            emptyMessage: "Open an album and we’ll keep your place here."
        )
    }

    private func continueReadingRow(
        title: String,
        items: [ContinueReadingItem],
        emptyTitle: String,
        emptyMessage: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.title3.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                if !items.isEmpty {
                    NavigationLink {
                        ContinueReadingHistoryView(env: env, title: title, items: items)
                    } label: {
                        HStack(spacing: 4) {
                            Text("More")
                            Image(systemName: "arrow.right")
                                .font(.caption.weight(.semibold))
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                }
            }

            if items.isEmpty {
                ContentUnavailableView(emptyTitle, systemImage: "clock", description: Text(emptyMessage))
                    .frame(maxWidth: .infinity)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: rowSpacing) {
                        ForEach(items) { item in
                            Button {
                                navSelection = HomeNavSelection(
                                    kind: .viewerEntry(
                                        authorId: item.authorId,
                                        authorName: item.authorName,
                                        albumId: item.album.id,
                                        albumTitle: item.album.displayTitle,
                                        startIndex: item.startIndex
                                    )
                                )
                            } label: {
                                HomeAlbumTile(
                                    env: env,
                                    authorId: item.authorId,
                                    authorName: item.authorName,
                                    album: item.album,
                                    decodeMaxEdge: 720,
                                    cornerRadius: tileCorner,
                                    cardWidth: cardWidth
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func collectionRow(
        title: String,
        previewItems: [HomeAlbumItem],
        allItems: [HomeAlbumItem],
        emptyTitle: String,
        emptyMessage: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.title3.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                NavigationLink {
                    AlbumBrowserListView(env: env, title: title, items: allItems)
                } label: {
                    HStack(spacing: 4) {
                        Text("More")
                        Image(systemName: "arrow.right")
                            .font(.caption.weight(.semibold))
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }

            if allItems.isEmpty {
                ContentUnavailableView(emptyTitle, systemImage: emptySymbolForSection(title), description: Text(emptyMessage))
                    .frame(maxWidth: .infinity)
            } else {
                StableHomeSectionRow(
                    env: env,
                    items: previewItems,
                    selection: $navSelection,
                    rowSpacing: rowSpacing,
                    tileCorner: tileCorner,
                    cardWidth: cardWidth
                )
            }
        }
    }

    private var latestAllItems: [HomeAlbumItem] {
        env.indexSnapshot.authors.isEmpty ? [] : env.homeLatestAlbums(limit: Int.max).map { HomeAlbumItem(authorId: $0.authorId, album: $0.summary) }
    }

    private var latestPreviewItems: [HomeAlbumItem] {
        Array(latestAllItems.prefix(maxCardsPerSection))
    }

    private var favoritesAllItems: [HomeAlbumItem] {
        let base = env.homeFavoriteAlbums(limit: Int.max).map { HomeAlbumItem(authorId: $0.authorId, album: $0.summary) }
        var rng = SeededGenerator(seed: favoritesShuffleSeed)
        return base.shuffled(using: &rng)
    }

    private var favoritesPreviewItems: [HomeAlbumItem] {
        Array(favoritesAllItems.prefix(maxCardsPerSection))
    }

    private var notViewedAllItems: [HomeAlbumItem] {
        let base = env.homeNotViewedAlbums(limit: Int.max).map { HomeAlbumItem(authorId: $0.authorId, album: $0.summary) }
        var rng = SeededGenerator(seed: notViewedShuffleSeed)
        return base.shuffled(using: &rng)
    }

    private var notViewedPreviewItems: [HomeAlbumItem] {
        Array(notViewedAllItems.prefix(maxCardsPerSection))
    }

    private var continueReadingItems: [ContinueReadingItem] {
        env.homeContinueReadingItems(limit: maxCardsPerSection)
    }

    private func emptySymbolForSection(_ title: String) -> String {
        switch title {
        case "Latest Galleries":
            return "tray.and.arrow.down"
        case "Favorite Galleries":
            return "heart"
        case "Not Viewed":
            return "eye"
        default:
            return "photo.on.rectangle.angled"
        }
    }
}

private struct HomeImportPayload: Identifiable, Hashable {
    let id: UUID
    let urls: [URL]
    let stagingSessionDirectory: URL?

    static func == (lhs: HomeImportPayload, rhs: HomeImportPayload) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

private struct HomeZipGalleryImportPayload: Identifiable, Hashable {
    let id: UUID
    let extractedImageURLs: [URL]
    let stagingSessionDirectory: URL
    let suggestedGalleryTitle: String

    static func == (lhs: HomeZipGalleryImportPayload, rhs: HomeZipGalleryImportPayload) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

fileprivate struct StableHomeSectionRow: View {
    @ObservedObject var env: HoneyBoxEnvironment
    let items: [HomeAlbumItem]
    @Binding var selection: HomeNavSelection?
    let rowSpacing: CGFloat
    let tileCorner: CGFloat
    let cardWidth: CGFloat

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: rowSpacing) {
                ForEach(items) { item in
                    if let author = env.indexSnapshot.authors.first(where: { $0.id == item.authorId }) {
                        Button {
                            selection = HomeNavSelection(
                                kind: .albumDetail(
                                    authorId: item.authorId,
                                    authorName: author.name,
                                    albumId: item.album.id,
                                    albumTitle: item.album.displayTitle
                                )
                            )
                        } label: {
                            HomeAlbumTile(
                                env: env,
                                authorId: item.authorId,
                                authorName: author.name,
                                album: item.album,
                                decodeMaxEdge: 720,
                                cornerRadius: tileCorner,
                                cardWidth: cardWidth
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

private struct HomeAlbumTile: View {
    @ObservedObject var env: HoneyBoxEnvironment
    let authorId: String
    let authorName: String
    let album: AlbumSummaryDTO
    var decodeMaxEdge: CGFloat
    var cornerRadius: CGFloat
    var cardWidth: CGFloat

    @Environment(\.displayScale) private var displayScale
    @State private var image: CGImage?

    private var cardHeight: CGFloat { cardWidth * 4 / 3 }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color(.secondarySystemFill)
            if let image {
                Image(decorative: image, scale: displayScale, orientation: .up)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: cardWidth, height: cardHeight)
                    .clipped()
            }
            LinearGradient(
                colors: [.black.opacity(0.58), .black.opacity(0.2), .clear],
                startPoint: .bottom,
                endPoint: .center
            )
            Text("\(album.displayTitle) by \(authorName)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.45), radius: 2, x: 0, y: 1)
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
        }
        .frame(width: cardWidth, height: cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: "\(authorId)-\(album.id)-\(album.coverThumbnailFileName ?? "")") {
            await load()
        }
    }

    private func load() async {
        guard let name = album.coverThumbnailFileName else {
            image = nil
            return
        }
        image = try? await env.imageLoader.loadThumbnailCGImage(
            authorId: authorId,
            albumId: album.id,
            thumbFileName: name,
            decodeMaxEdge: decodeMaxEdge
        )
    }
}

extension HoneyBoxEnvironment {
    func homeLatestAlbums(limit: Int) -> [(authorId: String, summary: AlbumSummaryDTO)] {
        let keys = indexSnapshot.recentlyAdded.prefix(limit)
        var out: [(String, AlbumSummaryDTO)] = []
        for entry in keys {
            if let s = indexSnapshot.albumsByAuthor[entry.authorId]?.first(where: { $0.id == entry.albumId }) {
                out.append((entry.authorId, s))
            }
        }
        return out
    }

    func homeFavoriteAlbums(limit: Int) -> [(authorId: String, summary: AlbumSummaryDTO)] {
        var out: [(String, AlbumSummaryDTO)] = []
        for key in indexSnapshot.favoriteAlbums {
            let parts = key.split(separator: "/", maxSplits: 1).map(String.init)
            guard parts.count == 2,
                  let s = indexSnapshot.albumsByAuthor[parts[0]]?.first(where: { $0.id == parts[1] }) else { continue }
            out.append((parts[0], s))
            if out.count >= limit { break }
        }
        return out
    }

    func homeNotViewedAlbums(limit: Int) -> [(authorId: String, summary: AlbumSummaryDTO)] {
        var collected: [(String, AlbumSummaryDTO)] = []
        for author in indexSnapshot.authors {
            guard let albums = indexSnapshot.albumsByAuthor[author.id] else { continue }
            for a in albums where a.lastOpenedAt == nil {
                collected.append((author.id, a))
            }
        }
        collected.sort { $0.1.updatedAt > $1.1.updatedAt }
        return Array(collected.prefix(limit))
    }
}

fileprivate struct ContinueReadingItem: Identifiable {
    var id: String { "\(authorId)/\(album.id)" }
    let authorId: String
    let authorName: String
    let album: AlbumSummaryDTO
    let startIndex: Int
}

fileprivate extension HoneyBoxEnvironment {
    func homeContinueReadingItems(limit: Int) -> [ContinueReadingItem] {
        guard !indexSnapshot.recentlyViewed.isEmpty else { return [] }
        var out: [ContinueReadingItem] = []
        out.reserveCapacity(min(limit, indexSnapshot.recentlyViewed.count))

        for entry in indexSnapshot.recentlyViewed.prefix(limit) {
            guard let author = indexSnapshot.authors.first(where: { $0.id == entry.authorId }),
                  let album = indexSnapshot.albumsByAuthor[entry.authorId]?.first(where: { $0.id == entry.albumId }) else {
                continue
            }
            let key = ImageRef.globalAlbumKey(authorId: entry.authorId, albumId: entry.albumId)
            let startIndex = indexSnapshot.continueReadingProgress[key] ?? 0
            out.append(
                ContinueReadingItem(
                    authorId: entry.authorId,
                    authorName: author.name,
                    album: album,
                    startIndex: startIndex
                )
            )
        }
        return out
    }
}

fileprivate struct ContinueReadingHistoryView: View {
    @ObservedObject var env: HoneyBoxEnvironment
    let title: String
    let items: [ContinueReadingItem]
    @State private var stableItems: [ContinueReadingItem] = []

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                ForEach(stableItems.isEmpty ? items : stableItems) { item in
                    NavigationLink {
                        ImageViewerEntryView(
                            env: env,
                            authorId: item.authorId,
                            authorName: item.authorName,
                            albumId: item.album.id,
                            albumTitle: item.album.displayTitle,
                            startIndex: item.startIndex
                        )
                        .id("\(item.id)-\(item.startIndex)")
                    } label: {
                        ContinueReadingCardRow(
                            env: env,
                            authorId: item.authorId,
                            authorName: item.authorName,
                            album: item.album
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 24)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if stableItems.isEmpty {
                stableItems = items
            }
        }
    }
}

fileprivate struct ContinueReadingCardRow: View {
    @ObservedObject var env: HoneyBoxEnvironment
    let authorId: String
    let authorName: String
    let album: AlbumSummaryDTO

    @Environment(\.displayScale) private var displayScale
    @State private var cg: CGImage?

    var body: some View {
        ZStack {
            Color(.secondarySystemFill)
            if let cg {
                Image(decorative: cg, scale: displayScale, orientation: .up)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            }
        }
        .frame(height: 128)
        .overlay {
            Color.black.opacity(0.25)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .bottom) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(authorName)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.88))
                    Text(album.displayTitle)
                        .font(.headline)
                        .foregroundStyle(.white)
                }
                Spacer()
                HStack(spacing: 6) {
                    Text("\(album.imageCount) Photos")
                        .font(.footnote)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                }
                .foregroundStyle(.white.opacity(0.9))
            }
            .padding(16)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .task(id: "\(authorId)-\(album.id)-\(album.coverThumbnailFileName ?? "")") {
            guard let name = album.coverThumbnailFileName else {
                cg = nil
                return
            }
            cg = try? await env.imageLoader.loadThumbnailCGImage(
                authorId: authorId,
                albumId: album.id,
                thumbFileName: name,
                decodeMaxEdge: 1100
            )
        }
    }
}

struct HomeAlbumItem: Identifiable, Sendable {
    let authorId: String
    let album: AlbumSummaryDTO
    var id: String { "\(authorId)/\(album.id)" }
}

fileprivate struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed == 0 ? 0xDEADBEEF : seed }

    mutating func next() -> UInt64 {
        // SplitMix64
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

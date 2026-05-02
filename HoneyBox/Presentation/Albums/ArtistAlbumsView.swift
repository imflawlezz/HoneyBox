import SwiftUI
import UniformTypeIdentifiers

struct ArtistAlbumsView: View {
    @ObservedObject var env: HoneyBoxEnvironment
    let authorId: String
    let authorName: String

    @AppStorage("honeybox.albumsViewMode") private var useGrid: Bool = false
    @State private var sortLatest = true
    @State private var filter: AlbumsFilter = .all
    @State private var showImport = false
    @State private var importMessage: String?
    @State private var showImportAlert = false
    @State private var contentWidth: CGFloat = 0
    @State private var showArtistImmersive = false
    @State private var artistImmersivePlaylist: [ImageRef] = []
    @State private var isBuildingArtistPlaylist = false
    @State private var isStagingImport = false

    private var albums: [AlbumSummaryDTO] {
        let sort: AlbumsSortOrder = sortLatest ? .latestFirst : .oldestFirst
        var list = env.indexSnapshot.albumsByAuthor[authorId] ?? []
        switch filter {
        case .all: break
        case .favoritesOnly:
            let fav = Set(env.indexSnapshot.favoriteAlbums)
            list = list.filter { fav.contains(ImageRef.globalAlbumKey(authorId: authorId, albumId: $0.id)) }
        case .notViewedOnly:
            list = list.filter { $0.lastOpenedAt == nil }
        }
        if sortLatest {
            list.sort { $0.updatedAt > $1.updatedAt }
        } else {
            list.sort { $0.updatedAt < $1.updatedAt }
        }
        return list
    }

    var body: some View {
        Group {
            if albums.isEmpty {
                EmptyStateView(
                    systemImage: "rectangle.stack",
                    title: "No albums",
                    message: "Use + to import images for this artist."
                )
            } else if useGrid {
                ScrollView {
                    MosaicContentWidthProbe(horizontalPadding: 16)

                    if contentWidth > 0 {
                        let metrics = MosaicMetrics(contentWidth: contentWidth, gap: 10, cornerRadius: 20)
                        MosaicGridView(rows: mosaicRows(albums), metrics: metrics) { album in
                            AlbumMosaicCell(
                                env: env,
                                authorId: authorId,
                                authorName: authorName,
                                album: album,
                                cornerRadius: metrics.cornerRadius
                            )
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 32)
                        .id("\(sortLatest)-\(filter)")
                    }
                }
                .onPreferenceChange(MosaicContentWidthKey.self) { if $0 > 0 { contentWidth = $0 } }
            } else {
                List(albums) { album in
                    NavigationLink {
                        AlbumDetailView(env: env, authorId: authorId, authorName: authorName, albumId: album.id, albumTitle: album.displayTitle)
                    } label: {
                        albumRow(album: album)
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle(authorName)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isBuildingArtistPlaylist = true
                    Task {
                        let refs = await buildOrderedArtistPlaylist()
                        await MainActor.run {
                            isBuildingArtistPlaylist = false
                            guard !refs.isEmpty else { return }
                            artistImmersivePlaylist = refs
                            showArtistImmersive = true
                        }
                    }
                } label: {
                    Image(systemName: "play.square.stack")
                }
                .foregroundStyle(.primary)
                .tint(.primary)
                .disabled(albums.isEmpty)
                .accessibilityLabel("Play all albums")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Section("View as") {
                        Picker("View", selection: $useGrid) {
                            Label("Grid", systemImage: "square.grid.2x2").tag(true)
                            Label("List", systemImage: "list.bullet").tag(false)
                        }
                    }

                    Section("Order") {
                        Picker("Order", selection: $sortLatest) {
                            Label("Latest First", systemImage: "text.line.first.and.arrowtriangle.forward").tag(true)
                            Label("Oldest First", systemImage: "text.line.last.and.arrowtriangle.forward").tag(false)
                        }
                    }

                    Section("Filter") {
                        Picker("Filter", selection: $filter) {
                            Text("All").tag(AlbumsFilter.all)
                            Label("Favorites", systemImage: "heart").tag(AlbumsFilter.favoritesOnly)
                            Label("Not Viewed", systemImage: "eye.slash").tag(AlbumsFilter.notViewedOnly)
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                }
                .tint(.primary)
                .accessibilityLabel("View, order, and filter")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showImport = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Import")
            }
        }
        .fileImporter(
            isPresented: $showImport,
            allowedContentTypes: [.item, .image, .jpeg, .png, .gif, UTType(filenameExtension: "webp") ?? .data],
            allowsMultipleSelection: true
        ) { result in
            Task { await handleImport(result) }
        }
        .alert("Import", isPresented: $showImportAlert) {
            Button("OK", role: .cancel) { importMessage = nil }
        } message: {
            Text(importMessage ?? "")
        }
        .task { await env.refreshIndex() }
        .fullScreenCover(isPresented: $showArtistImmersive, onDismiss: {
            artistImmersivePlaylist = []
        }) {
            ImmersiveArtistPlaylistViewerShell(
                env: env,
                authorId: authorId,
                authorName: authorName,
                playlist: artistImmersivePlaylist
            )
        }
        .overlay {
            if isBuildingArtistPlaylist || isStagingImport {
                ZStack {
                    Rectangle().fill(.black.opacity(0.35)).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                        Text(isStagingImport ? "Copying files…" : "Preparing…")
                            .font(.subheadline.weight(.semibold))
                    }
                    .padding(18)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .transition(.opacity)
            }
        }
    }

    private func buildOrderedArtistPlaylist() async -> [ImageRef] {
        var refs: [ImageRef] = []
        refs.reserveCapacity(256)
        for album in albums {
            guard let meta = try? await env.index.loadAlbumMeta(authorId: authorId, albumId: album.id) else { continue }
            for name in meta.images {
                refs.append(ImageRef(authorId: authorId, albumId: album.id, fileName: name))
            }
        }
        return refs
    }

    private func albumRow(album: AlbumSummaryDTO) -> some View {
        HStack(spacing: 12) {
            AlbumThumbView(env: env, authorId: authorId, album: album, decodeMaxEdge: 360)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(album.displayTitle)
                    .font(.headline)
                Text("\(album.imageCount) photos")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if env.indexSnapshot.favoriteAlbums.contains(ImageRef.globalAlbumKey(authorId: authorId, albumId: album.id)) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.red)
            }
        }
    }

    private func mosaicRows(_ albums: [AlbumSummaryDTO]) -> [MosaicRow<AlbumSummaryDTO>] {
        var out: [MosaicRow<AlbumSummaryDTO>] = []
        var i = 0
        var flip = false
        while i < albums.count {
            let remaining = albums.count - i
            if remaining >= 3 {
                out.append(.featured(big: albums[i], s1: albums[i + 1], s2: albums[i + 2], bigOnRight: flip))
                flip.toggle()
                i += 3
            } else if remaining == 2 {
                out.append(.pair(a: albums[i], b: albums[i + 1]))
                i += 2
            } else {
                out.append(.single(albums[i]))
                i += 1
            }
        }
        return out
    }

    private func handleImport(_ result: Result<[URL], Error>) async {
        switch result {
        case .success(let urls):
            guard !urls.isEmpty else { return }
            await MainActor.run { isStagingImport = true }
            do {
                let (staged, sessionDir) = try await ImportSecurityStaging.stageFilesForImport(urls)
                await MainActor.run { isStagingImport = false }
                defer { ImportSecurityStaging.removeSessionDirectory(sessionDir) }
                let report = try await env.importPipeline.importFiles(authorId: authorId, fileURLs: staged)
                await env.refreshIndex()
            } catch {
                await MainActor.run { isStagingImport = false }
                await MainActor.run { importMessage = error.localizedDescription }
                await MainActor.run { showImportAlert = true }
            }
        case .failure(let error):
            await MainActor.run {
                importMessage = error.localizedDescription
                showImportAlert = true
            }
        }
    }
}

private struct AlbumThumbView: View {
    @ObservedObject var env: HoneyBoxEnvironment
    let authorId: String
    let album: AlbumSummaryDTO
    let decodeMaxEdge: CGFloat
    @Environment(\.displayScale) private var displayScale
    @State private var cg: CGImage?

    var body: some View {
        ZStack {
            Color.secondary.opacity(0.12)
            if let cg {
                Image(decorative: cg, scale: displayScale, orientation: .up)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: album.id) {
            guard let name = album.coverThumbnailFileName else { return }
            cg = try? await env.imageLoader.loadThumbnailCGImage(
                authorId: authorId,
                albumId: album.id,
                thumbFileName: name,
                decodeMaxEdge: decodeMaxEdge
            )
        }
    }
}

private enum MosaicRow<T: Identifiable> {
    case featured(big: T, s1: T, s2: T, bigOnRight: Bool)
    case pair(a: T, b: T)
    case single(T)

    var rowId: String {
        switch self {
        case .featured(let big, let s1, let s2, let right):
            return "featured-\(right)-\(big.id)-\(s1.id)-\(s2.id)"
        case .pair(let a, let b):
            return "pair-\(a.id)-\(b.id)"
        case .single(let a):
            return "single-\(a.id)"
        }
    }
}

private struct MosaicMetrics {
    let contentWidth: CGFloat
    let gap: CGFloat
    let cornerRadius: CGFloat

    var unit: CGFloat { (contentWidth - gap) / 2 }
    var bigHeight: CGFloat { unit * 2 + gap }
}

private struct MosaicGridView<T: Identifiable, Cell: View>: View {
    let rows: [MosaicRow<T>]
    let metrics: MosaicMetrics
    @ViewBuilder var cell: (T) -> Cell

    var body: some View {
        LazyVStack(spacing: metrics.gap) {
            ForEach(rows, id: \.rowId) { row in
                MosaicRowView(row: row, metrics: metrics, cell: cell)
            }
        }
    }
}

private struct MosaicRowView<T: Identifiable, Cell: View>: View {
    let row: MosaicRow<T>
    let metrics: MosaicMetrics
    @ViewBuilder var cell: (T) -> Cell

    var body: some View {
        switch row {
        case .featured(let big, let s1, let s2, let bigOnRight):
            HStack(spacing: metrics.gap) {
                if !bigOnRight {
                    cell(big).frame(width: metrics.unit, height: metrics.bigHeight)
                }
                VStack(spacing: metrics.gap) {
                    cell(s1).frame(width: metrics.unit, height: metrics.unit)
                    cell(s2).frame(width: metrics.unit, height: metrics.unit)
                }
                if bigOnRight {
                    cell(big).frame(width: metrics.unit, height: metrics.bigHeight)
                }
            }
        case .pair(let a, let b):
            HStack(spacing: metrics.gap) {
                cell(a).frame(width: metrics.unit, height: metrics.unit)
                cell(b).frame(width: metrics.unit, height: metrics.unit)
            }
        case .single(let a):
            cell(a)
                .frame(maxWidth: .infinity)
                .frame(height: metrics.unit)
        }
    }
}

private struct MosaicContentWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct MosaicContentWidthProbe: View {
    let horizontalPadding: CGFloat
    var body: some View {
        GeometryReader { geo in
            Color.clear
                .preference(key: MosaicContentWidthKey.self, value: max(0, geo.size.width - horizontalPadding * 2))
        }
        .frame(height: 0)
    }
}

private struct AlbumMosaicCell: View {
    @ObservedObject var env: HoneyBoxEnvironment
    let authorId: String
    let authorName: String
    let album: AlbumSummaryDTO
    let cornerRadius: CGFloat

    var body: some View {
        NavigationLink {
            AlbumDetailView(env: env, authorId: authorId, authorName: authorName, albumId: album.id, albumTitle: album.displayTitle)
        } label: {
            ZStack(alignment: .bottomLeading) {
                Color(.secondarySystemFill)
                AlbumThumbView(env: env, authorId: authorId, album: album, decodeMaxEdge: 900)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                LinearGradient(
                    colors: [.black.opacity(0.62), .black.opacity(0.25), .clear],
                    startPoint: .bottom,
                    endPoint: .center
                )
                HStack {
                    Text(album.displayTitle)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.6), radius: 3, x: 0, y: 1)
                    Spacer()
                    if env.indexSnapshot.favoriteAlbums.contains(ImageRef.globalAlbumKey(authorId: authorId, albumId: album.id)) {
                        Image(systemName: "heart.fill")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.red)
                            .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                    }
                }
                .padding(10)
            }
            .contentShape(Rectangle())
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

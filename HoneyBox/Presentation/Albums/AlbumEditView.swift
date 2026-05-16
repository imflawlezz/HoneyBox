import SwiftUI
import UniformTypeIdentifiers

struct AlbumEditView: View {
    @ObservedObject var env: HoneyBoxEnvironment
    let authorId: String
    let authorName: String
    let albumId: String
    let albumTitle: String

    @Environment(\.dismiss) private var dismiss
    @State private var titleDraft: String = ""
    @State private var meta: AlbumMetaFile?
    @State private var imagesDraft: [String] = []
    @State private var pendingDelete: Set<String> = []
    @State private var showImporter = false
    @State private var showDeleteConfirm = false
    @State private var message: String?
    @State private var showAlert = false
    @State private var draggingImageName: String?
    @State private var isStagingAppend = false

    var body: some View {
        Group {
            if meta != nil {
                let horizontalPadding: CGFloat = 16
                GeometryReader { geo in
                    let contentWidth = max(0, geo.size.width - horizontalPadding * 2)
                    ScrollView {
                        VStack(spacing: 12) {
                            Form {
                                Section("Album name") {
                                    TextField("", text: $titleDraft)
                                        .textInputAutocapitalization(.words)
                                        .disableAutocorrection(true)
                                }
                            }
                            .scrollDisabled(true)
                            .scrollContentBackground(.hidden)
                            .background(Color.clear)
                            .frame(height: 120)
                            .padding(.horizontal, horizontalPadding)

                            if contentWidth > 0 {
                                let spacing: CGFloat = 6
                                let tile = floor((contentWidth - spacing * 2) / 3)
                                let columns = Array(repeating: GridItem(.fixed(tile), spacing: spacing), count: 3)

                                LazyVGrid(columns: columns, spacing: spacing) {
                                    ForEach(imagesDraft, id: \.self) { name in
                                        ZStack(alignment: .topTrailing) {
                                            AlbumImageThumbCell(
                                                env: env,
                                                authorId: authorId,
                                                albumId: albumId,
                                                fileName: name,
                                                decodeMaxEdge: 720
                                            )
                                            .frame(width: tile, height: tile)
                                            .clipped()

                                            Button(role: .destructive) {
                                                pendingDelete.insert(name)
                                                imagesDraft.removeAll { $0 == name }
                                            } label: {
                                                Image(systemName: "xmark.circle.fill")
                                                    .font(.title3)
                                                    .foregroundStyle(.red)
                                                    .symbolRenderingMode(.hierarchical)
                                                    .padding(6)
                                            }
                                            .buttonStyle(.plain)
                                            .accessibilityLabel("Remove image (requires Save)")
                                        }
                                        .frame(width: tile, height: tile)
                                        .clipped()
                                        .onDrag {
                                            draggingImageName = name
                                            return NSItemProvider(object: name as NSString)
                                        }
                                        .onDrop(
                                            of: [.text],
                                            delegate: ImageReorderDropDelegate(
                                                item: name,
                                                items: $imagesDraft,
                                                dragging: $draggingImageName
                                            )
                                        )
                                    }

                                    Button {
                                        showImporter = true
                                    } label: {
                                        ZStack {
                                            Color.secondary.opacity(0.12)
                                            Image(systemName: "plus")
                                                .font(.title)
                                                .foregroundStyle(.secondary)
                                        }
                                        .frame(width: tile, height: tile)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, horizontalPadding)
                                .padding(.bottom, 32)
                            }
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Editing")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text("Editing")
                        .font(.subheadline.weight(.semibold))
                    Text("\((titleDraft.isEmpty ? albumTitle : titleDraft)) by \(authorName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                }
                .tint(.red)
                .accessibilityLabel("Delete album")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await save() }
                } label: {
                    Image(systemName: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .clipShape(Circle())
                .accessibilityLabel("Save")
            }
        }
        .task { await load() }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.image, .jpeg, .png, .gif, UTType(filenameExtension: "webp") ?? .data],
            allowsMultipleSelection: true
        ) { result in
            Task { await append(result) }
        }
        .confirmationDialog("Delete entire album?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete album", role: .destructive) {
                Task { await deleteAlbum() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the album folder and index entries.")
        }
        .alert("Album", isPresented: $showAlert) {
            Button("OK", role: .cancel) { message = nil }
        } message: {
            Text(message ?? "")
        }
        .overlay {
            if isStagingAppend {
                ZStack {
                    Rectangle().fill(.black.opacity(0.35)).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Copying files…")
                            .font(.subheadline.weight(.semibold))
                    }
                    .padding(18)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .transition(.opacity)
            }
        }
    }

    private func load() async {
        do {
            let m = try await env.loadAlbumMeta(authorId: authorId, albumId: albumId)
            await MainActor.run {
                meta = m
                titleDraft = m.displayTitle
                imagesDraft = m.images
                pendingDelete = []
            }
        } catch {}
    }

    private func save() async {
        do {
            try await env.updateAlbumDisplayTitle(authorId: authorId, albumId: albumId, title: titleDraft)
            try await env.setAlbumImageOrder(authorId: authorId, albumId: albumId, images: imagesDraft)
            for name in pendingDelete {
                try await env.deleteAlbumImage(authorId: authorId, albumId: albumId, fileName: name)
            }
            dismiss()
        } catch {
            message = error.localizedDescription
            showAlert = true
        }
    }

    private func append(_ result: Result<[URL], Error>) async {
        switch result {
        case .success(let urls):
            guard !urls.isEmpty else { return }
            await MainActor.run { isStagingAppend = true }
            do {
                let (staged, sessionDir) = try await ImportSecurityStaging.stageFilesForImport(urls)
                await MainActor.run { isStagingAppend = false }
                defer { ImportSecurityStaging.removeSessionDirectory(sessionDir) }
                _ = try await env.appendLooseImages(authorId: authorId, albumId: albumId, fileURLs: staged)
                let m = try await env.loadAlbumMeta(authorId: authorId, albumId: albumId)
                await MainActor.run {
                    meta = m
                    imagesDraft = m.images
                    pendingDelete = []
                }
            } catch {
                await MainActor.run { isStagingAppend = false }
                await MainActor.run {
                    message = error.localizedDescription
                    showAlert = true
                }
            }
        case .failure(let error):
            await MainActor.run {
                message = error.localizedDescription
                showAlert = true
            }
        }
    }

    private func deleteAlbum() async {
        let root = env.albumDirectoryURL(authorId: authorId, albumId: albumId)
        do {
            try env.removeLibraryItem(at: root)
            try await env.removeAlbumFromLibrary(authorId: authorId, albumId: albumId)
            dismiss()
        } catch {
            message = error.localizedDescription
            showAlert = true
        }
    }

    private func deleteImage(_ name: String) async {
        do {
            try await env.deleteAlbumImage(authorId: authorId, albumId: albumId, fileName: name)
            let m = try await env.loadAlbumMeta(authorId: authorId, albumId: albumId)
            await MainActor.run { meta = m }
        } catch {
            message = error.localizedDescription
            showAlert = true
        }
    }
}

private struct ImageReorderDropDelegate: DropDelegate {
    let item: String
    @Binding var items: [String]
    @Binding var dragging: String?

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != item,
              let from = items.firstIndex(of: dragging),
              let to = items.firstIndex(of: item) else { return }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
            items.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

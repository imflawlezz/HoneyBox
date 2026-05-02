import SwiftUI

struct ArtistsListView: View {
    @ObservedObject var env: HoneyBoxEnvironment
    @State private var newArtistName = ""
    @State private var showAdd = false
    @State private var renameAuthorId: String?
    @State private var renameText: String = ""
    @State private var showRename = false
    @State private var deleteAuthorId: String?
    @State private var showDeleteConfirm = false

    var body: some View {
        Group {
            if env.librarySnapshot.authors.isEmpty {
                EmptyStateView(
                    systemImage: "person.2",
                    title: "No artists yet",
                    message: "Add one to get started."
                )
                .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(env.librarySnapshot.authors) { author in
                        NavigationLink {
                            ArtistAlbumsView(env: env, authorId: author.id, authorName: author.name)
                        } label: {
                            HStack(spacing: 12) {
                                AuthorAvatarView(env: env, author: author)
                                    .frame(width: 52, height: 52)
                                    .clipShape(Circle())
                                    .overlay(Circle().strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(author.name)
                                        .font(.headline)
                                    Text("\(author.albumCount) albums")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button {
                                renameAuthorId = author.id
                                renameText = author.name
                                showRename = true
                            } label: {
                                Image(systemName: "pencil")
                            }
                            .tint(.orange)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                deleteAuthorId = author.id
                                showDeleteConfirm = true
                            } label: {
                                Image(systemName: "trash")
                            }
                            .tint(.red)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Artists")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAdd = true
                } label: {
                    Image(systemName: "person.crop.circle.badge.plus")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Add artist")
            }
        }
        .alert("New artist", isPresented: $showAdd) {
            TextField("Name", text: $newArtistName)
            Button("Cancel", role: .cancel) { newArtistName = "" }
            Button("Create") {
                Task { await createArtist() }
            }
        } message: {
            Text("Artist name")
        }
        .alert("Rename artist", isPresented: $showRename) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) {
                renameAuthorId = nil
                renameText = ""
            }
            Button("Save") {
                Task { await renameArtist() }
            }
        } message: {
            Text("Enter a new name.")
        }
        .confirmationDialog("Delete artist?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete Artist", role: .destructive) {
                Task { await deleteArtistCascade() }
            }
            Button("Cancel", role: .cancel) {
                deleteAuthorId = nil
            }
        } message: {
            Text("This will delete the artist, all albums, and all photos from this device.")
        }
        .task { await env.refreshLibrarySnapshot() }
    }

    private func createArtist() async {
        let name = newArtistName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        do {
            _ = try await env.createAuthor(displayName: name)
            newArtistName = ""
        } catch {
        }
    }

    private func renameArtist() async {
        guard let id = renameAuthorId else { return }
        let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        do {
            try await env.renameAuthor(authorId: id, newName: name)
        } catch {
        }
        renameAuthorId = nil
        renameText = ""
    }

    private func deleteArtistCascade() async {
        guard let id = deleteAuthorId else { return }
        do {
            try await env.deleteAuthorCascade(authorId: id)
            env.invalidateImageCaches()
        } catch {
        }
        deleteAuthorId = nil
    }
}

private struct AuthorAvatarView: View {
    @ObservedObject var env: HoneyBoxEnvironment
    let author: AuthorSummaryDTO
    @Environment(\.displayScale) private var displayScale
    @State private var cg: CGImage?

    var body: some View {
        ZStack {
            Color.secondary.opacity(0.2)
            if let cg {
                Image(decorative: cg, scale: displayScale, orientation: .up)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            } else if author.avatarFileName == nil {
                Image(systemName: "person.fill")
                    .resizable()
                    .scaledToFit()
                    .padding(10)
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: "\(author.id)-\(author.avatarFileName ?? "")") {
            guard let file = author.avatarFileName else {
                cg = nil
                return
            }
            let url = env.authorDirectoryURL(authorId: author.id)
                .appendingPathComponent(file, isDirectory: false)
            cg = try? await env.images.loadDownsampledCGImage(url: url, maxPixel: 256)
        }
    }
}

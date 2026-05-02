import SwiftUI

struct ZipGalleryImportDestinationView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var env: HoneyBoxEnvironment
    let extractedImageURLs: [URL]
    let stagingSessionDirectory: URL
    let suggestedGalleryTitle: String
    let onComplete: (String) -> Void

    @State private var galleryTitle: String
    @State private var selection: String = "__new__"
    @State private var newArtistName: String = ""
    @State private var isBusy = false
    @State private var message: String?
    @State private var showAlert = false
    @State private var copyDone = 0
    @State private var copyTotal = 1
    @State private var thumbDone = 0
    @State private var thumbTotal = 1
    @State private var activePhase: ImportProgressPhase = .copying
    @State private var importStatus = ""

    init(
        env: HoneyBoxEnvironment,
        extractedImageURLs: [URL],
        stagingSessionDirectory: URL,
        suggestedGalleryTitle: String,
        onComplete: @escaping (String) -> Void
    ) {
        self.env = env
        self.extractedImageURLs = extractedImageURLs
        self.stagingSessionDirectory = stagingSessionDirectory
        self.suggestedGalleryTitle = suggestedGalleryTitle
        self.onComplete = onComplete
        _galleryTitle = State(initialValue: suggestedGalleryTitle)
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Images from .zip") {
                    Text("\(extractedImageURLs.count)")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Gallery") {
                TextField("Gallery name", text: $galleryTitle)
                    .textInputAutocapitalization(.words)
            }

            Section("Artist") {
                Picker("Artist", selection: $selection) {
                    Text("New artist…").tag("__new__")
                    ForEach(env.indexSnapshot.authors) { a in
                        Text(a.name).tag(a.id)
                    }
                }

                if selection == "__new__" {
                    TextField("New artist name", text: $newArtistName)
                        .textInputAutocapitalization(.words)
                        .disableAutocorrection(true)
                }
            }

            if isBusy {
                Section {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Copying to library")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            ProgressView(value: Double(copyDone), total: Double(max(copyTotal, 1))) {
                                Text("\(copyDone) / \(copyTotal)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.tertiary)
                            }
                            .tint(activePhase == .copying ? .accentColor : .secondary.opacity(0.35))
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Thumbnails")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            ProgressView(value: Double(thumbDone), total: Double(max(thumbTotal, 1))) {
                                Text("\(thumbDone) / \(thumbTotal)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.tertiary)
                            }
                            .tint(activePhase == .thumbnails ? .accentColor : .secondary.opacity(0.35))
                        }

                        if !importStatus.isEmpty {
                            Text(importStatus)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .listRowBackground(Color.clear)
                }
            }
        }
        .navigationTitle("Import gallery from .zip")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await runImport() }
                } label: {
                    if isBusy {
                        ProgressView()
                    } else {
                        Image(systemName: "checkmark")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isBusy || extractedImageURLs.isEmpty || !canImport)
            }
        }
        .alert("Import", isPresented: $showAlert) {
            Button("OK", role: .cancel) { message = nil }
        } message: {
            Text(message ?? "")
        }
        .onDisappear {
            ImportSecurityStaging.removeSessionDirectory(stagingSessionDirectory)
        }
    }

    private var canImport: Bool {
        let t = galleryTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return false }
        if selection == "__new__" {
            return !newArtistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return env.indexSnapshot.authors.contains(where: { $0.id == selection })
    }

    private func runImport() async {
        isBusy = true
        copyDone = 0
        copyTotal = max(1, extractedImageURLs.count)
        thumbDone = 0
        thumbTotal = max(1, extractedImageURLs.count)
        activePhase = .copying
        importStatus = "Starting…"
        defer { isBusy = false }
        do {
            let authorId: String
            if selection == "__new__" {
                let name = newArtistName.trimmingCharacters(in: .whitespacesAndNewlines)
                authorId = try await env.index.createAuthor(displayName: name)
                await env.refreshIndex()
            } else {
                authorId = selection
            }

            let title = galleryTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let report = try await env.importPipeline.importNewGallery(
                authorId: authorId,
                displayTitle: title,
                fileURLs: extractedImageURLs,
                onProgress: { phase, done, total, msg in
                    activePhase = phase
                    if phase == .copying {
                        copyDone = done
                        copyTotal = max(1, total)
                    } else {
                        thumbDone = done
                        thumbTotal = max(1, total)
                    }
                    importStatus = msg
                }
            )
            await env.refreshIndex()
            let summary = report.messages.first ?? "Imported \(report.importedImages) image(s)."
            onComplete(summary)
            dismiss()
        } catch {
            message = error.localizedDescription
            showAlert = true
        }
    }
}

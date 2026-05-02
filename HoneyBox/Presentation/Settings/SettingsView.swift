import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var env: HoneyBoxEnvironment
    @EnvironmentObject private var lock: AppLockManager
    @State private var showZipImporter = false
    @State private var showZipExportSheet = false
    @State private var zipRestorePick: ZipRestorePick?
    @State private var message: String?
    @State private var showMessageAlert = false
    @AppStorage("immersiveSlideshowIntervalSeconds") private var immersiveSlideshowIntervalSeconds: Double = 2.5

    private var libraryBusy: Bool {
        zipRestorePick != nil || showZipExportSheet
    }

    var body: some View {
        Form {
            Section("Security") {
                Toggle("Require Face ID / Passcode", isOn: $lock.appLockEnabled)
                    .onChange(of: lock.appLockEnabled) { _, on in
                        if on {
                            Task { await lock.authenticate() }
                        } else {
                            lock.noteLockDisabled()
                        }
                    }
            }

            Section("Library") {
                Button {
                    showZipImporter = true
                } label: {
                    Label("Restore from .zip", systemImage: "arrow.up.page.on.clipboard")
                }
                .disabled(libraryBusy)

                Button {
                    showZipExportSheet = true
                } label: {
                    Label("Export .zip", systemImage: "zipper.page")
                }
                .disabled(libraryBusy)
            }

            Section("Playback") {
                Stepper(
                    value: $immersiveSlideshowIntervalSeconds,
                    in: 0.5...30,
                    step: 0.5
                ) {
                    LabeledContent("Slideshow interval") {
                        Text("\(immersiveSlideshowIntervalSeconds, specifier: "%.1f")s")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Storage path") {
                Text(env.storage.rootURL.path)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .navigationTitle("Settings")
        .fileImporter(
            isPresented: $showZipImporter,
            allowedContentTypes: [UTType.zip],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                zipRestorePick = ZipRestorePick(url: url)
            case .failure(let error):
                message = error.localizedDescription
            }
        }
        .sheet(item: $zipRestorePick) { pick in
            ZipRestoreProgressSheet(
                env: env,
                url: pick.url,
                onFinished: { result in
                    zipRestorePick = nil
                    switch result {
                    case .success(let msg):
                        message = msg
                    case .failure(let err):
                        message = err.localizedDescription
                    }
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showZipExportSheet) {
            ZipExportProgressSheet(env: env, isPresented: $showZipExportSheet)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .alert("Backup", isPresented: $showMessageAlert) {
            Button("OK", role: .cancel) { message = nil }
        } message: {
            Text(message ?? "")
        }
        .onChange(of: message) { _, newVal in
            if newVal != nil { showMessageAlert = true }
        }
        .onChange(of: showMessageAlert) { _, shown in
            if !shown { message = nil }
        }
    }
}

private struct SimpleRestoreError: LocalizedError {
    var errorDescription: String? { message }
    let message: String
    init(_ message: String) { self.message = message }
}

private struct ZipRestorePick: Identifiable, Hashable {
    let id = UUID()
    let url: URL

    static func == (lhs: ZipRestorePick, rhs: ZipRestorePick) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

private struct ZipRestoreProgressSheet: View {
    @ObservedObject var env: HoneyBoxEnvironment
    let url: URL
    let onFinished: (Result<String, Error>) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var phase: ZipRestorePhase = .extracting
    @State private var done = 0
    @State private var total = 1
    @State private var currentLabel = ""
    @State private var successMessage: String?
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                if let errorText {
                    ContentUnavailableView(
                        "Restore failed",
                        systemImage: "exclamationmark.triangle.fill",
                        description: Text(errorText)
                    )
                    .symbolRenderingMode(.multicolor)
                } else if let successMessage {
                    VStack(spacing: 20) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 52))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.green, .primary.opacity(0.15))
                        Text("Library restored")
                            .font(.title2.weight(.semibold))
                        Text(successMessage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 8)
                } else {
                    VStack(spacing: 18) {
                        ZStack {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .frame(width: 88, height: 88)
                            Image(systemName: "arrow.up.page.on.clipboard")
                                .font(.system(size: 36, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        Text(titleForPhase)
                            .font(.title2.weight(.semibold))
                        ProgressView(value: Double(done), total: Double(max(total, 1))) {
                            Text("\(done) / \(total)")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .progressViewStyle(.linear)
                        .tint(.accentColor)
                        Text(currentLabel)
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, 12)
                }
                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Restore")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if successMessage != nil || errorText != nil {
                        Button("Done") {
                            if let successMessage {
                                onFinished(.success(successMessage))
                            } else if let errorText {
                                onFinished(.failure(SimpleRestoreError(errorText)))
                            }
                            dismiss()
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
            .interactiveDismissDisabled(successMessage == nil && errorText == nil)
        }
        .task {
            await runRestore()
        }
    }

    private var titleForPhase: String {
        switch phase {
        case .extracting: "Extracting backup"
        case .installing: "Installing library"
        case .finalizing: "Finishing up"
        }
    }

    private func runRestore() async {
        let started = url.startAccessingSecurityScopedResource()
        defer { if started { url.stopAccessingSecurityScopedResource() } }
        do {
            try await env.zip.restoreLibrary(from: url, indexService: env.index) { p, d, t, label in
                phase = p
                done = d
                total = t
                currentLabel = label
            }
            env.invalidateImageCaches()
            await env.refreshIndex()
            successMessage = "Your library was replaced with the backup contents."
        } catch {
            errorText = error.localizedDescription
        }
    }
}

private struct ZipExportProgressSheet: View {
    @ObservedObject var env: HoneyBoxEnvironment
    @Binding var isPresented: Bool
    @Environment(\.dismiss) private var dismiss

    @State private var done = 0
    @State private var total = 1
    @State private var currentLabel = "Preparing…"
    @State private var finishedURL: URL?
    @State private var errorText: String?
    @State private var tempExportZipURL: URL?

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                if let errorText {
                    ContentUnavailableView(
                        "Export failed",
                        systemImage: "exclamationmark.triangle.fill",
                        description: Text(errorText)
                    )
                    .symbolRenderingMode(.multicolor)
                } else if let url = finishedURL {
                    VStack(spacing: 20) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 52))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.green, .primary.opacity(0.15))
                        Text("Backup ready")
                            .font(.title2.weight(.semibold))
                        ShareLink(
                            item: url,
                            preview: SharePreview("HoneyBox backup", image: Image(systemName: "doc.zipper"))
                        ) {
                            Label("Share .zip", systemImage: "square.and.arrow.up")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                    .padding(.horizontal, 8)
                } else {
                    VStack(spacing: 18) {
                        ZStack {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .frame(width: 88, height: 88)
                            Image(systemName: "doc.zipper")
                                .font(.system(size: 36, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        Text("Creating backup")
                            .font(.title2.weight(.semibold))
                        ProgressView(value: Double(done), total: Double(max(total, 1))) {
                            Text("\(done) / \(total) files")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .progressViewStyle(.linear)
                        .tint(.accentColor)
                        Text(currentLabel)
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, 12)
                }
                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if finishedURL != nil || errorText != nil {
                        Button("Done") {
                            removeTemporaryExportFile()
                            finishedURL = nil
                            dismiss()
                            isPresented = false
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
            .interactiveDismissDisabled(finishedURL == nil && errorText == nil)
        }
        .task {
            await runExport()
        }
        .onDisappear {
            removeTemporaryExportFile()
        }
    }

    private func removeTemporaryExportFile() {
        guard let url = tempExportZipURL else { return }
        try? FileManager.default.removeItem(at: url)
        tempExportZipURL = nil
    }

    private func runExport() async {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("HoneyBox-backup-\(Int(Date().timeIntervalSince1970)).zip")
        do {
            try await env.zip.exportLibrary(to: url) { completed, fileTotal, path in
                done = completed
                total = fileTotal
                currentLabel = path.isEmpty ? "Compressing…" : path
            }
            finishedURL = url
            tempExportZipURL = url
        } catch {
            errorText = error.localizedDescription
            try? FileManager.default.removeItem(at: url)
        }
    }
}

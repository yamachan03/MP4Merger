import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct IntegrityCheckView: View {
    @EnvironmentObject var lm: LanguageManager
    @StateObject private var model = IntegrityCheckModel()
    @State private var expanded: Set<UUID> = []
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 10) {
            sourceSection
            optionsSection

            if model.isChecking || model.progress > 0 {
                progressSection
            }

            if let error = model.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red)
                    Text(error).foregroundColor(.red)
                    Spacer()
                }
                .padding(.horizontal)
            }

            resultsSection
                .frame(minHeight: 150, maxHeight: .infinity)

            footerSection
        }
        .padding(.bottom, 10)
    }

    // MARK: - Source

    private var sourceSection: some View {
        VStack(spacing: 8) {
            if model.hasTargets || model.isScanning || model.foundNothing {
                HStack {
                    Image(systemName: model.hasFolderInput ? "folder.fill" : "doc.fill")
                        .foregroundColor(model.foundNothing ? .orange : .accentColor)
                    Text(model.sourceLabel)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    if model.isScanning {
                        ProgressView().controlSize(.small)
                    } else if model.foundNothing {
                        Text(lm.localized("No MP4 or MOV files found"))
                            .font(.caption)
                            .foregroundColor(.orange)
                    } else {
                        Text(lm.localizedDynamic("{0} files / {1} total", args: [
                            "\(model.targets.count)",
                            IntegrityCheckModel.formatDuration(model.totalDuration)
                        ]))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "doc.badge.ellipsis")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text(lm.localized("Drop files or a folder to check"))
                        .foregroundColor(.secondary)
                    Text(lm.localized("A single file works too; folders are searched for MP4 and MOV"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.4),
                            style: StrokeStyle(lineWidth: 1.5, dash: [6])
                        )
                )
            }

            HStack {
                Button(lm.localized("Choose Files or Folders...")) { chooseFiles() }
                    .disabled(model.isChecking)
                if model.hasTargets || model.isScanning || model.foundNothing {
                    Button(lm.localized("Clear All")) {
                        expanded = []
                        model.clear()
                    }
                    .disabled(model.isChecking)
                }
                Spacer()
            }
        }
        .padding(.horizontal)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            guard !model.isChecking else { return false }
            handleDrop(providers)
            return true
        }
    }

    // MARK: - Options

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(lm.localized("Check Level"))
                .font(.headline)

            Picker("", selection: $model.level) {
                ForEach(CheckLevel.allCases) { level in
                    Text(lm.localized(level.titleKey)).tag(level)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Text(lm.localized(model.level.detailKey))
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if model.hasFolderInput {
                Toggle(lm.localized("Include Subfolders"), isOn: $model.includeSubfolders)
                    .toggleStyle(.checkbox)
                    .onChange(of: model.includeSubfolders) {
                        model.rescan()
                    }
            }

            if model.hasTargets {
                Text(lm.localizedDynamic("Estimated time: about {0}", args: [
                    IntegrityCheckModel.formatDuration(model.estimatedDuration)
                ]))
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
        .padding(.horizontal)
        .disabled(model.isChecking)
    }

    // MARK: - Progress

    private var progressSection: some View {
        VStack(spacing: 4) {
            ProgressView(value: model.progress)
                .progressViewStyle(.linear)

            HStack {
                Text(model.currentFileNames.isEmpty
                     ? lm.localized("Preparing...")
                     : model.currentFileNames.joined(separator: ", "))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if model.remainingTime >= 0 {
                    Text("\(lm.localized("Remaining:")) \(IntegrityCheckModel.formatDuration(model.remainingTime))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else if model.isChecking {
                    Text(lm.localized("Calculating remaining time..."))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Results

    private var resultsSection: some View {
        Group {
            if model.results.isEmpty {
                VStack {
                    Spacer()
                    if model.hasTargets && !model.isChecking {
                        Text(lm.localized("Ready to check"))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List(model.results) { result in
                    resultRow(result)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .padding(.horizontal)
    }

    private func resultRow(_ result: CheckResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: icon(for: result.status))
                    .foregroundColor(color(for: result.status))
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.url.lastPathComponent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("\(IntegrityCheckModel.formatDuration(result.duration))  ·  \(lm.localized("Checked in")) \(IntegrityCheckModel.formatDuration(result.elapsed))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if !result.log.isEmpty {
                    Button(expanded.contains(result.id) ? lm.localized("Hide Log") : lm.localized("Show Log")) {
                        if expanded.contains(result.id) {
                            expanded.remove(result.id)
                        } else {
                            expanded.insert(result.id)
                        }
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            }

            if expanded.contains(result.id) {
                ScrollView {
                    Text(result.log)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                }
                .frame(maxHeight: 140)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            NSWorkspace.shared.activateFileViewerSelecting([result.url])
        }
        .contextMenu {
            Button(lm.localized("Reveal in Finder")) {
                NSWorkspace.shared.activateFileViewerSelecting([result.url])
            }
        }
    }

    private func icon(for status: CheckStatus) -> String {
        switch status {
        case .ok: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .broken: return "xmark.octagon.fill"
        }
    }

    private func color(for status: CheckStatus) -> Color {
        switch status {
        case .ok: return .green
        case .warning: return .orange
        case .broken: return .red
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        VStack(spacing: 8) {
            if !model.results.isEmpty {
                HStack(spacing: 14) {
                    summaryChip(icon: "checkmark.circle.fill", color: .green,
                                label: lm.localized("OK"), count: model.okCount)
                    summaryChip(icon: "exclamationmark.triangle.fill", color: .orange,
                                label: lm.localized("Suspect"), count: model.warningCount)
                    summaryChip(icon: "xmark.octagon.fill", color: .red,
                                label: lm.localized("Damaged"), count: model.brokenCount)
                    Spacer()
                }
            }

            HStack {
                // A single call selects every damaged file at once; Finder opens as
                // many windows as it needs when they live in different folders.
                if !model.problemURLs.isEmpty {
                    Button(lm.localizedDynamic("Reveal {0} problem files in Finder",
                                               args: ["\(model.problemURLs.count)"])) {
                        NSWorkspace.shared.activateFileViewerSelecting(model.problemURLs)
                    }
                }

                Spacer()

                if model.isChecking {
                    Button(lm.localized("Cancel Processing"), role: .cancel) {
                        model.cancel()
                    }
                } else {
                    Button(lm.localized("Start Check")) {
                        expanded = []
                        model.start()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.hasTargets || model.isScanning)
                }
            }
        }
        .padding(.horizontal)
    }

    private func summaryChip(icon: String, color: Color, label: String, count: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).foregroundColor(color)
            Text("\(label) \(count)")
                .font(.caption)
        }
    }

    // MARK: - Input handling

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.message = lm.localized("Select folders or files to check")

        panel.begin { response in
            guard response == .OK, !panel.urls.isEmpty else { return }
            let urls = panel.urls
            Task { @MainActor in
                expanded = []
                model.load(urls: urls)
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        Task {
            var urls: [URL] = []
            for provider in providers {
                if let item = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil),
                   let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    urls.append(url)
                }
            }
            guard !urls.isEmpty else { return }
            await MainActor.run {
                expanded = []
                model.load(urls: urls)
            }
        }
    }
}

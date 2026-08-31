import SwiftUI

struct FFmpegSetupView: View {
    @EnvironmentObject var lm: LanguageManager
    @ObservedObject private var setup = FFmpegSetupManager.shared
    @Binding var isPresented: Bool
    var isUpdate: Bool = false

    @State private var homebrewCopied = false
    @State private var setupComplete = false
    @State private var errorText: String?

    private var homebrewCommand: String {
        isUpdate ? "brew upgrade ffmpeg" : "brew install ffmpeg"
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            if setupComplete {
                successView
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        homebrewSection
                        autoDownloadSection
                        if let error = errorText {
                            Label(error, systemImage: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                                .font(.caption)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 4)
                        }
                    }
                    .padding(20)
                }
            }
        }
        .frame(width: 500, height: 500)
        .interactiveDismissDisabled(setup.isDownloading)
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(spacing: 8) {
            Image(systemName: isUpdate ? "arrow.up.circle.fill" : "video.fill.badge.plus")
                .font(.system(size: 36))
                .foregroundColor(isUpdate ? .orange : .accentColor)
                .padding(.top, 24)

            Text(isUpdate
                 ? lm.localizedDynamic("FFmpeg Update Available", args: [FFmpegSetupManager.recommendedVersion])
                 : lm.localized("FFmpeg Required"))
                .font(.title2).fontWeight(.bold)

            Text(isUpdate
                 ? lm.localizedDynamic("FFmpeg Update Description", args: [
                     setup.installedVersion ?? "?",
                     FFmpegSetupManager.recommendedVersion
                   ])
                 : lm.localized("FFmpeg Setup Description"))
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
                .padding(.bottom, 16)
        }
    }

    // MARK: - Success

    private var successView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundColor(.green)
            Text(isUpdate ? lm.localized("Update Complete!") : lm.localized("Setup Complete!"))
                .font(.title3).fontWeight(.semibold)
            Text(lm.localized("FFmpeg Ready Message"))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
            Button(lm.localized("Get Started")) {
                isPresented = false
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Spacer()
        }
    }

    // MARK: - Section 1: Homebrew

    private var homebrewSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text(lm.localized("Homebrew Section Description"))
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    Text(homebrewCommand)
                        .font(.system(.body, design: .monospaced))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(6)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(homebrewCommand, forType: .string)
                        homebrewCopied = true
                        Task {
                            try? await Task.sleep(nanoseconds: 2_000_000_000)
                            homebrewCopied = false
                        }
                    } label: {
                        Label(
                            homebrewCopied ? lm.localized("Copied!") : lm.localized("Copy"),
                            systemImage: homebrewCopied ? "checkmark" : "doc.on.doc"
                        )
                    }
                    .frame(width: 100)
                }

                Button(lm.localized("Verify Homebrew Install")) {
                    if FFmpegSetupManager.isFFmpegAvailable() {
                        errorText = nil
                        setupComplete = true
                    } else {
                        errorText = lm.localized("FFmpeg Not Found After Install")
                    }
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label(
                isUpdate ? lm.localized("Update via Homebrew") : lm.localized("Install via Homebrew"),
                systemImage: "terminal"
            )
            .font(.headline)
        }
    }

    // MARK: - Section 2: Auto-download

    private var autoDownloadSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text(lm.localized("Auto Download Description"))
                    .font(.caption)
                    .foregroundColor(.secondary)

                // evermeet.cx ships Intel-only builds; say so before the user commits
                // to a ~52MB download that will then ask them to install Rosetta.
                if FFmpegSetupManager.isAppleSilicon {
                    Label(lm.localized("Intel Only Download Warning"), systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if setup.isDownloading {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(setup.phase)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        ProgressView(value: setup.downloadProgress)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Button {
                        errorText = nil
                        Task {
                            do {
                                try await setup.downloadAndInstall()
                                setupComplete = true
                            } catch {
                                errorText = error.localizedDescription
                            }
                        }
                    } label: {
                        Label(lm.localized("Download and Install"), systemImage: "arrow.down.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label(lm.localized("Download Automatically"), systemImage: "arrow.down.circle")
                .font(.headline)
        }
    }
}

import Foundation
import CryptoKit
import Combine

@MainActor
final class FFmpegSetupManager: ObservableObject {

    static let shared = FFmpegSetupManager()
    private init() {}

    // MARK: - Published State

    @Published var downloadProgress: Double = 0
    @Published var phase: String = ""
    @Published var isDownloading: Bool = false
    @Published var updateAvailable: Bool = false
    @Published var installedVersion: String? = nil

    // MARK: - Version Constants
    // To update FFmpeg: change the version string, URLs, and SHA256 below.
    // Get new SHA256 with: curl -sL <url> | shasum -a 256
    // All three (version, URL, SHA256) must be updated together.

    // In Xcode scheme: add "--simulate-update" or "--simulate-no-ffmpeg" to Arguments
    nonisolated static let recommendedVersion: String = {
        #if DEBUG
        if CommandLine.arguments.contains("--simulate-update") { return "99.0.0" }
        #endif
        return "8.1.2"
    }()


    private static let ffmpegZipURL  = URL(string: "https://evermeet.cx/ffmpeg/ffmpeg-8.1.2.zip")!
    private static let ffprobeZipURL = URL(string: "https://evermeet.cx/ffmpeg/ffprobe-8.1.2.zip")!

    // SHA256 verified on 2026-06-21 from evermeet.cx
    private static let ffmpegSHA256  = "e91df72a1ee7c26606f90dd2dd4dcccc6a75140ff9ea6fdd50faae828b82ba69"
    private static let ffprobeSHA256 = "399b93f0b9862f69767afa343e90c2f48d7e7958cadbb6deb76a012d0e3b7ce3"

    // MARK: - Install Paths

    nonisolated static var appSupportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MP4Merger")
    }

    nonisolated static var ffmpegPath: String {
        appSupportDirectory.appendingPathComponent("ffmpeg").path
    }

    nonisolated static var ffprobePath: String {
        appSupportDirectory.appendingPathComponent("ffprobe").path
    }

    // MARK: - Availability Check

    nonisolated static func isFFmpegAvailable() -> Bool {
        #if DEBUG
        if CommandLine.arguments.contains("--simulate-no-ffmpeg") { return false }
        #endif
        if Bundle.main.path(forResource: "ffmpeg", ofType: nil) != nil { return true }
        if FileManager.default.fileExists(atPath: ffmpegPath) { return true }
        if FileManager.default.fileExists(atPath: "/opt/homebrew/bin/ffmpeg") { return true }
        if FileManager.default.fileExists(atPath: "/usr/local/bin/ffmpeg") { return true }
        return false
    }

    nonisolated static var resolvedFFmpegExecutable: String? {
        if let p = Bundle.main.path(forResource: "ffmpeg", ofType: nil) { return p }
        if FileManager.default.fileExists(atPath: ffmpegPath) { return ffmpegPath }
        if FileManager.default.fileExists(atPath: "/opt/homebrew/bin/ffmpeg") { return "/opt/homebrew/bin/ffmpeg" }
        if FileManager.default.fileExists(atPath: "/usr/local/bin/ffmpeg") { return "/usr/local/bin/ffmpeg" }
        return nil
    }

    // MARK: - Version Check

    func checkForUpdate() async {
        guard let version = await Self.fetchInstalledVersion() else { return }
        installedVersion = version
        updateAvailable = Self.isOlderThan(version, Self.recommendedVersion)
    }

    nonisolated static func fetchInstalledVersion() async -> String? {
        guard let path = resolvedFFmpegExecutable else { return nil }

        return await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = ["-version"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()

            process.terminationHandler = { _ in
                let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                continuation.resume(returning: Self.parseVersionString(output))
            }
            do { try process.run() } catch { continuation.resume(returning: nil) }
        }
    }

    // Exposed for unit testing
    nonisolated static func parseVersionString(_ output: String) -> String? {
        // First line: "ffmpeg version 8.1.2 Copyright ..."
        let parts = (output.components(separatedBy: "\n").first ?? "")
            .components(separatedBy: " ")
        // Require exactly "ffmpeg version <x.y.z>" — skip snapshot builds like "N-123456-g..."
        guard parts.count >= 3,
              parts[0] == "ffmpeg",
              parts[1] == "version",
              parts[2].allSatisfy({ $0.isNumber || $0 == "." }),
              !parts[2].isEmpty else { return nil }
        return parts[2]
    }

    nonisolated static func isOlderThan(_ current: String, _ recommended: String) -> Bool {
        let v1 = current.split(separator: ".").compactMap { Int($0) }
        let v2 = recommended.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(v1.count, v2.count) {
            let a = i < v1.count ? v1[i] : 0
            let b = i < v2.count ? v2[i] : 0
            if a < b { return true }
            if a > b { return false }
        }
        return false
    }

    // MARK: - Download & Install

    func downloadAndInstall() async throws {
        isDownloading = true
        downloadProgress = 0
        defer { isDownloading = false }

        let dir = Self.appSupportDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let lm = LanguageManager.shared
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForResource = 600
        let session = URLSession(configuration: config)

        // --- ffmpeg ---
        phase = lm.localized("Downloading FFmpeg...")
        downloadProgress = 0.05
        let (ffmpegData, _) = try await session.data(from: Self.ffmpegZipURL)

        phase = lm.localized("Verifying FFmpeg...")
        downloadProgress = 0.4
        try Self.verify(data: ffmpegData, expectedSHA256: Self.ffmpegSHA256, name: "ffmpeg")

        phase = lm.localized("Extracting FFmpeg...")
        downloadProgress = 0.45
        let ffmpegDest = Self.appSupportDirectory.appendingPathComponent("ffmpeg")
        try await Self.extractAsync(data: ffmpegData, binaryName: "ffmpeg", to: ffmpegDest)

        // --- ffprobe ---
        phase = lm.localized("Downloading FFprobe...")
        downloadProgress = 0.5
        let (ffprobeData, _) = try await session.data(from: Self.ffprobeZipURL)

        phase = lm.localized("Verifying FFprobe...")
        downloadProgress = 0.85
        try Self.verify(data: ffprobeData, expectedSHA256: Self.ffprobeSHA256, name: "ffprobe")

        phase = lm.localized("Extracting FFprobe...")
        downloadProgress = 0.9
        let ffprobeDest = Self.appSupportDirectory.appendingPathComponent("ffprobe")
        try await Self.extractAsync(data: ffprobeData, binaryName: "ffprobe", to: ffprobeDest)

        // --- Test ---
        phase = lm.localized("Testing binary...")
        downloadProgress = 0.95
        try await Self.testBinaryAsync(at: ffmpegDest)

        phase = lm.localized("Setup Complete!")
        downloadProgress = 1.0
    }

    // MARK: - Private Helpers

    private static func verify(data: Data, expectedSHA256: String, name: String) throws {
        let digest = SHA256.hash(data: data)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        guard hex == expectedSHA256 else {
            try? FileManager.default.removeItem(atPath: ffmpegPath)
            try? FileManager.default.removeItem(atPath: ffprobePath)
            throw SetupError.checksumMismatch(name)
        }
    }

    nonisolated private static func extractAsync(data: Data, binaryName: String, to destination: URL) async throws {
        let tempZip = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).zip")
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        defer {
            try? FileManager.default.removeItem(at: tempZip)
            try? FileManager.default.removeItem(at: tempDir)
        }

        try data.write(to: tempZip)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzip.arguments = ["-q", "-o", tempZip.path, "-d", tempDir.path]
        unzip.standardOutput = Pipe()
        unzip.standardError = Pipe()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            unzip.terminationHandler = { proc in
                if proc.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: SetupError.extractionFailed(binaryName))
                }
            }
            do {
                try unzip.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }

        let extracted = tempDir.appendingPathComponent(binaryName)
        guard FileManager.default.fileExists(atPath: extracted.path) else {
            throw SetupError.extractionFailed(binaryName)
        }

        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: extracted, to: destination)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
    }

    nonisolated private static func testBinaryAsync(at url: URL) async throws {
        let process = Process()
        process.executableURL = url
        process.arguments = ["-version"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { proc in
                if proc.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: SetupError.binaryTestFailed)
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - Error

    enum SetupError: LocalizedError {
        case checksumMismatch(String)
        case extractionFailed(String)
        case binaryTestFailed
        case downloadFailed(String)

        var errorDescription: String? {
            switch self {
            case .checksumMismatch(let name):
                return "\(name) のチェックサムが一致しません。ダウンロードが改ざんされている可能性があります。"
            case .extractionFailed(let name):
                return "\(name) の展開に失敗しました。"
            case .binaryTestFailed:
                return "FFmpeg の動作確認に失敗しました。ダウンロードファイルを削除して再試行してください。"
            case .downloadFailed(let msg):
                return "ダウンロードに失敗しました: \(msg)"
            }
        }
    }
}

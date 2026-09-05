import Foundation

// How hard we make ffmpeg work. The decisive difference is whether the decoder
// runs at all: `-c copy` never decodes, so it sails past bitstream damage that a
// full decode catches immediately.
enum CheckLevel: String, CaseIterable, Identifiable {
    case quick
    case standard
    case full

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .quick: return "Check Level Quick"
        case .standard: return "Check Level Standard"
        case .full: return "Check Level Full"
        }
    }

    var detailKey: String {
        switch self {
        case .quick: return "Check Level Quick Detail"
        case .standard: return "Check Level Standard Detail"
        case .full: return "Check Level Full Detail"
        }
    }

    // Wall-clock seconds spent per second of footage, measured on an M1 Max
    // against 1080p30 H.264. estimate() scales this by pixel count.
    var realtimeFactor: Double {
        switch self {
        case .quick: return 0.003
        case .standard: return 0.015
        case .full: return 0.048
        }
    }

    // Software decoding only. VideoToolbox measures 3.5x slower here because a
    // decode session gives no frame-level parallelism, so hardware is the wrong
    // tool for verification even though it is the right one for encoding.
    fileprivate func arguments(for path: String) -> [String] {
        var args = ["-v", "warning", "-nostats", "-progress", "pipe:1"]
        switch self {
        case .quick:
            args += ["-i", path, "-c", "copy"]
        case .standard:
            args += ["-skip_frame", "nokey", "-i", path, "-an"]
        case .full:
            args += ["-i", path]
        }
        return args + ["-f", "null", "-"]
    }
}

enum CheckStatus {
    case ok
    case warning  // decoded, but ffmpeg flagged damaged frames
    case broken   // the bitstream or container is unreadable

    var isProblem: Bool { self != .ok }
}

struct CheckResult: Identifiable {
    let id = UUID()
    let url: URL
    let status: CheckStatus
    let log: String
    let duration: Double
    let elapsed: TimeInterval
}

struct VideoIntegrityChecker {
    struct Target: Identifiable, Hashable {
        let id = UUID()
        let url: URL
        let duration: Double
        // Relative to 1920x1080, so a 4K file costs roughly 4x the time.
        let pixelScale: Double

        var estimatedCost: Double { duration * pixelScale }
    }

    enum CheckerError: LocalizedError {
        case toolMissing

        var errorDescription: String? {
            LanguageManager.shared.localized("FFmpeg is required for checking.")
        }
    }

    // Two at a time saturates the machine: a single full decode already spreads
    // across ~4.6 cores of a 10-core M1 Max, so more workers just contend.
    static let concurrency = 2

    nonisolated static let videoExtensions: Set<String> = ["mp4", "mov", "m4v"]

    private var ffmpegPath: String? { FFmpegSetupManager.resolvedFFmpegExecutable }
    private var ffprobePath: String? { FFmpegSetupManager.resolvedFFprobeExecutable }

    // MARK: - Discovery

    /// Expands dropped/selected items into the video files underneath them.
    nonisolated static func collectVideos(from urls: [URL], recursive: Bool) -> [URL] {
        var found: [URL] = []
        var seen = Set<URL>()

        func append(_ url: URL) {
            let standardized = url.standardizedFileURL
            guard videoExtensions.contains(standardized.pathExtension.lowercased()) else { return }
            guard seen.insert(standardized).inserted else { return }
            found.append(standardized)
        }

        for url in urls {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }

            if isDirectory.boolValue {
                let options: FileManager.DirectoryEnumerationOptions = recursive
                    ? [.skipsHiddenFiles, .skipsPackageDescendants]
                    : [.skipsHiddenFiles, .skipsPackageDescendants, .skipsSubdirectoryDescendants]
                guard let enumerator = FileManager.default.enumerator(
                    at: url,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: options
                ) else { continue }

                for case let child as URL in enumerator {
                    let isRegular = (try? child.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile ?? false
                    if isRegular { append(child) }
                }
            } else {
                append(url)
            }
        }

        return found.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    /// Reads duration and frame size so the UI can estimate how long a run takes.
    /// A file damaged badly enough to defeat ffprobe still becomes a target — it
    /// simply carries no estimate.
    func inspect(urls: [URL]) async -> [Target] {
        guard let ffprobePath else {
            return urls.map { Target(url: $0, duration: 0, pixelScale: 1) }
        }

        var targets: [Target] = []
        for url in urls {
            if Task.isCancelled { break }
            let info = await Self.probe(ffprobePath: ffprobePath, url: url)
            let scale = info.width > 0 && info.height > 0
                ? Double(info.width * info.height) / (1920.0 * 1080.0)
                : 1.0
            targets.append(Target(url: url, duration: info.duration, pixelScale: scale))
        }
        return targets
    }

    private static func probe(ffprobePath: String, url: URL) async -> (duration: Double, width: Int, height: Int) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffprobePath)
        process.arguments = [
            "-v", "error",
            "-select_streams", "v:0",
            "-show_entries", "stream=width,height",
            "-show_entries", "format=duration",
            "-of", "json",
            url.path
        ]
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        let data: Data = await withCheckedContinuation { continuation in
            let pipe = Pipe()
            process.standardOutput = pipe

            var collected = Data()
            let queue = DispatchQueue(label: "ffprobe.inspect")
            var resumed = false

            pipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if !chunk.isEmpty { queue.async { collected.append(chunk) } }
            }

            process.terminationHandler = { _ in
                pipe.fileHandleForReading.readabilityHandler = nil
                try? pipe.fileHandleForReading.close()
                queue.sync {
                    guard !resumed else { return }
                    resumed = true
                    continuation.resume(returning: collected)
                }
            }

            do {
                try process.run()
            } catch {
                queue.sync {
                    guard !resumed else { return }
                    resumed = true
                    continuation.resume(returning: Data())
                }
            }
        }

        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (0, 0, 0)
        }
        let format = root["format"] as? [String: Any]
        let duration = Double((format?["duration"] as? String) ?? "") ?? 0
        let stream = (root["streams"] as? [[String: Any]])?.first
        let width = stream?["width"] as? Int ?? 0
        let height = stream?["height"] as? Int ?? 0
        return (duration, width, height)
    }

    /// Predicted wall-clock time for a run, accounting for resolution and the
    /// two workers that share the machine.
    static func estimate(targets: [Target], level: CheckLevel) -> TimeInterval {
        let cost = targets.reduce(0.0) { $0 + $1.estimatedCost }
        // A lone file gets no benefit from the second worker.
        let workers = max(min(concurrency, targets.count), 1)
        return cost * level.realtimeFactor / Double(workers)
    }

    // MARK: - Checking

    /// Runs one file. `onProgress` reports seconds of footage decoded so far.
    func check(
        target: Target,
        level: CheckLevel,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> CheckResult {
        guard let ffmpegPath else { throw CheckerError.toolMissing }

        let startedAt = Date()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        process.arguments = level.arguments(for: target.url.path)
        process.standardInput = FileHandle.nullDevice

        // stdout carries `-progress` key/value lines, stderr carries only the
        // diagnostics we judge on. Keeping them on separate pipes means a noisy
        // progress stream can never be mistaken for damage.
        let diagnostics: String = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe

                var errorText = ""
                var progressBuffer = ""
                let queue = DispatchQueue(label: "ffmpeg.integrity")
                var resumed = false

                outPipe.fileHandleForReading.readabilityHandler = { handle in
                    let chunk = handle.availableData
                    guard !chunk.isEmpty, let text = String(data: chunk, encoding: .utf8) else { return }
                    queue.async {
                        progressBuffer += text
                        // `out_time_ms` is microseconds despite the name.
                        while let newline = progressBuffer.firstIndex(of: "\n") {
                            let line = String(progressBuffer[progressBuffer.startIndex..<newline])
                            progressBuffer = String(progressBuffer[progressBuffer.index(after: newline)...])
                            guard line.hasPrefix("out_time_ms="),
                                  let micros = Double(line.dropFirst("out_time_ms=".count)) else { continue }
                            onProgress(max(micros / 1_000_000, 0))
                        }
                    }
                }

                errPipe.fileHandleForReading.readabilityHandler = { handle in
                    let chunk = handle.availableData
                    guard !chunk.isEmpty, let text = String(data: chunk, encoding: .utf8) else { return }
                    queue.async {
                        // Damage tends to repeat every frame; keep the run bounded.
                        if errorText.count < 64_000 { errorText += text }
                    }
                }

                process.terminationHandler = { _ in
                    outPipe.fileHandleForReading.readabilityHandler = nil
                    errPipe.fileHandleForReading.readabilityHandler = nil
                    try? outPipe.fileHandleForReading.close()
                    try? errPipe.fileHandleForReading.close()
                    queue.sync {
                        guard !resumed else { return }
                        resumed = true
                        continuation.resume(returning: errorText)
                    }
                }

                do {
                    try process.run()
                } catch {
                    queue.sync {
                        guard !resumed else { return }
                        resumed = true
                        continuation.resume(returning: "")
                    }
                }
            }
        } onCancel: {
            process.terminate()
        }

        try Task.checkCancellation()

        let findings = Self.meaningfulDiagnostics(diagnostics)
        return CheckResult(
            url: target.url,
            status: Self.classify(findings),
            log: findings,
            duration: target.duration,
            elapsed: Date().timeIntervalSince(startedAt)
        )
    }

    /// Drops complaints that come from the discard muxer rather than the input.
    /// A healthy file routinely makes `-f null` grumble about timestamps, and
    /// reporting that as damage would flag good footage.
    nonisolated static func meaningfulDiagnostics(_ raw: String) -> String {
        let benign = [
            "non monotonically increasing dts to muxer",
            "encoder did not produce proper pts",
            "could not update timestamps for skipped samples"
        ]
        let kept = raw
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
            .filter { line in
                let lower = line.lowercased()
                // Everything the null muxer says is about our own throwaway output.
                if lower.contains("[null @ ") { return false }
                return !benign.contains(where: lower.contains)
            }
        return kept.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// ffmpeg exits 0 even on badly damaged input unless `-xerror` is set, and we
    /// deliberately let it run to the end so every damaged region is reported.
    /// That makes stderr — not the exit status — the only usable signal.
    nonisolated static func classify(_ diagnostics: String) -> CheckStatus {
        let text = diagnostics.lowercased()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .ok }

        let fatal = [
            "invalid nal",
            "error splitting",
            "partial file",
            "invalid data found",
            "moov atom not found",
            "could not find codec parameters",
            "error while decoding",
            "decoding error",
            "no such file",
            "invalid argument",
            "packet corrupt"
        ]
        if fatal.contains(where: text.contains) { return .broken }

        // `corrupt decoded frame` is logged at warning level, which is exactly why
        // a `-v error` check reports a damaged file as clean.
        let suspect = ["corrupt", "missing picture", "concealing", "truncated"]
        if suspect.contains(where: text.contains) { return .warning }

        return .warning
    }
}

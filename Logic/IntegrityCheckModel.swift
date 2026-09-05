import Foundation
import SwiftUI
import Combine

/// Drives the check screen: turns dropped folders into a work list, runs the
/// checker over it, and keeps the aggregate progress the UI shows.
@MainActor
final class IntegrityCheckModel: ObservableObject {
    @Published var level: CheckLevel = .full
    @Published var includeSubfolders = true

    @Published private(set) var targets: [VideoIntegrityChecker.Target] = []
    @Published private(set) var results: [CheckResult] = []
    @Published private(set) var sourceLabel: String = ""
    @Published private(set) var isScanning = false
    @Published private(set) var isChecking = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var remainingTime: TimeInterval = -1
    @Published private(set) var currentFileNames: [String] = []
    @Published private(set) var errorMessage: String?
    /// Whether the current selection contains at least one folder. Only then does
    /// the subfolder option mean anything.
    @Published private(set) var hasFolderInput = false

    private var droppedURLs: [URL] = []
    private var scanTask: Task<Void, Never>?
    private var checkTask: Task<Void, Never>?

    // Footage decoded per target, weighted by pixel count so a 4K file
    // contributes proportionally more to the bar than a 1080p one.
    private var processedCost: [UUID: Double] = [:]

    var hasTargets: Bool { !targets.isEmpty }

    /// Something was selected, the scan finished, and it held no video files.
    var foundNothing: Bool { !sourceLabel.isEmpty && targets.isEmpty && !isScanning }

    var totalDuration: Double { targets.reduce(0) { $0 + $1.duration } }

    var estimatedDuration: TimeInterval {
        VideoIntegrityChecker.estimate(targets: targets, level: level)
    }

    var okCount: Int { results.filter { $0.status == .ok }.count }
    var warningCount: Int { results.filter { $0.status == .warning }.count }
    var brokenCount: Int { results.filter { $0.status == .broken }.count }

    /// Damaged and suspect files together — what "reveal in Finder" acts on.
    var problemURLs: [URL] {
        results.filter { $0.status.isProblem }.map { $0.url }
    }

    // MARK: - Input

    func load(urls: [URL]) {
        droppedURLs = urls
        hasFolderInput = urls.contains { url in
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            return exists && isDirectory.boolValue
        }
        sourceLabel = Self.describe(urls)
        rescan()
    }

    func rescan() {
        guard !droppedURLs.isEmpty else { return }
        scanTask?.cancel()
        results = []
        processedCost = [:]
        progress = 0
        remainingTime = -1
        errorMessage = nil

        let urls = droppedURLs
        let recursive = includeSubfolders
        isScanning = true

        scanTask = Task {
            let checker = VideoIntegrityChecker()
            let files = VideoIntegrityChecker.collectVideos(from: urls, recursive: recursive)
            let inspected = await checker.inspect(urls: files)
            guard !Task.isCancelled else { return }
            self.targets = inspected
            self.isScanning = false
        }
    }

    func clear() {
        scanTask?.cancel()
        checkTask?.cancel()
        droppedURLs = []
        hasFolderInput = false
        targets = []
        results = []
        processedCost = [:]
        sourceLabel = ""
        progress = 0
        remainingTime = -1
        currentFileNames = []
        errorMessage = nil
        isScanning = false
        isChecking = false
    }

    // MARK: - Running

    func start() {
        guard !targets.isEmpty, !isChecking else { return }

        results = []
        processedCost = [:]
        progress = 0
        remainingTime = -1
        errorMessage = nil
        isChecking = true

        let queue = targets
        let level = self.level
        let startedAt = Date()
        let totalCost = queue.reduce(0.0) { $0 + $1.estimatedCost }

        checkTask = Task {
            let checker = VideoIntegrityChecker()

            await withTaskGroup(of: CheckResult?.self) { group in
                var next = 0

                func addWorker() {
                    guard next < queue.count else { return }
                    let target = queue[next]
                    next += 1
                    group.addTask {
                        await MainActor.run { self.beginFile(target) }
                        defer { Task { @MainActor in self.endFile(target) } }
                        do {
                            return try await checker.check(target: target, level: level) { seconds in
                                Task { @MainActor in
                                    self.updateProgress(
                                        target: target,
                                        seconds: seconds,
                                        totalCost: totalCost,
                                        startedAt: startedAt
                                    )
                                }
                            }
                        } catch is CancellationError {
                            return nil
                        } catch {
                            await MainActor.run { self.errorMessage = error.localizedDescription }
                            return nil
                        }
                    }
                }

                for _ in 0..<min(VideoIntegrityChecker.concurrency, queue.count) { addWorker() }

                while let finished = await group.next() {
                    if let finished {
                        self.results.append(finished)
                        self.completeFile(finished, totalCost: totalCost, startedAt: startedAt)
                    }
                    if Task.isCancelled { break }
                    addWorker()
                }
            }

            self.results.sort { $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending }
            self.isChecking = false
            self.currentFileNames = []
            if !Task.isCancelled { self.progress = 1.0 }
            self.remainingTime = -1
        }
    }

    func cancel() {
        checkTask?.cancel()
    }

    // MARK: - Progress bookkeeping

    private func beginFile(_ target: VideoIntegrityChecker.Target) {
        currentFileNames.append(target.url.lastPathComponent)
    }

    private func endFile(_ target: VideoIntegrityChecker.Target) {
        if let index = currentFileNames.firstIndex(of: target.url.lastPathComponent) {
            currentFileNames.remove(at: index)
        }
    }

    private func updateProgress(
        target: VideoIntegrityChecker.Target,
        seconds: Double,
        totalCost: Double,
        startedAt: Date
    ) {
        let capped = target.duration > 0 ? min(seconds, target.duration) : seconds
        processedCost[target.id] = capped * target.pixelScale
        recomputeProgress(totalCost: totalCost, startedAt: startedAt)
    }

    private func completeFile(_ result: CheckResult, totalCost: Double, startedAt: Date) {
        if let target = targets.first(where: { $0.url == result.url }) {
            processedCost[target.id] = target.estimatedCost
        }
        recomputeProgress(totalCost: totalCost, startedAt: startedAt)
    }

    private func recomputeProgress(totalCost: Double, startedAt: Date) {
        guard totalCost > 0 else { return }
        let done = processedCost.values.reduce(0, +)
        progress = min(done / totalCost, 1.0)

        // Rate-based estimate, using the same "wait for a few seconds of real
        // data" approach as the merge progress in FFmpegRunner.
        let elapsed = Date().timeIntervalSince(startedAt)
        guard elapsed > 5, done > 0 else { return }
        let rate = done / elapsed
        guard rate > 0.0001 else { return }
        remainingTime = max((totalCost - done) / rate, 0)
    }

    // MARK: - Helpers

    private static func describe(_ urls: [URL]) -> String {
        if urls.count == 1 { return urls[0].lastPathComponent }
        return LanguageManager.shared.localizedDynamic("{0} items selected", args: ["\(urls.count)"])
    }

    static func formatDuration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--:--" }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute, .second] : [.minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: seconds) ?? "--:--"
    }
}

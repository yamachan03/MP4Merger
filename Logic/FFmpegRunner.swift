import Foundation
import AVFoundation

struct FFmpegRunner {
    enum FFmpegError: LocalizedError {
        case ffmpegNotFound
        case commandFailed(String)
        case outputCreationFailed
        
        var errorDescription: String? {
            switch self {
            case .ffmpegNotFound:
                return "FFmpeg binary not found at /opt/homebrew/bin/ffmpeg."
            case .commandFailed(let output):
                return "FFmpeg command failed: \(output)"
            case .outputCreationFailed:
                return "Failed to create output file."
            }
        }
        
        var failureReason: String? {
             switch self {
             case .commandFailed(let output):
                 return output
             default:
                 return nil
             }
        }
    }
    
    // usage: private var ffmpegPath: String { ... }
    private var ffmpegPath: String {
        // 1. Check for bundled ffmpeg in Resources
        if let bundledPath = Bundle.main.path(forResource: "ffmpeg", ofType: nil) {
            return bundledPath
        }
        // 2. Fallback to Homebrew path (for development)
        return "/opt/homebrew/bin/ffmpeg"
    }
    
    // Apply Finder tags with retries and dual strategy (URL resource value + xattr fallback)
    private func applyFinderTags(_ tags: [String], to url: URL, retries: Int = 5) async {
        guard !tags.isEmpty else { return }
        let tagArray = tags

        // Normalize tags: allow both plain names and "Name\n<colorIndex>"; here we keep as-is
        let normalizedTags = tagArray

        // Helper: try URLResourceValue API
        func setViaResourceValues() throws {
            // Try NSURL API first (works on older macOS too)
            let nsurl = url as NSURL
            try nsurl.setResourceValue(normalizedTags, forKey: .tagNamesKey)

            // Try URLResourceValues API if available at runtime; otherwise skip
            // (Removed explicit URLResourceValues block due to availability issues on some SDKs; logic covered by NSURL below)
        }

        // Helper: write com.apple.metadata:_kMDItemUserTags via xattr as binary plist
        func setViaXattr() throws {
            let plistData = try PropertyListSerialization.data(fromPropertyList: tagArray, format: .binary, options: 0)
            let hex = plistData.map { String(format: "%02x", $0) }.joined()
            let xattrProcess = Process()
            xattrProcess.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
            xattrProcess.arguments = ["-w", "-x", "com.apple.metadata:_kMDItemUserTags", hex, url.path]
            let pipe = Pipe()
            xattrProcess.standardOutput = pipe
            xattrProcess.standardError = pipe
            try xattrProcess.run()
            xattrProcess.waitUntilExit()
            if xattrProcess.terminationStatus != 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let msg = String(data: data, encoding: .utf8) ?? "unknown xattr error"
                throw FFmpegError.commandFailed("xattr writer failed: \(msg)")
            }
        }

        // Helper: verify tag presence by reading xattrs
        func verify() -> Bool {
            let verify = Process()
            verify.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
            verify.arguments = ["-l", url.path]
            let pipe = Pipe()
            verify.standardOutput = pipe
            verify.standardError = pipe
            do {
                try verify.run()
                verify.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let out = String(data: data, encoding: .utf8) {
                    return out.contains("com.apple.metadata:_kMDItemUserTags:")
                }
            } catch {
                return false
            }
            return false
        }

        // Helper: verify via mdls (Spotlight metadata)
        func verifyViaMDLS() -> Bool {
            let mdls = Process()
            mdls.executableURL = URL(fileURLWithPath: "/usr/bin/mdls")
            mdls.arguments = ["-name", "kMDItemUserTags", url.path]
            let pipe = Pipe()
            mdls.standardOutput = pipe
            mdls.standardError = pipe
            do {
                try mdls.run()
                mdls.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let out = String(data: data, encoding: .utf8) {
                    // kMDItemUserTags = (
                    //   "Tag1",
                    //   "Tag2\n0"
                    // )
                    return out.contains("kMDItemUserTags = (")
                }
            } catch {
                return false
            }
            return false
        }

        // Retry loop: small backoff to avoid races with file closing/indexing
        var attempt = 0
        while attempt < retries {
            do {
                // First try URL resource values
                try setViaResourceValues()
                if verify() || verifyViaMDLS() { return }
            } catch {
                // fall through to xattr
            }

            do {
                try setViaXattr()
                if verify() || verifyViaMDLS() { return }
            } catch {
                // continue to retry
            }

            attempt += 1
            // Backoff 150ms * attempt
            let sleepNanos = 150_000_000 * UInt64(attempt)
            try? await Task.sleep(nanoseconds: sleepNanos)
        }

        print("Failed to apply Finder tags after \(retries) attempts to \(url.path)")
    }
    
    // Helper: Detect video codec
    private func getVideoCodec(for url: URL) async -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        process.arguments = [
            "-v", "error",
            "-select_streams", "v:0",
            "-show_entries", "stream=codec_name",
            "-of", "default=noprint_wrappers=1:nokey=1",
            url.path
        ]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    func merge(files: [URL], fastMerge: Bool, normalizeAudio: Bool, fixJitter: Bool, useHEVC: Bool, destinationURL: URL, targetHeight: Int?, metadata: [String: String]? = nil, finderTags: [String]? = nil, onProgress: @escaping (Double, TimeInterval) -> Void) async throws -> URL {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory
        
        // Output URL is now passed directly (from Save Panel)
        let outputURL = destinationURL
        
        // Check FFmpeg
        guard FileManager.default.fileExists(atPath: ffmpegPath) else {
            throw FFmpegError.ffmpegNotFound
        }

        // Calculate durations
        var fileDurations: [Double] = []
        var totalDuration: Double = 0
        for file in files {
            let asset = AVURLAsset(url: file)
            let duration = (try? await asset.load(.duration))?.seconds ?? 0
            fileDurations.append(duration)
            totalDuration += duration
        }
        
        // Determine Mode
        let filtersActive = normalizeAudio || fixJitter || targetHeight != nil || useHEVC
        let effectiveFastMerge = fastMerge || !filtersActive

        // Shared progress state
        let startTime = Date()
        
        // --- TIER 1: FAST MERGE (Direct Copy) ---
        var success = false
        
        if effectiveFastMerge {
            // ... TIER 1 Logic ...
            let concatListURL = tempDir.appendingPathComponent("concat_list_\(UUID()).txt")
            var concatContent = ""
            for file in files {
                let escapedPath = file.path.replacingOccurrences(of: "'", with: "'\\''")
                concatContent += "file '\(escapedPath)'\n"
            }
            
            do {
                try concatContent.write(to: concatListURL, atomically: true, encoding: .utf8)
                
                var args = [
                    "-f", "concat",
                    "-safe", "0",
                    "-i", concatListURL.path
                ]
                
                if let first = files.first {
                    args.append(contentsOf: ["-i", first.path, "-map_metadata", "1", "-map", "0"])
                }
                
                args.append(contentsOf: ["-c", "copy", "-movflags", "use_metadata_tags", "-y", outputURL.path])
                
                print("🚀 Attempting Tier 1 (Direct Copy)...")
                try await runFFmpeg(arguments: args, totalDuration: totalDuration, offsetDuration: 0, startTime: startTime, onProgress: onProgress)
                try? fileManager.removeItem(at: concatListURL)

                // Verify
                try await verifyOutput(outputURL, expectedDuration: totalDuration)
                success = true
                
            } catch {
                print("⚠️ Tier 1 Failed: \(error).")
                try? fileManager.removeItem(at: concatListURL)
                try? fileManager.removeItem(at: outputURL)
                success = false
            }
        }
        
        // --- TIER 2: REWRAP MERGE (Stream Copy via TS) ---
        // If TIER 1 failed but we have NO filters, we can try rewrapping.
        // This fixes container timestamp issues (6h bug) without encoding (60min wait).
        if !success && effectiveFastMerge {
            print("🔄 Attempting Tier 2 (Rewrap via TS)...")
            
            // 1. Check Codec
            let firstCodec = await getVideoCodec(for: files.first!)
            let bsf: String?
            if firstCodec == "h264" { bsf = "h264_mp4toannexb" }
            else if firstCodec == "hevc" { bsf = "hevc_mp4toannexb" }
            else { bsf = nil } // Unknown, might fail or not need it
            
            var tsFiles: [URL] = []
            var accumulated: Double = 0
            var rewrapFailed = false
            
            do {
                // Convert each to TS
                for (idx, file) in files.enumerated() {
                    let tsURL = tempDir.appendingPathComponent("part_\(UUID()).ts")
                    tsFiles.append(tsURL)
                    
                    var args = ["-i", file.path, "-c", "copy", "-bsf:v", bsf ?? "null", "-f", "mpegts", "-y", tsURL.path]
                    // remove null bsf if nil
                    if bsf == nil { args.remove(at: 4); args.remove(at: 4) }
                    
                    try await runFFmpeg(arguments: args, totalDuration: totalDuration, offsetDuration: accumulated, startTime: startTime, onProgress: onProgress)
                    accumulated += fileDurations[idx]
                }
                
                // Concat TS
                let concatStr = "concat:" + tsFiles.map { $0.path }.joined(separator: "|")
                let args = [
                    "-i", concatStr,
                    "-c", "copy",
                    "-movflags", "+faststart",
                    "-y", outputURL.path
                ]
                
                try await runFFmpeg(arguments: args, totalDuration: 0, offsetDuration: 0, startTime: startTime, onProgress: {_,_ in })
                
                // Cleanup TS
                for f in tsFiles { try? fileManager.removeItem(at: f) }
                
                // Verify
                try await verifyOutput(outputURL, expectedDuration: totalDuration)
                success = true
                print("✅ Tier 2 Success!")
                
            } catch {
                print("⚠️ Tier 2 Failed: \(error).")
                for f in tsFiles { try? fileManager.removeItem(at: f) }
                try? fileManager.removeItem(at: outputURL)
                success = false
            }
        }
        
        if success {
            try? fileManager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: outputURL.path)
            if let finderTags = finderTags, !finderTags.isEmpty {
                 try? await Task.sleep(nanoseconds: 200_000_000)
                 await self.applyFinderTags(finderTags, to: outputURL)
            }
            return outputURL
        }

        // ... (Existing Robust Path Logic) ...
        
        // RESET TIMER for Tier 3
        let tier3StartTime = Date()
        
        var args: [String] = []
        var filterComplex = ""
        
        // 1. Inputs
        for file in files {
            // Enable Hardware Decoding
            args.append(contentsOf: ["-hwaccel", "videotoolbox", "-i", file.path])
        }
        
        // 2. Filter Construction
        for i in 0..<files.count {
            // Video
            var vOps = "fps=30,format=yuv420p"
            if fixJitter { vOps += ",yadif=0:-1:0" }
            if let height = targetHeight { vOps += ",scale=-2:\(height):flags=lanczos" }
            filterComplex += "[\(i):v]\(vOps)[v\(i)];"
            
            // Audio
            var aOps = "aresample=48000"
            if normalizeAudio { aOps += ",loudnorm=I=-16:TP=-1.5:LRA=11" }
            filterComplex += "[\(i):a]\(aOps)[a\(i)];"
        }
        
        // Concat Command
        for i in 0..<files.count {
            filterComplex += "[v\(i)][a\(i)]"
        }
        filterComplex += "concat=n=\(files.count):v=1:a=1[outv][outa]"
        
        args.append(contentsOf: ["-filter_complex", filterComplex])
        args.append(contentsOf: ["-map", "[outv]", "-map", "[outa]"])
        
        // 3. Encoder Settings
        if useHEVC {
             args.append(contentsOf: [
                "-c:v", "hevc_videotoolbox", "-tag:v", "hvc1", "-allow_sw", "1",
                "-b:v", "8M", "-maxrate", "12M", "-bufsize", "16M", "-profile:v", "main"
             ])
        } else {
             args.append(contentsOf: [
                "-c:v", "h264_videotoolbox", "-allow_sw", "1",
                "-b:v", "12M", "-maxrate", "16M", "-bufsize", "20M", "-profile:v", "high"
             ])
        }
        args.append(contentsOf: ["-c:a", "aac", "-b:a", "192k"])
        
        // Optimize
        args.append(contentsOf: ["-movflags", "+faststart", "-y", outputURL.path])
        
        // Run (Use tier3StartTime)
        try await runFFmpeg(
            arguments: args,
            totalDuration: totalDuration,
            offsetDuration: 0,
            startTime: tier3StartTime,
            onProgress: { prog, remaining in
                // Proxy the progress, but maybe we want to inform UI we are in "Retry" mode?
                // The UI just takes double/TimeInterval.
                onProgress(prog, remaining)
            }
        )
        
        // Verify Robust Path too
        try await verifyOutput(outputURL, expectedDuration: totalDuration, tolerance: 10.0) // 10s tolerance for recheck
        
        return outputURL
    }

    // Helper: Run generic ffmpeg command and parse progress
    private func runFFmpeg(arguments: [String], totalDuration: Double, offsetDuration: Double, startTime: Date, onProgress: @escaping (Double, TimeInterval) -> Void) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        
        return try await withTaskCancellationHandler {
            return try await withCheckedThrowingContinuation { continuation in
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                
                var collectedData = Data()
                var outputBuffer = ""
                // Progress smoothing state
                var lastEstimates: [TimeInterval] = []
                
                let queue = DispatchQueue(label: "ffmpeg.output.collection")
                
                pipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    if !data.isEmpty {
                        queue.async {
                            collectedData.append(data)
                            if let str = String(data: data, encoding: .utf8) {
                                outputBuffer += str
                                if outputBuffer.count > 4096 { outputBuffer = String(outputBuffer.suffix(4096)) }
                                
                                // Call parser
                                parseProgress(
                                    lastOutput: outputBuffer,
                                    globalTotalDuration: totalDuration,
                                    currentOffset: offsetDuration,
                                    startTime: startTime,
                                    lastEstimates: &lastEstimates,
                                    onProgress: onProgress
                                )
                            }
                        }
                    }
                }
                
                process.terminationHandler = { proc in
                    pipe.fileHandleForReading.readabilityHandler = nil
                    try? pipe.fileHandleForReading.close()
                    
                    queue.sync {
                        if proc.terminationStatus == 0 {
                            continuation.resume()
                        } else {
                            let output = String(data: collectedData, encoding: .utf8) ?? "Unknown error"
                            continuation.resume(throwing: FFmpegError.commandFailed(output))
                        }
                    }
                }
                
                do {
                    print("Running: \(arguments.joined(separator: " "))")
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            process.terminate()
        }
    }
    
    // Quick Verification Check
    private func verifyOutput(_ url: URL, expectedDuration: Double? = nil, tolerance: Double = 5.0) async throws {
        // 1. Check for integrity errors
        let checkProcess = Process()
        checkProcess.executableURL = URL(fileURLWithPath: ffmpegPath)
        checkProcess.arguments = [
            "-v", "error",
            "-sseof", "-1", // Check last second only for speed, or remove for specific check
             // Actually -sseof -1 with -f null - reads last second. But to check validation we might want full read?
             // Fast check: just detect errors.
            "-i", url.path,
            "-f", "null",
            "-"
        ]
        
        let pipe = Pipe()
        checkProcess.standardError = pipe
        checkProcess.standardOutput = pipe
        
        try checkProcess.run()
        checkProcess.waitUntilExit()
        
        // Read stderr for errors
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let msg = String(data: data, encoding: .utf8) ?? ""
        
        if checkProcess.terminationStatus != 0 || (!msg.isEmpty && msg.lowercased().contains("error")) {
             // Ignoring generic warnings, looking for hard errors
             if msg.contains("Error") || msg.contains("Invalid") {
                 throw FFmpegError.commandFailed("Verification Integrity Error: \(msg)")
             }
        }
        
        // 2. Duration Check (Critical for the 6-hour bug)
        if let expected = expectedDuration {
            // Get actual duration using ffprobe-like command (ffmpeg -i)
            let durationProcess = Process()
            durationProcess.executableURL = URL(fileURLWithPath: ffmpegPath)
            durationProcess.arguments = ["-i", url.path]
            let dPipe = Pipe()
            durationProcess.standardError = dPipe // ffmpeg prints info to stderr
            
            try durationProcess.run()
            durationProcess.waitUntilExit()
            
            let dData = dPipe.fileHandleForReading.readDataToEndOfFile()
            let dOutput = String(data: dData, encoding: .utf8) ?? ""
            
            // Parse "Duration: HH:MM:SS.ss"
            let pattern = "Duration: (\\d{2}):(\\d{2}):(\\d{2}\\.\\d{2})"
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: dOutput, options: [], range: NSRange(location: 0, length: dOutput.utf16.count)) {
                
                if let swiftRange = Range(match.range(at: 0), in: dOutput) {
                     let durationStr = String(dOutput[swiftRange]).replacingOccurrences(of: "Duration: ", with: "")
                     let components = durationStr.split(separator: ":")
                     if components.count == 3,
                        let h = Double(components[0]),
                        let m = Double(components[1]),
                        let s = Double(components[2]) {
                         let actualSeconds = h * 3600 + m * 60 + s
                         
                         let diff = abs(actualSeconds - expected)
                         if diff > tolerance {
                             throw FFmpegError.commandFailed("Duration Mismatch: Expected \(expected)s, Got \(actualSeconds)s. (Diff: \(diff)s)")
                         }
                     }
                }
            } else {
                // If we can't parse duration, that's suspicious too, but maybe just let it pass or warn
                print("⚠️ Could not parse duration from output.")
            }
        }
    }
    
    // Updated Parser
    // Updated Parser with Moving Average Smoothing
    private var lastThreeEstimates: [TimeInterval] = []
    
    // We modify the signature to be internal or private but we need state (lastThreeEstimates) which is problematic in a struct.
    // However, since FFmpegRunner is initialized per task in ContentView, we can add a property if we change it to a class or use a closure capture.
    // Current design is struct. We can't mutate 'self' in the closure easily.
    // FIX: We will handle smoothing in the closure's captured variables inside runFFmpeg or make the parser static and pass state?
    // Easiest is to move valid logic into runFFmpeg's closure local state.
    
    // Actually, let's keep the parseProgress straightforward but smarter about "start time".
    // Better idea: calculate speed (seconds processed per second real time) and average THAT.
    
    private func parseProgress(lastOutput: String, globalTotalDuration: Double, currentOffset: Double, startTime: Date, lastEstimates: inout [TimeInterval], onProgress: @escaping (Double, TimeInterval) -> Void) {
        guard globalTotalDuration > 0 else { return }
        
        let pattern = "time=(\\d{2}):(\\d{2}):(\\d{2}\\.\\d{2})"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return }
        
        let range = NSRange(location: 0, length: lastOutput.utf16.count)
        if let match = regex.firstMatch(in: lastOutput, options: [], range: range) {
            if let swiftRange = Range(match.range(at: 0), in: lastOutput) {
                let timeString = String(lastOutput[swiftRange]).replacingOccurrences(of: "time=", with: "")
                let components = timeString.split(separator: ":")
                if components.count == 3,
                   let hours = Double(components[0]),
                   let minutes = Double(components[1]),
                   let seconds = Double(components[2]) {
                    
                    let currentSeconds = hours * 3600 + minutes * 60 + seconds
                    let actualTotalProcessed = currentOffset + currentSeconds
                    let percentage = max(actualTotalProcessed / globalTotalDuration, 0.0) // Allow > 1.0 internally
                    
                    let elapsedTime = Date().timeIntervalSince(startTime)
                    var remaining: TimeInterval = -1
                    
                    // Improved Estimation Logic:
                    if percentage > 0.05 || elapsedTime > 10 {
                        let rate = actualTotalProcessed / elapsedTime
                        if rate > 0.0001 {
                            // If we overrun total duration, current > total.
                            let remainingWork = globalTotalDuration - actualTotalProcessed
                            if remainingWork < 0 {
                                // Overrun: The duration was underestimated.
                                // We cannot predict remaining time anymore.
                                remaining = -2
                            } else {
                                let instantRemaining = remainingWork / rate
                                
                                // Smooth with history
                                lastEstimates.append(instantRemaining)
                                if lastEstimates.count > 30 { lastEstimates.removeFirst() }
                                
                                let smoothedRemaining = lastEstimates.reduce(0, +) / Double(lastEstimates.count)
                                remaining = smoothedRemaining
                            }
                        }
                    } else {
                         remaining = -1
                    }
                    
                    // Cap percentage at 1.0 for the UI progress bar itself
                    let uiPercentage = min(percentage, 1.0)
                    
                    DispatchQueue.main.async {
                        onProgress(uiPercentage, remaining)
                    }
                }
            }
        }
    }
}

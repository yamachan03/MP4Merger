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
        // 1. Bundled in app resources (testing / custom distribution)
        if let p = Bundle.main.path(forResource: "ffmpeg", ofType: nil) { return p }
        // 2. Downloaded via in-app setup wizard → ~/Library/Application Support/MP4Merger/ffmpeg
        if FileManager.default.fileExists(atPath: FFmpegSetupManager.ffmpegPath) { return FFmpegSetupManager.ffmpegPath }
        // 3. Homebrew (Apple Silicon)
        if FileManager.default.fileExists(atPath: "/opt/homebrew/bin/ffmpeg") { return "/opt/homebrew/bin/ffmpeg" }
        // 4. Homebrew (Intel Mac)
        return "/usr/local/bin/ffmpeg"
    }

    private var ffprobePath: String {
        // 1. Bundled
        if let p = Bundle.main.path(forResource: "ffprobe", ofType: nil) { return p }
        // 2. Downloaded via setup wizard
        if FileManager.default.fileExists(atPath: FFmpegSetupManager.ffprobePath) { return FFmpegSetupManager.ffprobePath }
        // 3. Homebrew (Apple Silicon)
        if FileManager.default.fileExists(atPath: "/opt/homebrew/bin/ffprobe") { return "/opt/homebrew/bin/ffprobe" }
        // 4. Homebrew (Intel Mac)
        return "/usr/local/bin/ffprobe"
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
        process.executableURL = URL(fileURLWithPath: ffprobePath)
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

    func validateFiles(files: [URL], checkFormat: Bool, deepCheck: Bool) async throws -> Bool {
        guard files.count > 0 else { return false }
        
        // Check FFprobe
        guard FileManager.default.fileExists(atPath: ffprobePath) else {
            throw FFmpegError.commandFailed("ffprobe binary not found. Validation requires ffprobe.")
        }
        
        var needsReencode = false
        
        // 1. Fast Check: Format consistency (only if multiple files)
        if checkFormat && files.count > 1 {
            var firstInfo: String?
            for file in files {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: ffprobePath)
                process.arguments = [
                    "-v", "error",
                    "-show_entries", "stream=codec_name,profile,width,height,r_frame_rate,time_base,sample_rate,channels",
                    "-of", "csv=p=0",
                    file.path
                ]
                let pipe = Pipe()
                process.standardOutput = pipe
                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let info = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    if process.terminationStatus != 0 {
                        throw FFmpegError.commandFailed("ffprobe exited with code \(process.terminationStatus) at \(ffprobePath). File: \(file.lastPathComponent)")
                    }
                    if info == nil || info!.isEmpty {
                        throw FFmpegError.commandFailed("ffprobe returned empty output at \(ffprobePath). File: \(file.lastPathComponent)")
                    }
                    
                    if let first = firstInfo {
                        if first != info {
                            print("Format mismatch: \(first) vs \(info ?? "nil")")
                            needsReencode = true
                            break
                        }
                    } else {
                        firstInfo = info
                    }
                } catch let err as FFmpegError {
                    throw err
                } catch {
                     throw FFmpegError.commandFailed("ffprobe format check failed for \(file.lastPathComponent): \(error.localizedDescription)")
                }
            }
        }
        
        // 2. Deep Check: File integrity
        if deepCheck {
            guard FileManager.default.fileExists(atPath: ffmpegPath) else {
                throw FFmpegError.ffmpegNotFound
            }
            
            for file in files {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: ffmpegPath)
                process.arguments = [
                    "-v", "error",
                    "-i", file.path,
                    "-f", "null",
                    "-c", "copy",
                    "-"
                ]
                let pipe = Pipe()
                process.standardError = pipe
                
                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let msg = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    
                    // ffmpeg will print errors to stderr
                    if process.terminationStatus != 0 || msg.lowercased().contains("error") || msg.lowercased().contains("invalid") {
                         throw FFmpegError.commandFailed(LanguageManager.shared.localizedDynamic("File integrity error detected in {0}:\n{1}", args: [file.lastPathComponent, msg]))
                    }
                } catch let error as FFmpegError {
                    throw error
                } catch {
                     throw FFmpegError.commandFailed("Deep check execution failed for \(file.lastPathComponent)")
                }
            }
        }
        
        return needsReencode
    }

    func merge(files: [URL], fastMerge: Bool, requiresReencode: Bool, normalizeAudio: Bool, fixJitter: Bool, enableStabilize: Bool = false, stabilizeSmoothing: Int = 60, useHEVC: Bool, destinationURL: URL, targetHeight: Int?, metadata: [String: String]? = nil, finderTags: [String]? = nil, onReencodeForced: @escaping () async throws -> Bool = { false }, onProgress: @escaping (Double, TimeInterval, String?) -> Void) async throws -> URL {
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
        
        // --- PRE-PROCESSING: Gimbal Stabilization ---
        var workingFiles = files
        var tempStabilizedFiles: [URL] = []
        
        defer {
            // Clean up intermediate stabilized files at the end
            for url in tempStabilizedFiles {
                try? fileManager.removeItem(at: url)
            }
        }
        
        if enableStabilize {
            for (index, file) in workingFiles.enumerated() {
                let duration = fileDurations[index]
                let clipNum = index + 1
                let totalClips = workingFiles.count
                
                let trfURL = tempDir.appendingPathComponent("transform_\(UUID()).trf")
                let stabExt = useHEVC ? "mov" : "mp4"
                let stabURL = tempDir.appendingPathComponent("stabilized_\(UUID()).\(stabExt)")
                
                defer {
                    try? fileManager.removeItem(at: trfURL)
                }
                
                // Pass 1: vidstabdetect
                let pass1Args = [
                    "-i", file.path,
                    "-vf", "vidstabdetect=shakiness=5:accuracy=15:result=\(trfURL.path)",
                    "-f", "null", "-"
                ]
                print("🎥 Stabilize Pass 1 for clip \(clipNum)")
                try await runFFmpeg(arguments: pass1Args, totalDuration: duration, offsetDuration: 0, startTime: Date()) { prog, rem in
                    onProgress(prog, rem, LanguageManager.shared.localizedDynamic("Stabilize Pass 1", args: ["\(clipNum)", "\(totalClips)"]))
                }
                
                // Pass 2: vidstabtransform
                let vCodec = useHEVC ? "hevc_videotoolbox" : "h264_videotoolbox"
                var pass2Args: [String] = [
                    "-i", file.path,
                    "-vf", "vidstabtransform=input=\(trfURL.path):smoothing=\(stabilizeSmoothing):crop=black:optzoom=1",
                    "-c:v", vCodec, "-b:v", "20M",
                    "-r", "30", "-video_track_timescale", "90000",
                    "-t", String(duration),
                    "-c:a", "copy",
                ]
                if useHEVC { pass2Args += ["-tag:v", "hvc1"] }
                pass2Args += ["-y", stabURL.path]
                print("🎥 Stabilize Pass 2 for clip \(clipNum)")
                try await runFFmpeg(arguments: pass2Args, totalDuration: duration, offsetDuration: 0, startTime: Date()) { prog, rem in
                    onProgress(prog, rem, LanguageManager.shared.localizedDynamic("Stabilize Pass 2", args: ["\(clipNum)", "\(totalClips)"]))
                }
                
                tempStabilizedFiles.append(stabURL)
            }
            
            // Override working files
            workingFiles = tempStabilizedFiles
            
            // Re-calculate durations for the new files
            fileDurations.removeAll()
            totalDuration = 0
            for file in workingFiles {
                let asset = AVURLAsset(url: file)
                let duration = (try? await asset.load(.duration))?.seconds ?? 0
                fileDurations.append(duration)
                totalDuration += duration
            }
        }
        
        var finalUseHEVC = useHEVC
        if requiresReencode && !useHEVC {
            finalUseHEVC = try await onReencodeForced()
        }
        
        // Determine Mode
        let filtersActive = normalizeAudio || fixJitter || targetHeight != nil || finalUseHEVC
        let effectiveFastMerge = (fastMerge || !filtersActive) && !requiresReencode

        let modeMsg: String
        if enableStabilize || filtersActive {
            modeMsg = LanguageManager.shared.localizedDynamic("Mode: Filter / Re-encode", args: [])
        } else if requiresReencode {
            modeMsg = LanguageManager.shared.localizedDynamic("Mode: Smart Re-encode (Format Mismatch)", args: [])
        } else {
            modeMsg = LanguageManager.shared.localizedDynamic("Mode: Fast Merge (Direct Copy)", args: [])
        }
        onProgress(0, -1, modeMsg)

        // Shared progress state
        let startTime = Date()
        
        // --- TIER 1: FAST MERGE (Direct Copy) ---
        var success = false
        
        if effectiveFastMerge {
            // ... TIER 1 Logic ...
            let concatListURL = tempDir.appendingPathComponent("concat_list_\(UUID()).txt")
            var concatContent = ""
            for file in workingFiles {
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
                
                if let first = workingFiles.first {
                    args.append(contentsOf: ["-i", first.path, "-map_metadata", "1", "-map", "0"])
                }
                
                args.append(contentsOf: ["-c", "copy", "-movflags", "use_metadata_tags", "-y", outputURL.path])
                
                print("🚀 Attempting Tier 1 (Direct Copy)...")
                try await runFFmpeg(arguments: args, totalDuration: totalDuration, offsetDuration: 0, startTime: startTime) { prog, rem in onProgress(prog, rem, nil) }
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
            onProgress(0, -1, LanguageManager.shared.localizedDynamic("Fast merge failed. Attempting Rewrap (Tier 2)...", args: []))
            
            // 1. Check Codec
            guard let firstWorkingFile = workingFiles.first else {
                throw FFmpegError.commandFailed("Internal error: no working files available for Tier 2")
            }
            let firstCodec = await getVideoCodec(for: firstWorkingFile)
            let bsf: String?
            if firstCodec == "h264" { bsf = "h264_mp4toannexb" }
            else if firstCodec == "hevc" { bsf = "hevc_mp4toannexb" }
            else { bsf = nil } // Unknown, might fail or not need it
            
            var tsFiles: [URL] = []
            var accumulated: Double = 0
            
            do {
                // Convert each to TS
                for (idx, file) in workingFiles.enumerated() {
                    let tsURL = tempDir.appendingPathComponent("part_\(UUID()).ts")
                    tsFiles.append(tsURL)
                    
                    var args = ["-i", file.path, "-c", "copy"]
                    if let bsf = bsf {
                        args.append(contentsOf: ["-bsf:v", bsf])
                    }
                    args.append(contentsOf: ["-f", "mpegts", "-y", tsURL.path])
                    
                    try await runFFmpeg(arguments: args, totalDuration: totalDuration, offsetDuration: accumulated, startTime: startTime) { prog, rem in onProgress(prog, rem, nil) }
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
        
        if effectiveFastMerge {
            onProgress(0, -1, LanguageManager.shared.localizedDynamic("Fast merge failed. Re-encoding completely (This may take a while)...", args: []))
        } else {
            onProgress(0, -1, LanguageManager.shared.localizedDynamic("Processing with Re-encoding (This may take a while)...", args: []))
        }
        
        // Prompt for HEVC if we fell back from a fast merge attempt and aren't already using it
        if effectiveFastMerge && !finalUseHEVC {
            finalUseHEVC = try await onReencodeForced()
        }
        
        var finalOutputURL = outputURL
        if finalUseHEVC && finalOutputURL.pathExtension.lowercased() != "mov" {
            finalOutputURL = finalOutputURL.deletingPathExtension().appendingPathExtension("mov")
        }
        
        // NEW TIER 3 LOGIC: Sequential Smart Re-encode + Fast Concat
        var tempSegments: [URL] = []
        defer {
            for url in tempSegments {
                try? fileManager.removeItem(at: url)
            }
        }
        
        var completedDuration: Double = 0
        let totalCount = workingFiles.count
        
        for (index, file) in workingFiles.enumerated() {
            let tempSegmentURL = tempDir.appendingPathComponent("segment_\(index)_\(UUID()).mov")
            var segArgs: [String] = []
            
            // Determine if CPU-intensive filters are needed
            let needsCpuFilters = fixJitter || (targetHeight != nil)
            
            // Use hardware decode only when no CPU-side pixel filters are active.
            // yadif and scale require frames in CPU memory; format=nv12 alone does not block hwaccel.
            if !needsCpuFilters {
                segArgs.append(contentsOf: [
                    "-hwaccel", "videotoolbox",
                    "-hwaccel_output_format", "nv12"
                ])
            }
            
            segArgs.append(contentsOf: ["-i", file.path])
            
            // Video Filters — only add what's actually needed
            var vFilters: [String] = []
            if fixJitter { vFilters.append("yadif=0:-1:0") }
            if let height = targetHeight { vFilters.append("scale=-2:\(height):flags=lanczos") }
            vFilters.append("format=nv12")
            segArgs.append(contentsOf: ["-vf", vFilters.joined(separator: ",")])
            
            // Audio Filters
            var aFilters = ["aresample=48000"]
            if normalizeAudio { aFilters.append("loudnorm=I=-16:TP=-1.5:LRA=11") }
            segArgs.append(contentsOf: ["-af", aFilters.joined(separator: ",")])
            
            // Encoder Settings
            if finalUseHEVC {
                 segArgs.append(contentsOf: [
                    "-c:v", "hevc_videotoolbox", "-tag:v", "hvc1",
                    "-b:v", "8M", "-profile:v", "main"
                 ])
            } else {
                 segArgs.append(contentsOf: [
                    "-c:v", "h264_videotoolbox",
                    "-b:v", "12M", "-profile:v", "high"
                 ])
            }
            
            // Force 30fps and 90k timebase to prevent concat demuxer PTS scaling bugs
            segArgs.append(contentsOf: ["-r", "30", "-video_track_timescale", "90000"])
            // Cap output to AVAsset-measured duration to prevent edit list expansion (2x duration bug)
            segArgs.append(contentsOf: ["-t", String(fileDurations[index])])
            segArgs.append(contentsOf: ["-c:a", "aac", "-b:a", "192k", "-y", tempSegmentURL.path])
            
            let segmentDuration = fileDurations[index]
            
            tempSegments.append(tempSegmentURL)

            try await runFFmpeg(
                arguments: segArgs,
                totalDuration: totalDuration,
                offsetDuration: completedDuration,
                startTime: tier3StartTime,
                onProgress: { prog, remaining in
                    // Override status message to show segment progress
                    onProgress(prog, remaining, LanguageManager.shared.localizedDynamic("Processing Segment {0}/{1}", args: ["\(index + 1)", "\(totalCount)"]))
                }
            )

            completedDuration += segmentDuration
        }
        
        // Final Concat Step
        onProgress(1.0, -2, LanguageManager.shared.localizedDynamic("Finalizing (Merging Segments)...", args: []))
        let concatListURL = tempDir.appendingPathComponent("tier3_concat_\(UUID()).txt")
        var concatContent = ""
        for url in tempSegments {
            concatContent += "file '\(url.path)'\n"
        }
        try concatContent.write(to: concatListURL, atomically: true, encoding: .utf8)
        defer { try? fileManager.removeItem(at: concatListURL) }
        
        let concatArgs = [
            "-f", "concat",
            "-safe", "0",
            "-i", concatListURL.path,
            "-c", "copy",
            "-movflags", "+faststart",
            "-y", finalOutputURL.path
        ]
        
        try await runFFmpeg(arguments: concatArgs, totalDuration: totalDuration, offsetDuration: totalDuration - 1, startTime: tier3StartTime) { _, _ in }
        
        // Verify Robust Path too
        try await verifyOutput(finalOutputURL, expectedDuration: totalDuration, tolerance: 10.0) // 10s tolerance for recheck
        
        try? fileManager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: finalOutputURL.path)
        if let finderTags = finderTags, !finderTags.isEmpty {
             try? await Task.sleep(nanoseconds: 200_000_000)
             await self.applyFinderTags(finderTags, to: finalOutputURL)
        }
        
        return finalOutputURL
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
                
                var resumed = false

                process.terminationHandler = { proc in
                    pipe.fileHandleForReading.readabilityHandler = nil
                    try? pipe.fileHandleForReading.close()

                    queue.sync {
                        guard !resumed else { return }
                        resumed = true
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
                    queue.sync {
                        guard !resumed else { return }
                        resumed = true
                        continuation.resume(throwing: error)
                    }
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
        
        let hasError = checkProcess.terminationStatus != 0 || msg.lowercased().contains("error") || msg.contains("Invalid")
        if hasError {
            throw FFmpegError.commandFailed("Verification Integrity Error: \(msg)")
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
                    if elapsedTime > 5 {
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

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
                return "FFmpeg command failed. Check log for details."
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
    private func applyFinderTags(_ tags: [String], to url: URL, retries: Int = 5) {
        guard !tags.isEmpty else { return }
        let tagArray = tags

        // Normalize tags: allow both plain names and "Name\n<colorIndex>"; here we keep as-is
        let normalizedTags = tagArray

        // Helper: try URLResourceValue API
        func setViaResourceValues() throws {
            // Try NSURL API first (works on older macOS too)
            var nsurl = url as NSURL
            try nsurl.setResourceValue(normalizedTags, forKey: .tagNamesKey)

            // Try URLResourceValues API if available at runtime; otherwise skip
            if #available(macOS 26.0, *) {
                var values = URLResourceValues()
                values.tagNames = normalizedTags
                var mutableURL = url
                try mutableURL.setResourceValues(values)
            }
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
            let sleepTime = useconds_t(150_000 * UInt32(attempt))
            usleep(sleepTime)
        }

        print("Failed to apply Finder tags after \(retries) attempts to \(url.path)")
    }
    
    func merge(files: [URL], normalizeAudio: Bool, useHEVC: Bool, outputName: String, targetHeight: Int?, metadata: [String: String]? = nil, finderTags: [String]? = nil, onProgress: @escaping (Double, TimeInterval) -> Void) async throws -> URL {
        let fileManager = FileManager.default
        
        // 1. Create concat.txt
        let tempDir = fileManager.temporaryDirectory
        let concatListURL = tempDir.appendingPathComponent("concat_list_\(UUID()).txt")
        
        var concatContent = ""
        for file in files {
            // ffmpeg requires path to be escaped properly for the concat demuxer
            // format: file '/path/to/file.mp4'
            let path = file.path // standard absolute path
            // We need to escape single quotes if present
            let escapedPath = path.replacingOccurrences(of: "'", with: "'\\''")
            concatContent += "file '\(escapedPath)'\n"
        }
        
        try concatContent.write(to: concatListURL, atomically: true, encoding: .utf8)
        
        // 2. Prepare Output URL (defaults to Desktop for visibility, or same folder as first file)
        // Use the provided output name. Ensure it ends with .mp4
        let firstFileDir = files.first!.deletingLastPathComponent()
        let finalOutputName = outputName.lowercased().hasSuffix(".mp4") ? outputName : "\(outputName).mp4"
        let outputURL = firstFileDir.appendingPathComponent(finalOutputName)
        
        // 3. Run ffmpeg command
        // ffmpeg -f concat -safe 0 -i concat.txt ... output.mp4
        
        // Check if ffmpeg exists
        guard FileManager.default.fileExists(atPath: ffmpegPath) else {
            throw FFmpegError.ffmpegNotFound
        }

        // Calculate total duration for progress
        var totalDuration: Double = 0
        for file in files {
            let asset = AVAsset(url: file)
            // CMTime seconds return Float64 (Double)
            if let duration = try? await asset.load(.duration) {
                totalDuration += duration.seconds
            }
        }

        var arguments = [
            "-f", "concat",
            "-safe", "0",
            "-i", concatListURL.path
        ]
        
        // Use the first file as a source for metadata
        if let firstFile = files.first {
            arguments.append(contentsOf: ["-i", firstFile.path])
            arguments.append(contentsOf: ["-map_metadata", "1"])
            arguments.append(contentsOf: ["-map", "0"])
        }
        
        // Apply user-provided metadata (tags) if any
        if let metadata = metadata {
            for (key, value) in metadata {
                // FFmpeg expects UTF-8; escape `=` and `\n` minimally if needed
                arguments.append(contentsOf: ["-metadata", "\(key)=\(value)"])
            }
        }
        
        // Video Logic
        // Always re-encode to prevent "freeze" issues at junctions caused by copy mode timestamps.
        // Use GPU acceleration for speed.
        if useHEVC {
             // HEVC encoding requested
             arguments.append(contentsOf: [
                "-c:v", "hevc_videotoolbox",
                "-tag:v", "hvc1",
                "-allow_sw", "1",
                "-q:v", "65"
             ])
        } else {
             // Standard H.264 encoding (GPU)
             arguments.append(contentsOf: [
                "-c:v", "h264_videotoolbox",
                "-allow_sw", "1",
                "-q:v", "65"
             ])
        }
        
        // Apply scaling if requested
        if let height = targetHeight {
            arguments.append(contentsOf: ["-vf", "scale=-2:\(height):flags=lanczos"])
        }
        
        // Audio Logic
        // Always re-encode audio to AAC to ensure continuity
        arguments.append(contentsOf: ["-c:a", "aac"])
        if normalizeAudio {
            arguments.append(contentsOf: ["-af", "loudnorm=I=-16:TP=-1.5:LRA=11"])
        } else {
            // High quality default for AAC if not normalising
            arguments.append(contentsOf: ["-b:a", "192k"])
        }
        
        // Ensure container writes metadata tags into atoms appropriately (esp. mp4)
        arguments.append(contentsOf: [
            "-movflags", "use_metadata_tags"
        ])
        
        arguments.append(contentsOf: [
            "-y", // overwrite if exists
            outputURL.path
        ])
             
        // Prevent generic hangs
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        
        return try await withCheckedThrowingContinuation { continuation in
            // ffmpeg writes progress usually to stderr, but sometimes stdout depending on flags.
            // We'll watch both but typically stderr is where log info goes.
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            var collectedData = Data()
            let queue = DispatchQueue(label: "ffmpeg.output.collection")
            let startTime = Date()
            
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty {
                    queue.async {
                        collectedData.append(data)
                        
                        // Parse progress
                        // Look for "time=HH:MM:SS.ss"
                        if let outputString = String(data: data, encoding: .utf8) {
                           parseProgress(lastOutput: outputString, totalDuration: totalDuration, startTime: startTime, onProgress: onProgress)
                        }
                    }
                }
            }
            
            process.terminationHandler = { proc in
                pipe.fileHandleForReading.readabilityHandler = nil
                pipe.fileHandleForReading.closeFile()
                try? fileManager.removeItem(at: concatListURL)
                
                queue.sync {
                      if proc.terminationStatus == 0 {
                         // Ensure file permissions allow writing attributes
                         try? fileManager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: outputURL.path)
                         
                         // Apply Finder tags (robust, with retries) if requested
                         if let finderTags = finderTags, !finderTags.isEmpty {
                             // Small delay to ensure ffmpeg has fully flushed file metadata
                             usleep(200_000)
                             applyFinderTags(finderTags, to: outputURL)
                         }
                         
                         continuation.resume(returning: outputURL)
                     } else {
                         let output = String(data: collectedData, encoding: .utf8) ?? "Unknown error"
                         print("FFmpeg failed with output: \n\(output)")
                         continuation.resume(throwing: FFmpegError.commandFailed(output))
                     }
                }
            }
            
            do {
                print("Running ffmpeg command: \(arguments.joined(separator: " "))")
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    private func parseProgress(lastOutput: String, totalDuration: Double, startTime: Date, onProgress: @escaping (Double, TimeInterval) -> Void) {
        guard totalDuration > 0 else { return }
        
        // Regex to find "time=HH:MM:SS.ss"
        // Simply looking for "time=" and reading the next characters is usually enough and faster than full regex
        let pattern = "time=(\\d{2}):(\\d{2}):(\\d{2}\\.\\d{2})"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return }
        
        let range = NSRange(location: 0, length: lastOutput.utf16.count)
        if let match = regex.firstMatch(in: lastOutput, options: [], range: range) {
            // Extract HH:MM:SS.ss
            if let swiftRange = Range(match.range(at: 0), in: lastOutput) {
                let timeString = String(lastOutput[swiftRange]).replacingOccurrences(of: "time=", with: "")
                let components = timeString.split(separator: ":")
                if components.count == 3,
                   let hours = Double(components[0]),
                   let minutes = Double(components[1]),
                   let seconds = Double(components[2]) {
                    
                    let currentSeconds = hours * 3600 + minutes * 60 + seconds
                    let percentage = min(max(currentSeconds / totalDuration, 0.0), 1.0)
                    
                    // Estimate remaining time
                    let elapsedTime = Date().timeIntervalSince(startTime)
                    var remaining: TimeInterval = 0
                    if percentage > 0 {
                        let estimatedTotalTime = elapsedTime / percentage
                        remaining = estimatedTotalTime - elapsedTime
                    }
                    
                    DispatchQueue.main.async {
                        onProgress(percentage, remaining)
                    }
                }
            }
        }
    }
}


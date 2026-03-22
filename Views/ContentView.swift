import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var filePaths: [URL] = []
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var normalizeAudio = false // Default off to prevent noise
    @State private var useHEVC = false // Default off
    @State private var progress: Double = 0.0
    @State private var remainingTime: TimeInterval?
    @State private var outputFilename: String = "merged.mp4"
    @State private var errorLog: String?
    @State private var showErrorLog = false
    
    enum Resolution: Int, CaseIterable, Identifiable {
        case original = 0
        case fhd = 1080
        case uhd = 2160
        
        var id: Int { self.rawValue }
        var description: String {
            switch self {
            case .original: return "Original (Fast)"
            case .fhd: return "1080p FHD"
            case .uhd: return "4K UHD"
            }
        }
    }
    @State private var selectedResolution: Resolution = .original
    
    var body: some View {
        VStack(spacing: 20) {
            Text("MP4 Merger")
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding(.top)
            Text("Version 0.91")
                .font(.footnote)
                .foregroundColor(.secondary)
                .padding(.bottom, 5)
            
            // Drop zone / List
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.secondary, style: StrokeStyle(lineWidth: 2, dash: [10]))
                    .foregroundColor(.secondary)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.1))
                
                if filePaths.isEmpty {
                    VStack {
                        Image(systemName: "arrow.down.doc")
                            .font(.system(size: 40))
                        Text("Drag & Drop MP4 files here")
                            .font(.headline)
                        Text("Files will be sorted by name")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .foregroundColor(.secondary)
                } else {
                    List {
                        ForEach(Array(filePaths.enumerated()), id: \.element) { index, url in
                            HStack {
                                Text("\(index + 1).")
                                    .fontWeight(.bold)
                                    .foregroundColor(.secondary)
                                    .frame(width: 30, alignment: .trailing)
                                Image(systemName: "film")
                                Text(url.lastPathComponent)
                                Spacer()
                            }
                        }
                        .onMove(perform: moveFiles)
                        .onDelete(perform: deleteFiles)
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .frame(maxHeight: .infinity)
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                loadFiles(from: providers)
                return true
            }
            .padding(.horizontal)
            
            if let error = errorMessage {
                VStack {
                    Text("Error Occurred")
                        .font(.headline)
                        .foregroundColor(.red)
                    Text(error)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    if let log = errorLog {
                         Button("Show Error Log") {
                             showErrorLog = true
                         }
                         .font(.caption)
                    }
                }
                .sheet(isPresented: $showErrorLog) {
                    ScrollView {
                        Text(errorLog ?? "No Log")
                            .font(.system(.caption, design: .monospaced))
                            .padding()
                            .textSelection(.enabled)
                    }
                    .padding()
                }
            }
            
            if let success = successMessage {
                Text(success)
                    .foregroundColor(.green)
            }
            
            if isProcessing {
                VStack(spacing: 8) {
                    ProgressView(value: progress, total: 1.0)
                        .padding(.horizontal)
                    if let remaining = remainingTime {
                        Text("Remaining: \(formatTime(remaining))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Estimating time...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            HStack {
                TextField("Output Filename", text: $outputFilename)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                
                Button("Clear All") {
                    filePaths.removeAll()
                    resetMessages()
                    outputFilename = "merged.mp4"
                }
                .disabled(isProcessing || filePaths.isEmpty)
                
                Button("Sort by Name") {
                    withAnimation {
                        filePaths.sort { $0.lastPathComponent < $1.lastPathComponent }
                    }
                }
                .disabled(isProcessing || filePaths.count < 2)
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    Picker("Resolution", selection: $selectedResolution) {
                        ForEach(Resolution.allCases) { res in
                            Text(res.description).tag(res)
                        }
                    }
                    .frame(width: 200)
                    
                    Toggle("Normalize Audio (Slower)", isOn: $normalizeAudio)
                        .help("Turn on if volumes are inconsistent. May introduce noise in quiet parts.")
                    
                    Toggle("High Efficiency (HEVC)", isOn: $useHEVC)
                        .help("Uses H.265 encoding for smaller file size but slower processing.")
                }
                
                Button("Merge Files") {
                    startMerge()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isProcessing || filePaths.isEmpty)
            }
            .padding()
        }
    }
    
    private func formatTime(_ interval: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: interval) ?? ""
    }
    

    
    private func moveFiles(from source: IndexSet, to destination: Int) {
        filePaths.move(fromOffsets: source, toOffset: destination)
    }
    
    private func deleteFiles(at offsets: IndexSet) {
        filePaths.remove(atOffsets: offsets)
    }
    
    private func resetMessages() {
        errorMessage = nil
        successMessage = nil
    }
    
    private func loadFiles(from providers: [NSItemProvider]) {
        resetMessages()
        Task {
            var newFiles: [URL] = []
            for provider in providers {
                if let item = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil),
                   let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    
                    if url.pathExtension.lowercased() == "mp4" {
                        newFiles.append(url)
                    }
                }
            }
            
            // Sort new batch by name
            newFiles.sort { $0.lastPathComponent < $1.lastPathComponent }
            
            await MainActor.run {
                let isFirstLoad = filePaths.isEmpty
                
                for url in newFiles {
                    if !filePaths.contains(url) {
                        filePaths.append(url)
                    }
                }
                
                // Smart naming logic: run only on first load or if name is default
                if !filePaths.isEmpty && (isFirstLoad || outputFilename == "merged.mp4") {
                     updateOutputFilenameSuggestion()
                }
            }
        }
    }
    
    private func updateOutputFilenameSuggestion() {
        guard let firstFile = filePaths.first else { return }
        
        let filename = firstFile.deletingPathExtension().lastPathComponent
        // Regex to remove tailing _1, _01, _123 etc.
        let pattern = "_\\d+$"
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(location: 0, length: filename.utf16.count)
            let newName = regex.stringByReplacingMatches(in: filename, options: [], range: range, withTemplate: "")
            // If the regex removed something, we might still want to add _merged to be safe, 
            // or maybe the user intends to create the "clean" master.
            // But to avoid the "in-place" error if the clean name also exists or is input:
            outputFilename = newName + "_merged.mp4"
        } else {
            outputFilename = filename + "_merged.mp4"
        }
    }
    
    private func startMerge() {
        guard !filePaths.isEmpty else { return } // Allow single file
        isProcessing = true
        progress = 0.0
        remainingTime = nil
        resetMessages()
        
        let targetH = selectedResolution == .original ? nil : selectedResolution.rawValue
        
        Task {
            do {
                let runner = FFmpegRunner()
                let outputURL = try await runner.merge(
                    files: filePaths,
                    normalizeAudio: normalizeAudio,
                    useHEVC: useHEVC,
                    outputName: outputFilename,
                    targetHeight: targetH
                ) { prog, remaining in
                    self.progress = prog
                    self.remainingTime = remaining
                }
                
                await MainActor.run {
                    successMessage = "Merged successfully! Saved to: \(outputURL.path)"
                    isProcessing = false
                    progress = 1.0
                    remainingTime = 0
                    // Optional: Reveal in Finder?
                    NSWorkspace.shared.activateFileViewerSelecting([outputURL])
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    if let ffmpegError = error as? FFmpegRunner.FFmpegError,
                       case .commandFailed(let log) = ffmpegError {
                        errorLog = log
                    } else {
                        errorLog = "\(error)"
                    }
                    isProcessing = false
                }
            }
        }
    }
}

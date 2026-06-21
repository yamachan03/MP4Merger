import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

struct ContentView: View {
    struct MediaFile: Identifiable, Hashable {
        let id = UUID()
        let url: URL
        let duration: Double
        let size: Int64
        var tags: [String]?
        var isProcessed: Bool = false
        
        var formattedDuration: String {
            let formatter = DateComponentsFormatter()
            formatter.allowedUnits = [.hour, .minute, .second]
            formatter.unitsStyle = .positional
            formatter.zeroFormattingBehavior = .pad
            return formatter.string(from: duration) ?? "00:00"
        }
        
        var formattedSize: String {
            return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        }
    }

    @EnvironmentObject var lm: LanguageManager
    @State private var files: [MediaFile] = []
    
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var normalizeAudio = false // Default off to prevent noise
    @State private var fixJitter = false // Default off
    @State private var useHEVC = false // Default off
    @State private var enableStabilize = false // Default off
    @AppStorage("stabilizeSmoothing") private var stabilizeSmoothing: Double = 50.0
    @AppStorage("keepOptions") private var keepOptions = false // Keep options on Clear All
    @AppStorage("warnSlowMerge") private var warnSlowMerge = false
    @State private var enableDeepValidation = false // Deep integrity check
    @State private var progress: Double = 0.0
    @State private var remainingTime: TimeInterval?
    @State private var statusMessage: String? = nil
    @State private var outputFilename: String = ""
    @State private var errorLog: String?
    @State private var showErrorLog = false
    @State private var showSlowMergeWarning = false
    @State private var slowMergeWarningMessage = ""
    @State private var pendingDestinationURL: URL? = nil
    @State private var isPendingBatchProcess = false
    @State private var currentTask: Task<Void, Never>? // Active task reference
    
    enum Resolution: Int, CaseIterable, Identifiable {
        case original = 0
        case fhd = 1080
        case uhd = 2160
        
        var id: Int { self.rawValue }
        var rawDescription: String {
            switch self {
            case .original: return "Original (Fast)"
            case .fhd: return "1080p FHD"
            case .uhd: return "4K UHD"
            }
        }
    }
    @State private var selectedResolution: Resolution = .original
    @State private var mergeOutput = true
    
    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        return "\(lm.localized("Version")) \(version)"
    }
    
    var body: some View {
        VStack(spacing: 10) {
            Text(lm.localized("MP4 Merger"))
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding(.top, 30)
            Text(appVersion)
                .font(.footnote)
                .foregroundColor(.secondary)
                .padding(.bottom, 5)
            
            fileListSection
                .frame(minHeight: 150, maxHeight: .infinity)
            
            // Settings Toolbar
            HStack {
                Spacer()
                
                VStack(alignment: .leading, spacing: 10) {
                    Text(lm.localized("Options"))
                        .font(.headline)
                    
                    HStack {
                        Text(lm.localized("Resolution:"))
                        Picker("", selection: $selectedResolution) {
                            ForEach(Resolution.allCases) { res in
                                Text(lm.localized(res.rawDescription)).tag(res)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 150)
                    }
                    
                    Toggle(lm.localized("Fix Jitter"), isOn: $fixJitter)
                        .toggleStyle(.checkbox)
                        .onChange(of: fixJitter) {
                            updateOutputFilenameSuggestion()
                        }
                    
                    VStack(alignment: .leading, spacing: 5) {
                        Toggle(lm.localized("Gimbal Stabilization"), isOn: $enableStabilize)
                            .toggleStyle(.checkbox)
                            .onChange(of: enableStabilize) {
                                updateOutputFilenameSuggestion()
                            }
                        
                        if enableStabilize {
                            HStack {
                                Text(lm.localized("Smoothing:"))
                                    .font(.caption)
                                Slider(value: $stabilizeSmoothing, in: 10...100, step: 1)
                                    .frame(width: 100)
                                TextField("", value: $stabilizeSmoothing, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 50)
                                    .font(.caption)
                            }
                            .padding(.leading, 20)
                        }
                    }
                    
                    Toggle(lm.localized("HEVC (High Compression)"), isOn: $useHEVC)
                        .toggleStyle(.checkbox)
                        .onChange(of: useHEVC) {
                            updateOutputFilenameSuggestion()
                        }
                    
                    Toggle(lm.localized("Normalize Audio"), isOn: $normalizeAudio)
                        .toggleStyle(.checkbox)
                        .onChange(of: normalizeAudio) {
                             updateOutputFilenameSuggestion()
                        }
                    
                    Toggle(lm.localized("Run Deep Validation"), isOn: $enableDeepValidation)
                        .toggleStyle(.checkbox)
                        .help(lm.localized("Check files for corruption before processing. This may take some time."))
                    
                    Divider()
                        .padding(.vertical, 2)
                    
                    Toggle(lm.localized("Merge into single file"), isOn: $mergeOutput)
                        .toggleStyle(.checkbox)
                        .onChange(of: mergeOutput) {
                             if mergeOutput && !files.isEmpty {
                                 updateOutputFilenameSuggestion()
                             }
                        }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
            }
            .padding(.horizontal)
            .disabled(isProcessing)
            
            // Status Messages & Progress
            if let error = errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red)
                    Text(error).foregroundColor(.red)
                    Spacer()
                    if let log = errorLog {
                        Button(lm.localized("Show Log")) { showErrorLog = true }
                    }
                }
                .padding()
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
                .sheet(isPresented: $showErrorLog) {
                    ScrollView {
                        Text(errorLog ?? lm.localized("No log available"))
                            .font(.system(.caption, design: .monospaced))
                            .padding()
                    }
                    .frame(minWidth: 600, minHeight: 400)
                }
            }
            
            if let success = successMessage {
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                    Text(success).foregroundColor(.green)
                }
                .padding()
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)
            }
            
            if isProcessing {
                VStack(alignment: .leading, spacing: 5) {
                    if let msg = statusMessage {
                        Text(msg)
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.orange)
                    }
                    ProgressView(value: progress)
                    HStack {
                        if let remaining = remainingTime {
                            if remaining < 0 {
                                if remaining == -2 {
                                     Text(lm.localized("Processing... (Finalizing)"))
                                } else {
                                     Text(lm.localized("Calculating remaining time..."))
                                }
                            } else {
                                Text("\(lm.localized("Remaining:")) \(formatTime(remaining))")
                            }
                        } else {
                            Text(lm.localized("Preparing..."))
                        }
                        Spacer()
                        Text("\(Int(progress * 100))%")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                .padding(.horizontal)
            }
            
            HStack(alignment: .bottom, spacing: 20) {
                VStack(alignment: .leading, spacing: 5) {
                    if mergeOutput {
                        Text(lm.localized("Output Filename"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("", text: $outputFilename)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 220)
                    } else {
                        Text(lm.localized("Output Filename"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(lm.localized("Files will be saved in selected folder"))
                            .foregroundColor(.secondary)
                            .frame(width: 220, alignment: .leading)
                            .padding(.bottom, 4)
                    }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(lm.localized("Keep Options"), isOn: $keepOptions)
                        .toggleStyle(.checkbox)
                        .help(lm.localized("Keep Options Help"))
                        
                    Toggle(lm.localized("Warn on Slow Process"), isOn: $warnSlowMerge)
                        .toggleStyle(.checkbox)
                        .help(lm.localized("Warn on Slow Process Help"))
                }
                
                Spacer()
                
                HStack(spacing: 10) {
                    Button(lm.localized("Clear All")) {
                        clearAll()
                    }
                    .disabled(files.isEmpty)
                    
                    Button(lm.localized("Sort by Name")) {
                        withAnimation {
                            files.sort { $0.url.lastPathComponent < $1.url.lastPathComponent }
                        }
                    }
                    .disabled(isProcessing || files.count < 2)
                    
                    Button(mergeOutput ? lm.localized("Merge Files") : lm.localized("Process Files")) {
                        showSavePanel()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isProcessing || files.isEmpty)
                }
            }
            .padding()
            .padding(.bottom, 20)
        }
    }
    
    @ViewBuilder
    private var fileListSection: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.secondary, style: StrokeStyle(lineWidth: 2, dash: [10]))
                .foregroundColor(.secondary)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.1))
            if files.isEmpty {
                VStack {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 40))
                    Text(lm.localized("Drag & Drop MP4 files here"))
                        .font(.headline)
                    Text(lm.localized("Files will be sorted by name"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .foregroundColor(.secondary)
            } else {
                List {
                    ForEach(Array(files.enumerated()), id: \.element.id) { index, file in
                        fileRow(index: index, file: file)
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
        .alert(lm.localized("Processing Time Warning"), isPresented: $showSlowMergeWarning) {
            Button(lm.localized("Cancel Processing"), role: .cancel) {
                pendingDestinationURL = nil
                clearAll()
            }
            Button(lm.localized("Proceed")) {
                if let dest = pendingDestinationURL {
                    proceedWithMerge(destination: dest, isBatch: isPendingBatchProcess)
                }
                pendingDestinationURL = nil
            }
        } message: {
            Text(slowMergeWarningMessage + "\n\n" + lm.localized("This process will take a significant amount of time. Do you want to proceed?"))
        }
    }
    
    private func fileRow(index: Int, file: MediaFile) -> some View {
        HStack {
            Text("\(index + 1).")
                .fontWeight(.bold)
                .foregroundColor(.secondary)
                .frame(width: 30, alignment: .trailing)
            Image(systemName: "film")
            VStack(alignment: .leading) {
                Text(file.url.lastPathComponent)
                    .truncationMode(.middle)
                HStack {
                    Text(file.formattedSize)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("•")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(file.formattedDuration)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    if let tags = file.tags, !tags.isEmpty {
                        Text("•")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        HStack(spacing: 4) {
                            ForEach(tags, id: \.self) { tag in
                                Text(tag)
                                    .font(.system(size: 9))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.2))
                                    .cornerRadius(4)
                            }
                        }
                    }
                }
            }
            
            Spacer()
            
            if file.isProcessed {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .help(lm.localized("Successfully processed"))
            }
        }
    }
    
    private func formatTime(_ interval: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: interval) ?? ""
    }

    private func moveFiles(from source: IndexSet, to destination: Int) {
        files.move(fromOffsets: source, toOffset: destination)
    }
    
    private func deleteFiles(at offsets: IndexSet) {
        files.remove(atOffsets: offsets)
    }
    
    private func resetMessages() {
        errorMessage = nil
        successMessage = nil
    }
    
    private func clearAll() {
        // Cancel any running task
        currentTask?.cancel()
        currentTask = nil
        isProcessing = false
        
        files.removeAll()
        resetMessages()
        progress = 0.0
        remainingTime = nil
        errorLog = nil
        showErrorLog = false
        
        if !keepOptions {
            normalizeAudio = false
            fixJitter = false
            enableStabilize = false
            useHEVC = false
            enableDeepValidation = false
            selectedResolution = .original
        }
        outputFilename = ""
    }
    
    private func loadFiles(from providers: [NSItemProvider]) {
        if successMessage != nil {
            clearAll()
        } else {
            resetMessages()
        }
        Task {
            var newURLs: [URL] = []
            for provider in providers {
                if let item = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil),
                   let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    
                    let ext = url.pathExtension.lowercased()
                    if ext == "lrf" {
                        continue // Explicitly ignore .lrf files
                    }
                    if ext == "mp4" || ext == "mov" {
                        newURLs.append(url)
                    }
                }
            }
            
            // Sort new batch
            newURLs.sort { $0.lastPathComponent < $1.lastPathComponent }
            
            var newMediaFiles: [MediaFile] = []
            for url in newURLs {
                let asset = AVURLAsset(url: url)
                let duration = (try? await asset.load(.duration))?.seconds ?? 0
                let resources = try? url.resourceValues(forKeys: [.fileSizeKey, .tagNamesKey])
                let size = Int64(resources?.fileSize ?? 0)
                let tags = resources?.tagNames
                
                newMediaFiles.append(MediaFile(url: url, duration: duration, size: size, tags: tags))
            }
            
            await MainActor.run {
                let isFirstLoad = files.isEmpty
                let previousCount = files.count
                
                for file in newMediaFiles {
                    // Avoid checking URL duplication for now or use URL as ID
                    if !files.contains(where: { $0.url == file.url }) {
                        files.append(file)
                    }
                }
                
                let newTotal = files.count
                if previousCount <= 1 && newTotal > 1 {
                    mergeOutput = true
                } else if newTotal <= 1 {
                    mergeOutput = false
                }
                
                // Smart naming logic: run only on first load or if name is default
                if !files.isEmpty && (isFirstLoad || outputFilename.isEmpty) {
                    updateOutputFilenameSuggestion()
                }
            }
        }
    }
    
    private func updateOutputFilenameSuggestion() {
        guard let firstFile = files.first else { return }
        
        let originalName = firstFile.url.deletingPathExtension().lastPathComponent
        var baseName = originalName
        let isSingleFile = files.count == 1
        
        // 1. If multiple files, clean sequence number from first filename to make a generic base name
        if !isSingleFile {
            if let regex = try? NSRegularExpression(pattern: "[ _]\\d+$") {
                let range = NSRange(location: 0, length: originalName.utf16.count)
                let cleaned = regex.stringByReplacingMatches(in: originalName, options: [], range: range, withTemplate: "")
                if !cleaned.isEmpty { baseName = cleaned }
            }
        }
        
        // 2. Build Suffixes based on active filters
        var suffixes = ""
        
        if fixJitter { suffixes += "_fix" }
        if enableStabilize { suffixes += "_stab" }
        if normalizeAudio { suffixes += "_norm" }
        
        switch selectedResolution {
        case .fhd: suffixes += "_1080"
        case .uhd: suffixes += "_4k"
        default: break
        }
        
        // 3. Extension
        let ext = useHEVC ? "mov" : "mp4"
        
        // 4. Construct Name
        let inputExt = firstFile.url.pathExtension.lowercased()
        let isSameExt = (inputExt == "mp4" && !useHEVC) || (inputExt == "mov" && useHEVC)
        
        var suggestedName = ""
        if isSingleFile && suffixes.isEmpty && isSameExt {
            // No functional changes that alter name, avoid in-place overwrite
            suggestedName = "\(baseName)_merged.\(ext)"
        } else {
            suggestedName = "\(baseName)\(suffixes).\(ext)"
        }
        
        // 5. Prevent collision with any input file
        var finalName = suggestedName
        var attempt = 1
        while files.contains(where: { $0.url.lastPathComponent.lowercased() == finalName.lowercased() }) {
            if attempt == 1 {
                finalName = "\(baseName)\(suffixes)_merged.\(ext)"
            } else {
                finalName = "\(baseName)\(suffixes)_merged\(attempt).\(ext)"
            }
            attempt += 1
        }
        
        outputFilename = finalName
    }
    
    private func proceedWithMerge(destination: URL, isBatch: Bool) {
        if isBatch {
            startBatchProcess(destinationFolder: destination)
        } else {
            startMerge(destination: destination)
        }
    }
    
    private func checkMergeSpeedAndProceed(destination: URL, isBatch: Bool) {
        guard !files.isEmpty else { return }
        let currentFiles = files.map { $0.url }
        let filtersActive = normalizeAudio || fixJitter || selectedResolution != .original || useHEVC || enableStabilize
        
        if !warnSlowMerge {
            proceedWithMerge(destination: destination, isBatch: isBatch)
            return
        }
        
        if filtersActive {
            self.slowMergeWarningMessage = lm.localized("Reason: Filters are active")
            self.pendingDestinationURL = destination
            self.isPendingBatchProcess = isBatch
            self.showSlowMergeWarning = true
            return
        }
        
        isProcessing = true
        statusMessage = lm.localized("Validating files...")
        
        currentTask = Task {
            do {
                let runner = FFmpegRunner()
                let requiresReencode = try await runner.validateFiles(files: currentFiles, checkFormat: true, deepCheck: false)
                
                await MainActor.run {
                    self.isProcessing = false
                    self.statusMessage = nil
                    
                    if requiresReencode {
                        self.slowMergeWarningMessage = lm.localized("Reason: Format Mismatch")
                        self.pendingDestinationURL = destination
                        self.isPendingBatchProcess = isBatch
                        self.showSlowMergeWarning = true
                    } else {
                        self.proceedWithMerge(destination: destination, isBatch: isBatch)
                    }
                }
            } catch {
                await MainActor.run {
                    self.isProcessing = false
                    self.statusMessage = nil
                    self.errorMessage = error.localizedDescription
                    self.errorLog = error.localizedDescription
                    self.showErrorLog = true
                }
            }
        }
    }

    private func showSavePanel() {
        if mergeOutput {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.mpeg4Movie, .quickTimeMovie]
            panel.nameFieldStringValue = outputFilename
            panel.canCreateDirectories = true
            panel.message = lm.localized("Save destination")
            
            if let firstFile = files.first {
                panel.directoryURL = firstFile.url.deletingLastPathComponent()
            }
            
            panel.begin { response in
                if response == .OK, let url = panel.url {
                    checkMergeSpeedAndProceed(destination: url, isBatch: false)
                }
            }
        } else {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.canCreateDirectories = true
            panel.message = lm.localized("Select destination folder")
            
            if let firstFile = files.first {
                panel.directoryURL = firstFile.url.deletingLastPathComponent()
            }
            
            panel.begin { response in
                if response == .OK, let url = panel.url {
                    checkMergeSpeedAndProceed(destination: url, isBatch: true)
                }
            }
        }
    }

    private func startMerge(destination: URL) {
        guard !files.isEmpty else { return }
        isProcessing = true
        progress = 0.0
        remainingTime = nil
        resetMessages()
        errorLog = nil
        
        let currentFiles = files.map { $0.url }
        let currentNormalize = normalizeAudio
        let currentFixJitter = fixJitter
        let currentEnableStabilize = enableStabilize
        let currentStabilizeSmoothing = Int(stabilizeSmoothing)
        let currentHEVC = useHEVC
        let targetH = selectedResolution == .original ? nil : selectedResolution.rawValue
        let currentDeepValidation = enableDeepValidation
        
        currentTask = Task {
            do {
                let runner = FFmpegRunner()
                
                await MainActor.run {
                    self.statusMessage = lm.localized("Validating files...")
                }
                let requiresReencode = try await runner.validateFiles(files: currentFiles, checkFormat: true, deepCheck: currentDeepValidation)
                
                let uniqueTags = Array(Set(files.compactMap { $0.tags }.flatMap { $0 }))
                
                let outputURL = try await runner.merge(
                    files: currentFiles,
                    fastMerge: false,
                    requiresReencode: requiresReencode,
                    normalizeAudio: currentNormalize,
                    fixJitter: currentFixJitter,
                    enableStabilize: currentEnableStabilize,
                    stabilizeSmoothing: currentStabilizeSmoothing,
                    useHEVC: currentHEVC,
                    destinationURL: destination,
                    targetHeight: targetH,
                    finderTags: uniqueTags.isEmpty ? nil : uniqueTags,
                    onReencodeForced: {
                        return false
                    }
                ) { prog, remaining, status in
                    Task { @MainActor in
                        self.progress = prog
                        self.remainingTime = remaining
                        if let st = status {
                            if st.isEmpty { self.statusMessage = nil }
                            else { self.statusMessage = st }
                        }
                    }
                }
                
                if !Task.isCancelled {
                    await MainActor.run {
                        successMessage = "\(lm.localized("Merged successfully! Saved to:")) \(outputURL.path)"
                        isProcessing = false
                        progress = 1.0
                        remainingTime = 0
                        
                        // Mark files as processed
                        for i in 0..<self.files.count {
                             // Assuming files haven't changed order; relying on index
                             if i < self.files.count {
                                 self.files[i].isProcessed = true
                             }
                        }
                        
                        NSWorkspace.shared.activateFileViewerSelecting([outputURL])
                    }
                }
            } catch {
                if !Task.isCancelled {
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
    
    private func startBatchProcess(destinationFolder: URL) {
        guard !files.isEmpty else { return }
        isProcessing = true
        progress = 0.0
        remainingTime = nil
        resetMessages()
        errorLog = nil
        
        let currentFiles = files
        let currentNormalize = normalizeAudio
        let currentFixJitter = fixJitter
        let currentEnableStabilize = enableStabilize
        let currentStabilizeSmoothing = Int(stabilizeSmoothing)
        let currentHEVC = useHEVC
        let targetH = selectedResolution == .original ? nil : selectedResolution.rawValue
        let currentDeepValidation = enableDeepValidation
        
        // Compute suffix locally
        var suffixes = ""
        if currentFixJitter { suffixes += "_fix" }
        if currentEnableStabilize { suffixes += "_stab" }
        if currentNormalize { suffixes += "_norm" }
        switch selectedResolution {
        case .fhd: suffixes += "_1080"
        case .uhd: suffixes += "_4k"
        default: break
        }
        let ext = currentHEVC ? "mov" : "mp4"
        
        currentTask = Task {
            var completedCount = 0
            let totalCount = currentFiles.count
            let startTime = Date()
            
            await MainActor.run {
                self.statusMessage = lm.localized("Validating files...")
            }
            do {
                let runner = FFmpegRunner()
                _ = try await runner.validateFiles(files: currentFiles.map { $0.url }, checkFormat: false, deepCheck: currentDeepValidation)
            } catch {
                if !Task.isCancelled {
                    await MainActor.run {
                        self.errorMessage = error.localizedDescription
                        if let ffmpegError = error as? FFmpegRunner.FFmpegError,
                           case .commandFailed(let log) = ffmpegError {
                            self.errorLog = log
                        } else {
                            self.errorLog = "\(error)"
                        }
                        self.isProcessing = false
                    }
                }
                return
            }
            
            for file in currentFiles {
                if Task.isCancelled { break }
                
                let originalName = file.url.deletingPathExtension().lastPathComponent
                
                // Clean sequence number like in merge
                var baseName = originalName
                if let regex = try? NSRegularExpression(pattern: "[ _]\\d+$") {
                    let range = NSRange(location: 0, length: originalName.utf16.count)
                    let cleaned = regex.stringByReplacingMatches(in: originalName, options: [], range: range, withTemplate: "")
                    if !cleaned.isEmpty { baseName = cleaned }
                }
                
                let outputName = "\(baseName)\(suffixes).\(ext)"
                var outputURL = destinationFolder.appendingPathComponent(outputName)
                
                // Prevent overwrite explicitly
                var copyIndex = 1
                while FileManager.default.fileExists(atPath: outputURL.path) && copyIndex < 100 {
                     outputURL = destinationFolder.appendingPathComponent("\(baseName)\(suffixes)_\(copyIndex).\(ext)")
                     copyIndex += 1
                }
                
                await MainActor.run {
                    self.statusMessage = lm.localizedDynamic("Processing file {0}/{1}...", args: ["\(completedCount + 1)", "\(totalCount)"])
                }
                
                do {
                    let runner = FFmpegRunner()
                    _ = try await runner.merge(
                        files: [file.url], // Process single file
                        fastMerge: false,
                        requiresReencode: false,
                        normalizeAudio: currentNormalize,
                        fixJitter: currentFixJitter,
                        enableStabilize: currentEnableStabilize,
                        stabilizeSmoothing: currentStabilizeSmoothing,
                        useHEVC: currentHEVC,
                        destinationURL: outputURL,
                        targetHeight: targetH,
                        finderTags: file.tags
                    ) { prog, _, status in
                        Task { @MainActor in
                            let overallProg = (Double(completedCount) + prog) / Double(totalCount)
                            self.progress = overallProg
                            
                            // Estimate remaining time based on overall progress
                            if overallProg > 0.05 { // wait until 5% to estimate
                                let elapsed = Date().timeIntervalSince(startTime)
                                let estTotal = elapsed / overallProg
                                self.remainingTime = estTotal - elapsed
                            }
                            
                            if let st = status {
                                let baseMsg = self.lm.localizedDynamic("Processing file {0}/{1}...", args: ["\(completedCount + 1)", "\(totalCount)"])
                                if st.isEmpty {
                                    self.statusMessage = baseMsg
                                } else {
                                    self.statusMessage = "\(baseMsg) - \(st)"
                                }
                            }
                        }
                    }
                    completedCount += 1
                    
                    await MainActor.run {
                        if let idx = self.files.firstIndex(where: { $0.id == file.id }) {
                            self.files[idx].isProcessed = true
                        }
                    }
                } catch {
                    if !Task.isCancelled {
                        await MainActor.run {
                            self.errorMessage = error.localizedDescription
                            if let ffmpegError = error as? FFmpegRunner.FFmpegError,
                               case .commandFailed(let log) = ffmpegError {
                                self.errorLog = log
                            } else {
                                self.errorLog = "\(error)"
                            }
                            self.isProcessing = false
                        }
                    }
                    return // Stop on first error
                }
            }
            
            if !Task.isCancelled {
                await MainActor.run {
                    self.successMessage = "\(self.lm.localized("Batch processed successfully!")) \(destinationFolder.path)"
                    self.isProcessing = false
                    self.progress = 1.0
                    self.remainingTime = 0
                    self.statusMessage = nil
                    NSWorkspace.shared.activateFileViewerSelecting([destinationFolder])
                }
            }
        }
    }
}

func readUserTags(from url: URL) -> [String] {
    let attributeName = "com.apple.metadata:_kMDItemUserTags"
    
    return url.withUnsafeFileSystemRepresentation { fileSystemPath -> [String] in
        guard let fileSystemPath = fileSystemPath else { return [] }
        
        let size = getxattr(fileSystemPath, attributeName, nil, 0, 0, 0)
        guard size > 0 else { return [] }
        
        var data = Data(count: size)
        let readSize = data.withUnsafeMutableBytes { buffer in
            getxattr(fileSystemPath, attributeName, buffer.baseAddress, size, 0, 0)
        }
        
        guard readSize == size else { return [] }
        
        do {
            if let tags = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String] {
                // 色情報（例: "\n6"）を取り除いて純粋なタグ名にする
                return tags.compactMap { $0.components(separatedBy: "\n").first }
            }
        } catch { }
        
        return []
    }
}

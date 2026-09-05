import XCTest
@testable import MP4Merger

final class VideoIntegrityCheckerTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("IntegrityCheckerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    @discardableResult
    private func touch(_ relativePath: String) throws -> URL {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data().write(to: url)
        return url
    }

    // MARK: - collectVideos

    func test_collectVideos_singleFile_isAccepted() throws {
        let file = try touch("clip.mp4")
        let found = VideoIntegrityChecker.collectVideos(from: [file], recursive: false)
        XCTAssertEqual(found.map { $0.lastPathComponent }, ["clip.mp4"],
                       "ファイル単体を直接指定してもチェック対象になるべき")
    }

    func test_collectVideos_multipleFiles_areAllAccepted() throws {
        let a = try touch("b.mov")
        let b = try touch("a.mp4")
        let found = VideoIntegrityChecker.collectVideos(from: [a, b], recursive: false)
        XCTAssertEqual(found.map { $0.lastPathComponent }, ["a.mp4", "b.mov"],
                       "複数ファイルを選んだ場合は名前順に並ぶべき")
    }

    func test_collectVideos_nonVideoFile_isIgnored() throws {
        let file = try touch("notes.txt")
        XCTAssertTrue(VideoIntegrityChecker.collectVideos(from: [file], recursive: false).isEmpty,
                      "動画以外を指定しても対象にはならない")
    }

    func test_collectVideos_folderRecursesWhenAsked() throws {
        try touch("top.mp4")
        try touch("sub/nested.mov")
        try touch("sub/readme.md")

        let recursive = VideoIntegrityChecker.collectVideos(from: [root], recursive: true)
        XCTAssertEqual(recursive.map { $0.lastPathComponent }, ["nested.mov", "top.mp4"])

        let shallow = VideoIntegrityChecker.collectVideos(from: [root], recursive: false)
        XCTAssertEqual(shallow.map { $0.lastPathComponent }, ["top.mp4"],
                       "サブフォルダを含まない設定では直下のみ")
    }

    func test_collectVideos_duplicateSelection_isDeduplicated() throws {
        let file = try touch("clip.mp4")
        let found = VideoIntegrityChecker.collectVideos(from: [file, root], recursive: true)
        XCTAssertEqual(found.count, 1, "ファイルとその親フォルダを同時に選んでも二重にならない")
    }

    // MARK: - Diagnostics

    func test_meaningfulDiagnostics_dropsNullMuxerComplaints() {
        // A healthy file still makes the throwaway `-f null` output grumble.
        let raw = "[null @ 0x79480b700] Application provided invalid, non monotonically increasing dts to muxer in stream 0: 3911 >= 3911"
        XCTAssertTrue(VideoIntegrityChecker.meaningfulDiagnostics(raw).isEmpty)
        XCTAssertEqual(VideoIntegrityChecker.classify(VideoIntegrityChecker.meaningfulDiagnostics(raw)), .ok)
    }

    func test_meaningfulDiagnostics_keepsRealFindings() {
        let raw = """
        [null @ 0x1] Application provided invalid, non monotonically increasing dts to muxer in stream 0
        [h264 @ 0x2] Invalid NAL unit size (5587 > 4393).
        """
        let kept = VideoIntegrityChecker.meaningfulDiagnostics(raw)
        XCTAssertEqual(kept, "[h264 @ 0x2] Invalid NAL unit size (5587 > 4393).")
    }

    func test_classify_emptyOutput_isOK() {
        XCTAssertEqual(VideoIntegrityChecker.classify(""), .ok)
        XCTAssertEqual(VideoIntegrityChecker.classify("\n  \n"), .ok)
    }

    func test_classify_bitstreamDamage_isBroken() {
        XCTAssertEqual(VideoIntegrityChecker.classify("[h264 @ 0x1] Invalid NAL unit size (5587 > 4393)."), .broken)
        XCTAssertEqual(VideoIntegrityChecker.classify("stream 1, offset 0x1317091: partial file"), .broken)
        XCTAssertEqual(VideoIntegrityChecker.classify("moov atom not found"), .broken)
    }

    func test_classify_corruptFrameWarning_isWarning() {
        // ffmpeg logs this at warning level, which a `-v error` check never sees.
        XCTAssertEqual(VideoIntegrityChecker.classify("[vist#0:1/h264] corrupt decoded frame"), .warning)
    }

    // MARK: - Estimation

    func test_estimate_scalesWithLevelResolutionAndConcurrency() {
        let hourOf1080p = VideoIntegrityChecker.Target(url: URL(fileURLWithPath: "/tmp/a.mp4"),
                                                       duration: 3600, pixelScale: 1)
        // One file runs on one worker: about 3 minutes for an hour of 1080p.
        let full = VideoIntegrityChecker.estimate(targets: [hourOf1080p], level: .full)
        XCTAssertEqual(full, 3600 * 0.048, accuracy: 0.001)

        // Two files share the machine, so the batch is no slower than one file.
        let pair = VideoIntegrityChecker.estimate(targets: [hourOf1080p, hourOf1080p], level: .full)
        XCTAssertEqual(pair, full, accuracy: 0.001)

        let quick = VideoIntegrityChecker.estimate(targets: [hourOf1080p], level: .quick)
        XCTAssertLessThan(quick, full)

        let uhd = VideoIntegrityChecker.Target(url: URL(fileURLWithPath: "/tmp/b.mp4"),
                                               duration: 3600, pixelScale: 4)
        XCTAssertEqual(VideoIntegrityChecker.estimate(targets: [uhd], level: .full), full * 4, accuracy: 0.001)
    }
}

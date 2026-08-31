import XCTest
@testable import MP4Merger

final class FFmpegSetupTests: XCTestCase {

    // MARK: - 1. parseVersionString

    func test_parseVersionString_releaseVersion_extractsCorrectly() {
        let output = "ffmpeg version 8.1.2 Copyright (c) 2000-2024 the FFmpeg developers\nbuilt with..."
        XCTAssertEqual(FFmpegSetupManager.parseVersionString(output), "8.1.2")
    }

    func test_parseVersionString_twoComponentVersion_extractsCorrectly() {
        let output = "ffmpeg version 6.0 Copyright (c) 2000-2023 the FFmpeg developers\n"
        XCTAssertEqual(FFmpegSetupManager.parseVersionString(output), "6.0")
    }

    func test_parseVersionString_snapshotBuild_returnsNil() {
        // Snapshot builds from evermeet.cx look like "N-112345-gabcdef"
        let output = "ffmpeg version N-112345-gabcdef Copyright (c) 2000-2024 the FFmpeg developers\n"
        XCTAssertNil(FFmpegSetupManager.parseVersionString(output),
                     "スナップショットビルドはバージョン比較できないので nil を返すべき")
    }

    func test_parseVersionString_emptyOutput_returnsNil() {
        XCTAssertNil(FFmpegSetupManager.parseVersionString(""))
    }

    func test_parseVersionString_homebrewOutput_extractsCorrectly() {
        // Homebrew-installed ffmpeg outputs the same format
        let output = "ffmpeg version 7.1 Copyright (c) 2000-2024 the FFmpeg developers\n" +
                     "built with Apple clang version 16.0.0 (clang-1600.0.26.6)\n"
        XCTAssertEqual(FFmpegSetupManager.parseVersionString(output), "7.1")
    }

    // MARK: - 2. isOlderThan（バージョン比較）

    func test_isOlderThan_majorVersionOlder_returnsTrue() {
        XCTAssertTrue(FFmpegSetupManager.isOlderThan("6.0", "8.1.2"))
    }

    func test_isOlderThan_minorVersionOlder_returnsTrue() {
        XCTAssertTrue(FFmpegSetupManager.isOlderThan("8.0", "8.1.2"))
    }

    func test_isOlderThan_patchVersionOlder_returnsTrue() {
        XCTAssertTrue(FFmpegSetupManager.isOlderThan("8.1.1", "8.1.2"))
    }

    func test_isOlderThan_missingPatch_treatedAsZero_returnsTrue() {
        // "8.1" は "8.1.0" と同等なので "8.1.2" より古い
        XCTAssertTrue(FFmpegSetupManager.isOlderThan("8.1", "8.1.2"))
    }

    func test_isOlderThan_sameVersion_returnsFalse() {
        XCTAssertFalse(FFmpegSetupManager.isOlderThan("8.1.2", "8.1.2"))
    }

    func test_isOlderThan_newerMajor_returnsFalse() {
        XCTAssertFalse(FFmpegSetupManager.isOlderThan("9.0", "8.1.2"))
    }

    func test_isOlderThan_newerMinor_returnsFalse() {
        XCTAssertFalse(FFmpegSetupManager.isOlderThan("8.2", "8.1.2"))
    }

    func test_isOlderThan_newerPatch_returnsFalse() {
        XCTAssertFalse(FFmpegSetupManager.isOlderThan("8.1.3", "8.1.2"))
    }

    // MARK: - 3. isFFmpegAvailable（パス解決）

    func test_isFFmpegAvailable_withDownloadedBinary_returnsTrue() throws {
        // Application Support に実行可能ダミーファイルを置いてテスト
        let dir = FFmpegSetupManager.appSupportDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fakeBinary = dir.appendingPathComponent("ffmpeg")

        // ダミーシェルスクリプトを作成
        try "#!/bin/sh\necho 'ffmpeg version 8.1.2'\n".write(to: fakeBinary, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeBinary.path)

        defer { try? FileManager.default.removeItem(at: fakeBinary) }

        XCTAssertTrue(FFmpegSetupManager.isFFmpegAvailable(),
                      "AppSupportにバイナリがある場合はtrueを返すべき")
    }

    func test_isFFmpegAvailable_noFFmpeg_returnsFalse() throws {
        // AppSupport のバイナリを一時的に退避してチェック
        let binary = URL(fileURLWithPath: FFmpegSetupManager.ffmpegPath)
        let backup = binary.appendingPathExtension("bak")
        let existed = FileManager.default.fileExists(atPath: binary.path)

        if existed { try FileManager.default.moveItem(at: binary, to: backup) }
        defer { if existed { try? FileManager.default.moveItem(at: backup, to: binary) } }

        // Homebrew も存在する環境ではこのテストは常に true になるためスキップ
        if FileManager.default.fileExists(atPath: "/opt/homebrew/bin/ffmpeg") ||
           FileManager.default.fileExists(atPath: "/usr/local/bin/ffmpeg") {
            throw XCTSkip("Homebrew ffmpeg がインストールされているためスキップ")
        }

        XCTAssertFalse(FFmpegSetupManager.isFFmpegAvailable())
    }

    // MARK: - 4. checkForUpdate（統合）

    func test_checkForUpdate_withOlderVersion_setsUpdateAvailable() async {
        // parseVersionString + isOlderThan の組み合わせを間接テスト
        let fakeOutput = "ffmpeg version 6.0 Copyright (c) 2000-2023 the FFmpeg developers\n"
        let parsed = FFmpegSetupManager.parseVersionString(fakeOutput)
        XCTAssertEqual(parsed, "6.0")

        let isOlder = FFmpegSetupManager.isOlderThan(parsed!, FFmpegSetupManager.recommendedVersion)
        XCTAssertTrue(isOlder, "6.0 は推奨バージョンより古いので更新フラグが立つべき")
    }

    func test_checkForUpdate_withCurrentVersion_doesNotFlagUpdate() {
        let fakeOutput = "ffmpeg version \(FFmpegSetupManager.recommendedVersion) Copyright (c) 2000-2024 the FFmpeg developers\n"
        let parsed = FFmpegSetupManager.parseVersionString(fakeOutput)
        XCTAssertEqual(parsed, FFmpegSetupManager.recommendedVersion)

        let isOlder = FFmpegSetupManager.isOlderThan(parsed!, FFmpegSetupManager.recommendedVersion)
        XCTAssertFalse(isOlder, "推奨バージョンと同じならフラグは立たないべき")
    }

    // MARK: - 3. アーキテクチャ判定（Rosetta 回避）

    /// Thin little-endian 64-bit Mach-O header for `cpuType`.
    private func thinHeader(cpuType: UInt32) -> [UInt8] {
        var bytes: [UInt8] = [0xCF, 0xFA, 0xED, 0xFE]           // magic 0xFEEDFACF (little-endian)
        withUnsafeBytes(of: cpuType.littleEndian) { bytes.append(contentsOf: $0) }
        bytes.append(contentsOf: [UInt8](repeating: 0, count: 24))
        return bytes
    }

    /// Fat (universal) header listing `cpuTypes`. Fat headers are big-endian.
    private func fatHeader(cpuTypes: [UInt32]) -> [UInt8] {
        var bytes: [UInt8] = [0xCA, 0xFE, 0xBA, 0xBE]           // FAT_MAGIC
        withUnsafeBytes(of: UInt32(cpuTypes.count).bigEndian) { bytes.append(contentsOf: $0) }
        for cpu in cpuTypes {
            withUnsafeBytes(of: cpu.bigEndian) { bytes.append(contentsOf: $0) }
            bytes.append(contentsOf: [UInt8](repeating: 0, count: 16))  // rest of fat_arch
        }
        return bytes
    }

    private var foreignCPUType: UInt32 {
        // Whichever of arm64 / x86_64 this Mac is not
        FFmpegSetupManager.isAppleSilicon ? 0x0100_0007 : 0x0100_000C
    }

    func test_hasNativeSlice_thinNativeBinary_returnsTrue() {
        XCTAssertTrue(FFmpegSetupManager.hasNativeSlice(header: thinHeader(cpuType: FFmpegSetupManager.nativeCPUType)))
    }

    func test_hasNativeSlice_thinForeignBinary_returnsFalse() {
        // evermeet.cx の ffmpeg はこれ（Apple Silicon では Rosetta が必要）
        XCTAssertFalse(FFmpegSetupManager.hasNativeSlice(header: thinHeader(cpuType: foreignCPUType)))
    }

    func test_hasNativeSlice_universalBinary_returnsTrue() {
        let header = fatHeader(cpuTypes: [foreignCPUType, FFmpegSetupManager.nativeCPUType])
        XCTAssertTrue(FFmpegSetupManager.hasNativeSlice(header: header))
    }

    func test_hasNativeSlice_fatWithoutNativeSlice_returnsFalse() {
        XCTAssertFalse(FFmpegSetupManager.hasNativeSlice(header: fatHeader(cpuTypes: [foreignCPUType])))
    }

    func test_hasNativeSlice_garbage_returnsFalse() {
        XCTAssertFalse(FFmpegSetupManager.hasNativeSlice(header: []))
        XCTAssertFalse(FFmpegSetupManager.hasNativeSlice(header: [0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07]))
    }

    func test_isNativeBinary_systemBinary_returnsTrue() {
        // /bin/ls は必ずこの Mac でネイティブに動く
        XCTAssertTrue(FFmpegSetupManager.isNativeBinary(atPath: "/bin/ls"))
    }

    func test_isNativeBinary_missingPath_returnsFalse() {
        XCTAssertFalse(FFmpegSetupManager.isNativeBinary(atPath: "/nonexistent/ffmpeg"))
    }
}

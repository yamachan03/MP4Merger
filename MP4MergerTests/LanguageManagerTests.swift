import XCTest
@testable import MP4Merger

// MARK: - LanguageManagerTests
//
// このテストクラスは LanguageManager の以下の振る舞いを検証します：
//   1. localized(_:)          — 英語／日本語キーから正しい文字列を返す
//   2. localizedDynamic(_:args:) — {0}, {1} プレースホルダーを args で置換する
//   3. 言語切り替え             — currentLanguage を変更すると localized() の返り値が変わる
//   4. 未登録キーのフォールバック — strings に存在しないキーはキー自身を返す
//
// 各テストは UserDefaults への副作用が互いに干渉しないよう、
// setUp / tearDown で "AppLanguage" キーをリセットします。

final class LanguageManagerTests: XCTestCase {

    // MARK: - Setup / Teardown

    override func setUp() {
        super.setUp()
        // 各テスト開始前に AppLanguage を削除しておき、
        // init() のデフォルト（.japanese）が確実に使われるようにする
        UserDefaults.standard.removeObject(forKey: "AppLanguage")
    }

    override func tearDown() {
        // テスト後は副作用をリセットして次のテストに影響させない
        UserDefaults.standard.removeObject(forKey: "AppLanguage")
        UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        super.tearDown()
    }

    // MARK: - 1. localized(_:) — 日本語モード

    func test_localized_knownKey_returnsJapaneseString() {
        // UserDefaults を事前設定してから init() を呼ぶことで言語を固定する
        UserDefaults.standard.set("ja", forKey: "AppLanguage")
        let manager = LanguageManager()

        let result = manager.localized("Merge Files")

        XCTAssertEqual(result, "ファイルを結合",
                       "日本語モードで 'Merge Files' キーは 'ファイルを結合' を返すべき")
    }

    func test_localized_knownKey_returnsEnglishString() {
        UserDefaults.standard.set("en", forKey: "AppLanguage")
        let manager = LanguageManager()

        let result = manager.localized("Merge Files")

        XCTAssertEqual(result, "Merge Files",
                       "英語モードで 'Merge Files' キーは 'Merge Files' を返すべき")
    }

    func test_localized_versionKey_japaneseReturnsCorrectTranslation() {
        UserDefaults.standard.set("ja", forKey: "AppLanguage")
        let manager = LanguageManager()

        let result = manager.localized("Version")

        XCTAssertEqual(result, "バージョン",
                       "日本語モードで 'Version' キーは 'バージョン' を返すべき")
    }

    func test_localized_versionKey_englishReturnsSameAsKey() {
        UserDefaults.standard.set("en", forKey: "AppLanguage")
        let manager = LanguageManager()

        let result = manager.localized("Version")

        XCTAssertEqual(result, "Version",
                       "英語モードで 'Version' キーは 'Version' を返すべき")
    }

    func test_localized_dragAndDropKey_japaneseReturnsCorrectTranslation() {
        UserDefaults.standard.set("ja", forKey: "AppLanguage")
        let manager = LanguageManager()

        let result = manager.localized("Drag & Drop MP4 files here")

        XCTAssertEqual(result, "ここにMP4ファイルをドラッグ＆ドロップ")
    }

    // MARK: - 2. localizedDynamic(_:args:) — プレースホルダー置換

    func test_localizedDynamic_singleArg_replacesPlaceholder() {
        // "Processing Segment {0}/{1}" は引数を2つ取るが、
        // ここではまず1引数のキーとして振る舞いを確認するため別キーを使う
        // "Processing file {0}/{1}..." を英語で使う
        UserDefaults.standard.set("en", forKey: "AppLanguage")
        let manager = LanguageManager()

        let result = manager.localizedDynamic("Processing file {0}/{1}...", args: ["3", "10"])

        // このキーは strings に存在しないため、キー自身が返り、
        // そのキー内の {0}, {1} が置換される
        XCTAssertEqual(result, "Processing file 3/10...",
                       "キー自身が返されたときもプレースホルダー置換は行われるべき")
    }

    func test_localizedDynamic_englishStabilizePass1_replacesClipIndices() {
        UserDefaults.standard.set("en", forKey: "AppLanguage")
        let manager = LanguageManager()

        let result = manager.localizedDynamic("Stabilize Pass 1", args: ["2", "5"])

        XCTAssertEqual(result, "Analyzing (Clip 2/5, Pass 1/2)...",
                       "英語の 'Stabilize Pass 1' で {0}=2, {1}=5 が正しく置換されるべき")
    }

    func test_localizedDynamic_japaneseStabilizePass1_replacesClipIndices() {
        UserDefaults.standard.set("ja", forKey: "AppLanguage")
        let manager = LanguageManager()

        let result = manager.localizedDynamic("Stabilize Pass 1", args: ["1", "3"])

        XCTAssertEqual(result, "解析中 (Clip 1/3, Pass 1/2)...",
                       "日本語の 'Stabilize Pass 1' で {0}=1, {1}=3 が正しく置換されるべき")
    }

    func test_localizedDynamic_englishStabilizePass2_replacesClipIndices() {
        UserDefaults.standard.set("en", forKey: "AppLanguage")
        let manager = LanguageManager()

        let result = manager.localizedDynamic("Stabilize Pass 2", args: ["3", "5"])

        XCTAssertEqual(result, "Stabilizing (Clip 3/5, Pass 2/2)...")
    }

    func test_localizedDynamic_japaneseProcessingSegment_replacesIndices() {
        UserDefaults.standard.set("ja", forKey: "AppLanguage")
        let manager = LanguageManager()

        let result = manager.localizedDynamic("Processing Segment {0}/{1}", args: ["2", "4"])

        XCTAssertEqual(result, "セグメントエンコード中 2/4",
                       "日本語モードで 'Processing Segment {0}/{1}' は翻訳されてからプレースホルダーが置換される")
    }

    func test_localizedDynamic_registeredSegmentKey_japaneseReturnsTranslatedAndReplaced() {
        UserDefaults.standard.set("ja", forKey: "AppLanguage")
        let manager = LanguageManager()

        let result = manager.localizedDynamic("Processing Segment {0}/{1}", args: ["1", "3"])

        XCTAssertEqual(result, "セグメントエンコード中 1/3",
                       "日本語モードで翻訳文字列内のプレースホルダーが正しく置換される")
    }

    func test_localizedDynamic_formatMismatchKey_englishReplacesTwoArgs() {
        UserDefaults.standard.set("en", forKey: "AppLanguage")
        let manager = LanguageManager()

        let key = "Format mismatch detected between {0} and {1}. Fast merge may fail or produce corrupt output."
        let result = manager.localizedDynamic(key, args: ["fileA.mp4", "fileB.mp4"])

        let expected = "Format mismatch detected between fileA.mp4 and fileB.mp4. Fast merge may fail or produce corrupt output."
        XCTAssertEqual(result, expected,
                       "英語モードで2引数の format-mismatch キーが正しく置換されるべき")
    }

    func test_localizedDynamic_formatMismatchKey_japaneseReplacesTwoArgs() {
        UserDefaults.standard.set("ja", forKey: "AppLanguage")
        let manager = LanguageManager()

        let key = "Format mismatch detected between {0} and {1}. Fast merge may fail or produce corrupt output."
        let result = manager.localizedDynamic(key, args: ["動画1.mp4", "動画2.mp4"])

        let expected = "動画1.mp4 と 動画2.mp4 の間でフォーマットの不一致が検出されました。高速結合が失敗するか、映像が乱れる可能性があります。"
        XCTAssertEqual(result, expected,
                       "日本語モードで2引数の format-mismatch キーが正しく置換されるべき")
    }

    func test_localizedDynamic_emptyArgs_returnLocalizedStringUnchanged() {
        UserDefaults.standard.set("en", forKey: "AppLanguage")
        let manager = LanguageManager()

        let result = manager.localizedDynamic("Merge Files", args: [])

        XCTAssertEqual(result, "Merge Files",
                       "args が空のときはプレースホルダーなしのローカライズ文字列をそのまま返す")
    }

    // MARK: - 3. 言語切り替え

    func test_languageSwitch_fromJapaneseToEnglish_localizedReturnsEnglishString() {
        UserDefaults.standard.set("ja", forKey: "AppLanguage")
        let manager = LanguageManager()
        XCTAssertEqual(manager.localized("Clear All"), "すべてクリア",
                       "前提: 日本語モードで正しい翻訳が返ること")

        manager.currentLanguage = .english

        XCTAssertEqual(manager.localized("Clear All"), "Clear All",
                       "英語に切り替えた後は英語文字列が返るべき")
    }

    func test_languageSwitch_fromEnglishToJapanese_localizedReturnsJapaneseString() {
        UserDefaults.standard.set("en", forKey: "AppLanguage")
        let manager = LanguageManager()
        XCTAssertEqual(manager.localized("Settings"), "Settings",
                       "前提: 英語モードで正しい翻訳が返ること")

        manager.currentLanguage = .japanese

        XCTAssertEqual(manager.localized("Settings"), "設定",
                       "日本語に切り替えた後は日本語文字列が返るべき")
    }

    func test_languageSwitch_persistsToUserDefaults() {
        UserDefaults.standard.set("ja", forKey: "AppLanguage")
        let manager = LanguageManager()

        manager.currentLanguage = .english

        let saved = UserDefaults.standard.string(forKey: "AppLanguage")
        XCTAssertEqual(saved, "en",
                       "言語切り替え後は UserDefaults の 'AppLanguage' が新しい値に更新されるべき")
    }

    func test_languageSwitch_alsoUpdatesAppleLanguagesInUserDefaults() {
        UserDefaults.standard.set("ja", forKey: "AppLanguage")
        let manager = LanguageManager()

        manager.currentLanguage = .english

        let appleLanguages = UserDefaults.standard.array(forKey: "AppleLanguages") as? [String]
        XCTAssertEqual(appleLanguages, ["en"],
                       "言語切り替え後は UserDefaults の 'AppleLanguages' も更新されるべき")
    }

    func test_languageSwitch_multipleTimesRetainsLastLanguage() {
        UserDefaults.standard.set("ja", forKey: "AppLanguage")
        let manager = LanguageManager()

        manager.currentLanguage = .english
        manager.currentLanguage = .japanese
        manager.currentLanguage = .english

        XCTAssertEqual(manager.currentLanguage, .english)
        XCTAssertEqual(manager.localized("Merge Files"), "Merge Files",
                       "複数回切り替えても最後に設定した言語が有効になるべき")
    }

    // MARK: - 4. 未登録キーのフォールバック

    func test_localized_unknownKey_returnsKeyItself_inJapanese() {
        UserDefaults.standard.set("ja", forKey: "AppLanguage")
        let manager = LanguageManager()

        let unknownKey = "this_key_does_not_exist"
        let result = manager.localized(unknownKey)

        XCTAssertEqual(result, unknownKey,
                       "日本語モードで未登録キーはキー自身を返すべき")
    }

    func test_localized_unknownKey_returnsKeyItself_inEnglish() {
        UserDefaults.standard.set("en", forKey: "AppLanguage")
        let manager = LanguageManager()

        let unknownKey = "UNKNOWN_LOCALIZATION_KEY"
        let result = manager.localized(unknownKey)

        XCTAssertEqual(result, unknownKey,
                       "英語モードで未登録キーはキー自身を返すべき")
    }

    func test_localized_emptyStringKey_returnsEmptyString() {
        let manager = LanguageManager()

        let result = manager.localized("")

        XCTAssertEqual(result, "",
                       "空文字列キーは空文字列を返すべき（strings に登録がないためキー自身 = 空文字列）")
    }

    func test_localizedDynamic_unknownKeyWithPlaceholders_replacesPlaceholdersInKey() {
        UserDefaults.standard.set("en", forKey: "AppLanguage")
        let manager = LanguageManager()

        let result = manager.localizedDynamic("Unknown {0} key {1}", args: ["foo", "bar"])

        XCTAssertEqual(result, "Unknown foo key bar",
                       "未登録キーでもプレースホルダーは args で置換されるべき")
    }

    // MARK: - 5. init() のデフォルト言語

    func test_init_withNoUserDefaults_defaultsToJapanese() {
        // setUp で AppLanguage を削除済みなので保存値なし → デフォルトは .japanese
        let manager = LanguageManager()

        XCTAssertEqual(manager.currentLanguage, .japanese,
                       "UserDefaults に値がない場合は日本語がデフォルトになるべき")
    }

    func test_init_withSavedEnglish_restoresEnglish() {
        UserDefaults.standard.set("en", forKey: "AppLanguage")
        let manager = LanguageManager()

        XCTAssertEqual(manager.currentLanguage, .english,
                       "UserDefaults に 'en' が保存されている場合は英語で初期化されるべき")
    }

    func test_init_withSavedJapanese_restoresJapanese() {
        UserDefaults.standard.set("ja", forKey: "AppLanguage")
        let manager = LanguageManager()

        XCTAssertEqual(manager.currentLanguage, .japanese,
                       "UserDefaults に 'ja' が保存されている場合は日本語で初期化されるべき")
    }

    func test_init_withInvalidSavedValue_defaultsToJapanese() {
        UserDefaults.standard.set("fr", forKey: "AppLanguage")
        let manager = LanguageManager()

        XCTAssertEqual(manager.currentLanguage, .japanese,
                       "UserDefaults に無効な値がある場合は日本語がデフォルトになるべき")
    }

    // MARK: - 6. String extension

    func test_stringExtension_localizedWithManager_returnsCorrectString() {
        UserDefaults.standard.set("ja", forKey: "AppLanguage")
        let manager = LanguageManager()

        let result = "Language".localized(with: manager)

        XCTAssertEqual(result, "言語",
                       "String extension の localized(with:) が LanguageManager.localized(_:) と同じ結果を返すべき")
    }

    func test_stringExtension_unknownKey_returnsKeyItself() {
        let manager = LanguageManager()

        let result = "no_such_key".localized(with: manager)

        XCTAssertEqual(result, "no_such_key")
    }
}

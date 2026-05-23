import SwiftUI
import Combine

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case japanese = "ja"
    
    var id: String { self.rawValue }
    var displayName: String {
        switch self {
        case .english: return "English"
        case .japanese: return "日本語"
        }
    }
}

class LanguageManager: ObservableObject {
    static let shared = LanguageManager()
    
    @Published var currentLanguage: AppLanguage {
        didSet {
            UserDefaults.standard.set(currentLanguage.rawValue, forKey: "AppLanguage")
            // macOSの標準メニュー（Settings... 等）の言語も強制的に切り替える
            UserDefaults.standard.set([currentLanguage.rawValue], forKey: "AppleLanguages")
            UserDefaults.standard.synchronize()
        }
    }
    
    init() {
        let saved = UserDefaults.standard.string(forKey: "AppLanguage") ?? "ja"
        self.currentLanguage = AppLanguage(rawValue: saved) ?? .japanese
    }
    
    static let strings: [String: [AppLanguage: String]] = [
        "MP4 Merger": [.english: "MP4 Merger", .japanese: "MP4 Merger"],
        "Version": [.english: "Version", .japanese: "バージョン"],
        "Options": [.english: "Options", .japanese: "オプション"],
        "Resolution:": [.english: "Resolution:", .japanese: "解像度:"],
        "Original (Fast)": [.english: "Original (Fast)", .japanese: "オリジナル（高速）"],
        "1080p FHD": [.english: "1080p FHD", .japanese: "1080p FHD"],
        "4K UHD": [.english: "4K UHD", .japanese: "4K UHD"],
        "Fix Jitter": [.english: "Fix Jitter", .japanese: "ジッター修正"],
        "Gimbal Stabilization": [.english: "Gimbal Stabilization", .japanese: "ジンバル揺れ補正（スタビライズ）"],
        "Smoothing:": [.english: "Smoothing:", .japanese: "滑らかさ:"],
        "HEVC (High Compression)": [.english: "HEVC (High Compression)", .japanese: "HEVC（高圧縮）"],
        "Normalize Audio": [.english: "Normalize Audio", .japanese: "音量ノーマライズ"],
        "Drag & Drop MP4 files here": [.english: "Drag & Drop MP4 files here", .japanese: "ここにMP4ファイルをドラッグ＆ドロップ"],
        "Files will be sorted by name": [.english: "Files will be sorted by name", .japanese: "ファイルは名前順にソートされます"],
        "Preparing...": [.english: "Preparing...", .japanese: "準備中..."],
        "Remaining:": [.english: "Remaining:", .japanese: "残り:"],
        "Calculating remaining time...": [.english: "Calculating remaining time...", .japanese: "残り時間を計算中..."],
        "Processing... (Finalizing)": [.english: "Processing... (Finalizing)", .japanese: "処理中...（最終化）"],
        "Output Filename": [.english: "Output Filename", .japanese: "出力ファイル名"],
        "Clear All": [.english: "Clear All", .japanese: "すべてクリア"],
        "Keep Options": [.english: "Keep Options", .japanese: "設定を保持"],
        "Keep Options Help": [.english: "Preserve settings when clearing files", .japanese: "Clear Allを押したときに各種設定を保持します"],
        "Sort by Name": [.english: "Sort by Name", .japanese: "名前順でソート"],
        "Merge Files": [.english: "Merge Files", .japanese: "ファイルを結合"],
        "Show Log": [.english: "Show Log", .japanese: "ログを表示"],
        "No log available": [.english: "No log available", .japanese: "ログはありません"],
        "Successfully processed": [.english: "Successfully processed", .japanese: "処理完了"],
        "Merged successfully! Saved to:": [.english: "Merged successfully! Saved to:", .japanese: "結合成功！保存先:"],
        "Save destination": [.english: "Select destination for merged file", .japanese: "結合したファイルの保存先を選択してください"],
        "Settings": [.english: "Settings", .japanese: "設定"],
        "Language": [.english: "Language", .japanese: "言語"],
        "Stabilize Pass 1": [.english: "Analyzing (Clip {0}/{1}, Pass 1/2)...", .japanese: "解析中 (Clip {0}/{1}, Pass 1/2)..."],
        "Stabilize Pass 2": [.english: "Stabilizing (Clip {0}/{1}, Pass 2/2)...", .japanese: "スタビライズ出力中 (Clip {0}/{1}, Pass 2/2)..."],
        "Merge into single file": [.english: "Merge into single file", .japanese: "出力ファイルを一つに結合する"],
        "Process Files": [.english: "Process Files", .japanese: "処理を開始"],
        "Select destination folder": [.english: "Select destination folder", .japanese: "保存先のフォルダを選択してください"],
        "Files will be saved in selected folder": [.english: "Files will be saved with suffixes", .japanese: "ファイルごとにサフィックスが付与されます"],
        "Batch processed successfully!": [.english: "Batch processed successfully! Saved to:", .japanese: "一括処理が完了しました！ 保存先:"],
        "Processing file {0}/{1}...": [.english: "Processing file {0}/{1}...", .japanese: "ファイル処理中 {0}/{1}..."],
        
        // --- 新機能用に追加 ---
        "Run Deep Validation": [.english: "Run Deep Validation", .japanese: "詳細検証を実行（ディープチェック）"],
        "Check files for corruption before processing. This may take some time.": [.english: "Check files for corruption before processing. This may take some time.", .japanese: "処理前にファイルが破損していないかチェックします。この処理には時間がかかる場合があります。"],
        "Validating files...": [.english: "Validating files...", .japanese: "ファイルを検証中..."],
        "Format mismatch detected between {0} and {1}. Fast merge may fail or produce corrupt output.": [.english: "Format mismatch detected between {0} and {1}. Fast merge may fail or produce corrupt output.", .japanese: "{0} と {1} の間でフォーマットの不一致が検出されました。高速結合が失敗するか、映像が乱れる可能性があります。"],
        "File integrity error detected in {0}:\n{1}": [.english: "File integrity error detected in {0}:\n{1}", .japanese: "{0} のファイル内に破損エラーを検出しました:\n{1}"],
        "Fast merge failed. Attempting Rewrap (Tier 2)...": [.english: "Fast merge failed. Attempting Rewrap (Tier 2)...", .japanese: "高速結合に失敗しました。再パッキング（Tier 2）でやり直しています..."],
        "Merge failed. Re-encoding completely (This may take a while)...": [.english: "Merge failed. Re-encoding completely (This may take a while)...", .japanese: "結合に失敗しました。全体を再エンコードしてやり直しています（時間がかかります）..."],
        
        // --- モード表示用に追加 ---
        "Mode: Filter / Re-encode": [.english: "Mode: Filter / Re-encode", .japanese: "モード: フィルター適用（再エンコード）"],
        "Mode: Smart Re-encode (Format Mismatch)": [.english: "Mode: Smart Re-encode (Format Mismatch)", .japanese: "モード: 自動再エンコード（形式不一致のため）"],
        "Mode: Fast Merge (Direct Copy)": [.english: "Mode: Fast Merge (Direct Copy)", .japanese: "モード: 超高速結合（再エンコードなし）"],
        
        "Fast merge failed. Re-encoding completely (This may take a while)...": [.english: "Fast merge failed. Re-encoding completely (This may take a while)...", .japanese: "高速結合に失敗しました。全体を再エンコードしてやり直しています (時間がかかります)..."],
        "Processing with Re-encoding (This may take a while)...": [.english: "Processing with Re-encoding (This may take a while)...", .japanese: "再エンコード処理を行っています（時間がかかります）..."],
        "Processing Segment {0}/{1}": [.english: "Processing Segment {0}/{1}", .japanese: "セグメントエンコード中 {0}/{1}"],
        "Finalizing (Merging Segments)...": [.english: "Finalizing (Merging Segments)...", .japanese: "最終処理中（セグメント結合）..."]
    ]
    
    func localized(_ key: String) -> String {
        guard let translations = Self.strings[key] else { return key }
        return translations[currentLanguage] ?? translations[.english] ?? key
    }
    
    func localizedDynamic(_ baseKey: String, args: [String]) -> String {
        // Simple interpolation for dynamics, e.g., "Clip X/Y"
        var str = localized(baseKey)
        for (i, arg) in args.enumerated() {
            str = str.replacingOccurrences(of: "{\(i)}", with: arg)
        }
        return str
    }
}

extension String {
    func localized(with manager: LanguageManager) -> String {
        return manager.localized(self)
    }
}

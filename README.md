# MP4 Merger (for macOS)

**"Combine multiple videos into one with consistent volume and resolution."**

MP4 Merger is a simple and intuitive native macOS application designed to merge video files seamlessly. Without complex editing software, you can align multiple clips into a single file with unified audio levels and your choice of output resolution.

---

## ✨ Key Features

* **Normalize Audio (Volume Balancing):** When merging multiple clips, it analyzes and adjusts varying audio levels to a consistent, comfortable volume throughout the entire output video.
* **Resolution Scaling:** Set your output size to **1080p FHD** or **4K UHD**. This ensures all combined clips fit the frame size of your target display or TV.
* **Fix Jitter:** Reduces playback stutter and stabilizes video jitter for a smoother viewing experience.
* **Native macOS Integration:**
    * Supports **HEVC (High Compression)** to save space while maintaining quality.
    * Preserves Finder **Color Tags** and metadata during the merge process.
    * Modern Dark Mode interface.

---

## 🚀 How to Use

1. **Add Videos:** Drag and drop your video files into the central dashed area. Use **[Sort by Name]** to organize them or **[Clear All]** to reset the list.
2. **Configure Options:** In the **Options** panel (bottom-right), check **Normalize Audio** to balance the sound and select your desired **Resolution**.
3. **Merge:** Enter a name in the **Output Filename** field and click the blue **[Merge Files]** button.

---

## 🛠️ Requirements

This app uses the **FFmpeg** engine. If you don't have it installed, run the following command in your Terminal:

```bash
brew install ffmpeg
```

---

## 📄 License

This project is licensed under the **MIT License**.

### Acknowledgments
This software uses libraries from the [FFmpeg](https://ffmpeg.org) project under the LGPLv2.1.  
FFmpeg is a trademark of Fabrice Bellard, originator of the FFmpeg project.

---
---

# MP4 Merger (for macOS) - 日本語

**「複数の動画を、一定の音量と指定の解像度でひとつに結合」**

MP4 Mergerは、Macユーザーのために設計された直感的な動画結合ツールです。複雑な編集ソフトを使わずに、バラバラの動画ファイルを、音量バランスの整った一本の動画へとまとめあげます。

---

## ✨ 主な機能

* **音量の自動均一化 (Normalize Audio):** 複数の動画を結合する際、ファイルごとにバラバラな音量を解析し、全体を一定の聞き取りやすいレベルに自動調整します。
* **解像度の指定 (Resolution):** 出力サイズを **1080p FHD** や **4K UHD** に指定可能。視聴するテレビやディスプレイの枠サイズに合わせて動画を書き出せます。
* **映像の安定化補正 (Fix Jitter):** 動画特有の微細なカクつき（ジッター）を抑え、スムーズな再生を実現します。
* **Mac専用設計:**
    * **HEVC (High Compression)** 対応で、画質を維持したままファイル容量を節約。
    * Finderの**カラータグ**などのメタデータも保持したまま結合可能です。

---

## 🚀 使い方

1. **動画を読み込む:** 中央の点線エリアに動画をドラッグ＆ドロップします。 **[Sort by Name]** で名前順に整列させたり、**[Clear All]** でリストをリセットできます。
2. **オプションを選択:** 右下の **Options** パネルで、全体の音量を揃えるなら **Normalize Audio** にチェックを入れ、希望の出力サイズを **Resolution** から選びます。
3. **実行:** **Output Filename** にファイル名を入力し、青い **[Merge Files]** ボタンを押せば結合が始まります。

---

## 🛠️ 事前準備

本アプリは映像処理エンジン **FFmpeg** を利用します。未インストールの場合は、ターミナルで以下のコマンドを実行してください。

```bash
brew install ffmpeg
```

---

## 📄 ライセンス

このプロジェクトは **MITライセンス** のもとで公開されています。

### 謝辞
本ソフトウェアは、LGPLv2.1ライセンスに基づき [FFmpeg](https://ffmpeg.org) プロジェクトのライブラリを使用しています。  
FFmpegは、FFmpegプロジェクトの創設者であるFabrice Bellard氏の商標です。

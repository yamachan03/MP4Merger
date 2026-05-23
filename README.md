# MP4 Merger (for macOS)

**"Combine multiple videos into one, or batch-process them individually with consistent volume, stabilization, and resolution."**

MP4 Merger is a simple and intuitive native macOS application designed to process video files seamlessly. Without complex editing software, you can align multiple clips into a single file or batch-process them one by one, with unified audio levels, gimbal stabilization, and your choice of output resolution. 
*Highly optimized for Apple Silicon (M1/M2/M3) using native VideoToolbox hardware acceleration.*

---

## ✨ Key Features

* **Batch Processing & Merging:** Choose to either seamlessly merge multiple clips into a single file, or process multiple files individually in a batch sequence.
* **Normalize Audio (Volume Balancing):** Analyzes and adjusts varying audio levels to a consistent, comfortable volume.
* **Resolution Scaling:** Set your output size to **1080p FHD** or **4K UHD**. This ensures all clips fit the frame size of your target display.
* **Gimbal Stabilization:** Two-pass stabilization to smooth out camera movements and reduce shaky footage.
* **Fix Jitter:** Reduces playback stutter and stabilizes video jitter for a smoother viewing experience.
* **Native macOS Integration:**
    * Hardware-accelerated processing via **Apple VideoToolbox** for incredibly fast export speeds.
    * Supports **HEVC (High Compression)** to save space while maintaining quality.
    * Modern Dark Mode interface.

---

## 🚀 How to Use

1. **Add Videos:** Drag and drop your video files into the central dashed area. Use **[Sort by Name]** to organize them or **[Clear All]** to reset the list.
2. **Configure Options:** In the **Options** panel, choose to **Merge into single file** or process individually. Check **Normalize Audio**, **Gimbal Stabilization**, or other features, and select your desired **Resolution**.
3. **Run:** Click the blue **[Merge Files]** (or **[Process Files]**) button to begin.

---

## 🛠️ Requirements & Building

This app uses the **FFmpeg** engine. For local development, if you don't have it installed, run the following command in your Terminal:

```bash
brew install ffmpeg
```

**Building the App:**
You can build the standalone app bundle using the provided shell script:
```bash
./build_app.sh
```
This script will compile the Swift code, bundle the local `ffmpeg` binary (if available) inside the app, apply necessary entitlements, and generate `MP4Merger.app`.

---

## 📄 License & Acknowledgments

This project is licensed under the **MIT License**.

### Acknowledgments & FFmpeg License
This software uses code of **[FFmpeg](https://ffmpeg.org/)** licensed under the **LGPLv2.1** (or GPL depending on your build configuration) and its source can be downloaded from the [official FFmpeg website](https://ffmpeg.org/download.html). FFmpeg is a trademark of Fabrice Bellard, originator of the FFmpeg project.

> **Note to Developers / Forkers**: 
> If you distribute a compiled `.app` bundle that includes the `ffmpeg` binary, you must comply with FFmpeg's license. This generally requires preserving copyright notices, distributing this license information, and indicating where the FFmpeg source code can be obtained. Please do not commit the `ffmpeg` binary directly to your Git repository due to GitHub's file size limits.

---
---

# MP4 Merger (for macOS) - 日本語

**「複数の動画を一つに結合、または一括で個別処理。一定の音量、手ブレ補正、指定の解像度で綺麗に書き出し」**

MP4 Mergerは、Macユーザーのために設計された直感的な動画処理ツールです。複雑な編集ソフトを使わずに、バラバラの動画ファイルを一本にまとめたり、複数ファイルに対して手ブレ補正や音量均一化を一括で適用することができます。
*Apple Silicon (M1/M2/M3) の VideoToolbox ハードウェアアクセラレーションに極限まで最適化されています。*

---

## ✨ 主な機能

* **一括処理と結合 (Batch Processing & Merging):** 複数の動画を1つのファイルに結合するか、それぞれのファイルに対して個別に同じ処理を順番に適用するかを選択できます。
* **音量の自動均一化 (Normalize Audio):** ファイルごとにバラバラな音量を解析し、全体を一定の聞き取りやすいレベルに自動調整します。
* **手ブレ補正 (Gimbal Stabilization):** 2パス（2段階）の高度なスタビライズ処理により、手持ち撮影の揺れを滑らかに補正します。補正の強さ（滑らかさ）も自由に指定可能です。
* **解像度の指定 (Resolution):** 出力サイズを **1080p FHD** や **4K UHD** に指定可能。
* **映像のカクつき補正 (Fix Jitter):** 動画特有の微細なカクつき（ジッター）を抑え、スムーズな再生を実現します。
* **Mac専用設計:**
    * **Apple VideoToolbox** によるハードウェアアクセラレーションで、実時間の数倍に及ぶ超爆速エンコードを実現。
    * **HEVC (High Compression)** 対応で、画質を維持したままファイル容量を節約。

---

## 🚀 使い方

1. **動画を読み込む:** 中央の点線エリアに動画をドラッグ＆ドロップします。 **[Sort by Name]** で名前順に整列させたり、**[Clear All]** でリストをリセットできます。
2. **オプションを選択:** 右下の **Options** パネルで、「出力ファイルを一つに結合する」か個別処理かを選びます。必要に応じて **Normalize Audio** や **Gimbal Stabilization** にチェックを入れ、希望の出力サイズを **Resolution** から選びます。
3. **実行:** 青い **[Merge Files]**（または **[処理を開始]**）ボタンを押せば処理が始まります。

---

## 🛠️ 事前準備とビルド

本アプリは映像処理エンジン **FFmpeg** を利用します。ローカルでの開発・実行環境に未インストールの場合は、ターミナルで以下のコマンドを実行してください。

```bash
brew install ffmpeg
```

**アプリのビルド方法:**
同梱されているビルドスクリプトを実行することで、単独で動作するMacアプリを作成できます。
```bash
./build_app.sh
```
これにより、Swiftコードがコンパイルされ、ローカルの `ffmpeg` バイナリがアプリ内に同梱され、必要な署名が行われた `MP4Merger.app` が作成されます。

---

## 📄 ライセンスと謝辞

このプロジェクトは **MITライセンス** のもとで公開されています。

### FFmpegの利用について
本ソフトウェアは、LGPLv2.1（ビルド設定によってはGPL）ライセンスに基づき [FFmpeg](https://ffmpeg.org) プロジェクトのコードを使用しています。ソースコードは公式ウェブサイトから取得可能です。FFmpegは、FFmpegプロジェクトの創設者であるFabrice Bellard氏の商標です。

> **開発者の方へ**:
> アプリ（`.app`）内に `ffmpeg` バイナリを同梱して配布する場合、LGPL/GPLライセンスの条項に従う必要があります（ライセンス表記とソースコード入手元の明記など）。また、ファイルサイズ制限の観点から、`ffmpeg` 本体をそのままGitHub等にコミットしないようご注意ください。

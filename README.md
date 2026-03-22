# MP4 Merger (for macOS)

A simple yet powerful native macOS application that lets you seamlessly merge multiple video files using a drag & drop interface.

## ✨ Key Features
- Seamlessly merge multiple `.mp4` and `.mov` (HEVC) files.
- Merge and preserve native macOS Finder tags (including color tags) to the output file.
- Upscale resolution to `1080p FHD` or `4K UHD`.
- Audio drift (Jitter) correction and audio volume normalization.
- Smart auto-formatting for output filenames.

## 🛠️ Requirements
This application relies on **FFmpeg** under the hood for video processing.
You must have FFmpeg installed on your Mac to use this application.

### How to install FFmpeg (using Homebrew)
Open your Terminal and run the following command:

```bash
brew install ffmpeg
```

## 🚀 Usage

### 1. Add Files
Launch the app and **drag & drop** the `.mp4` or `.mov` files you want to merge into the main window.

### 2. Configure Options *(Optional)*
From the options panel on the right, you can toggle:
- **Resolution**: Upscale to `1080p FHD` or `4K UHD`.
- **Filters**: Enable `Fix Jitter` or `Normalize Audio`.
- **Target Format**: Select `HEVC (High Compression)` to export as a `.mov` file.

### 3. Merge!
Click the **`Merge Files`** button, choose the destination folder, and the fully automated merging process will begin!


## 📄 License
This project is licensed under the [MIT License](LICENSE).

### Acknowledgments
This software uses libraries from the [FFmpeg](https://ffmpeg.org) project under the LGPLv2.1.
FFmpeg is a trademark of Fabrice Bellard, originator of the FFmpeg project.

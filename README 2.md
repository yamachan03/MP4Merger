# MP4 Merger (macOS)

MP4 Merger is a native macOS application designed to quickly merge multiple MP4/MOV videos into a single file, or batch-process them individually. 

It provides an easy-to-use GUI for powerful video processing features, including:
- **Fast Merging**: Seamlessly combine multiple video clips.
- **Resolution Scaling**: Scale videos up to 1080p FHD or 4K UHD.
- **Jitter Fixing**: Apply de-interlacing filters to reduce jitter.
- **Gimbal Stabilization**: Two-pass stabilization for smooth camera movements.
- **HEVC Compression**: Encode outputs in H.265 (HEVC) for smaller file sizes.
- **Audio Normalization**: Balance audio loudness automatically.

## Acknowledgments & Licenses

This software uses code of **[FFmpeg](https://ffmpeg.org/)** licensed under the **LGPLv2.1** (or GPL depending on your build configuration) and its source can be downloaded from the [official FFmpeg website](https://ffmpeg.org/download.html).

> **Note to Developers / Forkers**: 
> If you are distributing a compiled `.app` bundle that includes the `ffmpeg` binary, you must comply with FFmpeg's license (LGPL or GPL). This generally requires preserving copyright notices, distributing this license information, and indicating where the FFmpeg source code can be obtained. Please do not commit the `ffmpeg` binary directly to your Git repository due to GitHub's file size limits and licensing best practices.

## Requirements
- macOS 14.0 or later
- `ffmpeg` binary installed via Homebrew (for local development)

## Building the App
You can build the standalone app bundle using the provided shell script:
```bash
./build_app.sh
```
This script will compile the Swift code, bundle the local `ffmpeg` binary (if available), apply necessary entitlements, and generate `MP4Merger.app` in the current directory.

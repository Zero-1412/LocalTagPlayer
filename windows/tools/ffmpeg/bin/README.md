# Bundled FFmpeg Tools

Put Windows ffmpeg binaries here before building the app:

- ffmpeg.exe
- ffprobe.exe
- any required .dll files from the same FFmpeg distribution

The Windows CMake build copies these files into the app bundle at:

  tools/ffmpeg/bin

At runtime the app checks this bundled path first, then falls back to PATH.
# ImageSquoosher

> [!TIP]
> **日本語版は [README_Japanese.md](README_Japanese.md) を参照してください。**

ImageSquoosher is a desktop app for converting still images to compact JPEG files. It can center-crop, resize, remove metadata, and compress multiple JPEG, PNG, and WebP images with MozJPEG in one pass.

## Installation

ImageSquoosher supports the following systems:

| OS | Architecture |
| --- | --- |
| Windows 10 / 11 | x64 |
| macOS 12 or later | Apple Silicon (arm64) |

1. Open the [Releases page](https://github.com/tsukumijima/ImageSquoosher/releases).
2. Download the ZIP file for your OS.
   - Windows: `ImageSquoosher-vX.Y.Z-windows.zip`
   - macOS: `ImageSquoosher-vX.Y.Z-macos.zip`
3. Extract the ZIP file.

On Windows, keep all files in the extracted folder together and run `ImageSquoosher.exe`. The `mozjpeg` folder and VC++ runtime DLLs next to the app are required.

On macOS, move `ImageSquoosher.app` to the Applications folder and open it. Release builds are signed with a Developer ID certificate and notarized by Apple.

## Supported image formats

| Input | Output | Notes |
| --- | --- | --- |
| JPEG (`.jpg`, `.jpeg`) | JPEG (`.jpg`) | Static images only |
| PNG (`.png`) | JPEG (`.jpg`) | Transparency is composited over white |
| WebP (`.webp`) | JPEG (`.jpg`) | Static images only |

Animated PNG and WebP files are rejected. ImageSquoosher does not silently switch to another encoder when MozJPEG is unavailable.

## Basic usage

1. Drop images into the window or choose **Add images**.
2. Review the output size and filename shown for each image.
3. Adjust the crop ratio, resize axis and pixels, JPEG quality, metadata option, and filename suffix.
4. Choose **Start compression**.
5. Open the completed output from the image row or reveal its folder.

The crop is always centered. You can keep the source aspect ratio, choose a preset ratio, or enter a custom horizontal-to-vertical ratio. Resizing uses the selected width or height while preserving the cropped aspect ratio.

In a small window, scroll through the settings and conversion preview. The image-add and compression buttons stay visible while scrolling.

Click the ratio or resize-axis field to open its options. While the list is open, use the arrow keys and Enter to select an option, or Esc to close the list.

Completed images stay in the list without being compressed again with the same settings. Adding images processes only the new items; changing conversion settings makes images whose source files remain ready to run again. PNG and WebP rows retain their completed results when overwriting has removed the source files.

## Output filenames

The default suffix is `_resized`, so `photo.png` becomes `photo_resized.jpg`. If that output already exists, ImageSquoosher uses Finder-style sequence numbers such as `photo_resized (1).jpg` and `photo_resized (2).jpg`.

An input that already ends in a sequence number keeps the sequence after the suffix. For example, `photo (2).png` becomes `photo_resized (2).jpg`.

## Replacing original images

**Overwrite original files** is an explicit destructive option and is reset to off every time the app starts.

While overwrite is enabled, the suffix field directly below it is disabled. Its value is preserved and becomes available again when overwrite is turned off.

For JPEG input, ImageSquoosher writes the conversion to a separate temporary path, verifies that MozJPEG succeeded and that the result is a valid JPEG with the requested dimensions, then atomically replaces the source file. A failure leaves the source file in place.

For PNG and WebP input, JPEG cannot occupy the same path as the source. ImageSquoosher first selects an unused `.jpg` filename, completes and verifies the JPEG, copies the source timestamps, and only then removes the PNG or WebP source. An existing same-named JPEG is preserved and a numbered output name is used instead.

Creation and modification timestamps are copied from the source on both macOS and Windows. If timestamp preservation fails, the conversion is reported as failed instead of deleting the source.

> [!WARNING]
> Keep overwrite disabled until you have checked the output with representative images. Non-overwrite mode keeps every source image and is the default.

## Finder integration on macOS

The macOS app includes a Finder Sync extension.

1. Choose the Finder integration button beside **Add images** in the upper-right corner of ImageSquoosher.
2. Enable the **ImageSquoosher Finder Sync** extension in macOS System Settings.
3. Select one or more JPEG, PNG, or WebP files in Finder.
4. Control-click the selection and choose **ImageSquoosher で圧縮・リサイズ**.

ImageSquoosher opens with the supported selected files in its conversion queue. The extension adds an item only to the contextual menu for supported image selections.

## Privacy and processing

Image conversion runs locally on your computer. ImageSquoosher invokes the bundled MozJPEG `cjpeg` executable and does not upload source images for conversion.

Metadata is preserved by default. Enable the metadata removal option when you want to omit EXIF information such as camera settings and location data from the JPEG output.

## Development

### Requirements

- Flutter 3.35.7, including Dart 3.9.2
- macOS: Xcode and CMake
- Windows: Visual Studio 2022 with Desktop development with C++, PowerShell, and CMake

Read [AGENTS.md](AGENTS.md) before changing the app. It defines the source-file safety rules, Finder Sync boundary, Debug QA gate, and cross-platform completion criteria.

### Debug workflow

Use a Debug app and hot reload for normal UI development:

```bash
flutter pub get
tools/build_mozjpeg.sh
flutter run -d macos
```

On Windows, prepare MozJPEG with PowerShell before starting the Debug app:

```powershell
flutter pub get
pwsh -File tools/build_mozjpeg.ps1
flutter run -d windows
```

Run the machine checks after editing:

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
```

To exercise the conversion pipeline with a real macOS binary:

```bash
IMAGE_SQUOOSHER_CJPEG="$PWD/native/mozjpeg/macos/arm64/cjpeg" \
  flutter test test/services/image_conversion_pipeline_test.dart
```

Use `native/mozjpeg/windows/cjpeg.exe` for the equivalent PowerShell environment variable on Windows.

### Release builds

The helper scripts download and build MozJPEG 4.1.1 in a temporary directory. They retain only the executable needed by the app under `native/mozjpeg/`.

macOS Apple Silicon:

```bash
tools/build_mozjpeg.sh
flutter build macos --release
tools/bundle_mozjpeg.sh build/macos/Build/Products/Release/ImageSquoosher.app
```

Windows x64:

```powershell
pwsh -File tools/build_mozjpeg.ps1
flutter build windows --release
pwsh -File tools/bundle_mozjpeg.ps1
```

GitHub Actions runs format, analyze, and test first. It then builds macOS arm64 and Windows x64, performs a real conversion with each bundled `cjpeg`, includes the VC++ runtime DLLs in the Windows artifact, and stores both ZIP files.

Tags must use `vX.Y.Z` and match the version in `pubspec.yaml`. A tag release publishes exactly:

- `ImageSquoosher-vX.Y.Z-macos.zip`
- `ImageSquoosher-vX.Y.Z-windows.zip`

The macOS release job requires these GitHub Actions secrets:

| Secret | Purpose |
| --- | --- |
| `MACOS_CODE_SIGNING_ENABLED` | Must be `true` for a tag release |
| `MACOS_CERTIFICATE_P12_BASE64` | Base64-encoded Developer ID Application certificate and private key |
| `MACOS_CERTIFICATE_PASSWORD` | Password used to export the `.p12` file |
| `APPLE_API_KEY_ID` | App Store Connect API key ID |
| `APPLE_API_ISSUER_ID` | App Store Connect issuer ID |
| `APPLE_API_KEY_P8_BASE64` | Base64-encoded App Store Connect `.p8` private key |

The workflow imports signing material into a temporary keychain, signs the nested frameworks, Finder Sync extension, bundled `cjpeg`, and app from the inside out, submits the app to Apple for notarization, staples the ticket, and verifies both the signature and Gatekeeper result.

## License

ImageSquoosher is distributed under the [MIT License](LICENSE). The bundled MozJPEG binary is built from upstream version 4.1.1; its license and attribution files are under [`native/mozjpeg/`](native/mozjpeg/).

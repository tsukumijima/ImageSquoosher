# ImageSquoosher

<!-- Main Screenshot -->
<img width="49%" alt="ImageSquoosher Main Screen (Light Mode)" src="https://github.com/user-attachments/assets/b8e29d08-efd1-468f-a3f4-09690e138785" />
<img width="49%" alt="ImageSquoosher Main Screen (Dark Mode)" src="https://github.com/user-attachments/assets/8f830f64-1f3f-41cf-ba00-64e61b933d61" /><br />

> [!TIP]  
> **🇯🇵 日本語版 README はこちら: [Readme.md](Readme.md)**

**A lightweight desktop utility that lets you select one or more photos or images in Explorer or Finder, open them directly from the right-click context menu, and batch compress, change aspect ratio (crop), and resize in one swift pass.**

Featuring the high-quality, high-compression JPEG encoder **[MozJPEG](https://github.com/mozilla/mozjpeg)** (also used by [Squoosh](https://squoosh.app/)) alongside the clarity-preserving **Lanczos3** resampling algorithm, it enables you to **convert images into ultra-compact JPEGs stripped down to the bare minimum file size while keeping visual quality and sharpness intact.**  
**Supports both Windows 11 and macOS.**

> [!NOTE]  
> **This app was built to prepare images you handle every day—for embedding in websites and documentation, uploading to Discord or Notion, using as reference materials for generative AI, and more—into an easy-to-use format with the fewest possible steps, right from the Explorer or Finder right-click menu.**  
> 
> There is no longer any need to open an online compression tool in your browser, drag and drop files one by one, or click [Show more options] on Windows 11 to dig up legacy context menu tools whenever you need to do this.

## Background

When embedding images in websites, blog posts, or technical documentation, or uploading images and screenshots to Notion or Discord, you frequently run into file size and resolution limitations:

- **Encountering unfriendly web services that require you to manually crop and resize your avatar to 1:1 under a few hundred pixels because they lack an in-app avatar cropping tool**
- **Notion's free plan has a 5MB per file upload limit**
- **Discord's free tier also imposes upload file size restrictions**
- **Wanting to feed high-resolution camera photos or PC screenshots to video generation AI as reference inputs, but getting rejected because the files are massive**
- **Needing to batch-standardize the resolution and aspect ratio of assorted images with mismatched dimensions for web design or reference material assets**

Photos taken with digital mirrorless/DSLR cameras, recent high-megapixel smartphone cameras, or high-resolution PC screenshots routinely exceed several megabytes to well over 10MB.  
Needing to quickly resize them to drop the file size is an all-too-common occurrence.

As an image compression tool, Google's web app [Squoosh](https://squoosh.app/) is well-known in some circles with exquisite compression quality (though its active development appears to have ended...).  
I personally found it handy from time to time, but when doing daily work, **the round-trip routine of "opening the browser, dragging and dropping images one by one, checking parameters, and downloading" became a huge hassle when dealing with multiple images.**

On Windows, using the "Image Resizer" tool in Microsoft's official [PowerToys](https://github.com/microsoft/PowerToys) makes resizing itself fairly easy right from the context menu.  
However, there were several hurdles:

1. **On macOS, there were no handy tools for right-click batch processing**:  
   Looking around, macOS had no lightweight tool that could be cleanly launched from the Finder context menu to resize images in batch.
2. **Even on Windows, if I'm resizing images, I want to squeeze them down cleanly using MozJPEG**:  
   Tools like PowerToys Image Resizer use standard encoders and lack advanced compression methods like MozJPEG.  
   Even while maintaining the same resolution, MozJPEG can strip away far more bytes.
3. **I switch between macOS and Windows daily**:  
   I use macOS as my primary daily driver, but I import DSLR/mirrorless camera photos on a Windows machine, do video editing on Windows, and frequently bounce between both OSes.  
   That's why I wanted a tool that works with the exact same feel from the right-click menu on either platform.
4. **Wanting to quickly align mismatched aspect ratios centered without black bars**:  
   For video thumbnails (16:9), article OGP cards (1.91:1), SNS avatars (1:1), desktop wallpapers, etc., there are often times when you just want to crop off the top/bottom or left/right based on the center to match an aspect ratio.  
   Doing this by opening a separate image editor and cropping images one by one is way too tedious.

"I want a tool that launches instantly from the familiar Explorer or Finder context menu when I select files, lets me check everything in a modern UI, and outputs top-quality, lightweight JPEGs with a single click."  
Driven by that idea, I developed **ImageSquoosher** as an individual project.

Drawing upon the success and lessons learned from [α Import Utility](https://github.com/tsukumijima/Alpha-Import-Utility)—a utility I vibecoded back in January with Opus 4.5 to automatically and reliably import only un-imported photos/videos from Sony α cameras—I once again chose **Flutter Desktop**.  
By sharing the core logic (Dart) and UI design across Windows and macOS, it delivers the exact same user experience on both platforms.

As for the tricky native OS integration code—like Windows Explorer integration (packaged COM with loose package registration) and macOS Finder integration (Finder Sync Extension)—**I left it entirely to GPT-6 Astra to write.**  
I haven't dug into the fine implementation details, but it worked smoothly right out of the box with zero issues, so it should be all good...!  
While ~~offloading the implementation to Astra~~, **for the UI design and overall usability, I crafted the details meticulously despite its simplicity, making sure it scratches every subtle itch in daily workflows.**

## Motivation

ImageSquoosher is designed to drastically streamline the workflow of creators, engineers, and bloggers who work with images daily.

### What I Wanted to Achieve

- **Open in a single right-click from Explorer or Finder**:  
  - Simply select multiple images, right-click, and ImageSquoosher launches immediately with your selection queued up.  
  - **On Windows 11, it appears directly in the primary context menu, not hidden inside [Show more options].**
  - **On macOS, the Finder Sync extension puts it right in the Finder context menu.**
- **Best-in-class compression ratio and visual fidelity with MozJPEG**:  
  - Bundles MozJPEG (used by Google's [Squoosh](https://squoosh.app/)) directly inside the app. No need to build or install anything extra.  
  - Since there are virtually no usable standalone GUI frontends for MozJPEG out there besides Squoosh, the goal was to provide the definitive GUI experience for it.  
  - **Compared to standard JPEG encoders, it can slash file sizes by up to nearly 50% depending on quality settings while maintaining identical visual quality.**
- **Deliberately focused on versatile JPEG for simplicity**:  
  - While WebP and AVIF are great formats in terms of raw compression, they often lack full support across image editors, viewers, and web services.  
  - **At the end of the day, JPEG displays reliably everywhere and offers the best all-around versatility. The goal was to make those universally compatible JPEG files as compact as possible while retaining quality.**  
  - Since WebP and AVIF are rarely needed in my own workflow, the output format is deliberately fixed to MozJPEG (JPEG) to keep the app and features clean and focused.
- **Batch-standardize mismatched resolutions and aspect ratios without black bars**:  
  - **Add a mixed collection of landscape, portrait, and square images, and batch-unify them into identical resolutions with specified aspect ratios like 16:9, 1:1, or OGP's 1.91:1 via crop & resize.**  
  - Uses the Lanczos3 filter for resizing, ensuring smooth and sharp scaling while preserving crisp details.  
    - Checking [Allow upscaling small images] will stretch images smaller than the target width while resizing larger ones appropriately, standardizing the dimensions and aspect ratios of all selected files at once. Incredibly handy when you need it!  
  - Aspect ratio adjustments apply a "Fit" crop, trimming the top/bottom or left/right anchored to the center to fit the chosen ratio.
- **Handy EXIF (location & camera metadata) stripping**:  
  - While major social networks often strip EXIF automatically on upload, when embedding images in blogs, website assets, or shared folders, having embedded GPS coordinates or camera gear info can cause privacy concerns.  
  - To solve this, **you can effortlessly strip EXIF metadata alongside resizing and compression.**
- **Handy preservation of filesystem timestamps (Created/Modified dates) from source images**:  
  - You've probably experienced this: **after resizing source images, whether you sort by name or modification date in Explorer or Finder, don't you want the resized images and original images to sit right next to each other?! (Especially in messy, unorganized folders...)**  
    - Using web-based tools like Squoosh requires moving files from the Downloads folder, and files end up with the current timestamp, creating annoying workflow friction.  
    - **ImageSquoosher preserves the original creation and modification dates onto the newly resized files to achieve this seamless organization.**
- **Failsafe design to prevent accidental overwriting of valuable source images**:  
  - Accidentally overwriting an original image is something you never want to happen. **The overwrite option is always reset to OFF every time the app launches, ensuring images are safely saved under distinct names unless explicitly checked.**  
  - Even when overwrite is enabled, it is designed to write to a temporary file first, verify MozJPEG's exit code, validate the JPEG structure, confirm requested dimensions, copy timestamps, and only then atomically replace the file.
- **Flutter Desktop: matching cross-platform UX with snappy, lightweight performance**:  
  - Nowadays, people often build cross-platform desktop apps with Electron because native PC development is tedious, or at best Tauri (which still uses browser WebViews and consumes notable memory). But since the UI is essentially a browser, heavy resource usage and large install footprints are unavoidable.  
  - In that regard, for single-window desktop utilities (where complex multi-page apps aren't needed), Flutter Desktop offers massive benefits: **cross-platform support, beautiful out-of-the-box Material Design UI controls with high design freedom for unified look across OSes, and significantly faster launch times with install sizes kept within a few dozen megabytes compared to Electron or WebView-based apps.**  
    - The downside is having to write Dart—a language rarely used outside of Flutter—but since it's built with LLMs anyway, having a modern language with first-class linter support that is LLM-friendly makes it far easier to build high-quality software than using Qt, GTK, or Xamarin in this day and age.

### Specialized for "Center-Crop & Aspect Ratio Adjustment Without Needing Fine Composition Adjustments"

If you need to fine-tune crop positions or pixel-level framing, you should use standard editing software or Photoshop. That is not ImageSquoosher's primary use case.  
- Making a desktop wallpaper  
- Framing 16:9 for YouTube or video thumbnails  
- Cropping a favorite image to 1:1 for a website account avatar  
- Cropping to 1.91:1 for article OGP cards  
- Sizing images to submit as reference inputs for video generation AI / APIs (e.g., APIs like MiniMax H3 Max where higher reference resolutions increase billing costs)  

...This tool exists to solve the subtle yet frequent real-world need: **"Just anchor it to the center and batch-unify the aspect ratio and resolution in the fewest possible steps."**

### Reliable Failsafe Design

**ImageSquoosher is designed with top priority on "erring on the side of safety so nothing goes wrong even when running on autopilot" and "quick, frictionless operation and conversion."**

- **Source images are preserved by default**:  
  - Saves files under a new name with the `_resized` suffix by default, fundamentally preventing the tragic accident of overwriting original assets.
- **No silent overwriting of duplicate filenames**:  
  - If a file with the same name already exists in the destination, Finder/Explorer-style sequence numbers like `DSC01234_resized (1).jpg` and `DSC01234_resized (2).jpg` are automatically assigned.
- **Overwriting only occurs after strict verification**:  
  - Even if [Overwrite original files] is explicitly enabled, source files are never touched until all processing completes and valid conversion is verified.
- **No dangerous settings persist across restarts**:  
  - The [Overwrite original files] checkbox always resets to off upon launching the app.

## Features

### ⚡ Instant Launch from Explorer and Finder Context Menus

<!-- Screenshots: Windows 11 Context Menu & macOS Finder Menu -->
<img width="49%" alt="ImageSquoosher shown directly in the Windows 11 context menu" src="https://github.com/user-attachments/assets/5a022ec6-4f60-4330-b2dc-356faf3093ee" />
<img width="49%" alt="ImageSquoosher shown directly in the macOS context menu" src="https://github.com/user-attachments/assets/29b0617a-d3f6-4235-b60d-155f64634850" /><br /><br />

Whether in Windows 11 Explorer or macOS Finder, simply select image files and right-click to launch the app instantly with your selection loaded into the conversion queue.

On Windows 11, [ImageSquoosher] appears directly at the top level of the primary right-click menu without having to open [Show more options].  
On macOS, it appears directly inside the Finder contextual menu as [ImageSquoosher で圧縮・リサイズ].

> [!TIP]
> **Select multiple files and launch from the context menu to add all selected images to the queue in a single batch!**  
> You can also drag and drop image files into an already running ImageSquoosher window.

### 🗜️ High Compression and Visual Quality Powered by MozJPEG

<!-- Screenshot: File size comparison before and after compression -->
<img width="380" alt="File size reduction results with MozJPEG" src="https://github.com/user-attachments/assets/8f830f64-1f3f-41cf-ba00-64e61b933d61" /><br />

JPEG output directly utilizes the battle-tested MozJPEG (v4.1.1) `cjpeg` binary.

MozJPEG's proprietary optimizations—including trellis quantization—drastically reduce file sizes while maintaining indistinguishable visual quality compared to standard JPEG encoders.  
The quality slider (default: 90) lets you easily dial in the optimal balance for your needs.

### 📐 Batch Unify Mismatched Images Without Black Bars · Lanczos3 Resizing

<!-- Screenshot: Conversion settings panel -->
<img width="380" alt="Conversion settings panel (aspect ratio, quality, resize, suffix)" src="https://github.com/user-attachments/assets/3171fe30-67f1-4602-9b62-498e87465467" /><br />

Even for collections of images with completely different resolutions and aspect ratios, you can unify them centered without adding letterbox black bars by cropping off excess top/bottom or left/right margins.  
The scaling algorithm adopts the high-quality **Lanczos3 (3rd-order Lanczos filter)**, keeping downscaled text and fine details crisp and readable.  
Fine details in screenshots remain clear and sharp.

Presets include "Original aspect ratio (default)", 16:9 (video thumbnails, blogs, etc.), 1.91:1 (OGP cards), 1:1 (square avatars), 4:3, and 3:2.

> [!TIP]
> A safety guard against upscaling beyond the source resolution is enabled by default.  
> To disable it and allow enlargement, check [Allow upscaling small images].

### 🎨 Modern UI That Scratches Every Itch

<!-- Screenshot: Image list and progress display -->
<img width="380" alt="Image list and progress display" src="https://github.com/user-attachments/assets/8e4157dc-bc35-4b4f-a2a5-ab9c3a3e92d3" /><br />

Features a clean interface crafted with deep attention to everyday ergonomics:

- **Cropped Thumbnail Preview**: When you change the aspect ratio, thumbnails immediately update to reflect the actual center-cropped framing.
- **At-a-Glance Conversion Info**: Input/output filenames, before/after resolutions, original vs. compressed file sizes, and reduction percentage (%) are clearly displayed on each image card.
- **Remove Accidental Items**: Individual remove buttons [×] allow you to exclude accidental additions, with [Clear all] available for a clean slate.
- **One-Click Output Access**: Double-click any row to view the source file in your default viewer. Once converted, jump directly to the destination via [Open file] or [Show in Finder] (or [Open folder] on Windows).

### 🕵️‍♂️ Handy EXIF Stripping for Privacy

Photos taken with smartphones or digital cameras often contain metadata including not just shooting dates, but GPS latitude/longitude coordinates and camera model information.

When uploading images to asset libraries, personal blogs, or public websites, checking **[Strip metadata]** in the settings panel cleanly removes EXIF data in tandem with resizing and compression.

### 🛡️ Complete Data Safety and Timestamp Preservation

To prevent accidents where original images are unintentionally overwritten, **the [Overwrite original files] option always resets to OFF every time the app launches.**  
Even when overwrite is enabled, **it writes to a separate temporary file and only replaces the original atomically after verifying MozJPEG's exit code, JPEG signature, and requested dimensions, completely eliminating the risk of ending up with corrupt files.**

Converted files inherit the exact creation and modification timestamps of the source image (`URLResourceValues` on macOS, Win32 API on Windows).  
When overwriting PNG or WebP files, an unused JPEG filename is secured first; the source file is deleted only after successful generation and verification, ensuring existing same-named JPEGs are never destroyed.

### 🔒 100% Local Processing & Privacy Protection

**All image processing runs entirely on your local machine.**  
No images are ever uploaded to external servers or transmitted across the network, ensuring complete confidentiality for sensitive documents, proprietary screenshots, and private photos.

## Supported Environments

| OS | Architecture | Notes |
| --- | --- | --- |
| Windows 11 | x64 | Supports launching from right-click context menu |
| macOS 12 or later | Apple Silicon (arm64) | Supports launching from right-click context menu (Finder Sync extension) |

## Supported Image Formats

| Input Format | Output Format | Processing |
| --- | --- | --- |
| JPEG (`.jpg`, `.jpeg`) | JPEG (`.jpg`) | Static images only |
| PNG (`.png`) | JPEG (`.jpg`) | Transparency automatically composited over white |
| WebP (`.webp`) | JPEG (`.jpg`) | Static images only |

> [!IMPORTANT]
> APNG (Animated PNG) and Animated WebP are not supported.  
> HEIC / HEIF support may be added in the future, but is currently shelved because the underlying image decoding library lacks HEIC / HEIF decoding capability...

## Installation and Setup

### Download

1. Open the [Releases page](https://github.com/tsukumijima/ImageSquoosher/releases).
2. Download the ZIP file for your operating system:
   - Windows: `ImageSquoosher-vX.Y.Z-windows.zip`
   - macOS: `ImageSquoosher-vX.Y.Z-macos.zip`
3. Extract the downloaded ZIP file.

### Windows Setup & Context Menu Registration

1. Place the extracted folder in any directory of your choice.  
   The `mozjpeg` folder and VC++ runtime DLLs located next to `ImageSquoosher.exe` are required for operation, so keep the folder contents intact.
2. Double-click `ImageSquoosher.exe` to launch.
3. **Click the puzzle button [Add to the Explorer context menu] in the top-right corner.**  
   Approve the Windows User Account Control (UAC) prompt when it appears.
4. Registration is complete! When you select images in Explorer and right-click, **[ImageSquoosher] will appear directly in the first menu.**

> [!TIP]  
> - **Portable yet integrated**: ImageSquoosher is an installer-free portable app, yet adds itself directly to the modern Windows 11 context menu.  
>   - Under the hood, it uses [Loose Package Registration](https://learn.microsoft.com/en-us/windows/apps/develop/testing/loose-file-registration). This seemed fairly involved, but I dumped the detailed implementation onto Astra-kun, so I have no idea how it works under the hood! Huge thanks to Astra for building it properly...
> - **Moving the folder**: If you move the app folder to a new location, the top-right button changes to [Repair Explorer integration]. Click it to repair.
> - **Removing integration**: Simply click [Remove from the Explorer context menu] in the top-right corner anytime to cleanly remove the context menu entry.

### macOS Setup & Enabling Finder Integration

1. Move the extracted `ImageSquoosher.app` to your Applications folder.
2. Launch `ImageSquoosher.app`.
3. **Click the puzzle-shaped Finder integration button in the top-right corner.**  
   This opens the macOS System Settings Extensions pane.
4. Enable the **ImageSquoosher Finder Sync** extension.
5. Setup is complete! When you select images in Finder and right-click, **[ImageSquoosher で圧縮・リサイズ] will appear in the contextual menu.**

## Basic Usage

1. **Add Images**:  
   Select images in Explorer or Finder and open via the right-click menu, or drag and drop image files directly into the window. You can also click the [Add images] button in the header.
2. **Adjust Conversion Settings**:  
   Tune conversion parameters in the left settings panel as needed:
   - **Quality**: Specify JPEG quality from 1 to 100 (default: 90).
   - **Aspect Ratio**: Choose center-crop ratio. "Original" preserves source proportions, or pick from presets like 16:9, 1.91:1 (OGP), 1:1 (square), 4:3, 3:2, etc.
   - **Resize**: Scale to specified pixel width or height.
   - **Strip Metadata**: Enable to omit GPS coordinates and camera EXIF information.
   - **Suffix**: Suffix appended to output filenames (default: `_resized`).
3. **Start Conversion**:  
   Click the [Convert] button at the bottom. Images are processed sequentially, with progress bars and reduction percentages updating in real time.
4. **Inspect Output Files**:  
   Once finished, click [Open file] on any card to view the result, or click [Show in Finder] (or [Open folder] on Windows) to reveal the output directory.

### Output Filename Rules

- By default, files are saved as `{OriginalName}{Suffix}.jpg`.  
  Example: `photo.png` → `photo_resized.jpg`
- If an output file with the same name already exists, sequence numbers are appended to avoid overwriting:  
  Example: `photo_resized (1).jpg`, `photo_resized (2).jpg`
- If the original input filename already ends with a sequence number, it carries over after the suffix:  
  Example: `photo (2).png` → `photo_resized (2).jpg`

### Overwriting Original Files

Enabling [Overwrite original files] replaces original images with converted JPEGs.

> [!WARNING]  
> **Overwriting original files is an irreversible operation. Always test results with representative images beforehand.**  
> Overwrite is disabled by default and always resets to OFF upon restarting the application.

- **Overwriting JPEG Images**: Written to a temporary file first; only atomically replaces the original after confirming MozJPEG exit code, JPEG validity, and target dimensions. Source files remain intact if errors occur.
- **Overwriting PNG / WebP Images**: Secures an unused JPEG filename, validates the output, copies creation/modification timestamps, and only then deletes the source file. Existing same-named JPEGs are never destroyed.

## Technical Highlights

### Why MozJPEG?

Most standard image converters use generic libjpeg or OS-provided encoders for lightweight implementation.  
However, these encoders lack optimizations for perceptual redundancy; lowering quality settings quickly introduces noticeable block noise and color bleeding.

[MozJPEG](https://github.com/mozilla/mozjpeg) is an advanced open-source JPEG encoder developed by Mozilla.  
By automatically tuning quantization tables to human visual perception and performing exhaustive data reduction via trellis quantization, it achieves **dramatic file size reductions while preserving visual beauty.**  
ImageSquoosher bundles native MozJPEG 4.1.1 `cjpeg` binaries precompiled for each platform, invoking them directly from the conversion core without system path dependencies.

> [!NOTE]
> I originally learned about MozJPEG because Squoosh used it behind the scenes. Looking into it recently, Google has released a newer encoder called Jpegli, which appears to offer even better compression, so I might consider switching to it in the future...

### Why Lanczos3 Resizing?

Downscaling images using simple Nearest Neighbor or Bilinear interpolation causes blurred typography and severe moiré patterns on fine lines.  
ImageSquoosher employs the high-grade **Lanczos3 (3rd-order Lanczos filter)** sampling filter.

> [!NOTE]
> It's the algorithm listed under GIMP's resize tool options. Squoosh's resize logic should be using roughly the same algorithm (and I had Astra port the implementation from there).  
> Fine text in screenshots remains crisp and legible, while high-resolution photos maintain razor-sharp definition even when scaled down.

### Direct Registration to the Windows 11 Modern Context Menu

Windows 11 redesigned the context menu, burying legacy shell extensions under [Show more options].  
Adding items to the modern top-level menu typically demands MSIX packaging and code signing certificates.

ImageSquoosher maintains the convenience of an installer-free portable ZIP distribution while integrating directly into Windows 11's modern menu.

The bundled helper executable (`ImageSquoosherShellRegistration.exe`) registers `AppxManifest.xml` within the extracted directory as a Loose Package for the current user.  
Only the Developer Mode toggle required during registration is temporarily elevated via a UAC helper, immediately reverting to its original state once registration finishes.  
This delivers native Windows 11 ergonomics from a completely portable utility.

> [!IMPORTANT]  
> Because my development PC always has Developer Mode enabled, I haven't tested extensively on machines where Developer Mode is turned off; it might run into issues on those machines.  
> In that case, manually turning on Developer Mode in Windows 11 Settings should allow registration without issues.

## Development

### Requirements

- Flutter 3.35.7, including Dart 3.9.2
- macOS: Xcode, CMake
- Windows: Visual Studio 2022 (with "Desktop development with C++"), PowerShell, CMake

### Debug Workflow

Use a Debug build and hot reload for regular UI development:

Windows:

```powershell
flutter pub get
pwsh -File tools/build_mozjpeg.ps1
flutter run -d windows
```

macOS:

```bash
flutter pub get
tools/build_mozjpeg.sh
flutter run -d macos
```

### Tests and Static Analysis

Run formatters, linters, and unit tests after code modifications:

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
```

Running real binary conversion tests with MozJPEG:

Windows:

```powershell
$env:IMAGE_SQUOOSHER_CJPEG = "$PWD\native\mozjpeg\windows\cjpeg.exe"
flutter test test/services/image_conversion_pipeline_test.dart
```

macOS:

```bash
IMAGE_SQUOOSHER_CJPEG="$PWD/native/mozjpeg/macos/arm64/cjpeg" \
  flutter test test/services/image_conversion_pipeline_test.dart
```

### Release Builds

Windows (x64):

```powershell
pwsh -File tools/build_mozjpeg.ps1
flutter build windows --release
pwsh -File tools/bundle_mozjpeg.ps1
```

macOS (Apple Silicon):

```bash
tools/build_mozjpeg.sh
flutter build macos --release
tools/bundle_mozjpeg.sh build/macos/Build/Products/Release/ImageSquoosher.app
```

## License

[MIT License](License.txt)

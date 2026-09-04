import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:image/image.dart' as image;

import '../models/conversion_settings.dart';
import '../models/image_dimensions.dart';
import '../utils/lanczos_resizer.dart';
import 'image_metadata.dart';
import 'image_mozjpeg_encoder.dart';
import 'image_pipeline_types.dart';

/// JPEG・PNG・WebP の静止画を MozJPEG へ変換する一連の処理です。
///
/// デコード後の画素処理は Dart の [Isolate] で完結し、ネイティブ実行は最後の `cjpeg` だけです。
/// 入力をすべて読んで検証してから出力用の一時ディレクトリを使い、検証済みの出力だけを公開します。
class ImageConversionPipeline {
  /// 置換失敗時も元画像を残す処理を検査できるよう、ステージ済み出力の確定処理を差し替えられます。
  ImageConversionPipeline({Future<void> Function(File stagedOutput, File outputFile)? replaceStagedOutput})
    : _replaceStagedOutput = replaceStagedOutput;

  static const _fileOperationsChannel = MethodChannel(
    'net.tsukumijima.image-squoosher/finder_sync',
  );

  final Future<void> Function(File stagedOutput, File outputFile)? _replaceStagedOutput;

  /// 1枚を JPEG へ変換します。
  Future<ImageConversionResult> convert(ImageConversionRequest request) async {
    final inputPath = request.inputFile.path;
    final settings = request.settings;
    final prepared = await Isolate.run(
      () => _prepareImage(inputPath, settings),
    );
    final sourceFormat = prepared.sourceFormat;
    final plan = prepared.plan;
    if (request.settings.overwrite &&
        sourceFormat != SourceImageFormat.jpeg &&
        request.inputFile.absolute.path == request.outputFile.absolute.path) {
      throw ArgumentError.value(
        request.outputFile.path,
        'outputFile',
        'PNG and WebP overwrite outputs must use a separate JPEG path.',
      );
    }
    late final Uint8List rgbBytes;
    final directRgbBytes = prepared.directRgbBytes;
    if (directRgbBytes != null) {
      // 全領域を同じ寸法で出力する場合は、8bit RGB をそのまま PPM 入力に使う
      rgbBytes = directRgbBytes;
    } else {
      final crop = prepared.crop!;
      final resized = crop.width == plan.output.width && crop.height == plan.output.height
          ? crop
          : await LanczosResizer.resizeInIsolate(
              crop,
              width: plan.output.width,
              height: plan.output.height,
            );
      rgbBytes = resized.toSrgbBytes();
    }

    final sourceStat = await request.inputFile.stat();
    final outputParent = request.outputFile.parent;
    await outputParent.create(recursive: true);
    final temporaryDirectory = await outputParent.createTemp('.image-squoosher-');

    try {
      final stagedOutput = File(
        '${temporaryDirectory.path}${Platform.pathSeparator}converted.jpg',
      );
      await MozJpegEncoder(request.cjpegExecutable).encode(
        width: plan.output.width,
        height: plan.output.height,
        rgbBytes: rgbBytes,
        quality: request.settings.quality,
        outputFile: stagedOutput,
        temporaryDirectory: temporaryDirectory,
        iccProfileBytes: prepared.iccProfileBytes,
      );

      // cjpeg の JPEG を一度デコードし、検証済みの出力だけを公開する
      var outputBytes = await stagedOutput.readAsBytes();
      if (request.settings.stripMetadata == false && prepared.metadataSegments.isNotEmpty) {
        outputBytes = ImageMetadataTransfer.inject(outputBytes, prepared.metadataSegments);
        await stagedOutput.writeAsBytes(outputBytes, flush: true);
      }
      _verifyJpeg(outputBytes, plan.output.width, plan.output.height);

      final finalizeStagedOutput = request.finalizeStagedOutput;
      if (finalizeStagedOutput == null) {
        await stagedOutput.setLastModified(sourceStat.modified);
      } else {
        await finalizeStagedOutput(request.inputFile, stagedOutput);
      }
      final replaceStagedOutput = _replaceStagedOutput;
      final isOverwritingJpegInput =
          request.settings.overwrite &&
          sourceFormat == SourceImageFormat.jpeg &&
          request.inputFile.absolute.path == request.outputFile.absolute.path;
      if (isOverwritingJpegInput) {
        if (replaceStagedOutput != null) {
          await replaceStagedOutput(stagedOutput, request.outputFile);
        } else if (Platform.isWindows) {
          // 明示的な JPEG 上書きだけを既存ファイルの置換 API で公開する
          await _replaceStagedOutputOnWindows(stagedOutput, request.outputFile);
        } else {
          await _renameAtomically(stagedOutput, request.outputFile);
        }
      } else {
        await _publishNewOutputExclusively(
          stagedOutput,
          request.outputFile,
          replaceStagedOutput: replaceStagedOutput,
        );
      }
    } finally {
      // 一時出力を公開前の作業ディレクトリへ限定し、変換完了後に片付ける
      if (await temporaryDirectory.exists()) {
        await temporaryDirectory.delete(recursive: true);
      }
    }

    return ImageConversionResult(
      inputFile: request.inputFile,
      outputFile: request.outputFile,
      sourceFormat: sourceFormat,
      sourceWidth: prepared.sourceWidth,
      sourceHeight: prepared.sourceHeight,
      cropRect: plan.crop,
      outputWidth: plan.output.width,
      outputHeight: plan.output.height,
    );
  }

  /// デコード、向き補正、中央クロップをワーカー [Isolate] でまとめて実行します。
  static Future<_PreparedImage> _prepareImage(String inputPath, ConversionSettings settings) async {
    final inputBytes = await File(inputPath).readAsBytes();
    final decoder = image.findDecoderForData(inputBytes);
    if (decoder == null) {
      throw const UnsupportedImageException('The input is not a supported image.');
    }
    final sourceFormat = _sourceFormatFor(decoder.format);
    // PNG/WebP の上書きは別名 JPEG を完成させてから元入力を削除するため、別の出力先を使う
    final decodeInfo = decoder.startDecode(inputBytes);
    if (decodeInfo == null) {
      throw const UnsupportedImageException('The input image could not be decoded.');
    }
    // 静止 WebP はデコーダー実装上フレーム数を 0 と報告する場合があるため、複数フレームだけを拒否して静止画像を変換対象にする
    if (decoder.numFrames() > 1 || decodeInfo.numFrames > 1) {
      throw const UnsupportedImageException('Animated images cannot be converted.');
    }

    // Orientation を先に画素へ反映すると、クロップ比率と JPEG の向きが一致する
    final decoded = decoder.decode(inputBytes, frame: 0);
    if (decoded == null || decoded.width <= 0 || decoded.height <= 0) {
      throw const UnsupportedImageException('The input image contains no pixel data.');
    }
    final oriented = image.bakeOrientation(decoded);
    final plan = settings.plan(
      ImageDimensions(oriented.width, oriented.height),
    );
    final metadataSegments = settings.stripMetadata
        ? const <JpegMetadataSegment>[]
        : ImageMetadataTransfer.collect(inputBytes, sourceFormat);
    final isDirectRgb =
        plan.crop.left == 0 &&
        plan.crop.top == 0 &&
        plan.crop.width == oriented.width &&
        plan.crop.height == oriented.height &&
        plan.output.width == oriented.width &&
        plan.output.height == oriented.height;
    return _PreparedImage(
      sourceFormat: sourceFormat,
      sourceWidth: oriented.width,
      sourceHeight: oriented.height,
      plan: plan,
      crop: isDirectRgb ? null : _copyCropAsWhiteLinearRgb(oriented, plan.crop),
      directRgbBytes: isDirectRgb ? _copyAsWhiteSrgbBytes(oriented) : null,
      metadataSegments: metadataSegments,
      iccProfileBytes: oriented.iccProfile?.clone().decompressed(),
    );
  }

  /// [source] 全体を白背景の 8bit sRGB 配列へ変換します。
  static Uint8List _copyAsWhiteSrgbBytes(image.Image source) {
    if (source.isLdrFormat && source.hasPalette == false && source.numChannels == 3) {
      // 8bit RGB はコピーも色変換も不要なため、デコーダーの画素列を PPM へそのまま渡す
      return source.getBytes(order: image.ChannelOrder.rgb);
    }

    final rgbBytes = Uint8List(source.width * source.height * 3);
    var offset = 0;
    for (final pixel in source) {
      final alpha = pixel.aNormalized.toDouble().clamp(0.0, 1.0);
      if (alpha == 1.0) {
        // 不透明画素は元の sRGB 値を維持し、JPEG 圧縮前の色を保つ
        rgbBytes[offset] = (pixel.rNormalized * 255).round().clamp(0, 255).toInt();
        rgbBytes[offset + 1] = (pixel.gNormalized * 255).round().clamp(0, 255).toInt();
        rgbBytes[offset + 2] = (pixel.bNormalized * 255).round().clamp(0, 255).toInt();
      } else if (alpha == 0.0) {
        // 完全透明な画素は元の RGB 値にかかわらず白背景として出力する
        rgbBytes[offset] = 255;
        rgbBytes[offset + 1] = 255;
        rgbBytes[offset + 2] = 255;
      } else {
        // 半透明画素はリサイズ経路と同じ線形 RGB の白合成で明るさを保つ
        rgbBytes[offset] = SrgbColorSpace.toByte(
          SrgbColorSpace.toLinear(pixel.rNormalized.toDouble()) * alpha + (1.0 - alpha),
        );
        rgbBytes[offset + 1] = SrgbColorSpace.toByte(
          SrgbColorSpace.toLinear(pixel.gNormalized.toDouble()) * alpha + (1.0 - alpha),
        );
        rgbBytes[offset + 2] = SrgbColorSpace.toByte(
          SrgbColorSpace.toLinear(pixel.bNormalized.toDouble()) * alpha + (1.0 - alpha),
        );
      }
      offset += 3;
    }
    return rgbBytes;
  }

  /// [requests] を選択順に変換し、個別失敗は記録して次の画像へ進みます。
  ///
  /// 大きな画像を並列に展開するとメモリ使用量が急増するため、変換開始順と出力更新順をそろえた逐次処理にします。
  Future<ImageBatchConversionResult> convertSequentially(
    Iterable<ImageConversionRequest> requests, {
    ImageConversionStopToken? stopToken,
  }) async {
    final completed = <ImageConversionResult>[];
    final failures = <ImageConversionFailure>[];

    for (final request in requests) {
      if (stopToken?.isRequested ?? false) {
        return ImageBatchConversionResult(
          completed: completed,
          failures: failures,
          wasStopped: true,
        );
      }
      try {
        completed.add(await convert(request));
      } catch (error, stackTrace) {
        failures.add(
          ImageConversionFailure(
            inputFile: request.inputFile,
            error: error,
            stackTrace: stackTrace,
          ),
        );
      }
    }
    return ImageBatchConversionResult(
      completed: completed,
      failures: failures,
      wasStopped: false,
    );
  }

  /// [source] の [cropRect] を白背景の線形 RGB 配列へ変換します。
  static LanczosLinearRgbImage _copyCropAsWhiteLinearRgb(
    image.Image source,
    CropRect cropRect,
  ) {
    final linearRgb = Float32List(cropRect.width * cropRect.height * 3);
    for (var y = 0; y < cropRect.height; y += 1) {
      for (var x = 0; x < cropRect.width; x += 1) {
        final pixel = source.getPixel(cropRect.left + x, cropRect.top + y);
        final alpha = pixel.aNormalized.toDouble().clamp(0.0, 1.0);
        final offset = (y * cropRect.width + x) * 3;

        // JPEG に透過はないため、sRGB を線形化してから白いキャンバスへ合成する
        linearRgb[offset] = SrgbColorSpace.toLinear(pixel.rNormalized.toDouble()) * alpha + (1.0 - alpha);
        linearRgb[offset + 1] = SrgbColorSpace.toLinear(pixel.gNormalized.toDouble()) * alpha + (1.0 - alpha);
        linearRgb[offset + 2] = SrgbColorSpace.toLinear(pixel.bNormalized.toDouble()) * alpha + (1.0 - alpha);
      }
    }
    return LanczosLinearRgbImage(
      width: cropRect.width,
      height: cropRect.height,
      linearRgb: linearRgb,
    );
  }

  /// 生成結果が要求解像度の JPEG かを確認します。
  static void _verifyJpeg(Uint8List jpegBytes, int width, int height) {
    final decoder = image.findDecoderForData(jpegBytes);
    if (decoder == null || decoder.format != image.ImageFormat.jpg) {
      throw const MozJpegEncodingException('cjpeg output is not a JPEG file.');
    }
    final decoded = decoder.decode(jpegBytes, frame: 0);
    if (decoded == null || decoded.width != width || decoded.height != height) {
      throw const MozJpegEncodingException('cjpeg output dimensions do not match the request.');
    }
  }

  /// Windows の既存出力をステージ済み JPEG で置き換えます。
  static Future<void> _replaceStagedOutputOnWindows(File stagedOutput, File outputFile) async {
    try {
      // 一時出力と既存 JPEG を同じボリューム内で1回の Win32 操作として入れ替える
      await _fileOperationsChannel.invokeMethod<void>(
        'replaceStagedOutputAtomically',
        {
          'stagedOutputPath': stagedOutput.path,
          'outputPath': outputFile.path,
        },
      );
    } on PlatformException catch (error) {
      final errorCode = error.details is int ? error.details as int : null;
      final osError = errorCode == null
          ? null
          : OSError(error.message ?? 'Windows file replacement failed.', errorCode);
      throw FileSystemException(
        'Could not atomically replace JPEG output: ${error.code}.',
        outputFile.path,
        osError,
      );
    } on MissingPluginException catch (error) {
      throw FileSystemException(
        'Could not atomically replace JPEG output: ${error.message}.',
        outputFile.path,
      );
    }
  }

  /// ステージ済みファイルを既存 JPEG 入力へ原子的に名前変更します。
  static Future<void> _renameAtomically(File stagedOutput, File outputFile) async {
    try {
      await stagedOutput.rename(outputFile.path);
    } on FileSystemException catch (error) {
      throw FileSystemException(
        'Could not atomically replace JPEG output.',
        outputFile.path,
        error.osError,
      );
    }
  }

  /// ステージ済みファイルを、既存ファイルを置き換えずに新規出力として公開します。
  static Future<void> _publishNewOutputExclusively(
    File stagedOutput,
    File outputFile, {
    Future<void> Function(File stagedOutput, File outputFile)? replaceStagedOutput,
  }) async {
    var hasReservedOutput = false;
    try {
      // 排他的な空ファイルを先に確保すると、確定直前の同名作成も公開失敗として返せる
      await outputFile.create(exclusive: true);
      hasReservedOutput = true;

      if (replaceStagedOutput != null) {
        await replaceStagedOutput(stagedOutput, outputFile);
      } else if (Platform.isWindows) {
        // 排他的に確保した出力名だけを native API で確定し、既存出力は予約時に保護する
        await _replaceStagedOutputOnWindows(stagedOutput, outputFile);
      } else {
        await stagedOutput.rename(outputFile.path);
      }
    } on FileSystemException {
      if (hasReservedOutput) {
        try {
          // 排他的に作成した予約ファイルだけを取り除き、次回も同じ出力名を選べるようにする
          await outputFile.delete();
        } on FileSystemException {
          // 削除結果にかかわらず、元の公開失敗をキューへ返す
        }
      }
      rethrow;
    }
  }

  /// `image` パッケージの形式を許可された静止画へ絞ります。
  static SourceImageFormat _sourceFormatFor(image.ImageFormat format) {
    return switch (format) {
      image.ImageFormat.jpg => SourceImageFormat.jpeg,
      image.ImageFormat.png => SourceImageFormat.png,
      image.ImageFormat.webp => SourceImageFormat.webp,
      _ => throw const UnsupportedImageException(
        'Only JPEG, PNG, and WebP input files are supported.',
      ),
    };
  }
}

/// ワーカー [Isolate] からエンコード処理へ返す、1枚分の準備済みデータです。
class _PreparedImage {
  const _PreparedImage({
    required this.sourceFormat,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.plan,
    required this.crop,
    required this.directRgbBytes,
    required this.metadataSegments,
    required this.iccProfileBytes,
  });

  final SourceImageFormat sourceFormat;
  final int sourceWidth;
  final int sourceHeight;
  final ImageSizePlan plan;
  final LanczosLinearRgbImage? crop;
  final Uint8List? directRgbBytes;
  final List<JpegMetadataSegment> metadataSegments;
  final Uint8List? iccProfileBytes;
}

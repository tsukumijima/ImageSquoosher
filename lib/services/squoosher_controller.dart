/// 画面と画像変換エンジンを結ぶ操作窓口。
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as image;

import '../models/conversion_settings.dart';
import '../models/image_dimensions.dart';
import '../utils/output_name_planner.dart';
import 'image_conversion_pipeline.dart';
import 'image_pipeline_types.dart';
import 'logging_service.dart';

/// 画像キューの現在の処理状態です。
enum QueuedImageStatus { queued, processing, completed, failed, stopped }

/// 画面に表示する入力画像と変換結果です。
class QueuedImage {
  const QueuedImage({
    required this.path,
    this.byteLength,
    this.sourceDimensions,
    this.outputPath,
    this.outputDimensions,
    this.outputByteLength,
    this.status = QueuedImageStatus.queued,
    this.isInputValid = true,
    this.errorMessage,
  });

  final String path;
  final int? byteLength;
  final ImageDimensions? sourceDimensions;
  final String? outputPath;
  final ImageDimensions? outputDimensions;
  final int? outputByteLength;
  final QueuedImageStatus status;
  final bool isInputValid;
  final String? errorMessage;

  String get fileName => path.split(Platform.pathSeparator).last;

  /// 新しい読み取り結果や変換状態を反映した行を返します。
  QueuedImage copyWith({
    int? byteLength,
    ImageDimensions? sourceDimensions,
    String? outputPath,
    ImageDimensions? outputDimensions,
    int? outputByteLength,
    QueuedImageStatus? status,
    bool? isInputValid,
    String? errorMessage,
    bool clearErrorMessage = false,
    bool clearOutputByteLength = false,
  }) {
    return QueuedImage(
      path: path,
      byteLength: byteLength ?? this.byteLength,
      sourceDimensions: sourceDimensions ?? this.sourceDimensions,
      outputPath: outputPath ?? this.outputPath,
      outputDimensions: outputDimensions ?? this.outputDimensions,
      outputByteLength: clearOutputByteLength ? null : outputByteLength ?? this.outputByteLength,
      status: status ?? this.status,
      isInputValid: isInputValid ?? this.isInputValid,
      errorMessage: clearErrorMessage ? null : errorMessage ?? this.errorMessage,
    );
  }
}

/// キューへ追加する時点で読み取る静止画の情報です。
class _ImageInspection {
  const _ImageInspection(this.dimensions);

  final ImageDimensions dimensions;
}

/// 変換エンジンの開始時に渡す条件です。
class CompressionRequest {
  const CompressionRequest({required this.images, required this.settings});

  final List<QueuedImage> images;
  final ConversionSettings settings;
}

/// 実際のエンコーダーが実装するインターフェースです。
abstract interface class ImageCompressionEngine {
  /// 画像を圧縮し、個々の行の状態を逐次通知します。
  Future<ImageBatchConversionResult> compress(
    CompressionRequest request, {
    required ImageConversionStopToken stopToken,
    required ValueChanged<QueuedImage> onItemStarted,
    required FutureOr<void> Function(ImageConversionResult) onItemCompleted,
    required ValueChanged<ImageConversionFailure> onItemFailed,
  });
}

/// 既存の `ImageConversionPipeline` を画面用の逐次処理へ接続します。
class PipelineCompressionEngine implements ImageCompressionEngine {
  PipelineCompressionEngine({ImageConversionPipeline? pipeline}) : _pipeline = pipeline ?? ImageConversionPipeline();

  final ImageConversionPipeline _pipeline;

  @override
  Future<ImageBatchConversionResult> compress(
    CompressionRequest request, {
    required ImageConversionStopToken stopToken,
    required ValueChanged<QueuedImage> onItemStarted,
    required FutureOr<void> Function(ImageConversionResult) onItemCompleted,
    required ValueChanged<ImageConversionFailure> onItemFailed,
  }) async {
    final executable = await _resolveCjpegExecutable();
    final completed = <ImageConversionResult>[];
    final failures = <ImageConversionFailure>[];
    final occupiedPaths = <String>{};

    // 同じ起動で作る出力も候補へ入れ、選択した一覧内で名前が衝突しないようにする
    for (final queuedImage in request.images) {
      if (stopToken.isRequested) {
        return ImageBatchConversionResult(completed: completed, failures: failures, wasStopped: true);
      }

      onItemStarted(queuedImage);
      try {
        final inputFile = File(queuedImage.path);
        final existingPaths = await _existingPaths(inputFile.parent);
        final outputPlan = OutputNamePlanner.plan(
          inputPath: inputFile.path,
          existingPaths: {...existingPaths, ...occupiedPaths},
          suffix: request.settings.suffix,
          overwrite: request.settings.overwrite,
        );
        occupiedPaths.add(outputPlan.outputPath);
        final result = await _pipeline.convert(
          ImageConversionRequest(
            inputFile: inputFile,
            outputFile: File(outputPlan.outputPath),
            cjpegExecutable: executable,
            settings: request.settings,
            finalizeStagedOutput: Platform.isMacOS || Platform.isWindows ? _copySourceFileDates : null,
          ),
        );
        await _removeConvertedSource(result, request.settings);
        completed.add(result);
        await onItemCompleted(result);
      } catch (error, stackTrace) {
        final failure = ImageConversionFailure(
          inputFile: File(queuedImage.path),
          error: error,
          stackTrace: stackTrace,
        );
        failures.add(failure);
        onItemFailed(failure);
      }
    }
    return ImageBatchConversionResult(
      completed: completed,
      failures: failures,
      wasStopped: stopToken.isRequested,
    );
  }

  /// アプリ配布物と開発用の出力先から `cjpeg` を探します。
  static Future<File> _resolveCjpegExecutable() async {
    final executableDirectory = File(Platform.resolvedExecutable).parent;
    final configuredPath = Platform.environment['IMAGE_SQUOOSHER_CJPEG'];
    final candidates = <File>[
      if (configuredPath != null && configuredPath.isNotEmpty) File(configuredPath),
      if (Platform.isMacOS)
        File(
          '${executableDirectory.parent.path}${Platform.pathSeparator}Resources${Platform.pathSeparator}mozjpeg${Platform.pathSeparator}cjpeg',
        ),
      if (Platform.isWindows)
        File('${executableDirectory.path}${Platform.pathSeparator}mozjpeg${Platform.pathSeparator}cjpeg.exe'),
      File(
        '${Directory.current.path}${Platform.pathSeparator}native${Platform.pathSeparator}mozjpeg${Platform.pathSeparator}'
        '${Platform.isWindows ? 'windows${Platform.pathSeparator}cjpeg.exe' : 'macos${Platform.pathSeparator}arm64${Platform.pathSeparator}cjpeg'}',
      ),
    ];
    for (final candidate in candidates) {
      if (await candidate.exists()) {
        return candidate;
      }
    }
    throw StateError('MozJPEG cjpeg executable was not found.');
  }

  /// EXIF の向き、アニメーション、破損を変換前に検査して一覧へ理由を残します。
  static Future<_ImageInspection> _inspectInputImage(File inputFile) async {
    final inputBytes = await inputFile.readAsBytes();
    final decoder = image.findDecoderForData(inputBytes);
    final decodeInfo = decoder?.startDecode(inputBytes);
    if (decodeInfo == null || decodeInfo.width <= 0 || decodeInfo.height <= 0) {
      throw const UnsupportedImageException('The input image could not be decoded.');
    }
    if (decoder!.format != image.ImageFormat.jpg &&
        decoder.format != image.ImageFormat.png &&
        decoder.format != image.ImageFormat.webp) {
      throw const UnsupportedImageException('Only JPEG, PNG, and WebP input files are supported.');
    }
    if (decoder.numFrames() > 1 || decodeInfo.numFrames > 1) {
      throw const UnsupportedImageException('Animated images cannot be converted.');
    }
    final decoded = decoder.decode(inputBytes, frame: 0);
    if (decoded == null) {
      throw const UnsupportedImageException('The input image contains no pixel data.');
    }
    final oriented = image.bakeOrientation(decoded);
    return _ImageInspection(ImageDimensions(oriented.width, oriented.height));
  }

  /// 保存済みの同名出力も避けられるよう、ディレクトリ内のパスを読み取ります。
  static Future<Set<String>> _existingPaths(Directory directory) async {
    if (await directory.exists() == false) {
      return <String>{};
    }
    return directory.list().map((entity) => entity.path).toSet();
  }

  /// 入力が残っている間に、検証済みの一時 JPEG へ作成日時と更新日時を複製します。
  static Future<void> _copySourceFileDates(File sourceFile, File stagedOutput) async {
    try {
      await const MethodChannel('net.tsukumijima.image-squoosher/finder_sync').invokeMethod<void>(
        'copySourceFileDatesToOutputFile',
        {'sourcePath': sourceFile.path, 'outputPath': stagedOutput.path},
      );
    } catch (error, stackTrace) {
      LoggingService.instance.warning(
        'Failed to copy source file dates.',
        tag: 'Compression',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  /// PNG/WebP の上書き時は、日時まで反映済みの JPEG を公開してから元入力を削除します。
  static Future<void> _removeConvertedSource(
    ImageConversionResult result,
    ConversionSettings settings,
  ) async {
    if (settings.overwrite && result.sourceFormat != SourceImageFormat.jpeg) {
      await result.inputFile.delete();
    }
  }
}

/// 画面が扱う画像一覧と実行状態を管理します。
class SquoosherController extends ChangeNotifier {
  SquoosherController({
    ImageCompressionEngine? engine,
    Future<Set<String>> Function(Directory directory)? existingPathsReader,
    LoggingService? log,
  }) : _engine = engine ?? PipelineCompressionEngine(),
       _existingPathsReader = existingPathsReader ?? PipelineCompressionEngine._existingPaths,
       _log = log ?? LoggingService.instance;

  final ImageCompressionEngine _engine;
  final Future<Set<String>> Function(Directory directory) _existingPathsReader;
  final LoggingService _log;
  final List<QueuedImage> _images = [];
  ImageConversionStopToken? _stopToken;
  ConversionSettings? _displaySettings;
  // ディスク確認中に設定やキューが変わった場合、古い出力計画を画面へ反映しないための世代番号
  int _outputPlanGeneration = 0;
  bool _isCompressing = false;
  bool _isStopping = false;
  bool _lastRunWasStopped = false;

  List<QueuedImage> get images => List.unmodifiable(_images);
  bool get isCompressing => _isCompressing;
  bool get isStopping => _isStopping;
  bool get lastRunWasStopped => _lastRunWasStopped;
  int get completedCount => _images.where((image) => image.status == QueuedImageStatus.completed).length;
  int get failedCount => _images.where((image) => image.status == QueuedImageStatus.failed).length;
  bool get hasValidImages => _images.any((image) => image.isInputValid);
  bool get hasPendingImages => _images.any(
    (image) =>
        image.isInputValid &&
        image.status != QueuedImageStatus.completed &&
        image.status != QueuedImageStatus.processing,
  );

  /// 外部のファイル選択機能から得たパスを一覧へ加え、重複は除外します。
  int addFiles(Iterable<String> paths) {
    if (_isCompressing) {
      return 0;
    }

    final knownPaths = _images.map((image) => _normalizedPath(image.path)).toSet();
    var addedCount = 0;
    for (final path in paths) {
      final normalizedPath = _normalizedPath(path);
      if (normalizedPath.isEmpty || knownPaths.add(normalizedPath) == false) {
        continue;
      }
      _images.add(QueuedImage(path: path));
      addedCount += 1;
      _loadImageDetails(path);
    }
    if (addedCount > 0) {
      _outputPlanGeneration += 1;
      _log.info('Images added: $addedCount.', tag: 'Queue');
      notifyListeners();
    }
    return addedCount;
  }

  /// 現在の一覧を置き換え、Finder などから受け取った新しい選択を反映します。
  int replaceFiles(Iterable<String> paths) {
    if (_isCompressing) {
      return 0;
    }
    _outputPlanGeneration += 1;
    _images.clear();
    final addedCount = addFiles(paths);
    if (addedCount == 0) {
      notifyListeners();
    }
    return addedCount;
  }

  /// 画面上のキューを空にします。
  void clear() {
    if (_isCompressing || _images.isEmpty) {
      return;
    }
    _outputPlanGeneration += 1;
    _images.clear();
    _log.info('Image queue cleared.', tag: 'Queue');
    notifyListeners();
  }

  /// 指定した画像だけを一覧から外します。
  void removeFile(String path) {
    if (_isCompressing) {
      return;
    }
    final index = _images.indexWhere((image) => image.path == path);
    if (index < 0) {
      return;
    }
    _outputPlanGeneration += 1;
    _images.removeAt(index);
    notifyListeners();
    final displaySettings = _displaySettings;
    if (displaySettings != null && _images.isNotEmpty) {
      unawaited(updateOutputPlans(displaySettings));
    }
  }

  /// 完了・失敗・停止済みの行を、同じ設定で再実行できる待機状態へ戻します。
  void resetResults() {
    if (_isCompressing) {
      return;
    }
    for (var index = 0; index < _images.length; index += 1) {
      if (_images[index].isInputValid) {
        // JPEG の上書き結果を再処理するときは、保存済みの画像を新しい入力として扱う
        final hasReplacedInput =
            _images[index].status == QueuedImageStatus.completed && _images[index].path == _images[index].outputPath;
        _images[index] = _images[index].copyWith(
          sourceDimensions: hasReplacedInput ? _images[index].outputDimensions : null,
          byteLength: hasReplacedInput ? _images[index].outputByteLength : null,
          status: QueuedImageStatus.queued,
          clearErrorMessage: true,
          clearOutputByteLength: true,
        );
      }
    }
    notifyListeners();
  }

  /// 指定された変換条件を各行の予定出力へ反映します。
  Future<void> updateOutputPlans(ConversionSettings settings) async {
    // 実行中は開始時の条件と結果表示を保持する
    if (_isCompressing) {
      return;
    }
    await _updateOutputPlans(settings);
  }

  /// 変換条件の実変更を判定し、未完了の行に出力計画を作ります。
  Future<void> _updateOutputPlans(ConversionSettings settings) async {
    final outputPlanGeneration = ++_outputPlanGeneration;
    final previousSettings = _displaySettings;
    // 言語切り替えや画像追加でも呼ばれるため、変換値が変わったときだけ結果を待機へ戻す
    if (previousSettings != null &&
        (previousSettings.aspectRatio != settings.aspectRatio ||
            previousSettings.quality != settings.quality ||
            previousSettings.resizeEnabled != settings.resizeEnabled ||
            previousSettings.resizeAxis != settings.resizeAxis ||
            previousSettings.resizeValue != settings.resizeValue ||
            previousSettings.allowUpscale != settings.allowUpscale ||
            previousSettings.stripMetadata != settings.stripMetadata ||
            previousSettings.suffix != settings.suffix ||
            previousSettings.overwrite != settings.overwrite)) {
      for (var index = 0; index < _images.length; index += 1) {
        if (_images[index].isInputValid) {
          // 完了表示の比較情報は待機へ戻す時点で、上書き後の入力寸法とサイズへ切り替える
          final hasReplacedInput =
              _images[index].status == QueuedImageStatus.completed && _images[index].path == _images[index].outputPath;
          _images[index] = _images[index].copyWith(
            sourceDimensions: hasReplacedInput ? _images[index].outputDimensions : null,
            byteLength: hasReplacedInput ? _images[index].outputByteLength : null,
            status: QueuedImageStatus.queued,
            clearErrorMessage: true,
            clearOutputByteLength: true,
          );
        }
      }
    }
    _displaySettings = settings;
    final plannedPaths = _images
        .where((image) => image.status == QueuedImageStatus.completed)
        .map((image) => image.outputPath)
        .whereType<String>()
        .toSet();
    final existingPathsByDirectory = <String, Set<String>>{};
    final outputPlans = <String, ({String outputPath, ImageDimensions outputDimensions})>{};
    final imagesToPlan = List<QueuedImage>.of(_images);
    for (final queuedImage in imagesToPlan) {
      // 完了行は実際に生成したパス、寸法、サイズを保持する
      if (queuedImage.status == QueuedImageStatus.completed) {
        continue;
      }
      final sourceDimensions = queuedImage.sourceDimensions;
      if (sourceDimensions == null) {
        continue;
      }
      final parentPath = File(queuedImage.path).parent.path;
      final existingPaths = existingPathsByDirectory.putIfAbsent(
        parentPath,
        () => <String>{},
      );
      if (existingPaths.isEmpty) {
        existingPaths.addAll(await _existingPathsReader(File(queuedImage.path).parent));
      }
      final outputPlan = OutputNamePlanner.plan(
        inputPath: queuedImage.path,
        existingPaths: {...existingPaths, ...plannedPaths},
        suffix: settings.suffix,
        overwrite: settings.overwrite,
      );
      plannedPaths.add(outputPlan.outputPath);
      outputPlans[queuedImage.path] = (
        outputPath: outputPlan.outputPath,
        outputDimensions: settings.plan(sourceDimensions).output,
      );
    }
    // 非同期で始まった古い計画は、利用者が最後に選んだ条件の表示を維持する
    if (outputPlanGeneration != _outputPlanGeneration) {
      return;
    }
    for (final entry in outputPlans.entries) {
      final index = _images.indexWhere((image) => image.path == entry.key);
      if (index >= 0) {
        // 計画処理が所有する2項目だけを最新の行へ反映し、処理状態やエラーを巻き戻さない
        _images[index] = _images[index].copyWith(
          outputPath: entry.value.outputPath,
          outputDimensions: entry.value.outputDimensions,
        );
      }
    }
    notifyListeners();
  }

  /// 変換を開始し、完了・失敗をそれぞれの行へ記録します。
  Future<bool> compress(ConversionSettings settings) async {
    if (hasPendingImages == false || _isCompressing) {
      return false;
    }

    _isCompressing = true;
    _isStopping = false;
    _lastRunWasStopped = false;
    _stopToken = ImageConversionStopToken();
    for (var index = 0; index < _images.length; index += 1) {
      if (_images[index].isInputValid && _images[index].status != QueuedImageStatus.completed) {
        _images[index] = _images[index].copyWith(status: QueuedImageStatus.queued, clearErrorMessage: true);
      }
    }
    try {
      await _updateOutputPlans(settings);
      notifyListeners();

      final result = await _engine.compress(
        CompressionRequest(
          images: images.where((image) => image.isInputValid && image.status == QueuedImageStatus.queued).toList(),
          settings: settings,
        ),
        stopToken: _stopToken!,
        onItemStarted: _markProcessing,
        onItemCompleted: _markCompleted,
        onItemFailed: _markFailed,
      );
      if (result.wasStopped) {
        _markRemainingAsStopped();
      }
      _lastRunWasStopped = result.wasStopped;
      _log.info('Image compression completed.', tag: 'Compression');
      return true;
    } catch (error, stackTrace) {
      _log.error('Image compression failed.', tag: 'Compression', error: error, stackTrace: stackTrace);
      rethrow;
    } finally {
      _stopToken = null;
      _isCompressing = false;
      _isStopping = false;
      notifyListeners();
    }
  }

  /// 現在の画像を安全に完了させ、次の画像を開始する前に停止します。
  void requestStop() {
    if (_isCompressing == false || _isStopping) {
      return;
    }
    _isStopping = true;
    _stopToken?.requestStop();
    _log.info('Image compression stop requested.', tag: 'Compression');
    notifyListeners();
  }

  /// ファイルの追加直後にも、一覧で寸法とファイルサイズを確認できるようにします。
  Future<void> _loadImageDetails(String path) async {
    try {
      final inputFile = File(path);
      final stat = await inputFile.stat();
      final inspection = await PipelineCompressionEngine._inspectInputImage(inputFile);
      final index = _images.indexWhere((image) => image.path == path);
      if (index < 0 || _isCompressing) {
        return;
      }
      _images[index] = _images[index].copyWith(byteLength: stat.size, sourceDimensions: inspection.dimensions);
      if (_displaySettings != null) {
        unawaited(updateOutputPlans(_displaySettings!));
      }
      notifyListeners();
    } catch (error, stackTrace) {
      _log.warning('Failed to read image details.', tag: 'Queue', error: error, stackTrace: stackTrace);
      final index = _images.indexWhere((image) => image.path == path);
      if (index >= 0 && _isCompressing == false) {
        _images[index] = _images[index].copyWith(
          status: QueuedImageStatus.failed,
          isInputValid: false,
          errorMessage: error.toString(),
        );
        notifyListeners();
      }
    }
  }

  /// 変換中の行を見つけて状態を切り替えます。
  void _markProcessing(QueuedImage queuedImage) {
    _replaceByPath(queuedImage.path, (current) => current.copyWith(status: QueuedImageStatus.processing));
  }

  /// 成功した出力の寸法とファイルサイズを行へ表示します。
  Future<void> _markCompleted(ImageConversionResult result) async {
    final outputSize = await result.outputFile.length();
    // PNG / WebP の上書きで元入力が削除された行は、再実行の対象から外して成功結果を保持する
    final isInputValid = await result.inputFile.exists();
    _replaceByPath(
      result.inputFile.path,
      (current) => current.copyWith(
        sourceDimensions: ImageDimensions(result.sourceWidth, result.sourceHeight),
        outputPath: result.outputFile.path,
        outputDimensions: ImageDimensions(result.outputWidth, result.outputHeight),
        outputByteLength: outputSize,
        status: QueuedImageStatus.completed,
        isInputValid: isInputValid,
        clearErrorMessage: true,
      ),
    );
  }

  /// 個別失敗は次の画像を続行できるよう、該当行だけへ理由を残します。
  void _markFailed(ImageConversionFailure failure) {
    _replaceByPath(
      failure.inputFile.path,
      (current) => current.copyWith(status: QueuedImageStatus.failed, errorMessage: failure.error.toString()),
    );
  }

  /// 停止要求を受けた後に未着手の行を停止済みとして残します。
  void _markRemainingAsStopped() {
    for (var index = 0; index < _images.length; index += 1) {
      if (_images[index].status == QueuedImageStatus.queued) {
        _images[index] = _images[index].copyWith(status: QueuedImageStatus.stopped);
      }
    }
  }

  /// パスに対応する1行を置き換え、画面へ変更を通知します。
  void _replaceByPath(String path, QueuedImage Function(QueuedImage current) update) {
    final index = _images.indexWhere((image) => image.path == path);
    if (index < 0) {
      return;
    }
    _images[index] = update(_images[index]);
    notifyListeners();
  }

  /// 異なる区切り文字や相対パスで渡されても同じファイルとして扱います。
  static String _normalizedPath(String path) {
    if (path.trim().isEmpty) {
      return '';
    }
    final absolutePath = File(path).absolute.path.replaceAll('\\', '/');
    return Platform.isWindows ? absolutePath.toLowerCase() : absolutePath;
  }
}

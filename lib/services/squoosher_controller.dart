/// 画面と画像変換エンジンを結ぶ操作窓口。
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as image;

import '../models/conversion_settings.dart';
import '../models/image_dimensions.dart';
import '../utils/output_name_planner.dart';
import 'image_conversion_pipeline.dart';
import 'image_pipeline_types.dart';
import 'logging_service.dart';

/// 画像キューの現在の処理状態。
enum QueuedImageStatus { queued, processing, completed, failed, stopped }

/// 画面に表示する入力画像と変換結果。
class QueuedImage {
  /// 入力画像と変換状態を作成する。
  /// @param path 入力画像のパス
  /// @param byteLength 入力画像のファイルサイズ
  /// @param sourceDimensions 入力画像の寸法
  /// @param outputPath 出力画像のパス
  /// @param outputDimensions 出力画像の寸法
  /// @param outputByteLength 出力画像のファイルサイズ
  /// @param status キュー内の処理状態
  /// @param progress 変換の進捗率
  /// @param isInputValid 入力画像が変換可能かどうか
  /// @param errorMessage 入力または変換に失敗した理由
  const QueuedImage({
    required this.path,
    this.byteLength,
    this.sourceDimensions,
    this.outputPath,
    this.outputDimensions,
    this.outputByteLength,
    this.status = QueuedImageStatus.queued,
    this.progress = 0,
    this.isInputValid = true,
    this.errorMessage,
  });

  /// 入力画像のパス
  final String path;

  /// 入力画像のファイルサイズ
  final int? byteLength;

  /// 入力画像の寸法
  final ImageDimensions? sourceDimensions;

  /// 出力画像のパス
  final String? outputPath;

  /// 出力画像の寸法
  final ImageDimensions? outputDimensions;

  /// 出力画像のファイルサイズ
  final int? outputByteLength;

  /// キュー内の処理状態
  final QueuedImageStatus status;

  /// 変換の進捗率
  final double progress;

  /// 入力画像が変換可能かどうか
  final bool isInputValid;

  /// 入力または変換に失敗した理由
  final String? errorMessage;

  /// パスからファイル名を取得する。
  /// @returns 入力画像のファイル名
  String get fileName => path.split(Platform.pathSeparator).last;

  /// 指定した読み取り結果や変換状態を反映した行を返す。
  /// @param byteLength 更新する入力画像のファイルサイズ
  /// @param sourceDimensions 更新する入力画像の寸法
  /// @param outputPath 更新する出力画像のパス
  /// @param outputDimensions 更新する出力画像の寸法
  /// @param outputByteLength 更新する出力画像のファイルサイズ
  /// @param status 更新する処理状態
  /// @param progress 更新する進捗率
  /// @param isInputValid 更新する入力可否
  /// @param errorMessage 更新するエラーメッセージ
  /// @param clearErrorMessage エラーメッセージを消去するかどうか
  /// @param clearOutputByteLength 出力ファイルサイズを消去するかどうか
  /// @returns 更新後のキュー項目
  QueuedImage copyWith({
    int? byteLength,
    ImageDimensions? sourceDimensions,
    String? outputPath,
    ImageDimensions? outputDimensions,
    int? outputByteLength,
    QueuedImageStatus? status,
    double? progress,
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
      progress: progress ?? this.progress,
      isInputValid: isInputValid ?? this.isInputValid,
      errorMessage: clearErrorMessage ? null : errorMessage ?? this.errorMessage,
    );
  }
}

/// キューへ追加する時点で読み取る静止画の情報。
class _ImageInspection {
  /// 入力画像の寸法情報を作成する。
  /// @param dimensions 入力画像の寸法
  const _ImageInspection(this.dimensions);

  /// 入力画像の寸法
  final ImageDimensions dimensions;
}

/// 変換エンジンの開始時に渡す条件。
class CompressionRequest {
  /// 変換対象と変換条件を作成する。
  /// @param images 変換対象の画像一覧
  /// @param settings 適用する変換条件
  /// @param onProgress 画像ごとの進捗通知
  const CompressionRequest({required this.images, required this.settings, this.onProgress});

  /// 変換対象の画像一覧
  final List<QueuedImage> images;

  /// 画像ごとの進捗通知
  final void Function(String path, double progress)? onProgress;

  /// 適用する変換条件
  final ConversionSettings settings;
}

/// 実際のエンコーダーが実装するインターフェース。
abstract interface class ImageCompressionEngine {
  /// 画像を圧縮し、個々の行の状態を逐次通知する。
  /// @param request 変換対象と変換条件
  /// @param stopToken 停止要求を共有するトークン
  /// @param onItemStarted 画像の処理開始時に呼び出す通知
  /// @param onItemCompleted 画像の処理完了時に呼び出す通知
  /// @param onItemFailed 画像の処理失敗時に呼び出す通知
  /// @returns バッチ全体の完了結果
  Future<ImageBatchConversionResult> compress(
    CompressionRequest request, {
    required ImageConversionStopToken stopToken,
    required ValueChanged<QueuedImage> onItemStarted,
    required FutureOr<void> Function(ImageConversionResult) onItemCompleted,
    required ValueChanged<ImageConversionFailure> onItemFailed,
  });
}

/// 既存の `ImageConversionPipeline` を画面用の逐次処理へ接続する。
class PipelineCompressionEngine implements ImageCompressionEngine {
  /// 変換パイプラインを指定してエンジンを作成する。
  /// @param pipeline 使用する変換パイプライン
  PipelineCompressionEngine({ImageConversionPipeline? pipeline}) : _pipeline = pipeline ?? ImageConversionPipeline();

  final ImageConversionPipeline _pipeline;

  /// 画像を順番に圧縮し、各画像の状態を通知する。
  /// @param request 変換対象と変換条件
  /// @param stopToken 停止要求を共有するトークン
  /// @param onItemStarted 画像の処理開始時に呼び出す通知
  /// @param onItemCompleted 画像の処理完了時に呼び出す通知
  /// @param onItemFailed 画像の処理失敗時に呼び出す通知
  /// @returns バッチ全体の完了結果
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
            onProgress: (progress) => request.onProgress?.call(queuedImage.path, progress),
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

  /// アプリ配布物と開発用の出力先から `cjpeg` を探す。
  /// @returns 使用する `cjpeg` のパス
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

  /// ヘッダーから寸法と EXIF の向きを読み取り、アニメーションを一覧で拒否する。
  /// @param inputFile 検査する入力画像
  /// @returns 入力画像の寸法情報
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
    // 画素の破損検査は変換時の全画素デコードが担い、一覧の準備はヘッダーだけで完了する
    // PNG / WebP は変換用デコーダーと同じく保存された画素の向きで寸法を表示する
    final orientation = decoder.format == image.ImageFormat.jpg
        ? image.decodeJpgExif(inputBytes)?.imageIfd.orientation ?? 1
        : 1;
    final shouldSwapAxes = orientation >= 5 && orientation <= 8;
    return _ImageInspection(
      ImageDimensions(
        shouldSwapAxes ? decodeInfo.height : decodeInfo.width,
        shouldSwapAxes ? decodeInfo.width : decodeInfo.height,
      ),
    );
  }

  /// 保存済みの同名出力も避けられるよう、ディレクトリ内のパスを読み取る。
  /// @param directory 読み取るディレクトリ
  /// @returns ディレクトリ内のパス集合
  static Future<Set<String>> _existingPaths(Directory directory) async {
    if (await directory.exists() == false) {
      return <String>{};
    }
    return directory.list().map((entity) => entity.path).toSet();
  }

  /// 入力が残っている間に、検証済みの一時 JPEG へ作成日時と更新日時を複製する。
  /// @param sourceFile 日時を読み取る入力ファイル
  /// @param stagedOutput 日時を書き込む一時出力
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

  /// PNG/WebP の上書き時は、日時まで反映済みの JPEG を公開してから元入力を削除する。
  /// @param result 確定した変換結果
  /// @param settings 適用した変換条件
  static Future<void> _removeConvertedSource(
    ImageConversionResult result,
    ConversionSettings settings,
  ) async {
    if (settings.overwrite && result.sourceFormat != SourceImageFormat.jpeg) {
      await result.inputFile.delete();
    }
  }
}

/// 画面が扱う画像一覧と実行状態を管理する。
class SquoosherController extends ChangeNotifier {
  /// 画像変換エンジンと出力パス読み取り処理を指定して状態管理を作成する。
  /// @param engine 使用する画像変換エンジン
  /// @param existingPathsReader 出力先の既存パスを読み取る処理
  /// @param log 使用するログサービス
  SquoosherController({
    ImageCompressionEngine? engine,
    Future<Set<String>> Function(Directory directory)? existingPathsReader,
    LoggingService? log,
  }) : _engine = engine ?? PipelineCompressionEngine(),
       _existingPathsReader = existingPathsReader ?? PipelineCompressionEngine._existingPaths,
       _log = log ?? LoggingService.instance;

  /// 画像変換を実行するエンジン
  final ImageCompressionEngine _engine;

  /// 出力先の既存パスを読み取る処理
  final Future<Set<String>> Function(Directory directory) _existingPathsReader;

  /// キュー操作のログ出力先
  final LoggingService _log;

  /// 画面に表示する画像一覧
  final List<QueuedImage> _images = [];

  /// 実行中の変換へ停止要求を伝えるトークン
  ImageConversionStopToken? _stopToken;

  /// 画面へ表示する変換条件
  ConversionSettings? _displaySettings;
  // ディスク確認中に設定やキューが変わった場合、古い出力計画を画面へ反映しないための世代番号
  int _outputPlanGeneration = 0;

  /// 変換を実行中かどうか。
  bool _isCompressing = false;

  /// 停止処理を要求済みかどうか。
  bool _isStopping = false;

  /// 直前の変換が停止要求で終了したかどうか。
  bool _lastRunWasStopped = false;

  /// コントローラーを破棄済みかどうか。
  bool _isDisposed = false;

  /// 画像検査処理を直列化した末尾。
  Future<void> _inspectionTail = Future<void>.value();
  // 行の copyWith() と独立した識別子で、削除や同じパスの再追加をまたぐ検査結果を区別する
  final Map<String, Object> _inspectionTokens = {};

  @override
  void dispose() {
    _isDisposed = true;
    _outputPlanGeneration += 1;
    _inspectionTokens.clear();
    _stopToken?.requestStop();
    super.dispose();
  }

  @override
  void notifyListeners() {
    // 処理中に画面を閉じた場合は、ファイル確定を継続したまま画面への通知を抑える
    if (!_isDisposed) super.notifyListeners();
  }

  /// 画面に表示する画像一覧の読み取り専用コピー。
  /// @returns 現在の画像一覧
  List<QueuedImage> get images => List.unmodifiable(_images);

  /// 変換を実行中かどうか。
  /// @returns 実行中の場合は `true`
  bool get isCompressing => _isCompressing;

  /// 停止処理を要求済みかどうか。
  /// @returns 停止処理中の場合は `true`
  bool get isStopping => _isStopping;

  /// 直前の変換が停止要求で終了したかどうか。
  /// @returns 停止要求で終了した場合は `true`
  bool get lastRunWasStopped => _lastRunWasStopped;

  /// 完了した画像の件数。
  /// @returns 完了した画像の件数
  int get completedCount => _images.where((image) => image.status == QueuedImageStatus.completed).length;

  /// 失敗した画像の件数。
  /// @returns 失敗した画像の件数
  int get failedCount => _images.where((image) => image.status == QueuedImageStatus.failed).length;

  /// 停止済み画像の件数。
  /// @returns 停止済み画像の件数
  int get stoppedCount => _images.where((image) => image.status == QueuedImageStatus.stopped).length;

  /// キュー全体の進捗率。
  /// @returns キュー全体の進捗率
  double get progress => _images.isEmpty
      ? 0
      : _images.fold<double>(0, (sum, image) => sum + (image.status == QueuedImageStatus.failed ? 1 : image.progress)) /
            _images.length;

  /// 変換可能な画像が含まれるかどうか。
  /// @returns 変換可能な画像がある場合は `true`
  bool get hasValidImages => _images.any((image) => image.isInputValid);

  /// 未完了で変換可能な画像が含まれるかどうか。
  /// @returns 変換対象がある場合は `true`
  bool get hasPendingImages => _images.any(
    (image) =>
        image.isInputValid &&
        image.status != QueuedImageStatus.completed &&
        image.status != QueuedImageStatus.processing,
  );

  /// 外部のファイル選択機能から得たパスを一覧へ加え、重複は除外する。
  /// @param paths 追加する入力画像のパス
  /// @returns 追加した画像の件数
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
      // 大きな画像の検査は1枚ずつワーカーへ送り、画面用のメモリと実行時間を確保する
      final inspectionToken = Object();
      _inspectionTokens[path] = inspectionToken;
      _inspectionTail = _inspectionTail.then((_) async {
        if (!_isDisposed && identical(_inspectionTokens[path], inspectionToken)) {
          await _loadImageDetails(path, inspectionToken);
        }
      });
    }
    if (addedCount > 0) {
      _outputPlanGeneration += 1;
      _log.info('Images added: $addedCount.', tag: 'Queue');
      notifyListeners();
    }
    return addedCount;
  }

  /// 現在の一覧を置き換え、Finder などから受け取った新しい選択を反映する。
  /// @param paths 新しい入力画像のパス
  /// @returns 追加した画像の件数
  int replaceFiles(Iterable<String> paths) {
    if (_isCompressing) {
      return 0;
    }
    _outputPlanGeneration += 1;
    _inspectionTokens.clear();
    _images.clear();
    final addedCount = addFiles(paths);
    if (addedCount == 0) {
      notifyListeners();
    }
    return addedCount;
  }

  /// 画面上のキューを空にする。
  void clear() {
    if (_isCompressing || _images.isEmpty) {
      return;
    }
    _outputPlanGeneration += 1;
    _inspectionTokens.clear();
    _images.clear();
    _log.info('Image queue cleared.', tag: 'Queue');
    notifyListeners();
  }

  /// 指定した画像だけを一覧から外す。
  /// @param path 一覧から外す画像のパス
  void removeFile(String path) {
    if (_isCompressing) {
      return;
    }
    final index = _images.indexWhere((image) => image.path == path);
    if (index < 0) {
      return;
    }
    _outputPlanGeneration += 1;
    _inspectionTokens.remove(path);
    _images.removeAt(index);
    notifyListeners();
    final displaySettings = _displaySettings;
    if (displaySettings != null && _images.isNotEmpty) {
      unawaited(updateOutputPlans(displaySettings));
    }
  }

  /// 完了・失敗・停止済みの行を、同じ設定で再実行できる待機状態へ戻す。
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
          progress: 0,
          clearErrorMessage: true,
          clearOutputByteLength: true,
        );
      }
    }
    notifyListeners();
  }

  /// 指定された変換条件を各行の予定出力へ反映する。
  /// @param settings 予定出力の計算に使う変換条件
  Future<void> updateOutputPlans(ConversionSettings settings) async {
    // 実行中は開始時の条件と結果表示を保持する
    if (_isCompressing) {
      return;
    }
    await _updateOutputPlans(settings);
  }

  /// 変換条件の実変更を判定し、未完了の行に出力計画を作る。
  /// @param settings 出力計画に使う変換条件
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
            progress: 0,
            clearErrorMessage: true,
            clearOutputByteLength: true,
          );
        }
      }
    }
    _displaySettings = settings;
    for (var index = 0; index < _images.length; index += 1) {
      final current = _images[index];
      if (current.sourceDimensions != null && current.status != QueuedImageStatus.completed) {
        _images[index] = current.copyWith(outputDimensions: settings.plan(current.sourceDimensions!).output);
      }
    }
    notifyListeners();
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
      // 空のディレクトリも読み取り済みとして保存し、同じ一覧をファイル数だけ取得する負荷を抑える
      final existingPaths =
          existingPathsByDirectory[parentPath] ?? await _existingPathsReader(File(queuedImage.path).parent);
      existingPathsByDirectory[parentPath] = existingPaths;
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

  /// 変換を開始し、完了・失敗をそれぞれの行へ記録する。
  /// @param settings 適用する変換条件
  /// @returns 変換処理を開始できた場合は `true`
  Future<bool> compress(ConversionSettings settings) async {
    if (_isDisposed || hasPendingImages == false || _isCompressing) {
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
    notifyListeners();
    try {
      // 未検査の行も同じバッチへ含め、寸法と入力可否が確定してから出力名を計画する
      await _inspectionTail;
      if (_isDisposed) return false;
      await _updateOutputPlans(settings);
      if (_isDisposed) return false;
      notifyListeners();

      final result = await _engine.compress(
        CompressionRequest(
          images: images.where((image) => image.isInputValid && image.status == QueuedImageStatus.queued).toList(),
          settings: settings,
          onProgress: _markProgress,
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

  /// 現在の画像を安全に完了させ、次の画像を開始する前に停止する。
  void requestStop() {
    if (_isCompressing == false || _isStopping) {
      return;
    }
    _isStopping = true;
    _stopToken?.requestStop();
    _log.info('Image compression stop requested.', tag: 'Compression');
    notifyListeners();
  }

  /// ファイルの追加直後にも、一覧で寸法とファイルサイズを確認できるようにする。
  /// @param path 詳細を読み取る画像のパス
  /// @param inspectionToken 読み取り結果を識別するトークン
  Future<void> _loadImageDetails(String path, Object inspectionToken) async {
    try {
      final inputFile = File(path);
      final stat = await inputFile.stat();
      final inspection = await Isolate.run(() => PipelineCompressionEngine._inspectInputImage(File(path)));
      if (_isDisposed || !identical(_inspectionTokens[path], inspectionToken)) return;
      final index = _images.indexWhere((image) => image.path == path);
      if (index < 0) {
        return;
      }
      _images[index] = _images[index].copyWith(byteLength: stat.size, sourceDimensions: inspection.dimensions);
      if (_displaySettings != null && !_isCompressing) {
        unawaited(updateOutputPlans(_displaySettings!));
      }
      notifyListeners();
    } catch (error, stackTrace) {
      if (_isDisposed || !identical(_inspectionTokens[path], inspectionToken)) return;
      _log.warning('Failed to read image details.', tag: 'Queue', error: error, stackTrace: stackTrace);
      final index = _images.indexWhere((image) => image.path == path);
      if (index >= 0) {
        _images[index] = _images[index].copyWith(
          status: QueuedImageStatus.failed,
          isInputValid: false,
          errorMessage: error.toString(),
        );
        notifyListeners();
      }
    }
  }

  /// 変換中の行を見つけて状態を切り替える。
  /// @param queuedImage 処理を開始した画像
  void _markProcessing(QueuedImage queuedImage) {
    _replaceByPath(queuedImage.path, (current) => current.copyWith(status: QueuedImageStatus.processing, progress: 0));
  }

  /// エンコーダーの細かな通知を描画に必要な刻みへまとめる。
  /// @param path 進捗を更新する画像のパス
  /// @param progress 新しい進捗率
  void _markProgress(String path, double progress) {
    final index = _images.indexWhere((image) => image.path == path);
    if (index < 0 || _isDisposed) return;
    if (progress < 1 && progress - _images[index].progress < 0.005) return;
    _images[index] = _images[index].copyWith(progress: progress);
    notifyListeners();
  }

  /// 成功した出力の寸法とファイルサイズを行へ表示する。
  /// @param result 確定した変換結果
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
        progress: 1,
        isInputValid: isInputValid,
        clearErrorMessage: true,
      ),
    );
  }

  /// 個別失敗は次の画像を続行できるよう、該当行だけへ理由を残す。
  /// @param failure 変換に失敗した画像と理由
  void _markFailed(ImageConversionFailure failure) {
    _replaceByPath(
      failure.inputFile.path,
      (current) => current.copyWith(status: QueuedImageStatus.failed, errorMessage: failure.error.toString()),
    );
  }

  /// 停止要求を受けた後に未着手の行を停止済みとして残す。
  void _markRemainingAsStopped() {
    for (var index = 0; index < _images.length; index += 1) {
      if (_images[index].status == QueuedImageStatus.queued) {
        _images[index] = _images[index].copyWith(status: QueuedImageStatus.stopped);
      }
    }
  }

  /// パスに対応する1行を置き換え、画面へ変更を通知する。
  /// @param path 更新する画像のパス
  /// @param update 現在の行から更新後の行を作る処理
  void _replaceByPath(String path, QueuedImage Function(QueuedImage current) update) {
    final index = _images.indexWhere((image) => image.path == path);
    if (index < 0) {
      return;
    }
    _images[index] = update(_images[index]);
    notifyListeners();
  }

  /// 異なる区切り文字や相対パスで渡されても同じファイルとして扱う。
  /// @param path 正規化する画像のパス
  /// @returns 比較に使う絶対パス
  static String _normalizedPath(String path) {
    if (path.trim().isEmpty) {
      return '';
    }
    final absolutePath = File(path).absolute.path.replaceAll('\\', '/');
    return Platform.isWindows ? absolutePath.toLowerCase() : absolutePath;
  }
}

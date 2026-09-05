import 'dart:async';
import 'dart:io';

import '../models/conversion_settings.dart';
import '../models/image_dimensions.dart';

/// 入力ファイルが使う静止画形式です。
enum SourceImageFormat {
  /// JPEG です。
  jpeg,

  /// PNG です。
  png,

  /// WebP です。
  webp,
}

/// 1ファイルを JPEG へ変換する指定です。
///
/// 画面や設定モデルは、この小さな値オブジェクトへ選択値を渡します。
/// 変換器は UI の状態から独立しているため、順次バッチ処理中も同じ条件を保てます。
class ImageConversionRequest {
  /// 変換指定を作成します。
  ImageConversionRequest({
    required this.inputFile,
    required this.outputFile,
    required this.cjpegExecutable,
    required this.settings,
    this.finalizeStagedOutput,
    this.onProgress,
  });

  /// デコードする画像ファイルです。
  final File inputFile;

  /// 原子的に置き換える JPEG 出力先です。
  final File outputFile;

  /// バンドル済み `cjpeg` の実行ファイルです。
  final File cjpegExecutable;

  /// 切り出し、リサイズ、画質、メタデータを決める唯一の変換設定です。
  final ConversionSettings settings;

  /// 準備、圧縮、検証、保存の工程進捗を 0.0 から 1.0 で通知します。
  ///
  /// 経過時間の割合ではなく、1.0 は出力の公開まで成功したことを表します。
  final void Function(double progress)? onProgress;

  /// 検証済み JPEG を公開する直前に、日時などのファイル属性を反映します。
  ///
  /// 上書き時も入力が残っている段階で呼び出すため、元の作成日時をステージ済み出力へ複製できます。
  final Future<void> Function(File sourceFile, File stagedOutput)? finalizeStagedOutput;
}

/// 正常に完了した1ファイルの変換結果です。
class ImageConversionResult {
  /// 変換結果を作成します。
  const ImageConversionResult({
    required this.inputFile,
    required this.outputFile,
    required this.sourceFormat,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.cropRect,
    required this.outputWidth,
    required this.outputHeight,
  });

  /// 変換元です。
  final File inputFile;

  /// 生成した JPEG です。
  final File outputFile;

  /// 読み取った画像形式です。
  final SourceImageFormat sourceFormat;

  /// EXIF 補正後の横幅です。
  final int sourceWidth;

  /// EXIF 補正後の高さです。
  final int sourceHeight;

  /// 出力比率へ合わせた中央切り出し範囲です。
  final CropRect cropRect;

  /// 出力 JPEG の横幅です。
  final int outputWidth;

  /// 出力 JPEG の高さです。
  final int outputHeight;
}

/// 変換できなかったファイルと例外です。
class ImageConversionFailure {
  /// 失敗内容を作成します。
  const ImageConversionFailure({
    required this.inputFile,
    required this.error,
    required this.stackTrace,
  });

  /// 変換対象です。
  final File inputFile;

  /// 発生した例外です。
  final Object error;

  /// 失敗地点です。
  final StackTrace stackTrace;
}

/// 順次バッチ変換の完了状態です。
class ImageBatchConversionResult {
  /// バッチ結果を作成します。
  const ImageBatchConversionResult({
    required this.completed,
    required this.failures,
    required this.wasStopped,
  });

  /// 生成済み JPEG です。
  final List<ImageConversionResult> completed;

  /// 続行可能なファイル単位の失敗です。
  final List<ImageConversionFailure> failures;

  /// 停止要求を受け取った状態です。
  final bool wasStopped;
}

/// 画面からバッチへ渡す停止要求です。
///
/// 実行中の1件を完了した直後、次のファイルへ進む境界で利用します。
class ImageConversionStopToken {
  final Completer<void> _requested = Completer<void>();

  /// 停止要求済みなら `true` です。
  bool get isRequested => _requested.isCompleted;

  /// 停止を通知する [Future] です。
  Future<void> get whenRequested => _requested.future;

  /// 停止を要求します。
  void requestStop() {
    if (!_requested.isCompleted) {
      _requested.complete();
    }
  }
}

/// 利用者が変換停止を求めたことを表します。
class ImageConversionStoppedException implements Exception {
  /// 停止理由を作成します。
  const ImageConversionStoppedException();

  @override
  String toString() => 'Image conversion was stopped.';
}

/// デコード対象が静止 JPEG/PNG/WebP でないことを表します。
class UnsupportedImageException implements Exception {
  /// 例外を作成します。
  const UnsupportedImageException(this.message);

  /// 利用者へ出す理由です。
  final String message;

  @override
  String toString() => message;
}

/// `cjpeg` が JPEG を生成できなかったことを表します。
class MozJpegEncodingException implements Exception {
  /// 例外を作成します。
  const MozJpegEncodingException(this.message);

  /// `cjpeg` の標準エラー出力を含む理由です。
  final String message;

  @override
  String toString() => message;
}

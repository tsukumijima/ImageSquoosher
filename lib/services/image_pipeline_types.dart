import 'dart:async';
import 'dart:io';

import '../models/conversion_settings.dart';
import '../models/image_dimensions.dart';

/// 入力ファイルが使う静止画形式。
enum SourceImageFormat {
  /// JPEG 形式。
  jpeg,

  /// PNG 形式。
  png,

  /// WebP 形式。
  webp,
}

/// 1ファイルを JPEG へ変換する指定。
/// 画面や設定モデルから受け取った値を UI の状態から切り離し、変換中の条件を固定する。
class ImageConversionRequest {
  /// 変換指定を作成する。
  /// @param inputFile デコードする画像ファイル
  /// @param outputFile 生成する JPEG の出力先
  /// @param cjpegExecutable 実行する `cjpeg` のファイル
  /// @param settings 切り出し、リサイズ、画質、メタデータを決める設定
  /// @param finalizeStagedOutput 検証済み出力へファイル属性を反映する処理
  /// @param onProgress 変換の進捗を 0.0 から 1.0 で受け取る処理
  ImageConversionRequest({
    required this.inputFile,
    required this.outputFile,
    required this.cjpegExecutable,
    required this.settings,
    this.finalizeStagedOutput,
    this.onProgress,
  });

  /// デコードする画像ファイル。
  final File inputFile;

  /// 原子的に置き換える JPEG 出力先。
  final File outputFile;

  /// バンドル済み `cjpeg` の実行ファイル。
  final File cjpegExecutable;

  /// 切り出し、リサイズ、画質、メタデータを決める変換設定。
  final ConversionSettings settings;

  /// 準備、圧縮、検証、保存の工程進捗を 0.0 から 1.0 で通知する処理。
  /// 経過時間ではなく、1.0 は出力の公開まで成功した状態を表す。
  final void Function(double progress)? onProgress;

  /// 検証済み JPEG を公開する直前に、日時などのファイル属性を反映する処理。
  /// 入力が残っている上書き前の段階で呼び出し、元ファイルの属性をステージ済み出力へ複製する。
  final Future<void> Function(File sourceFile, File stagedOutput)? finalizeStagedOutput;
}

/// 正常に完了した1ファイルの変換結果。
class ImageConversionResult {
  /// 変換結果を作成する。
  /// @param inputFile 変換元の画像ファイル
  /// @param outputFile 生成した JPEG
  /// @param sourceFormat 読み取った画像形式
  /// @param sourceWidth EXIF 補正後の横幅
  /// @param sourceHeight EXIF 補正後の高さ
  /// @param cropRect 出力比率へ合わせた中央切り出し範囲
  /// @param outputWidth 出力 JPEG の横幅
  /// @param outputHeight 出力 JPEG の高さ
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

  /// 変換元の画像ファイル。
  final File inputFile;

  /// 生成した JPEG。
  final File outputFile;

  /// 読み取った画像形式。
  final SourceImageFormat sourceFormat;

  /// EXIF 補正後の横幅。
  final int sourceWidth;

  /// EXIF 補正後の高さ。
  final int sourceHeight;

  /// 出力比率へ合わせた中央切り出し範囲。
  final CropRect cropRect;

  /// 出力 JPEG の横幅。
  final int outputWidth;

  /// 出力 JPEG の高さ。
  final int outputHeight;
}

/// 変換できなかったファイルと例外。
class ImageConversionFailure {
  /// 失敗内容を作成する。
  /// @param inputFile 変換に失敗した画像ファイル
  /// @param error 発生した例外
  /// @param stackTrace 例外が発生した地点
  const ImageConversionFailure({
    required this.inputFile,
    required this.error,
    required this.stackTrace,
  });

  /// 変換対象の画像ファイル。
  final File inputFile;

  /// 発生した例外。
  final Object error;

  /// 失敗地点のスタックトレース。
  final StackTrace stackTrace;
}

/// 順次バッチ変換の完了状態。
class ImageBatchConversionResult {
  /// バッチ結果を作成する。
  /// @param completed 正常に生成できた JPEG の結果
  /// @param failures 個別に失敗し、処理を継続できたファイルの結果
  /// @param wasStopped 停止要求によって未処理のファイルを残した状態かどうか
  const ImageBatchConversionResult({
    required this.completed,
    required this.failures,
    required this.wasStopped,
  });

  /// 生成済み JPEG の結果。
  final List<ImageConversionResult> completed;

  /// 続行可能なファイル単位の失敗。
  final List<ImageConversionFailure> failures;

  /// 停止要求を受け取った状態かどうか。
  final bool wasStopped;
}

/// 画面からバッチへ渡す停止要求。
/// 実行中の1件を完了した直後、次のファイルへ進む境界で利用する。
class ImageConversionStopToken {
  /// 停止要求を一度だけ完了させる通知。
  final Completer<void> _requested = Completer<void>();

  /// 停止要求を受け取った状態かどうか。
  bool get isRequested => _requested.isCompleted;

  /// 停止要求が完了したときに完了する `Future`。
  Future<void> get whenRequested => _requested.future;

  /// 停止を要求する。
  void requestStop() {
    if (!_requested.isCompleted) {
      _requested.complete();
    }
  }
}

/// 利用者が変換停止を求めたことを表す例外。
class ImageConversionStoppedException implements Exception {
  /// 停止理由を作成する。
  const ImageConversionStoppedException();

  /// 停止例外を表示用の文字列へ変換する。
  /// @returns 停止理由の文字列
  @override
  String toString() => 'Image conversion was stopped.';
}

/// デコード対象が静止 JPEG/PNG/WebP でないことを表す例外。
class UnsupportedImageException implements Exception {
  /// 例外を作成する。
  /// @param message 利用者へ伝える理由
  const UnsupportedImageException(this.message);

  /// 利用者へ伝える理由。
  final String message;

  /// 例外を表示用の文字列へ変換する。
  /// @returns 利用者へ伝える理由
  @override
  String toString() => message;
}

/// `cjpeg` が JPEG を生成できなかったことを表す例外。
class MozJpegEncodingException implements Exception {
  /// 例外を作成する。
  /// @param message `cjpeg` の標準エラー出力を含む理由
  const MozJpegEncodingException(this.message);

  /// `cjpeg` の標準エラー出力を含む理由。
  final String message;

  /// 例外を表示用の文字列へ変換する。
  /// @returns `cjpeg` の失敗理由
  @override
  String toString() => message;
}

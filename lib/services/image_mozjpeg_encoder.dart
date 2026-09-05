import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'image_pipeline_types.dart';

/// バンドル済み MozJPEG の `cjpeg` を実行するエンコーダー。
/// Rust や FFI を介さず、標準入力の代わりに一時 PPM を明示的に渡す。
/// 大きい画像をパイプへ一括送信したときのバックプレッシャーを避けつつ、失敗時に再現しやすい入力を作る。
class MozJpegEncoder {
  /// エンコーダーを作成する。
  /// @param executable 実行する `cjpeg` のファイル
  const MozJpegEncoder(this.executable);

  /// 実行する `cjpeg` のファイル。
  final File executable;

  /// [rgbBytes] を progressive JPEG として [outputFile] へ生成する。
  /// [temporaryDirectory] は出力先と同じボリュームに置き、完成前のファイルをそこへ限定する。
  /// @param width 入力画像の横幅
  /// @param height 入力画像の高さ
  /// @param rgbBytes 左上から右下へ並ぶ 8bit RGB 配列
  /// @param quality JPEG の画質を 1 から 100 で指定する値
  /// @param outputFile ステージ済み JPEG の出力先
  /// @param temporaryDirectory PPM と ICC プロファイルを置く一時ディレクトリ
  /// @param iccProfileBytes 埋め込む ICC プロファイル (省略時は埋め込まない)
  /// @param onProgress エンコード進捗を 0.0 から 1.0 で受け取る処理
  Future<void> encode({
    required int width,
    required int height,
    required Uint8List rgbBytes,
    required int quality,
    required File outputFile,
    required Directory temporaryDirectory,
    Uint8List? iccProfileBytes,
    void Function(double progress)? onProgress,
  }) async {
    if (rgbBytes.lengthInBytes != width * height * 3) {
      throw ArgumentError.value(
        rgbBytes.lengthInBytes,
        'rgbBytes.lengthInBytes',
        'RGB data must contain exactly three bytes per pixel.',
      );
    }
    if (quality < 1 || quality > 100) {
      throw RangeError.range(quality, 1, 100, 'quality');
    }
    if (await executable.exists() == false) {
      throw MozJpegEncodingException('cjpeg executable was not found: ${executable.path}.');
    }

    final ppmFile = File('${temporaryDirectory.path}${Platform.pathSeparator}input.ppm');
    final iccFile = File('${temporaryDirectory.path}${Platform.pathSeparator}profile.icc');
    await _writePpm(ppmFile, width, height, rgbBytes);

    final arguments = <String>[
      '-report',
      '-quality',
      quality.toString(),
      '-progressive',
      '-optimize',
      '-outfile',
      outputFile.path,
    ];
    if (iccProfileBytes != null && iccProfileBytes.isNotEmpty) {
      await iccFile.writeAsBytes(iccProfileBytes, flush: true);
      arguments
        ..add('-icc')
        ..add(iccFile.path);
    }
    arguments.add(ppmFile.path);

    late final Process process;
    try {
      process = await Process.start(executable.path, arguments);
    } on ProcessException catch (error) {
      throw MozJpegEncodingException('Failed to start cjpeg: ${error.message}.');
    }
    // 改行でなく復帰文字で更新される進捗を分割し、診断メッセージだけを失敗理由として保持する
    final errorMessages = StringBuffer();
    final progressPattern = RegExp(r'^Pass\s+(\d+)/(\d+):\s*(\d+)%$');
    final singlePassPattern = RegExp(r'^(\d+)%$');
    var lastProgress = 0.0;
    final standardError = process.stderr.transform(utf8.decoder).transform(const LineSplitter()).forEach((line) {
      final message = line.trim();
      final match = progressPattern.firstMatch(message);
      final singlePassMatch = singlePassPattern.firstMatch(message);
      if (match != null || singlePassMatch != null) {
        final progress = match != null
            ? (int.parse(match[1]!) - 1 + int.parse(match[3]!) / 100) / int.parse(match[2]!)
            : int.parse(singlePassMatch![1]!) / 100;
        // MozJPEG は総パス数を途中で更新するため、表示済みの進捗を下限として扱う
        if (progress > lastProgress) {
          lastProgress = progress.clamp(0.0, 1.0);
          onProgress?.call(lastProgress);
        }
      } else if (message.isNotEmpty) {
        errorMessages.writeln(message);
      }
    });
    final standardOutput = process.stdout.drain<void>();

    final exitCode = await process.exitCode;
    await standardError;
    await standardOutput;
    final errorOutput = errorMessages.toString().trim();
    if (exitCode != 0) {
      throw MozJpegEncodingException(
        'cjpeg exited with code $exitCode.${errorOutput.isEmpty ? '' : '\n$errorOutput'}',
      );
    }
    if (await outputFile.exists() == false || await outputFile.length() == 0) {
      throw const MozJpegEncodingException('cjpeg completed without producing JPEG data.');
    }
    onProgress?.call(1.0);
  }

  /// RGB バイト列を加工せず `cjpeg` へ渡せる PPM P6 ファイルを書き込む。
  /// @param file 書き込み先の PPM ファイル
  /// @param width 画像の横幅
  /// @param height 画像の高さ
  /// @param rgbBytes 左上から右下へ並ぶ 8bit RGB 配列
  static Future<void> _writePpm(File file, int width, int height, Uint8List rgbBytes) async {
    final sink = file.openWrite();
    sink.add(ascii.encode('P6\n$width $height\n255\n'));
    sink.add(rgbBytes);
    await sink.flush();
    await sink.close();
  }
}

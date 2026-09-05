import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:image_squoosher/models/conversion_settings.dart';
import 'package:image_squoosher/services/image_conversion_pipeline.dart';
import 'package:image_squoosher/services/image_pipeline_types.dart';
import 'package:image_squoosher/services/squoosher_controller.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';

const _fileOperations = MethodChannel('net.tsukumijima.image-squoosher/finder_sync');

/// Windows の実ファイル操作を、再生成できる一時画像だけで検証する。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Windows の日時転送・連番・置換成功と失敗時の元画像保持を実 API で検証する',
    (tester) async {
      final directory = await Directory.systemTemp.createTemp('image-squoosher-windows-safety-');
      addTearDown(() async => directory.delete(recursive: true));
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('Windows file safety checks'))));
      await windowManager.ensureInitialized();
      await windowManager.show();

      final cjpeg = File(
        Platform.environment['IMAGE_SQUOOSHER_CJPEG'] ?? p.join('native', 'mozjpeg', 'windows', 'cjpeg.exe'),
      );
      expect(await cjpeg.exists(), isTrue, reason: 'The actual MozJPEG executable is required.');
      final source = image.Image(width: 64, height: 40);
      for (var y = 0; y < source.height; y += 1) {
        for (var x = 0; x < source.width; x += 1) {
          source.setPixelRgb(x, y, x * 3, y * 5, 80);
        }
      }
      final encodedImages = <String, List<int>>{
        'jpg': image.encodeJpg(source),
        'png': image.encodePng(source),
        'webp': image.encodeWebP(source),
      };
      const normalSettings = ConversionSettings(resizeEnabled: true, resizeValue: 32);
      const overwriteSettings = ConversionSettings(resizeEnabled: true, resizeValue: 16, overwrite: true);

      // 元画像と3回分の出力を保ち、連番と日時がすべて実ファイルへ反映されることを確認する
      for (final entry in encodedImages.entries) {
        final input = File(p.join(directory.path, '日本語 空白 ${entry.key}.${entry.key}'));
        await input.writeAsBytes(entry.value, flush: true);
        final sourceDates = await _fileDates(input, shouldSetDates: true);
        final outputSnapshots = <String, List<int>>{};
        for (var sequence = 0; sequence < 3; sequence += 1) {
          final result = await _compress(<File>[input], normalSettings);
          expect(result.failures, isEmpty);
          expect(result.completed, hasLength(1));
          final output = result.completed.single.outputFile;
          final suffix = sequence == 0 ? '' : ' ($sequence)';
          expect(p.basename(output.path), '日本語 空白 ${entry.key}_resized$suffix.jpg');
          await _expectJpegSize(output, width: 32, height: 20);
          expect(await _fileDates(output), sourceDates);
          expect(await input.readAsBytes(), entry.value);
          outputSnapshots[output.path] = await output.readAsBytes();
        }
        for (final snapshot in outputSnapshots.entries) {
          expect(await File(snapshot.key).readAsBytes(), snapshot.value);
        }
      }

      // JPEG の上書きは同じパスへ確定し、作成日時も検証済み出力から引き継ぐ
      final overwriteJpeg = File(p.join(directory.path, '上書き 元画像.jpg'));
      await overwriteJpeg.writeAsBytes(encodedImages['jpg']!, flush: true);
      final jpegDates = await _fileDates(overwriteJpeg, shouldSetDates: true);
      final jpegResult = await _compress(<File>[overwriteJpeg], overwriteSettings);
      expect(jpegResult.failures, isEmpty);
      expect(jpegResult.completed.single.outputFile.path, overwriteJpeg.path);
      await _expectJpegSize(overwriteJpeg, width: 16, height: 10);
      expect(await _fileDates(overwriteJpeg), jpegDates);

      // PNG と WebP は既存 JPEG を保持し、空いている連番への公開後にだけ元入力を除去する
      for (final extension in <String>['png', 'webp']) {
        final stem = '上書き $extension';
        final input = File(p.join(directory.path, '$stem.$extension'));
        final existingJpeg = File(p.join(directory.path, '$stem.jpg'));
        final existingSequence = File(p.join(directory.path, '$stem (1).jpg'));
        await input.writeAsBytes(encodedImages[extension]!, flush: true);
        await existingJpeg.writeAsBytes(encodedImages['jpg']!, flush: true);
        await existingSequence.writeAsBytes(encodedImages['jpg']!, flush: true);
        final dates = await _fileDates(input, shouldSetDates: true);
        final result = await _compress(<File>[input], overwriteSettings);
        expect(result.failures, isEmpty);
        expect(result.completed, hasLength(1));
        final output = result.completed.single.outputFile;
        expect(p.basename(output.path), '$stem (2).jpg');
        await _expectJpegSize(output, width: 16, height: 10);
        expect(await _fileDates(output), dates);
        expect(await input.exists(), isFalse);
        expect(await existingJpeg.readAsBytes(), encodedImages['jpg']);
        expect(await existingSequence.readAsBytes(), encodedImages['jpg']);
      }

      // 読み取り専用の一時 JPEG で Win32 の置換を失敗させ、元画像の内容と日時を確認する
      final protectedInput = File(p.join(directory.path, '読み取り専用 画像.jpg'));
      await protectedInput.writeAsBytes(encodedImages['jpg']!, flush: true);
      final protectedDates = await _fileDates(protectedInput, shouldSetDates: true);
      await _setReadOnly(protectedInput, isReadOnly: true);
      try {
        final result = await _compress(<File>[protectedInput], overwriteSettings);
        expect(result.completed, isEmpty);
        expect(result.failures, hasLength(1));
        expect(result.failures.single.error, isA<FileSystemException>());
        expect(await protectedInput.readAsBytes(), encodedImages['jpg']);
        expect(await _fileDates(protectedInput), protectedDates);
      } finally {
        await _setReadOnly(protectedInput, isReadOnly: false);
      }

      // 実チャネルの日時転送失敗を公開前に起こし、元 PNG と既存 JPEG の保持を確認する
      final dateFailureInput = File(p.join(directory.path, '日時失敗.png'));
      final dateFailureOutput = File(p.join(directory.path, '日時失敗.jpg'));
      await dateFailureInput.writeAsBytes(encodedImages['png']!, flush: true);
      await dateFailureOutput.writeAsBytes(encodedImages['jpg']!, flush: true);
      await expectLater(
        ImageConversionPipeline().convert(
          ImageConversionRequest(
            inputFile: dateFailureInput,
            outputFile: dateFailureOutput,
            cjpegExecutable: cjpeg,
            settings: overwriteSettings,
            finalizeStagedOutput: (_, stagedOutput) => _fileOperations.invokeMethod<void>(
              'copySourceFileDatesToOutputFile',
              <String, String>{
                'sourcePath': p.join(directory.path, '存在しない 元画像.png'),
                'outputPath': stagedOutput.path,
              },
            ),
          ),
        ),
        throwsA(isA<PlatformException>().having((error) => error.code, 'code', 'COPY_FILE_DATES_FAILED')),
      );
      expect(await dateFailureInput.readAsBytes(), encodedImages['png']);
      expect(await dateFailureOutput.readAsBytes(), encodedImages['jpg']);
      expect(
        await directory.list().where((entry) => p.basename(entry.path).startsWith('.image-squoosher-')).toList(),
        isEmpty,
      );
    },
    skip: !Platform.isWindows,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

/// 本番のバッチエンジンで、日時反映から元入力の除去まで通す。
/// @param inputs 一時ディレクトリ内の画像
/// @param settings 適用する変換条件
/// @returns 実エンジンによる完了と失敗の一覧
Future<ImageBatchConversionResult> _compress(List<File> inputs, ConversionSettings settings) {
  return PipelineCompressionEngine().compress(
    CompressionRequest(
      images: inputs.map((input) => QueuedImage(path: input.path)).toList(),
      settings: settings,
    ),
    stopToken: ImageConversionStopToken(),
    onItemStarted: (_) {},
    onItemCompleted: (_) {},
    onItemFailed: (_) {},
  );
}

/// JPEG の実デコードで確定した出力の寸法を確認する。
/// @param file 検証する出力ファイル
/// @param width 期待する横幅
/// @param height 期待する縦幅
Future<void> _expectJpegSize(File file, {required int width, required int height}) async {
  final decoded = image.decodeJpg(await file.readAsBytes());
  expect(decoded, isNotNull);
  expect(decoded!.width, width);
  expect(decoded.height, height);
}

/// Windows のファイル日時を100ns単位の文字列として取得する。
/// @param file 日時を取得するファイル
/// @param shouldSetDates true の場合は読み取り前に過去の日時を設定する
/// @returns 作成日時と更新日時の ticks
Future<({String creation, String modified})> _fileDates(File file, {bool shouldSetDates = false}) async {
  // パスは環境変数で渡し、引用符や日本語を含んでも PowerShell のコードと分離する
  final result = await Process.run(
    'powershell.exe',
    <String>[
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      r'''
$ErrorActionPreference = 'Stop'
$file = Get-Item -LiteralPath $env:IMAGE_SQUOOSHER_TEST_FILE -Force
if ($env:IMAGE_SQUOOSHER_TEST_SET_DATES -eq 'true') {
  $file.CreationTimeUtc = [DateTime]::new(2020, 1, 2, 3, 4, 5, [DateTimeKind]::Utc).AddTicks(1234567)
  $file.LastWriteTimeUtc = [DateTime]::new(2021, 2, 3, 4, 5, 6, [DateTimeKind]::Utc).AddTicks(7654321)
  $file.Refresh()
}
@{ creation = $file.CreationTimeUtc.Ticks.ToString(); modified = $file.LastWriteTimeUtc.Ticks.ToString() } | ConvertTo-Json -Compress
''',
    ],
    environment: <String, String>{
      'IMAGE_SQUOOSHER_TEST_FILE': file.path,
      'IMAGE_SQUOOSHER_TEST_SET_DATES': shouldSetDates.toString(),
    },
  );
  expect(result.exitCode, 0, reason: 'Could not inspect Windows file dates: ${result.stderr}');
  final value = jsonDecode((result.stdout as String).trim()) as Map<String, dynamic>;
  return (creation: value['creation'] as String, modified: value['modified'] as String);
}

/// 一時画像の読み取り専用属性を変更し、実際の置換失敗を作る。
/// @param file このテストで作成した JPEG
/// @param isReadOnly true で読み取り専用、false で通常属性へ戻す
Future<void> _setReadOnly(File file, {required bool isReadOnly}) async {
  final result = await Process.run('attrib.exe', <String>[isReadOnly ? '+R' : '-R', file.path]);
  expect(result.exitCode, 0, reason: 'Could not update the temporary file attribute: ${result.stderr}');
}

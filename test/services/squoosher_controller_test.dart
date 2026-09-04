import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:image_squoosher/models/conversion_settings.dart';
import 'package:image_squoosher/models/image_dimensions.dart';
import 'package:image_squoosher/services/image_pipeline_types.dart';
import 'package:image_squoosher/services/squoosher_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final cjpegPath =
      Platform.environment['IMAGE_SQUOOSHER_CJPEG'] ??
      '${Directory.current.path}${Platform.pathSeparator}native${Platform.pathSeparator}mozjpeg${Platform.pathSeparator}'
          '${Platform.isWindows ? 'windows${Platform.pathSeparator}cjpeg.exe' : 'macos${Platform.pathSeparator}arm64${Platform.pathSeparator}cjpeg'}';
  final canRunPipelineEngine = (Platform.isMacOS || Platform.isWindows) && File(cjpegPath).existsSync();

  group('SquoosherController', () {
    late Directory temporaryDirectory;

    setUp(() async {
      temporaryDirectory = await Directory.systemTemp.createTemp('image-squoosher-controller-test-');
    });

    tearDown(() async {
      await temporaryDirectory.delete(recursive: true);
    });

    test(
      'PNG と WebP の上書きは日時反映と JPEG 公開後だけ入力を削除する',
      () async {
        const fileDatesChannel = MethodChannel('net.tsukumijima.image-squoosher/finder_sync');
        final copiedDateSourcePaths = <String>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
          fileDatesChannel,
          (call) async {
            expect(call.method, 'copySourceFileDatesToOutputFile');
            final arguments = call.arguments! as Map<Object?, Object?>;
            final sourceFile = File(arguments['sourcePath']! as String);
            final stagedOutput = File(arguments['outputPath']! as String);
            expect(await sourceFile.exists(), isTrue);
            expect(await stagedOutput.exists(), isTrue);
            if (sourceFile.path.contains('failed')) {
              throw PlatformException(code: 'date-copy-failed');
            }
            copiedDateSourcePaths.add(sourceFile.path);
            await stagedOutput.setLastModified(await sourceFile.lastModified());
            return null;
          },
        );
        addTearDown(
          () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
            fileDatesChannel,
            null,
          ),
        );

        final engine = PipelineCompressionEngine();
        for (final source in <({String extension, List<int> bytes})>[
          (extension: 'png', bytes: image.encodePng(image.Image(width: 8, height: 6))),
          (extension: 'webp', bytes: image.encodeWebP(image.Image(width: 8, height: 6))),
        ]) {
          final inputFile = File('${temporaryDirectory.path}${Platform.pathSeparator}published.${source.extension}');
          final originalOutput = File('${temporaryDirectory.path}${Platform.pathSeparator}published.jpg');
          await inputFile.writeAsBytes(source.bytes, flush: true);
          await inputFile.setLastModified(DateTime.utc(2020, 1, 2, 3, 4, 5));
          await originalOutput.writeAsString('existing JPEG output', flush: true);

          final result = await engine.compress(
            CompressionRequest(
              images: <QueuedImage>[QueuedImage(path: inputFile.path)],
              settings: const ConversionSettings(overwrite: true),
            ),
            stopToken: ImageConversionStopToken(),
            onItemStarted: (_) {},
            onItemCompleted: (_) {},
            onItemFailed: (_) {},
          );

          final publishedOutput = File('${temporaryDirectory.path}${Platform.pathSeparator}published (1).jpg');
          expect(result.failures, isEmpty);
          expect(result.completed.single.outputFile.path, publishedOutput.path);
          expect(await inputFile.exists(), isFalse);
          expect(await originalOutput.readAsString(), 'existing JPEG output');
          expect(image.decodeJpg(await publishedOutput.readAsBytes()), isNotNull);
          expect(
            (await publishedOutput.lastModified()).difference(DateTime.utc(2020, 1, 2, 3, 4, 5)).abs(),
            lessThan(const Duration(seconds: 2)),
          );
          await publishedOutput.delete();
          await originalOutput.delete();
        }

        final failedInput = File('${temporaryDirectory.path}${Platform.pathSeparator}failed.webp');
        await failedInput.writeAsBytes(image.encodeWebP(image.Image(width: 8, height: 6)), flush: true);
        final failedResult = await engine.compress(
          CompressionRequest(
            images: <QueuedImage>[QueuedImage(path: failedInput.path)],
            settings: const ConversionSettings(overwrite: true),
          ),
          stopToken: ImageConversionStopToken(),
          onItemStarted: (_) {},
          onItemCompleted: (_) {},
          onItemFailed: (_) {},
        );

        expect(copiedDateSourcePaths, hasLength(2));
        expect(failedResult.completed, isEmpty);
        expect(failedResult.failures, hasLength(1));
        expect(await failedInput.exists(), isTrue);
        expect(await File('${temporaryDirectory.path}${Platform.pathSeparator}failed.jpg').exists(), isFalse);
      },
      skip: canRunPipelineEngine == false ? 'cjpeg is unavailable on this host.' : false,
    );

    test('個別失敗の後も後続の画像を変換する', () async {
      final inputFiles = <File>[
        File('${temporaryDirectory.path}${Platform.pathSeparator}first.png'),
        File('${temporaryDirectory.path}${Platform.pathSeparator}failed.png'),
        File('${temporaryDirectory.path}${Platform.pathSeparator}last.png'),
      ];
      for (final inputFile in inputFiles) {
        await inputFile.writeAsBytes(image.encodePng(image.Image(width: 8, height: 6)), flush: true);
      }
      final engine = _ScriptedCompressionEngine();
      final controller = SquoosherController(engine: engine);

      expect(controller.addFiles(inputFiles.map((inputFile) => inputFile.path)), 3);
      await _waitForImageDetails(controller);
      expect(await controller.compress(const ConversionSettings()), isTrue);

      expect(engine.startedPaths, inputFiles.map((inputFile) => inputFile.path));
      expect(
        controller.images.map((queuedImage) => queuedImage.status),
        <QueuedImageStatus>[
          QueuedImageStatus.completed,
          QueuedImageStatus.failed,
          QueuedImageStatus.completed,
        ],
      );
    });

    test('停止要求後は未開始の画像を停止済みとして残す', () async {
      final inputFiles = <File>[
        File('${temporaryDirectory.path}${Platform.pathSeparator}first.png'),
        File('${temporaryDirectory.path}${Platform.pathSeparator}last.png'),
      ];
      for (final inputFile in inputFiles) {
        await inputFile.writeAsBytes(image.encodePng(image.Image(width: 8, height: 6)), flush: true);
      }
      late SquoosherController controller;
      final engine = _ScriptedCompressionEngine(onFirstItemStarted: () => controller.requestStop());
      controller = SquoosherController(engine: engine);

      expect(controller.addFiles(inputFiles.map((inputFile) => inputFile.path)), 2);
      await _waitForImageDetails(controller);
      expect(await controller.compress(const ConversionSettings()), isTrue);

      expect(engine.startedPaths, <String>[inputFiles.first.path]);
      expect(controller.lastRunWasStopped, isTrue);
      expect(
        controller.images.map((queuedImage) => queuedImage.status),
        <QueuedImageStatus>[QueuedImageStatus.completed, QueuedImageStatus.stopped],
      );
    });

    test('Finder の選択は一覧を置き換え、通常追加は重複を除外する', () async {
      final inputFiles = <File>[
        File('${temporaryDirectory.path}${Platform.pathSeparator}first.png'),
        File('${temporaryDirectory.path}${Platform.pathSeparator}second.png'),
        File('${temporaryDirectory.path}${Platform.pathSeparator}finder.png'),
        File('${temporaryDirectory.path}${Platform.pathSeparator}added.png'),
      ];
      for (final inputFile in inputFiles) {
        await inputFile.writeAsBytes(image.encodePng(image.Image(width: 8, height: 6)), flush: true);
      }
      final controller = SquoosherController();

      expect(controller.addFiles(<String>[inputFiles[0].path, inputFiles[1].path, inputFiles[0].path]), 2);
      await _waitForImageDetails(controller);
      expect(controller.replaceFiles(<String>[inputFiles[2].path, inputFiles[2].path]), 1);
      await _waitForImageDetails(controller);
      expect(controller.images.map((queuedImage) => queuedImage.path), <String>[inputFiles[2].path]);
      expect(controller.addFiles(<String>[inputFiles[2].path, inputFiles[3].path, inputFiles[3].path]), 1);
      await _waitForImageDetails(controller);
      expect(controller.images.map((queuedImage) => queuedImage.path), <String>[
        inputFiles[2].path,
        inputFiles[3].path,
      ]);
    });

    test('遅れて完了した古い出力計画は最新の設定を上書きしない', () async {
      final inputFile = File('${temporaryDirectory.path}${Platform.pathSeparator}source.png');
      await inputFile.writeAsBytes(image.encodePng(image.Image(width: 8, height: 6)), flush: true);
      final oldPlanStarted = Completer<void>();
      final releaseOldPlan = Completer<Set<String>>();
      var readCount = 0;
      final controller = SquoosherController(
        existingPathsReader: (_) {
          readCount += 1;
          if (readCount == 1) {
            oldPlanStarted.complete();
            return releaseOldPlan.future;
          }
          return Future<Set<String>>.value(<String>{});
        },
      );

      expect(controller.addFiles(<String>[inputFile.path]), 1);
      await _waitForImageDetails(controller);
      final oldPlan = controller.updateOutputPlans(
        const ConversionSettings(suffix: '_old', resizeEnabled: true, resizeValue: 3),
      );
      await oldPlanStarted.future;
      await controller.updateOutputPlans(
        const ConversionSettings(suffix: '_latest', resizeEnabled: true, resizeValue: 4),
      );
      releaseOldPlan.complete(<String>{});
      await oldPlan;

      expect(
        controller.images.single.outputPath,
        '${temporaryDirectory.path}${Platform.pathSeparator}source_latest.jpg',
      );
      expect(controller.images.single.outputDimensions, const ImageDimensions(4, 3));
    });

    test('出力計画の待機中に一覧が変更されても現在の画像へ安全に適用する', () async {
      final mutationNames = <String>['remove', 'clear', 'replace'];
      for (final mutationName in mutationNames) {
        final inputFiles = <File>[
          File('${temporaryDirectory.path}${Platform.pathSeparator}$mutationName-first.png'),
          File('${temporaryDirectory.path}${Platform.pathSeparator}$mutationName-second.png'),
        ];
        for (final inputFile in inputFiles) {
          await inputFile.writeAsBytes(image.encodePng(image.Image(width: 8, height: 6)), flush: true);
        }
        final planStarted = Completer<void>();
        final releasePlan = Completer<Set<String>>();
        var isFirstRead = true;
        final controller = SquoosherController(
          existingPathsReader: (_) {
            if (isFirstRead) {
              isFirstRead = false;
              planStarted.complete();
              return releasePlan.future;
            }
            return Future<Set<String>>.value(<String>{});
          },
        );

        expect(controller.addFiles(inputFiles.map((inputFile) => inputFile.path)), 2);
        await _waitForImageDetails(controller);
        final planFuture = controller.updateOutputPlans(const ConversionSettings(suffix: '_planned'));
        await planStarted.future;

        switch (mutationName) {
          case 'remove':
            controller.removeFile(inputFiles.first.path);
          case 'clear':
            controller.clear();
          case 'replace':
            controller.replaceFiles(<String>[inputFiles.last.path]);
        }
        releasePlan.complete(<String>{});

        await expectLater(planFuture, completes);
        if (mutationName == 'replace') {
          await _waitForImageDetails(controller);
        }
        final expectedPaths = switch (mutationName) {
          'remove' => <String>[inputFiles.last.path],
          'clear' => <String>[],
          _ => <String>[inputFiles.last.path],
        };
        expect(controller.images.map((queuedImage) => queuedImage.path), expectedPaths);
        if (mutationName != 'clear') {
          final expectedOutputPath =
              '${temporaryDirectory.path}${Platform.pathSeparator}$mutationName-second_planned.jpg';
          for (var attempt = 0; attempt < 50; attempt += 1) {
            if (controller.images.single.outputPath == expectedOutputPath) {
              break;
            }
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
          expect(controller.images.single.outputPath, expectedOutputPath);
        }
        controller.dispose();
      }
    });

    test('出力計画の待機中に画像を外すと残った画像の出力名を再計画する', () async {
      final inputFiles = <File>[
        File('${temporaryDirectory.path}${Platform.pathSeparator}source.png'),
        File('${temporaryDirectory.path}${Platform.pathSeparator}source.jpg'),
      ];
      await inputFiles.first.writeAsBytes(image.encodePng(image.Image(width: 8, height: 6)), flush: true);
      await inputFiles.last.writeAsBytes(image.encodeJpg(image.Image(width: 8, height: 6)), flush: true);
      final planStarted = Completer<void>();
      final releasePlan = Completer<Set<String>>();
      var readCount = 0;
      final controller = SquoosherController(
        existingPathsReader: (_) {
          readCount += 1;
          if (readCount == 1) {
            planStarted.complete();
            return releasePlan.future;
          }
          return Future<Set<String>>.value(<String>{});
        },
      );

      expect(controller.addFiles(inputFiles.map((inputFile) => inputFile.path)), 2);
      await _waitForImageDetails(controller);
      final stalePlan = controller.updateOutputPlans(const ConversionSettings(suffix: '_planned'));
      await planStarted.future;
      controller.removeFile(inputFiles.first.path);
      releasePlan.complete(<String>{});
      await stalePlan;

      for (var attempt = 0; attempt < 50; attempt += 1) {
        if (controller.images.single.outputPath?.endsWith('source_planned.jpg') == true) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(
        controller.images.single.outputPath,
        '${temporaryDirectory.path}${Platform.pathSeparator}source_planned.jpg',
      );
    });

    test('出力計画の待機中に変更された行状態を計画結果で巻き戻さない', () async {
      final inputFile = File('${temporaryDirectory.path}${Platform.pathSeparator}source.png');
      await inputFile.writeAsBytes(image.encodePng(image.Image(width: 8, height: 6)), flush: true);
      final planStarted = Completer<void>();
      final releasePlan = Completer<Set<String>>();
      var readCount = 0;
      final controller = SquoosherController(
        engine: _ScriptedCompressionEngine(),
        existingPathsReader: (_) {
          readCount += 1;
          if (readCount == 2) {
            planStarted.complete();
            return releasePlan.future;
          }
          return Future<Set<String>>.value(<String>{});
        },
      );

      expect(controller.addFiles(<String>[inputFile.path]), 1);
      await _waitForImageDetails(controller);
      expect(await controller.compress(const ConversionSettings()), isTrue);
      expect(controller.images.single.status, QueuedImageStatus.completed);

      final plan = controller.updateOutputPlans(const ConversionSettings(suffix: '_planned'));
      await planStarted.future;
      controller.resetResults();
      releasePlan.complete(<String>{});
      await plan;

      expect(controller.images.single.status, QueuedImageStatus.queued);
      expect(
        controller.images.single.outputPath,
        '${temporaryDirectory.path}${Platform.pathSeparator}source_planned.jpg',
      );
    });
  });
}

/// キュー追加後の非同期詳細読み込みを待ち、テスト終了時まで入力ファイルを保持します。
Future<void> _waitForImageDetails(SquoosherController controller) async {
  for (var attempt = 0; attempt < 50; attempt += 1) {
    if (controller.images.every((queuedImage) => queuedImage.sourceDimensions != null)) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  throw StateError('Image details were not loaded before the test timed out.');
}

/// コントローラーの行状態を個別に通知できるテスト用変換器です。
class _ScriptedCompressionEngine implements ImageCompressionEngine {
  _ScriptedCompressionEngine({this.onFirstItemStarted});

  /// 1件目の開始直後に停止要求を注入するコールバックです。
  final void Function()? onFirstItemStarted;

  /// 開始済みとして通知した入力パスを順番に記録します。
  final List<String> startedPaths = <String>[];

  /// テストで指定した順番に完了・失敗・停止をコントローラーへ通知します。
  @override
  Future<ImageBatchConversionResult> compress(
    CompressionRequest request, {
    required ImageConversionStopToken stopToken,
    required ValueChanged<QueuedImage> onItemStarted,
    required FutureOr<void> Function(ImageConversionResult) onItemCompleted,
    required ValueChanged<ImageConversionFailure> onItemFailed,
  }) async {
    final completed = <ImageConversionResult>[];
    final failures = <ImageConversionFailure>[];
    for (final queuedImage in request.images) {
      if (stopToken.isRequested) {
        return ImageBatchConversionResult(completed: completed, failures: failures, wasStopped: true);
      }
      startedPaths.add(queuedImage.path);
      onItemStarted(queuedImage);
      if (startedPaths.length == 1) {
        onFirstItemStarted?.call();
      }
      if (queuedImage.path.contains('failed')) {
        final failure = ImageConversionFailure(
          inputFile: File(queuedImage.path),
          error: StateError('Test item failure.'),
          stackTrace: StackTrace.current,
        );
        failures.add(failure);
        onItemFailed(failure);
      } else {
        final outputFile = File('${queuedImage.path}.output.jpg');
        await outputFile.writeAsBytes(<int>[0xFF, 0xD8, 0xFF, 0xD9], flush: true);
        final result = ImageConversionResult(
          inputFile: File(queuedImage.path),
          outputFile: outputFile,
          sourceFormat: SourceImageFormat.png,
          sourceWidth: 8,
          sourceHeight: 6,
          cropRect: const CropRect(left: 0, top: 0, width: 8, height: 6),
          outputWidth: 8,
          outputHeight: 6,
        );
        completed.add(result);
        await onItemCompleted(result);
      }
    }
    return ImageBatchConversionResult(
      completed: completed,
      failures: failures,
      wasStopped: stopToken.isRequested,
    );
  }
}

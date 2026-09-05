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

    test(
      '上書きで元入力を削除した結果は設定変更とリセット後も保持し、JPEG は再実行できる',
      () async {
        const fileDatesChannel = MethodChannel('net.tsukumijima.image-squoosher/finder_sync');
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
          fileDatesChannel,
          (_) async => null,
        );
        addTearDown(
          () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
            fileDatesChannel,
            null,
          ),
        );

        // 実変換で削除される形式と元パスが残る JPEG を同じキューで比較する
        final inputFiles = <File>[];
        for (final source in <({String extension, List<int> bytes})>[
          (extension: 'png', bytes: image.encodePng(image.Image(width: 8, height: 6))),
          (extension: 'webp', bytes: image.encodeWebP(image.Image(width: 8, height: 6))),
          (extension: 'jpg', bytes: image.encodeJpg(image.Image(width: 8, height: 6))),
        ]) {
          final inputFile = File(
            '${temporaryDirectory.path}${Platform.pathSeparator}source-${source.extension}.${source.extension}',
          );
          await inputFile.writeAsBytes(source.bytes, flush: true);
          inputFiles.add(inputFile);
        }
        final controller = SquoosherController();
        addTearDown(controller.dispose);
        controller.addFiles(inputFiles.map((inputFile) => inputFile.path));
        await _waitForImageDetails(controller);
        expect(await controller.compress(const ConversionSettings(overwrite: true)), isTrue);
        expect(controller.completedCount, 3);
        final replacedImages = controller.images.take(2).toList();
        for (final replacedImage in replacedImages) {
          expect(await File(replacedImage.path).exists(), isFalse);
          expect(replacedImage.isInputValid, isFalse);
          expect(image.decodeJpg(await File(replacedImage.outputPath!).readAsBytes()), isNotNull);
        }

        // リセットと設定変更の両方で、再入力できる JPEG だけを待機へ戻す
        controller.resetResults();
        for (var index = 0; index < replacedImages.length; index += 1) {
          expect(controller.images[index], same(replacedImages[index]));
        }
        expect(controller.images.last.status, QueuedImageStatus.queued);
        const changedSettings = ConversionSettings(quality: 75, suffix: '_changed');
        await controller.updateOutputPlans(changedSettings);
        for (var index = 0; index < replacedImages.length; index += 1) {
          expect(controller.images[index], same(replacedImages[index]));
        }
        expect(await controller.compress(changedSettings), isTrue);
        expect(controller.completedCount, 3);
        expect(controller.failedCount, 0);
        expect(controller.hasPendingImages, isFalse);
        expect(controller.images.last.outputPath, endsWith('source-jpg_changed.jpg'));
      },
      skip: canRunPipelineEngine == false ? 'cjpeg is unavailable on this host.' : false,
    );

    test(
      'JPEG の上書き結果は変換前の寸法を保持し、再設定時は保存済みの寸法とサイズを使う',
      () async {
        // 日時反映の OS 境界を置き換え、同梱した cjpeg で実際の JPEG 上書きを確認する
        const fileDatesChannel = MethodChannel('net.tsukumijima.image-squoosher/finder_sync');
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
          fileDatesChannel,
          (_) async => null,
        );
        addTearDown(
          () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
            fileDatesChannel,
            null,
          ),
        );

        final inputFile = File('${temporaryDirectory.path}${Platform.pathSeparator}resized.jpg');
        await inputFile.writeAsBytes(image.encodeJpg(image.Image(width: 80, height: 60)), flush: true);
        final originalByteLength = await inputFile.length();
        final controller = SquoosherController();
        addTearDown(controller.dispose);
        controller.addFiles(<String>[inputFile.path]);
        await _waitForImageDetails(controller);

        // 完了行には圧縮前後の比較に使う元寸法と元サイズを残す
        expect(
          await controller.compress(const ConversionSettings(overwrite: true, resizeEnabled: true, resizeValue: 40)),
          isTrue,
        );
        final completedImage = controller.images.single;
        final savedBytes = await inputFile.readAsBytes();
        final savedImage = image.decodeJpg(savedBytes)!;
        expect(completedImage.status, QueuedImageStatus.completed);
        expect(completedImage.outputPath, inputFile.path);
        expect(completedImage.sourceDimensions, const ImageDimensions(80, 60));
        expect(completedImage.byteLength, originalByteLength);
        expect(ImageDimensions(savedImage.width, savedImage.height), const ImageDimensions(40, 30));
        expect(completedImage.outputDimensions, const ImageDimensions(40, 30));
        expect(completedImage.outputByteLength, savedBytes.length);

        // 再設定後の入力情報と出力計画は、現在のファイルへ更新する
        await controller.updateOutputPlans(const ConversionSettings(overwrite: true));
        final queuedImage = controller.images.single;
        expect(queuedImage.status, QueuedImageStatus.queued);
        expect(queuedImage.sourceDimensions, const ImageDimensions(40, 30));
        expect(queuedImage.byteLength, savedBytes.length);
        expect(queuedImage.outputDimensions, const ImageDimensions(40, 30));
        expect(await inputFile.readAsBytes(), savedBytes);
      },
      skip: canRunPipelineEngine == false ? 'cjpeg is unavailable on this host.' : false,
    );

    test('完了後の再実行と同じ設定の再計画は生成済みの結果を保持する', () async {
      final inputFile = File('${temporaryDirectory.path}${Platform.pathSeparator}source.png');
      await inputFile.writeAsBytes(image.encodePng(image.Image(width: 8, height: 6)), flush: true);
      final engine = _ScriptedCompressionEngine();
      final controller = SquoosherController(engine: engine);
      addTearDown(controller.dispose);
      controller.addFiles(<String>[inputFile.path]);
      await _waitForImageDetails(controller);
      await controller.compress(const ConversionSettings());
      final completedImage = controller.images.single;

      // 言語変更で設定オブジェクトが作り直されても、生成済みの結果は同じ行へ残る
      await controller.updateOutputPlans(ConversionSettings());
      expect(controller.hasPendingImages, isFalse);
      expect(await controller.compress(const ConversionSettings()), isFalse);
      expect(engine.startedPaths, <String>[inputFile.path]);
      expect(controller.images.single.outputPath, completedImage.outputPath);
      expect(controller.images.single.outputDimensions, completedImage.outputDimensions);
      expect(controller.images.single.outputByteLength, completedImage.outputByteLength);
      expect(controller.images.single.status, QueuedImageStatus.completed);

      // 変換値の変更後は新しい出力計画と待機状態を表示する
      await controller.updateOutputPlans(const ConversionSettings(quality: 75));
      expect(controller.hasPendingImages, isTrue);
      expect(controller.images.single.status, QueuedImageStatus.queued);
      expect(controller.images.single.outputByteLength, isNull);
      expect(await controller.compress(const ConversionSettings(quality: 75)), isTrue);
      expect(engine.startedPaths, <String>[inputFile.path, inputFile.path]);
    });

    test('完了済み画像に追加した画像だけを変換し、既存の出力情報を保持する', () async {
      final inputFiles = <File>[
        File('${temporaryDirectory.path}${Platform.pathSeparator}first.png'),
        File('${temporaryDirectory.path}${Platform.pathSeparator}added.png'),
      ];
      for (final inputFile in inputFiles) {
        await inputFile.writeAsBytes(image.encodePng(image.Image(width: 8, height: 6)), flush: true);
      }
      final engine = _ScriptedCompressionEngine();
      final controller = SquoosherController(engine: engine);
      addTearDown(controller.dispose);
      controller.addFiles(<String>[inputFiles.first.path]);
      await _waitForImageDetails(controller);
      await controller.compress(const ConversionSettings());
      final completedImage = controller.images.first;

      controller.addFiles(<String>[inputFiles.last.path]);
      await _waitForImageDetails(controller);
      await controller.updateOutputPlans(const ConversionSettings());
      expect(controller.hasPendingImages, isTrue);
      await controller.compress(const ConversionSettings());

      expect(engine.startedPaths, inputFiles.map((inputFile) => inputFile.path));
      expect(controller.images.first.outputPath, completedImage.outputPath);
      expect(controller.images.first.outputDimensions, completedImage.outputDimensions);
      expect(controller.images.first.outputByteLength, completedImage.outputByteLength);
      expect(controller.completedCount, 2);
      expect(controller.hasPendingImages, isFalse);
    });

    test('変換中の設定変更は開始時の出力計画を保持する', () async {
      final inputFile = File('${temporaryDirectory.path}${Platform.pathSeparator}source.png');
      await inputFile.writeAsBytes(image.encodePng(image.Image(width: 8, height: 6)), flush: true);
      late SquoosherController controller;
      final engine = _ScriptedCompressionEngine(
        onFirstItemStarted: () {
          unawaited(controller.updateOutputPlans(const ConversionSettings(suffix: '_changed')));
          expect(controller.images.single.outputPath, endsWith('source_resized.jpg'));
          expect(controller.images.single.status, QueuedImageStatus.processing);
        },
      );
      controller = SquoosherController(engine: engine);
      addTearDown(controller.dispose);
      controller.addFiles(<String>[inputFile.path]);
      await _waitForImageDetails(controller);
      await controller.compress(const ConversionSettings());
      final outputPath = controller.images.single.outputPath;
      await controller.updateOutputPlans(const ConversionSettings());
      expect(controller.images.single.status, QueuedImageStatus.completed);
      expect(controller.images.single.outputPath, outputPath);
    });

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
      expect(controller.hasPendingImages, isTrue);
      await controller.compress(const ConversionSettings());
      expect(engine.startedPaths, <String>[
        ...inputFiles.map((inputFile) => inputFile.path),
        inputFiles[1].path,
      ]);
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
      await controller.compress(const ConversionSettings());
      expect(engine.startedPaths, inputFiles.map((inputFile) => inputFile.path));
      expect(controller.completedCount, 2);
    });

    test('出力計画で失敗しても処理状態を戻し、設定を直せば再実行できる', () async {
      final inputFile = File('${temporaryDirectory.path}${Platform.pathSeparator}invalid-settings.png');
      await inputFile.writeAsBytes(image.encodePng(image.Image(width: 8, height: 6)), flush: true);
      final controller = SquoosherController(engine: _ScriptedCompressionEngine());
      addTearDown(controller.dispose);

      expect(controller.addFiles(<String>[inputFile.path]), 1);
      await _waitForImageDetails(controller);

      await expectLater(
        controller.compress(const ConversionSettings(suffix: '/')),
        throwsA(isA<ArgumentError>()),
      );
      expect(controller.isCompressing, isFalse);
      expect(controller.isStopping, isFalse);

      expect(await controller.compress(const ConversionSettings()), isTrue);
      expect(controller.images.single.status, QueuedImageStatus.completed);
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

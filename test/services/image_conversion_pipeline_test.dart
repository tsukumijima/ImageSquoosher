import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:image_squoosher/models/aspect_ratio.dart';
import 'package:image_squoosher/models/conversion_settings.dart';
import 'package:image_squoosher/models/image_dimensions.dart';
import 'package:image_squoosher/services/image_conversion_pipeline.dart';
import 'package:image_squoosher/services/image_metadata.dart';
import 'package:image_squoosher/services/image_pipeline_types.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const fileOperationsChannel = MethodChannel('net.tsukumijima.image-squoosher/finder_sync');
  const sRgbIccProfilePath = '/System/Library/ColorSync/Profiles/sRGB Profile.icc';
  // 既定では配布物と同じ MozJPEG 4.1.1 のリポジトリ内ビルドを使い、配布検証時だけ環境変数の実行ファイルへ差し替える
  final repositoryCjpegPath = Platform.isWindows
      ? 'native/mozjpeg/windows/cjpeg.exe'
      : 'native/mozjpeg/macos/arm64/cjpeg';
  final cjpeg = File(Platform.environment['IMAGE_SQUOOSHER_CJPEG'] ?? repositoryCjpegPath);
  final canRunCjpeg = cjpeg.existsSync();
  final sRgbIccProfile = File(sRgbIccProfilePath);
  final canRunMetadataTests = canRunCjpeg && sRgbIccProfile.existsSync();

  setUpAll(() {
    if (Platform.isWindows == false) {
      return;
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      fileOperationsChannel,
      (call) async {
        if (call.method != 'replaceStagedOutputAtomically') {
          return null;
        }
        final arguments = call.arguments! as Map<Object?, Object?>;
        final stagedOutput = File(arguments['stagedOutputPath']! as String);
        final outputFile = File(arguments['outputPath']! as String);
        if (await outputFile.exists()) {
          await outputFile.delete();
        }
        await stagedOutput.rename(outputFile.path);
        return null;
      },
    );
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      fileOperationsChannel,
      null,
    );
  });

  group('ImageConversionPipeline', () {
    late Directory temporaryDirectory;

    setUp(() async {
      temporaryDirectory = await Directory.systemTemp.createTemp(
        'image-squoosher-pipeline-test-',
      );
    });

    tearDown(() async {
      await temporaryDirectory.delete(recursive: true);
    });

    test(
      'JPEG、PNG、WebP の静止画を中央クロップして JPEG へ変換する',
      () async {
        final source = image.Image(width: 12, height: 8, numChannels: 4);
        for (var y = 0; y < source.height; y += 1) {
          for (var x = 0; x < source.width; x += 1) {
            source.setPixelRgba(x, y, x * 20, y * 30, 80, 255);
          }
        }
        final sourceFiles = <({String extension, Uint8List bytes, SourceImageFormat format})>[
          (extension: 'jpg', bytes: image.encodeJpg(source), format: SourceImageFormat.jpeg),
          (extension: 'png', bytes: image.encodePng(source), format: SourceImageFormat.png),
          (extension: 'webp', bytes: image.encodeWebP(source), format: SourceImageFormat.webp),
        ];

        for (final sourceFile in sourceFiles) {
          final inputFile = File(
            '${temporaryDirectory.path}${Platform.pathSeparator}input.${sourceFile.extension}',
          );
          final outputFile = File(
            '${temporaryDirectory.path}${Platform.pathSeparator}output-${sourceFile.extension}.jpg',
          );
          await inputFile.writeAsBytes(sourceFile.bytes, flush: true);

          final result = await ImageConversionPipeline().convert(
            ImageConversionRequest(
              inputFile: inputFile,
              outputFile: outputFile,
              cjpegExecutable: cjpeg,
              settings: const ConversionSettings(
                resizeEnabled: true,
                resizeValue: 6,
              ),
            ),
          );
          final output = image.decodeJpg(await outputFile.readAsBytes());

          expect(result.sourceFormat, sourceFile.format);
          expect(result.cropRect, const CropRect(left: 0, top: 0, width: 12, height: 8));
          expect(result.outputWidth, 6);
          expect(result.outputHeight, 4);
          expect(output, isNotNull);
          expect(output!.width, 6);
          expect(output.height, 4);
        }
      },
      skip: canRunCjpeg == false ? 'cjpeg is unavailable on this host.' : false,
    );

    test(
      'EXIF Orientation 1〜8 を画素へ反映し、元の日時を出力へ引き継ぐ',
      () async {
        final sourceModifiedAt = DateTime.utc(2020, 1, 2, 3, 4, 5);
        for (var orientation = 1; orientation <= 8; orientation += 1) {
          final inputFile = File('${temporaryDirectory.path}${Platform.pathSeparator}orientation-$orientation.jpg');
          final outputFile = File(
            '${temporaryDirectory.path}${Platform.pathSeparator}orientation-$orientation-output.jpg',
          );
          await inputFile.writeAsBytes(
            _jpegWithOrientation(image.encodeJpg(_orientationPatternImage(), quality: 100), orientation),
            flush: true,
          );
          await inputFile.setLastModified(sourceModifiedAt);

          final result = await ImageConversionPipeline().convert(
            ImageConversionRequest(
              inputFile: inputFile,
              outputFile: outputFile,
              cjpegExecutable: cjpeg,
              settings: const ConversionSettings(quality: 100),
            ),
          );
          final output = image.decodeJpg(await outputFile.readAsBytes());
          final expectedGrid = _orientationColorGrid(orientation);
          final expectedWidth = orientation >= 5 ? 48 : 72;
          final expectedHeight = orientation >= 5 ? 72 : 48;

          expect(result.sourceWidth, expectedWidth);
          expect(result.sourceHeight, expectedHeight);
          expect(result.cropRect, CropRect(left: 0, top: 0, width: expectedWidth, height: expectedHeight));
          expect(output, isNotNull);
          for (var row = 0; row < expectedGrid.length; row += 1) {
            for (var column = 0; column < expectedGrid[row].length; column += 1) {
              final pixel = output!.getPixel(column * 24 + 12, row * 24 + 12);
              expect(
                _closestOrientationColor(pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()),
                expectedGrid[row][column],
                reason: 'Orientation $orientation at ($column, $row)',
              );
            }
          }

          final outputMetadata = ImageMetadataTransfer.collect(
            await outputFile.readAsBytes(),
            SourceImageFormat.jpeg,
          );
          final outputExif = outputMetadata.firstWhere(
            (segment) => segment.marker == 0xE1 && segment.data[0] == 0x45,
          );
          expect(outputExif.data[24], 1);
          expect(outputExif.data[25], 0);
          expect(
            (await outputFile.stat()).modified.difference(sourceModifiedAt).abs(),
            lessThan(const Duration(seconds: 2)),
          );
        }
      },
      skip: canRunCjpeg == false ? 'cjpeg is unavailable on this host.' : false,
    );

    test(
      'ICC はメタデータ削除の指定にかかわらず維持し、削除指定では撮影メタデータを除去する',
      () async {
        final source = image.Image(width: 48, height: 48);
        for (var y = 0; y < source.height; y += 1) {
          for (var x = 0; x < source.width; x += 1) {
            source.setPixelRgb(x, y, x * 5, y * 5, 80);
          }
        }
        final iccProfileBytes = await sRgbIccProfile.readAsBytes();
        source.iccProfile = image.IccProfile(
          'sRGB',
          image.IccProfileCompression.none,
          iccProfileBytes,
        );
        final inputFile = File('${temporaryDirectory.path}${Platform.pathSeparator}metadata-source.jpg');
        await inputFile.writeAsBytes(
          _jpegWithMetadata(image.encodeJpg(source, quality: 100)),
          flush: true,
        );

        for (final stripMetadata in <bool>[false, true]) {
          final outputFile = File(
            '${temporaryDirectory.path}${Platform.pathSeparator}metadata-$stripMetadata.jpg',
          );
          await ImageConversionPipeline().convert(
            ImageConversionRequest(
              inputFile: inputFile,
              outputFile: outputFile,
              cjpegExecutable: cjpeg,
              settings: ConversionSettings(quality: 100, stripMetadata: stripMetadata),
            ),
          );
          final outputBytes = await outputFile.readAsBytes();

          expect(_iccProfileFromJpeg(outputBytes), orderedEquals(iccProfileBytes));
          if (stripMetadata) {
            final outputSegments = _jpegHeaderSegments(outputBytes);
            expect(
              outputSegments.where((segment) => _hasPrefix(segment.data, _exifHeader)),
              isEmpty,
            );
            expect(
              outputSegments.where((segment) => _hasPrefix(segment.data, _xmpHeader)),
              isEmpty,
            );
            expect(
              outputSegments.where((segment) => _hasPrefix(segment.data, _photoshopHeader)),
              isEmpty,
            );
            expect(outputSegments.where((segment) => segment.marker == 0xFE), isEmpty);
          }
        }
      },
      skip: canRunMetadataTests == false ? 'cjpeg or the macOS sRGB ICC profile is unavailable on this host.' : false,
    );

    test(
      '逐次バッチは個別失敗後に残りを変換し、停止後は残りを開始しない',
      () async {
        final firstInput = File('${temporaryDirectory.path}${Platform.pathSeparator}first.png');
        final invalidInput = File('${temporaryDirectory.path}${Platform.pathSeparator}invalid.png');
        final lastInput = File('${temporaryDirectory.path}${Platform.pathSeparator}last.png');
        await firstInput.writeAsBytes(image.encodePng(image.Image(width: 24, height: 24)), flush: true);
        await invalidInput.writeAsBytes(Uint8List.fromList(<int>[0x00, 0x01, 0x02]), flush: true);
        await lastInput.writeAsBytes(image.encodePng(image.Image(width: 24, height: 24)), flush: true);
        final firstOutput = File('${temporaryDirectory.path}${Platform.pathSeparator}first.jpg');
        final invalidOutput = File('${temporaryDirectory.path}${Platform.pathSeparator}invalid.jpg');
        final lastOutput = File('${temporaryDirectory.path}${Platform.pathSeparator}last.jpg');

        final partialFailureResult = await ImageConversionPipeline().convertSequentially(<ImageConversionRequest>[
          _conversionRequest(firstInput, firstOutput, cjpeg),
          _conversionRequest(invalidInput, invalidOutput, cjpeg),
          _conversionRequest(lastInput, lastOutput, cjpeg),
        ]);

        expect(partialFailureResult.wasStopped, isFalse);
        expect(partialFailureResult.completed.map((result) => result.inputFile.path), <String>[
          firstInput.path,
          lastInput.path,
        ]);
        expect(partialFailureResult.failures, hasLength(1));
        expect(partialFailureResult.failures.single.inputFile.path, invalidInput.path);
        expect(image.decodeJpg(await firstOutput.readAsBytes()), isNotNull);
        expect(await invalidOutput.exists(), isFalse);
        expect(image.decodeJpg(await lastOutput.readAsBytes()), isNotNull);

        final stopToken = ImageConversionStopToken();
        final stoppedFirstInput = File('${temporaryDirectory.path}${Platform.pathSeparator}stopped-first.png');
        final stoppedLastInput = File('${temporaryDirectory.path}${Platform.pathSeparator}stopped-last.png');
        await stoppedFirstInput.writeAsBytes(image.encodePng(image.Image(width: 24, height: 24)), flush: true);
        await stoppedLastInput.writeAsBytes(image.encodePng(image.Image(width: 24, height: 24)), flush: true);
        final stoppedFirstOutput = File('${temporaryDirectory.path}${Platform.pathSeparator}stopped-first.jpg');
        final stoppedLastOutput = File('${temporaryDirectory.path}${Platform.pathSeparator}stopped-last.jpg');
        var didRequestStop = false;

        final stoppedResult = await ImageConversionPipeline().convertSequentially(
          <ImageConversionRequest>[
            ImageConversionRequest(
              inputFile: stoppedFirstInput,
              outputFile: stoppedFirstOutput,
              cjpegExecutable: cjpeg,
              settings: const ConversionSettings(),
              finalizeStagedOutput: (_, _) async {
                stopToken.requestStop();
                didRequestStop = true;
              },
            ),
            _conversionRequest(stoppedLastInput, stoppedLastOutput, cjpeg),
          ],
          stopToken: stopToken,
        );

        expect(stoppedResult.failures, isEmpty);
        expect(didRequestStop, isTrue);
        expect(stopToken.isRequested, isTrue);
        expect(stoppedResult.wasStopped, isTrue);
        expect(stoppedResult.completed.map((result) => result.inputFile.path), <String>[stoppedFirstInput.path]);
        expect(await stoppedFirstOutput.exists(), isTrue);
        expect(await stoppedLastOutput.exists(), isFalse);
      },
      skip: canRunCjpeg == false ? 'cjpeg is unavailable on this host.' : false,
    );

    test(
      '不透明 PNG は元の 8bit RGB を cjpeg へ渡す',
      () async {
        final source = image.Image(width: 16, height: 16);
        final sourceRgbBytes = Uint8List(source.width * source.height * 3);
        var offset = 0;
        for (var y = 0; y < source.height; y += 1) {
          for (var x = 0; x < source.width; x += 1) {
            final red = (x * 17) % 256;
            final green = (y * 19) % 256;
            final blue = ((x + y) * 13) % 256;
            source.setPixelRgb(x, y, red, green, blue);
            sourceRgbBytes[offset] = red;
            sourceRgbBytes[offset + 1] = green;
            sourceRgbBytes[offset + 2] = blue;
            offset += 3;
          }
        }
        final inputFile = File('${temporaryDirectory.path}${Platform.pathSeparator}opaque.png');
        final outputFile = File('${temporaryDirectory.path}${Platform.pathSeparator}opaque.jpg');
        await inputFile.writeAsBytes(image.encodePng(source), flush: true);

        await ImageConversionPipeline().convert(
          ImageConversionRequest(
            inputFile: inputFile,
            outputFile: outputFile,
            cjpegExecutable: cjpeg,
            settings: const ConversionSettings(),
          ),
        );

        expect(
          await outputFile.readAsBytes(),
          orderedEquals(
            await _encodePpmWithCjpeg(
              cjpegExecutable: cjpeg,
              temporaryDirectory: temporaryDirectory,
              fileName: 'opaque-reference',
              width: source.width,
              height: source.height,
              rgbBytes: sourceRgbBytes,
              quality: 90,
            ),
          ),
        );
      },
      skip: canRunCjpeg == false ? 'cjpeg is unavailable on this host.' : false,
    );

    test(
      '透過 PNG は白背景の 8bit RGB を cjpeg へ渡す',
      () async {
        final source = image.Image(width: 4, height: 4, numChannels: 4);
        for (var y = 0; y < source.height; y += 1) {
          for (var x = 0; x < source.width; x += 1) {
            source.setPixelRgba(x, y, 255, 0, 0, 0);
          }
        }
        final inputFile = File('${temporaryDirectory.path}${Platform.pathSeparator}transparent.png');
        final outputFile = File('${temporaryDirectory.path}${Platform.pathSeparator}transparent.jpg');
        await inputFile.writeAsBytes(image.encodePng(source), flush: true);

        await ImageConversionPipeline().convert(
          ImageConversionRequest(
            inputFile: inputFile,
            outputFile: outputFile,
            cjpegExecutable: cjpeg,
            settings: const ConversionSettings(),
          ),
        );
        final output = image.decodeJpg(await outputFile.readAsBytes());
        final pixel = output!.getPixel(2, 2);

        expect(await inputFile.exists(), isTrue);
        expect(
          await outputFile.readAsBytes(),
          orderedEquals(
            await _encodePpmWithCjpeg(
              cjpegExecutable: cjpeg,
              temporaryDirectory: temporaryDirectory,
              fileName: 'transparent-reference',
              width: source.width,
              height: source.height,
              rgbBytes: Uint8List.fromList(List<int>.filled(source.width * source.height * 3, 255)),
              quality: 90,
            ),
          ),
        );
        expect(pixel.r, greaterThan(245));
        expect(pixel.g, greaterThan(245));
        expect(pixel.b, greaterThan(245));
      },
      skip: canRunCjpeg == false ? 'cjpeg is unavailable on this host.' : false,
    );

    test(
      'JPEG 上書きでは入力が残っている間にステージ済み出力を確定する',
      () async {
        final inputFile = File('${temporaryDirectory.path}${Platform.pathSeparator}overwrite.jpg');
        await inputFile.writeAsBytes(image.encodeJpg(image.Image(width: 4, height: 4)), flush: true);
        var didFinalizeStagedOutput = false;

        await ImageConversionPipeline().convert(
          ImageConversionRequest(
            inputFile: inputFile,
            outputFile: inputFile,
            cjpegExecutable: cjpeg,
            settings: const ConversionSettings(overwrite: true),
            finalizeStagedOutput: (sourceFile, stagedOutput) async {
              expect(await sourceFile.exists(), isTrue);
              expect(await stagedOutput.exists(), isTrue);
              expect(sourceFile.path, inputFile.path);
              expect(stagedOutput.path, isNot(inputFile.path));
              didFinalizeStagedOutput = true;
            },
          ),
        );

        expect(didFinalizeStagedOutput, isTrue);
        expect(image.decodeJpg(await inputFile.readAsBytes()), isNotNull);
      },
      skip: canRunCjpeg == false ? 'cjpeg is unavailable on this host.' : false,
    );

    test(
      'JPEG 上書きの置換に失敗したときは元画像を残す',
      () async {
        final inputFile = File('${temporaryDirectory.path}${Platform.pathSeparator}replace-failure.jpg');
        final originalBytes = Uint8List.fromList(image.encodeJpg(image.Image(width: 4, height: 4)));
        await inputFile.writeAsBytes(originalBytes, flush: true);
        var didAttemptReplacement = false;

        await expectLater(
          ImageConversionPipeline(
            replaceStagedOutput: (stagedOutput, outputFile) async {
              expect(await inputFile.exists(), isTrue);
              expect(await stagedOutput.exists(), isTrue);
              expect(outputFile.path, inputFile.path);
              didAttemptReplacement = true;
              throw FileSystemException('Native file replacement failed.', outputFile.path);
            },
          ).convert(
            ImageConversionRequest(
              inputFile: inputFile,
              outputFile: inputFile,
              cjpegExecutable: cjpeg,
              settings: const ConversionSettings(overwrite: true),
            ),
          ),
          throwsA(isA<FileSystemException>()),
        );

        expect(didAttemptReplacement, isTrue);
        expect(await inputFile.readAsBytes(), orderedEquals(originalBytes));
      },
      skip: canRunCjpeg == false ? 'cjpeg is unavailable on this host.' : false,
    );

    test(
      '新規 JPEG の公開直前に同名ファイルが作られたときはその内容を残す',
      () async {
        final inputFile = File('${temporaryDirectory.path}${Platform.pathSeparator}exclusive-source.png');
        final outputFile = File('${temporaryDirectory.path}${Platform.pathSeparator}exclusive-output.jpg');
        final competingBytes = Uint8List.fromList(
          image.encodeJpg(image.Image(width: 3, height: 3, backgroundColor: image.ColorRgb8(20, 40, 60))),
        );
        await inputFile.writeAsBytes(image.encodePng(image.Image(width: 4, height: 4)), flush: true);

        await expectLater(
          ImageConversionPipeline().convert(
            ImageConversionRequest(
              inputFile: inputFile,
              outputFile: outputFile,
              cjpegExecutable: cjpeg,
              settings: const ConversionSettings(),
              finalizeStagedOutput: (_, _) async {
                await outputFile.writeAsBytes(competingBytes, flush: true);
              },
            ),
          ),
          throwsA(isA<FileSystemException>()),
        );

        expect(await outputFile.readAsBytes(), orderedEquals(competingBytes));
      },
      skip: canRunCjpeg == false ? 'cjpeg is unavailable on this host.' : false,
    );

    test(
      '新規 JPEG の予約後の公開に失敗したときは予約ファイルを残さない',
      () async {
        final inputFile = File('${temporaryDirectory.path}${Platform.pathSeparator}reservation-source.png');
        final outputFile = File('${temporaryDirectory.path}${Platform.pathSeparator}reservation-output.jpg');
        final publicationFailure = FileSystemException('Reserved output publication failed.', outputFile.path);
        await inputFile.writeAsBytes(image.encodePng(image.Image(width: 4, height: 4)), flush: true);
        var didReserveOutput = false;

        await expectLater(
          ImageConversionPipeline(
            replaceStagedOutput: (stagedOutput, reservedOutput) async {
              expect(await stagedOutput.exists(), isTrue);
              expect(reservedOutput.path, outputFile.path);
              expect(await reservedOutput.exists(), isTrue);
              didReserveOutput = true;
              throw publicationFailure;
            },
          ).convert(
            ImageConversionRequest(
              inputFile: inputFile,
              outputFile: outputFile,
              cjpegExecutable: cjpeg,
              settings: const ConversionSettings(),
            ),
          ),
          throwsA(same(publicationFailure)),
        );

        expect(didReserveOutput, isTrue);
        expect(await outputFile.exists(), isFalse);

        final retryResult = await ImageConversionPipeline().convert(
          ImageConversionRequest(
            inputFile: inputFile,
            outputFile: outputFile,
            cjpegExecutable: cjpeg,
            settings: const ConversionSettings(),
          ),
        );

        expect(retryResult.outputFile.path, outputFile.path);
        expect(await outputFile.exists(), isTrue);
      },
      skip: canRunCjpeg == false ? 'cjpeg is unavailable on this host.' : false,
    );

    test(
      '新規 JPEG の予約後に任意例外が起きたときも予約ファイルを残さない',
      () async {
        final inputFile = File('${temporaryDirectory.path}${Platform.pathSeparator}state-error-source.png');
        final outputFile = File('${temporaryDirectory.path}${Platform.pathSeparator}state-error-output.jpg');
        final publicationFailure = StateError('Reserved output publication failed.');
        await inputFile.writeAsBytes(image.encodePng(image.Image(width: 4, height: 4)), flush: true);

        await expectLater(
          ImageConversionPipeline(
            replaceStagedOutput: (_, _) async {
              throw publicationFailure;
            },
          ).convert(
            ImageConversionRequest(
              inputFile: inputFile,
              outputFile: outputFile,
              cjpegExecutable: cjpeg,
              settings: const ConversionSettings(),
            ),
          ),
          throwsA(same(publicationFailure)),
        );

        expect(await outputFile.exists(), isFalse);
      },
      skip: canRunCjpeg == false ? 'cjpeg is unavailable on this host.' : false,
    );

    test(
      '任意比率の中央クロップを設定モデルから適用する',
      () async {
        final source = image.Image(width: 12, height: 8);
        final inputFile = File('${temporaryDirectory.path}${Platform.pathSeparator}square-source.png');
        final outputFile = File('${temporaryDirectory.path}${Platform.pathSeparator}square-output.jpg');
        await inputFile.writeAsBytes(image.encodePng(source), flush: true);

        final result = await ImageConversionPipeline().convert(
          ImageConversionRequest(
            inputFile: inputFile,
            outputFile: outputFile,
            cjpegExecutable: cjpeg,
            settings: const ConversionSettings(
              aspectRatio: AspectRatio.custom(horizontal: 1, vertical: 1),
              resizeEnabled: true,
              resizeValue: 4,
            ),
          ),
        );

        expect(result.cropRect, const CropRect(left: 2, top: 0, width: 8, height: 8));
        expect(result.outputWidth, 4);
        expect(result.outputHeight, 4);
      },
      skip: canRunCjpeg == false ? 'cjpeg is unavailable on this host.' : false,
    );

    test('アニメーション PNG を出力前に拒否する', () async {
      final firstFrame = image.Image(width: 4, height: 4);
      firstFrame.addFrame(image.Image(width: 4, height: 4));
      final inputFile = File('${temporaryDirectory.path}${Platform.pathSeparator}animated.png');
      await inputFile.writeAsBytes(image.encodePng(firstFrame), flush: true);

      expect(
        ImageConversionPipeline().convert(
          ImageConversionRequest(
            inputFile: inputFile,
            outputFile: File('${temporaryDirectory.path}${Platform.pathSeparator}animated.jpg'),
            cjpegExecutable: cjpeg,
            settings: const ConversionSettings(),
          ),
        ),
        throwsA(
          isA<UnsupportedImageException>().having(
            (exception) => exception.message,
            'message',
            'Animated images cannot be converted.',
          ),
        ),
      );
    });

    test('PNG の上書きで入力と同じ出力先を拒否する', () async {
      final inputFile = File('${temporaryDirectory.path}${Platform.pathSeparator}same-path.png');
      await inputFile.writeAsBytes(image.encodePng(image.Image(width: 4, height: 4)), flush: true);

      expect(
        ImageConversionPipeline().convert(
          ImageConversionRequest(
            inputFile: inputFile,
            outputFile: inputFile,
            cjpegExecutable: cjpeg,
            settings: const ConversionSettings(overwrite: true),
          ),
        ),
        throwsArgumentError,
      );
    });
  });
}

Uint8List _jpegWithOrientation(Uint8List jpegBytes, int orientation) {
  final exifData = <int>[
    0x45,
    0x78,
    0x69,
    0x66,
    0x00,
    0x00,
    0x49,
    0x49,
    0x2A,
    0x00,
    0x08,
    0x00,
    0x00,
    0x00,
    0x01,
    0x00,
    0x12,
    0x01,
    0x03,
    0x00,
    0x01,
    0x00,
    0x00,
    0x00,
    orientation,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
  ];
  final length = exifData.length + 2;
  return Uint8List.fromList(<int>[
    ...jpegBytes.sublist(0, 2),
    0xFF,
    0xE1,
    length >> 8,
    length & 0xFF,
    ...exifData,
    ...jpegBytes.sublist(2),
  ]);
}

/// テスト用の変換指定を作成します。
ImageConversionRequest _conversionRequest(File inputFile, File outputFile, File cjpegExecutable) {
  return ImageConversionRequest(
    inputFile: inputFile,
    outputFile: outputFile,
    cjpegExecutable: cjpegExecutable,
    settings: const ConversionSettings(),
  );
}

/// 指定した 8bit RGB の PPM を実際の `cjpeg` で圧縮します。
Future<Uint8List> _encodePpmWithCjpeg({
  required File cjpegExecutable,
  required Directory temporaryDirectory,
  required String fileName,
  required int width,
  required int height,
  required Uint8List rgbBytes,
  required int quality,
}) async {
  final ppmFile = File('${temporaryDirectory.path}${Platform.pathSeparator}$fileName.ppm');
  final outputFile = File('${temporaryDirectory.path}${Platform.pathSeparator}$fileName.jpg');
  final ppmBytes = BytesBuilder(copy: false)
    ..add(ascii.encode('P6\n$width $height\n255\n'))
    ..add(rgbBytes);
  await ppmFile.writeAsBytes(ppmBytes.toBytes(), flush: true);
  final result = await Process.run(cjpegExecutable.path, <String>[
    '-quality',
    quality.toString(),
    '-progressive',
    '-optimize',
    '-outfile',
    outputFile.path,
    ppmFile.path,
  ]);
  if (result.exitCode != 0) {
    throw StateError('cjpeg exited with code ${result.exitCode}: ${result.stderr}.');
  }
  return outputFile.readAsBytes();
}

/// EXIF、GPS、XMP、IPTC、コメントを含む実 JPEG ヘッダーを追加します。
Uint8List _jpegWithMetadata(Uint8List jpegBytes) {
  return _injectJpegSegments(jpegBytes, <({int marker, Uint8List data})>[
    (marker: 0xE1, data: Uint8List.fromList(_exifWithGps())),
    (marker: 0xE1, data: Uint8List.fromList(<int>[..._xmpHeader, ...ascii.encode('<x:xmpmeta/>')])),
    (
      marker: 0xED,
      data: Uint8List.fromList(<int>[..._photoshopHeader, 0x1C, 0x02, 0x00, 0x04, 0x74, 0x65, 0x73, 0x74]),
    ),
    (marker: 0xFE, data: Uint8List.fromList(ascii.encode('camera comment'))),
  ]);
}

/// EXIF の IFD0 から GPS IFD を参照する最小の TIFF データを作成します。
List<int> _exifWithGps() {
  return <int>[
    ..._exifHeader,
    0x49,
    0x49,
    0x2A,
    0x00,
    0x08,
    0x00,
    0x00,
    0x00,
    0x02,
    0x00,
    0x12,
    0x01,
    0x03,
    0x00,
    0x01,
    0x00,
    0x00,
    0x00,
    0x01,
    0x00,
    0x00,
    0x00,
    0x25,
    0x88,
    0x04,
    0x00,
    0x01,
    0x00,
    0x00,
    0x00,
    0x26,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
  ];
}

/// JPEG の SOI 直後へ任意の APP/COM セグメントを挿入します。
Uint8List _injectJpegSegments(Uint8List jpegBytes, List<({int marker, Uint8List data})> segments) {
  final output = BytesBuilder(copy: false)..add(jpegBytes.sublist(0, 2));
  for (final segment in segments) {
    final length = segment.data.lengthInBytes + 2;
    output.add(<int>[0xFF, segment.marker, length >> 8, length & 0xFF]);
    output.add(segment.data);
  }
  output.add(jpegBytes.sublist(2));
  return output.toBytes();
}

/// JPEG ヘッダーに含まれる APP/COM セグメントを走査します。
List<({int marker, Uint8List data})> _jpegHeaderSegments(Uint8List bytes) {
  final segments = <({int marker, Uint8List data})>[];
  var offset = 2;
  while (offset + 1 < bytes.lengthInBytes && bytes[offset] == 0xFF) {
    while (offset < bytes.lengthInBytes && bytes[offset] == 0xFF) {
      offset += 1;
    }
    if (offset >= bytes.lengthInBytes) {
      break;
    }
    final marker = bytes[offset];
    offset += 1;
    if (marker == 0xDA || marker == 0xD9) {
      break;
    }
    if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
      continue;
    }
    if (offset + 2 > bytes.lengthInBytes) {
      break;
    }
    final length = (bytes[offset] << 8) | bytes[offset + 1];
    final dataStart = offset + 2;
    final dataEnd = dataStart + length - 2;
    if (length < 2 || dataEnd > bytes.lengthInBytes) {
      break;
    }
    segments.add((marker: marker, data: Uint8List.fromList(bytes.sublist(dataStart, dataEnd))));
    offset = dataEnd;
  }
  return segments;
}

/// `cjpeg` が出力した分割済み APP2 セグメントから ICC プロファイルを復元します。
Uint8List _iccProfileFromJpeg(Uint8List jpegBytes) {
  final segments =
      _jpegHeaderSegments(
          jpegBytes,
        ).where((segment) => segment.marker == 0xE2 && _hasPrefix(segment.data, _iccHeader)).toList()
        ..sort((left, right) => left.data[12].compareTo(right.data[12]));
  final profile = BytesBuilder(copy: false);
  for (final segment in segments) {
    profile.add(segment.data.sublist(14));
  }
  return profile.toBytes();
}

/// バイト列が指定ヘッダーで始まるか調べます。
bool _hasPrefix(Uint8List bytes, List<int> header) {
  if (bytes.lengthInBytes < header.length) {
    return false;
  }
  for (var index = 0; index < header.length; index += 1) {
    if (bytes[index] != header[index]) {
      return false;
    }
  }
  return true;
}

/// Orientation ごとの差が分かる3列2行の色パターンを作成します。
image.Image _orientationPatternImage() {
  const cellSize = 24;
  final source = image.Image(width: cellSize * 3, height: cellSize * 2);
  for (var row = 0; row < 2; row += 1) {
    for (var column = 0; column < 3; column += 1) {
      final color = _orientationColors[row * 3 + column];
      for (var y = row * cellSize; y < (row + 1) * cellSize; y += 1) {
        for (var x = column * cellSize; x < (column + 1) * cellSize; x += 1) {
          source.setPixelRgb(x, y, color.red, color.green, color.blue);
        }
      }
    }
  }
  return source;
}

/// EXIF Orientation ごとの焼き込み後の色配置を返します。
List<List<String>> _orientationColorGrid(int orientation) {
  return switch (orientation) {
    1 => const <List<String>>[
      <String>['red', 'green', 'blue'],
      <String>['yellow', 'magenta', 'cyan'],
    ],
    2 => const <List<String>>[
      <String>['blue', 'green', 'red'],
      <String>['cyan', 'magenta', 'yellow'],
    ],
    3 => const <List<String>>[
      <String>['cyan', 'magenta', 'yellow'],
      <String>['blue', 'green', 'red'],
    ],
    4 => const <List<String>>[
      <String>['yellow', 'magenta', 'cyan'],
      <String>['red', 'green', 'blue'],
    ],
    5 => const <List<String>>[
      <String>['red', 'yellow'],
      <String>['green', 'magenta'],
      <String>['blue', 'cyan'],
    ],
    6 => const <List<String>>[
      <String>['yellow', 'red'],
      <String>['magenta', 'green'],
      <String>['cyan', 'blue'],
    ],
    7 => const <List<String>>[
      <String>['cyan', 'blue'],
      <String>['magenta', 'green'],
      <String>['yellow', 'red'],
    ],
    8 => const <List<String>>[
      <String>['blue', 'cyan'],
      <String>['green', 'magenta'],
      <String>['red', 'yellow'],
    ],
    _ => throw ArgumentError.value(orientation, 'orientation'),
  };
}

/// 圧縮後の RGB 値に最も近いテスト用の色名を返します。
String _closestOrientationColor(int red, int green, int blue) {
  var closestName = '';
  var closestDistance = double.infinity;
  for (final color in _orientationColors) {
    final distance =
        (red - color.red) * (red - color.red) +
        (green - color.green) * (green - color.green) +
        (blue - color.blue) * (blue - color.blue);
    if (distance < closestDistance) {
      closestName = color.name;
      closestDistance = distance.toDouble();
    }
  }
  return closestName;
}

const _exifHeader = <int>[0x45, 0x78, 0x69, 0x66, 0x00, 0x00];
const _xmpHeader = <int>[
  0x68,
  0x74,
  0x74,
  0x70,
  0x3A,
  0x2F,
  0x2F,
  0x6E,
  0x73,
  0x2E,
  0x61,
  0x64,
  0x6F,
  0x62,
  0x65,
  0x2E,
  0x63,
  0x6F,
  0x6D,
  0x2F,
  0x78,
  0x61,
  0x70,
  0x2F,
  0x31,
  0x2E,
  0x30,
  0x2F,
  0x00,
];
const _photoshopHeader = <int>[0x50, 0x68, 0x6F, 0x74, 0x6F, 0x73, 0x68, 0x6F, 0x70, 0x20, 0x33, 0x2E, 0x30, 0x00];
const _iccHeader = <int>[0x49, 0x43, 0x43, 0x5F, 0x50, 0x52, 0x4F, 0x46, 0x49, 0x4C, 0x45, 0x00];
const _orientationColors = <({String name, int red, int green, int blue})>[
  (name: 'red', red: 240, green: 15, blue: 15),
  (name: 'green', red: 15, green: 240, blue: 15),
  (name: 'blue', red: 15, green: 15, blue: 240),
  (name: 'yellow', red: 240, green: 240, blue: 15),
  (name: 'magenta', red: 240, green: 15, blue: 240),
  (name: 'cyan', red: 15, green: 240, blue: 240),
];

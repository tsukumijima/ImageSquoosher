import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:image_squoosher/models/conversion_settings.dart';
import 'package:image_squoosher/services/image_conversion_pipeline.dart';
import 'package:image_squoosher/services/image_pipeline_types.dart';

void main() {
  final cjpeg = File(
    Platform.environment['IMAGE_SQUOOSHER_CJPEG'] ??
        (Platform.isWindows ? 'native/mozjpeg/windows/cjpeg.exe' : 'native/mozjpeg/macos/arm64/cjpeg'),
  );

  test('実圧縮の進捗を通知し、出力の公開成功後だけ100%になる', () async {
    final directory = await Directory.systemTemp.createTemp('image-squoosher-progress-');
    // UI の状態と同様に送信できないオブジェクトを保持し、ワーカーへコールバックが漏れる故障を捕捉する
    final port = ReceivePort();
    addTearDown(() async {
      port.close();
      await directory.delete(recursive: true);
    });
    final input = File('${directory.path}/input.png');
    final output = File('${directory.path}/output.jpg');
    await input.writeAsBytes(image.encodePng(image.Image(width: 256, height: 256)));
    final progressValues = <double>[];
    // OS の公開 API は既存の変換テストで検証し、ここでは排他的に予約されたテスト出力へ確定する
    await ImageConversionPipeline(
      replaceStagedOutput: (stagedOutput, outputFile) async {
        await outputFile.delete();
        await stagedOutput.rename(outputFile.path);
      },
    ).convert(
      ImageConversionRequest(
        inputFile: input,
        outputFile: output,
        cjpegExecutable: cjpeg,
        settings: const ConversionSettings(),
        onProgress: (progress) {
          port.sendPort.send(progress);
          progressValues.add(progress);
          if (progress == 1.0) {
            expect(output.existsSync(), isTrue);
          }
        },
      ),
    );
    expect(progressValues.first, 0.0);
    expect(progressValues.last, 1.0);
    expect(progressValues.where((value) => value > 0.2 && value < 0.9), isNotEmpty);
    for (var index = 1; index < progressValues.length; index += 1) {
      expect(progressValues[index], greaterThanOrEqualTo(progressValues[index - 1]));
    }

    // 公開直前の属性反映が失敗した場合は、元画像と未完了の進捗を保持する
    final failedProgressValues = <double>[];
    final failedOutput = File('${directory.path}/failed.jpg');
    await expectLater(
      ImageConversionPipeline().convert(
        ImageConversionRequest(
          inputFile: input,
          outputFile: failedOutput,
          cjpegExecutable: cjpeg,
          settings: const ConversionSettings(),
          onProgress: failedProgressValues.add,
          finalizeStagedOutput: (_, _) async => throw const FileSystemException('Cannot copy timestamps.'),
        ),
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(failedProgressValues, isNot(contains(1.0)));
    expect(input.existsSync(), isTrue);
    expect(failedOutput.existsSync(), isFalse);
  }, skip: cjpeg.existsSync() ? false : 'cjpeg is unavailable on this host.');
}

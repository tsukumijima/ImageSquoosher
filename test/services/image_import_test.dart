import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:image_squoosher/models/conversion_settings.dart';
import 'package:image_squoosher/models/image_dimensions.dart';
import 'package:image_squoosher/services/image_pipeline_types.dart';
import 'package:image_squoosher/services/squoosher_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('image-squoosher-import-');
  });
  tearDown(() async => directory.delete(recursive: true));

  Future<void> waitForDetails(SquoosherController controller) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (controller.images.any((entry) => entry.sourceDimensions == null && entry.isInputValid)) {
      if (DateTime.now().isAfter(deadline)) fail('Image inspection did not finish.');
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  test('JPEG の EXIF Orientation 1〜8 と PNG・WebP の寸法をヘッダーから表示する', () async {
    final paths = <String>[];
    for (var orientation = 1; orientation <= 8; orientation += 1) {
      final source = image.Image(width: 24, height: 16)..exif.imageIfd.orientation = orientation;
      final file = File('${directory.path}/orientation-$orientation.jpg');
      await file.writeAsBytes(image.encodeJpg(source));
      paths.add(file.path);
    }
    for (final format in ['png', 'webp']) {
      final source = image.Image(width: 24, height: 16);
      final file = File('${directory.path}/source.$format');
      await file.writeAsBytes(format == 'png' ? image.encodePng(source) : image.encodeWebP(source));
      paths.add(file.path);
    }
    final controller = SquoosherController();
    addTearDown(controller.dispose);
    controller.addFiles(paths);
    await waitForDetails(controller);
    for (var index = 0; index < paths.length; index += 1) {
      expect(controller.images[index].isInputValid, isTrue);
      expect(
        controller.images[index].sourceDimensions,
        index >= 4 && index < 8 ? const ImageDimensions(16, 24) : const ImageDimensions(24, 16),
      );
    }
  });

  test('アニメーション PNG・WebP を検査時に拒否する', () async {
    final source = image.Image(width: 24, height: 16)..addFrame(image.Image(width: 24, height: 16));
    final paths = <String>[];
    for (final format in ['png', 'webp']) {
      final file = File('${directory.path}/animated.$format');
      // WebP エンコーダーは静止画専用のため、2フレームの実データで拒否経路を検証する
      await file.writeAsBytes(
        format == 'png'
            ? image.encodePng(source)
            : base64Decode(
                'UklGRoQAAABXRUJQVlA4WAoAAAACAAAAAQAAAQAAQU5JTQYAAAD/////AABBTk1GKAAAAAAAAAAAAAEAAAEAAGQAAAJWUDhMDwAAAC8BQAAABxDlj/4HIqL/AQBBTk1GKAAAAAAAAAAAAAEAAAEAAGQAAABWUDhMDwAAAC8BQAAABxDR/v4HIqL/AQA=',
              ),
      );
      paths.add(file.path);
    }
    final controller = SquoosherController();
    addTearDown(controller.dispose);
    controller.addFiles(paths);
    await waitForDetails(controller);
    expect(controller.images.every((entry) => !entry.isInputValid), isTrue);
    expect(controller.images.every((entry) => entry.errorMessage!.contains('Animated')), isTrue);
  });

  test('追加直後の設定変更と変換開始でも、全行の検査結果を開始条件へ反映する', () async {
    final paths = <String>[];
    for (var index = 0; index < 3; index += 1) {
      final file = File('${directory.path}/source-$index.png');
      await file.writeAsBytes(image.encodePng(image.Image(width: 24, height: 16)));
      paths.add(file.path);
    }
    final engine = _InspectionEngine();
    final controller = SquoosherController(engine: engine);
    addTearDown(controller.dispose);
    await controller.updateOutputPlans(const ConversionSettings());
    controller.addFiles(paths);
    // 待機行を copyWith() で更新する設定変更を、検査の開始前に発生させる
    unawaited(controller.updateOutputPlans(const ConversionSettings(quality: 80)));
    await controller.compress(const ConversionSettings(quality: 80));
    expect(engine.request!.images.length, paths.length);
    expect(engine.request!.images.every((entry) => entry.sourceDimensions == const ImageDimensions(24, 16)), isTrue);
    expect(engine.request!.images.every((entry) => entry.outputPath != null && entry.byteLength != null), isTrue);
  });

  test('出力計画の完了前に dispose しても遅延した通知を送らない', () async {
    final file = File('${directory.path}/source.png');
    await file.writeAsBytes(image.encodePng(image.Image(width: 24, height: 16)));
    final pathsRead = Completer<Set<String>>();
    final controller = SquoosherController(existingPathsReader: (_) => pathsRead.future);
    controller.addFiles([file.path]);
    await waitForDetails(controller);
    final planning = controller.updateOutputPlans(const ConversionSettings());
    controller.dispose();
    pathsRead.complete({file.path});
    await planning;
  });
}

/// 実エンコーダーを動かす直前に、入力情報が全件そろっていることを確認するエンジンです。
class _InspectionEngine implements ImageCompressionEngine {
  CompressionRequest? request;

  @override
  Future<ImageBatchConversionResult> compress(
    CompressionRequest request, {
    required ImageConversionStopToken stopToken,
    required ValueChanged<QueuedImage> onItemStarted,
    required FutureOr<void> Function(ImageConversionResult) onItemCompleted,
    required ValueChanged<ImageConversionFailure> onItemFailed,
  }) async {
    this.request = request;
    return const ImageBatchConversionResult(completed: [], failures: [], wasStopped: false);
  }
}

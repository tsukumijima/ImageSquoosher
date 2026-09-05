import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:image_squoosher/l10n/generated/app_localizations.dart';
import 'package:image_squoosher/models/image_dimensions.dart';
import 'package:image_squoosher/services/image_pipeline_types.dart';
import 'package:image_squoosher/services/settings_service.dart';
import 'package:image_squoosher/services/squoosher_controller.dart';
import 'package:image_squoosher/ui/home_screen.dart';
import 'package:image_squoosher/ui/widgets/compression_footer.dart';

/// 完了時刻を固定し、変換中の Finder 通知と停止要求を検査します。
class _ControlledEngine implements ImageCompressionEngine {
  final completion = Completer<void>();
  int startCount = 0;

  @override
  Future<ImageBatchConversionResult> compress(
    CompressionRequest request, {
    required ImageConversionStopToken stopToken,
    required ValueChanged<QueuedImage> onItemStarted,
    required FutureOr<void> Function(ImageConversionResult) onItemCompleted,
    required ValueChanged<ImageConversionFailure> onItemFailed,
  }) async {
    startCount += 1;
    onItemStarted(request.images.first);
    await completion.future;
    // 出力と完了通知を作り、一覧の置換後も結果ファイルが残ることを確認する
    final inputFile = File(request.images.first.path);
    final outputFile = File('${inputFile.parent.path}/converted.jpg');
    outputFile.writeAsBytesSync(image.encodeJpg(image.Image(width: 8, height: 6)));
    final result = ImageConversionResult(
      inputFile: inputFile,
      outputFile: outputFile,
      sourceFormat: SourceImageFormat.png,
      sourceWidth: 8,
      sourceHeight: 6,
      cropRect: const CropRect(left: 0, top: 0, width: 8, height: 6),
      outputWidth: 8,
      outputHeight: 6,
    );
    await onItemCompleted(result);
    return ImageBatchConversionResult(completed: [result], failures: [], wasStopped: stopToken.isRequested);
  }
}

/// 実コントローラーの置換回数を記録し、終了通知の再入による重複を検査します。
class _RecordingController extends SquoosherController {
  _RecordingController(ImageCompressionEngine engine) : super(engine: engine);

  int replacementCount = 0;

  @override
  int replaceFiles(Iterable<String> paths) {
    replacementCount += 1;
    return super.replaceFiles(paths);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('net.tsukumijima.image-squoosher/finder_sync');
  late Directory temporaryDirectory;
  late List<String> paths;

  setUp(() {
    temporaryDirectory = Directory.systemTemp.createTempSync('image-squoosher-finder-test-');
    // 実画像の読み込みを通し、キューの入力検証と通知も実装どおりに動かす
    paths = ['original', 'first', 'latest'].map((name) {
      final file = File('${temporaryDirectory.path}/$name.png');
      file.writeAsBytesSync(image.encodePng(image.Image(width: 8, height: 6)));
      return file.path;
    }).toList();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      return switch (call.method) {
        'getFinderSelectedImageURLs' => <String>[],
        'isFinderSyncExtensionEnabled' => true,
        _ => null,
      };
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    temporaryDirectory.deleteSync(recursive: true);
  });

  /// ネイティブから Dart へ届く選択通知を送信します。
  Future<void> sendSelection(List<String> selection) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(MethodCall('finderSelectedImageURLs', selection)),
      (_) {},
    );
  }

  /// Finder の受信ハンドラーを有効にした画面を構築します。
  Future<void> pumpHome(WidgetTester tester, SquoosherController controller) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ja'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: HomeScreen(
          initialPreferences: const AppPreferences(),
          settingsService: SettingsService.forTesting(temporaryDirectory),
          controller: controller,
          onLanguageChanged: (_) {},
          checkForUpdatesOnInitialize: false,
          enableDropTarget: false,
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('待機中の Finder 選択は直ちに一覧を置き換える', (tester) async {
    final engine = _ControlledEngine();
    final controller = _RecordingController(engine);
    addTearDown(controller.dispose);
    await pumpHome(tester, controller);
    await sendSelection([paths[1], paths[2]]);
    expect(controller.images.map((queuedImage) => queuedImage.path), [paths[1], paths[2]]);
    expect(controller.replacementCount, 1);
    expect(engine.startCount, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final shouldStop in [false, true]) {
    testWidgets('変換${shouldStop ? '停止' : '完了'}後に最新の Finder 選択を一度だけ反映する', (tester) async {
      final engine = _ControlledEngine();
      final controller = _RecordingController(engine);
      addTearDown(controller.dispose);
      await tester.runAsync(() async {
        controller.addFiles([paths[0]]);
        for (var attempt = 0; attempt < 200 && controller.images.single.sourceDimensions == null; attempt += 1) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(controller.images.single.sourceDimensions, isNotNull);
      });
      await pumpHome(tester, controller);
      await tester.runAsync(() async {
        tester.widget<CompressionFooter>(find.byType(CompressionFooter)).onStart();
        for (var attempt = 0; attempt < 200 && engine.startCount == 0; attempt += 1) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(engine.startCount, 1);
      });

      // 連続して選択しても、実行中の画像と処理状態を完了まで保持する
      await sendSelection([paths[1]]);
      await sendSelection([paths[1], paths[2]]);
      expect(controller.images.single.path, paths[0]);
      expect(controller.images.single.status, QueuedImageStatus.processing);
      if (shouldStop) {
        controller.requestStop();
        expect(controller.images.single.path, paths[0]);
      }
      await tester.runAsync(() async {
        engine.completion.complete();
        for (var attempt = 0; attempt < 200 && controller.isCompressing; attempt += 1) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(controller.isCompressing, isFalse);
      });
      await tester.pump();

      expect(controller.images.map((queuedImage) => queuedImage.path), [paths[1], paths[2]]);
      expect(controller.replacementCount, 1);
      expect(controller.isCompressing, isFalse);
      expect(controller.lastRunWasStopped, shouldStop);
      expect(engine.startCount, 1);
      expect(paths.every((path) => File(path).existsSync()), isTrue);
      expect(image.decodeJpg(File('${temporaryDirectory.path}/converted.jpg').readAsBytesSync()), isNotNull);
      expect(
        find.text(shouldStop ? '変換を停止しました。\n完了した画像は保存されています。' : '1件の画像を変換できました。\nファイルや保存先は一覧から開けます。'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}

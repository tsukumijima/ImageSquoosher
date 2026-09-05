import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:image_squoosher/l10n/generated/app_localizations.dart';
import 'package:image_squoosher/services/settings_service.dart';
import 'package:image_squoosher/services/squoosher_controller.dart';
import 'package:image_squoosher/ui/home_screen.dart';
import 'package:image_squoosher/ui/theme.dart';
import 'package:image_squoosher/ui/widgets/compression_footer.dart';
import 'package:image_squoosher/ui/widgets/conversion_settings_panel.dart';
import 'package:image_squoosher/ui/widgets/queue_header.dart';
import 'package:image_squoosher/ui/widgets/queued_image_row.dart';
import 'package:integration_test/integration_test.dart';
import 'package:window_manager/window_manager.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  const definedImageDirectory = String.fromEnvironment('IMAGE_SQUOOSHER_QA_IMAGE_DIR');
  final imageDirectory = Directory(
    definedImageDirectory.isNotEmpty
        ? definedImageDirectory
        : Platform.environment['IMAGE_SQUOOSHER_QA_IMAGE_DIR'] ?? '/tmp/image-squoosher-qa/images',
  );

  testWidgets(
    'Desktop の実画像変換と設定・通知・補助メニューを撮影して検証する',
    (tester) async {
      final workspace = await Directory.systemTemp.createTemp('image-squoosher-ui-review-');
      final screenshots = Directory('/tmp/image-squoosher-qa');
      await screenshots.create(recursive: true);
      final controller = SquoosherController();
      final captureKey = GlobalKey();
      await windowManager.ensureInitialized();
      await windowManager.setSize(const Size(620, 680));
      // 他のウィンドウで隠れたときも描画が続くよう、撮影中はテスト画面を最前面へ置く
      await windowManager.setAlwaysOnTop(true);
      addTearDown(() => windowManager.setAlwaysOnTop(false));
      await windowManager.show();
      await windowManager.focus();
      var locale = const Locale('ja');
      addTearDown(controller.dispose);
      addTearDown(() => workspace.delete(recursive: true));

      // 原本と既存の検証出力を保持し、入力画像だけを専用ディレクトリへ複製する
      final inputPaths = <String>[];
      for (final entry in await imageDirectory.list().toList()) {
        if (entry is! File || entry.path.contains('_resized')) {
          continue;
        }
        final extension = entry.path.split('.').last.toLowerCase();
        if (!['jpg', 'jpeg', 'png', 'webp'].contains(extension)) {
          continue;
        }
        final name = entry.uri.pathSegments.last;
        final copy = await entry.copy('${workspace.path}/$name');
        inputPaths.add(copy.path);
      }
      expect(inputPaths.any((path) => path.toLowerCase().endsWith('.jpg')), isTrue);
      expect(inputPaths.any((path) => path.toLowerCase().endsWith('.png')), isTrue);
      expect(inputPaths.any((path) => path.toLowerCase().endsWith('.webp')), isTrue);

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) => RepaintBoundary(
            key: captureKey,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: buildAppTheme(const Color(0xff0a84ff)),
              locale: locale,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: HomeScreen(
                initialPreferences: const AppPreferences(languageCode: 'ja'),
                settingsService: SettingsService.forTesting(workspace),
                controller: controller,
                onLanguageChanged: (languageCode) => setState(() => locale = Locale(languageCode)),
                checkForUpdatesOnInitialize: false,
                initializePlatformServices: false,
                enableDropTarget: false,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _capture(tester, captureKey, screenshots, 'ui-empty');

      // 実ファイルを通常のコントローラーへ投入し、ヘッダー解析とサムネイル表示を待つ
      final loadingTimer = Stopwatch()..start();
      controller.addFiles(inputPaths);
      await _waitFor(tester, () => controller.images.every((item) => item.sourceDimensions != null));
      debugPrint('UI review image inspection: ${loadingTimer.elapsedMilliseconds} ms.');
      await tester.pump(const Duration(milliseconds: 300));
      await _capture(tester, captureKey, screenshots, 'ui-loaded');

      // 画像一覧を末尾まで動かしても、変換設定と一覧の見出しを見失わないことを確認する
      final settingsBounds = tester.getRect(find.byType(ConversionSettingsPanel));
      final queueHeaderBounds = tester.getRect(find.byType(QueueHeader));
      final queueScrollable = find.descendant(
        of: find.byKey(const ValueKey('image-queue-list')),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(find.byKey(ValueKey(inputPaths.last)), 150, scrollable: queueScrollable);
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(ConversionSettingsPanel)), settingsBounds);
      expect(tester.getRect(find.byType(QueueHeader)), queueHeaderBounds);
      expect(tester.state<ScrollableState>(queueScrollable).position.pixels, greaterThan(0));
      await _capture(tester, captureKey, screenshots, 'ui-scrolled');
      await tester.scrollUntilVisible(find.byKey(ValueKey(inputPaths.first)), -150, scrollable: queueScrollable);
      await tester.pumpAndSettle();

      final firstRow = find.byType(QueuedImageRow).first;
      final initialRowHeight = tester.getSize(firstRow).height;
      await tester.tap(find.byKey(const ValueKey('aspect-ratio-select')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('16:9').last);
      await tester.tap(find.text('16:9').last);
      await tester.pump();
      await tester.tap(find.text('リサイズ'));
      await tester.pump();
      await tester.enterText(find.byKey(const ValueKey('resize-value-field')), '1920');
      await tester.pump();
      await tester.enterText(find.byKey(const ValueKey('suffix-field')), '_review');
      await tester.pump();
      await tester.tap(find.text('撮影情報と位置情報 (EXIF) を削除'));
      await tester.pump();
      await _waitFor(
        tester,
        () => controller.images.every(
          (item) => item.outputDimensions?.width == 1920 && item.outputDimensions?.height == 1080,
        ),
      );
      expect(tester.getSize(firstRow).height, initialRowHeight);
      expect(find.text('_review'), findsOneWidget);
      expect(controller.images.every((item) => item.outputPath!.endsWith('_review.jpg')), isTrue);
      await _capture(tester, captureKey, screenshots, 'ui-configured');

      await tester.tap(find.text('変換開始'));
      await _waitFor(tester, () => controller.isCompressing && controller.progress > 0);
      await _capture(tester, captureKey, screenshots, 'ui-converting');
      await _waitFor(tester, () => !controller.isCompressing && controller.completedCount == inputPaths.length);
      await tester.pump(const Duration(milliseconds: 300));
      expect(controller.failedCount, 0);
      expect(tester.getSize(firstRow).height, initialRowHeight);
      final footerProgress = tester.widget<LinearProgressIndicator>(
        find.descendant(of: find.byType(CompressionFooter), matching: find.byType(LinearProgressIndicator)),
      );
      expect(footerProgress.value, 1);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(tester.widget<SnackBar>(find.byType(SnackBar)).backgroundColor, footerProgress.color);
      expect(
        find.text(AppLocalizations.of(tester.element(firstRow)).conversionSucceeded(inputPaths.length)),
        findsOneWidget,
      );
      await _capture(tester, captureKey, screenshots, 'ui-completed');

      // JPEG の実デコードとネイティブ日時複製の結果を確認する
      for (final item in controller.images) {
        final input = File(item.path);
        final output = File(item.outputPath!);
        expect(await input.exists(), isTrue);
        expect(await output.exists(), isTrue);
        final decoded = image.decodeJpg(await output.readAsBytes());
        expect(decoded?.width, 1920);
        expect(decoded?.height, 1080);
        expect(
          (await output.lastModified()).difference(await input.lastModified()).abs(),
          lessThan(const Duration(seconds: 2)),
        );
        expect(item.progress, 1);
      }

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await _capture(tester, captureKey, screenshots, 'ui-menu');
      await tester.tap(find.byType(SubmenuButton));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check), findsOneWidget);
      await _capture(tester, captureKey, screenshots, 'ui-language');
      await tester.tap(find.text('English'));
      await tester.pumpAndSettle();
      expect(locale.languageCode, 'en');
      await _capture(tester, captureKey, screenshots, 'ui-english');
      await windowManager.setSize(const Size(520, 560));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await _capture(tester, captureKey, screenshots, 'ui-minimum-english');
      await windowManager.setSize(const Size(620, 680));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.info_outline));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await _capture(tester, captureKey, screenshots, 'ui-about');
      // ダイアログの外側には画面全幅の配置領域があるため、背景を描く Material の寸法を測る
      final dialogSurface = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byWidgetPredicate((widget) => widget is Material && widget.type == MaterialType.card),
      );
      expect(tester.getSize(dialogSurface).width, lessThanOrEqualTo(420));
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // 実エンコーダーの処理中に停止し、未着手の画像が停止状態になることを確認する
      controller.resetResults();
      await tester.pump();
      await tester.tap(find.text('Convert'));
      await _waitFor(
        tester,
        () => controller.isCompressing && controller.images.any((item) => item.status == QueuedImageStatus.processing),
      );
      await tester.pump();
      await tester.tap(find.text('Stop'));
      await _waitFor(tester, () => !controller.isCompressing);
      expect(controller.lastRunWasStopped, isTrue);
      expect(controller.stoppedCount, greaterThan(0));
      await tester.pump(const Duration(milliseconds: 300));
      await _capture(tester, captureKey, screenshots, 'ui-stopped');

      // 壊れた入力も実ファイルの検査へ通し、赤い失敗表示と原本の保持を確認する
      final brokenInput = File('${workspace.path}/broken-review.png');
      await brokenInput.writeAsBytes([0x89, 0x50, 0x4e, 0x47], flush: true);
      controller.addFiles([brokenInput.path]);
      await _waitFor(tester, () => controller.failedCount > 0);
      final failedRow = find.byKey(ValueKey(brokenInput.path));
      await tester.scrollUntilVisible(
        failedRow,
        150,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('image-queue-list')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      final failureBadge = tester.widget<Container>(
        find.descendant(of: failedRow, matching: find.byKey(const ValueKey('image-status-badge'))),
      );
      expect((failureBadge.decoration! as BoxDecoration).color, AppColors.error);
      expect(await brokenInput.exists(), isTrue);
      ScaffoldMessenger.of(tester.element(failedRow)).clearSnackBars();
      await tester.pumpAndSettle();
      await _capture(tester, captureKey, screenshots, 'ui-failed');
      expect(tester.takeException(), isNull);
    },
    skip: !imageDirectory.existsSync(),
    timeout: const Timeout(Duration(minutes: 6)),
  );
}

/// 実際の処理を待ちつつフレームを送り、低速な Debug 変換にも時間を確保する。
/// @param tester フレームを進めるテスト環境
/// @param condition 待機対象が完了した状態で true を返す条件
Future<void> _waitFor(WidgetTester tester, bool Function() condition) async {
  final timer = Stopwatch()..start();
  while (!condition()) {
    if (timer.elapsed > const Duration(minutes: 3)) {
      throw StateError('Timed out while waiting for the desktop UI review.');
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// ダイアログと通知を含む実レンダーを保存し、目視でレイアウトを確認できるようにする。
/// @param tester レンダリングを進めるテスト環境
/// @param key 撮影対象の RepaintBoundary を参照するキー
/// @param directory PNG を保存するディレクトリ
/// @param stage 保存ファイル名に使う画面状態名
Future<void> _capture(WidgetTester tester, GlobalKey key, Directory directory, String stage) async {
  debugPrint('UI capture $stage: preparing frame.');
  await tester.pump().timeout(const Duration(seconds: 10));
  final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  debugPrint('UI capture $stage: reading rendered image.');
  final rendered = await boundary.toImage(pixelRatio: 2).timeout(const Duration(seconds: 10));
  debugPrint('UI capture $stage: encoding PNG.');
  final bytes = await rendered.toByteData(format: ui.ImageByteFormat.png).timeout(const Duration(seconds: 10));
  debugPrint('UI capture $stage: writing PNG.');
  await File(
    '${directory.path}/$stage.png',
  ).writeAsBytes(bytes!.buffer.asUint8List(), flush: true).timeout(const Duration(seconds: 10));
  rendered.dispose();
  debugPrint('UI capture $stage: saved.');
}

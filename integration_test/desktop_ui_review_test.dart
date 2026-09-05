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
import 'package:image_squoosher/ui/widgets/queued_image_row.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
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

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.info_outline));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await _capture(tester, captureKey, screenshots, 'ui-about');
      // Dialog の外側には画面全幅の配置領域があるため、背景を描く Material の寸法を測る
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
        scrollable: find.descendant(of: find.byType(CustomScrollView), matching: find.byType(Scrollable)).first,
      );
      await tester.pump(const Duration(milliseconds: 300));
      final failureLabel = tester.widget<Text>(find.descendant(of: failedRow, matching: find.text('Failed')));
      expect(failureLabel.style?.color, AppColors.error);
      expect(await brokenInput.exists(), isTrue);
      await _capture(tester, captureKey, screenshots, 'ui-failed');
      expect(tester.takeException(), isNull);
    },
    skip: !imageDirectory.existsSync(),
    timeout: const Timeout(Duration(minutes: 6)),
  );
}

/// 実際の処理を待ちつつフレームを送り、低速な Debug 変換にも時間を確保します。
Future<void> _waitFor(WidgetTester tester, bool Function() condition) async {
  final timer = Stopwatch()..start();
  while (!condition()) {
    if (timer.elapsed > const Duration(minutes: 3)) {
      throw StateError('Timed out while waiting for the desktop UI review.');
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// ダイアログと通知を含む実レンダーを保存し、目視でレイアウトを確認できるようにします。
Future<void> _capture(WidgetTester tester, GlobalKey key, Directory directory, String stage) async {
  debugPrint('UI capture $stage: preparing frame.');
  await tester.pump().timeout(const Duration(seconds: 10));
  final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  debugPrint('UI capture $stage: reading rendered image.');
  final capture = boundary.toImage(pixelRatio: 2).timeout(const Duration(seconds: 10));
  var hasCaptured = false;
  capture.then((_) => hasCaptured = true, onError: (Object error) => hasCaptured = true);
  // GPU の読み戻しを待つ間もフレームを送り、Desktop の描画処理を進める
  while (!hasCaptured) {
    await tester.pump(const Duration(milliseconds: 16)).timeout(const Duration(seconds: 10));
  }
  final rendered = await capture;
  debugPrint('UI capture $stage: encoding PNG.');
  final bytes = await rendered.toByteData(format: ui.ImageByteFormat.png).timeout(const Duration(seconds: 10));
  debugPrint('UI capture $stage: writing PNG.');
  await File(
    '${directory.path}/$stage.png',
  ).writeAsBytes(bytes!.buffer.asUint8List(), flush: true).timeout(const Duration(seconds: 10));
  rendered.dispose();
  debugPrint('UI capture $stage: saved.');
}

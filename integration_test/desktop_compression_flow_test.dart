import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:image_squoosher/l10n/generated/app_localizations.dart';
import 'package:image_squoosher/services/settings_service.dart';
import 'package:image_squoosher/services/squoosher_controller.dart';
import 'package:image_squoosher/ui/home_screen.dart';
import 'package:image_squoosher/ui/theme.dart';
import 'package:image_squoosher/ui/widgets/queued_image_row.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Desktop で複数画像を圧縮し、個別失敗後も結果を表示する', (tester) async {
    final temporaryDirectory = await Directory.systemTemp.createTemp('image-squoosher-desktop-e2e-');
    // 既定では配布物と同じ MozJPEG 4.1.1 のリポジトリ内ビルドを使い、配布検証時だけ環境変数の実行ファイルへ差し替える
    final repositoryCjpegPath = Platform.isWindows
        ? 'native/mozjpeg/windows/cjpeg.exe'
        : 'native/mozjpeg/macos/arm64/cjpeg';
    final cjpegPath = Platform.environment['IMAGE_SQUOOSHER_CJPEG'] ?? repositoryCjpegPath;
    final inputPaths = <String>[];
    var didLoadFinderSelection = false;
    var didLoadFinderSyncStatus = false;

    addTearDown(() async {
      await temporaryDirectory.delete(recursive: true);
    });

    expect(Platform.isMacOS || Platform.isWindows, isTrue, reason: 'Desktop runner is required.');
    expect(await File(cjpegPath).exists(), isTrue, reason: 'MozJPEG 4.1.1 cjpeg executable was not found.');

    final firstInput = File('${temporaryDirectory.path}${Platform.pathSeparator}first.png');
    final secondInput = File('${temporaryDirectory.path}${Platform.pathSeparator}second.png');
    final brokenInput = File('${temporaryDirectory.path}${Platform.pathSeparator}broken.png');
    await firstInput.writeAsBytes(image.encodePng(image.Image(width: 64, height: 40)), flush: true);
    await secondInput.writeAsBytes(image.encodePng(image.Image(width: 80, height: 40)), flush: true);
    await brokenInput.writeAsBytes(<int>[0x89, 0x50, 0x4E, 0x47], flush: true);
    inputPaths.addAll(<String>[firstInput.path, secondInput.path, brokenInput.path]);

    const finderMethodChannel = MethodChannel('net.tsukumijima.image-squoosher/finder_sync');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      finderMethodChannel,
      (call) async {
        if (call.method == 'getFinderSelectedImageURLs') {
          didLoadFinderSelection = true;
          return inputPaths;
        }
        if (call.method == 'isFinderSyncExtensionEnabled') {
          didLoadFinderSyncStatus = true;
          return false;
        }
        if (call.method == 'copySourceFileDatesToOutputFile') {
          final arguments = call.arguments! as Map<Object?, Object?>;
          final sourceFile = File(arguments['sourcePath']! as String);
          final outputFile = File(arguments['outputPath']! as String);
          await outputFile.setLastModified(await sourceFile.lastModified());
          return null;
        }
        return null;
      },
    );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        finderMethodChannel,
        null,
      ),
    );

    final settingsService = SettingsService.forTesting(temporaryDirectory);
    final controller = SquoosherController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(const Color(0xff0a84ff)),
        locale: const Locale('ja'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: HomeScreen(
          initialPreferences: const AppPreferences(languageCode: 'ja'),
          settingsService: settingsService,
          controller: controller,
          onLanguageChanged: (_) {},
          checkForUpdatesOnInitialize: false,
        ),
      ),
    );

    await _waitFor(
      tester,
      () => find.byType(QueuedImageRow).evaluate().length == 3 && didLoadFinderSelection && didLoadFinderSyncStatus,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      finderMethodChannel,
      null,
    );
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1:1').last);
    await tester.pump();
    await tester.tap(find.text('リサイズ'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('resize-value-field')));
    await tester.enterText(find.byKey(const ValueKey('resize-value-field')), '24');
    await tester.tap(find.byKey(const ValueKey('suffix-field')));
    await tester.enterText(find.byKey(const ValueKey('suffix-field')), '_e2e');
    await tester.pump(const Duration(milliseconds: 300));

    await tester.ensureVisible(find.text('圧縮を開始'));
    await tester.tap(find.text('圧縮を開始'));
    await _waitFor(
      tester,
      () => controller.completedCount == 2 && controller.failedCount == 1 && controller.isCompressing == false,
    );

    final firstOutput = File('${temporaryDirectory.path}${Platform.pathSeparator}first_e2e.jpg');
    final secondOutput = File('${temporaryDirectory.path}${Platform.pathSeparator}second_e2e.jpg');
    expect(find.text('圧縮完了：2件成功、1件失敗'), findsOneWidget);
    expect(find.text('完了'), findsNWidgets(2));
    await tester.drag(find.byType(ListView), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(find.text('失敗'), findsOneWidget);
    expect(await firstOutput.exists(), isTrue);
    expect(await secondOutput.exists(), isTrue);
    expect(await brokenInput.exists(), isTrue);
    expect(await File('${temporaryDirectory.path}${Platform.pathSeparator}broken_e2e.jpg').exists(), isFalse);
    expect(image.decodeJpg(await firstOutput.readAsBytes())?.width, 24);
    expect(image.decodeJpg(await firstOutput.readAsBytes())?.height, 24);
    expect(image.decodeJpg(await secondOutput.readAsBytes())?.width, 24);
    expect(image.decodeJpg(await secondOutput.readAsBytes())?.height, 24);
  });
}

/// 非同期のキュー読み込みと変換完了を、実行環境の速度差を許容して待機します。
Future<void> _waitFor(WidgetTester tester, bool Function() condition) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    if (condition()) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
  throw StateError('Timed out while waiting for the desktop compression flow.');
}

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
    final sourceModifiedAt = DateTime.utc(2020, 1, 2, 3, 4, 5);
    await firstInput.setLastModified(sourceModifiedAt);
    await secondInput.setLastModified(sourceModifiedAt);
    final firstSourceCreationTime = Platform.isMacOS ? await _readMacOSCreationTime(firstInput) : null;
    if (Platform.isMacOS) {
      // 出力の新規作成日時と元画像の作成日時が偶然一致しないよう、秒境界を越えてから変換する
      await Future<void>.delayed(const Duration(seconds: 1));
    }
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
      () => controller.images.length == 3 && didLoadFinderSelection && didLoadFinderSyncStatus,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      finderMethodChannel,
      null,
    );
    await tester.tap(find.byKey(const ValueKey('aspect-ratio-select')));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
    await tester.tap(find.text('1:1').last);
    await tester.pump();
    await tester.tap(find.text('リサイズ'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('resize-value-field')));
    await tester.enterText(find.byKey(const ValueKey('resize-value-field')), '24');
    await tester.tap(find.byKey(const ValueKey('suffix-field')));
    await tester.enterText(find.byKey(const ValueKey('suffix-field')), '_e2e');
    await tester.pump(const Duration(milliseconds: 300));

    await tester.ensureVisible(find.text('変換開始'));
    await tester.tap(find.text('変換開始'));
    await _waitFor(
      tester,
      () => controller.completedCount == 2 && controller.failedCount == 1 && controller.isCompressing == false,
    );

    final firstOutput = File('${temporaryDirectory.path}${Platform.pathSeparator}first_e2e.jpg');
    final secondOutput = File('${temporaryDirectory.path}${Platform.pathSeparator}second_e2e.jpg');
    expect(find.text('2件の画像を変換しました。1件の画像でエラーが発生したため、一覧をご確認ください。'), findsOneWidget);
    // 画面外の行は必要になった時点で描画されるため、結果一覧までスクロールして確認する
    await tester.scrollUntilVisible(
      find.byKey(ValueKey(brokenInput.path)),
      150,
      scrollable: find.descendant(of: find.byType(CustomScrollView), matching: find.byType(Scrollable)).first,
    );
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
    expect((await firstOutput.lastModified()).difference(sourceModifiedAt).abs(), lessThan(const Duration(seconds: 2)));
    if (Platform.isMacOS) {
      expect(await _readMacOSCreationTime(firstOutput), firstSourceCreationTime);
    }

    // 上書き対象は専用の一時 PNG とし、通常保存で使った元画像と出力を保持する
    final overwriteInput = File('${temporaryDirectory.path}${Platform.pathSeparator}overwrite.png');
    await overwriteInput.writeAsBytes(image.encodePng(image.Image(width: 64, height: 40)), flush: true);
    controller.clear();
    controller.addFiles(<String>[overwriteInput.path]);
    await _waitFor(tester, () => controller.images.single.sourceDimensions != null);
    await tester.scrollUntilVisible(
      find.text('元のファイルを上書きする'),
      -150,
      scrollable: find.descendant(of: find.byType(CustomScrollView), matching: find.byType(Scrollable)).first,
    );
    await tester.tap(find.text('元のファイルを上書きする'));
    await tester.pump();
    await tester.ensureVisible(find.text('変換開始'));
    await tester.tap(find.text('変換開始'));
    await _waitFor(
      tester,
      () => controller.completedCount == 1 && controller.isCompressing == false,
    );

    // PNG の置き換え完了と、保存された JPEG の実寸法を確認する
    final overwriteOutput = File('${temporaryDirectory.path}${Platform.pathSeparator}overwrite.jpg');
    expect(await overwriteOutput.exists(), isTrue);
    expect(await overwriteInput.exists(), isFalse);
    final overwrittenImage = image.decodeJpg(await overwriteOutput.readAsBytes());
    expect(overwrittenImage?.width, 24);
    expect(overwrittenImage?.height, 24);
    expect(controller.images.single.outputPath, overwriteOutput.path);

    // 元 PNG が消えた後も、完了行のサムネイルが保存済み JPEG を参照することを確認する
    final completedRow = find.byKey(ValueKey(overwriteInput.path));
    await tester.scrollUntilVisible(
      completedRow,
      150,
      scrollable: find.descendant(of: find.byType(CustomScrollView), matching: find.byType(Scrollable)).first,
    );
    await tester.pumpAndSettle();
    expect(find.descendant(of: completedRow, matching: find.text('完了')), findsOneWidget);
    final thumbnail = tester.widget<Image>(find.descendant(of: completedRow, matching: find.byType(Image)));
    final thumbnailProvider = thumbnail.image;
    final fileImage =
        (thumbnailProvider is ResizeImage ? thumbnailProvider.imageProvider : thumbnailProvider) as FileImage;
    expect(fileImage.file.path, overwriteOutput.path);
    expect(find.descendant(of: completedRow, matching: find.byIcon(Icons.image_not_supported_outlined)), findsNothing);
  });
}

/// macOS のファイル作成日時を Unix time の秒単位で取得します。
Future<int> _readMacOSCreationTime(File file) async {
  final result = await Process.run('stat', <String>['-f', '%B', file.path]);
  if (result.exitCode != 0) {
    throw FileSystemException('Could not read the file creation time.', file.path);
  }
  return int.parse((result.stdout as String).trim());
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

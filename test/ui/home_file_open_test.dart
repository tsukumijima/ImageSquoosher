import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:image_squoosher/l10n/generated/app_localizations.dart';
import 'package:image_squoosher/services/settings_service.dart';
import 'package:image_squoosher/services/squoosher_controller.dart';
import 'package:image_squoosher/ui/home_screen.dart';
import 'package:image_squoosher/ui/theme.dart';
import 'package:image_squoosher/ui/widgets/queued_image_row.dart';

/// 入出力パスを固定し、ファイルを開く画面操作へ画像を提供する。
class _FileOpenController extends SquoosherController {
  /// 指定したキュー画像を使ってコントローラーを初期化する。
  /// @param queuedImage 開く操作の対象にするキュー画像
  _FileOpenController(this.queuedImage);

  final QueuedImage queuedImage;

  @override
  List<QueuedImage> get images => [queuedImage];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const launcherChannel = MethodChannel('plugins.flutter.io/url_launcher');
  late Directory directory;
  late File source;
  late File output;
  final launchedURLs = <String>[];

  setUp(() {
    directory = Directory.systemTemp.createTempSync('image-squoosher-file-open-');
    source = File('${directory.path}/元 画像.png')..writeAsBytesSync(image.encodePng(image.Image(width: 1, height: 1)));
    output = File('${directory.path}/変換 後.jpg')..writeAsBytesSync(image.encodeJpg(image.Image(width: 1, height: 1)));
    launchedURLs.clear();
    // OS へ渡す URI を記録し、実際のビューワ起動はテストから分離する
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      launcherChannel,
      (call) async {
        if (call.method == 'launch') {
          final arguments = call.arguments! as Map<Object?, Object?>;
          launchedURLs.add(arguments['url']! as String);
          return true;
        }
        return false;
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(launcherChannel, null);
    directory.deleteSync(recursive: true);
  });

  testWidgets('元画像と変換後画像は空白・日本語を含むそれぞれの URI で開く', (tester) async {
    await tester.binding.setSurfaceSize(const Size(620, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = _FileOpenController(
      QueuedImage(
        path: source.path,
        outputPath: output.path,
        status: QueuedImageStatus.completed,
      ),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Colors.blue),
        locale: const Locale('ja'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: HomeScreen(
          initialPreferences: const AppPreferences(),
          settingsService: SettingsService.forTesting(directory),
          onLanguageChanged: (_) {},
          controller: controller,
          checkForUpdatesOnInitialize: false,
          initializePlatformServices: false,
          enableDropTarget: false,
        ),
      ),
    );
    await tester.pump();
    // プレビューの実ファイル読み込みが完了してから、削除を含む操作へ進む
    final previews = find.byType(Image).evaluate().toList();
    var hasLoaded = false;
    Future.wait(
      previews.map((element) => precacheImage((element.widget as Image).image, element)),
    ).then((_) => hasLoaded = true);
    // 実 I/O のイベントとテスト時計の継続処理を両方進め、読み込み完了まで待つ
    while (!hasLoaded) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }
    final row = tester.widget<QueuedImageRow>(find.byType(QueuedImageRow));
    await tester.runAsync(() async {
      row.onOpenSourceFile();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    expect(launchedURLs, [Uri.file(source.path).toString()]);
    await tester.runAsync(() async {
      row.onOpenFile();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    expect(launchedURLs, [Uri.file(source.path).toString(), Uri.file(output.path).toString()]);

    // 元画像が欠落した場合は専用の通知を表示し、出力画像はそのまま保持する
    source.deleteSync();
    launchedURLs.clear();
    await tester.runAsync(() async {
      row.onOpenSourceFile();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    final l10n = AppLocalizations.of(tester.element(find.byType(HomeScreen)));
    expect(find.text(l10n.openSourceFileFailed), findsOneWidget);
    expect(launchedURLs, isEmpty);
    expect(output.existsSync(), isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_squoosher/l10n/generated/app_localizations.dart';
import 'package:image_squoosher/models/github_release.dart';
import 'package:image_squoosher/services/update_check_service.dart';
import 'package:image_squoosher/ui/widgets/update_banner.dart';

/// 指定したリリース URL を持つ更新バナーを構築します。
Future<void> _pumpUpdateBanner(WidgetTester tester, String releaseURL) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('ja'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: UpdateBanner(
          result: UpdateCheckResult(
            isUpdateAvailable: true,
            currentVersion: '1.0.0',
            latestVersion: '1.1.0',
            latestRelease: GitHubRelease(
              tagName: 'v1.1.0',
              htmlURL: releaseURL,
            ),
          ),
          onDismiss: () {},
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const urlLauncherChannel = MethodChannel('plugins.flutter.io/url_launcher');
  final launchedURLs = <String>[];

  setUp(() {
    launchedURLs.clear();
    // 起動要求だけを記録し、実ブラウザへ副作用を出さず URL の検証境界を確認する
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      urlLauncherChannel,
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
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      urlLauncherChannel,
      null,
    );
  });

  testWidgets('HTTPS のホスト付きリリース URL を標準ブラウザへ渡す', (tester) async {
    const releaseURL = 'https://github.com/tsukumijima/ImageSquoosher/releases/tag/v1.1.0';
    await _pumpUpdateBanner(tester, releaseURL);

    await tester.tap(find.text('リリースを見る'));
    await tester.pump();

    expect(launchedURLs, <String>[releaseURL]);
  });

  testWidgets('HTTPS 以外またはホストのないリリース URL を開かない', (tester) async {
    for (final releaseURL in <String>[
      'http://github.com/tsukumijima/ImageSquoosher/releases/tag/v1.1.0',
      'https:///releases/tag/v1.1.0',
      'file:///tmp/release.html',
    ]) {
      await _pumpUpdateBanner(tester, releaseURL);

      await tester.tap(find.text('リリースを見る'));
      await tester.pump();

      expect(launchedURLs, isEmpty, reason: releaseURL);
    }
  });
}

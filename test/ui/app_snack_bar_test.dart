import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_squoosher/l10n/generated/app_localizations.dart';
import 'package:image_squoosher/ui/theme.dart';
import 'package:image_squoosher/ui/widgets/app_snack_bar.dart';

void main() {
  for (final language in ['ja', 'en']) {
    test('$language の通知文は句点で終わる', () async {
      final l10n = await AppLocalizations.delegate.load(Locale(language));
      // 状態ラベルとは分け、ホーム画面と更新バナーが実際に通知へ渡す文章を検査する
      final messages = <String, String>{
        'selectImagesFailed': l10n.selectImagesFailed,
        'filesAdded': l10n.filesAdded,
        'duplicateFilesSkipped': l10n.duplicateFilesSkipped,
        'noSupportedImages': l10n.noSupportedImages,
        'compressionStopped': l10n.compressionStopped,
        'conversionSucceeded': l10n.conversionSucceeded(3),
        'statusCompleted': l10n.statusCompleted(2, 1),
        'compressionFailed': l10n.compressionFailed,
        'clearConfirmation': l10n.clearConfirmation,
        'checkingUpdates': l10n.checkingUpdates,
        'upToDate': l10n.upToDate,
        'checkFailed': l10n.checkFailed,
        'openFolderFailed': l10n.openFolderFailed,
        'openFileFailed': l10n.openFileFailed,
        'defaultsRestored': l10n.defaultsRestored,
        'releaseOpenFailed': l10n.releaseOpenFailed,
      };
      for (final message in messages.entries) {
        expect(message.value, endsWith(language == 'ja' ? '。' : '.'), reason: message.key);
      }
    });

    testWidgets('$language の成功・失敗・案内通知を固有の色とアイコンで表示する', (tester) async {
      late BuildContext notificationContext;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(Colors.blue),
          locale: Locale(language),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) {
                notificationContext = context;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      final l10n = AppLocalizations.of(notificationContext);
      final cases = [
        (AppNoticeKind.success, const Color(0xff4caf50), Icons.check_circle, l10n.conversionSucceeded(3)),
        (AppNoticeKind.error, const Color(0xffff5252), Icons.cancel, l10n.compressionFailed),
        (AppNoticeKind.info, const Color(0xff2196f3), Icons.info, l10n.clearConfirmation),
      ];
      for (final (kind, color, icon, message) in cases) {
        showAppSnackBar(notificationContext, message, kind: kind);
        await tester.pumpAndSettle();
        expect(find.text(message), findsOneWidget);
        final displayedIcon = tester.widget<Icon>(find.byIcon(icon));
        expect(displayedIcon.color, Colors.white);
        final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
        expect(snackBar.backgroundColor, color);
        expect((snackBar.shape! as RoundedRectangleBorder).side, BorderSide.none);
        expect(find.text(l10n.close), findsOneWidget);
        await tester.tap(find.text(l10n.close));
        await tester.pumpAndSettle();
        expect(find.byType(SnackBar), findsNothing);
        expect(tester.takeException(), isNull);
      }
    });
  }

  testWidgets('短時間に画像を追加・クリア・変換した通知は最新の結果を優先する', (tester) async {
    late BuildContext notificationContext;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Colors.blue),
        locale: const Locale('ja'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) {
              notificationContext = context;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    final l10n = AppLocalizations.of(notificationContext);
    showAppSnackBar(notificationContext, l10n.filesAdded);
    await tester.pumpAndSettle();
    // 退場アニメーション中にも通知が増える状態を再現する
    showAppSnackBar(notificationContext, l10n.clearConfirmation);
    showAppSnackBar(notificationContext, l10n.conversionSucceeded(3), kind: AppNoticeKind.success);
    await tester.pumpAndSettle();
    expect(find.text(l10n.conversionSucceeded(3)), findsOneWidget);
    expect(find.text(l10n.filesAdded), findsNothing);
    expect(find.text(l10n.clearConfirmation), findsNothing);
    // 最新結果が消えた後に、古い通知がキューから再表示されないことを確かめる
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

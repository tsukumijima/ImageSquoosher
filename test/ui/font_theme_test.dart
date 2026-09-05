import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_squoosher/l10n/generated/app_localizations.dart';
import 'package:image_squoosher/ui/theme.dart';
import 'package:image_squoosher/ui/widgets/home_header.dart';
import 'package:image_squoosher/ui/widgets/cupertino_select.dart';

void main() {
  testWidgets('補助メニューと独自選択欄の候補も同梱 Noto Sans JP で描画する', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Colors.blue),
        locale: const Locale('ja'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Column(
            children: [
              HomeHeader(
                isCompressing: false,
                isFinderSyncEnabled: false,
                isFinderIntegrationAvailable: false,
                onAddFiles: () {},
                onFinderSettings: () {},
                onMenuAction: (_) {},
              ),
              CupertinoSelect<int>(
                value: 0,
                items: const {0: '選択中', 1: '別の候補'},
                onChanged: (_) {},
              ),
            ],
          ),
        ),
      ),
    );

    // 実際の描画スタイルを確認し、ボタン独自の TextStyle による継承切れも検出する
    void expectBundledFont(String label) {
      final richText = tester.widget<RichText>(
        find.descendant(of: find.text(label), matching: find.byType(RichText)),
      );
      expect(richText.text.style!.fontFamily, 'Noto Sans JP');
    }

    expectBundledFont('選択中');
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expectBundledFont('言語');
    await tester.tap(find.text('言語'));
    await tester.pumpAndSettle();
    expectBundledFont('日本語');
    expectBundledFont('English');
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('選択中'));
    await tester.pumpAndSettle();
    expectBundledFont('別の候補');
  });
}

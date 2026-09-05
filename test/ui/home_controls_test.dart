import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_squoosher/l10n/generated/app_localizations.dart';
import 'package:image_squoosher/models/conversion_settings.dart';
import 'package:image_squoosher/ui/theme.dart';
import 'package:image_squoosher/ui/widgets/conversion_settings_panel.dart';
import 'package:image_squoosher/ui/widgets/home_header.dart';

/// デスクトップ用の配色と日本語ロケールで操作部品を検証します。
Widget _app(Widget child) => MaterialApp(
  theme: buildAppTheme(Colors.blue),
  locale: const Locale('ja'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  testWidgets('言語サブメニューで現在の言語を示し、選択した操作を親へ渡す', (tester) async {
    HomeMenuAction? selectedAction;
    await tester.pumpWidget(
      _app(
        HomeHeader(
          isCompressing: false,
          isFinderSyncEnabled: false,
          isFinderIntegrationAvailable: false,
          onFinderSettings: () {},
          onMenuAction: (action) => selectedAction = action,
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text('English'), findsNothing);
    final restoreItem = find.ancestor(of: find.byIcon(Icons.restore), matching: find.byType(MenuItemButton));
    expect(tester.getSize(restoreItem).height, lessThanOrEqualTo(36));
    await tester.tap(find.byType(SubmenuButton));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check), findsOneWidget);
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(selectedAction, HomeMenuAction.english);
    expect(tester.takeException(), isNull);
  });

  testWidgets('画質スライダーは矢印キーで1ずつ変更できる', (tester) async {
    var settings = const ConversionSettings();
    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (context, setState) => ConversionSettingsPanel(
            settings: settings,
            onChanged: (value) => setState(() => settings = value),
          ),
        ),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(settings.quality, 91);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(settings.quality, 90);
    expect(tester.takeException(), isNull);
  });
}

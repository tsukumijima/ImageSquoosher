import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_squoosher/l10n/generated/app_localizations.dart';
import 'package:image_squoosher/models/conversion_settings.dart';
import 'package:image_squoosher/ui/theme.dart';
import 'package:image_squoosher/ui/widgets/conversion_settings_panel.dart';
import 'package:image_squoosher/ui/widgets/home_header.dart';
import 'package:image_squoosher/ui/widgets/queue_header.dart';

/// デスクトップ用の配色と指定したロケールで操作部品を検証します。
Widget _app(Widget child, {Locale locale = const Locale('ja')}) => MaterialApp(
  theme: buildAppTheme(Colors.blue),
  locale: locale,
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
          onAddFiles: () {},
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

  for (final locale in const [Locale('ja'), Locale('en')]) {
    testWidgets('${locale.languageCode} の設定パネルは通常とカスタムで同じ高さを保つ', (tester) async {
      tester.view.physicalSize = const Size(520, 560);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var settings = const ConversionSettings();
      await tester.pumpWidget(
        _app(
          StatefulBuilder(
            builder: (context, setState) => ConversionSettingsPanel(
              settings: settings,
              onChanged: (value) => setState(() => settings = value),
            ),
          ),
          locale: locale,
        ),
      );
      final panel = find.byType(ConversionSettingsPanel);
      final initialHeight = tester.getSize(panel).height;
      expect(initialHeight, lessThanOrEqualTo(270));
      final l10n = AppLocalizations.of(tester.element(panel));
      // ラベル側の押下と数値入力を通し、コンパクトな配置でも操作対象と保存値を保つ
      await tester.tap(find.text(l10n.resize));
      await tester.pump();
      expect(settings.resizeEnabled, isTrue);
      await tester.enterText(find.byKey(const ValueKey('resize-value-field')), '1280');
      await tester.pump();
      await tester.enterText(find.byKey(const ValueKey('suffix-field')), '_compact');
      await tester.pump();
      await tester.tap(find.text(l10n.exifRemoval));
      await tester.pump();
      expect(settings.stripMetadata, isTrue);
      expect(settings.resizeValue, 1280);
      expect(settings.suffix, '_compact');
      await tester.tap(find.byKey(const ValueKey('aspect-ratio-select')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(l10n.customRatio).last);
      await tester.tap(find.text(l10n.customRatio).last);
      await tester.pumpAndSettle();
      expect(tester.getSize(panel).height, initialHeight);
      final ratioField = find.byKey(const ValueKey('ratio-width-field'));
      await tester.enterText(ratioField, '3.5');
      await tester.pump();
      expect(settings.aspectRatio.horizontal, 3.5);
      expect(tester.widget<CupertinoTextField>(ratioField).controller!.text, '3.5');
      expect(tester.takeException(), isNull);
      debugPrint('${locale.languageCode} settings panel height: $initialHeight.');
    });
  }

  testWidgets('追加と解除は同じ意匠と高さで、変換中も配置を保つ', (tester) async {
    tester.view.physicalSize = const Size(520, 560);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var addCount = 0;
    var clearCount = 0;
    var isCompressing = false;
    late StateSetter rebuild;
    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return Column(
              children: [
                HomeHeader(
                  isCompressing: isCompressing,
                  isFinderSyncEnabled: false,
                  isFinderIntegrationAvailable: true,
                  onAddFiles: () => addCount += 1,
                  onFinderSettings: () {},
                  onMenuAction: (_) {},
                ),
                QueueHeader(imageCount: 12, canClear: !isCompressing, onClear: () => clearCount += 1),
              ],
            );
          },
        ),
        locale: const Locale('en'),
      ),
    );
    final buttons = find.byWidgetPredicate((widget) => widget is FilledButton);
    expect(buttons, findsNWidgets(2));
    final addBounds = tester.getRect(buttons.first);
    final clearBounds = tester.getRect(buttons.last);
    expect(addBounds.height, clearBounds.height);
    final addButton = tester.widget<FilledButton>(buttons.first);
    final clearButton = tester.widget<FilledButton>(buttons.last);
    expect(addButton.style, clearButton.style);
    await tester.tap(buttons.first);
    await tester.tap(buttons.last);
    expect(addCount, 1);
    expect(clearCount, 1);
    rebuild(() => isCompressing = true);
    await tester.pump();
    expect(tester.widget<FilledButton>(buttons.first).onPressed, isNull);
    expect(tester.widget<FilledButton>(buttons.last).onPressed, isNull);
    expect(tester.getRect(buttons.first), addBounds);
    expect(tester.getRect(buttons.last), clearBounds);
    expect(tester.takeException(), isNull);
  });
}

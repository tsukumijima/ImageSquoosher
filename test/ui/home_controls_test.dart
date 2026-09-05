import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_squoosher/l10n/generated/app_localizations.dart';
import 'package:image_squoosher/models/conversion_settings.dart';
import 'package:image_squoosher/ui/theme.dart';
import 'package:image_squoosher/ui/widgets/compression_footer.dart';
import 'package:image_squoosher/ui/widgets/conversion_settings_panel.dart';
import 'package:image_squoosher/ui/widgets/cupertino_select.dart';
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
    testWidgets('${locale.languageCode} の選択欄と候補は本文と同じ字体を使う', (tester) async {
      await tester.pumpWidget(
        _app(
          Center(
            child: SizedBox(
              width: 300,
              child: CupertinoSelect<int>(
                value: 1,
                items: const {1: '選択済み Selected', 2: '候補 Option'},
                onChanged: (_) {},
              ),
            ),
          ),
          locale: locale,
        ),
      );
      final bodyStyle = Theme.of(tester.element(find.byType(CupertinoSelect<int>))).textTheme.bodyMedium!;

      // アンカーと選択済み・未選択の候補を同じ基準で比べ、一覧を開いても字体を保つ
      for (final isOpen in [false, true]) {
        if (isOpen) {
          await tester.tap(find.byType(CupertinoButton));
          await tester.pumpAndSettle();
        }
        final labels = find.byWidgetPredicate(
          (widget) => widget is Text && const ['選択済み Selected', '候補 Option'].contains(widget.data),
        );
        expect(labels, findsNWidgets(isOpen ? 3 : 1));
        for (final element in labels.evaluate()) {
          final style = (element.widget as Text).style!;
          expect(style.fontFamily, bodyStyle.fontFamily);
          expect(style.fontFamilyFallback, bodyStyle.fontFamilyFallback);
          expect(style.fontWeight, bodyStyle.fontWeight);
          expect(style.fontSize, bodyStyle.fontSize);
        }
      }
      expect(tester.takeException(), isNull);
    });

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
      expect(initialHeight, 268);
      final l10n = AppLocalizations.of(tester.element(panel));

      // トラックの余白をゼロにした実配置を測り、入力欄の左端と画質値までの間隔を確認する
      final slider = find.byType(Slider);
      expect(tester.widget<Slider>(slider).padding, EdgeInsets.zero);
      final sliderBounds = tester.getRect(slider);
      final suffixBounds = tester.getRect(find.byKey(const ValueKey('suffix-field')));
      final aspectBounds = tester.getRect(find.byKey(const ValueKey('aspect-ratio-select')));
      final resizeBounds = tester.getRect(find.byKey(const ValueKey('resize-axis-select')));
      final qualityValue = find.ancestor(of: find.text('90'), matching: find.byType(Container));
      expect(sliderBounds.left, suffixBounds.left);
      expect(sliderBounds.left, aspectBounds.left);
      expect(tester.getRect(qualityValue).left - sliderBounds.right, 16);

      // 上から画質、出力名、寸法を確認し、その下のチェック項目とは8px空ける
      final upscaleRow = find.ancestor(of: find.text(l10n.allowUpscale), matching: find.byType(InkWell));
      expect(sliderBounds.bottom, lessThan(suffixBounds.top));
      expect(suffixBounds.bottom, lessThan(aspectBounds.top));
      expect(aspectBounds.bottom, lessThan(resizeBounds.top));
      expect(tester.getRect(upscaleRow).top - resizeBounds.bottom, 8);
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

  testWidgets('追加・解除・変換開始・停止は同じ高さと波紋を備え、変換中も配置を保つ', (tester) async {
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
                CompressionFooter(
                  completedCount: 0,
                  imageCount: 12,
                  hasValidImages: true,
                  isCompressing: isCompressing,
                  isStopping: false,
                  onStart: () {},
                  onStop: () {},
                ),
              ],
            );
          },
        ),
        locale: const Locale('en'),
      ),
    );
    final buttons = find.byWidgetPredicate((widget) => widget is FilledButton);
    expect(buttons, findsNWidgets(3));
    final addBounds = tester.getRect(buttons.first);
    final clearBounds = tester.getRect(buttons.at(1));
    expect(addBounds.height, clearBounds.height);

    // 主要操作の背景と押下フィードバックを実際の Material と InkWell で検査する
    for (final button in buttons.evaluate()) {
      final material = find.descendant(of: find.byWidget(button.widget), matching: find.byType(Material));
      final inkWell = find.descendant(of: find.byWidget(button.widget), matching: find.byType(InkWell));
      expect(tester.getSize(material).height, 37);
      expect(tester.widget<InkWell>(inkWell).splashFactory, InkRipple.splashFactory);
    }
    await tester.tap(buttons.first);
    await tester.tap(buttons.at(1));
    expect(addCount, 1);
    expect(clearCount, 1);
    rebuild(() => isCompressing = true);
    await tester.pump();
    expect(tester.widget<FilledButton>(buttons.first).onPressed, isNull);
    expect(tester.widget<FilledButton>(buttons.at(1)).onPressed, isNull);
    expect(tester.getRect(buttons.first), addBounds);
    expect(tester.getRect(buttons.at(1)), clearBounds);
    expect(tester.getSize(find.descendant(of: buttons.last, matching: find.byType(Material))).height, 37);
    expect(
      tester.widget<InkWell>(find.descendant(of: buttons.last, matching: find.byType(InkWell))).splashFactory,
      InkRipple.splashFactory,
    );
    expect(tester.takeException(), isNull);
  });
}

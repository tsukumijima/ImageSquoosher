import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_squoosher/l10n/generated/app_localizations.dart';
import 'package:image_squoosher/models/aspect_ratio.dart' as image_settings;
import 'package:image_squoosher/models/conversion_settings.dart';
import 'package:image_squoosher/models/image_dimensions.dart';
import 'package:image_squoosher/services/settings_service.dart';
import 'package:image_squoosher/services/squoosher_controller.dart';
import 'package:image_squoosher/ui/home_screen.dart';
import 'package:image_squoosher/ui/theme.dart';
import 'package:image_squoosher/ui/widgets/compression_footer.dart';
import 'package:image_squoosher/ui/widgets/conversion_settings_panel.dart';
import 'package:image_squoosher/ui/widgets/queued_image_row.dart';
import 'package:image_squoosher/ui/widgets/queue_header.dart';

/// 実ファイルの読み取りを待たず、指定した画像状態を画面へ提供するコントローラーです。
class _LayoutTestController extends SquoosherController {
  _LayoutTestController(this._testImages);

  final List<QueuedImage> _testImages;

  @override
  List<QueuedImage> get images => List.unmodifiable(_testImages);

  @override
  int get completedCount => _testImages.where((image) => image.status == QueuedImageStatus.completed).length;

  @override
  int get failedCount => _testImages.where((image) => image.status == QueuedImageStatus.failed).length;

  @override
  bool get hasValidImages => _testImages.any((image) => image.isInputValid);

  @override
  bool get hasPendingImages => _testImages.any(
    (image) => image.isInputValid && image.status != QueuedImageStatus.completed,
  );

  @override
  void removeFile(String path) {
    _testImages.removeWhere((image) => image.path == path);
    notifyListeners();
  }
}

/// ディスクアクセスを伴わず、HomeScreen へ既定設定を返すテスト用サービスです。
class _LayoutSettingsService extends SettingsService {
  _LayoutSettingsService() : super.forTesting(Directory.systemTemp);

  @override
  Future<AppPreferences> load() async => const AppPreferences();

  @override
  Future<void> save(AppPreferences preferences) async {}
}

/// Esc による終了処理で保存された設定を検査するサービスです。
class _RecordingSettingsService extends SettingsService {
  _RecordingSettingsService() : super.forTesting(Directory.systemTemp);

  int saveCount = 0;
  AppPreferences? savedPreferences;

  @override
  Future<void> save(AppPreferences preferences) async {
    saveCount += 1;
    savedPreferences = preferences;
  }
}

/// 変換中の終了要求を停止要求へ変換するコントローラーです。
class _ClosingController extends SquoosherController {
  bool didRequestStop = false;

  @override
  bool get isCompressing => true;

  @override
  void requestStop() {
    didRequestStop = true;
  }
}

/// 選択欄からのキー操作が圧縮開始へ届いた回数を記録します。
class _StartTrackingController extends _LayoutTestController {
  _StartTrackingController() : super(_normalImages());

  int startCount = 0;

  @override
  Future<bool> compress(ConversionSettings settings) async {
    startCount += 1;
    return false;
  }
}

/// 設定変更後の再構築も含めて入力欄を検査するためのホストです。
class _SettingsPanelHost extends StatefulWidget {
  const _SettingsPanelHost();

  @override
  State<_SettingsPanelHost> createState() => _SettingsPanelHostState();
}

class _SettingsPanelHostState extends State<_SettingsPanelHost> {
  ConversionSettings _settings = const ConversionSettings();

  void useCustomAspectRatio() {
    setState(
      () => _settings = const ConversionSettings(
        aspectRatio: image_settings.AspectRatio.custom(horizontal: 16, vertical: 9),
      ),
    );
  }

  void restoreDefaults() {
    setState(() => _settings = const ConversionSettings());
  }

  void rebuildWithoutChangingSettings() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return ConversionSettingsPanel(
      settings: _settings,
      onChanged: (settings) => setState(() => _settings = settings),
    );
  }
}

/// 画面サイズとロケールを固定し、プラットフォーム機能を外した HomeScreen を構築します。
Future<void> _pumpHomeScreen(
  WidgetTester tester, {
  required Size size,
  required Locale locale,
  required List<QueuedImage> images,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });

  final settingsService = _LayoutSettingsService();
  final controller = _LayoutTestController(images);
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(const Color(0xff0a84ff)),
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: HomeScreen(
        initialPreferences: const AppPreferences(),
        settingsService: settingsService,
        controller: controller,
        onLanguageChanged: (_) {},
        checkForUpdatesOnInitialize: false,
        initializePlatformServices: false,
        enableDropTarget: false,
      ),
    ),
  );
  // ファイル I/O の初期化を2フレーム進め、継続アニメーションの停止は待たずに静的な配置を検査する
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

/// 一覧へ表示する通常状態の画像を、実ファイルへ依存しない値で作ります。
List<QueuedImage> _normalImages({int count = 3}) {
  return List.generate(
    count,
    (index) => QueuedImage(
      path: '/missing/landscape-$index.jpg',
      byteLength: 104192,
      sourceDimensions: const ImageDimensions(2400, 1600),
      outputPath: '/missing/landscape-${index}_resized.jpg',
      outputDimensions: const ImageDimensions(1920, 1280),
    ),
  );
}

/// 失敗理由が加わった画像行を作り、状態表示の追加行も検査対象にします。
List<QueuedImage> _failedImages() {
  return [
    const QueuedImage(
      path: '/missing/broken-image.jpg',
      byteLength: 2048,
      sourceDimensions: ImageDimensions(800, 600),
      outputDimensions: ImageDimensions(800, 600),
      status: QueuedImageStatus.failed,
      isInputValid: false,
      errorMessage: 'The image could not be decoded.',
    ),
  ];
}

void main() {
  test('Cupertino controls inherit the system accent and Japanese font fallback', () {
    const accentColor = Color(0xff0a84ff);
    final theme = buildAppTheme(accentColor).cupertinoOverrideTheme!;
    expect(theme.primaryColor, accentColor);
    expect(theme.primaryContrastingColor, Colors.white);
    expect(theme.textTheme!.textStyle.fontSize, 14);
    expect(theme.textTheme!.textStyle.fontFamilyFallback, ['Hiragino Sans', 'Noto Sans JP', 'Noto Sans CJK JP']);
  });

  group('HomeScreen layout', () {
    for (final locale in const [Locale('ja'), Locale('en')]) {
      for (final size in const [Size(620, 680), Size(520, 560)]) {
        for (final state in ['empty', 'normal', 'failed', 'completed']) {
          testWidgets('${locale.languageCode} ${size.width}x${size.height} $state has no overflow', (tester) async {
            final images = switch (state) {
              'normal' => _normalImages(),
              'failed' => _failedImages(),
              'completed' => [
                const QueuedImage(
                  path: '/missing/landscape.jpg',
                  byteLength: 104192,
                  sourceDimensions: ImageDimensions(2400, 1600),
                  outputPath: '/missing/landscape_resized.jpg',
                  outputDimensions: ImageDimensions(1920, 1280),
                  outputByteLength: 32000,
                  status: QueuedImageStatus.completed,
                ),
              ],
              _ => <QueuedImage>[],
            };
            await _pumpHomeScreen(tester, size: size, locale: locale, images: images);

            expect(tester.takeException(), isNull);
            expect(find.byType(ConversionSettingsPanel), findsOneWidget);
            expect(find.byType(CompressionFooter), findsOneWidget);
            if (state == 'completed') {
              final row = find.byType(QueuedImageRow);
              await tester.ensureVisible(row);
              await tester.pump();
              final l10n = AppLocalizations.of(tester.element(row));
              final openFile = find.byTooltip(l10n.openFile);
              final openFolder = find.byTooltip(l10n.openFolder);
              expect(tester.getTopLeft(openFile).dy, tester.getTopLeft(openFolder).dy);
              expect(tester.getTopLeft(openFolder).dy, tester.getTopLeft(find.byTooltip(l10n.removeItem)).dy);
              expect(
                tester.getTopRight(openFolder).dx,
                lessThanOrEqualTo(tester.getTopLeft(find.byTooltip(l10n.removeItem)).dx),
              );
              final startButton = find.ancestor(
                of: find.text(l10n.start),
                matching: find.byWidgetPredicate((widget) => widget is CupertinoButton),
              );
              expect(tester.widget<CupertinoButton>(startButton).onPressed, isNull);
              expect(find.text(l10n.compressionComplete), findsOneWidget);
              expect(find.textContaining(l10n.compressionReduction('69'), findRichText: true), findsOneWidget);
              expect(
                tester.getBottomRight(row).dy,
                lessThanOrEqualTo(tester.getTopLeft(find.byType(CompressionFooter)).dy),
              );
              expect(tester.takeException(), isNull);
            }
          });
        }
      }
    }

    for (final size in const [Size(620, 680), Size(520, 560)]) {
      testWidgets('${size.width}x${size.height} scrolls only the image list while settings remain fixed', (
        tester,
      ) async {
        await _pumpHomeScreen(tester, size: size, locale: const Locale('ja'), images: _normalImages(count: 12));

        final footerTop = tester.getTopLeft(find.byType(CompressionFooter)).dy;
        final settingsBounds = tester.getRect(find.byType(ConversionSettingsPanel));
        final headerBounds = tester.getRect(find.byType(QueueHeader));
        final queueList = find.byKey(const ValueKey('image-queue-list'));
        final queueBounds = tester.getRect(queueList);
        final scrollbarBounds = tester.getRect(find.byKey(const ValueKey('image-queue-scrollbar')));
        expect(scrollbarBounds, queueBounds);
        expect(queueBounds.top, headerBounds.bottom);
        final lastRow = find.byKey(const ValueKey('/missing/landscape-11.jpg'));
        await tester.scrollUntilVisible(
          lastRow,
          150,
          scrollable: find.descendant(of: queueList, matching: find.byType(Scrollable)),
        );
        await tester.pump();
        expect(tester.getRect(find.byType(ConversionSettingsPanel)), settingsBounds);
        expect(tester.getRect(find.byType(QueueHeader)), headerBounds);
        expect(tester.getBottomRight(lastRow).dy, lessThanOrEqualTo(footerTop));
        expect(
          tester.getTopLeft(lastRow).dy,
          greaterThan(tester.getBottomRight(find.byType(ConversionSettingsPanel)).dy),
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('English setting labels remain on one line at 520 width', (tester) async {
      await _pumpHomeScreen(
        tester,
        size: const Size(520, 560),
        locale: const Locale('en'),
        images: _normalImages(),
      );

      for (final label in [
        'Quality',
        'Aspect ratio',
        'Filename suffix',
        'Resize',
        'Allow upscaling',
        'Overwrite original files',
        'Remove camera and location data (EXIF)',
      ]) {
        final text = tester.widget<Text>(find.text(label));
        expect(text.maxLines, 1, reason: label);
        expect(text.softWrap, isFalse, reason: label);
      }
    });

    testWidgets('conversion start uses white text and icons while image addition uses a neutral color', (tester) async {
      await _pumpHomeScreen(
        tester,
        size: const Size(620, 680),
        locale: const Locale('ja'),
        images: _normalImages(),
      );

      final buttons = find.ancestor(
        of: find.text('変換開始'),
        matching: find.byType(CupertinoButton),
      );
      expect(buttons, findsOneWidget);
      final addButton = tester.widget<FilledButton>(
        find.ancestor(of: find.text('画像を追加'), matching: find.byWidgetPredicate((widget) => widget is FilledButton)),
      );
      final colorScheme = Theme.of(tester.element(find.byWidget(addButton))).colorScheme;
      expect(addButton.style!.backgroundColor!.resolve({}), colorScheme.surfaceContainerHighest);
      for (final element in buttons.evaluate()) {
        final button = element.widget as CupertinoButton;
        if (button.onPressed != null) {
          final label = find.descendant(of: find.byWidget(button), matching: find.byType(Text)).first;
          expect(DefaultTextStyle.of(tester.element(label)).style.color, Colors.white);
          for (final icon in find.descendant(of: find.byWidget(button), matching: find.byType(Icon)).evaluate()) {
            expect(IconTheme.of(icon).color, Colors.white);
          }
        }
      }
    });
  });

  testWidgets('allow upscaling is disabled with resize and retains its saved value', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(const Color(0xff0a84ff)),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: _SettingsPanelHost()),
      ),
    );
    final hostState = tester.state<_SettingsPanelHostState>(find.byType(_SettingsPanelHost));
    final label = find.text('Allow upscaling');
    final row = find.ancestor(of: label, matching: find.byType(InkWell)).first;
    final checkbox = find.descendant(of: row, matching: find.byType(CupertinoCheckbox));
    final semantics = find.ancestor(of: row, matching: find.byType(Semantics)).first;
    final originalBounds = tester.getRect(row);

    // 無効時はチェック本体とラベルの両方を操作対象から外す
    expect(tester.widget<CupertinoCheckbox>(checkbox).onChanged, isNull);
    expect(tester.widget<InkWell>(row).onTap, isNull);
    expect(tester.widget<Semantics>(semantics).properties.enabled, isFalse);
    expect(tester.widget<Text>(label).style!.color, Theme.of(tester.element(label)).disabledColor);
    final resizeField = find.byKey(const ValueKey('resize-value-field'));
    expect(
      tester.widget<CupertinoTextField>(resizeField).style!.color,
      Theme.of(tester.element(resizeField)).disabledColor,
    );
    await tester.tap(label);
    await tester.tap(checkbox);
    await tester.pump();
    expect(hostState._settings.allowUpscale, isTrue);

    // リサイズを有効にすると拡大を選択でき、再度無効にしても選択値と配置を保持する
    await tester.tap(find.text('Resize'));
    await tester.pump();
    expect(tester.widget<Semantics>(semantics).properties.enabled, isTrue);
    await tester.tap(label);
    await tester.pump();
    expect(hostState._settings.allowUpscale, isFalse);
    await tester.tap(find.text('Resize'));
    await tester.pump();
    expect(tester.widget<CupertinoCheckbox>(checkbox).onChanged, isNull);
    expect(tester.widget<CupertinoCheckbox>(checkbox).value, isFalse);
    expect(tester.getRect(row), originalBounds);
    await tester.tap(label);
    await tester.pump();
    expect(hostState._settings.allowUpscale, isFalse);
    await tester.tap(find.text('Resize'));
    await tester.pump();
    expect(tester.widget<CupertinoCheckbox>(checkbox).onChanged, isNotNull);
    expect(tester.widget<CupertinoCheckbox>(checkbox).value, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings text controllers keep continuous input across rebuilds', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(520, 560);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(const Color(0xff0a84ff)),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: _SettingsPanelHost()),
      ),
    );

    final suffixField = find.byKey(const ValueKey('suffix-field'));
    await tester.tap(suffixField);
    await tester.enterText(suffixField, '_thumb');
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);
    await tester.enterText(suffixField, '_thumbnail');
    await tester.pump();
    expect(find.text('_thumbnail'), findsOneWidget);

    await tester.enterText(suffixField, r'../unsafe');
    await tester.pump();
    expect(find.text('_thumbnail'), findsOneWidget);

    await tester.tap(find.text('Resize'));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('resize-value-field')), '1280');
    await tester.pump();
    expect(find.text('1280'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('overwrite disables the adjacent suffix field while preserving its value and bounds', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(const Color(0xff0a84ff)),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: _SettingsPanelHost()),
      ),
    );
    final suffixField = find.byKey(const ValueKey('suffix-field'));
    await tester.enterText(suffixField, '_thumbnail');
    await tester.pump();
    final suffixBounds = tester.getRect(suffixField);
    final overwriteRow = find.ancestor(of: find.text('Overwrite original files'), matching: find.byType(InkWell)).first;
    final overwriteBounds = tester.getRect(overwriteRow);
    expect(suffixBounds.top - overwriteBounds.bottom, closeTo(6, 0.01));
    expect(overwriteBounds.height, 26);
    final upscalingBounds = tester.getRect(
      find.ancestor(of: find.text('Allow upscaling'), matching: find.byType(InkWell)).first,
    );
    final exifBounds = tester.getRect(
      find.ancestor(of: find.text('Remove camera and location data (EXIF)'), matching: find.byType(InkWell)).first,
    );
    expect(upscalingBounds.height, 26);
    expect(exifBounds.height, 26);
    expect(exifBounds.top - upscalingBounds.bottom, 0);
    expect(overwriteBounds.top - exifBounds.bottom, 0);

    // 出力名の切り替え後も入力欄を同じ位置に保ち、元のサフィックスへ戻せる状態を確認する
    await tester.tap(overwriteRow);
    await tester.pump();
    expect(tester.widget<CupertinoTextField>(suffixField).enabled, isFalse);
    expect(
      tester.widget<CupertinoTextField>(suffixField).style!.color,
      Theme.of(tester.element(suffixField)).disabledColor,
    );
    expect(tester.widget<CupertinoTextField>(suffixField).controller!.text, '_thumbnail');
    expect(tester.getRect(suffixField), suffixBounds);
    expect(tester.getRect(overwriteRow), overwriteBounds);
    await tester.tap(overwriteRow);
    await tester.pump();
    expect(tester.widget<CupertinoTextField>(suffixField).enabled, isTrue);
    expect(tester.widget<CupertinoTextField>(suffixField).controller!.text, '_thumbnail');
    expect(tester.takeException(), isNull);
  });

  testWidgets('numeric settings fields keep intermediate input across parent rebuilds', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(520, 560);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(const Color(0xff0a84ff)),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: _SettingsPanelHost()),
      ),
    );

    final hostState = tester.state<_SettingsPanelHostState>(find.byType(_SettingsPanelHost));
    hostState.useCustomAspectRatio();
    await tester.pump();

    final ratioWidthField = find.byKey(const ValueKey('ratio-width-field'));
    await tester.tap(ratioWidthField);
    await tester.enterText(ratioWidthField, '');
    hostState.rebuildWithoutChangingSettings();
    await tester.pump();
    expect(tester.widget<CupertinoTextField>(ratioWidthField).controller!.text, isEmpty);

    await tester.enterText(ratioWidthField, '2.50');
    await tester.pump();
    expect(tester.widget<CupertinoTextField>(ratioWidthField).controller!.text, '2.50');
    expect(hostState._settings.aspectRatio.horizontal, 2.5);

    // 整数の範囲より大きい有限値も、編集終了後の表示から同じ数値を読み取れることを確認する
    await tester.enterText(ratioWidthField, '1e20');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('ratio-height-field')));
    await tester.pump();
    expect(double.parse(tester.widget<CupertinoTextField>(ratioWidthField).controller!.text), 1e20);

    await tester.tap(find.text('Resize'));
    await tester.pumpAndSettle();
    final resizeValueField = find.byKey(const ValueKey('resize-value-field'));
    await tester.showKeyboard(resizeValueField);
    await tester.enterText(resizeValueField, '007');
    await tester.pump();
    expect(tester.widget<CupertinoTextField>(resizeValueField).controller!.text, '007');
    expect(hostState._settings.resizeValue, 7);

    hostState.restoreDefaults();
    await tester.pump();
    expect(tester.widget<CupertinoTextField>(resizeValueField).controller!.text, '1920');
  });

  testWidgets('numeric settings fields restore saved values when focus leaves invalid input', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(const Color(0xff0a84ff)),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: _SettingsPanelHost()),
      ),
    );
    final hostState = tester.state<_SettingsPanelHostState>(find.byType(_SettingsPanelHost));
    hostState.useCustomAspectRatio();
    await tester.pump();
    await tester.tap(find.text('Resize'));
    await tester.pump();

    // 有効値の更新後に無効な入力を残し、フォーカス移動だけで実効設定へ戻ることを確認する
    for (final fieldKey in ['ratio-width-field', 'ratio-height-field', 'resize-value-field']) {
      final field = find.byKey(ValueKey(fieldKey));
      await tester.enterText(field, '7');
      await tester.pump();
      for (final invalidInput in ['0', '', 'invalid', 'Infinity', '1e309', 'NaN']) {
        await tester.enterText(field, invalidInput);
        await tester.pump();
        expect(tester.widget<CupertinoTextField>(field).controller!.text, invalidInput);
        expect(hostState._settings.resizeValue, fieldKey == 'resize-value-field' ? 7 : 1920);
        await tester.tap(find.byKey(const ValueKey('suffix-field')));
        await tester.pump();
        expect(
          tester.widget<CupertinoTextField>(field).controller!.text,
          '7',
        );
      }
    }
    expect(hostState._settings.aspectRatio.horizontal, 7);
    expect(hostState._settings.aspectRatio.vertical, 7);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Enter restores invalid resize input before compression', (tester) async {
    await _pumpHomeScreen(tester, size: const Size(520, 560), locale: const Locale('en'), images: []);
    await tester.tap(find.text('Resize'));
    await tester.pump();
    final resizeField = find.byKey(const ValueKey('resize-value-field'));
    await tester.enterText(resizeField, '0');
    await tester.pump();
    expect(tester.widget<CupertinoTextField>(resizeField).controller!.text, '0');

    // 入力欄にフォーカスを置いたまま、画面の開始ショートカットを実行する
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(tester.widget<CupertinoTextField>(resizeField).controller!.text, '1920');
    expect(tester.widget<CupertinoTextField>(resizeField).focusNode!.hasFocus, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('thumbnail decoding constrains only the cover axis at physical pixel size', (tester) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(1240, 1360);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });

    for (final testCase in <({ImageDimensions dimensions, int? width, int? height})>[
      (dimensions: const ImageDimensions(100, 100), width: 96, height: null),
      (dimensions: const ImageDimensions(200, 100), width: null, height: 54),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(const Color(0xff0a84ff)),
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: QueuedImageRow(
              queuedImage: QueuedImage(path: '/nonexistent.jpg', sourceDimensions: testCase.dimensions),
              settings: const ConversionSettings(
                aspectRatio: image_settings.AspectRatio.preset(image_settings.AspectRatioPreset.ratio16x9),
              ),
              canRemove: true,
              onOpenFile: () {},
              onOpenFolder: () {},
              onRemove: () {},
            ),
          ),
        ),
      );

      final imageWidget = tester.widget<Image>(
        find.descendant(of: find.byType(QueuedImageRow), matching: find.byType(Image)),
      );
      final resizeImage = imageWidget.image as ResizeImage;
      expect(resizeImage.width, testCase.width);
      expect(resizeImage.height, testCase.height);
    }
  });

  testWidgets('completed thumbnails use the output file and its saved aspect ratio', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(const Color(0xff0a84ff)),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: QueuedImageRow(
            queuedImage: const QueuedImage(
              path: '/removed-input.png',
              sourceDimensions: ImageDimensions(2400, 1600),
              outputPath: '/completed-output.jpg',
              outputDimensions: ImageDimensions(1920, 1080),
              status: QueuedImageStatus.completed,
              isInputValid: false,
            ),
            settings: const ConversionSettings(
              aspectRatio: image_settings.AspectRatio.preset(image_settings.AspectRatioPreset.square),
            ),
            canRemove: true,
            onOpenFile: () {},
            onOpenFolder: () {},
            onRemove: () {},
          ),
        ),
      ),
    );

    // 削除した元入力や、その後変更した比率から独立して、保存済みの出力を表示する
    final thumbnail = tester.widget<Image>(find.byType(Image));
    final provider = (thumbnail.image as ResizeImage).imageProvider as FileImage;
    expect(provider.file.path, '/completed-output.jpg');
    expect(tester.widget<AspectRatio>(find.byType(AspectRatio)).aspectRatio, 16 / 9);
  });

  testWidgets('quality supports Tab and arrow keys within encoder limits', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(const Color(0xff0a84ff)),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: _SettingsPanelHost()),
      ),
    );

    // 最初の設定へ Tab で入り、実際のキー入力から画質を変更する
    final host = tester.state<_SettingsPanelHostState>(find.byType(_SettingsPanelHost));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<Slider>(), isNotNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(host._settings.quality, 91);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(host._settings.quality, 90);

    // 端に到達した後の入力も含め、エンコーダーが扱える範囲へ収まることを確認する
    for (var index = 0; index < 15; index += 1) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
    }
    expect(host._settings.quality, 100);
    for (var index = 0; index < 105; index += 1) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
    }
    expect(host._settings.quality, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('custom aspect ratio stays on one row at minimum width', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(520, 560);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(const Color(0xff0a84ff)),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: _SettingsPanelHost()),
      ),
    );

    tester.state<_SettingsPanelHostState>(find.byType(_SettingsPanelHost)).useCustomAspectRatio();
    await tester.pump();

    expect(find.byKey(const ValueKey('ratio-width-field')), findsOneWidget);
    expect(find.byKey(const ValueKey('ratio-height-field')), findsOneWidget);
    final widthBounds = tester.getRect(find.byKey(const ValueKey('ratio-width-field')));
    final heightBounds = tester.getRect(find.byKey(const ValueKey('ratio-height-field')));
    final suffixBounds = tester.getRect(find.byKey(const ValueKey('suffix-field')));
    final resizeBounds = tester.getRect(find.byKey(const ValueKey('resize-value-field')));
    expect(widthBounds.top, heightBounds.top);
    expect(heightBounds.right, suffixBounds.right);
    expect(resizeBounds.right, suffixBounds.right);
    expect(widthBounds.width, greaterThan(40));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Cupertino selects preserve keyboard selection and disabled resize values', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(520, 560);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(const Color(0xff0a84ff)).copyWith(platform: TargetPlatform.macOS),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: Padding(padding: EdgeInsets.only(top: 80), child: _SettingsPanelHost()),
        ),
      ),
    );

    // 無効な基準辺はクリックしても設定と表示を保つ
    final host = tester.state<_SettingsPanelHostState>(find.byType(_SettingsPanelHost));
    await tester.tap(find.byKey(const ValueKey('resize-axis-select')));
    await tester.pumpAndSettle();
    expect(host._settings.resizeAxis, ResizeAxis.width);
    expect(find.text('Resize by height'), findsNothing);

    // 候補を上下キーで移動して確定し、カスタム入力への切り替えも確認する
    await tester.tap(find.byKey(const ValueKey('aspect-ratio-select')));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(host._settings.aspectRatio.preset, image_settings.AspectRatioPreset.ratio9x16);
    await tester.tap(find.byKey(const ValueKey('aspect-ratio-select')));
    await tester.pumpAndSettle();
    final menuScroll = find.descendant(
      of: find.byType(CupertinoScrollbar),
      matching: find.byType(SingleChildScrollView),
    );
    // マウスホイールの入力でも一覧を開いたまま下端の候補へ移動できることを確認する
    await tester.sendEventToBinding(
      PointerScrollEvent(position: tester.getCenter(menuScroll), scrollDelta: const Offset(0, 240)),
    );
    await tester.pumpAndSettle();
    expect(menuScroll, findsOneWidget);
    await tester.drag(menuScroll, const Offset(0, -240));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Custom').last);
    await tester.tap(find.text('Custom').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ratio-width-field')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'scrolling ratio options leaves the image list scroll position unchanged',
    (tester) async {
      await _pumpHomeScreen(
        tester,
        size: const Size(520, 560),
        locale: const Locale('en'),
        images: _normalImages(),
      );
      final screenScroll = tester.state<ScrollableState>(
        find.descendant(of: find.byKey(const ValueKey('image-queue-list')), matching: find.byType(Scrollable)),
      );
      final initialOffset = screenScroll.position.pixels;
      await tester.tap(find.byKey(const ValueKey('aspect-ratio-select')));
      await tester.pumpAndSettle();
      final menuScroll = find.descendant(
        of: find.byType(CupertinoScrollbar),
        matching: find.byType(SingleChildScrollView),
      );

      // 一覧の端までホイールを回しても、背後の設定画面とアンカー位置を保持する
      for (final distance in [20.0, 240.0, 240.0]) {
        await tester.sendEventToBinding(
          PointerScrollEvent(position: tester.getCenter(menuScroll), scrollDelta: Offset(0, distance)),
        );
        await tester.pumpAndSettle();
        expect(menuScroll, findsOneWidget);
        expect(screenScroll.position.pixels, initialOffset);
      }
      expect(find.text('Custom').hitTestable(), findsOneWidget);
      await tester.tap(find.text('Custom').hitTestable());
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ratio-width-field')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets('Enter selects a ratio and then starts compression', (tester) async {
    final controller = _StartTrackingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(const Color(0xff0a84ff)),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: HomeScreen(
          initialPreferences: const AppPreferences(),
          settingsService: _LayoutSettingsService(),
          controller: controller,
          onLanguageChanged: (_) {},
          checkForUpdatesOnInitialize: false,
          initializePlatformServices: false,
          enableDropTarget: false,
        ),
      ),
    );
    await tester.pump();

    // 一覧内の Enter は選択を確定し、一覧を閉じた後の Enter は圧縮を開始する
    await tester.tap(find.byKey(const ValueKey('aspect-ratio-select')));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(controller.startCount, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(controller.startCount, 1);
  });

  testWidgets('Esc closes a select before it exits the app', (tester) async {
    var exitCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(const Color(0xff0a84ff)),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: HomeScreen(
          initialPreferences: const AppPreferences(),
          settingsService: _LayoutSettingsService(),
          onExitRequested: () async => exitCount += 1,
          onLanguageChanged: (_) {},
          checkForUpdatesOnInitialize: false,
          initializePlatformServices: false,
          enableDropTarget: false,
        ),
      ),
    );
    await tester.pump();

    // 最初の Esc で一覧を閉じて画面を残し、次の Esc で終了することを確認する
    await tester.tap(find.byKey(const ValueKey('aspect-ratio-select')));
    await tester.pumpAndSettle();
    expect(find.text('16:9'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('16:9'), findsNothing);
    expect(exitCount, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(exitCount, 1);
  });

  testWidgets('Esc flushes pending preferences before requesting exit', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(520, 560);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    final settingsService = _RecordingSettingsService();
    var exitCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(const Color(0xff0a84ff)),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: HomeScreen(
          initialPreferences: const AppPreferences(),
          settingsService: settingsService,
          onExitRequested: () async {
            exitCount += 1;
          },
          onLanguageChanged: (_) {},
          checkForUpdatesOnInitialize: false,
          initializePlatformServices: false,
          enableDropTarget: false,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Resize'));
    await tester.pump();
    expect(settingsService.saveCount, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(settingsService.saveCount, 1);
    expect(settingsService.savedPreferences?.conversionSettings.resizeEnabled, isTrue);
    expect(exitCount, 1);
  });

  testWidgets('close during compression requests a stop and keeps the result screen', (tester) async {
    final controller = _ClosingController();
    addTearDown(controller.dispose);
    var exitCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(const Color(0xff0a84ff)),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: HomeScreen(
          initialPreferences: const AppPreferences(),
          settingsService: _LayoutSettingsService(),
          controller: controller,
          onExitRequested: () async {
            exitCount += 1;
          },
          onLanguageChanged: (_) {},
          checkForUpdatesOnInitialize: false,
          initializePlatformServices: false,
          enableDropTarget: false,
        ),
      ),
    );
    await tester.pump();

    final homeState = tester.state<HomeScreenState>(find.byType(HomeScreen));
    // 変換中は設定のフォーカス取得を拒否し、矢印キーでも画質を保持する
    final qualityFocus = Focus.of(tester.element(find.byType(Slider)));
    qualityFocus.requestFocus();
    await tester.pump();
    expect(qualityFocus.hasFocus, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(tester.widget<Slider>(find.byType(Slider)).value, 90);
    await homeState.handleWindowClose();

    expect(controller.didRequestStop, isTrue);
    expect(exitCount, 0);
    expect(find.byType(CompressionFooter), findsOneWidget);
  });
}

import 'dart:io';

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
List<QueuedImage> _normalImages() {
  return List.generate(
    3,
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
  group('HomeScreen layout', () {
    for (final locale in const [Locale('ja'), Locale('en')]) {
      for (final size in const [Size(620, 680), Size(520, 560)]) {
        for (final state in ['empty', 'normal', 'failed']) {
          testWidgets('${locale.languageCode} ${size.width}x${size.height} $state has no overflow', (tester) async {
            final images = switch (state) {
              'normal' => _normalImages(),
              'failed' => _failedImages(),
              _ => <QueuedImage>[],
            };
            await _pumpHomeScreen(tester, size: size, locale: locale, images: images);

            expect(tester.takeException(), isNull);
            expect(find.byType(ConversionSettingsPanel), findsOneWidget);
            expect(find.byType(CompressionFooter), findsOneWidget);
          });
        }
      }
    }

    testWidgets('620x680 shows three complete normal image rows', (tester) async {
      await _pumpHomeScreen(
        tester,
        size: const Size(620, 680),
        locale: const Locale('ja'),
        images: _normalImages(),
      );

      final footerTop = tester.getTopLeft(find.byType(CompressionFooter)).dy;
      final rows = find.byType(QueuedImageRow);
      expect(rows, findsNWidgets(3));
      for (final element in rows.evaluate()) {
        expect(tester.getBottomRight(find.byWidget(element.widget)).dy, lessThanOrEqualTo(footerTop));
      }
    });

    testWidgets('520x560 shows two complete normal image rows', (tester) async {
      await _pumpHomeScreen(
        tester,
        size: const Size(520, 560),
        locale: const Locale('en'),
        images: _normalImages(),
      );

      final footerTop = tester.getTopLeft(find.byType(CompressionFooter)).dy;
      final visibleRows = find
          .byType(QueuedImageRow)
          .evaluate()
          .where((element) => tester.getBottomRight(find.byWidget(element.widget)).dy <= footerTop)
          .length;
      expect(visibleRows, greaterThanOrEqualTo(2));
    });

    testWidgets('English setting labels remain on one line at 520 width', (tester) async {
      await _pumpHomeScreen(
        tester,
        size: const Size(520, 560),
        locale: const Locale('en'),
        images: _normalImages(),
      );

      for (final label in [
        'Quality',
        'Crop aspect ratio',
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

    testWidgets('enabled filled buttons use white text and icons', (tester) async {
      await _pumpHomeScreen(
        tester,
        size: const Size(620, 680),
        locale: const Locale('ja'),
        images: _normalImages(),
      );

      for (final button in tester.widgetList<FilledButton>(find.byType(FilledButton))) {
        expect(button.style?.foregroundColor?.resolve(<WidgetState>{}), Colors.white);
      }
    });
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
    expect(tester.takeException(), isNull);
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
    await homeState.handleWindowClose();

    expect(controller.didRequestStop, isTrue);
    expect(exitCount, 0);
    expect(find.byType(CompressionFooter), findsOneWidget);
  });
}

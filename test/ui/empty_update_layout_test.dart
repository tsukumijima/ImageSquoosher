import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_squoosher/l10n/generated/app_localizations.dart';
import 'package:image_squoosher/services/settings_service.dart';
import 'package:image_squoosher/services/update_check_service.dart';
import 'package:image_squoosher/ui/home_screen.dart';
import 'package:image_squoosher/ui/theme.dart';
import 'package:image_squoosher/ui/widgets/conversion_settings_panel.dart';
import 'package:image_squoosher/ui/widgets/empty_drop_area.dart';
import 'package:image_squoosher/ui/widgets/update_banner.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// ウィンドウ寸法の検証で利用者の保存設定を更新する必要がないため、保存だけをメモリ内で完結します。
class _LayoutSettingsService extends SettingsService {
  _LayoutSettingsService() : super.forTesting(Directory.systemTemp);

  @override
  Future<void> save(AppPreferences preferences) async {}
}

void main() {
  for (final locale in const [Locale('ja'), Locale('en')]) {
    testWidgets('${locale.languageCode} の最小ウィンドウで更新バナーと空一覧が収まる', (tester) async {
      tester.view.physicalSize = const Size(520, 560);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      PackageInfo.setMockInitialValues(
        appName: 'ImageSquoosher',
        packageName: 'net.tsukumijima.image-squoosher',
        version: '0.1.0',
        buildNumber: '1',
        buildSignature: '',
      );
      // 更新サービスの通常の解析経路を通し、外部通信だけを固定したリリース情報へ置き換える
      UpdateCheckService.instance.clearCache();
      addTearDown(UpdateCheckService.instance.clearCache);
      final result = await http.runWithClient(
        () => UpdateCheckService.instance.check(force: true),
        () => MockClient(
          (_) async =>
              http.Response(jsonEncode({'tag_name': 'v0.2.0', 'html_url': 'https://example.com/release'}), 200),
        ),
      );
      expect(result.isUpdateAvailable, isTrue);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(const Color(0xff0a84ff)),
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: HomeScreen(
            initialPreferences: const AppPreferences(),
            settingsService: _LayoutSettingsService(),
            onLanguageChanged: (_) {},
            initializePlatformServices: false,
            enableDropTarget: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(UpdateBanner), findsOneWidget);
      expect(find.byType(EmptyDropArea), findsOneWidget);
      expect(tester.getSize(find.byType(ConversionSettingsPanel)).height, 268);
      expect(tester.takeException(), isNull);
      final l10n = AppLocalizations.of(tester.element(find.byType(EmptyDropArea)));
      expect(find.text(l10n.idle), findsOneWidget);
      expect(find.byTooltip(l10n.emptyDescription), findsOneWidget);

      // バナーを閉じると説明文が戻り、空一覧の追加操作を引き続き案内する
      await tester.tap(find.byTooltip(l10n.dismiss));
      await tester.pumpAndSettle();
      expect(find.byType(UpdateBanner), findsNothing);
      expect(find.text(l10n.emptyDescription), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

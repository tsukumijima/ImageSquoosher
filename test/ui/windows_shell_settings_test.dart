import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_squoosher/l10n/generated/app_localizations.dart';
import 'package:image_squoosher/services/settings_service.dart';
import 'package:image_squoosher/ui/home_screen.dart';

void main() {
  const channel = MethodChannel('net.tsukumijima.image-squoosher/finder_sync');

  for (final shouldFail in [false, true]) {
    testWidgets('Explorer 連携の登録${shouldFail ? '失敗時は無効状態を保持する' : '成功後に有効状態を表示する'}', (tester) async {
      final temporaryDirectory = Directory.systemTemp.createTempSync('image-squoosher-shell-test-');
      addTearDown(() => temporaryDirectory.deleteSync(recursive: true));
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final registrations = <bool>[];
      // レジストリの変更結果だけを差し替え、画面の成功・失敗表示を検査する
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        switch (call.method) {
          case 'getFinderSelectedImageURLs':
            return <String>[];
          case 'isWindowsShellIntegrationEnabled':
            return false;
          case 'setWindowsShellIntegrationEnabled':
            expect((call.arguments as Map)['label'], 'ImageSquoosher で圧縮・リサイズ');
            registrations.add((call.arguments as Map)['enabled'] as bool);
            if (shouldFail) {
              throw PlatformException(code: 'registration_failed');
            }
            return null;
        }
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ja'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: HomeScreen(
            initialPreferences: const AppPreferences(),
            settingsService: SettingsService.forTesting(temporaryDirectory),
            onLanguageChanged: (_) {},
            checkForUpdatesOnInitialize: false,
            enableDropTarget: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Explorer 連携を管理'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(registrations, [true]);
      expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value, !shouldFail);
      expect(find.text('右クリック連携を変更できませんでした。もう一度お試しください。'), shouldFail ? findsOneWidget : findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    }, skip: !Platform.isWindows);
  }
}

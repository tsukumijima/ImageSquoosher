import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_squoosher/l10n/generated/app_localizations.dart';
import 'package:image_squoosher/services/settings_service.dart';
import 'package:image_squoosher/ui/home_screen.dart';

void main() {
  const channel = MethodChannel('net.tsukumijima.image-squoosher/finder_sync');
  final shieldIcon = Uint8List.fromList(const [
    0x89,
    0x50,
    0x4e,
    0x47,
    0x0d,
    0x0a,
    0x1a,
    0x0a,
    0x00,
    0x00,
    0x00,
    0x0d,
    0x49,
    0x48,
    0x44,
    0x52,
    0x00,
    0x00,
    0x00,
    0x01,
    0x00,
    0x00,
    0x00,
    0x01,
    0x08,
    0x06,
    0x00,
    0x00,
    0x00,
    0x1f,
    0x15,
    0xc4,
    0x89,
    0x00,
    0x00,
    0x00,
    0x0d,
    0x49,
    0x44,
    0x41,
    0x54,
    0x78,
    0x9c,
    0x63,
    0x60,
    0x60,
    0x60,
    0x60,
    0x00,
    0x00,
    0x00,
    0x04,
    0x00,
    0x01,
    0x27,
    0x0a,
    0x35,
    0x9b,
    0x00,
    0x00,
    0x00,
    0x00,
    0x49,
    0x45,
    0x4e,
    0x44,
    0xae,
    0x42,
    0x60,
    0x82,
  ]);

  Future<void> pumpHome(
    WidgetTester tester, {
    required Future<Object?> Function(MethodCall call) handler,
  }) async {
    final temporaryDirectory = Directory.systemTemp.createTempSync('image-squoosher-shell-test-');
    addTearDown(() => temporaryDirectory.deleteSync(recursive: true));
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, handler);
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
  }

  testWidgets('未登録の右クリック連携を直接追加し、完了後に状態を再取得する', (tester) async {
    var status = 'disabled';
    final registrations = <Map<Object?, Object?>>[];
    var shieldRequests = 0;
    await pumpHome(
      tester,
      handler: (call) async {
        switch (call.method) {
          case 'getFinderSelectedImageURLs':
            return <String>[];
          case 'getWindowsShellIntegrationStatus':
            return status;
          case 'getWindowsUACShieldIcon':
            shieldRequests += 1;
            return shieldIcon;
          case 'setWindowsShellIntegrationEnabled':
            final arguments = call.arguments as Map<Object?, Object?>;
            registrations.add(arguments);
            status = 'enabled';
            return null;
        }
        return null;
      },
    );

    expect(find.byTooltip('Explorer の右クリックメニューに追加'), findsOneWidget);
    await tester.tap(find.byTooltip('Explorer の右クリックメニューに追加'));
    await tester.pumpAndSettle();

    expect(registrations, [
      {'enabled': true, 'label': 'ImageSquoosher で圧縮・リサイズ'},
    ]);
    expect(shieldRequests, greaterThanOrEqualTo(2));
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Explorer の右クリックメニューに追加しました。'), findsOneWidget);
    expect(find.byTooltip('Explorer の右クリックメニューから削除'), findsOneWidget);
  }, skip: !Platform.isWindows);

  testWidgets('登録済みの右クリック連携を直接削除する', (tester) async {
    var status = 'enabled';
    final registrations = <Map<Object?, Object?>>[];
    await pumpHome(
      tester,
      handler: (call) async {
        switch (call.method) {
          case 'getFinderSelectedImageURLs':
            return <String>[];
          case 'getWindowsShellIntegrationStatus':
            return status;
          case 'getWindowsUACShieldIcon':
            return shieldIcon;
          case 'setWindowsShellIntegrationEnabled':
            final arguments = call.arguments as Map<Object?, Object?>;
            registrations.add(arguments);
            status = 'disabled';
            return null;
        }
        return null;
      },
    );

    expect(find.byTooltip('Explorer の右クリックメニューから削除'), findsOneWidget);
    await tester.tap(find.byTooltip('Explorer の右クリックメニューから削除'));
    await tester.pumpAndSettle();

    expect(registrations, [
      {'enabled': false, 'label': ''},
    ]);
    expect(find.text('Explorer の右クリックメニューから削除しました。'), findsOneWidget);
    expect(find.byTooltip('Explorer の右クリックメニューに追加'), findsOneWidget);
  }, skip: !Platform.isWindows);

  testWidgets('配置が移動した状態では修復操作を直接実行する', (tester) async {
    var status = 'repair';
    final registrations = <Map<Object?, Object?>>[];
    await pumpHome(
      tester,
      handler: (call) async {
        switch (call.method) {
          case 'getFinderSelectedImageURLs':
            return <String>[];
          case 'getWindowsShellIntegrationStatus':
            return status;
          case 'getWindowsUACShieldIcon':
            return shieldIcon;
          case 'setWindowsShellIntegrationEnabled':
            final arguments = call.arguments as Map<Object?, Object?>;
            registrations.add(arguments);
            status = 'enabled';
            return null;
        }
        return null;
      },
    );

    expect(find.byTooltip('Explorer の右クリック連携を修復'), findsOneWidget);
    await tester.tap(find.byTooltip('Explorer の右クリック連携を修復'));
    await tester.pumpAndSettle();

    expect(registrations, [
      {'enabled': true, 'label': 'ImageSquoosher で圧縮・リサイズ'},
    ]);
    expect(find.text('Explorer の右クリック連携を修復しました。'), findsOneWidget);
  }, skip: !Platform.isWindows);

  testWidgets('登録失敗時は状態を保持して失敗通知を表示する', (tester) async {
    await pumpHome(
      tester,
      handler: (call) async {
        switch (call.method) {
          case 'getFinderSelectedImageURLs':
            return <String>[];
          case 'getWindowsShellIntegrationStatus':
            return 'disabled';
          case 'getWindowsUACShieldIcon':
            return shieldIcon;
          case 'setWindowsShellIntegrationEnabled':
            throw PlatformException(code: 'registration_failed', details: 5);
        }
        return null;
      },
    );

    await tester.tap(find.byTooltip('Explorer の右クリックメニューに追加'));
    await tester.pumpAndSettle();

    expect(find.text('Explorer 連携を変更できませんでした。\nもう一度お試しください。'), findsOneWidget);
    expect(find.byTooltip('Explorer の右クリックメニューに追加'), findsOneWidget);
  }, skip: !Platform.isWindows);

  for (final cancelledDetails in [1223, 0x800704C7]) {
    testWidgets('UAC 確認のキャンセルコード $cancelledDetails はキャンセル通知にする', (tester) async {
      await pumpHome(
        tester,
        handler: (call) async {
          switch (call.method) {
            case 'getFinderSelectedImageURLs':
              return <String>[];
            case 'getWindowsShellIntegrationStatus':
              return 'disabled';
            case 'getWindowsUACShieldIcon':
              return shieldIcon;
            case 'setWindowsShellIntegrationEnabled':
              throw PlatformException(code: 'registration_cancelled', details: cancelledDetails);
          }
          return null;
        },
      );

      await tester.tap(find.byTooltip('Explorer の右クリックメニューに追加'));
      await tester.pumpAndSettle();

      expect(find.text('Explorer 連携の変更をキャンセルしました。'), findsOneWidget);
      expect(find.byTooltip('Explorer の右クリックメニューに追加'), findsOneWidget);
    }, skip: !Platform.isWindows);
  }

  testWidgets('Explorer 連携の変更中はボタンを無効化してスピナーを表示する', (tester) async {
    final operation = Completer<void>();
    await pumpHome(
      tester,
      handler: (call) async {
        switch (call.method) {
          case 'getFinderSelectedImageURLs':
            return <String>[];
          case 'getWindowsShellIntegrationStatus':
            return 'disabled';
          case 'getWindowsUACShieldIcon':
            return shieldIcon;
          case 'setWindowsShellIntegrationEnabled':
            await operation.future;
            return null;
        }
        return null;
      },
    );

    final integrationButton = find.byTooltip('Explorer の右クリックメニューに追加');
    await tester.tap(integrationButton);
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.widget<IconButton>(find.byType(IconButton).first).onPressed, isNull);

    operation.complete();
    await tester.pumpAndSettle();
  }, skip: !Platform.isWindows);
}

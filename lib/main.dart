/// ImageSquoosher のエントリポイント。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:system_theme/system_theme.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'models/settings.dart';
import 'services/logging_service.dart';
import 'services/settings_service.dart';

/// デスクトップアプリケーションを起動する。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 設定やプラットフォーム初期化の失敗を追跡できるよう、最初にログ出力先を準備する
  await LoggingService.instance.initialize();
  await SystemTheme.accentColor.load();

  // ディスク読み込みを1回で終え、同じ設定スナップショットをウィンドウと UI へ渡す
  await SettingsService.instance.initialize();
  final settingsSnapshot = await SettingsService.instance.loadSnapshot();

  // 前回の寸法だけを復元し、起動するたびに現在のディスプレイ中央へ配置する
  await windowManager.ensureInitialized();
  final windowSettings = settingsSnapshot.windowSettings;
  final windowOptions = WindowOptions(
    size: Size(windowSettings.width, windowSettings.height),
    minimumSize: const Size(windowMinWidth, windowMinHeight),
    center: false,
    title: '',
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.normal,
  );
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    if (Platform.isMacOS) {
      await const MethodChannel(
        'net.tsukumijima.image-squoosher/finder_sync',
      ).invokeMethod<void>('centerOnPointerScreen');
    }
    await windowManager.show();
    await windowManager.focus();
  });

  LoggingService.instance.info('Window ready, starting application.', tag: 'Main');
  runApp(ImageSquoosherApp(initialSettings: settingsSnapshot));
}

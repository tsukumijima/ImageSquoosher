/// アプリケーションのルートウィジェット。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:system_theme/system_theme.dart';
import 'package:window_manager/window_manager.dart';

import 'l10n/generated/app_localizations.dart';
import 'services/logging_service.dart';
import 'services/settings_service.dart';
import 'services/squoosher_controller.dart';
import 'services/window_settings_save_queue.dart';
import 'ui/home_screen.dart';
import 'ui/theme.dart';

/// ImageSquoosher アプリケーションを構成するルートウィジェット。
class ImageSquoosherApp extends StatefulWidget {
  /// 起動時の設定と永続化サービスをアプリ全体へ渡す。
  /// @param key ウィジェットを識別するキー
  /// @param initialSettings 起動時に適用する設定。省略時は既定値を使う
  /// @param settingsService 設定の読み書きに使うサービス。省略時は共有インスタンスを使う
  ImageSquoosherApp({super.key, SettingsSnapshot? initialSettings, SettingsService? settingsService})
    : initialSettings = initialSettings ?? SettingsSnapshot.defaults(),
      settingsService = settingsService ?? SettingsService.instance;

  /// 起動時に一度だけ読み込んだ設定のスナップショット。
  final SettingsSnapshot initialSettings;

  /// テスト時に保存先を差し替えるための設定サービス。
  final SettingsService settingsService;

  /// StatefulWidget の状態を生成する。
  /// @returns アプリケーション状態
  @override
  State<ImageSquoosherApp> createState() => _ImageSquoosherAppState();
}

class _ImageSquoosherAppState extends State<ImageSquoosherApp> with WindowListener {
  final _homeKey = GlobalKey<HomeScreenState>();
  late Locale _locale;
  late final SquoosherController _controller;
  late final WindowSettingsSaveQueue _windowSettingsSaveQueue;
  bool _isExiting = false;

  /// 設定スナップショットの言語と変換キューを初期化する。
  @override
  void initState() {
    super.initState();
    _locale = Locale(widget.initialSettings.preferences.languageCode);
    _controller = SquoosherController();
    _windowSettingsSaveQueue = WindowSettingsSaveQueue(
      save: _saveWindowSettings,
      onError: _logWindowSettingsSaveError,
    );
    windowManager.addListener(this);
    unawaited(windowManager.setPreventClose(true));
  }

  /// アプリが所有する変換キューを破棄する。
  @override
  void dispose() {
    _windowSettingsSaveQueue.dispose();
    windowManager.removeListener(this);
    _controller.dispose();
    super.dispose();
  }

  /// 現在のウィンドウサイズだけを設定サービスへ保存する。
  Future<void> _saveWindowSettings() async {
    final size = await windowManager.getSize();
    await widget.settingsService.saveWindowSettings(WindowSettings(width: size.width, height: size.height));
  }

  /// 保存失敗をログへ残し、次の保存を実行できる状態へ戻す。
  /// @param error 保存時に発生したエラー
  /// @param stackTrace エラー発生時のスタックトレース
  void _logWindowSettingsSaveError(Object error, StackTrace stackTrace) {
    LoggingService.instance.error(
      'Failed to save window settings.',
      tag: 'App',
      error: error,
      stackTrace: stackTrace,
    );
  }

  /// 終了前に保留中のサイズ保存と直列化済みの保存を完了させる。
  Future<void> _flushWindowSettings() async {
    await _windowSettingsSaveQueue.flush();
  }

  /// HomeScreen の設定保存後にログとウィンドウを終了する。
  Future<void> _exitApplication() async {
    if (_isExiting) {
      return;
    }
    _isExiting = true;
    await _flushWindowSettings();
    await LoggingService.instance.dispose();
    await windowManager.destroy();
  }

  @override
  void onWindowClose() {
    if (_controller.isCompressing) {
      _controller.requestStop();
      return;
    }
    final homeState = _homeKey.currentState;
    if (homeState == null) {
      unawaited(_exitApplication());
      return;
    }
    unawaited(homeState.handleWindowClose());
  }

  @override
  void onWindowResized() {
    _windowSettingsSaveQueue.schedule();
  }

  @override
  void onWindowFocus() {
    unawaited(_homeKey.currentState?.refreshFinderSyncStatus());
  }

  /// 設定画面から受け取った言語をアプリ全体へ反映する。
  /// @param languageCode 適用する言語コード
  void _updateLocale(String languageCode) {
    final locale = Locale(languageCode);
    if (_locale != locale) {
      setState(() => _locale = locale);
    }
  }

  /// テーマ、表示言語、メイン画面を構築する。
  /// @param context ウィジェットツリーの BuildContext
  /// @returns アプリケーション画面
  @override
  Widget build(BuildContext context) {
    return SystemThemeBuilder(
      builder: (context, accentColor) => MaterialApp(
        title: 'ImageSquoosher',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(accentColor.accent),
        locale: _locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: HomeScreen(
          key: _homeKey,
          initialPreferences: widget.initialSettings.preferences,
          settingsService: widget.settingsService,
          controller: _controller,
          onExitRequested: _exitApplication,
          onLanguageChanged: _updateLocale,
        ),
      ),
    );
  }
}

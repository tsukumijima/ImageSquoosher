/// アプリケーション設定を JSON ファイルとして永続化するサービス
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/conversion_settings.dart';
import '../models/settings.dart';
import 'logging_service.dart';

export '../models/settings.dart' show AppPreferences, SettingsSnapshot, WindowSettings;

/// 変換条件と表示言語の設定ファイル名
const String _preferencesFileName = 'settings.json';

/// ウィンドウ状態の設定ファイル名
const String _windowSettingsFileName = 'window_settings.json';

/// Application Support 内でアプリ設定を管理する。
class SettingsService {
  /// 指定された保存先、または OS の標準保存先を使用する。
  SettingsService._({Directory? directoryOverride}) : _directoryOverride = directoryOverride;

  /// アプリ全体で共有するシングルトンインスタンス
  static final SettingsService instance = SettingsService._();

  final LoggingService _log = LoggingService.instance;
  final Directory? _directoryOverride;
  String? _settingsDirectoryPath;
  SettingsSnapshot? _cachedSnapshot;

  /// テスト用の保存先を指定したサービスを作成する。
  SettingsService.forTesting(Directory directory) : this._(directoryOverride: directory);

  /// 設定ディレクトリを作成し、保存先を確定する。
  Future<void> initialize() async {
    if (_settingsDirectoryPath != null) {
      return;
    }

    final settingsDirectory = _directoryOverride ?? _resolveSettingsDirectory();
    await settingsDirectory.create(recursive: true);
    _settingsDirectoryPath = settingsDirectory.path;
    _log.info('Settings service initialized: ${settingsDirectory.path}.', tag: 'Settings');
  }

  /// 変換・表示・ウィンドウ設定を起動時の単一スナップショットとして読み込む。
  Future<SettingsSnapshot> loadSnapshot() async {
    await initialize();
    if (_cachedSnapshot != null) {
      _log.debug('Using cached settings snapshot.', tag: 'Settings');
      return _cachedSnapshot!;
    }

    final preferences = await _loadPreferences();
    final windowSettings = await _loadWindowSettings();
    _cachedSnapshot = SettingsSnapshot(preferences: preferences, windowSettings: windowSettings);
    return _cachedSnapshot!;
  }

  /// UI へスナップショット内の変換条件と表示言語を返す。
  Future<AppPreferences> load() async => (await loadSnapshot()).preferences;

  /// スナップショット内のウィンドウ状態を返す。
  Future<WindowSettings> loadWindowSettings() async => (await loadSnapshot()).windowSettings;

  /// 変換条件と表示言語を保存し、共有スナップショットを更新する。
  Future<void> save(AppPreferences preferences) async {
    final snapshot = await loadSnapshot();
    await File(_preferencesPath).writeAsString(const JsonEncoder.withIndent('  ').convert(preferences.toJson()));
    _cachedSnapshot = SettingsSnapshot(
      preferences: preferences,
      windowSettings: _cachedSnapshot?.windowSettings ?? snapshot.windowSettings,
    );
    _log.info('Application preferences saved.', tag: 'Settings');
  }

  /// ウィンドウ状態を専用ファイルへ保存し、共有スナップショットを更新する。
  Future<void> saveWindowSettings(WindowSettings windowSettings) async {
    final snapshot = await loadSnapshot();
    await File(_windowSettingsPath).writeAsString(const JsonEncoder.withIndent('  ').convert(windowSettings.toJson()));
    _cachedSnapshot = SettingsSnapshot(
      preferences: _cachedSnapshot?.preferences ?? snapshot.preferences,
      windowSettings: windowSettings,
    );
    _log.debug('Window settings saved.', tag: 'Settings');
  }

  /// 次回の読み込みでディスクから新しいスナップショットを構築する。
  void clearCache() {
    _cachedSnapshot = null;
  }

  /// 設定ディレクトリのパスを取得する。
  String? get settingsDirectoryPath => _settingsDirectoryPath;

  /// 変換条件と表示言語を読み込み、上書き指定を起動ごとに無効化する。
  Future<AppPreferences> _loadPreferences() async {
    final preferencesFile = File(_preferencesPath);
    if (await preferencesFile.exists() == false) {
      _log.debug('No saved application preferences found, using defaults.', tag: 'Settings');
      return AppPreferences.defaults();
    }

    try {
      final json = jsonDecode(await preferencesFile.readAsString()) as Map<String, dynamic>;
      final savedPreferences = AppPreferences.fromJson(json);
      final preferences = savedPreferences.copyWith(
        conversionSettings: _withOverwrite(savedPreferences.conversionSettings, false),
      );
      _log.info('Application preferences loaded.', tag: 'Settings');
      return preferences;
    } catch (error, stackTrace) {
      // 破損した保存値はログへ残し、初回起動と同じ安全な設定でアプリを開始する
      _log.error(
        'Failed to parse application preferences, using defaults.',
        tag: 'Settings',
        error: error,
        stackTrace: stackTrace,
      );
      return AppPreferences.defaults();
    }
  }

  /// 保存済みのウィンドウサイズを読み込む。
  Future<WindowSettings> _loadWindowSettings() async {
    final windowSettingsFile = File(_windowSettingsPath);
    if (await windowSettingsFile.exists() == false) {
      _log.debug('No saved window settings found, using defaults.', tag: 'Settings');
      return WindowSettings.defaults();
    }

    try {
      final json = jsonDecode(await windowSettingsFile.readAsString()) as Map<String, dynamic>;
      final windowSettings = WindowSettings.fromJson(json);
      _log.info('Window settings loaded: ${windowSettings.width}x${windowSettings.height}.', tag: 'Settings');
      return windowSettings;
    } catch (error, stackTrace) {
      // 読み取れない寸法は復元せず、操作可能な既定ウィンドウを用意する
      _log.error(
        'Failed to parse window settings, using defaults.',
        tag: 'Settings',
        error: error,
        stackTrace: stackTrace,
      );
      return WindowSettings.defaults();
    }
  }

  /// 既存の変換条件を保ちながら上書き指定だけを変更する。
  static ConversionSettings _withOverwrite(ConversionSettings settings, bool isOverwriteEnabled) {
    return ConversionSettings(
      aspectRatio: settings.aspectRatio,
      quality: settings.quality,
      resizeEnabled: settings.resizeEnabled,
      resizeAxis: settings.resizeAxis,
      resizeValue: settings.resizeValue,
      allowUpscale: settings.allowUpscale,
      stripMetadata: settings.stripMetadata,
      suffix: settings.suffix,
      overwrite: isOverwriteEnabled,
    );
  }

  /// OS ごとのアプリケーションデータ領域から設定ディレクトリを決定する。
  Directory _resolveSettingsDirectory() {
    final String basePath;
    if (Platform.isMacOS) {
      basePath = p.join(Platform.environment['HOME'] ?? Directory.systemTemp.path, 'Library', 'Application Support');
    } else if (Platform.isWindows) {
      basePath =
          Platform.environment['APPDATA'] ??
          p.join(Platform.environment['USERPROFILE'] ?? Directory.systemTemp.path, 'AppData', 'Roaming');
    } else {
      basePath = p.join(Platform.environment['HOME'] ?? Directory.systemTemp.path, '.local', 'share');
    }
    return Directory(p.join(basePath, 'ImageSquoosher'));
  }

  /// 変換条件と表示言語の保存先を取得する。
  String get _preferencesPath {
    _ensureInitialized();
    return p.join(_settingsDirectoryPath!, _preferencesFileName);
  }

  /// ウィンドウ状態の保存先を取得する。
  String get _windowSettingsPath {
    _ensureInitialized();
    return p.join(_settingsDirectoryPath!, _windowSettingsFileName);
  }

  /// 初期化後だけ保存先を参照できる状態にする。
  void _ensureInitialized() {
    if (_settingsDirectoryPath == null) {
      throw StateError('SettingsService is not initialized. Call initialize() first.');
    }
  }
}

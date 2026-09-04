/// アプリケーション設定とウィンドウ設定のモデル定義。
library;

import 'dart:io' show Platform;
import 'dart:ui' show Locale;

import 'package:json_annotation/json_annotation.dart';

import 'aspect_ratio.dart';
import 'conversion_settings.dart';

part 'settings.g.dart';

/// ウィンドウの最小幅。
const double windowMinWidth = 520;

/// ウィンドウの最小高さ。
const double windowMinHeight = 560;

/// ウィンドウの既定幅。
const double windowDefaultWidth = 620;

/// ウィンドウの既定高さ。
const double windowDefaultHeight = 680;

/// アプリの表示言語。
enum AppLanguage {
  /// 日本語。
  japanese,

  /// 英語。
  english,
}

/// 表示言語をロケールと相互変換する。
extension AppLanguageExtension on AppLanguage {
  /// ロケールコードを取得する。
  String get localeCode => this == AppLanguage.japanese ? 'ja' : 'en';

  /// Flutter のロケールを取得する。
  Locale get locale => Locale(localeCode);

  /// OS のロケールから初回起動時の表示言語を決定する。
  static AppLanguage fromPlatformLocale() {
    return Platform.localeName.toLowerCase().startsWith('ja') ? AppLanguage.japanese : AppLanguage.english;
  }

  /// 保存されたロケールコードを表示言語へ変換する。
  static AppLanguage fromLocaleCode(String localeCode) {
    return localeCode == 'ja' ? AppLanguage.japanese : AppLanguage.english;
  }
}

/// 変換条件と表示言語を保持する。
@JsonSerializable()
class AppPreferences {
  /// 変換条件と表示言語を保持する。
  const AppPreferences({
    this.conversionSettings = const ConversionSettings(),
    this.languageCode = 'ja',
  });

  /// 画像の変換条件。
  @_ConversionSettingsJsonConverter()
  final ConversionSettings conversionSettings;

  /// 表示言語のロケールコード。
  @JsonKey(fromJson: _languageCodeFromJson, toJson: _languageCodeToJson)
  final String languageCode;

  /// 初回起動時の表示言語へ OS のロケールを反映した既定値を取得する。
  factory AppPreferences.defaults() {
    return AppPreferences(languageCode: AppLanguageExtension.fromPlatformLocale().localeCode);
  }

  /// JSON から設定を復元する。
  ///
  /// 平坦な JSON と入れ子の JSON の両形式から利用者の変換条件を読み込む。
  factory AppPreferences.fromJson(Map<String, dynamic> json) {
    if (json['conversionSettings'] is Map<String, dynamic>) {
      final preferences = _$AppPreferencesFromJson(json);
      return json.containsKey('languageCode')
          ? preferences
          : preferences.copyWith(languageCode: AppLanguageExtension.fromPlatformLocale().localeCode);
    }

    return AppPreferences(
      conversionSettings: const _ConversionSettingsJsonConverter().fromJson(json),
      languageCode: _languageCodeFromJson(json['languageCode']),
    );
  }

  /// JSON へ保存できる値へ変換する。
  Map<String, dynamic> toJson() => _$AppPreferencesToJson(this);

  /// 指定した項目だけを更新した設定を返す。
  AppPreferences copyWith({
    ConversionSettings? conversionSettings,
    String? languageCode,
  }) {
    return AppPreferences(
      conversionSettings: conversionSettings ?? this.conversionSettings,
      languageCode: languageCode ?? this.languageCode,
    );
  }

  /// 表示言語を取得する。
  AppLanguage get language => AppLanguageExtension.fromLocaleCode(languageCode);
}

/// 次回起動時に復元するウィンドウサイズを保持する。
@JsonSerializable()
class WindowSettings {
  /// ウィンドウサイズを保持する。
  const WindowSettings({this.width = windowDefaultWidth, this.height = windowDefaultHeight});

  /// ウィンドウの幅。
  final double width;

  /// ウィンドウの高さ。
  final double height;

  /// 既定のウィンドウ状態を取得する。
  factory WindowSettings.defaults() => const WindowSettings();

  /// JSON からウィンドウ状態を復元する。
  factory WindowSettings.fromJson(Map<String, dynamic> json) {
    final settings = _$WindowSettingsFromJson(json);
    return WindowSettings(
      width: settings.width.clamp(windowMinWidth, 10000).toDouble(),
      height: settings.height.clamp(windowMinHeight, 10000).toDouble(),
    );
  }

  /// JSON へ保存できる値へ変換する。
  Map<String, dynamic> toJson() => _$WindowSettingsToJson(this);

  /// 指定した項目だけを更新したウィンドウ状態を返す。
  WindowSettings copyWith({double? width, double? height}) {
    return WindowSettings(
      width: width ?? this.width,
      height: height ?? this.height,
    );
  }
}

/// 起動時に一度読み込み、アプリ全体で共有する設定のスナップショット。
class SettingsSnapshot {
  /// 変換・表示設定とウィンドウ状態を一組で保持する。
  const SettingsSnapshot({required this.preferences, required this.windowSettings});

  /// 変換条件と表示言語。
  final AppPreferences preferences;

  /// ウィンドウ状態。
  final WindowSettings windowSettings;

  /// OS のロケールを反映した初回起動用スナップショットを取得する。
  factory SettingsSnapshot.defaults() {
    return SettingsSnapshot(
      preferences: AppPreferences.defaults(),
      windowSettings: WindowSettings.defaults(),
    );
  }
}

/// 変換条件を既存モデルの形を保ったまま JSON と相互変換する。
class _ConversionSettingsJsonConverter implements JsonConverter<ConversionSettings, Map<String, dynamic>> {
  /// 変換コアへ JSON 依存を持ち込まず、永続化層で形式を変換する。
  const _ConversionSettingsJsonConverter();

  /// JSON から変換条件を復元する。
  @override
  ConversionSettings fromJson(Map<String, dynamic> json) {
    final presetName = json['aspectRatioPreset'] as String?;
    final preset = AspectRatioPreset.values.where((value) => value.name == presetName).firstOrNull;
    final horizontal = (json['aspectRatioHorizontal'] as num?)?.toDouble() ?? 1;
    final vertical = (json['aspectRatioVertical'] as num?)?.toDouble() ?? 1;
    final resizeAxisName = json['resizeAxis'] as String?;
    final resizeAxis = ResizeAxis.values.where((value) => value.name == resizeAxisName).firstOrNull ?? ResizeAxis.width;
    final resizeValue = (json['resizeValue'] as num?)?.toInt();

    return ConversionSettings(
      aspectRatio: preset == null
          ? AspectRatio.custom(horizontal: horizontal > 0 ? horizontal : 1, vertical: vertical > 0 ? vertical : 1)
          : AspectRatio.preset(preset),
      quality: ((json['quality'] as num?)?.toInt() ?? 90).clamp(1, 100),
      resizeEnabled: json['resizeEnabled'] as bool? ?? false,
      resizeAxis: resizeAxis,
      resizeValue: resizeValue != null && resizeValue > 0 ? resizeValue : 1920,
      allowUpscale: json['allowUpscale'] as bool? ?? true,
      stripMetadata: json['stripMetadata'] as bool? ?? false,
      suffix: json['suffix'] as String? ?? '_resized',
      overwrite: json['overwrite'] as bool? ?? false,
    );
  }

  /// 変換条件を JSON へ保存できる値へ変換する。
  @override
  Map<String, dynamic> toJson(ConversionSettings settings) {
    return {
      'quality': settings.quality,
      'aspectRatioPreset': settings.aspectRatio.preset?.name,
      'aspectRatioHorizontal': settings.aspectRatio.horizontal,
      'aspectRatioVertical': settings.aspectRatio.vertical,
      'resizeEnabled': settings.resizeEnabled,
      'resizeAxis': settings.resizeAxis.name,
      'resizeValue': settings.resizeValue,
      'allowUpscale': settings.allowUpscale,
      'stripMetadata': settings.stripMetadata,
      'suffix': settings.suffix,
      'overwrite': settings.overwrite,
    };
  }
}

/// 保存値を対応するロケールコードへ正規化する。
String _languageCodeFromJson(Object? value) {
  if (value == 'ja' || value == 'en') {
    return value! as String;
  }
  return AppLanguageExtension.fromPlatformLocale().localeCode;
}

/// 対応するロケールコードだけを保存する。
String _languageCodeToJson(String value) => value == 'ja' ? 'ja' : 'en';

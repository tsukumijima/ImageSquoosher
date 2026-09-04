// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'settings.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AppPreferences _$AppPreferencesFromJson(Map<String, dynamic> json) => AppPreferences(
  conversionSettings: json['conversionSettings'] == null
      ? const ConversionSettings()
      : const _ConversionSettingsJsonConverter().fromJson(
          json['conversionSettings'] as Map<String, dynamic>,
        ),
  languageCode: json['languageCode'] == null ? 'ja' : _languageCodeFromJson(json['languageCode']),
);

Map<String, dynamic> _$AppPreferencesToJson(AppPreferences instance) => <String, dynamic>{
  'conversionSettings': const _ConversionSettingsJsonConverter().toJson(
    instance.conversionSettings,
  ),
  'languageCode': _languageCodeToJson(instance.languageCode),
};

WindowSettings _$WindowSettingsFromJson(Map<String, dynamic> json) => WindowSettings(
  width: (json['width'] as num?)?.toDouble() ?? windowDefaultWidth,
  height: (json['height'] as num?)?.toDouble() ?? windowDefaultHeight,
);

Map<String, dynamic> _$WindowSettingsToJson(WindowSettings instance) => <String, dynamic>{
  'width': instance.width,
  'height': instance.height,
};

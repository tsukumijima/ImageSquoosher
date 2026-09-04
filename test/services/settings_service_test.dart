import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_squoosher/models/conversion_settings.dart';
import 'package:image_squoosher/services/settings_service.dart';

void main() {
  group('SettingsService', () {
    late Directory temporaryDirectory;
    late SettingsService settingsService;

    setUp(() async {
      temporaryDirectory = await Directory.systemTemp.createTemp('image-squoosher-settings-test-');
      settingsService = SettingsService.forTesting(temporaryDirectory);
      await settingsService.initialize();
    });

    tearDown(() async {
      await temporaryDirectory.delete(recursive: true);
    });

    test('変換設定と言語を復元し、上書きだけは起動ごとに無効へ戻す', () async {
      await settingsService.save(
        const AppPreferences(
          conversionSettings: ConversionSettings(quality: 82, suffix: '_web', overwrite: true),
          languageCode: 'en',
        ),
      );

      settingsService.clearCache();
      final restored = await settingsService.loadSnapshot();

      expect(restored.preferences.languageCode, 'en');
      expect(restored.preferences.conversionSettings.quality, 82);
      expect(restored.preferences.conversionSettings.suffix, '_web');
      expect(restored.preferences.conversionSettings.overwrite, isFalse);
    });

    test('ウィンドウは寸法だけを専用ファイルから復元する', () async {
      await settingsService.saveWindowSettings(const WindowSettings(width: 700, height: 740));

      settingsService.clearCache();
      final restored = await settingsService.loadWindowSettings();

      expect(restored.width, 700);
      expect(restored.height, 740);
      final json = await File('${temporaryDirectory.path}${Platform.pathSeparator}window_settings.json').readAsString();
      expect(json, isNot(contains('position')));
      expect(json, isNot(contains('maximized')));
    });
  });
}

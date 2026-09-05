import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_squoosher/l10n/generated/app_localizations.dart';
import 'package:image_squoosher/models/conversion_settings.dart';
import 'package:image_squoosher/models/aspect_ratio.dart' as image_ratio;
import 'package:image_squoosher/models/image_dimensions.dart';
import 'package:image_squoosher/services/squoosher_controller.dart';
import 'package:image_squoosher/ui/theme.dart';
import 'package:image_squoosher/ui/widgets/queued_image_row.dart';
import 'package:image_squoosher/ui/widgets/compression_footer.dart';

void main() {
  testWidgets('長い画像名でも結果を表示し、待機・処理・成功・失敗で高さと操作位置を保つ', (tester) async {
    await tester.binding.setSurfaceSize(const Size(620, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const queued = QueuedImage(
      path: '/tmp/PXL_20260816_060330996.jpg',
      byteLength: 8 * 1024 * 1024,
      sourceDimensions: ImageDimensions(6192, 4128),
      outputPath: '/tmp/PXL_20260816_060330996_resized.jpg',
      outputDimensions: ImageDimensions(1920, 1280),
    );
    Offset? folderPosition;
    for (final status in [
      QueuedImageStatus.queued,
      QueuedImageStatus.processing,
      QueuedImageStatus.completed,
      QueuedImageStatus.failed,
    ]) {
      final isCompleted = status == QueuedImageStatus.completed;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(Colors.blue),
          locale: const Locale('ja'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(20),
              child: QueuedImageRow(
                queuedImage: queued.copyWith(
                  status: status,
                  progress: 0.45,
                  outputByteLength: isCompleted ? 2 * 1024 * 1024 : null,
                ),
                settings: const ConversionSettings(),
                canRemove: status != QueuedImageStatus.processing,
                onOpenFile: () {},
                onOpenFolder: () {},
                onRemove: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(QueuedImageRow)).height, 64);
      final folder = find.widgetWithIcon(IconButton, Icons.folder_open);
      expect(tester.widget<IconButton>(folder).onPressed, isNotNull);
      folderPosition ??= tester.getTopLeft(folder);
      expect(tester.getTopLeft(folder), folderPosition);
      final openFile = tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.open_in_new));
      expect(openFile.onPressed, isCompleted ? isNotNull : isNull);
      expect(find.byType(IconButton), findsNWidgets(3));
      final progress = tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
      expect(progress.value, isCompleted ? 1 : 0.45);
      if (isCompleted) {
        expect(find.text(' (2.0MB / 75% 圧縮!)'), findsOneWidget);
        expect(progress.color, AppColors.success);
      }
      if (status != QueuedImageStatus.failed) {
        expect(find.text('6192×4128 (3:2) → 1920×1280 (3:2)'), findsOneWidget);
      }
    }
  });

  testWidgets('任意の元比率とカスタム比率はリサイズの丸め後も短い表記を維持する', (tester) async {
    final cases = [
      (
        const ConversionSettings(),
        const ImageDimensions(1792, 1024),
        const ImageDimensions(2560, 1463),
        '1792×1024 (7:4) → 2560×1463 (7:4)',
      ),
      (
        const ConversionSettings(aspectRatio: image_ratio.AspectRatio.custom(horizontal: 11, vertical: 7)),
        const ImageDimensions(1792, 1024),
        const ImageDimensions(1920, 1222),
        '1792×1024 (7:4) → 1920×1222 (11:7)',
      ),
      (
        const ConversionSettings(aspectRatio: image_ratio.AspectRatio.customRatio(1.7)),
        const ImageDimensions(1792, 1024),
        const ImageDimensions(1920, 1129),
        '1792×1024 (7:4) → 1920×1129 (1.7:1)',
      ),
      (
        const ConversionSettings(aspectRatio: image_ratio.AspectRatio.custom(horizontal: 11, vertical: 7)),
        const ImageDimensions(1792, 1024),
        const ImageDimensions(2560, 1463),
        '1792×1024 (7:4) → 2560×1463 (7:4)',
      ),
    ];
    for (final (settings, source, output, expectedText) in cases) {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(Colors.blue),
          locale: const Locale('ja'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: QueuedImageRow(
              queuedImage: QueuedImage(
                path: '/tmp/ratio.jpg',
                sourceDimensions: source,
                outputDimensions: output,
              ),
              settings: settings,
              canRemove: true,
              onOpenFile: () {},
              onOpenFolder: () {},
              onRemove: () {},
            ),
          ),
        ),
      );
      expect(find.text(expectedText), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('全体進捗をフッター下端に配置し、完了後も緑色で保持する', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Colors.blue),
        locale: const Locale('ja'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          bottomNavigationBar: CompressionFooter(
            completedCount: 3,
            imageCount: 3,
            hasValidImages: false,
            isCompressing: false,
            isStopping: false,
            onStart: () {},
            onStop: () {},
          ),
        ),
      ),
    );
    final indicator = find.byType(LinearProgressIndicator);
    expect(tester.widget<LinearProgressIndicator>(indicator).value, 1);
    expect(tester.widget<LinearProgressIndicator>(indicator).color, AppColors.success);
    expect(
      tester.getBottomRight(indicator).dy,
      tester.getBottomRight(find.byType(Scaffold)).dy,
    );
    expect(tester.takeException(), isNull);
  });
}

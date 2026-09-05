import 'package:flutter_test/flutter_test.dart';
import 'package:image_squoosher/models/aspect_ratio.dart';
import 'package:image_squoosher/models/conversion_settings.dart';
import 'package:image_squoosher/models/image_dimensions.dart';

void main() {
  test('preserves original-ratio rounding at a half pixel', () {
    const settings = ConversionSettings(
      resizeEnabled: true,
      resizeAxis: ResizeAxis.height,
      resizeValue: 360,
    );
    expect(settings.plan(const ImageDimensions(7, 80)).output, const ImageDimensions(32, 360));
  });

  for (final height in [360, 720]) {
    test('keeps the selected ratio after an integer crop at height $height', () {
      final settings = ConversionSettings(
        aspectRatio: const AspectRatio.preset(AspectRatioPreset.ratio16x9),
        resizeEnabled: true,
        resizeAxis: ResizeAxis.height,
        resizeValue: height,
      );
      expect(settings.plan(const ImageDimensions(1000, 1000)).output, ImageDimensions(height * 16 ~/ 9, height));
    });
  }

  test('keeps the cropped pixels when the requested size would enlarge them', () {
    const settings = ConversionSettings(
      aspectRatio: AspectRatio.preset(AspectRatioPreset.ratio16x9),
      resizeEnabled: true,
      resizeAxis: ResizeAxis.height,
      resizeValue: 720,
      allowUpscale: false,
    );
    expect(settings.plan(const ImageDimensions(1000, 1000)).output, const ImageDimensions(1000, 562));
  });

  test('provides the supported aspect ratio presets', () {
    expect(AspectRatioPreset.ratio3x2.value, closeTo(3 / 2, 0.0001));
    expect(AspectRatioPreset.ratio2x3.value, closeTo(2 / 3, 0.0001));
    expect(AspectRatioPreset.ratio4x5.value, closeTo(4 / 5, 0.0001));
    expect(AspectRatioPreset.ratio5x4.value, closeTo(5 / 4, 0.0001));
    expect(AspectRatioPreset.ogp.value, closeTo(1.91, 0.0001));
  });

  test('accepts a custom horizontal and vertical ratio', () {
    const ratio = AspectRatio.custom(horizontal: 5, vertical: 4);

    expect(ratio.resolve(const ImageDimensions(1000, 1000)), 1.25);
    expect(ratio.label, '5:4');
  });

  test('keeps the source ratio when Original is selected', () {
    const settings = ConversionSettings();

    expect(
      settings.plan(const ImageDimensions(4000, 3000)).crop,
      const CropRect(left: 0, top: 0, width: 4000, height: 3000),
    );
  });

  test('uses the specified defaults without enabling resize', () {
    const settings = ConversionSettings();

    expect(settings.resizeValue, 1920);
    expect(settings.allowUpscale, isTrue);
    expect(settings.plan(const ImageDimensions(4000, 3000)).output, const ImageDimensions(4000, 3000));
  });

  group('calculateCenterCrop', () {
    test('crops the sides for a wider source', () {
      expect(
        calculateCenterCrop(const ImageDimensions(4000, 2000), 1),
        const CropRect(left: 1000, top: 0, width: 2000, height: 2000),
      );
    });

    test('crops the top and bottom for a taller source', () {
      expect(
        calculateCenterCrop(const ImageDimensions(2000, 4000), 1),
        const CropRect(left: 0, top: 1000, width: 2000, height: 2000),
      );
    });

    test('keeps the source when the ratio already matches', () {
      expect(
        calculateCenterCrop(const ImageDimensions(1600, 900), 16 / 9),
        const CropRect(left: 0, top: 0, width: 1600, height: 900),
      );
    });
  });

  group('calculateOutputDimensions', () {
    test('uses width as the resize basis', () {
      expect(
        calculateOutputDimensions(
          const ImageDimensions(4000, 2000),
          targetWidth: 1000,
        ),
        const ImageDimensions(1000, 500),
      );
    });

    test('uses height as the resize basis', () {
      expect(
        calculateOutputDimensions(
          const ImageDimensions(4000, 2000),
          targetHeight: 500,
        ),
        const ImageDimensions(1000, 500),
      );
    });

    test('prevents enlargement by default', () {
      expect(
        calculateOutputDimensions(
          const ImageDimensions(400, 200),
          targetWidth: 1000,
        ),
        const ImageDimensions(400, 200),
      );
    });

    test('allows enlargement when explicitly requested', () {
      expect(
        calculateOutputDimensions(
          const ImageDimensions(400, 200),
          targetWidth: 1000,
          preventUpscale: false,
        ),
        const ImageDimensions(1000, 500),
      );
    });
  });

  test('ConversionSettings combines a preset crop and width resize', () {
    const settings = ConversionSettings(
      aspectRatio: AspectRatio.preset(AspectRatioPreset.ratio16x9),
      resizeEnabled: true,
      resizeValue: 1280,
    );

    expect(
      settings.plan(const ImageDimensions(4000, 3000)),
      const ImageSizePlan(
        source: ImageDimensions(4000, 3000),
        crop: CropRect(left: 0, top: 375, width: 4000, height: 2250),
        output: ImageDimensions(1280, 720),
      ),
    );
  });

  test('ConversionSettings exposes quality and processing options', () {
    const settings = ConversionSettings(
      quality: 92,
      resizeEnabled: true,
      resizeAxis: ResizeAxis.height,
      resizeValue: 720,
      allowUpscale: true,
      stripMetadata: true,
      suffix: '_web',
      overwrite: true,
    );

    expect(settings.quality, 92);
    expect(settings.resizeEnabled, isTrue);
    expect(settings.resizeAxis, ResizeAxis.height);
    expect(settings.resizeValue, 720);
    expect(settings.allowUpscale, isTrue);
    expect(settings.preventUpscale, isFalse);
    expect(settings.stripMetadata, isTrue);
    expect(settings.suffix, '_web');
    expect(settings.overwrite, isTrue);
  });

  test('ConversionSettings allows upscaling by default', () {
    const settings = ConversionSettings(
      resizeEnabled: true,
      resizeValue: 1000,
    );

    expect(
      settings.plan(const ImageDimensions(400, 200)).output,
      const ImageDimensions(1000, 500),
    );
  });
}

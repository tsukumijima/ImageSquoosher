import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_squoosher/utils/lanczos_resizer.dart';

void main() {
  group('LanczosResizer', () {
    test('同じ解像度では線形 RGB の値を変えない', () {
      final source = LanczosLinearRgbImage(
        width: 2,
        height: 2,
        linearRgb: Float32List.fromList(<double>[
          0.0,
          0.25,
          1.0,
          0.5,
          0.75,
          0.125,
          1.0,
          0.0,
          0.5,
          0.25,
          1.0,
          0.75,
        ]),
      );

      final resized = LanczosResizer.resize(source, width: 2, height: 2);

      expect(resized.linearRgb, orderedEquals(source.linearRgb));
      expect(identical(resized.linearRgb, source.linearRgb), isFalse);
    });

    test('一定色の縮小は線形 RGB の明るさを保つ', () {
      final source = LanczosLinearRgbImage(
        width: 4,
        height: 4,
        linearRgb: Float32List.fromList(
          List<double>.filled(4 * 4 * 3, 0.25),
        ),
      );

      final resized = LanczosResizer.resize(source, width: 1, height: 1);

      expect(resized.linearRgb[0], closeTo(0.25, 0.00001));
      expect(resized.linearRgb[1], closeTo(0.25, 0.00001));
      expect(resized.linearRgb[2], closeTo(0.25, 0.00001));
    });

    test('線形 RGB の 0.5 は sRGB の約 188 へ変換する', () {
      final image = LanczosLinearRgbImage(
        width: 1,
        height: 1,
        linearRgb: Float32List.fromList(<double>[0.5, 0.5, 0.5]),
      );

      final bytes = image.toSrgbBytes();

      expect(bytes, orderedEquals(<int>[188, 188, 188]));
    });

    test('別 Isolate でも線形 RGB の値を保つ', () async {
      final source = LanczosLinearRgbImage(
        width: 2,
        height: 2,
        linearRgb: Float32List.fromList(List<double>.filled(2 * 2 * 3, 0.75)),
      );

      final resized = await LanczosResizer.resizeInIsolate(
        source,
        width: 1,
        height: 1,
      );

      expect(resized.linearRgb, everyElement(closeTo(0.75, 0.00001)));
    });
  });
}

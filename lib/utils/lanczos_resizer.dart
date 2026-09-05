import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

/// Lanczos3 でリサイズする線形 RGB 画像。
/// [linearRgb] は左上から右下へ走査した 0.0 から 1.0 の RGB 値で、長さは `width * height * 3` とする。
/// 線形値で畳み込み、縮小後の画像でも光量としての明るさを保つ。
class LanczosLinearRgbImage {
  /// 画像の横幅。
  final int width;

  /// 画像の高さ。
  final int height;

  /// ピクセルごとの線形 RGB 値。
  final Float32List linearRgb;

  /// 線形 RGB 画像を作成する。
  /// @param width 画像の横幅
  /// @param height 画像の高さ
  /// @param linearRgb 左上から右下へ並ぶ線形 RGB 配列
  LanczosLinearRgbImage({
    required this.width,
    required this.height,
    required this.linearRgb,
  }) {
    if (width <= 0 || height <= 0) {
      throw ArgumentError.value(
        '$width x $height',
        'dimensions',
        'Image dimensions must be positive.',
      );
    }
    if (linearRgb.length != width * height * 3) {
      throw ArgumentError.value(
        linearRgb.length,
        'linearRgb.length',
        'Linear RGB data must contain exactly three values per pixel.',
      );
    }
  }

  /// `cjpeg` の PPM 入力へ渡す 8bit sRGB 値へ変換する。
  /// @returns 左上から右下へ並ぶ 8bit sRGB 配列
  Uint8List toSrgbBytes() {
    final srgbBytes = Uint8List(linearRgb.length);
    for (var index = 0; index < linearRgb.length; index += 1) {
      srgbBytes[index] = SrgbColorSpace.toByte(linearRgb[index]);
    }
    return srgbBytes;
  }
}

/// sRGB と線形 RGB を相互変換する色空間変換。
class SrgbColorSpace {
  /// 8bit sRGB の正規化値を線形 RGB へ変換する。
  /// @param srgb 0.0 から 1.0 の sRGB 値
  /// @returns 0.0 から 1.0 の線形 RGB 値
  static double toLinear(double srgb) {
    final normalized = srgb.clamp(0.0, 1.0);
    if (normalized <= 0.04045) {
      return normalized / 12.92;
    }
    return math.pow((normalized + 0.055) / 1.055, 2.4).toDouble();
  }

  /// 線形 RGB の正規化値を sRGB へ変換する。
  /// @param linear 0.0 から 1.0 の線形 RGB 値
  /// @returns 0.0 から 1.0 の sRGB 値
  static double fromLinear(double linear) {
    final normalized = linear.clamp(0.0, 1.0);
    if (normalized <= 0.0031308) {
      return normalized * 12.92;
    }
    return 1.055 * math.pow(normalized, 1.0 / 2.4).toDouble() - 0.055;
  }

  /// 線形 RGB を PPM 用の 8bit sRGB 値へ丸める。
  /// @param linear 0.0 から 1.0 の線形 RGB 値
  /// @returns 0 から 255 の 8bit 値
  static int toByte(double linear) {
    return (fromLinear(linear) * 255.0).round().clamp(0, 255).toInt();
  }
}

/// Piston と Squoosh が用いる、半径 3 の Lanczos 窓関数によるリサイズ処理。
/// 水平と垂直を分けて畳み込み、2次元の計算を2回の1次元計算へ分けて計算量を減らす。
/// 縮小時は窓を広げて低域通過するため、細かい模様の折り返しを抑えながら輪郭を保つ。
class LanczosResizer {
  /// Lanczos3 の窓半径。
  static const double _radius = 3.0;

  /// [source] を指定した解像度へ同期的にリサイズする。
  /// 小さい画像の検証やワーカー [Isolate] 内で利用する。
  /// 画面の操作を継続する呼び出し元は [resizeInIsolate()] を使う。
  /// @param source リサイズ元の線形 RGB 画像
  /// @param width 出力画像の横幅
  /// @param height 出力画像の高さ
  /// @returns 指定解像度の線形 RGB 画像
  static LanczosLinearRgbImage resize(
    LanczosLinearRgbImage source, {
    required int width,
    required int height,
  }) {
    if (width <= 0 || height <= 0) {
      throw ArgumentError.value(
        '$width x $height',
        'dimensions',
        'Target dimensions must be positive.',
      );
    }
    if (source.width == width && source.height == height) {
      // 変換を省略する場合も、呼び出し元が独立したバッファーを受け取れるよう複製する
      return LanczosLinearRgbImage(
        width: width,
        height: height,
        linearRgb: Float32List.fromList(source.linearRgb),
      );
    }

    final horizontalWeights = _createContributions(source.width, width);
    final verticalWeights = _createContributions(source.height, height);
    final intermediate = Float32List(source.height * width * 3);

    // 横方向を先に畳み込むと、縦方向は目的幅だけを読むので大きい画像でも計算量を抑えられる
    for (var sourceY = 0; sourceY < source.height; sourceY += 1) {
      for (var targetX = 0; targetX < width; targetX += 1) {
        final contribution = horizontalWeights[targetX];
        var red = 0.0;
        var green = 0.0;
        var blue = 0.0;
        for (final tap in contribution.taps) {
          final sourceOffset = (sourceY * source.width + tap.index) * 3;
          red += source.linearRgb[sourceOffset] * tap.weight;
          green += source.linearRgb[sourceOffset + 1] * tap.weight;
          blue += source.linearRgb[sourceOffset + 2] * tap.weight;
        }
        final targetOffset = (sourceY * width + targetX) * 3;
        intermediate[targetOffset] = red;
        intermediate[targetOffset + 1] = green;
        intermediate[targetOffset + 2] = blue;
      }
    }

    final output = Float32List(width * height * 3);
    // sRGB への変換は畳み込み後に行い、縮小中の明るさを線形空間で保つ
    for (var targetY = 0; targetY < height; targetY += 1) {
      final contribution = verticalWeights[targetY];
      for (var targetX = 0; targetX < width; targetX += 1) {
        var red = 0.0;
        var green = 0.0;
        var blue = 0.0;
        for (final tap in contribution.taps) {
          final sourceOffset = (tap.index * width + targetX) * 3;
          red += intermediate[sourceOffset] * tap.weight;
          green += intermediate[sourceOffset + 1] * tap.weight;
          blue += intermediate[sourceOffset + 2] * tap.weight;
        }
        final targetOffset = (targetY * width + targetX) * 3;
        output[targetOffset] = red.clamp(0.0, 1.0);
        output[targetOffset + 1] = green.clamp(0.0, 1.0);
        output[targetOffset + 2] = blue.clamp(0.0, 1.0);
      }
    }

    return LanczosLinearRgbImage(width: width, height: height, linearRgb: output);
  }

  /// [source] を別 [Isolate] でリサイズする。
  /// フィルター計算を Flutter の描画 [Isolate] から切り離し、転送可能な数値とバイト列で結果を返す。
  /// @param source リサイズ元の線形 RGB 画像
  /// @param width 出力画像の横幅
  /// @param height 出力画像の高さ
  /// @returns 指定解像度の線形 RGB 画像を返す Future
  static Future<LanczosLinearRgbImage> resizeInIsolate(
    LanczosLinearRgbImage source, {
    required int width,
    required int height,
  }) {
    return Isolate.run<LanczosLinearRgbImage>(
      () => resize(source, width: width, height: height),
    );
  }

  /// 各出力座標へ寄与する入力画素と正規化済みの重みを作成する。
  /// @param sourceLength 入力軸の画素数
  /// @param targetLength 出力軸の画素数
  /// @returns 出力座標ごとの寄与情報
  static List<_Contributions> _createContributions(
    int sourceLength,
    int targetLength,
  ) {
    final scale = targetLength / sourceLength;
    final filterScale = math.max(1.0, 1.0 / scale);
    final support = _radius * filterScale;

    return List<_Contributions>.generate(targetLength, (targetIndex) {
      final center = (targetIndex + 0.5) / scale - 0.5;
      final first = (center - support).ceil();
      final last = (center + support).floor();
      final rawTaps = <_Tap>[];
      var totalWeight = 0.0;

      for (var sourceIndex = first; sourceIndex <= last; sourceIndex += 1) {
        final distance = center - sourceIndex;
        final weight = _lanczos(distance / filterScale) / filterScale;
        if (weight == 0.0) {
          continue;
        }
        // 端で画素を複製して畳み込み、切り落としたときも端の明るさを保つ
        final clampedIndex = sourceIndex.clamp(0, sourceLength - 1).toInt();
        rawTaps.add(_Tap(index: clampedIndex, weight: weight));
        totalWeight += weight;
      }

      if (totalWeight == 0.0) {
        return _Contributions(
          <_Tap>[
            _Tap(
              index: center.round().clamp(0, sourceLength - 1).toInt(),
              weight: 1.0,
            ),
          ],
        );
      }
      return _Contributions(
        rawTaps
            .map(
              (tap) => _Tap(
                index: tap.index,
                weight: tap.weight / totalWeight,
              ),
            )
            .toList(growable: false),
      );
    }, growable: false);
  }

  /// Lanczos3 の標本値を返す。
  /// @param distance 標本中心からの距離
  /// @returns 指定位置の Lanczos 係数
  static double _lanczos(double distance) {
    final absoluteDistance = distance.abs();
    if (absoluteDistance < 0.0000001) {
      return 1.0;
    }
    if (absoluteDistance >= _radius) {
      return 0.0;
    }
    final piDistance = math.pi * distance;
    return (math.sin(piDistance) / piDistance) * (math.sin(piDistance / _radius) / (piDistance / _radius));
  }
}

/// 1出力画素へ寄与する入力画素群。
class _Contributions {
  /// 係数を作成する。
  /// @param taps 入力画素と重みの組
  const _Contributions(this.taps);

  /// 入力画素と正規化済みの重み。
  final List<_Tap> taps;
}

/// 畳み込み係数の1要素。
class _Tap {
  /// 係数を作成する。
  /// @param index 入力画素の位置
  /// @param weight 出力画素への寄与率
  const _Tap({required this.index, required this.weight});

  /// 入力画素の位置。
  final int index;

  /// 出力画素への寄与率。
  final double weight;
}

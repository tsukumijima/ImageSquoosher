import 'aspect_ratio.dart';
import 'image_dimensions.dart';

/// リサイズの基準にする辺。
enum ResizeAxis { width, height }

/// 画像変換画面で指定する設定値。
class ConversionSettings {
  const ConversionSettings({
    this.aspectRatio = const AspectRatio.preset(AspectRatioPreset.original),
    this.quality = 90,
    this.resizeEnabled = false,
    this.resizeAxis = ResizeAxis.width,
    this.resizeValue = 1920,
    this.allowUpscale = true,
    this.stripMetadata = false,
    this.suffix = '_resized',
    this.overwrite = false,
  }) : assert(quality >= 1 && quality <= 100),
       assert(resizeValue > 0);

  final AspectRatio aspectRatio;
  final int quality;
  final bool resizeEnabled;
  final ResizeAxis resizeAxis;
  final int resizeValue;
  final bool allowUpscale;
  final bool stripMetadata;
  final String suffix;
  final bool overwrite;
  bool get preventUpscale => !allowUpscale;

  /// 元画像に適用する中央クロップと出力寸法を計算する。
  ImageSizePlan plan(ImageDimensions source) {
    final requestedRatio = aspectRatio.resolve(source);
    final crop = calculateCenterCrop(source, requestedRatio);
    final output = resizeEnabled
        ? calculateOutputDimensions(
            crop.dimensions,
            targetWidth: resizeAxis == ResizeAxis.width ? resizeValue : null,
            targetHeight: resizeAxis == ResizeAxis.height ? resizeValue : null,
            preventUpscale: preventUpscale,
          )
        : crop.dimensions;
    return ImageSizePlan(source: source, crop: crop, output: output);
  }
}

/// 指定縦横比に収まる中央クロップ領域を計算する。
CropRect calculateCenterCrop(ImageDimensions source, double targetAspectRatio) {
  if (targetAspectRatio <= 0) {
    throw ArgumentError.value(targetAspectRatio, 'targetAspectRatio');
  }

  final sourceAspectRatio = source.aspectRatio;
  if ((sourceAspectRatio - targetAspectRatio).abs() < 0.0000001) {
    return CropRect(
      left: 0,
      top: 0,
      width: source.width,
      height: source.height,
    );
  }

  if (sourceAspectRatio > targetAspectRatio) {
    final cropWidth = (source.height * targetAspectRatio).floor().clamp(
      1,
      source.width,
    );
    return CropRect(
      left: (source.width - cropWidth) ~/ 2,
      top: 0,
      width: cropWidth,
      height: source.height,
    );
  }

  final cropHeight = (source.width / targetAspectRatio).floor().clamp(
    1,
    source.height,
  );
  return CropRect(
    left: 0,
    top: (source.height - cropHeight) ~/ 2,
    width: source.width,
    height: cropHeight,
  );
}

/// 幅または高さを基準に比率を保った出力寸法を計算する。
ImageDimensions calculateOutputDimensions(
  ImageDimensions source, {
  int? targetWidth,
  int? targetHeight,
  bool preventUpscale = true,
}) {
  if (targetWidth == null && targetHeight == null) {
    return source;
  }
  if (targetWidth != null && targetWidth <= 0) {
    throw ArgumentError.value(targetWidth, 'targetWidth');
  }
  if (targetHeight != null && targetHeight <= 0) {
    throw ArgumentError.value(targetHeight, 'targetHeight');
  }

  int outputWidth;
  int outputHeight;
  if (targetWidth != null && targetHeight != null) {
    outputWidth = targetWidth;
    outputHeight = targetHeight;
  } else {
    // 片方だけを指定した場合は同じ拡大縮小率を両辺へ適用し、縦横比を保つ
    final requestedScale = targetWidth == null ? targetHeight! / source.height : targetWidth / source.width;
    final scale = preventUpscale && requestedScale > 1 ? 1.0 : requestedScale;
    outputWidth = (source.width * scale).round();
    outputHeight = (source.height * scale).round();
  }

  if (preventUpscale) {
    outputWidth = outputWidth.clamp(1, source.width);
    outputHeight = outputHeight.clamp(1, source.height);
  } else {
    outputWidth = outputWidth.clamp(1, double.maxFinite.toInt());
    outputHeight = outputHeight.clamp(1, double.maxFinite.toInt());
  }
  return ImageDimensions(outputWidth, outputHeight);
}

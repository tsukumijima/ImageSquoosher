import 'aspect_ratio.dart';
import 'image_dimensions.dart';

/// リサイズの基準にする辺。
enum ResizeAxis { width, height }

/// 画像変換画面で指定する設定値。
class ConversionSettings {
  /// 指定した変換条件を作成する。
  /// @param aspectRatio クロップに使う縦横比
  /// @param quality JPEG の品質値
  /// @param resizeEnabled リサイズを行うかどうか
  /// @param resizeAxis 基準にする辺
  /// @param resizeValue 基準にする辺の長さ
  /// @param allowUpscale 元画像より拡大するかどうか
  /// @param stripMetadata メタデータを除去するかどうか
  /// @param suffix 出力ファイル名へ付けるサフィックス
  /// @param overwrite JPEG の入力元を上書きするかどうか
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

  /// クロップに使う縦横比。
  final AspectRatio aspectRatio;

  /// JPEG の品質値。
  final int quality;

  /// リサイズを行うかどうか。
  final bool resizeEnabled;

  /// リサイズの基準にする辺。
  final ResizeAxis resizeAxis;

  /// 基準にする辺の長さ。
  final int resizeValue;

  /// 元画像より拡大するかどうか。
  final bool allowUpscale;

  /// メタデータを除去するかどうか。
  final bool stripMetadata;

  /// 出力ファイル名へ付けるサフィックス。
  final String suffix;

  /// JPEG の入力元を上書きするかどうか。
  final bool overwrite;

  /// 拡大を禁止する設定かどうかを返す。
  /// @returns 拡大を禁止する場合は `true`
  bool get preventUpscale => !allowUpscale;

  /// 元画像に適用する中央クロップと出力寸法を計算する。
  /// @param source 入力画像の寸法
  /// @returns クロップ領域と出力寸法を含む計画
  ImageSizePlan plan(ImageDimensions source) {
    final requestedRatio = aspectRatio.resolve(source);
    final crop = calculateCenterCrop(source, requestedRatio);
    final output = resizeEnabled
        ? calculateOutputDimensions(
            crop.dimensions,
            targetWidth: resizeAxis == ResizeAxis.width ? resizeValue : null,
            targetHeight: resizeAxis == ResizeAxis.height ? resizeValue : null,
            targetAspectRatio: aspectRatio.preset == AspectRatioPreset.original ? null : requestedRatio,
            preventUpscale: preventUpscale,
          )
        : crop.dimensions;
    return ImageSizePlan(source: source, crop: crop, output: output);
  }
}

/// 指定縦横比に収まる中央クロップ領域を計算する。
/// @param source 入力画像の寸法
/// @param targetAspectRatio 収める縦横比
/// @returns 入力画像の中央に配置したクロップ領域
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
/// [targetAspectRatio] を指定すると、クロップの整数丸め前の比率を出力へ適用する。
/// @param source リサイズ対象の寸法
/// @param targetWidth 出力幅。高さだけを指定する場合は `null`
/// @param targetHeight 出力高さ。幅だけを指定する場合は `null`
/// @param targetAspectRatio 出力へ適用する縦横比
/// @param preventUpscale 元画像を超える拡大を禁止するかどうか
/// @returns 計算した出力寸法
ImageDimensions calculateOutputDimensions(
  ImageDimensions source, {
  int? targetWidth,
  int? targetHeight,
  double? targetAspectRatio,
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
    // 指定した辺の倍率を求め、拡大禁止の上限を判定する
    final requestedScale = targetWidth == null ? targetHeight! / source.height : targetWidth / source.width;
    // 拡大禁止の上限では、画素単位に切り抜いた元の寸法を維持する
    if (preventUpscale && requestedScale >= 1) {
      return source;
    }
    // 元画像比率では倍率を先に求める計算順序を維持し、半画素の丸めも同じ結果にする
    if (targetAspectRatio == null) {
      outputWidth = (source.width * requestedScale).round();
      outputHeight = (source.height * requestedScale).round();
    } else {
      // クロップの整数丸めによる誤差を出力へ持ち越さず、指定比率から反対側の辺を求める
      outputWidth = targetWidth ?? (targetHeight! * targetAspectRatio).round();
      outputHeight = targetHeight ?? (targetWidth! / targetAspectRatio).round();
    }
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

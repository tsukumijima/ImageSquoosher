/// 画像の横幅と高さを表す整数寸法。
class ImageDimensions {
  const ImageDimensions(this.width, this.height) : assert(width > 0), assert(height > 0);

  final int width;
  final int height;

  double get aspectRatio => width / height;

  @override
  bool operator ==(Object other) {
    return other is ImageDimensions && other.width == width && other.height == height;
  }

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => '$width×$height';
}

/// 元画像から切り出す中央領域を表す矩形。
class CropRect {
  const CropRect({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  }) : assert(left >= 0),
       assert(top >= 0),
       assert(width > 0),
       assert(height > 0);

  final int left;
  final int top;
  final int width;
  final int height;

  ImageDimensions get dimensions => ImageDimensions(width, height);

  @override
  bool operator ==(Object other) {
    return other is CropRect &&
        other.left == left &&
        other.top == top &&
        other.width == width &&
        other.height == height;
  }

  @override
  int get hashCode => Object.hash(left, top, width, height);

  @override
  String toString() => 'CropRect(left: $left, top: $top, width: $width, height: $height)';
}

/// 元画像を切り出してからリサイズした結果の寸法計画。
class ImageSizePlan {
  const ImageSizePlan({
    required this.source,
    required this.crop,
    required this.output,
  });

  final ImageDimensions source;
  final CropRect crop;
  final ImageDimensions output;

  @override
  bool operator ==(Object other) {
    return other is ImageSizePlan && other.source == source && other.crop == crop && other.output == output;
  }

  @override
  int get hashCode => Object.hash(source, crop, output);
}

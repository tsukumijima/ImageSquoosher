/// 画像の横幅と高さを表す整数寸法。
class ImageDimensions {
  /// 幅と高さから画像寸法を作成する。
  /// @param width 画像の幅
  /// @param height 画像の高さ
  const ImageDimensions(this.width, this.height) : assert(width > 0), assert(height > 0);

  /// 画像の幅。
  final int width;

  /// 画像の高さ。
  final int height;

  /// 幅を高さで割った縦横比を返す。
  /// @returns 画像の縦横比
  double get aspectRatio => width / height;

  /// 寸法が一致するかを判定する。
  /// @param other 比較対象
  /// @returns 幅と高さが一致する場合は `true`
  @override
  bool operator ==(Object other) {
    return other is ImageDimensions && other.width == width && other.height == height;
  }

  @override
  int get hashCode => Object.hash(width, height);

  /// 寸法を幅と高さの表記へ変換する。
  /// @returns `幅×高さ` 形式の文字列
  @override
  String toString() => '$width×$height';
}

/// 元画像から切り出す中央領域を表す矩形。
class CropRect {
  /// クロップ領域を作成する。
  /// @param left 左端の座標
  /// @param top 上端の座標
  /// @param width クロップ幅
  /// @param height クロップ高さ
  const CropRect({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  }) : assert(left >= 0),
       assert(top >= 0),
       assert(width > 0),
       assert(height > 0);

  /// クロップ領域の左端座標。
  final int left;

  /// クロップ領域の上端座標。
  final int top;

  /// クロップ領域の幅。
  final int width;

  /// クロップ領域の高さ。
  final int height;

  /// クロップ領域の寸法を返す。
  /// @returns クロップ幅と高さの寸法
  ImageDimensions get dimensions => ImageDimensions(width, height);

  /// クロップ領域が一致するかを判定する。
  /// @param other 比較対象
  /// @returns 座標と寸法が一致する場合は `true`
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

  /// クロップ領域をデバッグ用の文字列へ変換する。
  /// @returns 座標と寸法を含む文字列
  @override
  String toString() => 'CropRect(left: $left, top: $top, width: $width, height: $height)';
}

/// 元画像を切り出してからリサイズした結果の寸法計画。
class ImageSizePlan {
  /// 入力画像、クロップ領域、出力寸法から計画を作成する。
  /// @param source 入力画像の寸法
  /// @param crop 適用するクロップ領域
  /// @param output 変換後の寸法
  const ImageSizePlan({
    required this.source,
    required this.crop,
    required this.output,
  });

  /// 入力画像の寸法。
  final ImageDimensions source;

  /// 適用するクロップ領域。
  final CropRect crop;

  /// 変換後の寸法。
  final ImageDimensions output;

  /// 寸法計画が一致するかを判定する。
  /// @param other 比較対象
  /// @returns 入力、クロップ、出力が一致する場合は `true`
  @override
  bool operator ==(Object other) {
    return other is ImageSizePlan && other.source == source && other.crop == crop && other.output == output;
  }

  @override
  int get hashCode => Object.hash(source, crop, output);
}

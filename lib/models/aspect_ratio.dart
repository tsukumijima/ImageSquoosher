import 'image_dimensions.dart';

/// 画面で選択できる代表的な縦横比。
enum AspectRatioPreset {
  original,
  ratio9x16,
  ratio2x3,
  ratio3x4,
  ratio4x5,
  square,
  ratio5x4,
  ratio4x3,
  ratio3x2,
  ratio16x9,
  ogp,
}

extension AspectRatioPresetInfo on AspectRatioPreset {
  /// 表示用の縦横比ラベルを返す。
  /// @returns プリセットに対応するラベル。元画像の比率は `Original`
  String get label {
    switch (this) {
      case AspectRatioPreset.original:
        return 'Original';
      case AspectRatioPreset.square:
        return '1:1';
      case AspectRatioPreset.ratio3x2:
        return '3:2';
      case AspectRatioPreset.ratio2x3:
        return '2:3';
      case AspectRatioPreset.ratio4x3:
        return '4:3';
      case AspectRatioPreset.ratio3x4:
        return '3:4';
      case AspectRatioPreset.ratio4x5:
        return '4:5';
      case AspectRatioPreset.ratio5x4:
        return '5:4';
      case AspectRatioPreset.ratio16x9:
        return '16:9';
      case AspectRatioPreset.ratio9x16:
        return '9:16';
      case AspectRatioPreset.ogp:
        return '1.91:1';
    }
  }

  /// プリセットの数値比を返す。
  /// @returns 数値比。元画像の比率は `null`
  double? get value {
    switch (this) {
      case AspectRatioPreset.original:
        return null;
      case AspectRatioPreset.square:
        return 1;
      case AspectRatioPreset.ratio3x2:
        return 3 / 2;
      case AspectRatioPreset.ratio2x3:
        return 2 / 3;
      case AspectRatioPreset.ratio4x3:
        return 4 / 3;
      case AspectRatioPreset.ratio3x4:
        return 3 / 4;
      case AspectRatioPreset.ratio4x5:
        return 4 / 5;
      case AspectRatioPreset.ratio5x4:
        return 5 / 4;
      case AspectRatioPreset.ratio16x9:
        return 16 / 9;
      case AspectRatioPreset.ratio9x16:
        return 9 / 16;
      case AspectRatioPreset.ogp:
        return 1.91;
    }
  }
}

/// プリセットまたは任意の数値で指定する縦横比。
class AspectRatio {
  /// 指定したプリセットを使う縦横比を作成する。
  /// @param preset 使用する縦横比プリセット
  const AspectRatio.preset(this.preset) : customValue = null, horizontal = 1, vertical = 1;

  /// 指定した横と縦の値を使う縦横比を作成する。
  /// @param horizontal 横方向の比率
  /// @param vertical 縦方向の比率
  const AspectRatio.custom({required this.horizontal, required this.vertical})
    : assert(horizontal > 0),
      assert(vertical > 0),
      preset = null,
      customValue = null;

  /// 指定した数値を横方向へ割り当てた縦横比を作成する。
  /// @param value 使用する数値比
  const AspectRatio.customRatio(double value)
    : assert(value > 0),
      preset = null,
      customValue = value,
      horizontal = value,
      vertical = 1;

  /// 使用するプリセット。
  final AspectRatioPreset? preset;

  /// 任意に指定した数値比。
  final double? customValue;

  /// 横方向の比率。
  final double horizontal;

  /// 縦方向の比率。
  final double vertical;

  /// 入力画像に対して縦横比を数値へ解決する。
  /// @param source 入力画像の寸法
  /// @returns 入力画像へ適用する数値比
  double resolve(ImageDimensions source) {
    // 元画像の比率は入力寸法が決まるまで数値化できないため、ここで解決する
    if (preset == AspectRatioPreset.original) {
      return source.aspectRatio;
    }
    return customValue ?? preset?.value ?? horizontal / vertical;
  }

  /// 縦横比を表示用ラベルへ変換する。
  /// @returns プリセットまたは数値で表したラベル
  String get label {
    if (preset != null) {
      return preset!.label;
    }
    if (customValue != null) {
      return _format(customValue!);
    }
    return '${_format(horizontal)}:${_format(vertical)}';
  }

  /// 比率の数値を末尾の不要なゼロを除いた文字列へ変換する。
  /// @param value 変換する数値
  /// @returns 表示用の数値文字列
  static String _format(double value) {
    final formatted = value.toStringAsFixed(4).replaceFirst(RegExp(r'0+$'), '');
    return formatted.endsWith('.') ? formatted.substring(0, formatted.length - 1) : formatted;
  }

  /// 縦横比が一致するかを判定する。
  /// @param other 比較対象
  /// @returns 縦横比の構成値が一致する場合は `true`
  @override
  bool operator ==(Object other) {
    return other is AspectRatio &&
        other.preset == preset &&
        other.customValue == customValue &&
        other.horizontal == horizontal &&
        other.vertical == vertical;
  }

  @override
  int get hashCode => Object.hash(preset, customValue, horizontal, vertical);
}

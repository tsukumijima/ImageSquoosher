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
  const AspectRatio.preset(this.preset) : customValue = null, horizontal = 1, vertical = 1;

  const AspectRatio.custom({required this.horizontal, required this.vertical})
    : assert(horizontal > 0),
      assert(vertical > 0),
      preset = null,
      customValue = null;

  const AspectRatio.customRatio(double value)
    : assert(value > 0),
      preset = null,
      customValue = value,
      horizontal = value,
      vertical = 1;

  final AspectRatioPreset? preset;
  final double? customValue;
  final double horizontal;
  final double vertical;

  double resolve(ImageDimensions source) {
    // 元画像の比率は入力寸法が決まるまで数値化できないため、ここで解決する
    if (preset == AspectRatioPreset.original) {
      return source.aspectRatio;
    }
    return customValue ?? preset?.value ?? horizontal / vertical;
  }

  String get label {
    if (preset != null) {
      return preset!.label;
    }
    if (customValue != null) {
      return _format(customValue!);
    }
    return '${_format(horizontal)}:${_format(vertical)}';
  }

  static String _format(double value) {
    final formatted = value.toStringAsFixed(4).replaceFirst(RegExp(r'0+$'), '');
    return formatted.endsWith('.') ? formatted.substring(0, formatted.length - 1) : formatted;
  }

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

/// 圧縮設定を小さなウィンドウへ常時表示するパネル。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../models/aspect_ratio.dart' as image_settings;
import '../../models/conversion_settings.dart';
import '../../utils/output_name_planner.dart';

/// 画像一覧の表示領域を保ちながら、すべての圧縮設定を直接編集できるパネルです。
class ConversionSettingsPanel extends StatefulWidget {
  const ConversionSettingsPanel({
    super.key,
    required this.settings,
    required this.onChanged,
  });

  final ConversionSettings settings;
  final ValueChanged<ConversionSettings> onChanged;

  @override
  State<ConversionSettingsPanel> createState() => _ConversionSettingsPanelState();
}

class _ConversionSettingsPanelState extends State<ConversionSettingsPanel> {
  late final TextEditingController _ratioWidthController;
  late final TextEditingController _ratioHeightController;
  late final TextEditingController _resizeController;
  late final TextEditingController _suffixController;
  final _ratioWidthFocusNode = FocusNode();
  final _ratioHeightFocusNode = FocusNode();
  final _resizeFocusNode = FocusNode();
  final _suffixFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _ratioWidthController = TextEditingController(text: widget.settings.aspectRatio.horizontal.toString());
    _ratioHeightController = TextEditingController(text: widget.settings.aspectRatio.vertical.toString());
    _resizeController = TextEditingController(text: widget.settings.resizeValue.toString());
    _suffixController = TextEditingController(text: widget.settings.suffix);
    // 編集を終えた数値欄は、変換で使う最後の有効値へ表示を戻す
    _ratioWidthFocusNode.addListener(_synchronizeNumericFields);
    _ratioHeightFocusNode.addListener(_synchronizeNumericFields);
    _resizeFocusNode.addListener(_synchronizeNumericFields);
  }

  /// フォーカスを外した数値欄へ実効設定を反映します。
  void _synchronizeNumericFields() {
    final settings = widget.settings;
    _synchronizeController(
      _ratioWidthController,
      _ratioWidthFocusNode,
      settings.aspectRatio.horizontal.toString(),
      settings.aspectRatio.horizontal.toString(),
    );
    _synchronizeController(
      _ratioHeightController,
      _ratioHeightFocusNode,
      settings.aspectRatio.vertical.toString(),
      settings.aspectRatio.vertical.toString(),
    );
    _synchronizeController(
      _resizeController,
      _resizeFocusNode,
      settings.resizeValue.toString(),
      settings.resizeValue.toString(),
    );
  }

  @override
  void didUpdateWidget(covariant ConversionSettingsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 入力中は入力欄側にも同じ値があるため、外部から既定値を戻した場合だけ表示値を置き換える
    _synchronizeController(
      _ratioWidthController,
      _ratioWidthFocusNode,
      oldWidget.settings.aspectRatio.horizontal.toString(),
      widget.settings.aspectRatio.horizontal.toString(),
      areEquivalent: _haveEqualDoubleValue,
    );
    _synchronizeController(
      _ratioHeightController,
      _ratioHeightFocusNode,
      oldWidget.settings.aspectRatio.vertical.toString(),
      widget.settings.aspectRatio.vertical.toString(),
      areEquivalent: _haveEqualDoubleValue,
    );
    _synchronizeController(
      _resizeController,
      _resizeFocusNode,
      oldWidget.settings.resizeValue.toString(),
      widget.settings.resizeValue.toString(),
      areEquivalent: _haveEqualIntValue,
    );
    _synchronizeController(
      _suffixController,
      _suffixFocusNode,
      oldWidget.settings.suffix,
      widget.settings.suffix,
    );
  }

  @override
  void dispose() {
    _ratioWidthController.dispose();
    _ratioHeightController.dispose();
    _resizeController.dispose();
    _suffixController.dispose();
    _ratioWidthFocusNode.dispose();
    _ratioHeightFocusNode.dispose();
    _resizeFocusNode.dispose();
    _suffixFocusNode.dispose();
    super.dispose();
  }

  /// フォーカス中の中間入力を保ち、外部の設定変更だけを表示値へ反映します。
  void _synchronizeController(
    TextEditingController controller,
    FocusNode focusNode,
    String previousSavedValue,
    String savedValue, {
    bool Function(String currentValue, String savedValue)? areEquivalent,
  }) {
    final settingsAreUnchanged = previousSavedValue == savedValue;
    final hasEquivalentValue = areEquivalent != null && areEquivalent(controller.text, savedValue);
    final keepsFocusedInput = focusNode.hasFocus && (settingsAreUnchanged || hasEquivalentValue);
    if (controller.text == savedValue || keepsFocusedInput) {
      return;
    }
    controller.value = TextEditingValue(
      text: savedValue,
      selection: TextSelection.collapsed(offset: savedValue.length),
    );
  }

  /// 表記が異なっても同じ小数値を表す入力かを判定します。
  bool _haveEqualDoubleValue(String currentValue, String savedValue) {
    return double.tryParse(currentValue) == double.tryParse(savedValue);
  }

  /// 表記が異なっても同じ整数値を表す入力かを判定します。
  bool _haveEqualIntValue(String currentValue, String savedValue) {
    return int.tryParse(currentValue) == int.tryParse(savedValue);
  }

  /// 変更された項目以外を保った圧縮設定を親画面へ返します。
  void _updateSettings({
    image_settings.AspectRatio? aspectRatio,
    int? quality,
    bool? resizeEnabled,
    ResizeAxis? resizeAxis,
    int? resizeValue,
    bool? allowUpscale,
    bool? stripMetadata,
    String? suffix,
    bool? overwrite,
  }) {
    final current = widget.settings;
    widget.onChanged(
      ConversionSettings(
        aspectRatio: aspectRatio ?? current.aspectRatio,
        quality: quality ?? current.quality,
        resizeEnabled: resizeEnabled ?? current.resizeEnabled,
        resizeAxis: resizeAxis ?? current.resizeAxis,
        resizeValue: resizeValue ?? current.resizeValue,
        allowUpscale: allowUpscale ?? current.allowUpscale,
        stripMetadata: stripMetadata ?? current.stripMetadata,
        suffix: suffix ?? current.suffix,
        overwrite: overwrite ?? current.overwrite,
      ),
    );
  }

  /// 高さ 34px の入力欄を作り、固定設定領域の中へ各値を収めます。
  InputDecoration _inputDecoration({String? suffixText}) {
    return InputDecoration(
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      suffixText: suffixText,
    );
  }

  /// ラベルとチェックを一体のクリック対象として、1行の設定項目を作ります。
  Widget _buildCheckbox({
    required String label,
    required bool value,
    required ValueChanged<bool?>? onChanged,
    bool isExpanded = true,
  }) {
    // 無効時も配置と保存値を保ち、チェックとラベルを同じ有効状態で表示する
    final isEnabled = onChanged != null;
    final labelStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: isEnabled ? null : Theme.of(context).disabledColor,
    );
    final content = InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onChanged == null ? null : () => onChanged(!value),
      child: SizedBox(
        height: 28,
        child: Row(
          mainAxisSize: isExpanded ? MainAxisSize.max : MainAxisSize.min,
          children: [
            SizedBox(
              width: 24,
              child: Checkbox(value: value, onChanged: onChanged),
            ),
            const SizedBox(width: 4),
            if (isExpanded)
              Expanded(
                child: Text(label, maxLines: 1, softWrap: false, style: labelStyle),
              )
            else
              Text(label, maxLines: 1, softWrap: false, style: labelStyle),
          ],
        ),
      ),
    );
    return Semantics(label: label, checked: value, enabled: isEnabled, button: true, child: content);
  }

  /// 比率のプリセットを選ぶドロップダウンを作ります。
  Widget _buildAspectRatioDropdown(AppLocalizations l10n) {
    final settings = widget.settings;
    return DropdownButtonFormField<String>(
      key: ValueKey(settings.aspectRatio.preset?.name ?? 'custom'),
      initialValue: settings.aspectRatio.preset?.name ?? 'custom',
      isExpanded: true,
      decoration: _inputDecoration(),
      items: [
        ...image_settings.AspectRatioPreset.values.map(
          (preset) => DropdownMenuItem(
            value: preset.name,
            child: Text(
              preset == image_settings.AspectRatioPreset.original ? l10n.originalAspectRatio : preset.label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.fade,
            ),
          ),
        ),
        DropdownMenuItem(value: 'custom', child: Text(l10n.customRatio, maxLines: 1, softWrap: false)),
      ],
      onChanged: (value) {
        if (value == 'custom') {
          _updateSettings(
            aspectRatio: const image_settings.AspectRatio.custom(horizontal: 16, vertical: 9),
          );
          return;
        }
        final preset = image_settings.AspectRatioPreset.values
            .where((candidate) => candidate.name == value)
            .firstOrNull;
        if (preset != null) {
          _updateSettings(aspectRatio: image_settings.AspectRatio.preset(preset));
        }
      },
    );
  }

  /// カスタム比率の横と縦を同じ行で編集します。
  Widget _buildCustomRatioFields() {
    final settings = widget.settings;
    return Row(
      children: [
        Expanded(
          child: TextField(
            key: const ValueKey('ratio-width-field'),
            controller: _ratioWidthController,
            focusNode: _ratioWidthFocusNode,
            keyboardType: TextInputType.number,
            decoration: _inputDecoration(),
            onChanged: (value) {
              final horizontal = double.tryParse(value);
              if (horizontal != null && horizontal > 0) {
                _updateSettings(
                  aspectRatio: image_settings.AspectRatio.custom(
                    horizontal: horizontal,
                    vertical: settings.aspectRatio.vertical,
                  ),
                );
              }
            },
          ),
        ),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 5), child: Text(':')),
        Expanded(
          child: TextField(
            key: const ValueKey('ratio-height-field'),
            controller: _ratioHeightController,
            focusNode: _ratioHeightFocusNode,
            keyboardType: TextInputType.number,
            decoration: _inputDecoration(),
            onChanged: (value) {
              final vertical = double.tryParse(value);
              if (vertical != null && vertical > 0) {
                _updateSettings(
                  aspectRatio: image_settings.AspectRatio.custom(
                    horizontal: settings.aspectRatio.horizontal,
                    vertical: vertical,
                  ),
                );
              }
            },
          ),
        ),
      ],
    );
  }

  /// 比率選択とカスタム値を固定高の1行へ収めます。
  Widget _buildAspectRatioField(AppLocalizations l10n) {
    final isCustom = widget.settings.aspectRatio.preset == null;
    return SizedBox(
      height: 34,
      child: Row(
        children: [
          SizedBox(
            width: 116,
            child: Text(
              l10n.aspectRatio,
              maxLines: 1,
              softWrap: false,
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
          if (isCustom) ...[
            SizedBox(width: 150, child: _buildAspectRatioDropdown(l10n)),
            const SizedBox(width: 8),
            Expanded(child: _buildCustomRatioFields()),
          ] else
            Expanded(child: _buildAspectRatioDropdown(l10n)),
        ],
      ),
    );
  }

  /// リサイズの有効状態、基準辺、画素数を1行で編集できるようにします。
  Widget _buildResizeField(AppLocalizations l10n) {
    final settings = widget.settings;
    return SizedBox(
      height: 34,
      child: Row(
        children: [
          SizedBox(
            width: 116,
            child: _buildCheckbox(
              label: l10n.resize,
              value: settings.resizeEnabled,
              onChanged: (value) => _updateSettings(resizeEnabled: value),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 112,
            child: DropdownButtonFormField<ResizeAxis>(
              key: ValueKey(settings.resizeAxis),
              initialValue: settings.resizeAxis,
              isExpanded: true,
              decoration: _inputDecoration(),
              items: [
                DropdownMenuItem(value: ResizeAxis.width, child: Text(l10n.horizontal, maxLines: 1)),
                DropdownMenuItem(value: ResizeAxis.height, child: Text(l10n.vertical, maxLines: 1)),
              ],
              onChanged: settings.resizeEnabled
                  ? (value) {
                      if (value != null) {
                        _updateSettings(resizeAxis: value);
                      }
                    }
                  : null,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              key: const ValueKey('resize-value-field'),
              controller: _resizeController,
              focusNode: _resizeFocusNode,
              enabled: settings.resizeEnabled,
              keyboardType: TextInputType.number,
              decoration: _inputDecoration(),
              onChanged: (value) {
                final resizeValue = int.tryParse(value);
                if (resizeValue != null && resizeValue > 0) {
                  _updateSettings(resizeValue: resizeValue);
                }
              },
            ),
          ),
          const SizedBox(width: 6),
          Text('px', maxLines: 1, style: Theme.of(context).textTheme.labelMedium),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settings = widget.settings;
    return Card(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 6),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 各設定のラベル位置をそろえ、上から下へ1方向に確認できる並びにする
            SizedBox(
              height: 32,
              child: Row(
                children: [
                  SizedBox(
                    width: 116,
                    child: Text(
                      l10n.quality,
                      maxLines: 1,
                      softWrap: false,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                  Expanded(
                    child: Slider(
                      value: settings.quality.toDouble(),
                      min: 1,
                      max: 100,
                      divisions: 99,
                      onChanged: (value) => _updateSettings(quality: value.round()),
                    ),
                  ),
                  Container(
                    width: 36,
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text(
                      '${settings.quality}',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            _buildAspectRatioField(l10n),
            const SizedBox(height: 4),
            _buildResizeField(l10n),
            const SizedBox(height: 2),
            Row(
              children: [
                Expanded(
                  child: _buildCheckbox(
                    label: l10n.allowUpscale,
                    value: settings.allowUpscale,
                    onChanged: settings.resizeEnabled ? (value) => _updateSettings(allowUpscale: value) : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildCheckbox(
                    label: l10n.overwrite,
                    value: settings.overwrite,
                    onChanged: (value) => _updateSettings(overwrite: value),
                  ),
                ),
              ],
            ),
            _buildCheckbox(
              label: l10n.exifRemoval,
              value: settings.stripMetadata,
              onChanged: (value) => _updateSettings(stripMetadata: value),
            ),
            const SizedBox(height: 2),
            SizedBox(
              height: 34,
              child: Row(
                children: [
                  SizedBox(
                    width: 116,
                    child: Text(
                      l10n.suffix,
                      maxLines: 1,
                      softWrap: false,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      key: const ValueKey('suffix-field'),
                      controller: _suffixController,
                      focusNode: _suffixFocusNode,
                      inputFormatters: [
                        TextInputFormatter.withFunction(
                          (oldValue, newValue) => OutputNamePlanner.isValidSuffix(newValue.text) ? newValue : oldValue,
                        ),
                      ],
                      decoration: _inputDecoration(),
                      onChanged: (value) => _updateSettings(suffix: value),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

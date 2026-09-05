/// 圧縮設定を小さなウィンドウへ常時表示するパネル。
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../models/aspect_ratio.dart' as image_settings;
import '../../models/conversion_settings.dart';
import '../../utils/output_name_planner.dart';
import 'cupertino_select.dart';

/// 画像一覧の表示領域を保ちながら、すべての圧縮設定を直接編集できるパネル。
class ConversionSettingsPanel extends StatefulWidget {
  /// 現在の変換設定と変更通知先を受け取って設定パネルを構成する。
  /// @param key ウィジェットを識別するキー
  /// @param settings 現在の変換設定
  /// @param onChanged 設定変更時の通知先
  const ConversionSettingsPanel({
    super.key,
    required this.settings,
    required this.onChanged,
  });

  final ConversionSettings settings;
  final ValueChanged<ConversionSettings> onChanged;

  /// StatefulWidget の状態を生成する。
  /// @returns 圧縮設定パネルの状態
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
    _ratioWidthController = TextEditingController(text: _formatRatioValue(widget.settings.aspectRatio.horizontal));
    _ratioHeightController = TextEditingController(text: _formatRatioValue(widget.settings.aspectRatio.vertical));
    _resizeController = TextEditingController(text: widget.settings.resizeValue.toString());
    _suffixController = TextEditingController(text: widget.settings.suffix);
    // 編集を終えた数値欄は、変換で使う最後の有効値へ表示を戻す
    _ratioWidthFocusNode.addListener(_synchronizeNumericFields);
    _ratioHeightFocusNode.addListener(_synchronizeNumericFields);
    _resizeFocusNode.addListener(_synchronizeNumericFields);
  }

  /// フォーカスを外した数値欄へ実効設定を反映する。
  void _synchronizeNumericFields() {
    final settings = widget.settings;
    _synchronizeController(
      _ratioWidthController,
      _ratioWidthFocusNode,
      _formatRatioValue(settings.aspectRatio.horizontal),
      _formatRatioValue(settings.aspectRatio.horizontal),
    );
    _synchronizeController(
      _ratioHeightController,
      _ratioHeightFocusNode,
      _formatRatioValue(settings.aspectRatio.vertical),
      _formatRatioValue(settings.aspectRatio.vertical),
    );
    _synchronizeController(
      _resizeController,
      _resizeFocusNode,
      settings.resizeValue.toString(),
      settings.resizeValue.toString(),
    );
  }

  /// 新しい設定を受け取り、入力欄の表示を同期する。
  /// @param oldWidget 更新前の設定パネル
  @override
  void didUpdateWidget(covariant ConversionSettingsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 入力中は入力欄側にも同じ値があるため、外部から既定値を戻した場合だけ表示値を置き換える
    _synchronizeController(
      _ratioWidthController,
      _ratioWidthFocusNode,
      _formatRatioValue(oldWidget.settings.aspectRatio.horizontal),
      _formatRatioValue(widget.settings.aspectRatio.horizontal),
      areEquivalent: _haveEqualDoubleValue,
    );
    _synchronizeController(
      _ratioHeightController,
      _ratioHeightFocusNode,
      _formatRatioValue(oldWidget.settings.aspectRatio.vertical),
      _formatRatioValue(widget.settings.aspectRatio.vertical),
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

  /// フォーカス中の中間入力を保ち、外部の設定変更だけを表示値へ反映する。
  /// @param controller 表示値を保持する入力コントローラー
  /// @param focusNode 入力欄のフォーカス状態を管理するノード
  /// @param previousSavedValue 前回保存された値
  /// @param savedValue 現在保存されている値
  /// @param areEquivalent 表記差を同値として扱う比較関数
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

  /// 整数の比率を小数点なしで表示し、小数の比率はそのまま表示する。
  /// @param value 表示する比率
  /// @returns 入力欄へ表示する比率文字列
  String _formatRatioValue(double value) {
    // 整数型の上限を超える値も保ち、小数点以下がゼロの表記だけを短くする
    return value.toString().replaceFirst(RegExp(r'\.0$'), '');
  }

  /// 表記が異なっても同じ小数値を表す入力かを判定する。
  /// @param currentValue 入力欄の現在値
  /// @param savedValue 保存済みの値
  /// @returns 2つの値が同じ数値を表す場合は true
  bool _haveEqualDoubleValue(String currentValue, String savedValue) {
    return double.tryParse(currentValue) == double.tryParse(savedValue);
  }

  /// 表記が異なっても同じ整数値を表す入力かを判定する。
  /// @param currentValue 入力欄の現在値
  /// @param savedValue 保存済みの値
  /// @returns 2つの値が同じ整数を表す場合は true
  bool _haveEqualIntValue(String currentValue, String savedValue) {
    return int.tryParse(currentValue) == int.tryParse(savedValue);
  }

  /// 変更された項目以外を保った圧縮設定を親画面へ返す。
  /// @param aspectRatio 更新する画像比率
  /// @param quality 更新する JPEG 品質
  /// @param resizeEnabled リサイズを有効にするか
  /// @param resizeAxis 基準にする辺
  /// @param resizeValue 基準辺の画素数
  /// @param allowUpscale 拡大を許可するか
  /// @param stripMetadata メタデータを除去するか
  /// @param suffix 出力名へ付ける接尾辞
  /// @param overwrite JPEG 入力を上書きするか
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

  /// 入力欄の背景と枠をドロップダウンと同じ階調へそろえる。
  /// @param isEnabled 入力欄を有効状態として装飾するか
  /// @returns 入力欄の背景装飾
  BoxDecoration _textFieldDecoration({bool isEnabled = true}) {
    return BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      border: Border.all(color: isEnabled ? Colors.white24 : Colors.white12),
      borderRadius: BorderRadius.circular(8),
    );
  }

  /// ラベルとチェックを一体のクリック対象として、1行の設定項目を作る。
  /// @param label 設定項目の表示ラベル
  /// @param value 現在のチェック状態
  /// @param onChanged 状態変更時の通知先
  /// @param isExpanded ラベルを残り幅へ広げるか
  /// @returns チェックボックスとラベルのウィジェット
  Widget _buildCheckbox({
    required String label,
    required bool value,
    required ValueChanged<bool?>? onChanged,
    bool isExpanded = true,
  }) {
    // 無効時も配置と保存値を保ち、チェックとラベルを同じ有効状態で表示する
    final isEnabled = onChanged != null;
    final labelStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
      fontSize: 14,
      color: isEnabled ? null : Theme.of(context).disabledColor,
    );
    final content = InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onChanged == null ? null : () => onChanged(!value),
      child: SizedBox(
        height: 26,
        child: Row(
          mainAxisSize: isExpanded ? MainAxisSize.max : MainAxisSize.min,
          children: [
            SizedBox(
              width: 24,
              child: CupertinoCheckbox(value: value, onChanged: onChanged),
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

  /// 比率のプリセットを選ぶドロップダウンを作る。
  /// @param l10n 現在の表示言語のローカライズ情報
  /// @returns 比率選択のウィジェット
  Widget _buildAspectRatioDropdown(AppLocalizations l10n) {
    final settings = widget.settings;
    return CupertinoSelect<String>(
      key: const ValueKey('aspect-ratio-select'),
      value: settings.aspectRatio.preset?.name ?? 'custom',
      items: {
        for (final preset in image_settings.AspectRatioPreset.values)
          preset.name: preset == image_settings.AspectRatioPreset.original ? l10n.originalAspectRatio : preset.label,
        'custom': l10n.customRatio,
      },
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

  /// カスタム比率の横と縦を同じ行で編集する。
  /// @returns 横と縦の入力欄を含むウィジェット
  Widget _buildCustomRatioFields() {
    final settings = widget.settings;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: CupertinoTextField(
            key: const ValueKey('ratio-width-field'),
            controller: _ratioWidthController,
            focusNode: _ratioWidthFocusNode,
            decoration: _textFieldDecoration(),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 14),
            keyboardType: TextInputType.number,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            onChanged: (value) {
              final horizontal = double.tryParse(value);
              // 貼り付けによる Infinity なども検査し、計算可能な正の値だけを設定へ保存する
              if (horizontal != null && horizontal.isFinite && horizontal > 0) {
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
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5),
          child: Center(child: Text(':', style: Theme.of(context).textTheme.bodyMedium)),
        ),
        Expanded(
          child: CupertinoTextField(
            key: const ValueKey('ratio-height-field'),
            controller: _ratioHeightController,
            focusNode: _ratioHeightFocusNode,
            decoration: _textFieldDecoration(),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 14),
            keyboardType: TextInputType.number,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            onChanged: (value) {
              final vertical = double.tryParse(value);
              // 横と同じ条件で検査し、寸法計算に使える比率を保持する
              if (vertical != null && vertical.isFinite && vertical > 0) {
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

  /// 比率選択とカスタム値を固定高の1行へ収める。
  /// @param l10n 現在の表示言語のローカライズ情報
  /// @returns 比率設定のウィジェット
  Widget _buildAspectRatioField(AppLocalizations l10n) {
    final isCustom = widget.settings.aspectRatio.preset == null;
    return SizedBox(
      height: 38,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 180,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                l10n.aspectRatio,
                maxLines: 1,
                softWrap: false,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 14),
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (isCustom) ...[
            Expanded(child: _buildAspectRatioDropdown(l10n)),
            const SizedBox(width: 8),
            Expanded(child: _buildCustomRatioFields()),
          ] else
            Expanded(child: _buildAspectRatioDropdown(l10n)),
        ],
      ),
    );
  }

  /// リサイズの有効状態、基準辺、画素数を1行で編集できるようにする。
  /// @param l10n 現在の表示言語のローカライズ情報
  /// @returns リサイズ設定のウィジェット
  Widget _buildResizeField(AppLocalizations l10n) {
    final settings = widget.settings;
    return SizedBox(
      height: 38,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 180,
            child: _buildCheckbox(
              label: l10n.resize,
              value: settings.resizeEnabled,
              onChanged: (value) => _updateSettings(resizeEnabled: value),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: CupertinoSelect<ResizeAxis>(
              key: const ValueKey('resize-axis-select'),
              value: settings.resizeAxis,
              items: {
                ResizeAxis.width: l10n.resizeByWidth,
                ResizeAxis.height: l10n.resizeByHeight,
              },
              onChanged: settings.resizeEnabled ? (value) => _updateSettings(resizeAxis: value) : null,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: CupertinoTextField(
              key: const ValueKey('resize-value-field'),
              controller: _resizeController,
              focusNode: _resizeFocusNode,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontSize: 14,
                color: settings.resizeEnabled ? null : Theme.of(context).disabledColor,
              ),
              enabled: settings.resizeEnabled,
              decoration: _textFieldDecoration(isEnabled: settings.resizeEnabled),
              keyboardType: TextInputType.number,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              suffix: Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Text(
                  'px',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontSize: 14,
                    color: settings.resizeEnabled ? null : Theme.of(context).disabledColor,
                  ),
                ),
              ),
              onChanged: (value) {
                final resizeValue = int.tryParse(value);
                if (resizeValue != null && resizeValue > 0) {
                  _updateSettings(resizeValue: resizeValue);
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  /// 設定パネルを構築する。
  /// @param context ウィジェットツリーの BuildContext
  /// @returns 圧縮設定パネルのウィジェット
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settings = widget.settings;
    return Card(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 6),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 各設定のラベル位置をそろえ、上から下へ1方向に確認できる並びにする
            SizedBox(
              height: 28,
              child: Row(
                children: [
                  SizedBox(
                    width: 180,
                    child: Text(
                      l10n.quality,
                      maxLines: 1,
                      softWrap: false,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 14),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    // トラックの既定余白を外し、下の入力欄と描画の左端をそろえる
                    child: Slider(
                      key: const ValueKey('quality-slider-focus'),
                      padding: EdgeInsets.zero,
                      value: settings.quality.toDouble(),
                      min: 1,
                      max: 100,
                      divisions: 99,
                      onChanged: (value) => _updateSettings(quality: value.round()),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Container(
                    width: 36,
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text(
                      '${settings.quality}',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 38,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 180,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        l10n.suffix,
                        maxLines: 1,
                        softWrap: false,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontSize: 14,
                          color: settings.overwrite ? Theme.of(context).disabledColor : null,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: CupertinoTextField(
                      key: const ValueKey('suffix-field'),
                      controller: _suffixController,
                      focusNode: _suffixFocusNode,
                      enabled: !settings.overwrite,
                      decoration: _textFieldDecoration(isEnabled: !settings.overwrite),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontSize: 14,
                        color: settings.overwrite ? Theme.of(context).disabledColor : null,
                      ),
                      inputFormatters: [
                        TextInputFormatter.withFunction(
                          (oldValue, newValue) => OutputNamePlanner.isValidSuffix(newValue.text) ? newValue : oldValue,
                        ),
                      ],
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      onChanged: (value) => _updateSettings(suffix: value),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            _buildAspectRatioField(l10n),
            const SizedBox(height: 6),
            _buildResizeField(l10n),
            const SizedBox(height: 8),
            _buildCheckbox(
              label: l10n.allowUpscale,
              value: settings.allowUpscale,
              onChanged: settings.resizeEnabled ? (value) => _updateSettings(allowUpscale: value) : null,
            ),
            _buildCheckbox(
              label: l10n.exifRemoval,
              value: settings.stripMetadata,
              onChanged: (value) => _updateSettings(stripMetadata: value),
            ),
            _buildCheckbox(
              label: l10n.overwrite,
              value: settings.overwrite,
              onChanged: (value) => _updateSettings(overwrite: value),
            ),
          ],
        ),
      ),
    );
  }
}

import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Theme;
import 'package:flutter/services.dart';

/// デスクトップ向けの小さなポップアップで値を選ぶ Cupertino コントロール。
class CupertinoSelect<T extends Object> extends StatefulWidget {
  /// 選択値、候補一覧、変更通知を受け取って選択コントロールを構成する。
  /// @param key ウィジェットを識別するキー
  /// @param value 現在選択されている値
  /// @param items 値と表示ラベルの対応表
  /// @param onChanged 選択変更時の通知先。null の場合は無効化する
  /// @param key ウィジェットを識別するキー
  const CupertinoSelect({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final T value;
  final Map<T, String> items;
  final ValueChanged<T>? onChanged;

  /// StatefulWidget の状態を生成する。
  /// @returns Cupertino 選択コントロールの状態
  @override
  State<CupertinoSelect<T>> createState() => _CupertinoSelectState<T>();
}

class _CupertinoSelectState<T extends Object> extends State<CupertinoSelect<T>> {
  final _controller = MenuController();
  final _focusNode = FocusNode();
  // デスクトップでも一覧とスクロールバーが同じスクロール位置を使う
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// 選択コントロールを構築する。
  /// @param context ウィジェットツリーの BuildContext
  /// @returns 選択コントロールのウィジェット
  @override
  Widget build(BuildContext context) {
    final isEnabled = widget.onChanged != null;
    // 選択値も入力欄と同じ本文フォントで表示する
    final textStyle = Theme.of(context).textTheme.bodyMedium!.copyWith(
      color: CupertinoDynamicColor.resolve(isEnabled ? CupertinoColors.label : CupertinoColors.tertiaryLabel, context),
    );
    return RawMenuAnchor(
      controller: _controller,
      childFocusNode: _focusNode,
      consumeOutsideTaps: true,
      overlayBuilder: (context, info) {
        // 狭いウィンドウでも一覧を画面内に収め、長い候補はスクロールして選べるようにする
        final width = math.min(math.max(info.anchorRect.width, 180.0), info.overlaySize.width - 16);
        final spaceBelow = info.overlaySize.height - info.anchorRect.bottom - 12;
        final spaceAbove = info.anchorRect.top - 12;
        final opensAbove = spaceAbove > spaceBelow && spaceBelow < widget.items.length * 32.0 + 8;
        final height = math.min(widget.items.length * 32.0 + 8, math.max(0.0, opensAbove ? spaceAbove : spaceBelow));
        final left = info.anchorRect.left.clamp(8.0, math.max(8.0, info.overlaySize.width - width - 8));
        final top = opensAbove ? info.anchorRect.top - height - 4 : info.anchorRect.bottom + 4;
        return Positioned(
          left: left.toDouble(),
          top: top.toDouble(),
          width: width,
          height: height,
          child: TapRegion(
            groupId: info.tapRegionGroupId,
            onTapOutside: (_) => _controller.close(),
            child: Semantics(
              scopesRoute: true,
              explicitChildNodes: true,
              child: FocusScope(
                child: Shortcuts(
                  shortcuts: const {
                    SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
                    SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
                    SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
                    SingleActivator(LogicalKeyboardKey.arrowDown): NextFocusIntent(),
                    SingleActivator(LogicalKeyboardKey.arrowUp): PreviousFocusIntent(),
                  },
                  child: Actions(
                    actions: {
                      // Escape は開いている一覧で処理し、閉じた後は選択欄へフォーカスを戻す
                      DismissIntent: CallbackAction<DismissIntent>(
                        onInvoke: (_) {
                          _controller.close();
                          _focusNode.requestFocus();
                          return null;
                        },
                      ),
                    },
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: CupertinoDynamicColor.resolve(CupertinoColors.secondarySystemBackground, context),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: CupertinoDynamicColor.resolve(CupertinoColors.separator, context)),
                        boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 16, offset: Offset(0, 4))],
                      ),
                      child: CupertinoScrollbar(
                        controller: _scrollController,
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(4),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (final entry in widget.items.entries)
                                _CupertinoSelectItem(
                                  key: ValueKey(entry.key),
                                  label: entry.value,
                                  isSelected: entry.key == widget.value,
                                  onPressed: () {
                                    _controller.close();
                                    _focusNode.requestFocus();
                                    widget.onChanged?.call(entry.key);
                                  },
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
      // 一覧の開閉を読み上げでも把握できるよう、アンカーの状態を更新する
      builder: (context, controller, child) => Semantics(expanded: controller.isOpen, child: child),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: CupertinoDynamicColor.resolve(CupertinoColors.tertiarySystemFill, context),
          border: Border.all(color: CupertinoDynamicColor.resolve(CupertinoColors.separator, context)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: CupertinoButton(
          focusNode: _focusNode,
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          borderRadius: BorderRadius.circular(8),
          onPressed: isEnabled ? () => _controller.isOpen ? _controller.close() : _controller.open() : null,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.items[widget.value]!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textStyle,
                ),
              ),
              const SizedBox(width: 4),
              Icon(CupertinoIcons.chevron_down, size: 12, color: textStyle.color),
            ],
          ),
        ),
      ),
    );
  }
}

/// マウスとキーボードの操作対象をアクセント色で示す選択肢。
class _CupertinoSelectItem extends StatefulWidget {
  /// 選択肢の表示内容と選択状態を受け取って項目を構成する
  /// @param label 表示する選択肢のラベル
  /// @param isSelected 現在選択されている項目か
  /// @param onPressed 項目が選択されたときのコールバック
  /// @param key ウィジェットを識別するキー
  const _CupertinoSelectItem({super.key, required this.label, required this.isSelected, required this.onPressed});

  final String label;
  final bool isSelected;
  final VoidCallback onPressed;

  /// 選択肢のフォーカス状態を管理するオブジェクトを作成する。
  /// @returns 選択肢の状態
  @override
  State<_CupertinoSelectItem> createState() => _CupertinoSelectItemState();
}

class _CupertinoSelectItemState extends State<_CupertinoSelectItem> {
  final _focusNode = FocusNode();
  bool _hasFocus = false;

  /// 選択肢のフォーカスノードを解放する。
  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  /// 選択肢を構築する。
  /// @param context ウィジェットツリーの BuildContext
  /// @returns 選択肢のウィジェット
  @override
  Widget build(BuildContext context) {
    final isHighlighted = _hasFocus;
    final theme = CupertinoTheme.of(context);
    final foreground = isHighlighted
        ? CupertinoColors.white
        : CupertinoDynamicColor.resolve(CupertinoColors.label, context);
    return MouseRegion(
      // マウスで示す行と Enter で選ぶ行を一致させる
      onEnter: (_) => _focusNode.requestFocus(),
      child: Semantics(
        selected: widget.isSelected,
        child: CupertinoButton(
          focusNode: _focusNode,
          autofocus: widget.isSelected,
          minimumSize: const Size(0, 32),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          borderRadius: BorderRadius.circular(4),
          color: isHighlighted ? theme.primaryColor : CupertinoColors.transparent,
          focusColor: CupertinoColors.transparent,
          onFocusChange: (hasFocus) {
            setState(() => _hasFocus = hasFocus);
            // キーボードで移動した候補を、スクロール領域の見える位置へ送る
            if (hasFocus) {
              Scrollable.ensureVisible(context, alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd);
            }
          },
          onPressed: widget.onPressed,
          child: Row(
            children: [
              SizedBox(
                width: 18,
                child: widget.isSelected ? Icon(CupertinoIcons.check_mark, size: 13, color: foreground) : null,
              ),
              Expanded(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium!.copyWith(color: foreground),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 画像が未選択のときに追加方法を示すドロップ領域。
library;

import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';

/// 空の画像一覧全体を、クリックとドラッグの追加対象として表示する。
class EmptyDropArea extends StatelessWidget {
  /// ドロップ状態と画像追加コールバックを受け取って空状態を構成する。
  /// @param key ウィジェットを識別するキー
  /// @param isDropActive ドロップ対象として強調表示するか
  /// @param isEnabled 画像追加操作を有効にするか
  /// @param onAddFiles 画像追加時のコールバック
  const EmptyDropArea({
    super.key,
    required this.isDropActive,
    required this.isEnabled,
    required this.onAddFiles,
  });

  final bool isDropActive;
  final bool isEnabled;
  final VoidCallback onAddFiles;

  /// 空状態のドロップ領域を構築する。
  /// @param context ウィジェットツリーの BuildContext
  /// @returns 空状態のドロップ領域
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final borderColor = isDropActive ? colorScheme.primary : colorScheme.outlineVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 20),
      child: InkWell(
        onTap: isEnabled ? onAddFiles : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            border: Border.all(color: borderColor, width: isDropActive ? 2 : 1),
            borderRadius: BorderRadius.circular(12),
            color: isDropActive ? colorScheme.primary.withValues(alpha: 0.08) : null,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              // 更新バナーで一覧が低くなった場合は、追加操作を残して説明をツールチップへまとめる
              final isCompact = constraints.maxHeight < 96;
              return Tooltip(
                message: isCompact ? l10n.emptyDescription : '',
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: isCompact ? 8 : 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_photo_alternate_outlined, size: isCompact ? 24 : 32, color: borderColor),
                      const SizedBox(width: 16),
                      Flexible(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isDropActive ? l10n.dropImages : l10n.idle,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            if (!isCompact) ...[
                              const SizedBox(height: 4),
                              Text(l10n.emptyDescription, style: Theme.of(context).textTheme.bodySmall),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

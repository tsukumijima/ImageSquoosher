/// 画像一覧の件数と一括解除の操作を表示する見出し。
library;

import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';

/// 一覧名、件数、一括解除を1行へ収める。
class QueueHeader extends StatelessWidget {
  /// 件数と一括解除操作を受け取って一覧見出しを構成する。
  /// @param key ウィジェットを識別するキー
  /// @param imageCount 一覧内の画像数
  /// @param canClear 一括解除操作を有効にするか
  /// @param onClear 一括解除時のコールバック
  const QueueHeader({
    super.key,
    required this.imageCount,
    required this.canClear,
    required this.onClear,
  });

  final int imageCount;
  final bool canClear;
  final VoidCallback onClear;

  /// 一覧見出しを構築する。
  /// @param context ウィジェットツリーの BuildContext
  /// @returns 一覧見出しのウィジェット
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    l10n.queueTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                const SizedBox(width: 8),
                Text('$imageCount ${l10n.files}', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          // 画像追加と高さをそろえ、一覧の補助操作を中立色で表示する
          FilledButton.tonalIcon(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              foregroundColor: Theme.of(context).colorScheme.onSurface,
              iconColor: Theme.of(context).colorScheme.onSurface,
            ),
            onPressed: canClear ? onClear : null,
            icon: const Icon(Icons.clear_all, size: 18),
            label: Text(l10n.clearSelection, maxLines: 1),
          ),
        ],
      ),
    );
  }
}

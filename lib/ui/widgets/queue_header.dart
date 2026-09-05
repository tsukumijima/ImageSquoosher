/// 画像一覧の件数と一括解除の操作を表示する見出し。
library;

import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';

/// 一覧名、件数、一括解除を1行へ収めます。
class QueueHeader extends StatelessWidget {
  const QueueHeader({
    super.key,
    required this.imageCount,
    required this.canClear,
    required this.onClear,
  });

  final int imageCount;
  final bool canClear;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 12, 2),
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
          // 画像の追加と同じ意匠で、一覧に対する補助操作として表示する
          FilledButton.tonalIcon(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              foregroundColor: Theme.of(context).colorScheme.onSurface,
              iconColor: Theme.of(context).colorScheme.onSurface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              minimumSize: const Size(0, 32),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
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

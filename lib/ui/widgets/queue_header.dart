/// 画像一覧の件数と追加・一括解除の操作を表示する見出し。
library;

import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';

/// 一覧名、件数、画像の追加と一括解除を1行へ収めます。
class QueueHeader extends StatelessWidget {
  const QueueHeader({
    super.key,
    required this.imageCount,
    required this.canAdd,
    required this.canClear,
    required this.onAddFiles,
    required this.onClear,
  });

  final int imageCount;
  final bool canAdd;
  final bool canClear;
  final VoidCallback onAddFiles;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 12, 2),
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
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
            // 追加操作を一覧の近くへ置き、変換開始より控えめな中立色で表示する
            FilledButton.tonalIcon(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                foregroundColor: Theme.of(context).colorScheme.onSurface,
                iconColor: Theme.of(context).colorScheme.onSurface,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                minimumSize: const Size(0, 30),
                textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              ),
              onPressed: canAdd ? onAddFiles : null,
              icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
              label: Text(l10n.addFiles, maxLines: 1),
            ),
            const SizedBox(width: 4),
            // 幅が限られるときは解除をアイコンへまとめ、一覧名と件数を読み取れる幅を確保する
            if (constraints.maxWidth < 560)
              IconButton(
                tooltip: l10n.clearSelection,
                onPressed: canClear ? onClear : null,
                icon: const Icon(Icons.clear_all, size: 18),
              )
            else
              TextButton.icon(
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6)),
                onPressed: canClear ? onClear : null,
                icon: const Icon(Icons.clear_all, size: 18),
                label: Text(l10n.clearSelection, maxLines: 1),
              ),
          ],
        ),
      ),
    );
  }
}

/// 画像が未選択のときに追加方法を示すドロップ領域。
library;

import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';

/// 空の画像一覧全体を、クリックとドラッグの追加対象として表示します。
class EmptyDropArea extends StatelessWidget {
  const EmptyDropArea({
    super.key,
    required this.isDropActive,
    required this.isEnabled,
    required this.onAddFiles,
  });

  final bool isDropActive;
  final bool isEnabled;
  final VoidCallback onAddFiles;

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
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add_photo_alternate_outlined, size: 32, color: borderColor),
                const SizedBox(width: 16),
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(isDropActive ? l10n.dropImages : l10n.idle, style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 4),
                      Text(
                        l10n.emptyDescription,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 圧縮の全体状態と開始・停止操作を固定表示するフッター。
library;

import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';

/// 画像一覧をスクロールしている間も、現在状態と主要操作を表示します。
class CompressionFooter extends StatelessWidget {
  const CompressionFooter({
    super.key,
    required this.completedCount,
    required this.imageCount,
    required this.hasValidImages,
    required this.isCompressing,
    required this.isStopping,
    required this.onStart,
    required this.onStop,
  });

  final int completedCount;
  final int imageCount;
  final bool hasValidImages;
  final bool isCompressing;
  final bool isStopping;
  final VoidCallback onStart;
  final VoidCallback onStop;

  /// 待機、準備、圧縮、停止受付をそれぞれ固有の文とアイコンへ割り当てます。
  (IconData, String) _status(AppLocalizations l10n) {
    if (isStopping) {
      return (Icons.pending_outlined, l10n.stop);
    }
    if (isCompressing) {
      return (Icons.sync, l10n.statusProgress(completedCount, imageCount));
    }
    if (imageCount == 0) {
      return (Icons.image_outlined, l10n.statusWaiting);
    }
    return (Icons.check_circle_outline, l10n.statusReady);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final (statusIcon, statusText) = _status(l10n);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
        color: colorScheme.surface,
      ),
      child: Row(
        children: [
          Icon(statusIcon, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(statusText, maxLines: 1, overflow: TextOverflow.ellipsis)),
          if (isCompressing)
            OutlinedButton.icon(
              onPressed: isStopping ? null : onStop,
              icon: const Icon(Icons.stop_circle_outlined, size: 18),
              label: Text(l10n.stop, maxLines: 1),
            )
          else
            FilledButton.icon(
              style: FilledButton.styleFrom(
                foregroundColor: Colors.white,
                disabledForegroundColor: colorScheme.onSurface.withValues(alpha: 0.38),
              ),
              onPressed: hasValidImages ? onStart : null,
              icon: const Icon(Icons.compress, size: 18),
              label: Text(l10n.start, maxLines: 1),
            ),
        ],
      ),
    );
  }
}

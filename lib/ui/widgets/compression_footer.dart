/// 圧縮の全体状態と開始・停止操作を固定表示するフッター。
library;

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

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
    this.isOverwriteEnabled = false,
    required this.onStart,
    required this.onStop,
  });

  final int completedCount;
  final int imageCount;
  final bool hasValidImages;
  final bool isCompressing;
  final bool isStopping;
  final bool isOverwriteEnabled;
  final VoidCallback onStart;
  final VoidCallback onStop;

  /// 待機、準備、圧縮、停止受付、完了をそれぞれ固有の文とアイコンへ割り当てます。
  (IconData, String) _status(AppLocalizations l10n) {
    if (isStopping) {
      return (Icons.pending_outlined, l10n.stop);
    }
    if (isCompressing) {
      return (Icons.sync, l10n.statusProgress(completedCount, imageCount));
    }
    if (isOverwriteEnabled && hasValidImages) {
      return (Icons.warning_amber_rounded, l10n.overwriteWarning);
    }
    if (imageCount == 0) {
      return (Icons.image_outlined, l10n.statusWaiting);
    }
    // 全画像の変換が成功し、次に処理する画像がない状態を完了として表示する
    if (completedCount == imageCount && !hasValidImages) {
      return (Icons.check_circle_outline, l10n.compressionComplete);
    }
    return (Icons.check_circle_outline, l10n.statusReady);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final (statusIcon, statusText) = _status(l10n);
    final isOverwriteWarningVisible = isOverwriteEnabled && hasValidImages && !isCompressing;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
        color: colorScheme.surface,
      ),
      child: Row(
        children: [
          Icon(statusIcon, size: 18, color: isOverwriteWarningVisible ? colorScheme.error : null),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              statusText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: isOverwriteWarningVisible ? colorScheme.error : null),
            ),
          ),
          if (isCompressing)
            CupertinoButton.tinted(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              minimumSize: const Size(0, 34),
              borderRadius: BorderRadius.circular(8),
              onPressed: isStopping ? null : onStop,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(CupertinoIcons.stop_circle, size: 18),
                  const SizedBox(width: 8),
                  Text(l10n.stop, maxLines: 1),
                ],
              ),
            )
          else
            CupertinoButton.filled(
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              minimumSize: const Size(0, 34),
              borderRadius: BorderRadius.circular(8),
              onPressed: hasValidImages ? onStart : null,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(CupertinoIcons.arrow_down_right_arrow_up_left, size: 18),
                  const SizedBox(width: 8),
                  Text(l10n.start, maxLines: 1, style: const TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

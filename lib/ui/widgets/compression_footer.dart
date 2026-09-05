/// 圧縮の全体状態と開始・停止操作を固定表示するフッター。
library;

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

import '../../l10n/generated/app_localizations.dart';
import '../theme.dart';

/// 画像一覧をスクロールしている間も、現在状態と主要操作を表示する。
class CompressionFooter extends StatelessWidget {
  /// 変換状態と操作コールバックを受け取ってフッターを構成する。
  /// @param completedCount 完了した画像数
  /// @param failedCount 失敗した画像数
  /// @param stoppedCount 停止した画像数
  /// @param progress 全体の進捗率
  /// @param imageCount キュー内の画像数
  /// @param hasValidImages 変換可能な画像があるか
  /// @param isCompressing 変換中か
  /// @param isStopping 停止処理中か
  /// @param isOverwriteEnabled 上書き設定が有効か
  /// @param onStart 変換開始時のコールバック
  /// @param onStop 変換停止時のコールバック
  /// @param key ウィジェットを識別するキー
  const CompressionFooter({
    super.key,
    required this.completedCount,
    this.failedCount = 0,
    this.stoppedCount = 0,
    this.progress = 0,
    required this.imageCount,
    required this.hasValidImages,
    required this.isCompressing,
    required this.isStopping,
    this.isOverwriteEnabled = false,
    required this.onStart,
    required this.onStop,
  });

  final int completedCount;
  final int failedCount;
  final int stoppedCount;
  final double progress;
  final int imageCount;
  final bool hasValidImages;
  final bool isCompressing;
  final bool isStopping;
  final bool isOverwriteEnabled;
  final VoidCallback onStart;
  final VoidCallback onStop;

  /// 待機、準備、圧縮、停止受付、完了をそれぞれ固有の文とアイコンへ割り当てる。
  /// @param l10n 現在の表示言語のローカライズ情報
  /// @returns 状態アイコンと表示文の組
  (IconData, String) _status(AppLocalizations l10n) {
    if (isStopping) {
      return (Icons.pending_outlined, l10n.stopping);
    }
    if (isCompressing) {
      return (Icons.sync, l10n.statusProgress(completedCount, imageCount));
    }
    if (failedCount > 0) {
      return (Icons.error_outline, l10n.conversionFailedStatus);
    }
    if (stoppedCount > 0) {
      return (Icons.stop_circle_outlined, l10n.stopped);
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

  /// 圧縮フッターを構築する。
  /// @param context ウィジェットツリーの BuildContext
  /// @returns 圧縮フッターのウィジェット
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final (statusIcon, statusText) = _status(l10n);
    final isOverwriteWarningVisible = isOverwriteEnabled && hasValidImages && !isCompressing;
    final isCompleted = imageCount > 0 && completedCount == imageCount && !isCompressing;
    final statusColor = isOverwriteWarningVisible || (!isCompressing && failedCount > 0)
        ? AppColors.error
        : isCompleted
        ? AppColors.success
        : colorScheme.onSurfaceVariant;
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
        color: colorScheme.surface,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
            child: Row(
              children: [
                Icon(statusIcon, size: 18, color: statusColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    statusText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: statusColor),
                  ),
                ),
                if (isCompressing)
                  FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      backgroundColor: colorScheme.surfaceContainerHighest,
                      foregroundColor: colorScheme.onSurface,
                      iconColor: colorScheme.onSurface,
                    ),
                    onPressed: isStopping ? null : onStop,
                    icon: const Icon(CupertinoIcons.stop_circle, size: 18),
                    label: Text(l10n.stop, maxLines: 1),
                  )
                else
                  FilledButton.icon(
                    onPressed: hasValidImages ? onStart : null,
                    icon: const Icon(CupertinoIcons.arrow_down_right_arrow_up_left, size: 18),
                    label: Text(l10n.start, maxLines: 1),
                  ),
              ],
            ),
          ),
          // ウインドウの下端へ接し、処理を終えた後も到達した進捗を表示する
          LinearProgressIndicator(
            value: isCompleted ? 1 : progress,
            minHeight: 4,
            color: failedCount > 0 ? AppColors.error : AppColors.success,
            backgroundColor: colorScheme.surfaceContainerHighest,
            trackGap: 0,
            stopIndicatorRadius: 0,
          ),
        ],
      ),
    );
  }
}

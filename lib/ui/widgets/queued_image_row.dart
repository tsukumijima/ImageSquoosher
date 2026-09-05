/// 画像一覧のプレビュー、寸法、出力名、処理状態を表示する行。
library;

import 'dart:io';

import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../models/aspect_ratio.dart' as image_ratio;
import '../../models/conversion_settings.dart';
import '../../models/image_dimensions.dart';
import '../../services/squoosher_controller.dart';
import '../theme.dart';

/// 1枚の画像について、入出力の名前と寸法を固定高さの2行へまとめる。
class QueuedImageRow extends StatelessWidget {
  /// キュー内画像の状態と操作コールバックを受け取って行を構成する。
  /// @param key ウィジェットを識別するキー
  /// @param queuedImage 表示対象のキュー画像
  /// @param settings 現在の変換設定
  /// @param canRemove 削除操作を有効にするか
  /// @param onOpenSourceFile 元画像を開くコールバック
  /// @param onOpenFile 出力画像を開くコールバック
  /// @param onOpenFolder 出力先フォルダーを開くコールバック
  /// @param onRemove キューから削除するコールバック
  const QueuedImageRow({
    super.key,
    required this.queuedImage,
    required this.settings,
    required this.canRemove,
    required this.onOpenSourceFile,
    required this.onOpenFile,
    required this.onOpenFolder,
    required this.onRemove,
  });

  final QueuedImage queuedImage;
  final ConversionSettings settings;
  final bool canRemove;
  final VoidCallback onOpenSourceFile;
  final VoidCallback onOpenFile;
  final VoidCallback onOpenFolder;
  final VoidCallback onRemove;

  /// 画像状態に対応する短いラベルを返す。
  /// @param l10n 現在の表示言語のローカライズ情報
  /// @returns 状態に対応する表示ラベル
  String _statusText(AppLocalizations l10n) {
    return switch (queuedImage.status) {
      QueuedImageStatus.queued => l10n.queued,
      QueuedImageStatus.processing => l10n.processing,
      QueuedImageStatus.completed => l10n.completed,
      QueuedImageStatus.failed => l10n.failed,
      QueuedImageStatus.stopped => l10n.stopped,
    };
  }

  /// 待機、進行、成功、失敗、停止を色でも見分けられるようにする。
  /// @param colorScheme 状態色の基準となる配色
  /// @returns 状態に対応する色
  Color _statusColor(ColorScheme colorScheme) {
    return switch (queuedImage.status) {
      QueuedImageStatus.queued => colorScheme.onSurfaceVariant,
      QueuedImageStatus.processing => colorScheme.primary,
      QueuedImageStatus.completed => AppColors.success,
      QueuedImageStatus.failed => AppColors.error,
      QueuedImageStatus.stopped => colorScheme.secondary,
    };
  }

  /// 色とアイコンを併用し、待機から完了まで同じ位置で状態を識別できるようにする。
  /// @param context テーマとローカライズ情報を取得する BuildContext
  /// @returns 状態バッジのウィジェット
  Widget _buildStatusBadge(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isNeutral = queuedImage.status == QueuedImageStatus.queued || queuedImage.status == QueuedImageStatus.stopped;
    final backgroundColor = isNeutral ? colorScheme.surfaceContainerHighest : _statusColor(colorScheme);
    final foregroundColor = isNeutral ? colorScheme.onSurfaceVariant : Colors.white;
    final icon = switch (queuedImage.status) {
      QueuedImageStatus.queued => Icons.schedule,
      QueuedImageStatus.processing => Icons.sync,
      QueuedImageStatus.completed => Icons.check_circle,
      QueuedImageStatus.failed => Icons.error,
      QueuedImageStatus.stopped => Icons.stop_circle,
    };
    return Container(
      key: const ValueKey('image-status-badge'),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(color: backgroundColor, borderRadius: BorderRadius.circular(10)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: foregroundColor, size: 12),
          const SizedBox(width: 3),
          Text(
            _statusText(AppLocalizations.of(context)),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: foregroundColor, height: 1.2),
          ),
        ],
      ),
    );
  }

  /// 代表的な比率と、最大公約数で約分した任意比率を短く表示する。
  /// @param dimensions 比率を表示する画像寸法
  /// @returns 画像比率の表示文字列
  String _aspectRatioText(ImageDimensions dimensions) {
    // 代表的な比率では、リサイズ後の端数を短い表記へ戻す
    for (final preset in image_ratio.AspectRatioPreset.values) {
      final ratio = preset.value;
      if (ratio != null && (dimensions.width - dimensions.height * ratio).abs() <= 1) {
        return preset.label;
      }
    }
    // 任意の画像は最大公約数で約分し、実寸法から求めた比率を示す
    final divisor = dimensions.width.gcd(dimensions.height);
    return '${dimensions.width ~/ divisor}:${dimensions.height ~/ divisor}';
  }

  /// 実寸法を保ち、出力の1画素以内の丸めは指定した比率として表示する。
  /// @param dimensions 表示する画像寸法
  /// @param isOutput 出力寸法として設定比率を優先するか
  /// @returns 寸法と比率の表示文字列
  String _dimensionText(ImageDimensions? dimensions, {bool isOutput = false}) {
    if (dimensions == null) {
      return '—';
    }
    final source = queuedImage.sourceDimensions;
    if (isOutput && source != null) {
      final requestedRatio = settings.aspectRatio.resolve(source);
      // 設定値は実際の出力にも一致するときだけ採用し、保存済み結果の表示を保つ
      if (settings.aspectRatio.preset != image_ratio.AspectRatioPreset.original &&
          (dimensions.width - dimensions.height * requestedRatio).abs() <= 1) {
        final label = settings.aspectRatio.customValue == null
            ? settings.aspectRatio.label
            : '${settings.aspectRatio.label}:1';
        return '$dimensions ($label)';
      }
      // 元の比率を維持したリサイズは、端数が出ても入力と同じ短い比率で示す
      if ((dimensions.width - dimensions.height * source.aspectRatio).abs() <= 1) {
        return '$dimensions (${_aspectRatioText(source)})';
      }
    }
    return '$dimensions (${_aspectRatioText(dimensions)})';
  }

  /// 出力予定と生成済み出力を同じ位置で確認できるファイル名を返す。
  /// @param l10n 現在の表示言語のローカライズ情報
  /// @returns 出力ファイル名または未作成を示す文字列
  String _outputFileName(AppLocalizations l10n) {
    final outputPath = queuedImage.outputPath;
    if (outputPath == null) {
      return l10n.outputNotCreated;
    }
    return File(outputPath).uri.pathSegments.last;
  }

  /// 内部例外の英語表現を、現在の表示言語に対応する短い理由へ置き換える。
  /// @param l10n 現在の表示言語のローカライズ情報
  /// @returns 利用者向けのエラー理由
  String _errorText(AppLocalizations l10n) {
    final message = queuedImage.errorMessage ?? '';
    if (message.contains('Animated images')) {
      return l10n.animatedImage;
    }
    if (message.contains('Only JPEG') || message.contains('not a supported image')) {
      return l10n.unsupportedImage;
    }
    if (message.contains('could not be decoded') || message.contains('contains no pixel data')) {
      return l10n.invalidImage;
    }
    return l10n.conversionError;
  }

  /// ファイルサイズを画像同士で比較しやすい単位へ整える。
  /// @param byteLength バイト単位のファイルサイズ
  /// @param l10n 現在の表示言語のローカライズ情報
  /// @returns 比較しやすい単位へ変換したサイズ
  String _formatBytes(int? byteLength, AppLocalizations l10n) {
    if (byteLength == null) {
      return l10n.unknownSize;
    }
    if (byteLength < 1024) {
      return '${byteLength}B';
    }
    if (byteLength < 1024 * 1024) {
      return '${(byteLength / 1024).toStringAsFixed(1)}KB';
    }
    return '${(byteLength / (1024 * 1024)).toStringAsFixed(1)}MB';
  }

  /// 圧縮できた割合と、出力が大きくなった場合の増加率を区別する。
  /// @param l10n 現在の表示言語のローカライズ情報
  /// @returns サイズ変化率の表示文字列
  String _sizeChangeText(AppLocalizations l10n) {
    final inputSize = queuedImage.byteLength;
    final outputSize = queuedImage.outputByteLength;
    if (inputSize == null || outputSize == null || inputSize == 0) {
      return '—';
    }
    final reduction = (1 - outputSize / inputSize) * 100;
    return reduction >= 0
        ? l10n.compressionReduction(reduction.toStringAsFixed(0))
        : l10n.sizeIncrease((-reduction).toStringAsFixed(0));
  }

  /// 待機中は切り抜き予定を、完了後は保存済みの出力をプレビューする。
  /// @param context テーマと表示倍率を取得する BuildContext
  /// @returns 画像プレビューのウィジェット
  Widget _buildPreview(BuildContext context) {
    final hasCompletedOutput = queuedImage.status == QueuedImageStatus.completed && queuedImage.outputPath != null;
    // 上書きで元入力が削除された後も、出力ファイルとその寸法から結果を表示する
    final sourceDimensions =
        (hasCompletedOutput ? queuedImage.outputDimensions : queuedImage.sourceDimensions) ??
        const ImageDimensions(1, 1);
    final sourceRatio = sourceDimensions.width / sourceDimensions.height;
    final requestedRatio = hasCompletedOutput ? sourceRatio : settings.aspectRatio.resolve(sourceDimensions);
    final previewRatio = requestedRatio.clamp(0.55, 1.8).toDouble();
    final cacheSize = (48 * MediaQuery.devicePixelRatioOf(context)).round();
    final previewWidth = previewRatio >= 1 ? cacheSize : (cacheSize * previewRatio).ceil();
    final previewHeight = previewRatio >= 1 ? (cacheSize / previewRatio).ceil() : cacheSize;
    // BoxFit.cover で切り抜かれる長辺は制限せず、枠を満たす短辺だけを物理解像度へ縮小してぼけとメモリ消費を抑える
    final cacheWidth = sourceRatio <= previewRatio ? previewWidth : null;
    final cacheHeight = sourceRatio > previewRatio ? previewHeight : null;
    return SizedBox(
      width: 48,
      height: 48,
      child: Center(
        child: AspectRatio(
          aspectRatio: previewRatio,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.file(
              File(hasCompletedOutput ? queuedImage.outputPath! : queuedImage.path),
              fit: BoxFit.cover,
              cacheWidth: cacheWidth,
              cacheHeight: cacheHeight,
              errorBuilder: (context, error, stackTrace) => ColoredBox(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: const Center(child: Icon(Icons.image_not_supported_outlined, size: 20)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// キュー画像の行を構築する。
  /// @param context ウィジェットツリーの BuildContext
  /// @returns キュー画像行のウィジェット
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isCompleted = queuedImage.status == QueuedImageStatus.completed;
    final hasFailed = queuedImage.status == QueuedImageStatus.failed;
    final inputText = '${queuedImage.fileName} (${_formatBytes(queuedImage.byteLength, l10n)})';
    final outputName = _outputFileName(l10n);
    final resultText = isCompleted
        ? ' (${_formatBytes(queuedImage.outputByteLength, l10n)} / ${_sizeChangeText(l10n)})'
        : '';
    final dimensionsText =
        '${_dimensionText(queuedImage.sourceDimensions)} → ${_dimensionText(queuedImage.outputDimensions, isOutput: true)}';
    final metadataStyle = theme.textTheme.bodySmall?.copyWith(height: 1.25);
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      // ファイル一覧と同じダブルクリック操作に、ホバーと波紋の反応を添える
      child: InkWell(
        onDoubleTap: onOpenSourceFile,
        splashFactory: InkRipple.splashFactory,
        hoverColor: colorScheme.onSurface.withValues(alpha: 0.06),
        child: SizedBox(
          height: 64,
          child: Column(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  child: Row(
                    children: [
                      _buildPreview(context),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 結果の数値を常に見せ、長いファイル名だけを省略する
                            Tooltip(
                              message: '$inputText → $outputName$resultText',
                              child: Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      inputText,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  Text(' → ', style: metadataStyle),
                                  Flexible(
                                    child: Text(
                                      outputName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.labelMedium,
                                    ),
                                  ),
                                  if (isCompleted)
                                    Text(
                                      resultText,
                                      style: theme.textTheme.labelMedium?.copyWith(color: AppColors.success),
                                    ),
                                ],
                              ),
                            ),
                            // 操作ボタンを常設し、変換中も完了後も2行の高さと位置を保つ
                            SizedBox(
                              height: 26,
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Tooltip(
                                      message: hasFailed ? _errorText(l10n) : dimensionsText,
                                      child: Text(
                                        hasFailed ? _errorText(l10n) : dimensionsText,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: metadataStyle?.copyWith(color: hasFailed ? AppColors.error : null),
                                      ),
                                    ),
                                  ),
                                  _buildStatusBadge(context),
                                  const SizedBox(width: 6),
                                  // 操作領域のダブルクリックはボタン内で受け、元画像を開く操作と分ける
                                  GestureDetector(
                                    onDoubleTap: () {},
                                    child: Row(
                                      children: [
                                        IconButton(
                                          onPressed: isCompleted ? onOpenFile : null,
                                          tooltip: l10n.openFile,
                                          icon: const Icon(Icons.open_in_new, size: 16),
                                          constraints: const BoxConstraints.tightFor(width: 26, height: 26),
                                          padding: EdgeInsets.zero,
                                        ),
                                        IconButton(
                                          onPressed: onOpenFolder,
                                          tooltip: l10n.openFolder,
                                          icon: const Icon(Icons.folder_open, size: 17),
                                          constraints: const BoxConstraints.tightFor(width: 26, height: 26),
                                          padding: EdgeInsets.zero,
                                        ),
                                        IconButton(
                                          onPressed: canRemove ? onRemove : null,
                                          tooltip: l10n.removeItem,
                                          icon: const Icon(Icons.close, size: 17),
                                          constraints: const BoxConstraints.tightFor(width: 26, height: 26),
                                          padding: EdgeInsets.zero,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // 完了済みの進捗は保持し、失敗時は到達位置を赤で示す
              LinearProgressIndicator(
                value: isCompleted ? 1 : queuedImage.progress,
                minHeight: 3,
                color: hasFailed ? AppColors.error : AppColors.success,
                backgroundColor: colorScheme.surfaceContainerHighest,
                trackGap: 0,
                stopIndicatorRadius: 0,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

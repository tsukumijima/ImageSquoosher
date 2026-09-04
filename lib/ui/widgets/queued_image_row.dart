/// 画像一覧のプレビュー、寸法、出力名、処理状態を表示する行。
library;

import 'dart:io';

import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../models/conversion_settings.dart';
import '../../models/image_dimensions.dart';
import '../../services/squoosher_controller.dart';

/// 1枚の画像について、入力から出力までの見通しを1行へまとめます。
class QueuedImageRow extends StatelessWidget {
  const QueuedImageRow({
    super.key,
    required this.queuedImage,
    required this.settings,
    required this.canRemove,
    required this.onOpenFile,
    required this.onOpenFolder,
    required this.onRemove,
  });

  final QueuedImage queuedImage;
  final ConversionSettings settings;
  final bool canRemove;
  final VoidCallback onOpenFile;
  final VoidCallback onOpenFolder;
  final VoidCallback onRemove;

  /// 画像状態に対応する短いラベルを返します。
  String _statusText(AppLocalizations l10n) {
    return switch (queuedImage.status) {
      QueuedImageStatus.queued => l10n.queued,
      QueuedImageStatus.processing => l10n.processing,
      QueuedImageStatus.completed => l10n.completed,
      QueuedImageStatus.failed => l10n.failed,
      QueuedImageStatus.stopped => l10n.stopped,
    };
  }

  /// 待機、進行、成功、失敗、停止を色でも見分けられるようにします。
  Color _statusColor(ColorScheme colorScheme) {
    return switch (queuedImage.status) {
      QueuedImageStatus.queued => colorScheme.onSurfaceVariant,
      QueuedImageStatus.processing => colorScheme.primary,
      QueuedImageStatus.completed => colorScheme.tertiary,
      QueuedImageStatus.failed => colorScheme.error,
      QueuedImageStatus.stopped => colorScheme.secondary,
    };
  }

  /// 寸法の読み取り前も行の情報配置を保つ文字列を返します。
  String _dimensionText(ImageDimensions? dimensions, AppLocalizations l10n) {
    if (dimensions == null) {
      return '—';
    }
    return l10n.dimensionValue(dimensions.width, dimensions.height);
  }

  /// 出力予定と生成済み出力を同じ位置で確認できるファイル名を返します。
  String _outputFileName(AppLocalizations l10n) {
    final outputPath = queuedImage.outputPath;
    if (outputPath == null) {
      return l10n.outputNotCreated;
    }
    return File(outputPath).uri.pathSegments.last;
  }

  /// 内部例外の英語表現を、現在の表示言語に対応する短い理由へ置き換えます。
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

  /// ファイルサイズを画像同士で比較しやすい単位へ整えます。
  String _formatBytes(int? byteLength, AppLocalizations l10n) {
    if (byteLength == null) {
      return l10n.unknownSize;
    }
    if (byteLength < 1024) {
      return '$byteLength B';
    }
    if (byteLength < 1024 * 1024) {
      return '${(byteLength / 1024).toStringAsFixed(1)} KB';
    }
    return '${(byteLength / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// 完成した画像では入力サイズから減った割合を表示します。
  String _reductionText() {
    final inputSize = queuedImage.byteLength;
    final outputSize = queuedImage.outputByteLength;
    if (inputSize == null || outputSize == null || inputSize == 0) {
      return '—';
    }
    return '${((1 - outputSize / inputSize) * 100).toStringAsFixed(1)}%';
  }

  /// 切り抜き比率を反映した小さなプレビューを作ります。
  Widget _buildPreview(BuildContext context) {
    final sourceDimensions = queuedImage.sourceDimensions ?? const ImageDimensions(1, 1);
    final requestedRatio = settings.aspectRatio.resolve(sourceDimensions);
    final previewRatio = requestedRatio.clamp(0.55, 1.8).toDouble();
    return SizedBox(
      width: 48,
      height: 48,
      child: Center(
        child: AspectRatio(
          aspectRatio: previewRatio,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.file(
              File(queuedImage.path),
              fit: BoxFit.cover,
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final statusColor = _statusColor(colorScheme);
    final metadataStyle = Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.25);
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildPreview(context),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    queuedImage.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    '${l10n.sourceSize}: ${_dimensionText(queuedImage.sourceDimensions, l10n)} · ${_formatBytes(queuedImage.byteLength, l10n)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: metadataStyle,
                  ),
                  Text(
                    '${l10n.outputSize}: ${_dimensionText(queuedImage.outputDimensions, l10n)} · ${_outputFileName(l10n)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: metadataStyle,
                  ),
                  if (queuedImage.status == QueuedImageStatus.completed)
                    Wrap(
                      spacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          '${_formatBytes(queuedImage.byteLength, l10n)} → ${_formatBytes(queuedImage.outputByteLength, l10n)} (${_reductionText()})',
                          style: metadataStyle,
                        ),
                        TextButton(onPressed: onOpenFile, child: Text(l10n.openFile)),
                        TextButton(onPressed: onOpenFolder, child: Text(l10n.openFolder)),
                      ],
                    ),
                  if (queuedImage.errorMessage != null)
                    Text(
                      _errorText(l10n),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: metadataStyle?.copyWith(color: colorScheme.error),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                _statusText(l10n),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(color: statusColor),
              ),
            ),
            if (canRemove)
              SizedBox(
                width: 32,
                height: 32,
                child: IconButton(
                  onPressed: onRemove,
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: l10n.removeItem,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

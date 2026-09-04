/// 更新可能なバージョンを伝えるバナー。
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../services/logging_service.dart';
import '../../services/update_check_service.dart';

/// 利用可能な更新を画面上部に控えめに表示する。
class UpdateBanner extends StatelessWidget {
  final UpdateCheckResult result;
  final VoidCallback onDismiss;

  const UpdateBanner({super.key, required this.result, required this.onDismiss});

  /// リリースページを標準ブラウザで開く。
  Future<void> _openReleasePage(BuildContext context) async {
    final releaseURL = result.releaseURL;
    if (releaseURL == null) {
      return;
    }

    try {
      final opened = await launchUrl(Uri.parse(releaseURL), mode: LaunchMode.externalApplication);
      if (opened == false && context.mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.releaseOpenFailed)),
        );
      }
    } catch (error, stackTrace) {
      LoggingService.instance.error(
        'Failed to open release page.',
        tag: 'UpdateBanner',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      color: primaryColor.withValues(alpha: 0.13),
      child: Row(
        children: [
          Icon(Icons.system_update_alt, color: primaryColor, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text('${l10n.updateAvailable} (${result.latestVersion})'),
          ),
          TextButton(
            onPressed: () => _openReleasePage(context),
            child: Text(l10n.viewRelease),
          ),
          IconButton(
            onPressed: onDismiss,
            icon: const Icon(Icons.close, size: 18),
            tooltip: l10n.dismiss,
          ),
        ],
      ),
    );
  }
}

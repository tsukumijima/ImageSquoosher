/// アプリ名、画像追加、補助操作をまとめる画面ヘッダー。
library;

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

import '../../l10n/generated/app_localizations.dart';

/// ヘッダーメニューから親画面へ伝える操作です。
enum HomeMenuAction { checkForUpdates, japanese, english, restoreDefaults, about }

/// 画面上端へ主要操作を固定し、補助操作をメニューへまとめます。
class HomeHeader extends StatelessWidget {
  const HomeHeader({
    super.key,
    required this.isCompressing,
    required this.isFinderSyncEnabled,
    required this.isFinderIntegrationAvailable,
    required this.onAddFiles,
    required this.onFinderSettings,
    required this.onMenuAction,
  });

  final bool isCompressing;
  final bool isFinderSyncEnabled;
  final bool isFinderIntegrationAvailable;
  final VoidCallback onAddFiles;
  final VoidCallback onFinderSettings;
  final ValueChanged<HomeMenuAction> onMenuAction;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 12, 8),
      child: Row(
        children: [
          Image.asset(
            'assets/images/app_icon_1024.png',
            width: 32,
            height: 32,
            filterQuality: FilterQuality.high,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              l10n.appTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
          CupertinoButton.filled(
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            minimumSize: const Size(0, 34),
            borderRadius: BorderRadius.circular(8),
            onPressed: isCompressing ? null : onAddFiles,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(CupertinoIcons.photo_on_rectangle, size: 18),
                const SizedBox(width: 8),
                Text(l10n.addFiles, maxLines: 1, style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          const SizedBox(width: 4),
          if (isFinderIntegrationAvailable)
            SizedBox(
              width: 40,
              height: 40,
              child: IconButton(
                tooltip: isFinderSyncEnabled ? l10n.finderSyncManage : l10n.finderSyncEnable,
                onPressed: isCompressing ? null : onFinderSettings,
                icon: Icon(
                  isFinderSyncEnabled ? Icons.extension : Icons.extension_off_outlined,
                  color: isFinderSyncEnabled ? Theme.of(context).colorScheme.primary : null,
                ),
              ),
            ),
          SizedBox(
            width: 40,
            height: 40,
            child: PopupMenuButton<HomeMenuAction>(
              padding: const EdgeInsets.all(8),
              tooltip: l10n.settings,
              icon: const Icon(Icons.more_vert),
              onSelected: onMenuAction,
              itemBuilder: (context) => [
                PopupMenuItem(value: HomeMenuAction.checkForUpdates, child: Text(l10n.checkForUpdates)),
                const PopupMenuDivider(),
                PopupMenuItem(value: HomeMenuAction.japanese, child: Text(l10n.japanese)),
                PopupMenuItem(value: HomeMenuAction.english, child: Text(l10n.english)),
                PopupMenuItem(
                  value: HomeMenuAction.restoreDefaults,
                  enabled: !isCompressing,
                  child: Text(l10n.restoreDefaults),
                ),
                const PopupMenuDivider(),
                PopupMenuItem(value: HomeMenuAction.about, child: Text(l10n.about)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

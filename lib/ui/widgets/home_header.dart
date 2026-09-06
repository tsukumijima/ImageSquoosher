/// アプリ名と補助操作をまとめる画面ヘッダー。
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';

/// ヘッダーメニューから親画面へ伝える操作。
enum HomeMenuAction { checkForUpdates, japanese, english, restoreDefaults, about }

/// Windows の Explorer 連携に表示する状態。
enum WindowsShellIntegrationStatus { enabled, disabled, repair }

/// 画面上端へ主要操作を固定し、補助操作をメニューへまとめる。
class HomeHeader extends StatelessWidget {
  /// ヘッダーの状態と各操作コールバックを受け取って構成する。
  /// @param key ウィジェットを識別するキー
  /// @param isCompressing 変換中か
  /// @param isFinderSyncEnabled Finder Sync が有効か
  /// @param isFinderIntegrationAvailable Finder Sync 操作を表示できるか
  /// @param onAddFiles 画像追加時のコールバック
  /// @param onFinderSettings Finder Sync または Explorer 連携の操作時に呼び出すコールバック
  /// @param onMenuAction メニュー操作の通知先
  /// @param isWindowsShellIntegration Explorer 連携の操作を表示するか
  /// @param windowsShellIntegrationStatus Explorer 連携の現在の状態
  /// @param windowsUACShieldIcon Windows 標準の UAC 盾アイコン
  /// @param isWindowsShellIntegrationBusy Explorer 連携の変更中か
  const HomeHeader({
    super.key,
    required this.isCompressing,
    required this.isFinderSyncEnabled,
    required this.isFinderIntegrationAvailable,
    required this.onAddFiles,
    required this.onFinderSettings,
    required this.onMenuAction,
    this.isWindowsShellIntegration = false,
    this.windowsShellIntegrationStatus = WindowsShellIntegrationStatus.disabled,
    this.windowsUACShieldIcon,
    this.isWindowsShellIntegrationBusy = false,
  });

  final bool isCompressing;
  final bool isFinderSyncEnabled;
  final bool isFinderIntegrationAvailable;
  final VoidCallback onAddFiles;
  final VoidCallback onFinderSettings;
  final ValueChanged<HomeMenuAction> onMenuAction;
  final bool isWindowsShellIntegration;
  final WindowsShellIntegrationStatus windowsShellIntegrationStatus;
  final Uint8List? windowsUACShieldIcon;
  final bool isWindowsShellIntegrationBusy;

  static const _menuItemStyle = ButtonStyle(
    minimumSize: WidgetStatePropertyAll(Size(0, 32)),
    padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12)),
    visualDensity: VisualDensity.standard,
  );

  /// ヘッダーを構築する。
  /// @param context ウィジェットツリーの BuildContext
  /// @returns ヘッダーのウィジェット
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // ポップアップでも本文と同じフォントを使い、メニュー用の文字サイズだけ調整する
    final menuItemStyle = _menuItemStyle.copyWith(
      textStyle: WidgetStatePropertyAll(Theme.of(context).textTheme.bodyMedium!.copyWith(fontSize: 13)),
    );
    final windowsShellTooltip = switch (windowsShellIntegrationStatus) {
      WindowsShellIntegrationStatus.enabled => l10n.windowsShellDisableTooltip,
      WindowsShellIntegrationStatus.repair => l10n.windowsShellRepairTooltip,
      WindowsShellIntegrationStatus.disabled => l10n.windowsShellEnableTooltip,
    };
    final isWindowsShellActionDisabled = isCompressing || isWindowsShellIntegrationBusy;
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
          // 画像追加をアクセント色で示し、主要操作に共通のボタン寸法を使う
          FilledButton.icon(
            onPressed: isCompressing ? null : onAddFiles,
            icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
            label: Text(l10n.addFiles, maxLines: 1),
          ),
          const SizedBox(width: 4),
          if (isFinderIntegrationAvailable)
            SizedBox(
              width: 40,
              height: 40,
              child: IconButton(
                tooltip: isWindowsShellIntegration
                    ? windowsShellTooltip
                    : isFinderSyncEnabled
                    ? l10n.finderSyncManage
                    : l10n.finderSyncEnable,
                onPressed: isWindowsShellActionDisabled ? null : onFinderSettings,
                icon: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    if (isWindowsShellIntegration && isWindowsShellIntegrationBusy)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      Icon(
                        isFinderSyncEnabled ? Icons.extension : Icons.extension_off_outlined,
                        color: isFinderSyncEnabled ? Theme.of(context).colorScheme.primary : null,
                      ),
                    if (isWindowsShellIntegration &&
                        isWindowsShellIntegrationBusy == false &&
                        windowsShellIntegrationStatus != WindowsShellIntegrationStatus.enabled &&
                        windowsUACShieldIcon != null)
                      Positioned(
                        right: -3,
                        bottom: -3,
                        child: Image.memory(
                          windowsUACShieldIcon!,
                          width: 14,
                          height: 14,
                          gaplessPlayback: true,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          SizedBox(
            width: 40,
            height: 40,
            // 言語はサブメニューへまとめ、設定操作からアプリ情報へ順に並べる
            child: MenuAnchor(
              style: const MenuStyle(
                padding: WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 4)),
              ),
              menuChildren: [
                MenuItemButton(
                  style: menuItemStyle,
                  leadingIcon: const Icon(Icons.restore, size: 18),
                  onPressed: isCompressing ? null : () => onMenuAction(HomeMenuAction.restoreDefaults),
                  child: Text(l10n.restoreDefaults),
                ),
                SubmenuButton(
                  style: menuItemStyle,
                  leadingIcon: const Icon(Icons.language, size: 18),
                  menuChildren: [
                    MenuItemButton(
                      style: menuItemStyle,
                      leadingIcon: const Icon(Icons.translate, size: 18),
                      trailingIcon: Localizations.localeOf(context).languageCode == 'ja'
                          ? const Icon(Icons.check, size: 18)
                          : const SizedBox(width: 18),
                      onPressed: () => onMenuAction(HomeMenuAction.japanese),
                      child: Text(l10n.japanese),
                    ),
                    MenuItemButton(
                      style: menuItemStyle,
                      leadingIcon: const Icon(Icons.translate, size: 18),
                      trailingIcon: Localizations.localeOf(context).languageCode == 'en'
                          ? const Icon(Icons.check, size: 18)
                          : const SizedBox(width: 18),
                      onPressed: () => onMenuAction(HomeMenuAction.english),
                      child: Text(l10n.english),
                    ),
                  ],
                  child: Text(l10n.language),
                ),
                const Divider(height: 9),
                MenuItemButton(
                  style: menuItemStyle,
                  leadingIcon: const Icon(Icons.system_update_alt, size: 18),
                  onPressed: () => onMenuAction(HomeMenuAction.checkForUpdates),
                  child: Text(l10n.checkForUpdates),
                ),
                MenuItemButton(
                  style: menuItemStyle,
                  leadingIcon: const Icon(Icons.info_outline, size: 18),
                  onPressed: () => onMenuAction(HomeMenuAction.about),
                  child: Text(l10n.about),
                ),
              ],
              builder: (context, controller, child) => IconButton(
                tooltip: l10n.settings,
                icon: const Icon(Icons.more_vert),
                onPressed: () {
                  // 同じボタンでメニューを開閉できるようにする
                  if (controller.isOpen) {
                    controller.close();
                  } else {
                    controller.open();
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

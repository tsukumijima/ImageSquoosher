/// 操作結果を色とアイコン、文章で伝える通知。
library;

import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';

/// 通知の意味に応じた表示種別です。
enum AppNoticeKind { info, success, error }

/// 新しい操作結果を優先して表示し、短い間隔の操作でも通知を読み取れるようにします。
void showAppSnackBar(BuildContext context, String message, {AppNoticeKind kind = AppNoticeKind.info}) {
  final color = switch (kind) {
    AppNoticeKind.info => const Color(0xff2196f3),
    AppNoticeKind.success => const Color(0xff4caf50),
    AppNoticeKind.error => const Color(0xffff5252),
  };
  final icon = switch (kind) {
    AppNoticeKind.info => Icons.info,
    AppNoticeKind.success => Icons.check_circle,
    AppNoticeKind.error => Icons.cancel,
  };
  // 通知は意味に対応する色で全面を塗り、本文と操作を白で揃える
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 5),
        backgroundColor: color,
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        padding: const EdgeInsets.only(left: 16, right: 8, top: 14, bottom: 14),
        content: Row(
          children: [
            Icon(icon, color: Colors.white, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Text(message, style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.25)),
            ),
            const SizedBox(width: 16),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              onPressed: () => ScaffoldMessenger.of(context).hideCurrentSnackBar(),
              child: Text(AppLocalizations.of(context).close),
            ),
          ],
        ),
      ),
    );
}

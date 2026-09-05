/// ImageSquoosher の Material 3 ダークテーマ。
library;

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

/// 操作のアクセント色と独立した、結果の意味を伝える色。
abstract final class AppColors {
  static const success = Color(0xff4caf50);
  static const error = Color(0xffff5252);
  static const info = Color(0xff2196f3);
}

/// OS のアクセント色と同梱 Noto Sans JP を使うテーマを作成する。
/// @param accentColor OS が提供するアクセント色
/// @returns アプリ全体で使うダークテーマ
ThemeData buildAppTheme(Color accentColor) {
  const fontFamily = 'Noto Sans JP';
  final colorScheme = ColorScheme.fromSeed(
    seedColor: accentColor,
    brightness: Brightness.dark,
    primary: accentColor,
    onPrimary: Colors.white,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    visualDensity: VisualDensity.compact,
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    fontFamily: fontFamily,
    colorScheme: colorScheme,
    cupertinoOverrideTheme: CupertinoThemeData(
      brightness: Brightness.dark,
      primaryColor: accentColor,
      primaryContrastingColor: Colors.white,
      textTheme: const CupertinoTextThemeData(
        textStyle: TextStyle(fontSize: 14, color: Colors.white, fontFamily: fontFamily),
        actionTextStyle: TextStyle(fontSize: 14, color: Colors.white, fontFamily: fontFamily),
      ),
    ),
    scaffoldBackgroundColor: colorScheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: colorScheme.surface,
      foregroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: Colors.white,
        fontFamily: fontFamily,
      ),
    ),
    cardTheme: CardThemeData(
      color: colorScheme.surfaceContainerHigh,
      elevation: 4,
      shadowColor: Colors.black.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: accentColor,
        foregroundColor: Colors.white,
        iconColor: Colors.white,
        // 主要操作の高さと押下時の波紋を、ヘッダーとフッターで共有する
        minimumSize: const Size(0, 37),
        visualDensity: VisualDensity.standard,
        splashFactory: InkRipple.splashFactory,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(
          fontSize: 14,
          // Noto Sans JP の字面をアイコンの中央へそろえ、ボタンの外寸は最小高さで維持する
          height: 1.25,
          fontWeight: FontWeight.w600,
          fontFamily: fontFamily,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: accentColor,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: const BorderSide(color: Colors.white54),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: accentColor,
      linearTrackColor: colorScheme.surfaceContainerHighest,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: colorScheme.surfaceContainerHigh,
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titleTextStyle: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: Colors.white,
        fontFamily: fontFamily,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: colorScheme.surfaceContainerHighest,
      contentTextStyle: const TextStyle(color: Colors.white, fontFamily: fontFamily),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      behavior: SnackBarBehavior.floating,
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      filled: true,
      fillColor: colorScheme.surfaceContainerHigh,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Colors.white24),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Colors.white12),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: accentColor, width: 2),
      ),
      labelStyle: const TextStyle(color: Colors.white70, fontFamily: fontFamily),
      hintStyle: const TextStyle(color: Colors.white38, fontFamily: fontFamily),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHigh,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      // 無効時の塗りとチェックマークは Material の既定色で描画する
      fillColor: WidgetStateProperty.resolveWith(
        (states) =>
            !states.contains(WidgetState.disabled) && states.contains(WidgetState.selected) ? accentColor : null,
      ),
      checkColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled) ? null : Colors.white,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
    ),
    listTileTheme: const ListTileThemeData(textColor: Colors.white, iconColor: Colors.white70),
    dividerTheme: const DividerThemeData(color: Colors.white12, thickness: 1),
    iconTheme: const IconThemeData(color: Colors.white70, size: 24),
    textTheme: const TextTheme(
      displayLarge: TextStyle(
        fontSize: 57,
        fontWeight: FontWeight.bold,
        color: Colors.white,
        height: 1.3,
        fontFamily: fontFamily,
      ),
      displayMedium: TextStyle(
        fontSize: 45,
        fontWeight: FontWeight.bold,
        color: Colors.white,
        height: 1.3,
        fontFamily: fontFamily,
      ),
      displaySmall: TextStyle(
        fontSize: 36,
        fontWeight: FontWeight.bold,
        color: Colors.white,
        height: 1.3,
        fontFamily: fontFamily,
      ),
      headlineLarge: TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.w600,
        color: Colors.white,
        height: 1.4,
        fontFamily: fontFamily,
      ),
      headlineMedium: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w600,
        color: Colors.white,
        height: 1.4,
        fontFamily: fontFamily,
      ),
      headlineSmall: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: Colors.white,
        height: 1.4,
        fontFamily: fontFamily,
      ),
      titleLarge: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w500,
        color: Colors.white,
        height: 1.4,
        fontFamily: fontFamily,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: Colors.white,
        height: 1.5,
        fontFamily: fontFamily,
      ),
      titleSmall: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: Colors.white,
        height: 1.5,
        fontFamily: fontFamily,
      ),
      bodyLarge: TextStyle(fontSize: 16, color: Colors.white, height: 1.6, fontFamily: fontFamily),
      bodyMedium: TextStyle(fontSize: 14, color: Colors.white, height: 1.6, fontFamily: fontFamily),
      bodySmall: TextStyle(fontSize: 12, color: Colors.white70, height: 1.6, fontFamily: fontFamily),
      labelLarge: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: Colors.white,
        height: 1.5,
        fontFamily: fontFamily,
      ),
      labelMedium: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: Colors.white,
        height: 1.5,
        fontFamily: fontFamily,
      ),
      labelSmall: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: Colors.white70,
        height: 1.5,
        fontFamily: fontFamily,
      ),
    ),
  );
}

/// α Import Utility と同じ階調で、ツール画面の奥行きを作る背景。
/// @param context 現在のテーマを取得する BuildContext
/// @returns テーマの表面色から作った背景装飾
BoxDecoration getGradientBackground(BuildContext context) {
  final colorScheme = Theme.of(context).colorScheme;
  return BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        colorScheme.surfaceContainer,
        colorScheme.surface,
        colorScheme.surface.withValues(alpha: 0.96),
      ],
    ),
  );
}

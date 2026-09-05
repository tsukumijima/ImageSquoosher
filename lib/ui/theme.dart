/// ImageSquoosher の Material 3 ダークテーマ。
library;

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

/// OS のアクセント色と α Import Utility のタイポグラフィを使うテーマを作成する。
ThemeData buildAppTheme(Color accentColor) {
  const fontFamilyFallback = <String>['Hiragino Sans', 'Noto Sans JP', 'Noto Sans CJK JP'];
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
    fontFamilyFallback: fontFamilyFallback,
    colorScheme: colorScheme,
    cupertinoOverrideTheme: CupertinoThemeData(
      brightness: Brightness.dark,
      primaryColor: accentColor,
      primaryContrastingColor: Colors.white,
      textTheme: const CupertinoTextThemeData(
        textStyle: TextStyle(fontSize: 14, color: Colors.white, fontFamilyFallback: fontFamilyFallback),
        actionTextStyle: TextStyle(fontSize: 14, color: Colors.white, fontFamilyFallback: fontFamilyFallback),
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
        fontFamilyFallback: fontFamilyFallback,
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontWeight: FontWeight.bold, fontFamilyFallback: fontFamilyFallback),
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
        fontFamilyFallback: fontFamilyFallback,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: colorScheme.surfaceContainerHighest,
      contentTextStyle: const TextStyle(color: Colors.white, fontFamilyFallback: fontFamilyFallback),
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
      labelStyle: const TextStyle(color: Colors.white70, fontFamilyFallback: fontFamilyFallback),
      hintStyle: const TextStyle(color: Colors.white38, fontFamilyFallback: fontFamilyFallback),
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
        fontFamilyFallback: fontFamilyFallback,
      ),
      displayMedium: TextStyle(
        fontSize: 45,
        fontWeight: FontWeight.bold,
        color: Colors.white,
        height: 1.3,
        fontFamilyFallback: fontFamilyFallback,
      ),
      displaySmall: TextStyle(
        fontSize: 36,
        fontWeight: FontWeight.bold,
        color: Colors.white,
        height: 1.3,
        fontFamilyFallback: fontFamilyFallback,
      ),
      headlineLarge: TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.w600,
        color: Colors.white,
        height: 1.4,
        fontFamilyFallback: fontFamilyFallback,
      ),
      headlineMedium: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w600,
        color: Colors.white,
        height: 1.4,
        fontFamilyFallback: fontFamilyFallback,
      ),
      headlineSmall: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: Colors.white,
        height: 1.4,
        fontFamilyFallback: fontFamilyFallback,
      ),
      titleLarge: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w500,
        color: Colors.white,
        height: 1.4,
        fontFamilyFallback: fontFamilyFallback,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: Colors.white,
        height: 1.5,
        fontFamilyFallback: fontFamilyFallback,
      ),
      titleSmall: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: Colors.white,
        height: 1.5,
        fontFamilyFallback: fontFamilyFallback,
      ),
      bodyLarge: TextStyle(fontSize: 16, color: Colors.white, height: 1.6, fontFamilyFallback: fontFamilyFallback),
      bodyMedium: TextStyle(fontSize: 14, color: Colors.white, height: 1.6, fontFamilyFallback: fontFamilyFallback),
      bodySmall: TextStyle(fontSize: 12, color: Colors.white70, height: 1.6, fontFamilyFallback: fontFamilyFallback),
      labelLarge: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: Colors.white,
        height: 1.5,
        fontFamilyFallback: fontFamilyFallback,
      ),
      labelMedium: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: Colors.white,
        height: 1.5,
        fontFamilyFallback: fontFamilyFallback,
      ),
      labelSmall: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: Colors.white70,
        height: 1.5,
        fontFamilyFallback: fontFamilyFallback,
      ),
    ),
  );
}

/// α Import Utility と同じ階調で、ツール画面の奥行きを作る背景です。
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

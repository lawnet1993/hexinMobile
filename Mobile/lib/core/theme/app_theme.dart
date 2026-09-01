import 'package:flutter/material.dart';

import 'app_colors.dart';

abstract final class AppTheme {
  static ThemeData get light => _light();
  static ThemeData get dark => _theme(Brightness.dark);

  static ThemeData lightWithFont(String fontFamily) =>
      _light(fontFamily: fontFamily);

  static ThemeData _light({String? fontFamily}) {
    return _theme(Brightness.light, fontFamily: fontFamily);
  }

  static ThemeData _theme(Brightness brightness, {String? fontFamily}) {
    final dark = brightness == Brightness.dark;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: brightness,
          surface: dark ? const Color(0xFF1C222B) : AppColors.surface,
          error: AppColors.error,
        ).copyWith(
          primary: dark ? const Color(0xFF79A8FF) : AppColors.primary,
          surface: dark ? const Color(0xFF1C222B) : AppColors.surface,
          outlineVariant: dark ? const Color(0xFF343C48) : AppColors.border,
        );
    final textColor = dark ? const Color(0xFFF2F4F7) : AppColors.text;
    final secondaryText = dark
        ? const Color(0xFFADB7C6)
        : AppColors.secondaryText;
    return ThemeData(
      useMaterial3: true,
      fontFamily: fontFamily,
      colorScheme: scheme,
      scaffoldBackgroundColor: dark
          ? const Color(0xFF11161D)
          : AppColors.background,
      fontFamilyFallback: const [
        'PingFang SC',
        'Microsoft YaHei',
        'sans-serif',
      ],
      textTheme: TextTheme(
        headlineSmall: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: textColor,
        ),
        titleLarge: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: textColor,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
        bodyLarge: TextStyle(fontSize: 16, color: textColor),
        bodyMedium: TextStyle(fontSize: 14, color: textColor),
        bodySmall: TextStyle(fontSize: 12, color: secondaryText),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: textColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        toolbarHeight: 44,
        titleSpacing: 12,
        actionsPadding: const EdgeInsets.only(right: 4),
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: textColor,
          fontFamily: fontFamily,
        ),
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surface,
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        prefixIconConstraints: BoxConstraints(minWidth: 36, minHeight: 36),
        suffixIconConstraints: BoxConstraints(minWidth: 36, minHeight: 36),
        labelStyle: TextStyle(fontSize: 12.5),
        hintStyle: TextStyle(fontSize: 13.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(6)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(6)),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(6)),
          borderSide: BorderSide(color: AppColors.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(6)),
          borderSide: BorderSide(color: AppColors.error),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(36, 36),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
          textStyle: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            fontFamily: fontFamily,
            fontFamilyFallback: const [
              'PingFang SC',
              'Microsoft YaHei',
              'sans-serif',
            ],
          ),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(32, 32),
          maximumSize: const Size(36, 36),
          padding: const EdgeInsets.all(6),
          iconSize: 19,
          visualDensity: VisualDensity.compact,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(36, 34),
          padding: const EdgeInsets.symmetric(horizontal: 13),
          textStyle: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w500,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(36, 36),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          textStyle: const TextStyle(fontSize: 13),
          visualDensity: VisualDensity.compact,
        ),
      ),
      listTileTheme: ListTileThemeData(
        dense: true,
        minVerticalPadding: 4,
        minLeadingWidth: 32,
        horizontalTitleGap: 10,
        contentPadding: EdgeInsets.symmetric(horizontal: 12),
        iconColor: AppColors.primary,
        titleTextStyle: TextStyle(fontSize: 14, color: textColor),
        subtitleTextStyle: TextStyle(fontSize: 11.5, color: secondaryText),
      ),
      switchTheme: const SwitchThemeData(
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        trackOutlineColor: WidgetStatePropertyAll(Colors.transparent),
      ),
      checkboxTheme: const CheckboxThemeData(
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 52,
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: Colors.transparent,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? scheme.primary : secondaryText,
            size: 20,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? scheme.primary : secondaryText,
          );
        }),
        overlayColor: WidgetStatePropertyAll(
          AppColors.primary.withValues(alpha: 0.08),
        ),
      ),
      splashFactory: InkSparkle.splashFactory,
    );
  }
}

import 'package:flutter/material.dart';

class AppTheme {
  const AppTheme._();

  static const _navy = Color(0xFF14263F);
  static const _teal = Color(0xFF176B68);
  static const _mint = Color(0xFF75D6BF);
  static const _lightBackground = Color(0xFFF4F7FA);
  static const _darkBackground = Color(0xFF101923);

  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: _teal,
      brightness: brightness,
    ).copyWith(
      primary: isDark ? _mint : _teal,
      onPrimary: isDark ? const Color(0xFF082A2B) : Colors.white,
      primaryContainer:
          isDark ? const Color(0xFF1D4142) : const Color(0xFFD9EFEB),
      onPrimaryContainer:
          isDark ? const Color(0xFFE0FFF6) : const Color(0xFF123C3B),
      secondary: isDark ? const Color(0xFF9FC8D9) : const Color(0xFF315B73),
      onSecondary: isDark ? const Color(0xFF10232C) : Colors.white,
      secondaryContainer:
          isDark ? const Color(0xFF263C49) : const Color(0xFFE4EDF2),
      onSecondaryContainer:
          isDark ? const Color(0xFFE2F3FA) : const Color(0xFF1C3544),
      tertiary: isDark ? const Color(0xFFF4C66F) : const Color(0xFF895800),
      onTertiary: isDark ? const Color(0xFF332100) : Colors.white,
      surface: isDark ? const Color(0xFF151F2B) : Colors.white,
      onSurface: isDark ? const Color(0xFFE8EEF4) : const Color(0xFF172536),
      surfaceContainerLowest:
          isDark ? const Color(0xFF101923) : _lightBackground,
      surfaceContainerLow:
          isDark ? const Color(0xFF1A2633) : const Color(0xFFF9FBFD),
      surfaceContainerHighest:
          isDark ? const Color(0xFF2A3948) : const Color(0xFFE9EFF4),
      onSurfaceVariant:
          isDark ? const Color(0xFFC0CCD6) : const Color(0xFF4B5C6B),
      outline: isDark ? const Color(0xFF8493A0) : const Color(0xFF657685),
      outlineVariant:
          isDark ? const Color(0xFF3A4A58) : const Color(0xFFD5DEE5),
      error: isDark ? const Color(0xFFFFB4AB) : const Color(0xFFB3261E),
      onError: isDark ? const Color(0xFF690005) : Colors.white,
      errorContainer:
          isDark ? const Color(0xFF5A1A18) : const Color(0xFFFFE5E1),
      onErrorContainer:
          isDark ? const Color(0xFFFFDAD4) : const Color(0xFF5F1712),
    );
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: scheme.outlineVariant),
    );

    return ThemeData(
      colorScheme: scheme,
      brightness: brightness,
      useMaterial3: true,
      scaffoldBackgroundColor: isDark ? _darkBackground : _lightBackground,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: isDark ? _darkBackground : _lightBackground,
        foregroundColor: scheme.onSurface,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: scheme.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.7)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        errorBorder: border.copyWith(
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: border.copyWith(
          borderSide: BorderSide(color: scheme.error, width: 2),
        ),
        labelStyle: TextStyle(color: scheme.onSurfaceVariant),
        hintStyle:
            TextStyle(color: scheme.onSurfaceVariant.withValues(alpha: 0.8)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(50),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          side: BorderSide(color: scheme.outlineVariant),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(44, 44),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 24,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      visualDensity: VisualDensity.standard,
    );
  }

  static const Color brandNavy = _navy;
  static const Color brandTeal = _teal;
}

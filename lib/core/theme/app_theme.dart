import 'package:flutter/material.dart';

/// Design tokens sourced directly from design.md (Stitch export).
/// Do not add/alter colors or spacing here — if a token is missing,
/// add it to design.md first (rules.md Rule 1).
class AppColors {
  AppColors._();

  static const surface = Color(0xFF141310);
  static const surfaceDim = Color(0xFF141310);
  static const surfaceBright = Color(0xFF3B3935);
  static const surfaceContainerLowest = Color(0xFF0F0E0B);
  static const surfaceContainerLow = Color(0xFF1D1B18);
  static const surfaceContainer = Color(0xFF211F1C);
  static const surfaceContainerHigh = Color(0xFF2B2A26);
  static const surfaceContainerHighest = Color(0xFF363531);
  static const cream = Color(0xFFFBF6F0);

  static const onSurface = Color(0xFFE6E2DC);
  static const onSurfaceVariant = Color(0xFFBFC9C4);
  static const inverseSurface = Color(0xFFE6E2DC);
  static const inverseOnSurface = Color(0xFF32302C);

  static const outline = Color(0xFF89938E);
  static const outlineVariant = Color(0xFF404945);

  static const primary = Color(0xFF98D2BF);
  static const onPrimary = Color(0xFF00382C);
  static const primaryContainer = Color(0xFF276152);
  static const onPrimaryContainer = Color(0xFF9FDAC7);
  static const inversePrimary = Color(0xFF2F6859);

  static const secondary = Color(0xFFC2C8BC);
  static const onSecondary = Color(0xFF2C3229);
  static const secondaryContainer = Color(0xFF43493F);
  static const onSecondaryContainer = Color(0xFFB1B7AB);

  static const tertiary = Color(0xFFA4CFC8);
  static const onTertiary = Color(0xFF083732);
  static const tertiaryContainer = Color(0xFF365F59);
  static const onTertiaryContainer = Color(0xFFABD7CF);

  static const error = Color(0xFFE24B4A);
  static const onError = Color(0xFF690005);
  static const errorContainer = Color(0xFF93000A);
  static const onErrorContainer = Color(0xFFFFDAD6);

  static const background = Color(0xFF141310);
  static const onBackground = Color(0xFFE6E2DC);
  static const surfaceVariant = Color(0xFF363531);

  // From "Surface Tiers" section — these are the actual chat-screen
  // background/raised tokens used for bubbles/cards/search bars.
  static const surfaceRaised = Color(0xFF154B44);
  static const backgroundBase = Color(0xFF0D3A35);
}

class AppRadius {
  AppRadius._();
  static const sm = 4.0; // 0.25rem
  static const md = 8.0; // DEFAULT 0.5rem
  static const lg = 12.0; // 0.75rem
  static const xl = 16.0; // 1rem
  static const xxl = 24.0; // 1.5rem
  static const full = 9999.0;

  // Component-specific, from design.md "Shapes"
  static const messageBubble = 14.0;
  static const messageBubbleTail = 4.0;
  static const buttonInput = 16.0; // rounded-lg standard
}

class AppSpacing {
  AppSpacing._();
  static const pageMargin = 20.0; // 1.25rem
  static const gutterBubble = 8.0; // 0.5rem
  static const paddingBubbleX = 16.0; // 1rem
  static const paddingBubbleY = 12.0; // 0.75rem
  static const stackCompact = 4.0; // 0.25rem
  static const stackDefault = 16.0; // 1rem

  // From "Layout & Spacing" — messaging rhythm
  static const bubbleSameSender = 4.0;
  static const bubbleDifferentSender = 12.0;
}

class AppTheme {
  AppTheme._();

  static ThemeData get dark {
    final colorScheme = ColorScheme.dark(
      surface: AppColors.surface,
      onSurface: AppColors.onSurface,
      onSurfaceVariant: AppColors.onSurfaceVariant,
      primary: AppColors.primary,
      onPrimary: AppColors.onPrimary,
      primaryContainer: AppColors.primaryContainer,
      onPrimaryContainer: AppColors.onPrimaryContainer,
      secondary: AppColors.secondary,
      onSecondary: AppColors.onSecondary,
      secondaryContainer: AppColors.secondaryContainer,
      onSecondaryContainer: AppColors.onSecondaryContainer,
      tertiary: AppColors.tertiary,
      onTertiary: AppColors.onTertiary,
      tertiaryContainer: AppColors.tertiaryContainer,
      onTertiaryContainer: AppColors.onTertiaryContainer,
      error: AppColors.error,
      onError: AppColors.onError,
      errorContainer: AppColors.errorContainer,
      onErrorContainer: AppColors.onErrorContainer,
      outline: AppColors.outline,
      outlineVariant: AppColors.outlineVariant,
      inverseSurface: AppColors.inverseSurface,
      onInverseSurface: AppColors.inverseOnSurface,
      inversePrimary: AppColors.inversePrimary,
      surfaceContainerLowest: AppColors.surfaceContainerLowest,
      surfaceContainerLow: AppColors.surfaceContainerLow,
      surfaceContainer: AppColors.surfaceContainer,
      surfaceContainerHigh: AppColors.surfaceContainerHigh,
      surfaceContainerHighest: AppColors.surfaceContainerHighest,
    );

    // design.md: "Sentence Case Only", weights restricted to 400/500 only.
    const fontFamily = 'Inter';

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.backgroundBase,
      fontFamily: fontFamily,
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w500,
          height: 32 / 24,
          color: AppColors.onSurface,
        ),
        headlineMedium: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w500,
          height: 28 / 20,
          color: AppColors.onSurface,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          height: 24 / 16,
          color: AppColors.onSurface,
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          height: 24 / 16,
          color: AppColors.onSurface,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          height: 20 / 14,
          color: AppColors.onSurfaceVariant,
        ),
        labelMedium: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          height: 16 / 12,
          color: AppColors.onSurfaceVariant,
        ),
        labelSmall: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w400,
          height: 14 / 11,
          letterSpacing: 0.02 * 11,
          color: AppColors.onSurfaceVariant,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.backgroundBase,
        foregroundColor: AppColors.onSurface,
        elevation: 0,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryContainer,
          foregroundColor: AppColors.cream, // Cream per design.md Buttons
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.buttonInput),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w500),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFFFBF6F0),
          side: const BorderSide(color: AppColors.outline, width: 1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.buttonInput),
          ),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.outlineVariant,
        thickness: 1,
        space: 1,
      ),
    );
  }
}

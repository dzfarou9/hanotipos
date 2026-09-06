import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_text_styles.dart';
import 'design_tokens.dart';

class AppTheme {
  AppTheme._();

  /// Builds the shared text theme from [AppTextStyles] (bundled Tajawal),
  /// tinting every role for the given text color set.
  static TextTheme _textTheme({
    required Color primary,
    required Color secondary,
    required Color tertiary,
  }) =>
      TextTheme(
        displayLarge: AppTextStyles.headline1(color: primary),
        displayMedium: AppTextStyles.headline2(color: primary),
        displaySmall: AppTextStyles.headline3(color: primary),
        headlineMedium: AppTextStyles.headline4(color: primary),
        headlineSmall: AppTextStyles.titleLarge(color: primary),
        titleLarge: AppTextStyles.titleLarge(color: primary),
        titleMedium: AppTextStyles.titleMedium(color: primary),
        bodyLarge: AppTextStyles.bodyLarge(color: primary),
        bodyMedium: AppTextStyles.bodyMedium(color: secondary),
        bodySmall: AppTextStyles.bodySmall(color: tertiary),
        labelLarge: AppTextStyles.labelLarge(color: primary),
        labelMedium: AppTextStyles.labelMedium(color: secondary),
        labelSmall: AppTextStyles.caption(color: tertiary),
      );

  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    fontFamily: AppTextStyles.fontFamily,

    colorScheme: const ColorScheme.light(
      primary: AppColors.primary,
      onPrimary: AppColors.white,
      primaryContainer: AppColors.primaryVeryLight,
      onPrimaryContainer: Color(0xFF1B5E20),
      secondary: AppColors.secondary,
      onSecondary: AppColors.white,
      secondaryContainer: AppColors.secondaryVeryLight,
      tertiary: AppColors.warning,
      error: AppColors.error,
      surface: AppColors.lightSurface,
      onSurface: AppColors.textLightPrimary,
      outline: AppColors.grey300,
    ),

    scaffoldBackgroundColor: AppColors.lightBackground,

    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.lightSurface,
      foregroundColor: AppColors.textLightPrimary,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: AppTextStyles.headline4(color: AppColors.textLightPrimary),
      surfaceTintColor: Colors.transparent,
      iconTheme: const IconThemeData(color: AppColors.textLightPrimary),
    ),

    cardTheme: CardThemeData(
      color: AppColors.lightSurface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
        side: BorderSide(color: AppColors.grey200.withValues(alpha: 0.8)),
      ),
      margin: EdgeInsets.zero,
    ),

    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: AppColors.lightSurface,
      selectedItemColor: AppColors.primary,
      unselectedItemColor: AppColors.textLightTertiary,
      type: BottomNavigationBarType.fixed,
      elevation: 0,
      selectedLabelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
      unselectedLabelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w400),
    ),

    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DesignTokens.radiusSm)),
        textStyle: AppTextStyles.buttonText(),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        side: const BorderSide(color: AppColors.primary),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DesignTokens.radiusSm)),
        textStyle: AppTextStyles.buttonText(color: AppColors.primary),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        textStyle: AppTextStyles.buttonText(color: AppColors.primary),
      ),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.lightSurfaceAlt,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        borderSide: const BorderSide(color: AppColors.error, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        borderSide: const BorderSide(color: AppColors.error, width: 1.5),
      ),
      hintStyle: AppTextStyles.bodyMedium(color: AppColors.textLightTertiary),
      labelStyle: AppTextStyles.bodyMedium(color: AppColors.textLightSecondary),
      prefixIconColor: AppColors.textLightSecondary,
      suffixIconColor: AppColors.textLightTertiary,
    ),

    dividerTheme: const DividerThemeData(color: AppColors.grey200, thickness: 1, space: 1),

    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.lightSurface,
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DesignTokens.radiusLg)),
      titleTextStyle: AppTextStyles.headline4(color: AppColors.textLightPrimary),
      contentTextStyle: AppTextStyles.bodyMedium(color: AppColors.textLightSecondary),
    ),

    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.textLightPrimary,
      contentTextStyle: AppTextStyles.bodyMedium(color: AppColors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DesignTokens.radiusSm)),
      behavior: SnackBarBehavior.floating,
      elevation: 4,
    ),

    chipTheme: ChipThemeData(
      backgroundColor: AppColors.lightSurfaceAlt,
      selectedColor: AppColors.primaryVeryLight,
      labelStyle: AppTextStyles.labelMedium(color: AppColors.textLightSecondary),
      secondaryLabelStyle: AppTextStyles.labelMedium(color: AppColors.primary),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DesignTokens.radiusXs)),
    ),

    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith<Color>((states) {
        if (states.contains(WidgetState.selected)) return AppColors.primary;
        return AppColors.grey300;
      }),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),

    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith<Color>((states) {
        if (states.contains(WidgetState.selected)) return AppColors.primary;
        return AppColors.grey300;
      }),
      trackColor: WidgetStateProperty.resolveWith<Color>((states) {
        if (states.contains(WidgetState.selected)) return AppColors.primaryVeryLight;
        return AppColors.grey200;
      }),
    ),

    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.primary,
      circularTrackColor: AppColors.grey200,
    ),

    tabBarTheme: TabBarThemeData(
      labelColor: AppColors.primary,
      unselectedLabelColor: AppColors.textLightTertiary,
      indicatorColor: AppColors.primary,
      labelStyle: AppTextStyles.labelLarge(color: AppColors.primary),
      unselectedLabelStyle: AppTextStyles.bodyMedium(color: AppColors.textLightTertiary),
    ),

    textTheme: _textTheme(
      primary: AppColors.textLightPrimary,
      secondary: AppColors.textLightSecondary,
      tertiary: AppColors.textLightTertiary,
    ),
  );

  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: AppTextStyles.fontFamily,

    colorScheme: const ColorScheme.dark(
      primary: AppColors.neonOrange,
      onPrimary: Color(0xFF0A1F10),
      primaryContainer: AppColors.neonOrangeVeryLight,
      onPrimaryContainer: AppColors.neonOrangeLight,
      secondary: AppColors.secondaryLight,
      onSecondary: AppColors.black,
      secondaryContainer: Color(0xFF12312D),
      tertiary: AppColors.warning,
      error: AppColors.errorOnDark,
      surface: AppColors.darkSurface,
      onSurface: AppColors.textDarkPrimary,
      outline: AppColors.grey600,
    ),

    scaffoldBackgroundColor: AppColors.darkBackground,

    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.darkSurface,
      foregroundColor: AppColors.textDarkPrimary,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: AppTextStyles.headline4(color: AppColors.textDarkPrimary),
      surfaceTintColor: Colors.transparent,
      iconTheme: const IconThemeData(color: AppColors.textDarkPrimary),
    ),

    cardTheme: CardThemeData(
      color: AppColors.darkSurface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
        side: BorderSide(color: AppColors.grey700.withValues(alpha: 0.5)),
      ),
      margin: EdgeInsets.zero,
    ),

    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: AppColors.darkSurface,
      selectedItemColor: AppColors.neonOrange,
      unselectedItemColor: AppColors.textDarkTertiary,
      type: BottomNavigationBarType.fixed,
      elevation: 0,
      selectedLabelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
      unselectedLabelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w400),
    ),

    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.neonOrange,
        foregroundColor: const Color(0xFF0A1F10),
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DesignTokens.radiusSm)),
        textStyle: AppTextStyles.buttonText(color: const Color(0xFF0A1F10)),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.neonOrange,
        side: const BorderSide(color: AppColors.neonOrange),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DesignTokens.radiusSm)),
        textStyle: AppTextStyles.buttonText(color: AppColors.neonOrange),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.neonOrange,
        textStyle: AppTextStyles.buttonText(color: AppColors.neonOrange),
      ),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.darkSurfaceAlt,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        borderSide: const BorderSide(color: AppColors.neonOrange, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        borderSide: const BorderSide(color: AppColors.errorOnDark, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        borderSide: const BorderSide(color: AppColors.errorOnDark, width: 1.5),
      ),
      hintStyle: AppTextStyles.bodyMedium(color: AppColors.textDarkTertiary),
      labelStyle: AppTextStyles.bodyMedium(color: AppColors.textDarkSecondary),
      prefixIconColor: AppColors.textDarkSecondary,
      suffixIconColor: AppColors.textDarkTertiary,
    ),

    dividerTheme: DividerThemeData(color: AppColors.grey700.withValues(alpha: 0.35), thickness: 1, space: 1),

    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.darkSurface,
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DesignTokens.radiusLg)),
      titleTextStyle: AppTextStyles.headline4(color: AppColors.textDarkPrimary),
      contentTextStyle: AppTextStyles.bodyMedium(color: AppColors.textDarkSecondary),
    ),

    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.darkSurfaceAlt,
      contentTextStyle: AppTextStyles.bodyMedium(color: AppColors.textDarkPrimary),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DesignTokens.radiusSm)),
      behavior: SnackBarBehavior.floating,
      elevation: 4,
    ),

    chipTheme: ChipThemeData(
      backgroundColor: AppColors.darkSurfaceAlt,
      selectedColor: AppColors.neonOrangeVeryLight,
      labelStyle: AppTextStyles.labelMedium(color: AppColors.textDarkSecondary),
      secondaryLabelStyle: AppTextStyles.labelMedium(color: AppColors.neonOrange),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DesignTokens.radiusXs)),
    ),

    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith<Color>((states) {
        if (states.contains(WidgetState.selected)) return AppColors.neonOrange;
        return AppColors.grey600;
      }),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),

    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith<Color>((states) {
        if (states.contains(WidgetState.selected)) return AppColors.neonOrange;
        return AppColors.grey500;
      }),
      trackColor: WidgetStateProperty.resolveWith<Color>((states) {
        if (states.contains(WidgetState.selected)) return AppColors.neonOrangeVeryLight;
        return AppColors.grey700;
      }),
    ),

    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.neonOrange,
      circularTrackColor: AppColors.grey700,
    ),

    tabBarTheme: TabBarThemeData(
      labelColor: AppColors.neonOrange,
      unselectedLabelColor: AppColors.textDarkTertiary,
      indicatorColor: AppColors.neonOrange,
      labelStyle: AppTextStyles.labelLarge(color: AppColors.neonOrange),
      unselectedLabelStyle: AppTextStyles.bodyMedium(color: AppColors.textDarkTertiary),
    ),

    textTheme: _textTheme(
      primary: AppColors.textDarkPrimary,
      secondary: AppColors.textDarkSecondary,
      tertiary: AppColors.textDarkTertiary,
    ),
  );
}
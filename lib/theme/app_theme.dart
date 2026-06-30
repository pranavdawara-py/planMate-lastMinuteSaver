import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

class AppTheme {
  static ThemeData get lightTheme {
    final base = ThemeData.light(useMaterial3: false);

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.bgPrimary,
      primaryColor: AppColors.accentPrimary,
      dividerColor: AppColors.border,
      cardColor: AppColors.bgSecondary,

      colorScheme: const ColorScheme.light(
        primary: AppColors.accentPrimary,
        secondary: AppColors.accentSecondary,
        surface: AppColors.bgSecondary,
        error: AppColors.danger,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: AppColors.textPrimary,
        onError: Colors.white,
      ),

      textTheme: GoogleFonts.interTextTheme(base.textTheme).copyWith(
        displayLarge: GoogleFonts.inter(
          fontWeight: FontWeight.w800,
          fontSize: 28,
          color: AppColors.textPrimary,
          letterSpacing: -0.5,
        ),
        displayMedium: GoogleFonts.inter(
          fontWeight: FontWeight.w700,
          fontSize: 24,
          color: AppColors.textPrimary,
          letterSpacing: -0.3,
        ),
        headlineLarge: GoogleFonts.inter(
          fontWeight: FontWeight.w700,
          fontSize: 20,
          color: AppColors.textPrimary,
        ),
        headlineMedium: GoogleFonts.inter(
          fontWeight: FontWeight.w600,
          fontSize: 17,
          color: AppColors.textPrimary,
        ),
        titleLarge: GoogleFonts.inter(
          fontWeight: FontWeight.w600,
          fontSize: 15,
          color: AppColors.textPrimary,
        ),
        titleMedium: GoogleFonts.inter(
          fontWeight: FontWeight.w500,
          fontSize: 13,
          color: AppColors.textPrimary,
        ),
        bodyLarge: GoogleFonts.inter(
          fontWeight: FontWeight.w400,
          fontSize: 14,
          color: AppColors.textPrimary,
          height: 1.5,
        ),
        bodyMedium: GoogleFonts.inter(
          fontWeight: FontWeight.w400,
          fontSize: 12,
          color: AppColors.textSecondary,
          height: 1.4,
        ),
        labelLarge: GoogleFonts.inter(
          fontWeight: FontWeight.w600,
          fontSize: 13,
          color: AppColors.textPrimary,
        ),
        labelSmall: GoogleFonts.inter(
          fontWeight: FontWeight.w500,
          fontSize: 10,
          color: AppColors.textSecondary,
          letterSpacing: 0.5,
        ),
      ),

      // App bar
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.bgPrimary,
        elevation: 0,
        scrolledUnderElevation: 1,
        shadowColor: AppColors.border,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: GoogleFonts.inter(
          fontWeight: FontWeight.w700,
          fontSize: 18,
          color: AppColors.textPrimary,
        ),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),

      // Tab bar — pill indicator
      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.accentPrimary,
        unselectedLabelColor: AppColors.textSecondary,
        indicator: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: AppColors.accentSoft,
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        labelStyle: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600),
        unselectedLabelStyle:
            GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w400),
      ),

      // Elevated button
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accentPrimary,
          foregroundColor: Colors.white,
          elevation: 0,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle:
              GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
          padding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),

      // Text button
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.accentPrimary,
          textStyle:
              GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500),
        ),
      ),

      // Outlined button
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.accentPrimary,
          side: const BorderSide(color: AppColors.accentPrimary),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle:
              GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),

      // Input decoration
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.bgChip,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide:
              const BorderSide(color: AppColors.accentPrimary, width: 1.5),
        ),
        hintStyle: GoogleFonts.inter(
            fontSize: 13, color: AppColors.textMuted),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),

      // Card
      cardTheme: CardThemeData(
        color: AppColors.bgSecondary,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),

      // Divider
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),

      // Floating action button
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.accentPrimary,
        foregroundColor: Colors.white,
        elevation: 6,
        shape: CircleBorder(),
      ),

      // Switch
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.white;
          return AppColors.textMuted;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.accentPrimary;
          }
          return AppColors.border;
        }),
      ),

      // Snack bar
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.textPrimary,
        contentTextStyle: GoogleFonts.inter(
            fontSize: 13, color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        behavior: SnackBarBehavior.floating,
      ),

      // Progress indicator
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.accentPrimary,
      ),

      // Bottom sheet
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.bgSecondary,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),

      // Date picker - light theme
      datePickerTheme: DatePickerThemeData(
        backgroundColor: AppColors.bgSecondary,
        headerBackgroundColor: AppColors.accentPrimary,
        headerForegroundColor: Colors.white,
        dayForegroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.white;
          return AppColors.textPrimary;
        }),
        dayBackgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.accentPrimary;
          return Colors.transparent;
        }),
        todayForegroundColor: WidgetStateProperty.all(AppColors.accentPrimary),
        todayBorder: const BorderSide(color: AppColors.accentPrimary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  // Keep old name as alias for backward compatibility
  static ThemeData get darkTheme => lightTheme;
}

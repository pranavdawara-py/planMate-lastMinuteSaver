import 'package:flutter/material.dart';

class AppColors {
  // ── Backgrounds ──────────────────────────────────────────────────────────
  static const Color bgPrimary    = Color(0xFFFAFAF7); // warm off-white
  static const Color bgSecondary  = Color(0xFFFFFFFF); // card surface
  static const Color bgElevated   = Color(0xFFF4F2FF); // light violet tint for sheets
  static const Color bgMuted      = Color(0xFFF4F2FF);
  static const Color bgChip       = Color(0xFFF0F0F5); // unselected chip background
  static const Color bgGlass      = Color(0x80FFFFFF); // glassmorphism overlay

  // ── Accent Gradient Identity ──────────────────────────────────────────────
  static const Color accentPrimary   = Color(0xFF7C3AED); // rich violet
  static const Color accentSecondary = Color(0xFFF97316); // coral
  static const Color accentCoral     = Color(0xFFF97316);
  static const Color accentGlow      = Color(0x267C3AED); // 15% violet glow
  static const Color accentSoft      = Color(0xFFEDE9FE); // light violet fill

  // ── Semantic ─────────────────────────────────────────────────────────────
  static const Color success  = Color(0xFF10B981);
  static const Color warning  = Color(0xFFF59E0B);
  static const Color danger   = Color(0xFFEF4444);
  static const Color info     = Color(0xFF3B82F6);

  // ── Text ─────────────────────────────────────────────────────────────────
  static const Color textPrimary   = Color(0xFF1C1C2E);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textMuted     = Color(0xFF9CA3AF);

  // ── Borders ──────────────────────────────────────────────────────────────
  static const Color border       = Color(0xFFE5E7EB);
  static const Color borderSubtle = Color(0xFFF3F4F6);
  static const Color borderAccent = Color(0xFFDDD6FE);

  // ── Gradients ────────────────────────────────────────────────────────────
  static const LinearGradient accentGradient = LinearGradient(
    colors: [Color(0xFF7C3AED), Color(0xFFF97316)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const LinearGradient accentGradientVertical = LinearGradient(
    colors: [Color(0xFF7C3AED), Color(0xFFF97316)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient bgGradient = LinearGradient(
    colors: [Color(0xFFFAFAF7), Color(0xFFF4F2FF)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  // ── Shadows ──────────────────────────────────────────────────────────────
  static List<BoxShadow> get cardShadow => [
    BoxShadow(
      color: const Color(0xFF1C1C2E).withValues(alpha: 0.06),
      blurRadius: 12,
      spreadRadius: 0,
      offset: const Offset(0, 3),
    ),
    BoxShadow(
      color: const Color(0xFF1C1C2E).withValues(alpha: 0.03),
      blurRadius: 4,
      spreadRadius: 0,
      offset: const Offset(0, 1),
    ),
  ];

  static List<BoxShadow> get elevatedShadow => [
    BoxShadow(
      color: const Color(0xFF1C1C2E).withValues(alpha: 0.12),
      blurRadius: 24,
      spreadRadius: 0,
      offset: const Offset(0, 8),
    ),
  ];

  static List<BoxShadow> get accentShadow => [
    BoxShadow(
      color: accentPrimary.withValues(alpha: 0.28),
      blurRadius: 16,
      spreadRadius: -2,
      offset: const Offset(0, 6),
    ),
  ];

  static List<BoxShadow> get subtleShadow => [
    BoxShadow(
      color: const Color(0xFF1C1C2E).withValues(alpha: 0.04),
      blurRadius: 6,
      offset: const Offset(0, 2),
    ),
  ];

  // ── Category Color Helpers ────────────────────────────────────────────────
  static Color categoryColor(String? category) {
    switch (category?.toLowerCase()) {
      case 'work':     return info;
      case 'college':  return accentPrimary;
      case 'personal': return const Color(0xFFEC4899);
      case 'health':   return success;
      default:         return warning;
    }
  }

  static Color categoryBg(String? category) {
    switch (category?.toLowerCase()) {
      case 'work':     return const Color(0xFFDBEAFE);
      case 'college':  return accentSoft;
      case 'personal': return const Color(0xFFFCE7F3);
      case 'health':   return const Color(0xFFD1FAE5);
      default:         return const Color(0xFFFEF3C7);
    }
  }
}

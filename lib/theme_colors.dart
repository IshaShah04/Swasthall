// theme_colors.dart
// Centralized theme-aware color helper for Swasthall dark mode.
// Import this in every screen: import 'theme_colors.dart';
// Usage: AppColors.cardBg(context) instead of Colors.white

import 'package:flutter/material.dart';

class AppColors {
  // ── Brand colors (same in both modes) ──────────────────────────────────
  static const Color brandIndigo   = Color(0xFF6366F1);
  static const Color brandGreen    = Color(0xFF10B981);
  static const Color brandRed      = Color(0xFFEF4444);
  static const Color brandAmber    = Color(0xFFF59E0B);
  static const Color brandOrange   = Color(0xFFF97316);

  // ── Backgrounds ──────────────────────────────────────────────────────────
  static Color scaffoldBg(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF0F172A)   // dark navy
          : const Color(0xFFF8FAFC);  // light grey

  static Color cardBg(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF1E293B)   // dark card
          : Colors.white;

  static Color surfaceBg(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF1E293B)
          : const Color(0xFFF1F5F9);

  static Color inputFill(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF1E293B)
          : Colors.white;

  static Color dividerColor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF334155)
          : const Color(0xFFE2E8F0);

  // ── Text colors ──────────────────────────────────────────────────────────
  static Color textPrimary(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? Colors.white
          : const Color(0xFF1E293B);

  static Color textSecondary(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF94A3B8)
          : const Color(0xFF64748B);

  static Color textMuted(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF64748B)
          : Colors.grey;

  static Color textOnBrand(BuildContext context) => Colors.white;

  // ── Border colors ─────────────────────────────────────────────────────────
  static Color border(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF334155)
          : const Color(0xFFE2E8F0);

  static Color borderLight(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF1E293B)
          : const Color(0xFFF1F5F9);

  // ── Overlay / tint ────────────────────────────────────────────────────────
  static Color indigoTint(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF1E1B4B)
          : const Color(0xFFEEF2FF);

  static Color greenTint(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF064E3B)
          : const Color(0xFFECFDF5);

  static Color redTint(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF7F1D1D)
          : const Color(0xFFFEF2F2);

  static Color amberTint(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF78350F)
          : const Color(0xFFFFFBEB);

  // ── Icon colors ───────────────────────────────────────────────────────────
  static Color iconMuted(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF64748B)
          : Colors.grey;

  // ── Shadow ────────────────────────────────────────────────────────────────
  static Color shadow(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? Colors.black.withValues(alpha: 0.3)
          : Colors.black.withValues(alpha: 0.06);

  // ── Bottom nav ────────────────────────────────────────────────────────────
  static Color navBg(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF1E293B)
          : Colors.white;
}

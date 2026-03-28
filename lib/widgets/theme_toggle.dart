import 'package:flutter/material.dart';
import '../theme_notifier.dart';
import '../theme_colors.dart';

/// 3-way appearance toggle: Light / System / Dark.
/// Drop this anywhere — it reads and writes [themeNotifier] directly.
class AppearanceToggle extends StatelessWidget {
  const AppearanceToggle({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, current, _) {
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.cardBg(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border(context)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.brightness_6_outlined,
                      color: const Color(0xFF6366F1), size: 20),
                  const SizedBox(width: 10),
                  Text(
                    'Appearance',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary(context),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceBg(context),
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.all(4),
                child: Row(
                  children: [
                    _segment(context, ThemeMode.light, Icons.wb_sunny_outlined,
                        'Light', current),
                    _segment(context, ThemeMode.system,
                        Icons.brightness_auto_outlined, 'System', current),
                    _segment(context, ThemeMode.dark,
                        Icons.nights_stay_outlined, 'Dark', current),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _segment(
    BuildContext context,
    ThemeMode mode,
    IconData icon,
    String label,
    ThemeMode current,
  ) {
    final isSelected = current == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => setThemeMode(mode),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF6366F1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    )
                  ]
                : [],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: isSelected
                    ? Colors.white
                    : AppColors.textMuted(context),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight:
                      isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected
                      ? Colors.white
                      : AppColors.textMuted(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

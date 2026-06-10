import 'package:flutter/material.dart';
import '../theme_notifier.dart';
import '../theme_colors.dart';

class AppearanceToggle extends StatefulWidget {
  const AppearanceToggle({super.key});

  @override
  State<AppearanceToggle> createState() => _AppearanceToggleState();
}

class _AppearanceToggleState extends State<AppearanceToggle> {
  late ThemeMode _currentMode;

  @override
  void initState() {
    super.initState();
    _currentMode = themeNotifier.value;
    themeNotifier.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    themeNotifier.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() {
    if (mounted) {
      setState(() {
        _currentMode = themeNotifier.value;
      });
    }
  }

  Widget _buildOption(ThemeMode mode, String label, IconData icon) {
    final isSelected = _currentMode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setThemeMode(mode);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF6366F1).withValues(alpha: 0.1) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? const Color(0xFF6366F1) : AppColors.border(context),
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: isSelected ? const Color(0xFF6366F1) : AppColors.textMuted(context),
                size: 20,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? const Color(0xFF6366F1) : AppColors.textMuted(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
              const Icon(Icons.brightness_6_outlined, color: Color(0xFF6366F1), size: 20),
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
          const SizedBox(height: 16),
          Row(
            children: [
              _buildOption(ThemeMode.light, 'Light', Icons.light_mode_outlined),
              const SizedBox(width: 8),
              _buildOption(ThemeMode.system, 'System', Icons.brightness_auto_outlined),
              const SizedBox(width: 8),
              _buildOption(ThemeMode.dark, 'Dark', Icons.dark_mode_outlined),
            ],
          ),
        ],
      ),
    );
  }
}

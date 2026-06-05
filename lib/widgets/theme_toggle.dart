import 'package:flutter/material.dart';
import '../theme_notifier.dart';
import '../theme_colors.dart';

/// Appearance slider: Dark ← System → Light.
/// Drop this anywhere — it reads and writes [themeNotifier] directly.
class AppearanceToggle extends StatefulWidget {
  const AppearanceToggle({super.key});

  @override
  State<AppearanceToggle> createState() => _AppearanceToggleState();
}

class _AppearanceToggleState extends State<AppearanceToggle> {
  double _brightnessValue = 0.5; // default to system

  @override
  void initState() {
    super.initState();
    _brightnessValue = switch (themeNotifier.value) {
      ThemeMode.dark   => 0.0,
      ThemeMode.system => 0.5,
      ThemeMode.light  => 1.0,
    };
  }

  String get _brightnessLabel => switch (_brightnessValue) {
    0.0 => 'Dark',
    1.0 => 'Light',
    _   => 'System',
  };

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
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 6,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
              activeTrackColor: const Color(0xFF6366F1),
              inactiveTrackColor: AppColors.surfaceBg(context),
              thumbColor: const Color(0xFF6366F1),
              overlayColor: const Color(0xFF6366F1).withValues(alpha: 0.15),
            ),
            child: Slider(
              value: _brightnessValue,
              min: 0.0,
              max: 1.0,
              divisions: 2,
              label: _brightnessLabel,
              onChanged: (value) {
                setState(() => _brightnessValue = value);
                if (value == 0.0) {
                  setThemeMode(ThemeMode.dark);
                } else if (value == 1.0) {
                  setThemeMode(ThemeMode.light);
                } else {
                  setThemeMode(ThemeMode.system);
                }
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Dark',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: _brightnessValue == 0.0
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: _brightnessValue == 0.0
                            ? const Color(0xFF6366F1)
                            : AppColors.textMuted(context))),
                Text('System',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: _brightnessValue == 0.5
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: _brightnessValue == 0.5
                            ? const Color(0xFF6366F1)
                            : AppColors.textMuted(context))),
                Text('Light',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: _brightnessValue == 1.0
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: _brightnessValue == 1.0
                            ? const Color(0xFF6366F1)
                            : AppColors.textMuted(context))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

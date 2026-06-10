import 'package:flutter/material.dart';
import '../../../theme_colors.dart';

class HealthVaultScreen extends StatelessWidget {
  const HealthVaultScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.shield_outlined, size: 64, color: AppColors.brandIndigo),
          const SizedBox(height: 16),
          Text(
            "Health Vault",
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Coming Soon",
            style: TextStyle(color: AppColors.textMuted(context)),
          ),
        ],
      ),
    );
  }
}

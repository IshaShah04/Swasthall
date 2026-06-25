import 'package:flutter/material.dart';
import '../../../../theme_colors.dart';

class HelpfulActionsRow extends StatelessWidget {
  const HelpfulActionsRow({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Helpful Actions",
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary(context),
          ),
        ),
        const SizedBox(height: 16),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _buildActionItem(
                  context: context,
                  icon: Icons.calendar_month,
                  label: "Book Appointment",
                  color: const Color(0xFF3B82F6), // Blue
                  bgColor: const Color(0xFFEFF6FF),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildActionItem(
                  context: context,
                  icon: Icons.local_pharmacy,
                  label: "Order Medicine",
                  color: const Color(0xFF10B981), // Green
                  bgColor: const Color(0xFFECFDF5),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildActionItem(
                  context: context,
                  icon: Icons.biotech,
                  label: "Book Lab Test",
                  color: const Color(0xFFF59E0B), // Amber
                  bgColor: const Color(0xFFFFFBEB),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionItem({
    required BuildContext context,
    required IconData icon,
    required String label,
    required Color color,
    required Color bgColor,
  }) {
    return GestureDetector(
      onTap: () {
        // Navigation actions to be implemented
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          color: AppColors.cardBg(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border(context)),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: bgColor,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 12),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary(context),
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

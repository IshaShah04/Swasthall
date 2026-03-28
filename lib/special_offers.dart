import 'package:flutter/material.dart';
import 'theme_colors.dart';

class SpecialOffers extends StatelessWidget {
  const SpecialOffers({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildOfferCard(
          context,
          title: "Premium Health Checkup",
          discount: "30% OFF",
          code: "HEALTH30",
          color: const Color(0xFF6366F1),
        ),
        const SizedBox(height: 12),
        _buildOfferCard(
          context,
          title: "First Lab Test Discount",
          discount: "FREE HOME VISIT",
          code: "LABFREE",
          color: const Color(0xFF10B981),
        ),
      ],
    );
  }

  Widget _buildOfferCard(BuildContext context,
      {required String title,
      required String discount,
      required String code,
      required Color color}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.local_offer_outlined, color: color, size: 30),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14)),
                Text(discount,
                    style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w900,
                        fontSize: 16)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(8)),
            child: Text(code,
                style: TextStyle(
                    color: AppColors.cardBg(context),
                    fontSize: 10,
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

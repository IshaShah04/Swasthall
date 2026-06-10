import 'package:flutter/material.dart';

class ServiceBenefitsRow extends StatelessWidget {
  const ServiceBenefitsRow({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _BenefitItem(icon: Icons.verified, label: 'Genuine', color: Colors.green.shade700),
          _BenefitItem(icon: Icons.local_shipping, label: 'Free Delivery', color: Colors.green.shade700),
          _BenefitItem(icon: Icons.health_and_safety, label: 'Safe & Secure', color: Colors.green.shade700),
        ],
      ),
    );
  }
}

class _BenefitItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _BenefitItem({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12),
        ),
      ],
    );
  }
}

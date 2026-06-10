import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class QuickReferenceGrid extends StatelessWidget {
  const QuickReferenceGrid({super.key});

  @override
  Widget build(BuildContext context) {
    final items = [
      _ReferenceItem('Indications', 'When it is used', Icons.healing_rounded, Colors.blue, 'indications'),
      _ReferenceItem('Side Effects', 'Possible side effects', Icons.warning_amber_rounded, Colors.orange, 'side-effects'),
      _ReferenceItem('Precautions', 'Safety information', Icons.shield_outlined, Colors.green, 'precautions'),
      _ReferenceItem('Dosage', 'How and how much', Icons.timer_outlined, Colors.purple, 'dosage'),
      _ReferenceItem('Contraindications', 'When not to use', Icons.block_rounded, Colors.red, 'contraindications'),
      _ReferenceItem('Drug Interactions', 'Interactions to know', Icons.compare_arrows_rounded, Colors.purple, 'drug-interactions'),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.85,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemBuilder: (context, index) {
        final item = items[index];
        return InkWell(
          onTap: () {
            try {
              GoRouter.of(context).go('/study-hub/reference/${item.type}');
            } catch (e) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Coming Soon')));
            }
          },
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: item.color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: item.color.withValues(alpha: 0.2)),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(item.icon, color: item.color, size: 28),
                const SizedBox(height: 8),
                Text(
                  item.title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: item.color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item.subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10,
                    color: item.color.withValues(alpha: 0.8),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ReferenceItem {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final String type;

  _ReferenceItem(this.title, this.subtitle, this.icon, this.color, this.type);
}

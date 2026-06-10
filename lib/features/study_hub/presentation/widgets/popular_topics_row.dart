import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class PopularTopicsRow extends StatelessWidget {
  const PopularTopicsRow({super.key});

  @override
  Widget build(BuildContext context) {
    final topics = [
      {'title': 'Heart Health', 'color': Colors.red, 'slug': 'heart-health'},
      {'title': 'Diabetes', 'color': Colors.blue, 'slug': 'diabetes'},
      {'title': 'Women\'s Health', 'color': Colors.pink, 'slug': 'womens-health'},
      {'title': 'Mental Wellbeing', 'color': Colors.purple, 'slug': 'mental-wellbeing'},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Popular Topics',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: topics.map((topic) {
              final color = topic['color'] as MaterialColor;
              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: ActionChip(
                  label: Text(topic['title'] as String),
                  labelStyle: TextStyle(color: color.shade700, fontWeight: FontWeight.bold),
                  backgroundColor: color.withValues(alpha: 0.1),
                  side: BorderSide.none,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  onPressed: () {
                    try {
                      GoRouter.of(context).go('/study-hub/topic/${topic['slug']}');
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Coming Soon')));
                    }
                  },
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

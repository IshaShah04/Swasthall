import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/pharmacies_providers.dart';

class HealthEssentialsCategories extends ConsumerWidget {
  const HealthEssentialsCategories({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentCat = ref.watch(medicineCategoryProvider);
    final categories = [
      {'id': 'all', 'label': 'All'},
      {'id': 'personal_care', 'label': 'Personal Care'},
      {'id': 'vitamins', 'label': 'Vitamins'},
      {'id': 'baby_care', 'label': 'Baby Care'},
      {'id': 'diabetes', 'label': 'Diabetes'},
      {'id': 'first_aid', 'label': 'First Aid'},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Health Essentials',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 40,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: categories.length,
            itemBuilder: (context, index) {
              final cat = categories[index];
              final isSelected = cat['id'] == currentCat;
              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: ChoiceChip(
                  label: Text(cat['label']!),
                  selected: isSelected,
                  onSelected: (selected) {
                    ref.read(medicineCategoryProvider.notifier).state = cat['id']!;
                  },
                  selectedColor: Colors.blueAccent,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : Colors.black87,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

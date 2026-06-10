import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/pharmacies_providers.dart';

class PharmaciesNearbySection extends ConsumerWidget {
  const PharmaciesNearbySection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pharmaciesAsync = ref.watch(pharmaciesNearbyProvider);
    final currentFilter = ref.watch(pharmacyFilterProvider);
    final filters = ['Near Me', 'Open Now', 'Up to 5km'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Find Pharmacies Nearby',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            TextButton(
              onPressed: () {},
              child: const Text('See All'),
            ),
          ],
        ),
        SizedBox(
          height: 40,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: filters.length,
            itemBuilder: (context, index) {
              final filter = filters[index];
              final isSelected = filter == currentFilter;
              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: FilterChip(
                  label: Text(filter),
                  selected: isSelected,
                  onSelected: (selected) {
                    ref.read(pharmacyFilterProvider.notifier).state = filter;
                  },
                  selectedColor: Colors.blue.shade100,
                  checkmarkColor: Colors.blue,
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        pharmaciesAsync.when(
          data: (pharmacies) {
            if (pharmacies.isEmpty) {
              return const Text('No pharmacies found.', style: TextStyle(color: Colors.grey));
            }
            return SizedBox(
              height: 120,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: pharmacies.length,
                itemBuilder: (context, index) {
                  final p = pharmacies[index];
                  final name = p['name'] ?? 'Pharmacy';
                  final rating = (p['rating'] as num?)?.toDouble() ?? 0.0;
                  final reviews = p['review_count'] as int? ?? 0;
                  final isOpen = p['is_open'] as bool? ?? false;
                  final closingTime = p['closing_time'] as String? ?? 'N/A';
                  final imageUrl = p['avatar_url'] as String?;

                  return Container(
                    width: 280,
                    margin: const EdgeInsets.only(right: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: imageUrl != null
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.network(imageUrl, fit: BoxFit.cover),
                                )
                              : const Icon(Icons.local_pharmacy, color: Colors.grey, size: 32),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(Icons.star, color: Colors.amber, size: 14),
                                  const SizedBox(width: 4),
                                  Text(
                                    '$rating ($reviews)',
                                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: isOpen ? Colors.green : Colors.red,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    isOpen ? 'Open • Closes $closingTime' : 'Closed',
                                    style: TextStyle(color: isOpen ? Colors.green : Colors.red, fontSize: 12),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            );
          },
          loading: () => const SizedBox(height: 120, child: Center(child: CircularProgressIndicator())),
          error: (e, st) => Text('Error: $e'),
        ),
      ],
    );
  }
}

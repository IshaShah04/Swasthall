import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/pharmacies_providers.dart';

class MedicinesGrid extends ConsumerWidget {
  const MedicinesGrid({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final medsAsync = ref.watch(medicinesGridProvider);

    return medsAsync.when(
      data: (medicines) {
        if (medicines.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32.0),
              child: Text('No medicines found.', style: TextStyle(color: Colors.grey)),
            ),
          );
        }
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 0.65,
          ),
          itemCount: medicines.length,
          itemBuilder: (context, index) {
            final med = medicines[index];
            final name = med['name'] as String? ?? 'Medicine';
            final brand = med['brand'] as String? ?? '';
            final dosage = med['dosage'] as String? ?? '';
            final unit = med['unit'] as String? ?? '';
            final price = (med['price'] as num?)?.toDouble() ?? 0.0;
            final imageUrl = med['image_url'] as String?;
            final id = med['id'].toString();

            return Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                      ),
                      child: imageUrl != null
                          ? ClipRRect(
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                              child: Image.network(imageUrl, fit: BoxFit.contain),
                            )
                          : const Icon(Icons.medication, size: 48, color: Colors.blueAccent),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        if (brand.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(brand, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                          ),
                        if (dosage.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text('$dosage $unit', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                          ),
                        const SizedBox(height: 8),
                        Text(
                          'Rs. $price',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent, fontSize: 16),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () {
                              ref.read(cartProvider.notifier).addItem(
                                CartItem(medicineId: id, name: name, qty: 1, price: price),
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('$name added to cart!'), duration: const Duration(seconds: 1)),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            child: const Text('Add'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
      loading: () => const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator())),
      error: (e, st) => Text('Error: $e'),
    );
  }
}

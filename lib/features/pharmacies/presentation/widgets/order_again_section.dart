import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/pharmacies_providers.dart';

class OrderAgainSection extends ConsumerWidget {
  const OrderAgainSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orderAgainAsync = ref.watch(orderAgainProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Order Again',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        orderAgainAsync.when(
          data: (medicines) {
            if (medicines.isEmpty) {
              return const Text('No past orders found.', style: TextStyle(color: Colors.grey));
            }
            return SizedBox(
              height: 140,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: medicines.length,
                itemBuilder: (context, index) {
                  final med = medicines[index];
                  final name = med['name'] as String? ?? 'Medicine';
                  final price = (med['price'] as num?)?.toDouble() ?? 0.0;
                  final imageUrl = med['image_url'] as String?;
                  final id = med['id'].toString();

                  return Container(
                    width: 200,
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
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: imageUrl != null
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.network(imageUrl, fit: BoxFit.cover),
                                )
                              : const Icon(Icons.medication, color: Colors.blue),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                              const Spacer(),
                              Text(
                                'Rs. $price',
                                style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 4),
                              SizedBox(
                                height: 28,
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
                                    padding: const EdgeInsets.symmetric(horizontal: 12),
                                    textStyle: const TextStyle(fontSize: 12),
                                  ),
                                  child: const Text('Add to Cart'),
                                ),
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
          loading: () => const SizedBox(height: 140, child: Center(child: CircularProgressIndicator())),
          error: (e, st) => Text('Error: $e'),
        ),
      ],
    );
  }
}

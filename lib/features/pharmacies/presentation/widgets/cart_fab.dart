import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/pharmacies_providers.dart';

class CartFab extends ConsumerWidget {
  const CartFab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cartState = ref.watch(cartProvider);

    if (cartState.items.isEmpty) {
      return const SizedBox.shrink();
    }

    final totalItems = cartState.items.fold<int>(0, (sum, item) => sum + item.qty);

    return FloatingActionButton.extended(
      onPressed: () {
        // Will be implemented later or if user provides route
        context.push('/pharmacies/cart');
      },
      backgroundColor: Colors.blueAccent,
      icon: const Icon(Icons.shopping_cart, color: Colors.white),
      label: Text(
        '$totalItems item${totalItems > 1 ? 's' : ''} • Rs. ${cartState.total.toStringAsFixed(2)}',
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
    );
  }
}

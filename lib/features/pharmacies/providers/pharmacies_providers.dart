import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final _supabase = Supabase.instance.client;

final medicineSearchQueryProvider = StateProvider<String>((ref) => '');
final medicineCategoryProvider = StateProvider<String>((ref) => 'all');
final pharmacyFilterProvider = StateProvider<String>((ref) => 'Near Me');

class CartItem {
  final String medicineId;
  final String name;
  final int qty;
  final double price;

  CartItem({required this.medicineId, required this.name, required this.qty, required this.price});

  CartItem copyWith({int? qty}) => CartItem(
    medicineId: medicineId,
    name: name,
    qty: qty ?? this.qty,
    price: price,
  );
}

class CartState {
  final List<CartItem> items;
  final double total;

  CartState({required this.items, required this.total});
}

class CartNotifier extends StateNotifier<CartState> {
  CartNotifier() : super(CartState(items: [], total: 0));

  void addItem(CartItem item) {
    final items = List<CartItem>.from(state.items);
    final index = items.indexWhere((e) => e.medicineId == item.medicineId);
    if (index >= 0) {
      final existing = items[index];
      items[index] = existing.copyWith(qty: existing.qty + item.qty);
    } else {
      items.add(item);
    }
    _updateState(items);
  }

  void removeItem(String medicineId) {
    final items = List<CartItem>.from(state.items)..removeWhere((e) => e.medicineId == medicineId);
    _updateState(items);
  }

  void updateQty(String medicineId, int qty) {
    if (qty <= 0) {
      removeItem(medicineId);
      return;
    }
    final items = List<CartItem>.from(state.items);
    final index = items.indexWhere((e) => e.medicineId == medicineId);
    if (index >= 0) {
      items[index] = items[index].copyWith(qty: qty);
    }
    _updateState(items);
  }

  void clear() => state = CartState(items: [], total: 0);

  void _updateState(List<CartItem> items) {
    double total = items.fold(0, (sum, item) => sum + (item.price * item.qty));
    state = CartState(items: items, total: total);
  }
}

final cartProvider = StateNotifierProvider<CartNotifier, CartState>((ref) => CartNotifier());

final orderAgainProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final userId = _supabase.auth.currentUser?.id;
  if (userId == null) return [];

  final ordersRes = await _supabase
      .from('medicine_orders')
      .select('items')
      .eq('user_id', userId)
      .order('created_at', ascending: false)
      .limit(10);

  final uniqueMedicineIds = <String>{};
  for (final row in ordersRes) {
    final items = row['items'] as List<dynamic>? ?? [];
    for (final item in items) {
      final map = item as Map<String, dynamic>;
      if (map['medicine_id'] != null) {
        uniqueMedicineIds.add(map['medicine_id'].toString());
      }
    }
  }

  if (uniqueMedicineIds.isEmpty) return [];

  final idsToFetch = uniqueMedicineIds.take(3).toList();
  final medsRes = await _supabase.from('medicines').select('*').inFilter('id', idsToFetch);

  return List<Map<String, dynamic>>.from(medsRes);
});

final pharmaciesNearbyProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final filter = ref.watch(pharmacyFilterProvider);
  var query = _supabase.from('pharmacies').select('*');

  if (filter == 'Open Now') {
    query = query.eq('is_open', true);
  }

  final res = await query.limit(10);
  return List<Map<String, dynamic>>.from(res);
});

final medicinesGridProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final searchQuery = ref.watch(medicineSearchQueryProvider);
  final category = ref.watch(medicineCategoryProvider);

  var query = _supabase.from('medicines').select('*');

  if (category != 'all') {
    query = query.eq('category', category);
  }
  if (searchQuery.isNotEmpty) {
    query = query.ilike('name', '%$searchQuery%');
  }

  final res = await query.limit(20);
  return List<Map<String, dynamic>>.from(res);
});

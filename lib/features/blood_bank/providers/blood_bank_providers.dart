import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final _supabase = Supabase.instance.client;

final bloodInventoryProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  return _supabase.from('blood_inventory').stream(primaryKey: ['id']);
});

final bloodGroupSummaryProvider = FutureProvider<Map<String, int>>((ref) async {
  final inventory = await _supabase.from('blood_inventory').select('blood_type, units');
  final summary = <String, int>{};
  for (final row in inventory) {
    final type = row['blood_type'] as String;
    final units = row['units'] as int;
    summary[type] = (summary[type] ?? 0) + units;
  }
  return summary;
});

class ActiveBloodRequestsNotifier extends StateNotifier<AsyncValue<List<Map<String, dynamic>>>> {
  ActiveBloodRequestsNotifier() : super(const AsyncValue.loading()) {
    _fetch();
  }

  String? _filterType;

  Future<void> _fetch() async {
    state = const AsyncValue.loading();
    try {
      var query = _supabase
          .from('blood_requests')
          .select('''
            id, blood_type, units_needed, urgency, created_at, hospital_name,
            hospital_id,
            hospitals ( name )
          ''')
          .eq('status', 'active');
          
      if (_filterType != null) {
        query = query.eq('blood_type', _filterType!);
      }
      
      final res = await query.order('urgency', ascending: false).order('created_at', ascending: false).limit(10).timeout(const Duration(seconds: 10));
      
      final data = (res as List).map((row) {
        final map = Map<String, dynamic>.from(row);
        final hospitals = map['hospitals'] as Map<String, dynamic>?;
        map['hospital_display'] = hospitals != null ? hospitals['name'] : map['hospital_name'];
        return map;
      }).toList();
      
      state = AsyncValue.data(data);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  void setFilter(String? type) {
    _filterType = type;
    _fetch();
  }
}

final activeBloodRequestsProvider = StateNotifierProvider<ActiveBloodRequestsNotifier, AsyncValue<List<Map<String, dynamic>>>>((ref) {
  return ActiveBloodRequestsNotifier();
});

final donationCampsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final res = await _supabase
      .from('blood_donation_camps')
      .select('*, hospitals(name)')
      .inFilter('status', ['upcoming', 'active'])
      .gte('camp_date', DateTime.now().toIso8601String().split('T')[0])
      .order('camp_date')
      .limit(3);
  return List<Map<String, dynamic>>.from(res);
});

final myDonationsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final userId = _supabase.auth.currentUser?.id;
  if (userId == null) throw Exception('Not logged in');
  
  final profileRes = await _supabase.from('profiles').select('blood_group').eq('id', userId).maybeSingle();
  final bloodGroup = profileRes?['blood_group'] as String?;

  final donationsRes = await _supabase.from('blood_donations').select('donated_at').eq('donor_id', userId);
  
  int total = donationsRes.length;
  int thisYear = 0;
  final currentYear = DateTime.now().year;
  
  for (final row in donationsRes) {
    final dateStr = row['donated_at'] as String?;
    if (dateStr != null) {
      final date = DateTime.tryParse(dateStr);
      if (date != null && date.year == currentYear) {
        thisYear++;
      }
    }
  }
  
  return {
    'blood_group': bloodGroup,
    'total': total,
    'this_year': thisYear,
  };
});

final hospitalsListProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final res = await _supabase.from('hospitals').select('id, name');
  return List<Map<String, dynamic>>.from(res);
});

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabase = Supabase.instance.client;

final labSearchQueryProvider = StateProvider<String>((ref) => '');

final verifiedLabPartnersProvider = AsyncNotifierProvider<VerifiedLabPartnersNotifier, List<Map<String, dynamic>>>(
  () => VerifiedLabPartnersNotifier(),
);

class VerifiedLabPartnersNotifier extends AsyncNotifier<List<Map<String, dynamic>>> {
  @override
  Future<List<Map<String, dynamic>>> build() async {
    return _fetchPartners();
  }

  Future<List<Map<String, dynamic>>> _fetchPartners() async {
    try {
      final response = await supabase
          .from('hospitals')
          .select('id, name, location, avatar_url, rating, review_count, is_nabl_accredited, turnaround_hours, home_collection_available')
          .order('rating', ascending: false)
          .limit(5);

      final hospitals = (response as List).map((r) => Map<String, dynamic>.from(r)).toList();
      
      if (hospitals.isEmpty) return hospitals;

      final hospitalIds = hospitals.map((h) => h['id']).toList();
      
      final testsResponse = await supabase
          .from('lab_tests')
          .select('id, hospital_id')
          .filter('hospital_id', 'in', hospitalIds);
          
      final Map<String, int> testCounts = {};
      for (final test in (testsResponse as List)) {
        final hId = test['hospital_id'].toString();
        testCounts[hId] = (testCounts[hId] ?? 0) + 1;
      }
      
      for (var hospital in hospitals) {
        hospital['test_count'] = testCounts[hospital['id'].toString()] ?? 0;
      }

      return hospitals;
    } catch (e) {
      rethrow;
    }
  }
}

final popularTestsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  try {
    final response = await supabase
        .from('lab_tests')
        .select('id, name')
        .order('bookings', ascending: false)
        .limit(8);
    
    return (response as List).map((row) => Map<String, dynamic>.from(row)).toList();
  } catch (e) {
    rethrow;
  }
});

final myLabBookingsProvider = AsyncNotifierProvider<MyLabBookingsNotifier, List<Map<String, dynamic>>>(
  () => MyLabBookingsNotifier(),
);

class MyLabBookingsNotifier extends AsyncNotifier<List<Map<String, dynamic>>> {
  @override
  Future<List<Map<String, dynamic>>> build() async {
    return _fetchBookings();
  }

  Future<List<Map<String, dynamic>>> _fetchBookings() async {
    final user = supabase.auth.currentUser;
    if (user == null) return [];

    try {
      final response = await supabase
          .from('lab_appointments')
          .select('*, hospitals!left(name)')
          .eq('user_id', user.id)
          .order('appointment_date', ascending: false);

      return (response as List).map((row) {
        final map = Map<String, dynamic>.from(row);
        final hospitalMap = map['hospitals'];
        if (hospitalMap != null && hospitalMap is Map) {
          map['hospital_name'] = hospitalMap['name'];
        } else if (hospitalMap != null && hospitalMap is List && hospitalMap.isNotEmpty) {
          map['hospital_name'] = hospitalMap.first['name'];
        }
        map.remove('hospitals');
        return map;
      }).toList();
    } catch (e) {
      rethrow;
    }
  }
}

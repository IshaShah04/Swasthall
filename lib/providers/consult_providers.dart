import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabase = Supabase.instance.client;

// --- Data Providers ---

// 1. Fetch doctors with hospitals join
final consultDoctorsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  try {
    final docsRes = await supabase
        .from('staff')
        .select('*, hospitals(id, name, location, avatar_url)')
        .eq('role', 'doctor')
        .order('rating', ascending: false)
        .order('daily_bookings', ascending: false);

    return List<Map<String, dynamic>>.from(docsRes);
  } catch (e) {
    rethrow;
  }
});

// 2. Extract specialities from the fetched doctors
final consultAllSpecialitiesProvider = Provider<List<String>>((ref) {
  final asyncDocs = ref.watch(consultDoctorsProvider);
  
  return asyncDocs.when(
    data: (docs) {
      final Set<String> specialities = {};
      for (var doc in docs) {
        if (doc['speciality'] != null && doc['speciality'].toString().isNotEmpty) {
          specialities.add(doc['speciality'].toString());
        }
      }
      return specialities.toList()..sort();
    },
    loading: () => [],
    error: (_, __) => [],
  );
});

// 3. Fetch unread notification count
final consultUnreadCountProvider = FutureProvider<int>((ref) async {
  final user = supabase.auth.currentUser;
  if (user == null) return 0;
  
  final notifRes = await supabase
      .from('notifications')
      .select('id')
      .eq('user_id', user.id)
      .eq('is_read', false);
      
  return (notifRes as List).length;
});

// --- Filter State Providers ---

final consultSearchQueryProvider = StateProvider<String>((ref) => '');
final consultSelectedSpecialityProvider = StateProvider<String?>((ref) => null);
final consultMinRatingProvider = StateProvider<double>((ref) => 0.0);
final consultFilterSpecialitiesProvider = StateProvider<List<String>>((ref) => []);
final consultAvailableOnlyProvider = StateProvider<bool>((ref) => false);

// --- Filtered Data Provider ---

final filteredConsultDoctorsProvider = Provider<List<Map<String, dynamic>>>((ref) {
  final asyncDocs = ref.watch(consultDoctorsProvider);
  final searchQuery = ref.watch(consultSearchQueryProvider);
  final selectedSpeciality = ref.watch(consultSelectedSpecialityProvider);
  final minRating = ref.watch(consultMinRatingProvider);
  final filterSpecialities = ref.watch(consultFilterSpecialitiesProvider);
  final availableOnly = ref.watch(consultAvailableOnlyProvider);

  return asyncDocs.when(
    data: (docs) {
      return docs.where((d) {
        // Search
        if (searchQuery.isNotEmpty) {
          final name = (d['name'] ?? '').toString().toLowerCase();
          final speciality = (d['speciality'] ?? '').toString().toLowerCase();
          
          String hospName = '';
          if (d['hospitals'] != null) {
            if (d['hospitals'] is Map) {
              hospName = (d['hospitals']['name'] ?? '').toString().toLowerCase();
            } else if (d['hospitals'] is List && (d['hospitals'] as List).isNotEmpty) {
               hospName = (d['hospitals'][0]['name'] ?? '').toString().toLowerCase();
            }
          }
          
          if (!name.contains(searchQuery.toLowerCase()) && 
              !speciality.contains(searchQuery.toLowerCase()) &&
              !hospName.contains(searchQuery.toLowerCase())) {
            return false;
          }
        }

        // Chip Specialty
        if (selectedSpeciality != null) {
          if (d['speciality'] != selectedSpeciality) return false;
        }

        // Bottom Sheet Specialty Multi-select
        if (filterSpecialities.isNotEmpty) {
          if (!filterSpecialities.contains(d['speciality'])) return false;
        }

        // Rating filter
        final rating = double.tryParse(d['rating']?.toString() ?? '0') ?? 0.0;
        if (rating < minRating) return false;

        // Availability filter (placeholder check)
        if (availableOnly) {
          // Add availability logic here if backend supports it
        }

        return true;
      }).toList();
    },
    loading: () => [],
    error: (_, __) => [],
  );
});

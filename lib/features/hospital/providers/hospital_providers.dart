import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabase = Supabase.instance.client;

final hospitalDetailProvider = FutureProvider.family<Map<String, dynamic>, String>((ref, id) async {
  final response = await supabase
      .from('hospitals')
      .select()
      .eq('id', id)
      .single();
  return response;
});

final hospitalSpecialtiesProvider = FutureProvider.family<List<String>, String>((ref, id) async {
  final response = await supabase
      .from('staff')
      .select('speciality')
      .eq('hospital_id', id)
      .eq('role', 'doctor');
  
  final specs = response.map((e) => e['speciality'] as String?).whereType<String>().toSet().toList();
  return specs;
});

class HospitalDoctorsArgs {
  final String hospitalId;
  final String? specialty;
  final String? query;
  
  HospitalDoctorsArgs({required this.hospitalId, this.specialty, this.query});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HospitalDoctorsArgs &&
          runtimeType == other.runtimeType &&
          hospitalId == other.hospitalId &&
          specialty == other.specialty &&
          query == other.query;

  @override
  int get hashCode => hospitalId.hashCode ^ specialty.hashCode ^ query.hashCode;
}

final hospitalDoctorsFilterProvider = StateProvider.family<HospitalDoctorsArgs, String>((ref, hospitalId) {
  return HospitalDoctorsArgs(hospitalId: hospitalId);
});

final hospitalDoctorsProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((ref, hospitalId) async {
  final filter = ref.watch(hospitalDoctorsFilterProvider(hospitalId));
  
  var query = supabase
      .from('staff')
      .select('id, name, speciality, degree, rating, review_count, avatar_url, experience_years, first_consultation_fee, followup_consultation_fee')
      .eq('hospital_id', hospitalId)
      .eq('role', 'doctor');
      
  if (filter.specialty != null && filter.specialty != 'All') {
    query = query.eq('speciality', filter.specialty!);
  }
  
  if (filter.query != null && filter.query!.isNotEmpty) {
    query = query.ilike('name', '%${filter.query}%');
  }
  
  final response = await query.order('rating', ascending: false);
  return List<Map<String, dynamic>>.from(response);
});

final hospitalReviewsProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((ref, id) async {
  final response = await supabase
      .from('hospital_reviews')
      .select('rating, comment, created_at, profiles!inner(full_name, avatar_url)')
      .eq('hospital_id', id)
      .order('created_at', ascending: false);
  return List<Map<String, dynamic>>.from(response);
});

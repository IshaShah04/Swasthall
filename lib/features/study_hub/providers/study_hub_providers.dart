import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final studyHubSearchProvider = StateProvider<String>((ref) => '');

final expertDoctorsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final supabase = Supabase.instance.client;
  
  // Fetch doctors from staff table who have videos
  // SELECT s.id, s.name, s.avatar_url, s.speciality, h.name as hospital_name
  // FROM staff s JOIN hospitals h ON h.id=s.hospital_id
  // WHERE s.role='doctor' LIMIT 6
  final response = await supabase
      .from('staff')
      .select('id, name, avatar_url, speciality, hospitals!inner(name)')
      .eq('role', 'doctor')
      .limit(6);
      
  return List<Map<String, dynamic>>.from(response);
});

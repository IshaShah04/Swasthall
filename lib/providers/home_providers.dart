import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/hospital.dart';
import '../models/home_data.dart';
import '../models/upcoming_booking.dart';

final supabase = Supabase.instance.client;

// All hospitals ordered by rating DESC
final hospitalsProvider = FutureProvider<List<Hospital>>((ref) async {
  final data = await supabase
      .from('hospitals')
      .select()
      .order('rating', ascending: false);
  return (data as List).map((e) => Hospital.fromJson(e)).toList();
});

// Selected hospital — initialized to null, set after hospitalsProvider loads
final selectedHospitalProvider = StateProvider<Hospital?>((ref) => null);

// Home data — parallel fetches
final homeDataProvider = FutureProvider<HomeData>((ref) async {
  final uid = supabase.auth.currentUser!.id;
  
  final results = await Future.wait([
    supabase
        .from('bookings')
        .select()
        .eq('patient_id', uid)
        .inFilter('status', ['confirmed', 'pending'])
        .gte('appointment_date', DateTime.now().toIso8601String().split('T')[0])
        .order('appointment_date', ascending: true)
        .order('appointment_time', ascending: true)
        .limit(1),
    supabase
        .from('medical_records')
        .select('id')
        .eq('patient_id', uid),
    supabase
        .from('notifications')
        .select('id')
        .eq('user_id', uid)
        .eq('is_read', false),
  ]);

  final bookings = results[0] as List;
  final records = results[1] as List;
  final notifs = results[2] as List;

  UpcomingBooking? booking;
  if (bookings.isNotEmpty) {
    final b = bookings[0];
    
    // Fetch staff and hospital separately to avoid schema foreign key issues
    final staffId = b['provider_id'] ?? b['doctor_id'] ?? b['staff_id'];
    final hospitalId = b['hospital_id'];
    
    Map<String, dynamic>? staffInfo;
    Map<String, dynamic>? hospitalInfo;
    
    try {
      if (staffId != null) {
        staffInfo = await supabase.from('profiles').select('full_name, speciality, avatar_url').eq('id', staffId).maybeSingle();
      }
      if (hospitalId != null) {
        hospitalInfo = await supabase.from('hospitals').select('name').eq('id', hospitalId).maybeSingle();
      }
    } catch (e) {
      debugPrint('Error fetching related data for booking: $e');
    }

    booking = UpcomingBooking(
      id: b['id'],
      doctorName: staffInfo?['full_name'] ?? 'Unknown',
      doctorSpeciality: staffInfo?['speciality'] ?? '',
      doctorAvatarUrl: staffInfo?['avatar_url'],
      hospitalName: hospitalInfo?['name'] ?? '',
      appointmentDate: DateTime.parse(b['appointment_date']),
      appointmentTime: b['appointment_time'],
      status: b['status'],
      type: b['type'] ?? '',
      consultationFee: (b['consultation_fee'] as num).toDouble(),
    );
  }

  return HomeData(
    upcomingBooking: booking,
    reportCount: records.length,
    unreadNotificationCount: notifs.length,
  );
});

// Profile data
final profileProvider = FutureProvider((ref) async {
  final uid = supabase.auth.currentUser!.id;
  return await supabase.from('profiles').select().eq('id', uid).single();
});

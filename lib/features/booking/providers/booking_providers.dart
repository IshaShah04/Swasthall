import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final doctorForBookingProvider = FutureProvider.family<Map<String, dynamic>, String>((ref, doctorId) async {
  final supabase = Supabase.instance.client;
  final response = await supabase
      .from('staff')
      .select('id, name, degree, speciality, avatar_url, rating, first_consultation_fee, followup_consultation_fee, email')
      .eq('id', doctorId)
      .single();
  return response;
});

final selectedDateProvider = StateProvider<DateTime>((ref) => DateTime.now());

final selectedSlotProvider = StateProvider<Map<String, dynamic>?>((ref) => null);

// 'in_clinic' | 'video'
final selectedAppointmentTypeProvider = StateProvider<String>((ref) => 'in_clinic');

// Custom record type for slots provider args
typedef SlotsProviderArgs = ({String doctorId, DateTime date, String slotType});

final availableSlotsProvider = FutureProvider.family<List<Map<String, dynamic>>, SlotsProviderArgs>((ref, args) async {
  final supabase = Supabase.instance.client;
  final dateString = "${args.date.year}-${args.date.month.toString().padLeft(2, '0')}-${args.date.day.toString().padLeft(2, '0')}";
  
  final response = await supabase.rpc(
    'get_provider_day_slots',
    params: {
      'p_provider_id': args.doctorId,
      'p_date': dateString,
      'p_slot_type': args.slotType,
    },
  );
  return List<Map<String, dynamic>>.from(response as List);
});

final visitReasonProvider = StateProvider<String>((ref) => 'General Consultation');

final appointmentNotesProvider = StateProvider<String>((ref) => '');

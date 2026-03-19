import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Returns a human-readable label for the earliest available slot
/// for [doctorId], looking up to [lookAheadDays] days from today.
/// Returns null if nothing found.
///
/// Examples: "8:00 AM", "Tomorrow 10:00 AM", null
Future<String?> fetchEarliestSlot(
  SupabaseClient supabase,
  String doctorId, {
  int lookAheadDays = 3,
  String? slotType, // 'online' or 'physical' — null means any
}) async {
  try {
    final now = DateTime.now();

    for (int offset = 0; offset < lookAheadDays; offset++) {
      final date = now.add(Duration(days: offset));
      final formattedDate = DateFormat('yyyy-MM-dd').format(date);
      final isToday = offset == 0;

      // Filter by slot_type if provided — online and physical have different schedules
      var query = supabase
          .from('availability_slots')
          .select()
          .eq('provider_id', doctorId)
          .eq('date', formattedDate);

      if (slotType != null && slotType.isNotEmpty) {
        query = query.eq('slot_type', slotType);
      }

      final availability = await query;

      if ((availability as List).isEmpty) continue;

      // Fetch bookings count per hour
      final booked = await supabase
          .from('bookings')
          .select('appointment_time')
          .eq('staff_id', doctorId)
          .eq('appointment_date', formattedDate)
          .neq('status', 'cancelled');

      final Map<String, int> bookedCount = {};
      for (final b in booked as List) {
        final t = b['appointment_time'].toString().toUpperCase();
        bookedCount[t] = (bookedCount[t] ?? 0) + 1;
      }

      // Walk through each window and find first open slot
      for (final row in availability) {
        DateTime start = DateTime.parse(row['start_time']).toLocal();
        DateTime end   = DateTime.parse(row['end_time']).toLocal();
        final int cap  = (row['hourly_cap'] as int?) ?? 1;

        DateTime current = start;
        while (current.isBefore(end)) {
          final String timeLabel = DateFormat('hh:00 a').format(current);

          // Same fix as booking screen: skip only fully-past hours
          final bool isPast = isToday && current.hour < now.hour;
          final int alreadyBooked = bookedCount[timeLabel.toUpperCase()] ?? 0;

          if (!isPast && alreadyBooked < cap) {
            if (isToday) return timeLabel;
            if (offset == 1) return 'Tomorrow $timeLabel';
            return '${DateFormat('EEE')} $timeLabel';
          }

          current = current.add(const Duration(hours: 1));
        }
      }
    }
    return null;
  } catch (_) {
    return null;
  }
}

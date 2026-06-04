import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Returns a human-readable label for the earliest available slot
/// for [doctorId], looking up to [lookAheadDays] days from today.
/// Returns null if nothing found.
///
/// Uses the safe `get_provider_day_slots` RPC instead of reading `bookings`
/// directly. This keeps public browsing compatible after `bookings` was made
/// private to anon users.
Future<String?> fetchEarliestSlot(
  SupabaseClient supabase,
  String doctorId, {
  int lookAheadDays = 3,
  String? slotType, // 'online' or 'physical' — null means any
}) async {
  try {
    final providerId = doctorId.trim();
    if (providerId.isEmpty) return null;

    final now = DateTime.now();
    final normalizedSlotType = (slotType ?? '').trim().toLowerCase();
    final slotTypes = normalizedSlotType.isEmpty
        ? const <String>['online', 'physical']
        : <String>[normalizedSlotType];

    for (int offset = 0; offset < lookAheadDays; offset++) {
      final date = now.add(Duration(days: offset));
      final formattedDate = DateFormat('yyyy-MM-dd').format(date);

      final candidates = <DateTime, String>{};

      for (final type in slotTypes) {
        final response = await supabase.rpc(
          'get_provider_day_slots',
          params: {
            'p_provider_id': providerId,
            'p_date': formattedDate,
            'p_slot_type': type,
          },
        );

        final rows = response is List ? response : const <dynamic>[];
        for (final raw in rows) {
          final row = Map<String, dynamic>.from(raw as Map);
          final remaining = int.tryParse(
                (row['remaining_capacity'] ?? '0').toString(),
              ) ??
              0;
          if (remaining <= 0) continue;

          final iso = row['iso_start']?.toString();
          final start = iso == null ? null : DateTime.tryParse(iso)?.toLocal();
          if (start == null || !start.isAfter(now)) continue;

          final display = (row['display_time'] ?? '').toString().trim();
          if (display.isEmpty) continue;
          candidates[start] = display;
        }
      }

      if (candidates.isEmpty) continue;
      final earliest = candidates.keys.reduce((a, b) => a.isBefore(b) ? a : b);
      final displayLabel = candidates[earliest]!;

      if (offset == 0) return displayLabel;
      if (offset == 1) return 'Tomorrow $displayLabel';
      return '${DateFormat('EEE').format(date)} $displayLabel';
    }

    return null;
  } catch (_) {
    return null;
  }
}

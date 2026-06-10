import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../providers/booking_providers.dart';

class AppointmentSummaryBar extends ConsumerWidget {
  final String doctorId;
  final String hospitalId;

  const AppointmentSummaryBar({
    super.key,
    required this.doctorId,
    required this.hospitalId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final doctorAsync = ref.watch(doctorForBookingProvider(doctorId));
    final selectedDate = ref.watch(selectedDateProvider);
    final selectedSlot = ref.watch(selectedSlotProvider);
    final apptType = ref.watch(selectedAppointmentTypeProvider);
    final visitReason = ref.watch(visitReasonProvider);
    final notes = ref.watch(appointmentNotesProvider);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            offset: const Offset(0, -4),
            blurRadius: 10,
          )
        ],
      ),
      child: SafeArea(
        child: doctorAsync.when(
          data: (doctor) {
            final fee = visitReason == 'Follow Up' 
                ? (doctor['followup_consultation_fee'] ?? 0.0) 
                : (doctor['first_consultation_fee'] ?? 0.0);
            final dateStr = DateFormat('MMM dd, yyyy').format(selectedDate);
            final timeStr = selectedSlot != null ? selectedSlot['slot_time'] : 'Select Time';
            
            return Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total Fee',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                      Text(
                        'NPR $fee',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$dateStr • $timeStr',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                ElevatedButton(
                  onPressed: selectedSlot == null
                      ? null
                      : () {
                          // Prepare appointment data
                          final appointmentData = {
                            'doctorId': doctorId,
                            'hospitalId': hospitalId,
                            'doctorName': doctor['name'],
                            'doctorEmail': doctor['email'],
                            'appointmentDate': selectedDate.toIso8601String(),
                            'appointmentTime': selectedSlot['slot_time'],
                            'slotId': selectedSlot['id'],
                            'appointmentType': apptType, // 'in_clinic' | 'video'
                            'slotsType': apptType == 'video' ? 'online' : 'physical',
                            'visitReason': visitReason,
                            'notes': notes,
                            'consultationFee': fee,
                          };

                          context.push('/payment', extra: appointmentData);
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Continue →',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => const Text('Error loading details'),
        ),
      ),
    );
  }
}

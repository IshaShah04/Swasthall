import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'widgets/doctor_summary_card.dart';
import 'widgets/date_selector.dart';
import 'widgets/time_slot_grid.dart';
import 'widgets/appointment_type_selector.dart';
import 'widgets/appointment_summary_bar.dart';
import '../providers/booking_providers.dart';

class BookAppointmentScreen extends ConsumerWidget {
  final String doctorId;
  final String hospitalId;

  const BookAppointmentScreen({
    super.key,
    required this.doctorId,
    required this.hospitalId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Book Appointment'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Stepper indicator
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildStep(context, '1', 'Appointment', isActive: true),
                _buildDivider(),
                _buildStep(context, '2', 'Details', isActive: false),
                _buildDivider(),
                _buildStep(context, '3', 'Confirm', isActive: false),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Scrollable content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DoctorSummaryCard(doctorId: doctorId),
                  const SizedBox(height: 24),
                  const DateSelector(),
                  const SizedBox(height: 24),
                  TimeSlotGrid(doctorId: doctorId),
                  const SizedBox(height: 24),
                  const AppointmentTypeSelector(),
                  const SizedBox(height: 24),
                  const Text(
                    'Add Notes (Optional)',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    maxLength: 300,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: 'Any specific concerns or symptoms?',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    onChanged: (val) {
                      ref.read(appointmentNotesProvider.notifier).state = val;
                    },
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: AppointmentSummaryBar(
        doctorId: doctorId,
        hospitalId: hospitalId,
      ),
    );
  }

  Widget _buildStep(BuildContext context, String step, String title, {required bool isActive}) {
    final color = isActive ? Theme.of(context).primaryColor : Colors.grey.shade400;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isActive ? color : Colors.transparent,
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 2),
          ),
          child: Text(
            step,
            style: TextStyle(
              color: isActive ? Colors.white : color,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          title,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }

  Widget _buildDivider() {
    return Expanded(
      child: Container(
        height: 2,
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
        alignment: Alignment.topCenter,
        color: Colors.grey.shade300,
      ),
    );
  }
}

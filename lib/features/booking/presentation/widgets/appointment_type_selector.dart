import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/booking_providers.dart';

class AppointmentTypeSelector extends ConsumerWidget {
  const AppointmentTypeSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedType = ref.watch(selectedAppointmentTypeProvider);
    final visitReason = ref.watch(visitReasonProvider);

    final types = [
      {'id': 'in_clinic', 'title': 'In-clinic Visit', 'icon': Icons.local_hospital, 'recommended': true},
      {'id': 'video', 'title': 'Video Consultation', 'icon': Icons.videocam, 'recommended': false},
    ];

    final reasons = [
      'General Consultation',
      'Follow Up',
      'Second Opinion',
      'Emergency'
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Appointment Type',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Row(
          children: types.map((type) {
            final isSelected = selectedType == type['id'];
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: GestureDetector(
                  onTap: () {
                    ref.read(selectedAppointmentTypeProvider.notifier).state = type['id'] as String;
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isSelected ? Theme.of(context).primaryColor.withValues(alpha: 0.1) : Colors.white,
                      border: Border.all(
                        color: isSelected ? Theme.of(context).primaryColor : Colors.grey.shade300,
                        width: isSelected ? 2 : 1,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (type['recommended'] == true) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.green.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Recommended',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.green.shade800,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                        Icon(
                          type['icon'] as IconData,
                          color: isSelected ? Theme.of(context).primaryColor : Colors.grey.shade600,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          type['title'] as String,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected ? Theme.of(context).primaryColor : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 24),
        const Text(
          'Visit For',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: visitReason,
          decoration: InputDecoration(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          items: reasons.map((reason) {
            return DropdownMenuItem(
              value: reason,
              child: Text(reason),
            );
          }).toList(),
          onChanged: (value) {
            if (value != null) {
              ref.read(visitReasonProvider.notifier).state = value;
            }
          },
        ),
      ],
    );
  }
}

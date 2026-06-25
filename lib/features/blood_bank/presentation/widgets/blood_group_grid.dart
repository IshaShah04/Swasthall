import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/blood_bank_providers.dart';

class BloodGroupGrid extends ConsumerWidget {
  const BloodGroupGrid({super.key});

  Color _getGroupColor(String group) {
    switch (group) {
      case 'A+': return Colors.teal;
      case 'A-': return Colors.teal.shade700;
      case 'B+': return Colors.indigo;
      case 'B-': return Colors.indigo.shade700;
      case 'O+': return Colors.deepOrange;
      case 'O-': return Colors.deepOrange.shade700;
      case 'AB+': return Colors.purple;
      case 'AB-': return Colors.purple.shade700;
      default: return Colors.redAccent;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(bloodGroupSummaryProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Find Blood by Group',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        summaryAsync.when(
          data: (summary) {
            final groups = ['A+', 'A-', 'B+', 'B-', 'O+', 'O-', 'AB+', 'AB-'];
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.8,
              ),
              itemCount: groups.length,
              itemBuilder: (context, index) {
                final group = groups[index];
                final count = summary[group] ?? 0;
                final isLow = count < 10;
                return InkWell(
                  onTap: () {
                    ref.read(activeBloodRequestsProvider.notifier).setFilter(group);
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          group,
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: _getGroupColor(group)),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '$count Units',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) => Text('Error: $e'),
        ),
      ],
    );
  }
}

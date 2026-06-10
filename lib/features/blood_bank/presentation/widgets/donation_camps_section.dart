import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/blood_bank_providers.dart';

class DonationCampsSection extends ConsumerWidget {
  const DonationCampsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final campsAsync = ref.watch(donationCampsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Upcoming Camps',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            TextButton(
              onPressed: () {
                // Future expansion
              },
              child: const Text('View All'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        campsAsync.when(
          data: (camps) {
            if (camps.isEmpty) {
              return const Text('No upcoming camps found.');
            }
            return SizedBox(
              height: 220,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: camps.length,
                itemBuilder: (context, index) {
                  final camp = camps[index];
                  final hospitalData = camp['hospitals'] as Map<String, dynamic>?;
                  final hospitalName = hospitalData != null ? hospitalData['name'] : 'Unknown Hospital';
                  
                  return Container(
                    width: 260,
                    margin: const EdgeInsets.only(right: 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade200),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                          child: Container(
                            height: 100,
                            width: double.infinity,
                            color: Colors.red.shade100,
                            child: camp['image_url'] != null
                                ? Image.network(camp['image_url'], fit: BoxFit.cover)
                                : Icon(Icons.event, size: 48, color: Colors.red.shade300),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                camp['title'] ?? 'Blood Donation Camp',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(Icons.location_on, size: 14, color: Colors.grey.shade600),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      hospitalName,
                                      style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(Icons.calendar_today, size: 14, color: Colors.grey.shade600),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${camp['camp_date']} | ${camp['start_time'] ?? ''}',
                                    style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) => Text('Error: $e'),
        ),
      ],
    );
  }
}

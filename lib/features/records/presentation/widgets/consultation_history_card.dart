import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../theme_colors.dart';
import '../../../../widgets/safe_network_image.dart';
import '../../providers/records_providers.dart';

class ConsultationHistoryCard extends ConsumerWidget {
  const ConsultationHistoryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(consultationHistoryProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              "Consultation History",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary(context),
              ),
            ),
            TextButton(
              onPressed: () {},
              child: const Text(
                "View All",
                style: TextStyle(
                  color: AppColors.brandIndigo,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        historyAsync.when(
          data: (bookings) {
            if (bookings.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Text(
                    "No previous consultations.",
                    style: TextStyle(color: AppColors.textMuted(context)),
                  ),
                ),
              );
            }
            return ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: bookings.length > 3 ? 3 : bookings.length,
              itemBuilder: (context, index) {
                final booking = bookings[index];
                final staff = booking['staff'] ?? {};
                final dateStr = booking['appointment_date'] != null 
                    ? DateFormat('MMM dd, yyyy').format(DateTime.parse(booking['appointment_date']))
                    : '';
                
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.cardBg(context),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border(context)),
                  ),
                  child: Row(
                    children: [
                      SafeAvatar(
                        url: staff['avatar_url'],
                        radius: 24,
                        fallbackIcon: Icons.person_outline,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              staff['name'] ?? 'Doctor',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: AppColors.textPrimary(context),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              staff['speciality'] ?? booking['type'] ?? 'Consultation',
                              style: TextStyle(
                                color: AppColors.brandIndigo,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(Icons.calendar_today, size: 12, color: AppColors.textMuted(context)),
                                const SizedBox(width: 4),
                                Text(
                                  dateStr,
                                  style: TextStyle(
                                    color: AppColors.textMuted(context),
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                _buildStatusChip(context, booking['status'] ?? ''),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: Colors.grey),
                    ],
                  ),
                );
              },
            );
          },
          loading: () => const Center(child: Padding(
            padding: EdgeInsets.all(20),
            child: CircularProgressIndicator(),
          )),
          error: (error, _) => Text(
            'Error loading history',
            style: TextStyle(color: AppColors.redTint(context)),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusChip(BuildContext context, String status) {
    Color bgColor;
    Color textColor;

    switch (status.toLowerCase()) {
      case 'completed':
        bgColor = const Color(0xFFDCFCE7);
        textColor = const Color(0xFF16A34A);
        break;
      case 'cancelled':
        bgColor = const Color(0xFFFEE2E2);
        textColor = const Color(0xFFEF4444);
        break;
      case 'missed':
        bgColor = const Color(0xFFFEF9C3);
        textColor = const Color(0xFFCA8A04);
        break;
      default:
        bgColor = const Color(0xFFF1F5F9);
        textColor = const Color(0xFF64748B);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
          color: textColor,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

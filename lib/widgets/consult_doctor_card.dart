import 'package:flutter/material.dart';
import '../theme_colors.dart';
import 'safe_network_image.dart';

class ConsultDoctorCard extends StatelessWidget {
  final Map<String, dynamic> doctor;
  final VoidCallback onConsultNow;

  const ConsultDoctorCard({
    super.key,
    required this.doctor,
    required this.onConsultNow,
  });

  @override
  Widget build(BuildContext context) {
    final name = doctor['name'] ?? 'Unknown Doctor';
    final speciality = doctor['speciality'] ?? 'General Physician';
    final rating = doctor['rating']?.toString() ?? '0.0';
    final fee = doctor['first_consultation_fee']?.toString() ?? '0';
    final avatarUrl = doctor['avatar_url'];
    final bool isAvailable = true; // Placeholder for availability logic

    // Hospital data from join
    final hospitals = doctor['hospitals'];
    String hospitalName = 'Unknown Hospital';
    String location = 'Unknown Location';

    if (hospitals != null) {
      if (hospitals is Map) {
        hospitalName = hospitals['name'] ?? hospitalName;
        location = hospitals['location'] ?? location;
      } else if (hospitals is List && hospitals.isNotEmpty) {
        hospitalName = hospitals[0]['name'] ?? hospitalName;
        location = hospitals[0]['location'] ?? location;
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border(context)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    SafeAvatar(
                      url: avatarUrl,
                      radius: 30,
                      fallbackIcon: Icons.person,
                      backgroundColor: AppColors.surfaceBg(context),
                    ),
                    if (isAvailable)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.cardBg(context),
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary(context),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF3C7), // Amber 100
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.star,
                                  size: 14,
                                  color: Color(0xFFD97706), // Amber 600
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  rating,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFFD97706),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        speciality,
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.brandIndigo,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            Icons.local_hospital_rounded,
                            size: 14,
                            color: AppColors.textMuted(context),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              '$hospitalName • $location',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textMuted(context),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Consultation Fee',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'NPR $fee',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary(context),
                      ),
                    ),
                  ],
                ),
                ElevatedButton(
                  onPressed: onConsultNow,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brandIndigo,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Consult Now',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(width: 4),
                      Icon(Icons.arrow_forward_rounded, size: 16),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

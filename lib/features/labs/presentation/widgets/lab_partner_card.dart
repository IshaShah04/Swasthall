import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../theme_colors.dart';

class LabPartnerCard extends StatelessWidget {
  final Map<String, dynamic> lab;

  const LabPartnerCard({super.key, required this.lab});

  @override
  Widget build(BuildContext context) {
    final String name = lab['name'] ?? 'Unknown Lab';
    final String location = lab['location'] ?? 'Location not available';
    final String? avatarUrl = lab['avatar_url'];
    final num rating = lab['rating'] ?? 0.0;
    final int reviewCount = lab['review_count'] ?? 0;
    final int testCount = lab['test_count'] ?? 0;
    final bool isNabl = lab['is_nabl_accredited'] == true;
    final String? turnaroundHours = lab['turnaround_hours'];
    final bool homeCollection = lab['home_collection_available'] == true;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Image
          Container(
            height: 140,
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              image: avatarUrl != null && avatarUrl.isNotEmpty
                  ? DecorationImage(
                      image: NetworkImage(avatarUrl),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: avatarUrl == null || avatarUrl.isEmpty
                ? const Icon(Icons.local_hospital, size: 48, color: Colors.grey)
                : null,
          ),
          
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Row(
                      children: [
                        const Icon(Icons.star, color: Colors.amber, size: 18),
                        const SizedBox(width: 4),
                        Text(
                          '$rating ($reviewCount)',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                // Location
                Row(
                  children: [
                    Icon(Icons.location_on, size: 14, color: AppColors.textMuted(context)),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        location,
                        style: TextStyle(
                          color: AppColors.textMuted(context),
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                
                // Badges Row
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (testCount > 0) _buildBadge(context, Icons.science, '$testCount Tests'),
                    if (isNabl) _buildBadge(context, Icons.verified, 'NABL Accredited', color: Colors.green),
                    if (turnaroundHours != null && turnaroundHours.isNotEmpty)
                      _buildBadge(context, Icons.access_time, turnaroundHours),
                    if (homeCollection)
                      _buildBadge(context, Icons.home, 'Home Collection'),
                  ],
                ),
                const SizedBox(height: 16),
                
                // CTA
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      final id = lab['id'];
                      if (id != null) {
                        context.go('/hospital/$id');
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6366F1), // primaryIndigo
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('View Profile'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBadge(BuildContext context, IconData icon, String text, {Color color = const Color(0xFF6366F1)}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

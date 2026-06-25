import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/hospital_providers.dart';

class HospitalHeader extends ConsumerWidget {
  final Map<String, dynamic> hospital;

  const HospitalHeader({super.key, required this.hospital});

  Future<void> _launchMap() async {
    final lat = hospital['latitude'];
    final lng = hospital['longitude'];
    final location = hospital['address'] ?? hospital['location'] ?? hospital['name'];

    if (lat != null && lng != null) {
      final url = Uri.parse('geo:$lat,$lng');
      if (await canLaunchUrl(url)) {
        await launchUrl(url);
        return;
      }
    }
    
    final url = Uri.parse('https://maps.google.com/?q=${Uri.encodeComponent(location)}');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  Future<void> _launchPhone() async {
    final phone = hospital['contact_number'];
    if (phone != null) {
      final url = Uri.parse('tel:$phone');
      if (await canLaunchUrl(url)) {
        await launchUrl(url);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOpen24Hrs = hospital['is_open_24hrs'] == true;
    final isNabh = hospital['is_nabh_accredited'] == true;
    final beds = hospital['total_beds'];
    final hospitalId = hospital['id'] as String;
    
    // We use the doctorsAsync to get the count, or a separate provider
    final doctorsAsync = ref.watch(hospitalDoctorsProvider(hospitalId));
    final doctorsCount = doctorsAsync.valueOrNull?.length;
    
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            hospital['name'] ?? '',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isOpen24Hrs ? Colors.green.shade50 : Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: isOpen24Hrs ? Colors.green : Colors.blue,
                        ),
                      ),
                      child: Text(
                        isOpen24Hrs ? 'Open 24 Hours' : 'Open',
                        style: TextStyle(
                          color: isOpen24Hrs ? Colors.green : Colors.blue,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              if (hospital['avatar_url'] != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CachedNetworkImage(
                    imageUrl: hospital['avatar_url'],
                    width: 80,
                    height: 80,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      width: 80,
                      height: 80,
                      color: Colors.grey.shade200,
                      child: const Icon(Icons.local_hospital, color: Colors.grey),
                    ),
                    errorWidget: (context, url, error) => Container(
                      width: 80,
                      height: 80,
                      color: Colors.grey.shade200,
                      child: const Icon(Icons.local_hospital, color: Colors.grey),
                    ),
                  ),
                )
              else
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.local_hospital, color: Colors.grey),
                ),
            ],
          ),
          const SizedBox(height: 16),
          InkWell(
            onTap: _launchMap,
            child: Row(
              children: [
                const Icon(Icons.location_on_outlined, size: 20, color: Colors.grey),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    hospital['address'] ?? hospital['location'] ?? 'Location not available',
                    style: const TextStyle(color: Colors.black87),
                  ),
                ),
              ],
            ),
          ),
          if (hospital['contact_number'] != null) ...[
            const SizedBox(height: 12),
            InkWell(
              onTap: _launchPhone,
              child: Row(
                children: [
                  const Icon(Icons.phone_outlined, size: 20, color: Colors.grey),
                  const SizedBox(width: 8),
                  Text(
                    hospital['contact_number'],
                    style: const TextStyle(color: Colors.black87),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (isNabh)
                _buildStatChip(Icons.verified, 'NABH Accredited', Colors.amber.shade700),
              if (beds != null)
                _buildStatChip(Icons.bed, '$beds Beds', Colors.indigo),
              if (doctorsCount != null && doctorsCount > 0)
                _buildStatChip(Icons.people_alt, '$doctorsCount Doctors', Colors.teal),
              if (isOpen24Hrs)
                _buildStatChip(Icons.local_hospital, '24/7 Emergency', Colors.red),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

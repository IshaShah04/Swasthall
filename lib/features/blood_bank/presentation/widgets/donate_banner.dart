import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../providers/blood_bank_providers.dart';

class DonateBanner extends ConsumerStatefulWidget {
  const DonateBanner({super.key});

  @override
  ConsumerState<DonateBanner> createState() => _DonateBannerState();
}

class _DonateBannerState extends ConsumerState<DonateBanner> {
  final _supabase = Supabase.instance.client;
  bool _isSubmitting = false;

  void _showDonateForm(BuildContext context, Map<String, dynamic>? userDonationData) {
    String? selectedBloodType = userDonationData?['blood_group'];
    String? selectedHospitalId;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            final hospitalsAsync = ref.watch(hospitalsListProvider);
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 24,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Donate Blood', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: 'Blood Type', border: OutlineInputBorder()),
                    initialValue: selectedBloodType,
                    items: ['A+', 'A-', 'B+', 'B-', 'O+', 'O-', 'AB+', 'AB-']
                        .map((type) => DropdownMenuItem(value: type, child: Text(type)))
                        .toList(),
                    onChanged: (val) => setState(() => selectedBloodType = val),
                  ),
                  const SizedBox(height: 16),
                  hospitalsAsync.when(
                    data: (hospitals) => DropdownButtonFormField<String>(
                      decoration: const InputDecoration(labelText: 'Hospital', border: OutlineInputBorder()),
                      initialValue: selectedHospitalId,
                      items: hospitals
                          .map((h) => DropdownMenuItem<String>(
                                value: h['id'] as String,
                                child: Text(h['name'] as String),
                              ))
                          .toList(),
                      onChanged: (val) => setState(() => selectedHospitalId = val),
                    ),
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (e, st) => Text('Error loading hospitals: $e'),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _isSubmitting
                        ? null
                        : () async {
                            if (selectedBloodType == null || selectedHospitalId == null) return;
                            setState(() => _isSubmitting = true);
                            try {
                              await _supabase.from('blood_donations').insert({
                                'donor_id': _supabase.auth.currentUser!.id,
                                'blood_type': selectedBloodType,
                                'hospital_id': selectedHospitalId,
                              });
                              if (ctx.mounted) {
                                Navigator.pop(ctx);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Donation logged successfully!')),
                                );
                                ref.invalidate(myDonationsProvider);
                              }
                            } catch (e) {
                              if (ctx.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Error: $e')),
                                );
                              }
                            } finally {
                              if (mounted) setState(() => _isSubmitting = false);
                            }
                          },
                    child: _isSubmitting ? const CircularProgressIndicator(color: Colors.white) : const Text('Confirm Donation'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final userDonationData = ref.watch(myDonationsProvider).valueOrNull;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.shade100),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Donate Blood, Save Lives ❤️🔥',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.redAccent),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Your donation can bring hope to someone in need.',
                  style: TextStyle(color: Colors.black87),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => _showDonateForm(context, userDonationData),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Donate Blood'),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Icon(Icons.water_drop, size: 64, color: Colors.red.shade300),
        ],
      ),
    );
  }
}

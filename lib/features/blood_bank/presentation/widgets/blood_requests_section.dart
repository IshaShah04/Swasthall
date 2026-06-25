import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../providers/blood_bank_providers.dart';

class BloodRequestsSection extends ConsumerStatefulWidget {
  const BloodRequestsSection({super.key});

  @override
  ConsumerState<BloodRequestsSection> createState() => _BloodRequestsSectionState();
}

class _BloodRequestsSectionState extends ConsumerState<BloodRequestsSection> {
  final _supabase = Supabase.instance.client;
  bool _isSubmitting = false;

  void _showRequestForm(BuildContext context) {
    String selectedBloodType = 'A+';
    String? selectedHospitalId;
    double units = 1;
    String urgency = 'normal';

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
                  const Text('Request Blood', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: 'Blood Type', border: OutlineInputBorder()),
                    initialValue: selectedBloodType,
                    items: ['A+', 'A-', 'B+', 'B-', 'O+', 'O-', 'AB+', 'AB-']
                        .map((type) => DropdownMenuItem(value: type, child: Text(type)))
                        .toList(),
                    onChanged: (val) => setState(() => selectedBloodType = val!),
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
                  const SizedBox(height: 16),
                  Text('Units Needed: ${units.toInt()}'),
                  Slider(
                    value: units,
                    min: 1,
                    max: 5,
                    divisions: 4,
                    label: units.toInt().toString(),
                    onChanged: (val) => setState(() => units = val),
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: const Text('Urgent Request'),
                    value: urgency == 'urgent',
                    onChanged: (val) => setState(() => urgency = val ? 'urgent' : 'normal'),
                    activeThumbColor: Colors.redAccent,
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
                            if (selectedHospitalId == null) return;
                            setState(() => _isSubmitting = true);
                            try {
                              await _supabase.from('blood_requests').insert({
                                'requester_id': _supabase.auth.currentUser!.id,
                                'blood_type': selectedBloodType,
                                'hospital_id': selectedHospitalId,
                                'units_needed': units.toInt(),
                                'urgency': urgency,
                              });
                              if (ctx.mounted) {
                                Navigator.pop(ctx);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Request submitted successfully!')),
                                );
                                ref.invalidate(activeBloodRequestsProvider);
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
                    child: _isSubmitting ? const CircularProgressIndicator(color: Colors.white) : const Text('Submit Request'),
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
    final requestsAsync = ref.watch(activeBloodRequestsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Request Blood',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Need blood? Send a request and connect with donors.',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () {
                // Future expansion: full list
              },
              child: const Text('View All Requests'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        requestsAsync.when(
          data: (requests) {
            if (requests.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text('No active blood requests.'),
              );
            }
            return Column(
              children: requests.map((req) {
                final isUrgent = req['urgency'] == 'urgent';
                final timeAgo = req['created_at'] != null 
                    ? timeago.format(DateTime.parse(req['created_at'])) 
                    : '';
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    leading: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        req['blood_type'],
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent, fontSize: 16),
                      ),
                    ),
                    title: Text(req['hospital_display'] ?? 'Unknown Hospital', style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Row(
                        children: [
                          Icon(Icons.bloodtype, size: 16, color: Colors.redAccent),
                          const SizedBox(width: 4),
                          Text('${req['units_needed']} Units'),
                          const SizedBox(width: 16),
                          Icon(Icons.access_time, size: 16, color: Colors.blueAccent),
                          const SizedBox(width: 4),
                          Text(timeAgo),
                        ],
                      ),
                    ),
                    trailing: isUrgent
                        ? Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text('Urgent', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                          )
                        : const SizedBox.shrink(),
                  ),
                );
              }).toList(),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) => Text('Error: $e'),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _showRequestForm(context),
            icon: const Icon(Icons.add),
            label: const Text('+ Request Blood'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              foregroundColor: Colors.redAccent,
              side: const BorderSide(color: Colors.redAccent),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ],
    );
  }
}

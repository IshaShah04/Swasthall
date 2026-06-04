import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'plan_details_screen.dart';
import 'theme_colors.dart';

class InsuranceSubscription extends StatefulWidget {
  const InsuranceSubscription({super.key});

  @override
  State<InsuranceSubscription> createState() => _InsuranceSubscriptionState();
}

class _InsuranceSubscriptionState extends State<InsuranceSubscription> {
  final supabase = Supabase.instance.client;
  late Future<List<Map<String, dynamic>>> _plansFuture;

  @override
  void initState() {
    super.initState();
    _plansFuture = _fetchPlans();
  }

  Future<List<Map<String, dynamic>>> _fetchPlans() async {
    final data = await supabase
        .from('insurance_plans')
        .select()
        .order('created_at', ascending: false)
        .limit(2);
    return (data as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  Future<void> _refreshPlans() async {
    final future = _fetchPlans();
    if (mounted) {
      setState(() => _plansFuture = future);
    }
    await future;
  }

  Future<String?> _resolveIconUrl(String? raw) async {
    if (raw == null || raw.trim().isEmpty) return null;
    if (raw.startsWith('http')) return raw;
    try {
      return await supabase.storage
          .from('insurance_vault')
          .createSignedUrl(raw, 3600);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _plansFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildLoadingPlaceholder();
        }

        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return _buildNoPlanCard();
        }

        return Column(
          children: snapshot.data!
              .map((plan) => _buildPlanItem(context, plan))
              .toList(),
        );
      },
    );
  }

  Widget _buildPlanItem(BuildContext context, Map<String, dynamic> plan) {
    final String? rawIconUrl = plan['icon_url']?.toString();

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PlanDetailsScreen(plan: plan),
        ),
      ).then((_) => _refreshPlans()),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.cardBg(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFF1F5F9)),
          boxShadow: [
            BoxShadow(
              color: AppColors.shadow(context),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: FutureBuilder<String?>(
                future: _resolveIconUrl(rawIconUrl),
                builder: (context, urlSnapshot) {
                  final resolved = urlSnapshot.data;
                  if (resolved != null && resolved.isNotEmpty) {
                    return Image.network(
                      resolved,
                      height: 50,
                      width: 50,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _planIconFallback(),
                    );
                  }
                  return _planIconFallback();
                },
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(plan['name'] ?? '',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16)),
                  Text('Suggested for you',
                      style: TextStyle(
                          color: AppColors.textMuted(context), fontSize: 12)),
                ],
              ),
            ),
            Text(
              'Rs. ${plan['price']}',
              style: const TextStyle(
                  color: Color(0xFF10B981), fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _planIconFallback() => Container(
        height: 50,
        width: 50,
        decoration: BoxDecoration(
          color: AppColors.indigoTint(context),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.shield, color: Color(0xFF6366F1), size: 28),
      );

  Widget _buildLoadingPlaceholder() =>
      const Center(child: CircularProgressIndicator());

  Widget _buildNoPlanCard() => const Text('No plans found');
}

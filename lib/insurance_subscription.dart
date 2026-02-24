import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
// Import the new full screen

class InsuranceSubscription extends StatelessWidget {
  const InsuranceSubscription({super.key});

  @override
  Widget build(BuildContext context) {
    final supabase = Supabase.instance.client;

    return StreamBuilder<List<Map<String, dynamic>>>(
      // Logic: Fetch plans prioritized by hospitals with recent bookings
      // For now, we fetch the 2 most relevant plans
      stream: supabase
          .from('insurance_plans')
          .stream(primaryKey: ['id'])
          .order('created_at', ascending: false)
          .limit(2),
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
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  plan['icon_url'] ?? '',
                  height: 50,
                  width: 50,
                  fit: BoxFit.cover,
                  errorBuilder: (context, e, s) =>
                      const Icon(Icons.shield, color: Color(0xFF6366F1)),
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
                    const Text("Suggested for you",
                        style: TextStyle(color: Colors.grey, fontSize: 12)),
                  ],
                ),
              ),
              Text(
                "Rs. ${plan['price']}",
                style: const TextStyle(
                    color: Color(0xFF10B981), fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Helper widgets (_buildLoadingPlaceholder, _buildNoPlanCard) remain same as previous code...
  Widget _buildLoadingPlaceholder() =>
      const Center(child: CircularProgressIndicator());
  Widget _buildNoPlanCard() => const Text("No plans found");
}

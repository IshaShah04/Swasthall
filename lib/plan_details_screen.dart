import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PlanDetailsScreen extends StatelessWidget {
  final Map<String, dynamic> plan;

  const PlanDetailsScreen({super.key, required this.plan});

  @override
  Widget build(BuildContext context) {
    const Color brandBlue = Color(0xFF6366F1);
    final supabase = Supabase.instance.client;

    // We use a StreamBuilder here so if the hospital updates the plan,
    // the user sees the changes (price, description) immediately.
    return StreamBuilder<List<Map<String, dynamic>>>(
        stream: supabase
            .from('insurance_plans')
            .stream(primaryKey: ['id']).eq('id', plan['id']),
        builder: (context, snapshot) {
          // Fallback to the initial 'plan' passed via constructor if stream is loading
          final data = (snapshot.hasData && snapshot.data!.isNotEmpty)
              ? snapshot.data!.first
              : plan;

          final double price = double.tryParse(data['price'].toString()) ?? 0.0;
          final int discount = data['discount'] ?? 0;
          final double discountedPrice = price - (price * (discount / 100));

          // Assume hospital stores benefits as a List or comma-separated string
          final List<dynamic> benefits = data['benefits'] is List
              ? data['benefits']
              : (data['benefits']?.toString().split(',') ??
                  ["General Coverage", "Hospital Verified"]);

          return Scaffold(
            backgroundColor: Colors.white,
            body: CustomScrollView(
              slivers: [
                // 1. Interactive Header
                SliverAppBar(
                  expandedHeight: 250,
                  pinned: true,
                  backgroundColor: brandBlue,
                  flexibleSpace: FlexibleSpaceBar(
                    background: Hero(
                      tag: 'plan_icon_${data['id']}',
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.network(
                            data['icon_url'],
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                Container(color: Colors.grey[200]),
                          ),
                          const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.black45,
                                  Colors.transparent,
                                  Colors.black87
                                ],
                                stops: [0.0, 0.5, 1.0],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // 2. Details Content
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                data['name'],
                                style: const TextStyle(
                                    fontSize: 24, fontWeight: FontWeight.bold),
                              ),
                            ),
                            if (discount > 0) _buildDiscountBadge(discount),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.verified_user_rounded,
                                color: Colors.blue, size: 16),
                            const SizedBox(width: 4),
                            Text(
                              data['hospital_name'] ?? "Verified Hospital Plan",
                              style: const TextStyle(
                                  color: Colors.grey, fontSize: 13),
                            ),
                          ],
                        ),
                        const Divider(height: 40),

                        const Text("Description",
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 10),
                        Text(
                          data['description'] ?? "No description available.",
                          style: TextStyle(
                              color: Colors.grey[700],
                              height: 1.6,
                              fontSize: 15),
                        ),

                        const SizedBox(height: 30),
                        const Text("Plan Benefits",
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 15),

                        // DYNAMIC BENEFITS: Fetched directly from Hospital update
                        ...benefits.map((benefit) => _buildBenefitItem(
                              Icons.check_circle_rounded,
                              benefit.toString().trim(),
                            )),

                        const SizedBox(height: 120),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            // 3. Purchase Bottom Bar
            bottomSheet:
                _buildBottomBar(brandBlue, price, discount, discountedPrice),
          );
        });
  }

  Widget _buildDiscountBadge(int discount) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.green[50],
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        "-$discount% OFF",
        style: const TextStyle(
            color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12),
      ),
    );
  }

  Widget _buildBottomBar(
      Color brandBlue, double price, int discount, double discountedPrice) {
    return Container(
      height: 100,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, -4))
        ],
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (discount > 0)
                Text("Rs. ${price.toStringAsFixed(0)}",
                    style: const TextStyle(
                        decoration: TextDecoration.lineThrough,
                        color: Colors.grey,
                        fontSize: 12)),
              Text(
                "Rs. ${discountedPrice.toStringAsFixed(0)}",
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: brandBlue),
              ),
            ],
          ),
          const SizedBox(width: 20),
          Expanded(
            child: ElevatedButton(
              onPressed: () {
                // Implementation for purchase/subscription logic
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: brandBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              child: const Text("Purchase Now",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBenefitItem(IconData icon, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                shape: BoxShape.circle),
            child: Icon(icon, size: 18, color: const Color(0xFF6366F1)),
          ),
          const SizedBox(width: 12),
          Text(title,
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

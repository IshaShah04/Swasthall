import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'add_plan_screen.dart';
import 'widgets/safe_network_image.dart';
import 'theme_colors.dart';

class InsuranceScreen extends StatefulWidget {
  const InsuranceScreen({super.key});

  @override
  State<InsuranceScreen> createState() => _InsuranceScreenState();
}

class _InsuranceScreenState extends State<InsuranceScreen> {
  final supabase = Supabase.instance.client;
  late Future<List<Map<String, dynamic>>> _plansFuture;

  @override
  void initState() {
    super.initState();
    _plansFuture = _fetchPlans();
  }

  Future<List<Map<String, dynamic>>> _fetchPlans() async {
    final data = await supabase.from('insurance_plans').select();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cardBg(context),
      floatingActionButton: FloatingActionButton(
        heroTag: 'insurance_add_plan',
        backgroundColor: const Color(0xFF6366F1),
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const AddPlanScreen()),
        ).then((_) => _refreshPlans()),
      ),
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _plansFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return RefreshIndicator(
                    onRefresh: _refreshPlans,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.5,
                          child: Center(
                            child: Text('Error loading plans: ${snapshot.error}'),
                          ),
                        ),
                      ],
                    ),
                  );
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return RefreshIndicator(
                    onRefresh: _refreshPlans,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        SizedBox(
                          height: 320,
                          child: Center(child: Text("No plans added yet.")),
                        ),
                      ],
                    ),
                  );
                }

                final plans = snapshot.data!;
                return RefreshIndicator(
                  onRefresh: _refreshPlans,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Active Schemes",
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 16),
                        _buildDynamicGrid(plans),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 60, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Insurance Management",
              style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF134E4A))),
          const SizedBox(height: 16),
          TextField(
            decoration: InputDecoration(
              hintText: "Search your plans...",
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: AppColors.inputFill(context),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: BorderSide.none),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDynamicGrid(List<Map<String, dynamic>> plans) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 0.75,
      ),
      itemCount: plans.length,
      itemBuilder: (context, index) {
        final plan = plans[index];
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.cardBg(context),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFF3F4F6)),
            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  plan['icon_url'],
                  height: 50,
                  width: 50,
                  fit: BoxFit.cover,
                  loadingBuilder: (_, child, progress) =>
                      progress == null ? child : const ShimmerBox(width: 50, height: 50),
                  errorBuilder: (context, error, stackTrace) =>
                      const Icon(Icons.broken_image),
                ),
              ),
              const Spacer(),
              Text(plan['name'],
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(plan['description'],
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 11, color: AppColors.textMuted(context))),
              const SizedBox(height: 8),
              Text("Rs. ${plan['price']}",
                  style: const TextStyle(
                      color: Color(0xFF10B981),
                      fontWeight: FontWeight.bold)),
              if (plan['discount'] != null)
                Text("${plan['discount']}% Off",
                    style: const TextStyle(color: Colors.red, fontSize: 10)),
            ],
          ),
        );
      },
    );
  }
}

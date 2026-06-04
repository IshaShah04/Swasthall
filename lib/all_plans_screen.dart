import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'plan_details_screen.dart';
import 'widgets/safe_network_image.dart';
import 'theme_colors.dart';

class AllPlansScreen extends StatefulWidget {
  const AllPlansScreen({super.key});

  @override
  State<AllPlansScreen> createState() => _AllPlansScreenState();
}

class _AllPlansScreenState extends State<AllPlansScreen> {
  final supabase = Supabase.instance.client;
  late Future<List<Map<String, dynamic>>> _plansFuture;
  String searchQuery = "";

  @override
  void initState() {
    super.initState();
    _plansFuture = _fetchPlans();
  }

  Future<List<Map<String, dynamic>>> _fetchPlans() async {
    final data = await supabase
        .from('insurance_plans')
        .select('id, name, hospital_name, description, benefits, price, discount, icon_url, type')
        .limit(200);
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
    const Color brandBlue = Color(0xFF6366F1);

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg(context),
      appBar: AppBar(
        title: const Text(
          "Health Plans & Insurance",
          style: TextStyle(
            color: Color(0xFF1F2937),
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: AppColors.cardBg(context),
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: AppColors.textPrimary(context)),
      ),
      body: Column(
        children: [
          Container(
            color: AppColors.cardBg(context),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: TextField(
              onChanged: (val) =>
                  setState(() => searchQuery = val.toLowerCase()),
              decoration: InputDecoration(
                hintText: "Search by plan name...",
                prefixIcon:
                    const Icon(Icons.search_rounded, color: brandBlue),
                filled: true,
                fillColor: AppColors.inputFill(context),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
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

                final filteredData = snapshot.data?.where((plan) {
                      final name = plan['name'].toString().toLowerCase();
                      final hospital = plan['hospital_name']?.toString().toLowerCase() ?? '';
                      return name.contains(searchQuery) || hospital.contains(searchQuery);
                    }).toList() ??
                    [];

                if (filteredData.isEmpty) {
                  return RefreshIndicator(
                    onRefresh: _refreshPlans,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.5,
                          child: _buildEmptyState(),
                        ),
                      ],
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: _refreshPlans,
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    itemCount: filteredData.length,
                    itemBuilder: (context, index) {
                      final plan = filteredData[index];
                      return _buildWidePlanCard(context, plan);
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWidePlanCard(BuildContext context, Map<String, dynamic> plan) {
    final planId = plan['id'];
    final planImage = ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: () {
        final iconUrl = plan['icon_url']?.toString();
        return (iconUrl != null && iconUrl.isNotEmpty)
            ? Image.network(
                iconUrl,
                height: 64,
                width: 64,
                fit: BoxFit.cover,
                loadingBuilder: (_, child, progress) => progress == null
                    ? child
                    : const ShimmerBox(width: 64, height: 64),
                errorBuilder: (c, e, s) => Container(
                  height: 64,
                  width: 64,
                  color: AppColors.indigoTint(context),
                  child: const Icon(Icons.shield, color: Color(0xFF6366F1)),
                ),
              )
            : Container(
                height: 64,
                width: 64,
                color: AppColors.indigoTint(context),
                child: const Icon(Icons.shield, color: Color(0xFF6366F1)),
              );
      }(),
    );

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => PlanDetailsScreen(plan: plan)),
      ).then((_) => _refreshPlans()),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.cardBg(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.dividerColor(context)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Row(
          children: [
            planId == null
                ? planImage
                : Hero(
                    tag: 'plan_icon_$planId',
                    child: planImage,
                  ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    plan['name'] ?? 'Unknown Plan',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    plan['description'] ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: AppColors.textMuted(context), fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Rs. ${plan['price'] ?? '—'}",
                    style: const TextStyle(
                      color: Color(0xFF6366F1),
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: AppColors.textMuted(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off_rounded, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text("No plans found",
              style: TextStyle(color: AppColors.textMuted(context))),
        ],
      ),
    );
  }
}

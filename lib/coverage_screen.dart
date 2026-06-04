import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'plan_details_screen.dart'; 
import 'widgets/safe_network_image.dart';
import 'theme_colors.dart';

class CoverageScreen extends StatefulWidget {
  const CoverageScreen({super.key});

  @override
  State<CoverageScreen> createState() => _CoverageScreenState();
}

class _CoverageScreenState extends State<CoverageScreen> {
  final _supabase = Supabase.instance.client;
  final TextEditingController _searchController = TextEditingController();
  
  // Reusable Color Palette
  final Color primaryTeal = const Color(0xFF134E4A);
  final Color healingGreen = const Color(0xFF10B981);
  final Color brandIndigo = const Color(0xFF6366F1);

  String? _hospitalId;
  String _searchQuery = "";
  bool _isLoading = true;
  late Future<List<Map<String, dynamic>>> _plansFuture;

  @override
  void initState() {
    super.initState();
    _plansFuture = _fetchPlans();
    _initializeData();
    
    _searchController.addListener(() {
      if (mounted) {
        setState(() => _searchQuery = _searchController.text.toLowerCase());
      }
    });
  }

  /// Initial Fetch + Real-time Sync
  Future<void> _initializeData() async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      String? resolvedHospitalId;

      // Get hospital_id from staff table (matched by auth uid or email)
      final staffRes = await _supabase
          .from('staff')
          .select('hospital_id')
          .eq('id', user.id)
          .maybeSingle();

      resolvedHospitalId = staffRes?['hospital_id']?.toString();

      // Fallback: match by email (some staff rows use email as key)
      if (resolvedHospitalId == null || resolvedHospitalId == 'null') {
        final staffByEmail = await _supabase
            .from('staff')
            .select('hospital_id')
            .eq('email', user.email ?? '')
            .maybeSingle();

        resolvedHospitalId = staffByEmail?['hospital_id']?.toString();
      }

      if (mounted) {
        setState(() {
          _hospitalId = resolvedHospitalId;
          _isLoading = false;
        });
      }

    } catch (e) {
      debugPrint("Data Init Error: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }


  Future<List<Map<String, dynamic>>> _fetchPlans() async {
    final data = await _supabase
        .from('insurance_plans')
        .select('id, hospital_id, name, price, icon_url, type, plan_type, category')
        .order('price')
        .limit(200);
    return (data as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<void> _handleRefresh() async {
    final future = _fetchPlans();
    await _initializeData();
    if (mounted) {
      setState(() {
        _plansFuture = future;
      });
    }
    await future;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppColors.scaffoldBg(context),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.cardBg(context),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 60, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Protection Plans",
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: primaryTeal,
                        letterSpacing: -0.5,
                      ),
                    ),
                    CircleAvatar(
                      backgroundColor: const Color(0xFFF1F5F9),
                      child: Icon(Icons.history_rounded, color: AppColors.textMuted(context)),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildSearchBar(),
              ],
            ),
          ),

          Expanded(
            child: RefreshIndicator(
              onRefresh: _handleRefresh,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionHeader("Hospital Insurance", "Exclusive rates for your facility"),
                    const SizedBox(height: 16),
                    _buildDynamicPlanGrid(type: 'insurance'),
                    const SizedBox(height: 32),
                    _sectionHeader("Professional Subscriptions", "Enhance your practice"),
                    const SizedBox(height: 16),
                    _buildDynamicPlanGrid(type: 'subscription'),
                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDynamicPlanGrid({required String type}) {
    if (_hospitalId == null || _hospitalId == "null") {
      return _buildEmptyState(
        Icons.domain_disabled_rounded,
        "No Hospital Linked", 
        "Connect to a hospital to view protection plans.",
      );
    }

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _plansFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) return const Text('Could not load plans. Please try again.');
        if (!snapshot.hasData) return const Center(child: LinearProgressIndicator());

        final plans = snapshot.data!.where((p) {
          final planHospId = p['hospital_id']?.toString();
          final isFromHospital = planHospId == _hospitalId;
          final isCorrectType = p['plan_type'] == type;
          final matchesSearch = (p['name'] ?? "").toString().toLowerCase().contains(_searchQuery);
          
          return isFromHospital && isCorrectType && matchesSearch;
        }).toList();

        if (plans.isEmpty) {
          return _buildEmptyState(
            _searchQuery.isEmpty ? Icons.inventory_2_outlined : Icons.search_off_rounded,
            _searchQuery.isEmpty ? "No Plans Found" : "No matches for '$_searchQuery'",
            _searchQuery.isEmpty 
                ? "This hospital hasn't listed any $type plans yet."
                : "Try a different keyword.",
          );
        }

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 0.72,
          ),
          itemCount: plans.length,
          itemBuilder: (context, index) => _buildPlanCard(plans[index], index),
        );
      },
    );
  }

  Widget _buildPlanCard(Map<String, dynamic> plan, int index) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => PlanDetailsScreen(plan: plan)),
      ),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.cardBg(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.surfaceBg(context)),
          boxShadow: [
            BoxShadow(
              color: AppColors.shadow(context),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Hero(
              tag: 'plan_icon_${plan['id'] ?? index}',
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: brandIndigo.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: (plan['icon_url'] != null && plan['icon_url'].toString().isNotEmpty)
                  ? Image.network(plan['icon_url'], width: 24, height: 24,
                      loadingBuilder: (_, child, progress) =>
                          progress == null ? child : const ShimmerBox(width: 24, height: 24),
                      errorBuilder: (_, __, ___) => Icon(Icons.shield, color: brandIndigo, size: 24))
                  : Icon(Icons.shield_outlined, color: brandIndigo, size: 24),
              ),
            ),
            const Spacer(),
            Text(
              plan['name'] ?? "Unnamed Plan",
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              "Rs. ${plan['price'] ?? '-'}",
              style: TextStyle(color: healingGreen, fontWeight: FontWeight.bold, fontSize: 15),
            ),
            Text(
              plan['category'] ?? "General",
              style: TextStyle(color: AppColors.textMuted(context), fontSize: 10),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 32,
              child: ElevatedButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => PlanDetailsScreen(plan: plan)),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryTeal,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: EdgeInsets.zero,
                ),
                child: const Text("View Details", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        Text(subtitle, style: TextStyle(fontSize: 12, color: AppColors.textMuted(context))),
      ],
    );
  }

  Widget _buildEmptyState(IconData icon, String title, String sub) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
      decoration: BoxDecoration(
        color: AppColors.scaffoldBg(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.surfaceBg(context)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.textMuted(context), size: 40),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 4),
          Text(sub, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppColors.textMuted(context))),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return TextField(
      controller: _searchController,
      decoration: InputDecoration(
        hintText: "Search for plans...",
        prefixIcon: Icon(Icons.search_rounded, color: AppColors.textMuted(context)),
        filled: true,
        fillColor: AppColors.inputFill(context),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
import 'package:flutter/material.dart';
import 'widgets/safe_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'theme_colors.dart';

class ProfessionalLabScreen extends StatefulWidget {
  const ProfessionalLabScreen({super.key});

  @override
  State<ProfessionalLabScreen> createState() => _ProfessionalLabScreenState();
}

class _ProfessionalLabScreenState extends State<ProfessionalLabScreen> {
  final supabase = Supabase.instance.client;
  late Future<List<Map<String, dynamic>>> _labsFuture;

  final Color primaryColor = const Color(0xFF6366F1);
  final Color textDark = const Color(0xFF1E293B);

  @override
  void initState() {
    super.initState();
    _labsFuture = _fetchLabs();
  }

  Future<List<Map<String, dynamic>>> _fetchLabs() async {
    final data = await Supabase.instance.client
        .from('lab_tests')
        .select()
        .order('name');
    return (data as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  Future<void> _refreshLabs() async {
    final future = _fetchLabs();
    if (mounted) setState(() => _labsFuture = future);
    await future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cardBg(context),
      appBar: AppBar(
        backgroundColor: AppColors.cardBg(context),
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            Expanded(
              child: Container(
                height: 45,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceBg(context),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.search,
                        color: AppColors.textMuted(context), size: 20),
                    const SizedBox(width: 8),
                    Text(
                      "Search lab tests...",
                      style: TextStyle(
                          color: AppColors.textMuted(context), fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.black12),
                borderRadius: BorderRadius.circular(10),
              ),
              child:
                  Icon(Icons.tune, color: AppColors.textSecondary(context), size: 20),
            ),
          ],
        ),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _labsFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text("Error: ${snapshot.error}"));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final labs = snapshot.data!;

          return RefreshIndicator(
            onRefresh: _refreshLabs,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Popular Lab Tests",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: textDark,
                    ),
                  ),
                  const SizedBox(height: 16),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                      childAspectRatio: 0.78,
                    ),
                    itemCount: labs.length,
                    itemBuilder: (context, index) {
                      final test = labs[index];
                      return _buildLabCard(test);
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLabCard(Map<String, dynamic> test) {
    return Container(
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
          Center(
            child: Container(
              height: 60,
              width: 60,
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: ClipOval(
                child: Image.network(
                  test['image_url'] ??
                      "https://api.dicebear.com/7.x/shapes/svg?seed=${test['name']}",
                  fit: BoxFit.cover,
                  loadingBuilder: (_, child, progress) => progress == null
                      ? child
                      : const ShimmerBox(
                          width: 60, height: 60, borderRadius: 30),
                  errorBuilder: (context, error, stackTrace) =>
                      Icon(Icons.biotech, color: primaryColor),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            test['name'] ?? "Lab Test",
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: textDark,
              fontSize: 14,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            "\$${test['price']}",
            style: const TextStyle(
              color: Color(0xFF10B981),
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const Divider(height: 20),
          _infoRow(
            Icons.calendar_today_outlined,
            "Bookings: ${test['bookings'] ?? 0}",
          ),
          const SizedBox(height: 6),
          _infoRow(
            Icons.location_on_outlined,
            test['location'] ?? "Main Floor",
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label) {
    return Row(
      children: [
        Icon(icon, size: 14, color: const Color(0xFF94A3B8)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

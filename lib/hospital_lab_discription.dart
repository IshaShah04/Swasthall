import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'theme_colors.dart';

class LabTestDetailScreen extends StatefulWidget {
  final Map<String, dynamic> test;

  const LabTestDetailScreen({super.key, required this.test});

  @override
  State<LabTestDetailScreen> createState() => _LabTestDetailScreenState();
}

class _LabTestDetailScreenState extends State<LabTestDetailScreen> {
  final supabase = Supabase.instance.client;
  String searchQuery = "";
  int _currentImageIndex = 0; // Track gallery position

  late final Stream<List<Map<String, dynamic>>> _bookingStream;

  @override
  void initState() {
    super.initState();
    // SYNC: Ensure the ID is parsed correctly for the stream filter
    final dynamic rawId = widget.test['id'];
    
    _bookingStream = supabase
        .from('bookings')
        .stream(primaryKey: ['id'])
        .eq('test_id', rawId) // Matches the ID type from the lab_tests table
        .order('created_at', ascending: false);
  }

  @override
  Widget build(BuildContext context) {
    final List<dynamic> images = widget.test['images'] ?? [];
    final String testName = widget.test['name']?.toString() ?? "Test Details";
    final String location = widget.test['location']?.toString() ?? "No location provided";
    final String price = widget.test['price']?.toString() ?? "0";
    final String doInstructions = widget.test['do_instructions']?.toString() ?? "No instructions provided.";
    final String dontInstructions = widget.test['dont_instructions']?.toString() ?? "No instructions provided.";

    return Scaffold(
      backgroundColor: AppColors.cardBg(context),
      appBar: AppBar(
        title: Text(testName, style: TextStyle(color: AppColors.textPrimary(context), fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.cardBg(context),
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: AppColors.textPrimary(context)),
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _bookingStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Text("Error loading bookings"));
          
          final bookings = snapshot.data ?? [];
          final total = bookings.length;
          final done = bookings.where((b) => b['status'] == 'done').length;
          final missed = bookings.where((b) => b['status'] == 'missed').length;

          String currentNum = 'N/A';
          if (bookings.isNotEmpty) {
            final pending = bookings.firstWhere(
              (b) => b['status'] == 'pending',
              orElse: () => {'appointment_number': 'N/A'},
            );
            currentNum = pending['appointment_number']?.toString() ?? 'N/A';
          }

          final filteredBookings = bookings.where((b) {
            final patientName = b['patient_name']?.toString().toLowerCase() ?? "";
            return patientName.contains(searchQuery.toLowerCase());
          }).toList();

          return CustomScrollView(
            slivers: [
              // 1. IMPROVED Image Gallery Section
              SliverToBoxAdapter(
                child: Column(
                  children: [
                    SizedBox(
                      height: 220,
                      child: images.isEmpty
                          ? _buildNoImage()
                          : PageView.builder(
                              onPageChanged: (index) => setState(() => _currentImageIndex = index),
                              itemCount: images.length,
                              itemBuilder: (context, index) => _buildGalleryImage(images[index].toString()),
                            ),
                    ),
                    if (images.length > 1) _buildPageIndicator(images.length),
                  ],
                ),
              ),

              // 2. Info & Instructions
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(location, style: TextStyle(color: AppColors.textSecondary(context), fontSize: 14)),
                                Text("\$$price", style: const TextStyle(color: Color(0xFF6366F1), fontSize: 28, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                          _buildStatBadge("Current No.", "#$currentNum", const Color(0xFF6366F1)),
                        ],
                      ),
                      const SizedBox(height: 25),
                      _buildInstructionTile("What to DO", doInstructions, Colors.green),
                      const SizedBox(height: 12),
                      _buildInstructionTile("What NOT to DO", dontInstructions, Colors.red),
                      const Divider(height: 50),
                      const Text("Live Booking Stats", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 15),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildSimpleStat("Total", total.toString(), Colors.blue),
                          _buildSimpleStat("Done", done.toString(), Colors.green),
                          _buildSimpleStat("Missed", missed.toString(), Colors.red),
                        ],
                      ),
                      const SizedBox(height: 30),
                      TextField(
                        onChanged: (val) => setState(() => searchQuery = val),
                        decoration: InputDecoration(
                          hintText: "Search patient by name...",
                          prefixIcon: const Icon(Icons.search),
                          filled: true,
                          fillColor: AppColors.inputFill(context),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ),
                ),
              ),

              // 3. Appointment History List
              filteredBookings.isEmpty 
                ? const SliverToBoxAdapter(child: Center(child: Text("No booking history found")))
                : SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final b = filteredBookings[index];
                      final status = b['status']?.toString() ?? 'pending';
                      final apptNo = b['appointment_number']?.toString() ?? '?';
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: _getStatusColor(status).withValues(alpha: 0.1),
                          child: Text("#$apptNo", style: TextStyle(color: _getStatusColor(status), fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                        title: Text(b['patient_name']?.toString() ?? "Unknown", style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text("Status: ${status.toUpperCase()}"),
                        trailing: const Icon(Icons.chevron_right, size: 16),
                      );
                    }, childCount: filteredBookings.length),
                  ),
              const SliverToBoxAdapter(child: SizedBox(height: 50)),
            ],
          );
        },
      ),
    );
  }

  // --- HELPER WIDGETS ---

  Widget _buildGalleryImage(String url) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10, offset: const Offset(0, 5))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Image.network(
          url,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Icon(Icons.broken_image_outlined, color: AppColors.textMuted(context), size: 40),
        ),
      ),
    );
  }

  Widget _buildNoImage() {
    return Center(child: Icon(Icons.image_not_supported, size: 50, color: Colors.grey[300]));
  }

  Widget _buildPageIndicator(int count) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (index) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        width: _currentImageIndex == index ? 12 : 6,
        height: 6,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(3),
          color: _currentImageIndex == index ? const Color(0xFF6366F1) : Colors.grey[300],
        ),
      )),
    );
  }

  Widget _buildInstructionTile(String title, String content, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: color.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(content, style: TextStyle(fontSize: 13, height: 1.4, color: AppColors.textSecondary(context))),
        ],
      ),
    );
  }

  Widget _buildStatBadge(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(15)),
      child: Column(
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10)),
          Text(value, style: TextStyle(color: AppColors.cardBg(context), fontWeight: FontWeight.bold, fontSize: 18)),
        ],
      ),
    );
  }

  Widget _buildSimpleStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: TextStyle(color: AppColors.textMuted(context), fontSize: 12)),
      ],
    );
  }

  Color _getStatusColor(String status) {
    if (status == 'done') return Colors.green;
    if (status == 'missed') return Colors.red;
    return Colors.orange;
  }
}
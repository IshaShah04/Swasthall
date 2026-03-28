import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'theme_colors.dart';

class ProfessionalInsightsScreen extends StatefulWidget {
  const ProfessionalInsightsScreen({super.key});

  @override
  State<ProfessionalInsightsScreen> createState() =>
      _ProfessionalInsightsScreenState();
}

class _ProfessionalInsightsScreenState
    extends State<ProfessionalInsightsScreen> {
  final _supabase = Supabase.instance.client;

  static const Color _indigo = Color(0xFF6366F1);
  static const Color _green = Color(0xFF10B981);
  static const Color _red = Color(0xFFEF4444);

  String _selectedFilter = 'Today';
  bool _isLoading = true;

  int _completedCount = 0;
  int _cancelledCount = 0;
  double _avgRating = 0;
  int _avgDurationSeconds = 0;

  List<FlSpot> _chartSpots = [];

  List<Map<String, dynamic>> _reviews = [];

  @override
  void initState() {
    super.initState();
    _fetchAll();
  }

  DateTime get _fromDate {
    final now = DateTime.now();
    switch (_selectedFilter) {
      case 'Today':
        return DateTime(now.year, now.month, now.day);
      case 'Week':
        return now.subtract(const Duration(days: 7));
      case '15 Days':
        return now.subtract(const Duration(days: 15));
      default:
        return DateTime(now.year, now.month, 1);
    }
  }

  Future<void> _fetchAll() async {
    setState(() => _isLoading = true);
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) {
      setState(() => _isLoading = false);
      return;
    }
    try {
      await Future.wait([
        _fetchBookingStats(uid),
        _fetchReviewStats(uid),
      ]);
    } catch (e) {
      debugPrint('Insights fetch error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchBookingStats(String uid) async {
    final from = _fromDate.toIso8601String();

    // Single query using OR — covers both provider_id and staff_id columns.
    // Older bookings may only have staff_id set; newer ones use provider_id.
    // Using .or() returns all rows for this professional in one round-trip.
    final rows = await _supabase
        .from('bookings')
        .select('status, created_at')
        .or('provider_id.eq.$uid,staff_id.eq.$uid')
        .gte('created_at', from)
        .order('created_at');

    debugPrint('Insights bookings: ${rows.length} rows for uid=$uid');

    int completed = 0, cancelled = 0;
    final Map<int, double> dayTotals = {};

    for (final r in rows) {
      final status = r['status']?.toString() ?? '';
      if (status == 'completed') {
        completed++;
        final day = DateTime.parse(r['created_at']).day;
        dayTotals[day] = (dayTotals[day] ?? 0) + 1;
      } else if (status == 'cancelled') {
        cancelled++;
      }
    }

    _completedCount = completed;
    _cancelledCount = cancelled;

    if (dayTotals.isEmpty) {
      _chartSpots = [const FlSpot(0, 0), const FlSpot(1, 0)];
    } else {
      final sorted = dayTotals.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      _chartSpots = sorted
          .asMap()
          .entries
          .map((e) => FlSpot(e.key.toDouble(), e.value.value))
          .toList();
    }
  }

  Future<void> _fetchReviewStats(String uid) async {
    final from = _fromDate.toIso8601String();

    final rows = await _supabase
        .from('call_reviews')
        .select('rating, review_text, duration_seconds, created_at, patient_id')
        .eq('doctor_id', uid)
        .gte('created_at', from)
        .order('created_at', ascending: false);

    final ratedRows = rows.where((r) => r['rating'] != null).toList();
    _avgRating = ratedRows.isEmpty
        ? 0
        : ratedRows
                .map((r) => (r['rating'] as num).toDouble())
                .reduce((a, b) => a + b) /
            ratedRows.length;

    final durRows = rows
        .where((r) => r['duration_seconds'] != null && r['duration_seconds'] > 0)
        .toList();
    _avgDurationSeconds = durRows.isEmpty
        ? 0
        : (durRows
                    .map((r) => (r['duration_seconds'] as num).toInt())
                    .reduce((a, b) => a + b) /
                durRows.length)
            .round();

    _reviews = rows
        .where((r) => r['rating'] != null || r['review_text'] != null)
        .take(10)
        .toList();
  }

  String _formatDuration(int seconds) {
    if (seconds == 0) return '—';
    final m = seconds ~/ 60;
    if (m == 0) return '${seconds}s';
    return '${m}m';
  }

  String _filterLabel() {
    switch (_selectedFilter) {
      case 'Today':
        return "Today's Ratings";
      case 'Week':
        return "This Week's Ratings";
      case '15 Days':
        return "Last 15 Days Ratings";
      default:
        return "This Month's Ratings";
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg(context),
      appBar: AppBar(
        title: Text(
          "Performance Insights",
          style: TextStyle(color: AppColors.textPrimary(context), fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppColors.cardBg(context),
        elevation: 0,
        iconTheme: IconThemeData(color: AppColors.textPrimary(context)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _indigo))
          : RefreshIndicator(
              onRefresh: _fetchAll,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildFilterBar(),
                    const SizedBox(height: 24),
                    _buildStatsGrid(),
                    const SizedBox(height: 24),
                    _buildChartSection(),
                    const SizedBox(height: 24),
                    _buildReviewSection(),
                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildFilterBar() {
    return SizedBox(
      height: 45,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: ['Today', 'Week', '15 Days', 'Month'].map((f) {
          final isSelected = _selectedFilter == f;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(f),
              selected: isSelected,
              onSelected: (_) {
                setState(() => _selectedFilter = f);
                _fetchAll();
              },
              selectedColor: _indigo,
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : AppColors.textPrimary(context),
                fontWeight: FontWeight.bold,
              ),
              backgroundColor: AppColors.cardBg(context),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              side: BorderSide(
                color: isSelected ? _indigo : const Color(0xFFE2E8F0),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildStatsGrid() {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.4,
      children: [
        _statCard(
          "Completed",
          "$_completedCount",
          Icons.event_available,
          _indigo,
        ),
        _statCard(
          "Avg. Rating",
          _avgRating == 0 ? "—" : _avgRating.toStringAsFixed(1),
          Icons.star_rounded,
          Colors.amber,
        ),
        _statCard(
          "Cancelled",
          "$_cancelledCount",
          Icons.event_busy,
          _red,
        ),
        _statCard(
          "Avg. Call",
          _formatDuration(_avgDurationSeconds),
          Icons.timer_outlined,
          _green,
        ),
      ],
    );
  }

  Widget _statCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.surfaceBg(context)),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow(context),
            blurRadius: 8,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          ),
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChartSection() {
    return Container(
      height: 260,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.surfaceBg(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Consultation Trends",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              Text(
                "$_completedCount completed",
                style: const TextStyle(
                  color: _indigo,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: _chartSpots.every((s) => s.y == 0)
                ? Center(
                    child: Text(
                      "No completed consultations\nin this period",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textMuted(context), fontSize: 13),
                    ),
                  )
                : LineChart(
                    LineChartData(
                      gridData: const FlGridData(show: false),
                      titlesData: const FlTitlesData(show: false),
                      borderData: FlBorderData(show: false),
                      lineBarsData: [
                        LineChartBarData(
                          spots: _chartSpots,
                          isCurved: true,
                          color: _indigo,
                          barWidth: 4,
                          dotData: const FlDotData(show: false),
                          belowBarData: BarAreaData(
                            show: true,
                            color: _indigo.withValues(alpha: 0.08),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.surfaceBg(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _filterLabel(),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              Text(
                "${_reviews.length} reviews",
                style: const TextStyle(
                  color: _indigo,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_reviews.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  "No reviews yet in this period",
                  style: TextStyle(color: AppColors.textMuted(context), fontSize: 13),
                ),
              ),
            )
          else
            ..._reviews.map((r) => _reviewTile(r)),
        ],
      ),
    );
  }

  Widget _reviewTile(Map<String, dynamic> r) {
    final rating = r['rating'] as num?;
    final text = r['review_text']?.toString() ?? '';
    final duration = r['duration_seconds'] as int? ?? 0;
    final date = r['created_at'] != null
        ? DateTime.parse(r['created_at'].toString())
        : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: const Color(0xFFEEF2FF),
            child: const Icon(Icons.person, color: _indigo, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (rating != null)
                      Row(
                        children: List.generate(
                          5,
                          (i) => Icon(
                            i < rating.round()
                                ? Icons.star_rounded
                                : Icons.star_outline_rounded,
                            size: 14,
                            color: Colors.amber,
                          ),
                        ),
                      ),
                    const Spacer(),
                    Text(
                      duration > 0 ? _formatDuration(duration) : '',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted(context),
                      ),
                    ),
                  ],
                ),
                if (text.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    text,
                    style: const TextStyle(fontSize: 13),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (date != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    "${date.day}/${date.month}/${date.year}",
                    style: TextStyle(fontSize: 11, color: AppColors.textMuted(context)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
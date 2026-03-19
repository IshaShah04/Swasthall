import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ─────────────────────────────────────────────────────────────
//  RevenueScreen — reads from platform_transactions (consultation)
//  and from lab_appointments + insurance_subscriptions.
//
//  Consultation card now shows:
//    • Total Collected from Patients  (total_payable sum)
//    • Swasthall Fees (convenience + commission)
//    • Hospital Net Payout
//
//  Lab and Insurance cards keep existing queries until their
//  tables are also wired into platform_transactions.
// ─────────────────────────────────────────────────────────────

class RevenueScreen extends StatefulWidget {
  const RevenueScreen({super.key});

  @override
  State<RevenueScreen> createState() => _RevenueScreenState();
}

class _RevenueScreenState extends State<RevenueScreen> {
  final _supabase = Supabase.instance.client;

  static const Color _indigo  = Color(0xFF6366F1);
  static const Color _green   = Color(0xFF10B981);
  static const Color _pink    = Color(0xFFEC4899);
  static const Color _orange  = Color(0xFFF97316);
  static const Color _amber   = Color(0xFFF59E0B);

  String  _selectedFilter = 'Month';
  bool    _isLoading      = true;
  String? _hospitalId;

  // ── Consultation (from platform_transactions) ────────────
  double _ptTotalCollected   = 0;   // sum of total_payable
  double _ptConvenienceFees  = 0;   // sum of convenience_fee
  double _ptCommission       = 0;   // sum of commission_amount
  double _ptSwasthallRevenue = 0;   // convenience + commission
  double _ptHospitalPayout   = 0;   // sum of hospital_payout
  int    _ptBookingCount     = 0;
  List<FlSpot> _ptSpots      = [];

  // ── Lab (from lab_appointments) ──────────────────────────
  double _labRevenue  = 0;
  List<FlSpot> _labSpots = [];

  // ── Insurance (from insurance_subscriptions) ─────────────
  double _insuranceGross  = 0;
  double _insuranceClaims = 0;
  List<FlSpot> _insuranceSpots = [];

  @override
  void initState() {
    super.initState();
    _loadHospitalId();
  }

  // ── Resolve hospital id ──────────────────────────────────
  Future<void> _loadHospitalId() async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final profile = await _supabase
          .from('profiles')
          .select('hospital_id')
          .eq('id', user.id)
          .maybeSingle();

      String? hid = profile?['hospital_id']?.toString();

      if (hid == null || hid == 'null') {
        final staff = await _supabase
            .from('staff')
            .select('hospital_id')
            .eq('user_id', user.id)
            .maybeSingle();
        hid = staff?['hospital_id']?.toString();
      }

      // Fallback: treat user id itself as hospital id
      if (hid == null || hid == 'null') hid = user.id;

      _hospitalId = hid;
      await _fetchAll();
    } catch (e) {
      debugPrint('RevenueScreen hospital load error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  DateTime get _fromDate {
    final now = DateTime.now();
    switch (_selectedFilter) {
      case 'Day':      return DateTime(now.year, now.month, now.day);
      case 'Week':     return now.subtract(const Duration(days: 7));
      case '15 Days':  return now.subtract(const Duration(days: 15));
      default:         return DateTime(now.year, now.month, 1);
    }
  }

  Future<void> _fetchAll() async {
    if (_hospitalId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    try {
      await Future.wait([
        _fetchPlatformTransactions(),
        _fetchLabRevenue(),
        _fetchInsuranceRevenue(),
      ]);
    } catch (e) {
      debugPrint('Revenue fetch error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Consultation: platform_transactions ──────────────────
  Future<void> _fetchPlatformTransactions() async {
    final from = _fromDate.toIso8601String();

    try {
      final rows = await _supabase
          .from('platform_transactions')
          .select(
            'gross_amount, convenience_fee, commission_amount, '
            'total_payable, hospital_payout, created_at',
          )
          .eq('hospital_id', _hospitalId!)
          .eq('status', 'completed')
          .gte('created_at', from)
          .order('created_at');

      double collected = 0, convenience = 0, commission = 0, payout = 0;
      final Map<int, double> dayTotals = {};

      for (final r in rows) {
        final tp = _d(r['total_payable']);
        final cf = _d(r['convenience_fee']);
        final ca = _d(r['commission_amount']);
        final hp = _d(r['hospital_payout']);

        collected   += tp;
        convenience += cf;
        commission  += ca;
        payout      += hp;

        final day = DateTime.parse(r['created_at']).day;
        dayTotals[day] = (dayTotals[day] ?? 0) + tp;
      }

      _ptTotalCollected   = collected;
      _ptConvenienceFees  = convenience;
      _ptCommission       = commission;
      _ptSwasthallRevenue = convenience + commission;
      _ptHospitalPayout   = payout;
      _ptBookingCount     = rows.length;
      _ptSpots            = _toSpots(dayTotals);

    } catch (e) {
      // platform_transactions table may not exist yet — fall back
      // to reading from bookings directly
      debugPrint('platform_transactions fetch failed, falling back: $e');
      await _fetchConsultationFallback(from);
    }
  }

  // Fallback: bookings table (before migration is deployed)
  Future<void> _fetchConsultationFallback(String from) async {
    final rows = await _supabase
        .from('bookings')
        .select('consultation_fee, platform_fee, amount, created_at')
        .eq('hospital_id', _hospitalId!)
        .eq('status', 'completed')
        .gte('created_at', from)
        .order('created_at');

    double collected = 0, convenience = 0;
    final Map<int, double> dayTotals = {};

    for (final r in rows) {
      final cf = _d(r['consultation_fee']);
      final pf = _d(r['platform_fee']);
      final tp = cf + pf;
      collected   += tp;
      convenience += pf;
      final day = DateTime.parse(r['created_at']).day;
      dayTotals[day] = (dayTotals[day] ?? 0) + tp;
    }

    _ptTotalCollected   = collected;
    _ptConvenienceFees  = convenience;
    _ptSwasthallRevenue = convenience;
    _ptHospitalPayout   = collected - convenience;
    _ptBookingCount     = rows.length;
    _ptSpots            = _toSpots(dayTotals);
  }

  // ── Lab revenue ──────────────────────────────────────────
  Future<void> _fetchLabRevenue() async {
    final from = _fromDate.toIso8601String();

    final rows = await _supabase
        .from('lab_appointments')
        .select('total_amount, created_at')
        .eq('hospital_id', _hospitalId!)
        .inFilter('status', ['completed', 'scheduled'])
        .gte('created_at', from)
        .order('created_at');

    double total = 0;
    final Map<int, double> dayTotals = {};

    for (final r in rows) {
      final price = _d(r['total_amount']);
      total += price;
      final day = DateTime.parse(r['created_at']).day;
      dayTotals[day] = (dayTotals[day] ?? 0) + price;
    }

    _labRevenue = total;
    _labSpots   = _toSpots(dayTotals);
  }

  // ── Insurance revenue ────────────────────────────────────
  Future<void> _fetchInsuranceRevenue() async {
    final from = _fromDate.toIso8601String();

    final rows = await _supabase
        .from('insurance_subscriptions')
        .select('amount_paid, claim_amount, created_at')
        .eq('hospital_id', _hospitalId!)
        .gte('created_at', from)
        .order('created_at');

    double gross = 0, claims = 0;
    final Map<int, double> dayTotals = {};

    for (final r in rows) {
      final paid  = _d(r['amount_paid']);
      final claim = _d(r['claim_amount']);
      gross  += paid;
      claims += claim;
      final day = DateTime.parse(r['created_at']).day;
      dayTotals[day] = (dayTotals[day] ?? 0) + paid;
    }

    _insuranceGross  = gross;
    _insuranceClaims = claims;
    _insuranceSpots  = _toSpots(dayTotals);
  }

  // ── Helpers ──────────────────────────────────────────────
  List<FlSpot> _toSpots(Map<int, double> dayTotals) {
    if (dayTotals.isEmpty) {
      return [const FlSpot(0, 0), const FlSpot(1, 0)];
    }
    final sorted = dayTotals.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return sorted
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.value))
        .toList();
  }

  String _npr(double amount) {
    if (amount >= 100000) {
      return 'Rs. ${(amount / 100000).toStringAsFixed(1)}L';
    } else if (amount >= 1000) {
      return 'Rs. ${(amount / 1000).toStringAsFixed(1)}K';
    }
    return 'Rs. ${amount.toStringAsFixed(0)}';
  }

  static double _d(dynamic v) {
    if (v == null) return 0.0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  // ─────────────────────────────────────────────────────────
  //  BUILD
  // ─────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header + filter
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 60, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Financial Overview',
                style:
                    TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: ['Day', 'Week', '15 Days', 'Month'].map((label) {
                  final isSelected = label == _selectedFilter;
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedFilter = label;
                        _isLoading = true;
                      });
                      _fetchAll();
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? _indigo
                            : const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          color: isSelected
                              ? Colors.white
                              : Colors.black54,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),

        // Body
        Expanded(
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: _indigo))
              : _hospitalId == null
                  ? _emptyState()
                  : RefreshIndicator(
                      onRefresh: () async {
                        setState(() => _isLoading = true);
                        await _fetchAll();
                      },
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding:
                            const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          children: [
                            _buildConsultationCard(),
                            const SizedBox(height: 20),
                            _buildLabCard(),
                            const SizedBox(height: 20),
                            _buildInsuranceCard(),
                            const SizedBox(height: 30),
                          ],
                        ),
                      ),
                    ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────
  //  CARDS
  // ─────────────────────────────────────────────────────────

  Widget _buildConsultationCard() {
    return _baseCard(
      title: 'Consultation Revenue',
      icon: Icons.medical_services_outlined,
      child: Column(
        children: [
          // Summary chip row
          Row(
            children: [
              _chipStat(
                  '$_ptBookingCount',
                  'Bookings',
                  _indigo),
              const SizedBox(width: 10),
              _chipStat(
                  _npr(_ptTotalCollected),
                  'Collected',
                  _green),
            ],
          ),
          const SizedBox(height: 16),
          _lineChart(_ptSpots, [_indigo, _pink]),
          const SizedBox(height: 20),
          _row('Total Collected from Patients',
              _npr(_ptTotalCollected), isBold: true),
          const Divider(height: 20),
          _row('Convenience Fees (Swasthall)',
              _npr(_ptConvenienceFees), color: _indigo),
          _row('Commission Earned (Swasthall)',
              _npr(_ptCommission), color: _indigo),
          _row('Total Swasthall Revenue',
              _npr(_ptSwasthallRevenue),
              color: _indigo, isBold: true),
          const Divider(height: 20),
          _row('Hospital Net Payout',
              _npr(_ptHospitalPayout),
              color: _green, isBold: true),
        ],
      ),
    );
  }

  Widget _buildLabCard() {
    return _baseCard(
      title: 'Lab Test Revenue',
      icon: Icons.biotech_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Total Online Lab Booking Revenue',
              style:
                  TextStyle(color: Colors.black87, fontSize: 13)),
          const SizedBox(height: 10),
          _areaChart(_labSpots, _amber),
          const SizedBox(height: 20),
          _row('Total Lab Revenue', _npr(_labRevenue),
              color: _amber, isBold: true),
        ],
      ),
    );
  }

  Widget _buildInsuranceCard() {
    final net = _insuranceGross - _insuranceClaims;
    return _baseCard(
      title: 'Insurance & Subscription Revenue',
      icon: Icons.shield_outlined,
      child: Column(
        children: [
          _lineChart(_insuranceSpots, [_orange, _green]),
          const SizedBox(height: 20),
          _row('Total Subscriptions Sold',
              _npr(_insuranceGross), color: _green, isBold: true),
          _row('Insurance Claims Paid Out',
              '- ${_npr(_insuranceClaims)}', color: Colors.black54),
          const Divider(height: 16),
          _row('Net Revenue', _npr(net),
              color: _green, isBold: true),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  //  CHART HELPERS
  // ─────────────────────────────────────────────────────────

  Widget _lineChart(List<FlSpot> spots, List<Color> colors) {
    return SizedBox(
      height: 160,
      child: LineChart(LineChartData(
        gridData: const FlGridData(
            show: true, drawVerticalLine: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineBarsData: colors.asMap().entries.map((e) {
          final offset = e.key * 0.3;
          final shifted = spots
              .map((s) => FlSpot(
                  s.x,
                  (s.y * (1 + offset))
                      .clamp(0, double.infinity)))
              .toList();
          return LineChartBarData(
            spots: shifted,
            isCurved: true,
            color: e.value,
            barWidth: 2.5,
            dotData: const FlDotData(show: false),
          );
        }).toList(),
      )),
    );
  }

  Widget _areaChart(List<FlSpot> spots, Color color) {
    return SizedBox(
      height: 140,
      child: LineChart(LineChartData(
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: color,
            barWidth: 3,
            belowBarData: BarAreaData(
                show: true, color: color.withAlpha(30)),
            dotData: const FlDotData(show: false),
          ),
        ],
      )),
    );
  }

  // ─────────────────────────────────────────────────────────
  //  UI HELPERS
  // ─────────────────────────────────────────────────────────

  Widget _chipStat(String value, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: color.withAlpha(20),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: color)),
            Text(label,
                style: const TextStyle(
                    fontSize: 11, color: Colors.black54)),
          ],
        ),
      ),
    );
  }

  Widget _baseCard({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFF3F4F6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(title,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
              ),
              Icon(icon, color: Colors.grey, size: 20),
            ],
          ),
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }

  Widget _row(String label, String value,
      {Color? color, bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(label,
                style: TextStyle(
                    color: Colors.grey[700], fontSize: 13)),
          ),
          Text(value,
              style: TextStyle(
                color: color ?? Colors.black,
                fontWeight:
                    isBold ? FontWeight.bold : FontWeight.normal,
                fontSize: 15,
              )),
        ],
      ),
    );
  }

  Widget _emptyState() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bar_chart_outlined,
                size: 48, color: Colors.grey[300]),
            const SizedBox(height: 12),
            const Text('No hospital linked',
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(height: 4),
            const Text('Connect to a hospital to view revenue',
                style:
                    TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      );
}
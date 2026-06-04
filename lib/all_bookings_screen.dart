import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'theme_colors.dart';
import 'package:intl/intl.dart';

class AllBookingsScreen extends StatefulWidget {
  const AllBookingsScreen({super.key});

  @override
  State<AllBookingsScreen> createState() => _AllBookingsScreenState();
}

class _AllBookingsScreenState extends State<AllBookingsScreen> {
  final supabase = Supabase.instance.client;
  String patientSearch = '';
  String? _errorMessage;
  Stream<List<Map<String, dynamic>>> _bookingsStream = const Stream.empty();

  @override
  void initState() {
    super.initState();
    _resolveHospitalIdAndSetupStream();
  }


  DateTime? _parseAppointmentDateTime(Map<String, dynamic> row) {
    final date = (row['appointment_date'] ?? '').toString().trim();
    final time = (row['appointment_time'] ?? '').toString().trim();
    if (date.isEmpty || time.isEmpty) return null;

    final candidates = <String>[
      'yyyy-MM-dd hh:mm a',
      'yyyy-MM-dd h:mm a',
      'yyyy-MM-dd HH:mm',
      'yyyy-MM-dd HH:mm:ss',
    ];

    for (final pattern in candidates) {
      try {
        return DateFormat(pattern).parseStrict('$date $time');
      } catch (_) {}
    }

    return DateTime.tryParse('$date $time');
  }

  bool _shouldHideExpiredOrStaleScheduled(Map<String, dynamic> row) {
    final status = (row['status'] ?? '').toString().toLowerCase().trim();
    final isExpired = row['is_expired'] == true || status == 'expired';
    if (isExpired) return true;
    if (status != 'scheduled') return false;

    final appointmentAt = _parseAppointmentDateTime(row);
    if (appointmentAt == null) return false;

    return DateTime.now().isAfter(
      appointmentAt.add(const Duration(hours: 24)),
    );
  }

  /// Resolves the effective hospital/clinic owner id for the current account.

  /// Resolves the effective hospital/clinic owner id for the current account.
  /// Hospital/clinic accounts use auth.uid(); linked staff fall back to staff.hospital_id.
  Future<void> _resolveHospitalIdAndSetupStream() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    String? hospitalId;

    try {
      final profileRes = await supabase
          .from('profiles')
          .select('role')
          .eq('id', user.id)
          .maybeSingle();

      final role = (profileRes?['role'] ?? '').toString().trim().toLowerCase();

      if (role == 'hospital' || role == 'clinic') {
        hospitalId = user.id;
      }

      if (hospitalId == null || hospitalId.isEmpty || hospitalId == 'null') {
        final staffByUser = await supabase
            .from('staff')
            .select('hospital_id')
            .eq('user_id', user.id)
            .maybeSingle();
        hospitalId = staffByUser?['hospital_id']?.toString();
      }

      if ((hospitalId == null || hospitalId.isEmpty || hospitalId == 'null') &&
          (user.email?.trim().isNotEmpty ?? false)) {
        final staffByEmail = await supabase
            .from('staff')
            .select('hospital_id')
            .eq('email', user.email!.trim())
            .maybeSingle();
        hospitalId = staffByEmail?['hospital_id']?.toString();
      }
    } catch (e) {
      debugPrint('AllBookings: hospital_id resolve error: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load hospital bookings. Please try again.';
        });
      }
      return;
    }

    if (hospitalId == null || hospitalId.isEmpty || hospitalId == 'null') {
      if (mounted) {
        setState(() {
          _errorMessage = 'Hospital account not linked correctly.';
        });
      }
      return;
    }

    final resolvedHospitalId = hospitalId;
    if (!mounted) return;
    setState(() {
      _errorMessage = null;
      _bookingsStream = supabase
          .from('lab_appointments')
          .stream(primaryKey: ['id'])
          .eq('hospital_id', resolvedHospitalId)
          .order('created_at', ascending: false)
          .map((rows) => rows.where((row) => !_shouldHideExpiredOrStaleScheduled(row)).toList());
    });
  }

  // --- PDF GENERATION LOGIC ---
  Future<void> _generatePdf(Map<String, dynamic> booking) async {
    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a5,
        build: (pw.Context context) {
          return pw.Container(
            padding: const pw.EdgeInsets.all(20),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Center(
                  child: pw.Text("HOSPITAL LAB RECEIPT",
                      style: pw.TextStyle(
                          fontSize: 18, fontWeight: pw.FontWeight.bold)),
                ),
                pw.SizedBox(height: 10),
                pw.Divider(),
                pw.SizedBox(height: 10),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text("Date: ${booking['appointment_date'] ?? 'N/A'}"),
                    pw.Text("ID: ${booking['id']}"),
                  ],
                ),
                pw.SizedBox(height: 20),
                pw.Text("Patient Name:",
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                pw.Text("${booking['patient_name'] ?? 'Unknown'}"),
                pw.SizedBox(height: 10),
                pw.Text("Test(s):",
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                pw.Text("${booking['test_names'] ?? 'General Test'}"),
                pw.SizedBox(height: 15),
                pw.Text("Total Amount: ${booking['total_amount'] ?? '0.0'}"),
                pw.Text(
                    "Status: ${booking['status']?.toString().toUpperCase() ?? 'PENDING'}"),
                pw.SizedBox(height: 40),
                pw.Divider(),
                pw.Center(
                  child: pw.Text("Thank you for choosing our services!",
                      style: const pw.TextStyle(
                          fontSize: 10, color: PdfColors.grey)),
                ),
              ],
            ),
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Receipt_${_sanitizeFilename(booking['patient_name']?.toString() ?? 'Unknown')}',
    );
  }


  String _sanitizeFilename(String name) {
    final cleaned = name.replaceAll(RegExp(r'[:"/\|?*]+'), '_').trim();
    return cleaned.isEmpty ? 'Unknown' : cleaned;
  }

  String _buildScheduleLabel(Map<String, dynamic> booking) {
    final date = (booking['appointment_date'] ?? '').toString().trim();
    final time = (booking['appointment_time'] ?? '').toString().trim();
    if (date.isNotEmpty && time.isNotEmpty) return '$date | $time';
    if (date.isNotEmpty) return date;
    if (time.isNotEmpty) return time;
    return 'Schedule unavailable';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg(context),
      appBar: AppBar(
        title: Text("Hospital Lab Manager",
            style: TextStyle(
                color: AppColors.textPrimary(context),
                fontWeight: FontWeight.bold,
                fontSize: 18)),
        backgroundColor: AppColors.cardBg(context),
        elevation: 0.5,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: AppColors.textPrimary(context), size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          _buildSummaryHeader(),
          _buildSearchBar(),
          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Text(
                  _errorMessage!,
                  style: TextStyle(color: Colors.red.shade800),
                ),
              ),
            ),
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _bookingsStream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text("Sync Error: ${snapshot.error}"));
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                      child:
                          CircularProgressIndicator(color: Color(0xFF6366F1)));
                }

                final allData = snapshot.data ?? [];
                final filteredBookings = allData.where((b) {
                  final name =
                      b['patient_name']?.toString().toLowerCase() ?? '';
                  return name.contains(patientSearch.toLowerCase());
                }).toList();

                if (filteredBookings.isEmpty) return _buildEmptyState();

                return ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: filteredBookings.length,
                  itemBuilder: (context, index) =>
                      _buildBookingCard(filteredBookings[index]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
      child: TextField(
        onChanged: (val) => setState(() => patientSearch = val),
        decoration: InputDecoration(
          hintText: "Search patient name...",
          prefixIcon: const Icon(Icons.search, color: Color(0xFF6366F1)),
          filled: true,
          fillColor: AppColors.inputFill(context),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: BorderSide(color: AppColors.border(context))),
        ),
      ),
    );
  }

  Widget _buildSummaryHeader() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _bookingsStream,
      builder: (context, snapshot) {
        final data = snapshot.data ?? [];
        int total = data.length;
        int pending = data.where((b) => b['status'] == 'scheduled').length;

        return Container(
          padding: const EdgeInsets.all(16),
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: const Color(0xFF6366F1),
              borderRadius: BorderRadius.circular(20)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem("Total Appts", total.toString(),
                  Icons.local_hospital_outlined),
              Container(width: 1, height: 30, color: Colors.white24),
              _buildStatItem(
                  "Scheduled", pending.toString(), Icons.calendar_month),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: Colors.white70, size: 20),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18)),
            Text(label,
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
      ],
    );
  }

  Widget _buildBookingCard(Map<String, dynamic> booking) {
    String status = booking['status']?.toString() ?? 'scheduled';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: AppColors.shadow(context),
              blurRadius: 10,
              offset: const Offset(0, 4))
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: IntrinsicHeight(
          child: Row(
            children: [
              Container(width: 6, color: _getStatusColor(status)),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text((booking['patient_name'] ?? 'Unknown').toString(),
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 16)),
                            Text(booking['test_names'] ?? "Lab Test",
                                style: TextStyle(
                                    fontSize: 13, color: AppColors.textSecondary(context))),
                            Text(
                                _buildScheduleLabel(booking),
                                style: TextStyle(
                                    color: AppColors.textMuted(context), fontSize: 12)),
                            const SizedBox(height: 8),
                            _buildStatusBadge(status),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => _showPrintConfirmation(booking),
                        icon: const Icon(Icons.print_outlined,
                            color: Color(0xFF6366F1)),
                        style: IconButton.styleFrom(
                            backgroundColor:
                                const Color(0xFF6366F1).withValues(alpha: 0.1)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color color = _getStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20)),
      child: Text(status.toUpperCase(),
          style: TextStyle(
              color: color, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.assignment_late_outlined,
              size: 80, color: Colors.grey[300]),
          const SizedBox(height: 10),
          Text("No appointments found",
              style: TextStyle(color: AppColors.textMuted(context))),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return const Color(0xFF10B981);
      case 'scheduled':
        return const Color(0xFFF59E0B);
      case 'cancelled':
        return const Color(0xFFEF4444);
      default:
        return Colors.blueGrey;
    }
  }

  void _showPrintConfirmation(Map<String, dynamic> booking) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.receipt_long, size: 48, color: Color(0xFF6366F1)),
            const SizedBox(height: 16),
            Text("Print Receipt for ${(booking['patient_name'] ?? 'Unknown Patient').toString()}?",
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _generatePdf(booking);
                },
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12))),
                child: Text("Confirm & Print",
                    style: TextStyle(color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}



import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:barcode_widget/barcode_widget.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'lab_appointment.dart';
import 'theme_colors.dart';

class OrderSuccessScreen extends StatefulWidget {
  final String itemLabel;
  final String amount;
  final String type;
  final String storeName;
  final Map<String, dynamic> labData;
  final Map<String, dynamic>? extraDetails;

  const OrderSuccessScreen({
    super.key,
    required this.itemLabel,
    required this.amount,
    required this.storeName,
    required this.type,
    required this.labData,
    this.extraDetails,
  });

  @override
  State<OrderSuccessScreen> createState() => _OrderSuccessScreenState();
}

class _OrderSuccessScreenState extends State<OrderSuccessScreen> {
  bool _isProcessing = false;

  // SYNCED BRAND COLORS
  final Color primaryIndigo = const Color(0xFF6366F1);
  final Color bgLight = const Color(0xFFF1F5F9);

  bool _canModify() {
    try {
      final String? dateStr = widget.extraDetails?['date'];
      final String? timeStr = widget.extraDetails?['time'];

      if (dateStr == null || timeStr == null) return false;

      DateTime? appointmentDateTime;
      List<String> formats = [
        "dd MMM yyyy hh:mm a",
        "yyyy-MM-dd hh:mm a",
        "dd/MM/yyyy hh:mm a",
      ];

      for (var format in formats) {
        try {
          appointmentDateTime = DateFormat(format).parse("$dateStr $timeStr");
          break;
        } catch (_) {}
      }

      if (appointmentDateTime == null) return false;

      final difference = appointmentDateTime.difference(DateTime.now());
      return difference.inHours >= 24;
    } catch (e) {
      return false;
    }
  }

  Future<void> _cancelAppointment() async {
    final String? appointmentId = widget.extraDetails?['appointment_id']
        ?.toString();
    if (appointmentId == null) return;

    setState(() => _isProcessing = true);

    try {
      await Supabase.instance.client
          .from('lab_appointments')
          .update({'status': 'cancelled'})
          .eq('id', appointmentId);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("Appointment Cancelled Successfully"),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
      Navigator.popUntil(context, (route) => route.isFirst);
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<Uint8List> _generatePdf() async {
    final pdf = pw.Document();
    final String appointmentId =
        widget.extraDetails?['appointment_id']?.toString() ?? "REF-PENDING";

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Padding(
            padding: const pw.EdgeInsets.all(40),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      widget.storeName,
                      style: pw.TextStyle(
                        fontSize: 24,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      "OFFICIAL RECEIPT",
                      style: pw.TextStyle(
                        fontSize: 14,
                        color: PdfColors.grey600,
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 10),
                pw.Divider(thickness: 1, color: PdfColors.grey300),
                pw.SizedBox(height: 30),
                pw.Text(
                  "Service Summary",
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 10),
                pw.Bullet(text: "Patient ID: $appointmentId"),
                pw.Bullet(text: "Tests: ${widget.itemLabel}"),
                pw.Bullet(text: "Amount Paid: Rs. ${widget.amount}"),
                pw.Bullet(
                  text:
                      "Schedule: ${widget.extraDetails?['date']} at ${widget.extraDetails?['time']}",
                ),
                pw.SizedBox(height: 40),
                pw.Container(
                  padding: const pw.EdgeInsets.all(15),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.indigo50,
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        "Instructions:",
                        style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.indigo900,
                        ),
                      ),
                      pw.SizedBox(height: 5),
                      pw.Text(
                        "Please arrive 15 minutes before your time slot. Fasting may be required depending on the test type. Present this receipt at the front desk.",
                        style: pw.TextStyle(
                          fontSize: 10,
                          color: PdfColors.indigo900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
    return pdf.save();
  }

  @override
  Widget build(BuildContext context) {
    bool isLab = widget.type == "Lab";
    final String appointmentId =
        widget.extraDetails?['appointment_id']?.toString() ?? "REF-PENDING";
    final bool modificationAllowed = _canModify();

    return Scaffold(
      backgroundColor: bgLight,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 240,
            pinned: true,
            automaticallyImplyLeading: false,
            backgroundColor: primaryIndigo,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      primaryIndigo,
                      primaryIndigo.withValues(alpha: 0.8),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.check_circle_rounded,
                      color: Colors.white,
                      size: 85,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      isLab ? "Booking Confirmed" : "Order Successful",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        "REF ID: $appointmentId",
                        style: TextStyle(
                          color: AppColors.cardBg(context),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Transform.translate(
              offset: const Offset(0, -35),
              child: Column(
                children: [
                  _buildReceiptCard(context, appointmentId),
                  const SizedBox(height: 20),
                  if (isLab) ...[
                    _buildManagementButtons(modificationAllowed),
                    _buildQrSection(appointmentId),
                  ],
                  const SizedBox(height: 30),
                  _buildDoneButton(context),
                  const SizedBox(height: 60),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildManagementButtons(bool allowed) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _actionButton(
                  onPressed: !allowed || _isProcessing
                      ? null
                      : () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => LabAppointmentScreen(
                                labData: widget.labData,
                                rescheduleAppointmentId: widget
                                    .extraDetails?['appointment_id']
                                    ?.toString(),
                              ),
                            ),
                          );
                        },
                  icon: Icons.edit_calendar_rounded,
                  label: "Reschedule",
                  color: primaryIndigo,
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: _actionButton(
                  onPressed: !allowed || _isProcessing
                      ? null
                      : _showCancelDialog,
                  icon: Icons.cancel_outlined,
                  label: "Cancel",
                  color: Colors.redAccent,
                ),
              ),
            ],
          ),
          if (!allowed)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 16,
                    color: Colors.orange[700],
                  ),
                  const SizedBox(width: 6),
                  Text(
                    "Locked: Changes allowed 24h before.",
                    style: TextStyle(
                      color: Colors.orange[800],
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required VoidCallback? onPressed,
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(vertical: 16),
        side: BorderSide(
          color: onPressed != null
              ? color.withValues(alpha: 0.5)
              : Colors.grey[300]!,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        disabledForegroundColor: Colors.grey[400],
      ),
    );
  }

  void _showCancelDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text(
          "Cancel Booking?",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: const Text(
          "Refunds for online payments are processed within 3-5 working days. Do you wish to proceed?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Keep Booking"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _cancelAppointment();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              elevation: 0,
            ),
            child: Text(
              "Cancel Appointment",
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReceiptCard(BuildContext context, String id) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow(context),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          _infoRow("Lab Provider", widget.storeName),
          _infoRow("Selected Tests", widget.itemLabel),
          _infoRow("Date", widget.extraDetails?['date'] ?? 'N/A'),
          _infoRow("Time Slot", widget.extraDetails?['time'] ?? 'N/A'),
          _infoRow(
            "Payment Status",
            widget.extraDetails?['status'] ?? 'Paid',
            isStatus: true,
          ),
          Padding(
            padding: EdgeInsets.symmetric(vertical: 15),
            child: Divider(),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Total Amount",
                style: TextStyle(
                  color: AppColors.textSecondary(context),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                "Rs. ${widget.amount}",
                style: TextStyle(
                  color: primaryIndigo,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _utilityIcon(Icons.file_download_rounded, "Receipt", () async {
                final bytes = await _generatePdf();
                await Printing.layoutPdf(onLayout: (format) => bytes);
              }),
              _utilityIcon(Icons.ios_share_rounded, "Share", () async {
                final bytes = await _generatePdf();
                await Printing.sharePdf(
                  bytes: bytes,
                  filename: 'receipt_$id.pdf',
                );
              }),
            ],
          ),
        ],
      ),
    );
  }

  Widget _utilityIcon(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: primaryIndigo.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: primaryIndigo, size: 22),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              color: primaryIndigo,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value, {bool isStatus = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: AppColors.textMuted(context),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          // Replace the isStatus logic in _infoRow with this:
      isStatus
        ? Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              // Logic: Orange for "Pay at Lab", Green for "Paid"
              color: (value.contains('Pay') ? Colors.orange : Colors.green).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              value,
              style: TextStyle(
                color: value.contains('Pay') ? Colors.orange[800] : Colors.green,
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
            ),
          )
        : Flexible(
                  child: Text(
                    value,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  Widget _buildQrSection(String id) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white, // QR container always light so barcode is scannable
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.indigo.withValues(alpha: 0.05)),
      ),
      child: Column(
        children: [
          Text(
            "APPOINTMENT PASS",
            style: TextStyle(
              fontSize: 12,
              letterSpacing: 1.5,
              fontWeight: FontWeight.w800,
              color: Colors.black54, // Fixed: always dark on white QR card
            ),
          ),
          const SizedBox(height: 25),
          BarcodeWidget(
            barcode: Barcode.qrCode(),
            data: id,
            width: 150,
            height: 150,
            color: Colors.black, // Fixed: always dark for scannable QR
          ),
          const SizedBox(height: 20),
          Text(
            "Fast check-in via QR at reception",
            style: const TextStyle(
              color: Colors.black87,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDoneButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: ElevatedButton(
        onPressed: () => Navigator.popUntil(context, (route) => route.isFirst),
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryIndigo,
          minimumSize: const Size(double.infinity, 58),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          elevation: 0,
        ),
        child: Text(
          "Return to Dashboard",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ),
    );
  }
}

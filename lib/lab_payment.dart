// lib/lab_payment.dart
//
// Changes from original:
//  • _processPayment() now runs the gateway FIRST, then inserts to DB.
//  • eSewa: calls edge functions → Custom Tabs/browser redirect → verify/poll → save.
//  • FonePay mock: dialog → confirm → save with payment_method='fonepay_mock'.
//  • Khalti / IME Pay removed per project requirements.
//  • No secrets in this file.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'order_success_screen.dart';
import 'services/booking_fee_service.dart';
import 'services/esewa_sdk_payment_service.dart';
import 'services/khalti_sdk_payment_service.dart';
import 'services/fonepay_mock_service.dart';
import 'theme_colors.dart';
import 'package:qr_flutter/qr_flutter.dart';

class LabPaymentScreen extends StatefulWidget {
  final Map<String, dynamic> labData;
  final List<Map<String, dynamic>> selectedTests;
  final double totalAmount;
  final DateTime selectedDate;
  final String selectedTime;

  const LabPaymentScreen({
    super.key,
    required this.labData,
    required this.selectedTests,
    required this.totalAmount,
    required this.selectedDate,
    required this.selectedTime,
  });

  @override
  State<LabPaymentScreen> createState() => _LabPaymentScreenState();
}

class _LabPaymentScreenState extends State<LabPaymentScreen> {
  String _selectedMethod = 'esewa';
  String? _verifiedPaymentProvider;
  String? _verifiedPaymentKey;


  final Color primaryIndigo = const Color(0xFF6366F1);

  BookingFeeBreakdown? _feeBreakdown;
  bool _feeLoading = true;
  bool _isProcessing = false;
  String? _feeError;

  @override
  void initState() {
    super.initState();
    _loadFeeBreakdown();
  }

  String _resolveHospitalId() {
    final rawHospitalId = widget.labData['hospital_id'] ??
        (widget.selectedTests.isNotEmpty
            ? widget.selectedTests.first['hospital_id']
            : null);
    final hospitalId = rawHospitalId?.toString().trim() ?? '';
    return (hospitalId.isEmpty || hospitalId == 'null') ? '' : hospitalId;
  }

  Future<void> _loadFeeBreakdown() async {
    if (mounted) {
      setState(() {
        _feeLoading = true;
        _feeError = null;
      });
    }
    try {
      final hospitalId = _resolveHospitalId();
      if (hospitalId.isEmpty) {
        debugPrint('Lab fee load error: Hospital ID could not be determined');
        if (mounted) {
          setState(() {
            _feeLoading = false;
            _feeBreakdown = null;
            _feeError = 'Could not determine hospital fee settings.';
          });
        }
        return;
      }
      final breakdown = await BookingFeeService.forLab(
        hospitalId: hospitalId,
        baseAmount: widget.totalAmount,
      );
      if (mounted) {
        setState(() {
          _feeBreakdown = breakdown;
          _feeLoading = false;
          _feeError = null;
        });
      }
    } catch (e) {
      debugPrint('Lab fee load error: $e');
      if (mounted) {
        setState(() {
          _feeBreakdown = null;
          _feeLoading = false;
          _feeError = 'Could not load fees. Please try again.';
        });
      }
    }
  }

  double? get _convenienceFee => _feeBreakdown?.convenienceFee;
  double? get _totalPayable => _feeBreakdown?.totalPayable;
  bool get _canPay => !_feeLoading && !_isProcessing && _feeBreakdown != null && _feeError == null;

  // ── Master pay handler ─────────────────────────────────────────────────────

  Future<void> _processPayment() async {
    final totalPayable = _totalPayable;
    if (!_canPay || totalPayable == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Fees are not ready yet. Please retry loading fees.'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ));
      }
      return;
    }

    _verifiedPaymentProvider = null;
    _verifiedPaymentKey = null;

    // Step 1: Run gateway first — only create appointment after success
    final paymentOk = await _runSelectedGateway();
    if (!paymentOk) return;
    if (!mounted) return;

    // Step 2: Save lab appointment
    setState(() => _isProcessing = true);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(
          child: CircularProgressIndicator(color: primaryIndigo)),
    );

    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) {
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
            'Your session expired after payment. Please contact support with your payment details.',
          ),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 8),
        ));
      }
      if (mounted) {
        setState(() => _isProcessing = false);
      }
      return;
    }

    try {
      final labTestIds = widget.selectedTests
          .map((e) => (e['id'] ?? e['lab_test_id'] ?? '').toString().trim())
          .where((e) => e.isNotEmpty && e.toLowerCase() != 'null')
          .toList(growable: false);

      if (labTestIds.isEmpty) {
        throw Exception('Selected lab test IDs are missing. Please reselect tests.');
      }

      final technicianIds = widget.selectedTests
          .map((e) => (e['technician_id'] ?? e['professional_id'] ?? e['provider_id'] ?? '').toString().trim())
          .where((e) => e.isNotEmpty && e.toLowerCase() != 'null')
          .toSet();

      if (technicianIds.isEmpty) {
        throw Exception('No technician assigned for selected test(s).');
      }
      if (technicianIds.length > 1) {
        throw Exception(
          'Selected tests are assigned to different technicians. '
          'Please book them separately.',
        );
      }

      final String professionalId = technicianIds.first;
      final String hospitalId = _resolveHospitalId();
      if (hospitalId.isEmpty) {
        throw Exception('Hospital ID could not be determined.');
      }

      final responseRaw = await supabase.rpc(
        'create_lab_appointment_after_payment',
        params: {
          'p_hospital_id': hospitalId,
          'p_professional_id': professionalId,
          'p_lab_test_ids': labTestIds,
          'p_appointment_date': DateFormat('yyyy-MM-dd').format(widget.selectedDate),
          'p_appointment_time': widget.selectedTime,
          'p_payment_method': _selectedMethod,
          'p_payment_provider': _verifiedPaymentProvider,
          'p_payment_key': _verifiedPaymentKey,
        },
      );

      final response = Map<String, dynamic>.from(
        (responseRaw as Map?) ?? <String, dynamic>{},
      );

      if (response['appointment_id'] == null) {
        throw Exception('Appointment not created — please try again.');
      }

      final String testNames = response['test_names']?.toString().trim().isNotEmpty == true
          ? response['test_names'].toString()
          : widget.selectedTests
              .map((e) => e['test_name'] ?? e['name'] ?? 'Test')
              .join(', ');
      final double paidAmount = double.tryParse(
            response['total_amount']?.toString() ?? '',
          ) ??
          totalPayable;

      if (!mounted) return;
      Navigator.of(context).pop(); // close loading dialog

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (context) => OrderSuccessScreen(
            itemLabel: testNames,
            amount: paidAmount.toStringAsFixed(0),
            storeName: widget.labData['full_name'] ?? 'Lab Center',
            type: 'Lab',
            labData: widget.labData,
            extraDetails: {
              'date': DateFormat('dd MMM yyyy').format(widget.selectedDate),
              'time': widget.selectedTime,
              'appointment_id': response['appointment_id'].toString(),
              'status': 'Paid',
            },
          ),
        ),
        (route) => route.isFirst,
      );
    } catch (e, st) {
      debugPrint('Lab appointment insert error: $e');
      debugPrint(st.toString());
      if (mounted) {
        Navigator.of(context).pop(); // close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not complete booking. Please try again or contact support.'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ── Gateway router ─────────────────────────────────────────────────────────

  Future<bool> _runSelectedGateway() async {
    switch (_selectedMethod) {
      case 'esewa':
        return _runEsewa();
      case 'khalti':
        return _runKhalti();
      case 'fonepay':
        return _runFonePayMock();
      default:
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Payment method not supported yet.'),
          behavior: SnackBarBehavior.floating,
        ));
        return false;
    }
  }

  // ── eSewa Custom Tabs / browser flow ───────────────────────────────────────
  Future<bool> _runEsewa() async {
    final totalPayable = _totalPayable;
    if (!_canPay || totalPayable == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Fees are not ready yet. Please retry loading fees.'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ));
      }
      return false;
    }

    setState(() => _isProcessing = true);
    try {
      final result = await EsewaSdkPaymentService.start(
        amount: totalPayable,
        productName: 'Lab Tests - ${widget.selectedTests.length}',
        productIdSeed: 'LAB_${widget.selectedDate.millisecondsSinceEpoch}_${widget.selectedTests.length}',
        orderType: 'lab',
      );

      if (!result.isComplete) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
              result.error ??
                  'Payment could not be confirmed (status: ${result.status}).',
            ),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ));
        }
        return false;
      }

      _verifiedPaymentProvider = 'esewa';
      _verifiedPaymentKey = result.transactionUuid.isNotEmpty
          ? result.transactionUuid
          : result.transactionCode;

      debugPrint(
        '✅ eSewa SDK verified: txn=${result.transactionCode} '
        'amount=${result.totalAmount} '
        'uuid=${result.transactionUuid}',
      );
      return true;
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }


Future<bool> _runKhalti() async {
  final totalPayable = _totalPayable;
  if (totalPayable == null) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Could not load the booking fee. Please try again.'),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
      ));
    }
    return false;
  }

  setState(() => _isProcessing = true);
  try {
    final user = Supabase.instance.client.auth.currentUser;
    final result = await KhaltiSdkPaymentService.start(
      context: context,
      amount: totalPayable,
      orderType: 'lab',
      orderIdSeed: 'LAB_${widget.selectedDate.millisecondsSinceEpoch}_${widget.selectedTests.length}',
      productName: 'Lab Tests - ${widget.selectedTests.length}',
      customerName: user?.userMetadata?['full_name']?.toString(),
      customerEmail: user?.email,
      customerPhone: user?.phone,
    );

    if (!result.isComplete) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            result.error ??
                'Khalti payment could not be confirmed (status: ${result.status}).',
          ),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ));
      }
      return false;
    }

    _selectedMethod = 'khalti';
    _verifiedPaymentProvider = 'khalti';
    _verifiedPaymentKey = result.pidx.isNotEmpty
        ? result.pidx
        : result.transactionCode;

    debugPrint(
      '✅ Khalti verified: txn=${result.transactionCode} '
      'amount=${result.totalAmount} '
      'pidx=${result.pidx}',
    );
    return true;
  } finally {
    if (mounted) setState(() => _isProcessing = false);
  }
}

  // ── FonePay mock flow ──────────────────────────────────────────────────────

  Future<bool> _runFonePayMock() async {
    final totalPayable = _totalPayable;
    if (!_canPay || totalPayable == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Fees are not ready yet. Please retry loading fees.'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ));
      }
      return false;
    }

    final result = await FonePayMockService.showMockDialog(
      context,
      amount: totalPayable,
    );
    if (!result.confirmed) return false;
    _selectedMethod = result.paymentMethod; // 'fonepay_mock'
    _verifiedPaymentProvider = null;
    _verifiedPaymentKey = null;
    return true;
  }

  // ── UI ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg(context),
      appBar: AppBar(
        title: Text(
          'Payment Details',
          style: TextStyle(
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary(context)),
        ),
        backgroundColor: AppColors.cardBg(context),
        elevation: 0,
        iconTheme: IconThemeData(color: AppColors.textPrimary(context)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSummaryCard(),
            const SizedBox(height: 24),
            const Text('Payment Method',
                style:
                    TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _buildPaymentMethod(
              id: 'esewa',
              name: 'eSewa',
              subtitle: 'Sandbox – test payments',
              color: const Color(0xFF60BB46),
              icon: Icons.account_balance_wallet_rounded,
            ),
            _buildPaymentMethod(
              id: 'khalti',
              name: 'Khalti',
              subtitle: 'Ready – add server secret to enable',
              color: const Color(0xFF5C2D91),
              icon: Icons.payments_rounded,
              readySoon: true,
            ),
            _buildPaymentMethod(
              id: 'fonepay',
              name: 'FonePay',
              subtitle: 'Mock test mode',
              color: const Color(0xFF6A1B9A),
              icon: Icons.qr_code_scanner_rounded,
              isMock: true,
            ),
          ],
        ),
      ),
      bottomSheet: _buildPayButton(),
    );
  }

  Widget _buildSummaryCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: AppColors.shadow(context), blurRadius: 8),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.labData['full_name'] ?? 'Lab',
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 4),
          Text(
            widget.selectedTests
                .map((t) => t['test_name'] ?? t['name'] ?? 'Test')
                .join(', '),
            style: const TextStyle(
                color: Color(0xFF64748B), fontSize: 13),
          ),
          const Divider(height: 20),
          _summaryRow('Date',
              DateFormat('EEE, dd MMM yyyy').format(widget.selectedDate)),
          _summaryRow('Time', widget.selectedTime),
          const Divider(height: 16),
          if (_feeLoading)
            const Center(
                child: SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2)))
          else if (_feeError != null) ...[
            _summaryRow('Tests Amount',
                'Rs. ${widget.totalAmount.toStringAsFixed(0)}'),
            const SizedBox(height: 8),
            Text(
              _feeError!,
              style: const TextStyle(
                color: Colors.redAccent,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _isProcessing ? null : _loadFeeBreakdown,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ),
          ] else if (_feeBreakdown == null) ...[
            _summaryRow('Tests Amount',
                'Rs. ${widget.totalAmount.toStringAsFixed(0)}'),
            const SizedBox(height: 8),
            const Text(
              'Could not load the booking fee. Please retry before paying.',
              style: TextStyle(
                color: Colors.redAccent,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ] else ...[
            _summaryRow('Tests Amount',
                'Rs. ${widget.totalAmount.toStringAsFixed(0)}'),
            _summaryRow('Convenience Fee',
                'Rs. ${_convenienceFee!.toStringAsFixed(0)}'),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total Payable',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15)),
                Text(
                  'Rs. ${_totalPayable!.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: Color(0xFF10B981),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: const TextStyle(
                    color: Color(0xFF64748B), fontSize: 13)),
            Text(value,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13)),
          ],
        ),
      );

  Widget _buildPaymentMethod({
    required String id,
    required String name,
    required String subtitle,
    required Color color,
    required IconData icon,
    bool isMock = false,
    bool readySoon = false,
  }) {
    final bool isSelected = _selectedMethod == id;
    return GestureDetector(
      onTap: () => setState(() => _selectedMethod = id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.cardBg(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? color : const Color(0xFFE2E8F0),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? color : Colors.transparent,
                border: Border.all(color: color, width: 2),
              ),
            ),
            const SizedBox(width: 14),
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14)),
                Text(subtitle,
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFF94A3B8))),
              ],
            ),
            const Spacer(),
            if (readySoon)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text('SERVER KEY',
                    style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade700)),
              ),
            if (isMock)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text('MOCK',
                    style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange.shade700)),
              ),
            if (isSelected) ...[
              const SizedBox(width: 6),
              Icon(Icons.check_circle_rounded, color: color, size: 20),
            ],
          ],
        ),
      ),
    );
  }

  void _showQRPayment(BuildContext context, double totalAmount) {
    final qrData = 'SWASTHALL_LAB_${widget.labData['id']}_$totalAmount';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: AppColors.cardBg(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        ),
        padding: const EdgeInsets.all(24),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 24),
              const Text('Pay via QR Code',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('Total Amount: Rs. ${totalAmount.toStringAsFixed(0)}',
                  style: const TextStyle(fontSize: 16, color: Colors.grey)),
              const SizedBox(height: 24),
              QrImageView(
                data: qrData,
                version: QrVersions.auto,
                size: 220,
                backgroundColor: Colors.white,
                errorCorrectionLevel: QrErrorCorrectLevel.M,
              ),
              const SizedBox(height: 16),
              Text('Show this QR at the lab counter',
                style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPayButton() {
    return Container(
      padding: const EdgeInsets.all(20),
      color: AppColors.cardBg(context),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton(
              onPressed: !_canPay ? null : _processPayment,
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryIndigo,
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: _isProcessing
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    )
                  : Text(
                      _feeLoading
                          ? 'Calculating…'
                          : (!_canPay
                              ? 'Fee unavailable'
                              : 'Pay Rs. ${_totalPayable!.toStringAsFixed(0)}'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: !_canPay
                  ? null
                  : () => _showQRPayment(context, _totalPayable ?? widget.totalAmount),
              icon: const Icon(Icons.qr_code_2_rounded),
              label: const Text('Pay via QR Code'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

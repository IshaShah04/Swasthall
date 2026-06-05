// lib/consultation_payment_screen.dart
//
// Updated for safer consultation payment flow:
//  • Uses short, SDK-safe gateway order seeds instead of raw slotId values.
//  • Keeps payment-first flow, then saves through verified consultation RPC.
//  • Uses a stable idempotency key based on confirmed payment details.
//  • Sends only p_payment_merchant_txn_id to the RPC (no fallback branch).
//  • No secrets in this file. All crypto is in Supabase edge functions.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'booking_success_screen.dart';
import 'services/queue_widget_service.dart';
import 'services/booking_fee_service.dart';
import 'services/esewa_sdk_payment_service.dart';
import 'services/khalti_sdk_payment_service.dart';
import 'widgets/app_transitions.dart';
import 'theme_colors.dart';
import 'package:qr_flutter/qr_flutter.dart';

class ConsultationPaymentScreen extends StatefulWidget {
  final Map<String, dynamic> doctorData;
  final String appointmentType;
  final double price;
  final DateTime selectedDate;
  final String selectedTime;
  final String slotType;
  final String slotId;

  const ConsultationPaymentScreen({
    super.key,
    required this.doctorData,
    required this.appointmentType,
    required this.price,
    required this.selectedDate,
    required this.selectedTime,
    required this.slotType,
    required this.slotId,
  });

  @override
  State<ConsultationPaymentScreen> createState() =>
      _ConsultationPaymentScreenState();
}

class _ConsultationPaymentScreenState
    extends State<ConsultationPaymentScreen> {
  final supabase = Supabase.instance.client;

  final Color primaryColor = const Color(0xFF6366F1);
  String _selectedMethod = 'esewa';
  bool _isProcessing = false;

  BookingFeeBreakdown? _feeBreakdown;
  bool _feeLoading = true;
  String? _feeError;

  String? _paymentProvider;
  String? _paymentTransactionUuid;
  String? _paymentReference;

  // eSewa is live in test mode. Khalti is wired and becomes live as soon as
  // the server gets KHALTI_SECRET_KEY. FonePay stays mock for now.
  final List<Map<String, dynamic>> _paymentMethods = [
    {
      'id': 'esewa',
      'name': 'eSewa',
      'subtitle': 'Sandbox – test payments',
      'color': const Color(0xFF60BB46),
      'icon': Icons.account_balance_wallet_rounded,
    },
    {
      'id': 'khalti',
      'name': 'Khalti',
      'subtitle': 'Ready – add server secret to enable',
      'color': const Color(0xFF5C2D91),
      'icon': Icons.payments_rounded,
    },
    {
      'id': 'fonepay',
      'name': 'FonePay',
      'subtitle': 'Disabled until mock verification is wired server-side',
      'color': const Color(0xFF6A1B9A),
      'icon': Icons.qr_code_scanner_rounded,
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadFeeBreakdown();
  }

  String _compactAlphaNum(String input, {int maxLen = 12}) {
    final cleaned = input.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    if (cleaned.isEmpty) return 'NA';
    if (cleaned.length <= maxLen) return cleaned;
    return cleaned.substring(cleaned.length - maxLen);
  }

  String _buildGatewayOrderSeed() {
    final dateKey = DateFormat('yyyyMMdd').format(widget.selectedDate);
    final timeKey = _compactAlphaNum(widget.selectedTime, maxLen: 8);
    final slotKey = _compactAlphaNum(widget.slotId, maxLen: 10);
    return 'CONS_${dateKey}_${timeKey}_$slotKey';
  }

  String _buildStableIdempotencyKey({
    required String userId,
    required String formattedDate,
  }) {
    final slotKey = _compactAlphaNum(widget.slotId, maxLen: 10);
    final timeKey = _compactAlphaNum(widget.selectedTime, maxLen: 8);
    final providerKey = _compactAlphaNum(_paymentProvider ?? '', maxLen: 12);
    final txnKey = _compactAlphaNum(_paymentTransactionUuid ?? '', maxLen: 40);

    return 'CONS_${slotKey}_${userId}_${formattedDate}_${timeKey}_${providerKey}_$txnKey';
  }

  Future<void> _loadFeeBreakdown() async {
    if (mounted) {
      setState(() {
        _feeLoading = true;
        _feeError = null;
      });
    }
    try {
      final hospitalId = widget.doctorData['hospital_id']?.toString() ?? '';
      final breakdown = await BookingFeeService.calculate(
        hospitalId: hospitalId,
        bookingType: widget.appointmentType.toLowerCase(),
        baseAmount: widget.price,
      );
      if (mounted) {
        setState(() {
          _feeBreakdown = breakdown;
          _feeLoading = false;
          _feeError = null;
        });
      }
    } catch (e) {
      debugPrint('Fee load error: $e');
      if (mounted) {
        setState(() {
          _feeBreakdown = null;
          _feeLoading = false;
          _feeError = 'Could not load booking fees. Please try again.';
        });
      }
    }
  }

  double get _totalPayable => _feeBreakdown?.totalPayable ?? 0;
  double get _convenienceFee => _feeBreakdown?.convenienceFee ?? 0;
  double get _baseAmount => _feeBreakdown?.baseAmount ?? 0;
  bool get _canPay =>
      !_feeLoading && !_isProcessing && _feeBreakdown != null && _feeError == null;

  // ── Master pay handler ─────────────────────────────────────────────────────

  Future<void> _handleInitialPaymentRequest() async {
    setState(() => _isProcessing = true);
    try {
      final paymentOk = await _runSelectedGateway();
      if (!paymentOk) return;
      if (mounted) setState(() => _isProcessing = true);

      final result = await _saveAppointmentToDatabase();

      if (result['queued'] == true) {
        if (!mounted) return;
        _showQueuedSnackBar();
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (context) => BookingSuccessScreen(
              bookingId: 'queued',
              doctorData: widget.doctorData,
              appointmentDate: widget.selectedDate,
              appointmentTime: widget.selectedTime,
              appointmentType: widget.appointmentType,
              queueNumber: 0,
            ),
          ),
          (route) => false,
        );
        return;
      }

      if (result['success'] == false) {
        debugPrint(
          'Consultation booking save failed after payment: ${result['error']}',
        );
        if (mounted) {
          _showErrorSnackBar(
            'Payment was received, but the booking could not be confirmed. '
            'Please contact support with your payment details.',
          );
        }
        return;
      }

      final booking = result['booking'] as Map<String, dynamic>?;
      final queueNum = booking?['queue_number'];
      final bookingId = booking?['booking_id']?.toString() ?? 'N/A';

      if (booking != null && queueNum != null) {
        await QueueWidgetService.updatePatientRealtimeWidget(
          appointmentId: bookingId,
          doctorName: (widget.doctorData['full_name'] ?? 'Doctor').toString(),
          originalQueueNumber: int.tryParse(queueNum.toString()) ?? 0,
          currentlyServing: 0,
        );
      }

      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (context) => BookingSuccessScreen(
            bookingId: bookingId,
            doctorData: widget.doctorData,
            appointmentDate: widget.selectedDate,
            appointmentTime: widget.selectedTime,
            appointmentType: widget.appointmentType,
            queueNumber: queueNum ?? 0,
          ),
        ),
        (route) => false,
      );
    } catch (e) {
      debugPrint('Consultation payment flow error: $e');
      if (mounted) {
        _showErrorSnackBar(
          'Could not complete the payment flow. Please try again.',
        );
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
        _showErrorSnackBar('Payment method not supported yet.');
        return false;
    }
  }

  // ── eSewa flow ─────────────────────────────────────────────────────────────

  Future<bool> _runEsewa() async {
    setState(() => _isProcessing = true);
    try {
      final orderSeed = _buildGatewayOrderSeed();

      final result = await EsewaSdkPaymentService.start(
        amount: _totalPayable,
        productName:
            'Consultation - ${(widget.doctorData['full_name'] ?? 'Doctor').toString()}',
        productIdSeed: orderSeed,
        orderType: 'consultation',
      );

      if (!result.isComplete) {
        if (mounted) {
          _showErrorSnackBar(
            result.error ??
                'Payment could not be confirmed (status: ${result.status}). '
                    'Please try again.',
          );
        }
        return false;
      }

      _selectedMethod = 'esewa';
      _paymentProvider = 'esewa';
      _paymentTransactionUuid = result.transactionUuid.toString().trim();
      _paymentReference = result.transactionCode.toString().trim().isNotEmpty
          ? result.transactionCode.toString().trim()
          : _paymentTransactionUuid;

      debugPrint(
        '✅ eSewa verified: seed=$orderSeed txn=${result.transactionCode} '
        'amount=${result.totalAmount} uuid=${result.transactionUuid}',
      );
      return true;
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<bool> _runKhalti() async {
    setState(() => _isProcessing = true);
    try {
      final user = supabase.auth.currentUser;
      final orderSeed = _buildGatewayOrderSeed();

      final result = await KhaltiSdkPaymentService.start(
        context: context,
        amount: _totalPayable,
        orderType: 'consultation',
        orderIdSeed: orderSeed,
        productName:
            'Consultation - ${(widget.doctorData['full_name'] ?? 'Doctor').toString()}',
        customerName: user?.userMetadata?['full_name']?.toString(),
        customerEmail: user?.email,
        customerPhone: user?.phone,
      );

      if (!result.isComplete) {
        if (mounted) {
          _showErrorSnackBar(
            result.error ??
                'Khalti payment could not be confirmed (status: ${result.status}). '
                    'Please try again.',
          );
        }
        return false;
      }

      _selectedMethod = 'khalti';
      _paymentProvider = 'khalti';
      _paymentTransactionUuid = result.pidx.toString().trim().isNotEmpty
          ? result.pidx.toString().trim()
          : result.transactionCode.toString().trim();
      _paymentReference = result.transactionCode.toString().trim().isNotEmpty
          ? result.transactionCode.toString().trim()
          : _paymentTransactionUuid;

      debugPrint(
        '✅ Khalti verified: seed=$orderSeed txn=${result.transactionCode} '
        'amount=${result.totalAmount} pidx=${result.pidx}',
      );
      return true;
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ── FonePay mock flow ──────────────────────────────────────────────────────

  Future<bool> _runFonePayMock() async {
    _showErrorSnackBar(
      'FonePay mock is disabled until a verified mock-payment server flow is added.',
    );
    return false;
  }

  // ── DB save ────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _saveAppointmentToDatabase() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      throw 'You must be signed in to book an appointment.';
    }

    final formattedDate = DateFormat('yyyy-MM-dd').format(widget.selectedDate);
    final rawName = user.userMetadata?['full_name']?.toString() ?? 'Patient';
    final safeName =
        rawName.replaceAll(RegExp(r"""[<>{}\\"';]"""), '').trim();

    final providerId = widget.doctorData['id']?.toString().trim() ?? '';
    final hospitalId = widget.doctorData['hospital_id']?.toString().trim() ?? '';
    final doctorEmail = widget.doctorData['email']?.toString().trim() ?? '';

    if (providerId.isEmpty) {
      throw 'Doctor profile is missing. Please refresh and try again.';
    }
    if (hospitalId.isEmpty) {
      throw 'Hospital details are missing. Please refresh and try again.';
    }
    if ((_paymentProvider ?? '').trim().isEmpty ||
        (_paymentTransactionUuid ?? '').trim().isEmpty) {
      throw 'Payment confirmation is missing. Please retry payment.';
    }

    final stableIdempotencyKey = _buildStableIdempotencyKey(
      userId: user.id,
      formattedDate: formattedDate,
    );

    final result = await supabase.rpc(
      'book_appointment_atomic_paid',
      params: {
        'p_slot_id': widget.slotId,
        'p_user_id': user.id,
        'p_provider_id': providerId,
        'p_hospital_id': hospitalId,
        'p_doctor_email': doctorEmail,
        'p_patient_name': safeName,
        'p_appointment_date': formattedDate,
        'p_appointment_time': widget.selectedTime,
        'p_payment_method': _selectedMethod,
        'p_amount': _totalPayable,
        'p_consultation_fee': _baseAmount,
        'p_platform_fee': _convenienceFee,
        'p_type': widget.appointmentType.toLowerCase(),
        'p_slots_type': widget.slotType,
        'p_idempotency_key': stableIdempotencyKey,
        'p_payment_provider': _paymentProvider,
        'p_payment_merchant_txn_id': _paymentTransactionUuid,
        'p_payment_reference': _paymentReference,
      },
    );

    if (result is! Map) {
      throw 'Booking response was invalid.';
    }

    final booking = Map<String, dynamic>.from(result);
    return {
      'success': true,
      'queued': false,
      'booking': booking,
    };
  }

  // ── Snack bars ─────────────────────────────────────────────────────────────

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showQueuedSnackBar() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Network unavailable. Your booking is saved and will confirm automatically when connection restores.',
        ),
        backgroundColor: Color(0xFF6366F1),
        duration: Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
      ),
    );
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
            color: AppColors.textPrimary(context),
          ),
        ),
        backgroundColor: AppColors.cardBg(context),
        elevation: 0,
        iconTheme: IconThemeData(color: AppColors.textPrimary(context)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildOrderSummary(),
            const SizedBox(height: 32),
            const Text(
              'Select Payment Method',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ..._paymentMethods
                .map((m) => _buildPaymentOption(m, _selectedMethod == m['id'])),
            const SizedBox(height: 100),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomPayButton(),
    );
  }

  Widget _buildOrderSummary() {
    final bool isPhysical = widget.appointmentType.toLowerCase() == 'physical';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: AppColors.shadow(context), blurRadius: 10),
        ],
      ),
      child: Column(
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              radius: 25,
              backgroundColor: primaryColor.withValues(alpha: 0.1),
              backgroundImage: widget.doctorData['avatar_url'] != null
                  ? NetworkImage(widget.doctorData['avatar_url'] as String)
                  : null,
              child: widget.doctorData['avatar_url'] == null
                  ? Icon(Icons.person, color: primaryColor)
                  : null,
            ),
            title: Text(
              widget.doctorData['full_name'] ?? 'Doctor',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            subtitle: Text(
              '${widget.doctorData['speciality'] ?? 'Specialist'} • ${widget.slotType}',
            ),
          ),
          const Divider(height: 30),
          _infoRow(
            'Date',
            DateFormat('EEE, MMM d, yyyy').format(widget.selectedDate),
          ),
          _infoRow('Check-in Time', widget.selectedTime),
          if (isPhysical)
            _infoRow(
              'Location',
              widget.doctorData['hospital_name'] ?? 'Hospital',
            ),
          const Divider(height: 24),
          if (_feeLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (_feeError != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                children: [
                  Text(
                    _feeError!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _loadFeeBreakdown,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            )
          else ...[
            _feeRow(
              'Consultation Fee',
              'Rs. ${_baseAmount.toStringAsFixed(0)}',
            ),
            _feeRow(
              'Convenience Fee',
              'Rs. ${_convenienceFee.toStringAsFixed(0)}',
              sub: 'Platform service charge',
            ),
            const Divider(height: 20),
            _feeRow(
              'Total Payable',
              'Rs. ${_totalPayable.toStringAsFixed(0)}',
              isTotal: true,
            ),
          ],
          if (isPhysical)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 16,
                      color: Colors.orange.shade800,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Queue number will be assigned after payment.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange.shade900,
                        ),
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

  Widget _infoRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(color: Color(0xFF475569), fontSize: 14),
            ),
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      );

  Widget _feeRow(String label, String value,
          {bool isTotal = false, String? sub}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: isTotal ? Colors.black : Colors.grey.shade700,
                    fontSize: isTotal ? 15 : 14,
                    fontWeight:
                        isTotal ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                if (sub != null)
                  Text(
                    sub,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
              ],
            ),
            Text(
              value,
              style: TextStyle(
                fontWeight: isTotal ? FontWeight.bold : FontWeight.w600,
                fontSize: isTotal ? 18 : 14,
                color: isTotal
                    ? const Color(0xFF10B981)
                    : Colors.black87,
              ),
            ),
          ],
        ),
      );

  Widget _buildPaymentOption(Map<String, dynamic> method, bool isSelected) {
    final color = method['color'] as Color;
    final isMock = method['id'] == 'fonepay';
    final isReadySoon = method['id'] == 'khalti';

    return GestureDetector(
      onTap: () => setState(() => _selectedMethod = method['id'] as String),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.cardBg(context),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: isSelected ? color : AppColors.surfaceBg(context),
            width: 2,
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
            const SizedBox(width: 16),
            Icon(method['icon'] as IconData, color: color, size: 22),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  method['name'] as String,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  method['subtitle'] as String,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
            const Spacer(),
            if (isReadySoon)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'SERVER KEY',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade700,
                  ),
                ),
              ),
            if (isMock)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'MOCK',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange.shade700,
                  ),
                ),
              ),
            if (isSelected) ...[
              const SizedBox(width: 6),
              Icon(Icons.check_circle_rounded, color: color),
            ],
          ],
        ),
      ),
    );
  }

  void _showQRPayment(BuildContext context, String bookingId, double totalAmount) {
    final qrData = 'SWASTHALL_CONS_${widget.doctorData['id']}_$totalAmount';
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
              Text('Show this QR at the hospital counter',
                style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomPayButton() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        border: const Border(top: BorderSide(color: Colors.black12)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton(
              onPressed: !_canPay
                  ? null
                  : () {
                      hapticMedium();
                      _handleInitialPaymentRequest();
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                minimumSize: const Size(double.infinity, 56),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: _isProcessing
                  ? const SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(
                      _feeLoading
                          ? 'Calculating…'
                          : _feeError != null
                              ? 'Fees unavailable'
                              : 'Pay Rs. ${_totalPayable.toStringAsFixed(0)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: !_canPay
                  ? null
                  : () => _showQRPayment(context, widget.slotId, _totalPayable),
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

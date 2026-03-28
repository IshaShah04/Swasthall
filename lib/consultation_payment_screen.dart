import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'booking_success_screen.dart';
import 'package:swasthall/services/queue_widget_service.dart';
import 'package:swasthall/services/booking_fee_service.dart';
import 'package:swasthall/services/offline_booking_queue.dart';
import 'widgets/app_transitions.dart';
import 'theme_colors.dart';

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

  final List<Map<String, dynamic>> _paymentMethods = [
    {'id': 'esewa',      'name': 'eSewa',       'color': const Color(0xFF60BB46)},
    {'id': 'khalti',     'name': 'Khalti',      'color': const Color(0xFF5C2D91)},
    {'id': 'imepay',     'name': 'IME Pay',     'color': const Color(0xFFED1C24)},
    {'id': 'connectips', 'name': 'Connect IPS', 'color': const Color(0xFF00408F)},
  ];

  @override
  void initState() {
    super.initState();
    _loadFeeBreakdown();
  }

  Future<void> _loadFeeBreakdown() async {
    try {
      final hospitalId = widget.doctorData['hospital_id']?.toString() ?? '';
      final breakdown = await BookingFeeService.calculate(
        hospitalId:  hospitalId,
        bookingType: widget.appointmentType.toLowerCase(),
        baseAmount:  widget.price,
      );
      if (mounted) {
        setState(() {
          _feeBreakdown = breakdown;
          _feeLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Fee load error: $e');
      if (mounted) setState(() => _feeLoading = false);
    }
  }

  double get _totalPayable  => _feeBreakdown?.totalPayable  ?? widget.price + 30;
  double get _convenienceFee => _feeBreakdown?.convenienceFee ?? 30;
  double get _baseAmount     => _feeBreakdown?.baseAmount     ?? widget.price;


  Future<void> _handleInitialPaymentRequest() async {
    setState(() => _isProcessing = true);
    try {
      final result = await _saveAppointmentToDatabase();

      if (result['queued'] == true) {
        // Offline — booking queued for retry
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

      // Hard failure returned from queue service
      if (result['success'] == false) {
        if (mounted) _showErrorSnackBar(result['error']?.toString() ?? 'Booking failed. Please try again.');
        return;
      }

      final booking = result['booking'] as Map<String, dynamic>?;
      final queueNum = booking?['queue_number'];
      // RPC returns 'booking_id', not 'id'
      final bookingId = booking?['booking_id']?.toString() ?? 'N/A';

      if (booking != null && queueNum != null) {
        await QueueWidgetService.updateLiveWidget(
          patientName:  supabase.auth.currentUser?.userMetadata?['full_name'] ?? 'Patient',
          queueNum:     queueNum.toString(),
          bookingId:    bookingId,
          doctorStatus: 'Confirmed at ${widget.doctorData['hospital_name'] ?? 'Hospital'}',
        );
      }

      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (context) => BookingSuccessScreen(
            bookingId:       bookingId,
            doctorData:      widget.doctorData,
            appointmentDate: widget.selectedDate,
            appointmentTime: widget.selectedTime,
            appointmentType: widget.appointmentType,
            queueNumber:     queueNum ?? 0,
          ),
        ),
        (route) => false,
      );
    } catch (e) {
      if (mounted) _showErrorSnackBar(e.toString());
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<Map<String, dynamic>> _saveAppointmentToDatabase() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      throw 'You must be signed in to book an appointment.';
    }

    final formattedDate = DateFormat('yyyy-MM-dd').format(widget.selectedDate);
    final rawName = user.userMetadata?['full_name']?.toString() ?? 'Patient';
    final safeName = rawName.replaceAll(RegExp(r"""[<>{}\\"';]"""), '').trim();

    final providerId = widget.doctorData['id']?.toString() ?? '';
    if (providerId.isEmpty) {
      throw 'Doctor profile is missing. Please refresh and try again.';
    }

    final rpcParams = {
      'p_slot_id': widget.slotId,
      'p_user_id': user.id,
      'p_provider_id': widget.doctorData['id'],
      'p_hospital_id': widget.doctorData['hospital_id'],
      'p_doctor_email': widget.doctorData['email'],
      'p_patient_name': safeName,
      'p_appointment_date': formattedDate,
      'p_appointment_time': widget.selectedTime,
      'p_payment_method': _selectedMethod,
      'p_amount': _totalPayable,
      'p_consultation_fee': _baseAmount,
      'p_platform_fee': _convenienceFee,
      'p_type': widget.appointmentType.toLowerCase(),
      'p_slots_type': widget.slotType,
    };

    // OfflineBookingQueue handles idempotency key generation + retry on failure
    return OfflineBookingQueue.submit(rpcParams: rpcParams);
  }

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg(context),
      appBar: AppBar(
        title: Text(
          'Payment Details',
          style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary(context)),
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
            ..._paymentMethods.map(
              (m) => _buildPaymentOption(m, _selectedMethod == m['id']),
            ),
            const SizedBox(height: 100),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomPayButton(),
    );
  }

  Widget _buildOrderSummary() {
    final bool isPhysical =
        widget.appointmentType.toLowerCase() == 'physical';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow(context),
            blurRadius: 10,
          ),
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
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            subtitle: Text(
              '${widget.doctorData['speciality'] ?? 'Specialist'} • ${widget.slotType}',
            ),
          ),
          const Divider(height: 30),
          _infoRow('Date', DateFormat('EEE, MMM d, yyyy').format(widget.selectedDate)),
          _infoRow('Check-in Time', widget.selectedTime),
          if (isPhysical)
            _infoRow('Location', widget.doctorData['hospital_name'] ?? 'Hospital'),
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
          else ...[
            _feeRow('Consultation Fee', 'Rs. ${_baseAmount.toStringAsFixed(0)}'),
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
                    Icon(Icons.info_outline, size: 16, color: Colors.orange.shade800),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Queue number will be assigned after payment.',
                        style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
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

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: const Color(0xFF475569), fontSize: 14)),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _feeRow(String label, String value, {bool isTotal = false, String? sub}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                    color: isTotal ? Colors.black : Colors.grey.shade700,
                    fontSize: isTotal ? 15 : 14,
                    fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
                  )),
              if (sub != null)
                Text(sub, style: TextStyle(fontSize: 11, color: const Color(0xFF94A3B8))),
            ],
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: isTotal ? FontWeight.bold : FontWeight.w600,
              fontSize: isTotal ? 18 : 14,
              color: isTotal ? const Color(0xFF10B981) : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentOption(Map<String, dynamic> method, bool isSelected) {
    return GestureDetector(
      onTap: () => setState(() => _selectedMethod = method['id'] as String),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.cardBg(context),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: isSelected ? method['color'] as Color : AppColors.surfaceBg(context),
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
                color: isSelected ? method['color'] as Color : Colors.transparent,
                border: Border.all(color: method['color'] as Color, width: 2),
              ),
            ),
            const SizedBox(width: 16),
            Text(
              method['name'] as String,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            if (isSelected)
              Icon(Icons.check_circle_rounded, color: method['color'] as Color),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomPayButton() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        border: Border(top: BorderSide(color: Colors.black12)),
      ),
      child: SafeArea(
        child: ElevatedButton(
          onPressed: (_isProcessing || _feeLoading)
              ? null
              : () {
                  hapticMedium();
                  _handleInitialPaymentRequest();
                },
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryColor,
            minimumSize: const Size(double.infinity, 56),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          child: _isProcessing
              ? SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                )
              : Text(
                  _feeLoading
                      ? 'Calculating...'
                      : 'Pay Rs. ${_totalPayable.toStringAsFixed(0)}',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
        ),
      ),
    );
  }
}
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'booking_success_screen.dart';
// Ensure this path matches your project structure for the widget service
import 'package:swasthall/services/queue_widget_service.dart';

enum PaymentStatus { initial, processing, success, failure }

class MockPaymentService {
  Future<void> requestOtp(String method, double amount) async {
    debugPrint("Requesting OTP for $method payment of Rs $amount...");
    await Future.delayed(const Duration(seconds: 1));
  }

  Future<PaymentStatus> verifyOtp(String code) async {
    await Future.delayed(const Duration(seconds: 1));
    // For demo purposes, "1234" is the success code
    if (code == "1234") return PaymentStatus.success;
    return PaymentStatus.failure;
  }
}

class ConsultationPaymentScreen extends StatefulWidget {
  final Map<String, dynamic> doctorData;
  final String appointmentType;
  final double price; // Fully flexible price
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

class _ConsultationPaymentScreenState extends State<ConsultationPaymentScreen> {
  final supabase = Supabase.instance.client;
  final MockPaymentService _paymentService = MockPaymentService();
  final TextEditingController _otpController = TextEditingController();

  final Color primaryColor = const Color(0xFF6366F1);
  String _selectedMethod = "esewa";
  bool _isProcessing = false;

  final List<Map<String, dynamic>> _paymentMethods = [
    {"id": "esewa", "name": "eSewa", "color": const Color(0xFF60BB46)},
    {"id": "khalti", "name": "Khalti", "color": const Color(0xFF5C2D91)},
    {"id": "imepay", "name": "IME Pay", "color": const Color(0xFFED1C24)},
    {"id": "connectips", "name": "Connect IPS", "color": const Color(0xFF00408F)},
  ];

  Future<void> _handleInitialPaymentRequest() async {
    setState(() => _isProcessing = true);
    try {
      await _paymentService.requestOtp(_selectedMethod, widget.price);
      if (!mounted) return;
      _showOtpBottomSheet();
    } catch (e) {
      _showErrorSnackBar("OTP Request Failed: $e");
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _showOtpBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          left: 24,
          right: 24,
          top: 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Verify Payment",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text("Enter the 4-digit OTP sent to your phone (Demo: 1234)",
                style: TextStyle(color: Colors.grey.shade600, fontSize: 14)),
            const SizedBox(height: 24),
            TextField(
              controller: _otpController,
              keyboardType: TextInputType.number,
              autofocus: true,
              maxLength: 4,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 15),
              decoration: InputDecoration(
                hintText: "0000",
                counterText: "",
                filled: true,
                fillColor: Colors.grey.shade100,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: () => _verifyAndFinalize(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text("Verify & Confirm Booking",
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _verifyAndFinalize() async {
    final code = _otpController.text;
    if (mounted) Navigator.pop(context);

    setState(() => _isProcessing = true);

    try {
      final status = await _paymentService.verifyOtp(code);

      if (status == PaymentStatus.success) {
        final Map<String, dynamic>? result = await _saveAppointmentToDatabase();

        if (result != null) {
          // UPDATE HOME SCREEN WIDGET IMMEDIATELY
          await QueueWidgetService.updateLiveWidget(
            patientName: supabase.auth.currentUser?.userMetadata?['full_name'] ?? 'Patient',
            queueNum: result['queue_number'].toString(),
            bookingId: result['id'].toString(),
            doctorStatus: "Confirmed at ${widget.doctorData['hospital_name'] ?? 'Hospital'}",
          );
        }

        if (!mounted) return;
        _otpController.clear();

        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (context) => BookingSuccessScreen(
              bookingId: result?['id']?.toString() ?? "N/A",
              doctorData: widget.doctorData,
              appointmentDate: widget.selectedDate,
              appointmentTime: widget.selectedTime,
              appointmentType: widget.appointmentType,
              queueNumber: result?['queue_number'] ?? 0,
            ),
          ),
          (route) => false,
        );
      } else {
        throw Exception("Invalid OTP. Use '1234' for this demo.");
      }
    } catch (e) {
      if (!mounted) return;
      _showErrorSnackBar(e.toString());
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<Map<String, dynamic>?> _saveAppointmentToDatabase() async {
  try {
    final user = supabase.auth.currentUser;
    if (user == null) throw Exception("User not logged in.");

    final formattedDate = DateFormat('yyyy-MM-dd').format(widget.selectedDate);

    // ✅ Get patient's ZEGO UID (patient can read own profile even with RLS)
    String myZegoUid = (user.userMetadata?['zego_uid']?.toString().trim() ?? '');
    if (myZegoUid.isEmpty) {
      try {
        final prof = await supabase
            .from('profiles')
            .select('zego_uid')
            .eq('id', user.id)
            .maybeSingle();

        myZegoUid = (prof?['zego_uid'] ?? '').toString().trim();
      } catch (_) {}
    }
    if (myZegoUid.isEmpty) {
      // last resort fallback
      myZegoUid = user.id;
    }

    // 1. Fetch current bookings (using maybeSingle to avoid PGRST116 error)
    final slotCheck = await supabase
        .from('availability_slots')
        .select('current_bookings')
        .eq('id', widget.slotId)
        .maybeSingle();

    int nextQueueNumber = (slotCheck?['current_bookings'] ?? 0) + 1;

    // 2. Insert the booking (✅ now also stores patient_zego_uid)
    final response = await supabase
        .from('bookings')
        .insert({
          'user_id': user.id,                 // keep your existing field
          'patient_id': user.id,              // ✅ also set if your schema uses patient_id
          'patient_zego_uid': myZegoUid,      // ✅ IMPORTANT FIX
          'provider_id': widget.doctorData['id'],
          'hospital_id': widget.doctorData['hospital_id'],
          'doctor_email': widget.doctorData['email'],
          'patient_name': user.userMetadata?['full_name'] ?? 'Patient',
          'appointment_date': formattedDate,
          'appointment_time': widget.selectedTime,
          'status': 'confirmed',
          'payment_method': _selectedMethod,
          'amount': widget.price,
          'type': widget.appointmentType.toLowerCase(),
          'slots_type': widget.slotType,
          'queue_number': nextQueueNumber,
        })
        .select('id, queue_number')
        .single();

    // 3. Update the slot count
    try {
      await supabase.rpc('increment_slot_booking', params: {
        'slot_uuid': widget.slotId,
      });
    } catch (e) {
      await supabase
          .from('availability_slots')
          .update({'current_bookings': nextQueueNumber})
          .eq('id', widget.slotId);
    }

    return response;
  } catch (e) {
    debugPrint("Database Error: $e");
    rethrow;
  }
}

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text("Payment Details",
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildOrderSummary(),
            const SizedBox(height: 32),
            const Text("Select Payment Method",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            ..._paymentMethods
                .map((m) => _buildPaymentOption(m, _selectedMethod == m['id'])),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomPayButton(),
    );
  }

  Widget _buildOrderSummary() {
    bool isPhysical = widget.appointmentType.toLowerCase() == 'physical';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)
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
                  ? NetworkImage(widget.doctorData['avatar_url'])
                  : null,
              child: widget.doctorData['avatar_url'] == null
                  ? Icon(Icons.person, color: primaryColor)
                  : null,
            ),
            title: Text(widget.doctorData['full_name'] ?? "Doctor",
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            subtitle: Text(
                "${widget.doctorData['speciality'] ?? 'Specialist'} • ${widget.slotType}"),
          ),
          const Divider(height: 30),
          _summaryRow("Date",
              DateFormat('EEE, MMM d, yyyy').format(widget.selectedDate)),
          _summaryRow("Check-in Time", widget.selectedTime),
          if (isPhysical)
            _summaryRow("Location", widget.doctorData['hospital_name'] ?? "Hospital"),
          _summaryRow("Consultation Fee", "Rs ${widget.price.toInt()}",
              isTotal: true),
          if (isPhysical)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8)
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: Colors.orange.shade800),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Queue number will be assigned after payment.",
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

  Widget _summaryRow(String label, String value, {bool isTotal = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 14)),
          Flexible(
            child: Text(value,
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontWeight: isTotal ? FontWeight.bold : FontWeight.w600,
                    color: isTotal ? const Color(0xFF10B981) : Colors.black,
                    fontSize: isTotal ? 18 : 14)),
          )
        ]),
      );

  Widget _buildPaymentOption(Map<String, dynamic> method, bool isSelected) {
    return GestureDetector(
      onTap: () => setState(() => _selectedMethod = method['id']),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
              color: isSelected ? method['color'] : Colors.grey.shade200,
              width: 2),
        ),
        child: Row(children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? method['color'] : Colors.transparent,
                border: Border.all(color: method['color'], width: 2)),
          ),
          const SizedBox(width: 16),
          Text(method['name'],
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const Spacer(),
          if (isSelected)
            Icon(Icons.check_circle_rounded, color: method['color'])
        ]),
      ),
    );
  }

  Widget _buildBottomPayButton() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.black12))),
      child: SafeArea(
        child: ElevatedButton(
          onPressed: _isProcessing ? null : _handleInitialPaymentRequest,
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryColor,
            minimumSize: const Size(double.infinity, 56),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          child: _isProcessing
              ? const SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))
              : Text("Pay Rs ${widget.price.toInt()}",
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16)),
        ),
      ),
    );
  }
}
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'order_success_screen.dart';
import 'package:swasthall/services/booking_fee_service.dart';
import 'theme_colors.dart';

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

  final Color primaryIndigo = const Color(0xFF6366F1);
  final Color bgLight = const Color(0xFFF8FAFC);

  // ── Fee breakdown ────────────────────────────────────────
  BookingFeeBreakdown? _feeBreakdown;
  bool _feeLoading = true;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _loadFeeBreakdown();
  }

  Future<void> _loadFeeBreakdown() async {
    try {
      final hospitalId =
          (widget.labData['hospital_id'] ?? widget.labData['id'])
              ?.toString() ?? '';
      final breakdown = await BookingFeeService.forLab(
        hospitalId: hospitalId,
        baseAmount:  widget.totalAmount,
      );
      if (mounted) {
        setState(() {
          _feeBreakdown = breakdown;
          _feeLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Lab fee load error: $e');
      if (mounted) setState(() => _feeLoading = false);
    }
  }

  double get _convenienceFee => _feeBreakdown?.convenienceFee ?? 30;
  double get _totalPayable =>
      _feeBreakdown?.totalPayable ?? widget.totalAmount + 30;

  Future<void> _processPayment() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) return;

    setState(() => _isProcessing = true);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          Center(child: CircularProgressIndicator(color: primaryIndigo)),
    );

    try {
      final profileData = await supabase
          .from('profiles')
          .select('full_name')
          .eq('id', user.id)
          .maybeSingle();

      final String patientName = profileData?['full_name'] ?? 'User';
      final String professionalId = widget.labData['id'].toString();
      final String testNames = widget.selectedTests
          .map((e) => e['test_name'] ?? e['name'] ?? 'Test')
          .join(', ');
      final String dbDateString =
          DateFormat('yyyy-MM-dd').format(widget.selectedDate);

      // Store base amount in total_amount (without convenience fee)
      // Convenience fee tracked via platform_transactions trigger
      final insertedRows = await supabase
          .from('lab_appointments')
          .insert({
            'professional_id': professionalId,
            'hospital_id':
                widget.labData['hospital_id'] ?? widget.labData['id'],
            'user_id':          user.id,
            'patient_name':     patientName,
            'test_names':       testNames,
            'appointment_date': dbDateString,
            'appointment_time': widget.selectedTime,
            'total_amount':     _totalPayable,   // patient pays this
            'payment_status':
                _selectedMethod == 'cod' ? 'pending' : 'paid',
            'payment_method':   _selectedMethod,
            'status':           'scheduled',
          })
          .select();
      // BUG-05b: safe first-row extraction (no .single() crash)
      final response = (insertedRows.isNotEmpty)
          ? Map<String, dynamic>.from(insertedRows.first as Map)
          : <String, dynamic>{};

      if (!mounted) return;
      Navigator.of(context).pop(); // close loading

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (context) => OrderSuccessScreen(
            itemLabel: testNames,
            amount: _totalPayable.toStringAsFixed(0),
            storeName: widget.labData['full_name'] ?? 'Lab Center',
            type: 'Lab',
            labData: widget.labData,
            extraDetails: {
              'date': DateFormat('dd MMM yyyy').format(widget.selectedDate),
              'time': widget.selectedTime,
              'appointment_id': response['id'].toString(),
              'status': _selectedMethod == 'cod' ? 'Pay at Lab' : 'Paid',
            },
          ),
        ),
        (route) => route.isFirst,
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Booking Failed: ${e.toString()}'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgLight,
      appBar: AppBar(
        title: Text(
          'Checkout',
          style: TextStyle(color: AppColors.textPrimary(context), fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppColors.cardBg(context),
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: AppColors.textPrimary(context)),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildOrderSummary(),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 10, 20, 15),
              child: Text(
                'Payment Method',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
              ),
            ),
            _buildPaymentMethod(
              id: 'esewa',
              name: 'eSewa Wallet',
              color: Colors.green,
              icon: Icons.account_balance_wallet_rounded,
            ),
            _buildPaymentMethod(
              id: 'khalti',
              name: 'Khalti SDK',
              color: Colors.deepPurple,
              icon: Icons.wallet_rounded,
            ),
            _buildPaymentMethod(
              id: 'cod',
              name: 'Pay at Lab (Cash/QR)',
              color: Colors.blueGrey,
              icon: Icons.payments_rounded,
            ),
            const SizedBox(height: 120),
          ],
        ),
      ),
      bottomSheet: _buildPayButton(),
    );
  }

  Widget _buildOrderSummary() {
    return Container(
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow(context),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Lab header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: primaryIndigo.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.science_rounded,
                    color: primaryIndigo, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.labData['full_name'] ?? 'Lab Center',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 17),
                ),
              ),
            ],
          ),
          Padding(
              padding: EdgeInsets.symmetric(vertical: 15),
              child: Divider(height: 1)),

          // Individual tests
          ...widget.selectedTests.map(
            (test) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      test['test_name'] ?? test['name'] ?? 'Test',
                      style:
                          TextStyle(color: AppColors.textSecondary(context), fontSize: 14),
                    ),
                  ),
                  Text(
                    'Rs. ${test['price']}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                ],
              ),
            ),
          ),

          const Divider(height: 20),

          // Schedule
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Schedule',
                  style: TextStyle(
                      color: AppColors.textSecondary(context),
                      fontSize: 13,
                      fontWeight: FontWeight.w500)),
              Text(
                '${DateFormat('dd MMM').format(widget.selectedDate)} • ${widget.selectedTime}',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Fee breakdown
          if (_feeLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else ...[
            // Tests subtotal
            _feeRow(
              'Tests Subtotal',
              'Rs. ${widget.totalAmount.toStringAsFixed(0)}',
            ),
            const SizedBox(height: 6),
            _feeRow(
              'Convenience Fee',
              'Rs. ${_convenienceFee.toStringAsFixed(0)}',
              sub: 'Platform service charge',
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: bgLight,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total Payable',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16)),
                  Text(
                    'Rs. ${_totalPayable.toStringAsFixed(0)}',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: primaryIndigo),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _feeRow(String label, String value, {String? sub}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(
                    color: AppColors.textSecondary(context),
                    fontSize: 13,
                    fontWeight: FontWeight.w500)),
            if (sub != null)
              Text(sub,
                  style: TextStyle(
                      fontSize: 11, color: AppColors.textMuted(context))),
          ],
        ),
        Text(value,
            style: const TextStyle(
                fontWeight: FontWeight.w600, fontSize: 13)),
      ],
    );
  }

  Widget _buildPaymentMethod({
    required String id,
    required String name,
    required Color color,
    required IconData icon,
  }) {
    final bool isSelected = _selectedMethod == id;
    return GestureDetector(
      onTap: () => setState(() => _selectedMethod = id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.cardBg(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? primaryIndigo
                : Colors.grey.withValues(alpha: 0.1),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              height: 40,
              width: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 15),
            Text(name,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 15)),
            const Spacer(),
            Icon(
              isSelected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_off_rounded,
              color: isSelected ? primaryIndigo : Colors.grey[300],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPayButton() {
    return Container(
      padding: EdgeInsets.fromLTRB(
          20, 15, 20, MediaQuery.of(context).padding.bottom + 15),
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow(context),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: (_feeLoading || _isProcessing) ? null : _processPayment,
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryIndigo,
          minimumSize: const Size(double.infinity, 56),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          elevation: 0,
        ),
        child: _isProcessing
            ? SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2),
              )
            : Text(
                _selectedMethod == 'cod'
                    ? 'Confirm Appointment'
                    : _feeLoading
                        ? 'Calculating...'
                        : 'Pay Rs. ${_totalPayable.toStringAsFixed(0)}',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold),
              ),
      ),
    );
  }
}
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'order_success_screen.dart';

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
  String _selectedMethod = "esewa";

  // SYNCED BRAND COLORS
  final Color primaryIndigo = const Color(0xFF6366F1);
  final Color bgLight = const Color(0xFFF8FAFC);

  Future<void> _processPayment() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;

    if (user == null) return;

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
          .single();

      final String patientName = profileData['full_name'] ?? "User";
      final String professionalId = widget.labData['id'].toString();
      
      // FIXED: Using 'test_name' to sync with LabAppointmentScreen
      final String testNames = widget.selectedTests
          .map((e) => e['test_name'] ?? e['name'] ?? 'Test')
          .join(", ");

      final String dbDateString = DateFormat('yyyy-MM-dd').format(widget.selectedDate);

      // Insert into Supabase
      final response = await supabase
          .from('lab_appointments')
          .insert({
            'professional_id': professionalId,
            'user_id': user.id,
            'patient_name': patientName,
            'test_names': testNames,
            'appointment_date': dbDateString,
            'appointment_time': widget.selectedTime,
            'total_amount': widget.totalAmount,
            'payment_status': _selectedMethod == 'cod' ? 'pending' : 'paid',
            'payment_method': _selectedMethod,
            'status': 'scheduled',
          })
          .select()
          .single();

      if (!mounted) return;
      Navigator.of(context).pop(); // Close loading dialog

      // Navigate to Success Screen
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (context) => OrderSuccessScreen(
            itemLabel: testNames,
            amount: widget.totalAmount.toStringAsFixed(0),
            storeName: widget.labData['full_name'] ?? "Lab Center",
            type: "Lab",
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
          content: Text("Booking Failed: ${e.toString()}"),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgLight,
      appBar: AppBar(
        title: const Text(
          "Checkout",
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildOrderSummary(),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 10, 20, 15),
              child: Text(
                "Payment Method",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
              ),
            ),
            _buildPaymentMethod(
              id: "esewa",
              name: "eSewa Wallet",
              color: Colors.green,
              icon: Icons.account_balance_wallet_rounded,
            ),
            _buildPaymentMethod(
              id: "khalti",
              name: "Khalti SDK",
              color: Colors.deepPurple,
              icon: Icons.wallet_rounded,
            ),
            _buildPaymentMethod(
              id: "cod",
              name: "Pay at Lab (Cash/QR)",
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: primaryIndigo.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.science_rounded, color: primaryIndigo, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.labData['full_name'] ?? "Lab Center",
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                ),
              ),
            ],
          ),
          const Padding(padding: EdgeInsets.symmetric(vertical: 15), child: Divider(height: 1)),
          
          // FIXED: Test name mapping
          ...widget.selectedTests.map(
            (test) => Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    test['test_name'] ?? test['name'] ?? 'Test',
                    style: TextStyle(color: Colors.grey[800], fontSize: 14),
                  ),
                  Text(
                    "Rs. ${test['price']}",
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 20),
          _summaryRow(
            "Schedule",
            "${DateFormat('dd MMM').format(widget.selectedDate)} • ${widget.selectedTime}",
          ),
          const SizedBox(height: 15),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: bgLight,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Total Payable", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Text(
                  "Rs. ${widget.totalAmount.toStringAsFixed(0)}",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: primaryIndigo),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 13, fontWeight: FontWeight.w500)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
      ],
    );
  }

  Widget _buildPaymentMethod({required String id, required String name, required Color color, required IconData icon}) {
    bool isSelected = _selectedMethod == id;
    return GestureDetector(
      onTap: () => setState(() => _selectedMethod = id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? primaryIndigo : Colors.grey.withValues(alpha: 0.1),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              height: 40, width: 40,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 15),
            Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const Spacer(),
            Icon(
              isSelected ? Icons.check_circle_rounded : Icons.radio_button_off_rounded,
              color: isSelected ? primaryIndigo : Colors.grey[300],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPayButton() {
    return Container(
      padding: EdgeInsets.fromLTRB(20, 15, 20, MediaQuery.of(context).padding.bottom + 15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -5))],
      ),
      child: ElevatedButton(
        onPressed: _processPayment,
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryIndigo,
          minimumSize: const Size(double.infinity, 56),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 0,
        ),
        child: Text(
          _selectedMethod == 'cod' ? "Confirm Appointment" : "Secure Payment",
          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
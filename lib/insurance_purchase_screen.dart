import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:swasthall/services/booking_fee_service.dart';
import 'theme_colors.dart';

class InsurancePurchaseScreen extends StatefulWidget {
  final Map<String, dynamic> plan;

  const InsurancePurchaseScreen({super.key, required this.plan});

  @override
  State<InsurancePurchaseScreen> createState() =>
      _InsurancePurchaseScreenState();
}

class _InsurancePurchaseScreenState
    extends State<InsurancePurchaseScreen> {
  final _supabase = Supabase.instance.client;

  static const Color _indigo = Color(0xFF6366F1);
  static const Color _green  = Color(0xFF10B981);

  String _selectedMethod = 'esewa';
  bool _isProcessing = false;

  // ── Fee breakdown ────────────────────────────────────────
  BookingFeeBreakdown? _feeBreakdown;
  bool _feeLoading = true;

  final List<Map<String, dynamic>> _methods = [
    {
      'id':    'esewa',
      'name':  'eSewa',
      'color': const Color(0xFF60BB46),
      'icon':  Icons.account_balance_wallet_rounded,
    },
    {
      'id':    'khalti',
      'name':  'Khalti',
      'color': const Color(0xFF5C2D91),
      'icon':  Icons.wallet_rounded,
    },
    {
      'id':    'connectips',
      'name':  'Connect IPS',
      'color': const Color(0xFF00408F),
      'icon':  Icons.account_balance_rounded,
    },
    {
      'id':    'cod',
      'name':  'Pay at Hospital',
      'color': const Color(0xFF64748B),
      'icon':  Icons.payments_rounded,
    },
  ];

  // ── Plan getters ─────────────────────────────────────────
  double get _price =>
      double.tryParse(widget.plan['price']?.toString() ?? '0') ?? 0;
  int    get _discount => widget.plan['discount'] ?? 0;
  double get _discountedPrice => _price - (_price * (_discount / 100));
  String get _planName =>
      widget.plan['name']?.toString() ?? 'Insurance Plan';
  String get _hospitalName =>
      widget.plan['hospital_name']?.toString() ?? 'Verified Hospital';

  // ── Fee getters ──────────────────────────────────────────
  double get _convenienceFee => _feeBreakdown?.convenienceFee ?? 30;
  double get _totalPayable =>
      _feeBreakdown?.totalPayable ?? _discountedPrice + 30;

  @override
  void initState() {
    super.initState();
    _loadFeeBreakdown();
  }

  Future<void> _loadFeeBreakdown() async {
    try {
      final hospitalId =
          widget.plan['hospital_id']?.toString() ?? '';
      final breakdown = await BookingFeeService.forInsurance(
        hospitalId: hospitalId,
        baseAmount:  _discountedPrice,
      );
      if (mounted) {
        setState(() {
          _feeBreakdown = breakdown;
          _feeLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Insurance fee load error: $e');
      if (mounted) setState(() => _feeLoading = false);
    }
  }

  Future<void> _handlePurchase() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    setState(() => _isProcessing = true);

    try {
      await _supabase.from('insurance_subscriptions').insert({
        'patient_id':     user.id,
        'hospital_id':    widget.plan['hospital_id'],
        'plan_id':        widget.plan['id'],
        'amount_paid':    _totalPayable,    // total including convenience fee
        'claim_amount':   0,
        'payment_method': _selectedMethod,
        'status':         'pending',
      });

      if (!mounted) return;
      _showSuccess();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Purchase failed: ${e.toString()}'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _showSuccess() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28)),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  color: Color(0xFFF0FDF4),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_rounded,
                    color: _green, size: 40),
              ),
              const SizedBox(height: 20),
              const Text(
                'Request Submitted!',
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Your request for $_planName has been submitted. The hospital will review and notify you within 24 hours.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary(context), fontSize: 14),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    // Pop dialog then go home safely regardless of stack depth
                    Navigator.of(context).pop(); // close dialog
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _indigo,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Done',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg(context),
      appBar: AppBar(
        title: Text(
          'Purchase Plan',
          style: TextStyle(
              color: AppColors.textPrimary(context), fontWeight: FontWeight.bold),
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
            const SizedBox(height: 28),
            const Text(
              'Payment Method',
              style:
                  TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 14),
            ..._methods.map((m) => _buildMethodTile(m)),
            const SizedBox(height: 120),
          ],
        ),
      ),
      bottomSheet: _buildBottomBar(),
    );
  }

  Widget _buildOrderSummary() {
    final List<dynamic> benefits = widget.plan['benefits'] is List
        ? widget.plan['benefits']
        : (widget.plan['benefits']?.toString().split(',') ?? []);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow(context),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Plan header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _indigo.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.shield_rounded,
                    color: _indigo, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _planName,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                    Row(
                      children: [
                        const Icon(Icons.verified_rounded,
                            color: Colors.blue, size: 13),
                        const SizedBox(width: 4),
                        Text(
                          _hospitalName,
                          style: TextStyle(
                              color: AppColors.textMuted(context), fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Benefits
          if (benefits.isNotEmpty) ...[
            const Divider(height: 28),
            Text(
              'Included Benefits',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMuted(context)),
            ),
            const SizedBox(height: 10),
            ...benefits.take(4).map((b) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_rounded,
                          color: _green, size: 15),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          b.toString().trim(),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                )),
          ],

          const Divider(height: 28),

          // Price breakdown
          if (_discount > 0) ...[
            _priceRow(
              'Original Price',
              'Rs. ${_price.toStringAsFixed(0)}',
              strikethrough: true,
            ),
            const SizedBox(height: 6),
            _priceRow(
              'Discount ($_discount%)',
              '- Rs. ${(_price * _discount / 100).toStringAsFixed(0)}',
              color: _green,
            ),
            const Divider(height: 20),
            _priceRow(
              'Plan Price',
              'Rs. ${_discountedPrice.toStringAsFixed(0)}',
            ),
            const SizedBox(height: 6),
          ],

          // Fee breakdown from Supabase
          if (_feeLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else ...[
            if (_discount == 0)
              _priceRow(
                'Plan Price',
                'Rs. ${_discountedPrice.toStringAsFixed(0)}',
              ),
            const SizedBox(height: 6),
            _priceRow(
              'Convenience Fee',
              'Rs. ${_convenienceFee.toStringAsFixed(0)}',
              sub: 'Platform service charge',
            ),
            const Divider(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Total Payable',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16),
                ),
                Text(
                  'Rs. ${_totalPayable.toStringAsFixed(0)}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 20,
                      color: _indigo),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _priceRow(
    String label,
    String value, {
    bool strikethrough = false,
    Color? color,
    String? sub,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(
                    color: color ?? Colors.grey[600], fontSize: 13)),
            if (sub != null)
              Text(sub,
                  style: TextStyle(
                      fontSize: 11, color: AppColors.textMuted(context))),
          ],
        ),
        Text(
          value,
          style: TextStyle(
            decoration:
                strikethrough ? TextDecoration.lineThrough : null,
            color: color ?? Colors.grey,
            fontSize: 13,
          ),
        ),
      ],
    );
  }

  Widget _buildMethodTile(Map<String, dynamic> method) {
    final isSelected = _selectedMethod == method['id'];
    return GestureDetector(
      onTap: () => setState(() => _selectedMethod = method['id']),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.cardBg(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? _indigo : AppColors.surfaceBg(context),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              height: 42,
              width: 42,
              decoration: BoxDecoration(
                color: (method['color'] as Color).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(method['icon'] as IconData,
                  color: method['color'] as Color, size: 22),
            ),
            const SizedBox(width: 14),
            Text(
              method['name'],
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const Spacer(),
            Icon(
              isSelected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_off_rounded,
              color: isSelected ? _indigo : Colors.grey[300],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, MediaQuery.of(context).padding.bottom + 16),
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow(context),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: (_isProcessing || _feeLoading)
            ? null
            : _handlePurchase,
        style: ElevatedButton.styleFrom(
          backgroundColor: _indigo,
          minimumSize: const Size(double.infinity, 56),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          elevation: 0,
        ),
        child: _isProcessing
            ? SizedBox(
                height: 22,
                width: 22,
                child: const CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2),
              )
            : Text(
                _feeLoading
                    ? 'Calculating...'
                    : _selectedMethod == 'cod'
                        ? 'Confirm & Pay at Hospital'
                        : 'Pay Rs. ${_totalPayable.toStringAsFixed(0)}',
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16),
              ),
      ),
    );
  }
}
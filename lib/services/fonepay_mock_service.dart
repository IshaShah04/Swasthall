// lib/services/fonepay_mock_service.dart
//
// ─── FonePay MOCK / TEST SANDBOX ────────────────────────────────────────────
//
// FonePay does not offer a self-service public sandbox like eSewa.
// Production API access requires direct merchant registration.
//
// This service provides a SAFE TEST STRUCTURE that:
//   • Simulates the FonePay UI / UX flow.
//   • Lets you test the full payment screen → success/failure flow.
//   • Uses NO real API calls, credentials, or money.
//   • Marks transactions with payment_method = 'fonepay_mock' in the DB
//     so they are clearly distinguishable from live payments.
//   • Is architecturally identical to what a real FonePay integration will
//     look like — only the inner _callFonePayApi() method changes when you
//     obtain real merchant credentials.
//
// TO UPGRADE TO REAL FONEPAY:
//   1. Create a Supabase edge function `fonepay-initiate` (similar to esewa-initiate).
//   2. Store FONEPAY_MERCHANT_CODE and FONEPAY_SECRET_KEY in Supabase secrets.
//   3. Replace _callFonePayApi() below with a call to that edge function.
//   4. Create a `fonepay-verify` edge function for callback verification.
//   5. Remove the isMock flag.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';

class FonePayMockResult {
  final bool confirmed;

  /// Always 'fonepay_mock' in test mode.
  /// Change to 'fonepay' when real integration is live.
  final String paymentMethod;

  /// Fake transaction reference for test records.
  final String mockTransactionRef;

  const FonePayMockResult({
    required this.confirmed,
    this.paymentMethod = 'fonepay_mock',
    this.mockTransactionRef = '',
  });
}

class FonePayMockService {
  /// Shows a realistic mock FonePay payment UI and returns whether the user
  /// "confirmed" the mock payment.
  static Future<FonePayMockResult> showMockDialog(
    BuildContext context, {
    required double amount,
  }) async {
    if (kReleaseMode) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('FonePay test mode is disabled in release builds.'),
        ),
      );
      return const FonePayMockResult(confirmed: false);
    }

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _FonePayMockDialog(amount: amount),
    );

    if (result != true) {
      return const FonePayMockResult(confirmed: false);
    }

    // Generate a fake transaction reference so DB records look realistic
    final fakeRef =
        'FP-MOCK-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}';

    return FonePayMockResult(
      confirmed: true,
      paymentMethod: 'fonepay_mock',
      mockTransactionRef: fakeRef,
    );
  }
}

// ─── Mock UI dialog ───────────────────────────────────────────────────────────

class _FonePayMockDialog extends StatefulWidget {
  final double amount;
  const _FonePayMockDialog({required this.amount});

  @override
  State<_FonePayMockDialog> createState() => _FonePayMockDialogState();
}

class _FonePayMockDialogState extends State<_FonePayMockDialog> {
  bool _processing = false;

  Future<void> _onConfirm() async {
    setState(() => _processing = true);
    // Simulate a short network delay (mimics real gateway latency)
    await Future.delayed(const Duration(milliseconds: 1800));
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6A1B9A),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'fonepay',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.orange.shade300),
                  ),
                  child: Text(
                    'TEST MODE',
                    style: TextStyle(
                      color: Colors.orange.shade800,
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ── Amount ───────────────────────────────────────────────────────
            Text(
              'Rs. ${widget.amount.toStringAsFixed(0)}',
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Consultation / Lab Payment',
              style: TextStyle(color: Color(0xFF64748B), fontSize: 14),
            ),
            const SizedBox(height: 20),

            // ── Test notice ──────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline,
                      size: 16, color: Colors.orange.shade800),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'FonePay sandbox is not yet available. '
                      'This simulates the payment flow for testing. '
                      'No real money is moved.',
                      style: TextStyle(
                          fontSize: 12, color: Colors.orange.shade900),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── Mock mobile number field (visual only) ───────────────────────
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFCBD5E1)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                children: [
                  Text('+977 ', style: TextStyle(color: Color(0xFF64748B))),
                  Text('98XXXXXXXX [Test User]',
                      style: TextStyle(
                          color: Color(0xFF64748B),
                          fontStyle: FontStyle.italic)),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── Buttons ──────────────────────────────────────────────────────
            if (_processing)
              const SizedBox(
                height: 48,
                child: Center(
                  child: CircularProgressIndicator(color: Color(0xFF6A1B9A)),
                ),
              )
            else
              Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _onConfirm,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6A1B9A),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text(
                        'Confirm Mock Payment',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(color: Color(0xFF64748B)),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

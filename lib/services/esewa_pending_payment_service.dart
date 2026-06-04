import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class PendingEsewaPayment {
  final String transactionUuid;
  final String checkoutUrl;
  final String totalAmount;
  final int startedAtMillis;

  const PendingEsewaPayment({
    required this.transactionUuid,
    required this.checkoutUrl,
    required this.totalAmount,
    required this.startedAtMillis,
  });

  Map<String, dynamic> toJson() => {
        'transaction_uuid': transactionUuid,
        'checkout_url': checkoutUrl,
        'total_amount': totalAmount,
        'started_at_millis': startedAtMillis,
      };

  factory PendingEsewaPayment.fromJson(Map<String, dynamic> json) =>
      PendingEsewaPayment(
        transactionUuid: json['transaction_uuid']?.toString() ?? '',
        checkoutUrl: json['checkout_url']?.toString() ?? '',
        totalAmount: json['total_amount']?.toString() ?? '0',
        startedAtMillis: (json['started_at_millis'] as num?)?.toInt() ?? 0,
      );
}

class EsewaPendingPaymentService {
  static const _key = 'pending_esewa_payment_v1';

  static Future<void> save(PendingEsewaPayment payment) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(payment.toJson()));
  }

  static Future<PendingEsewaPayment?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return null;

    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return PendingEsewaPayment.fromJson(decoded);
    } catch (_) {
      await prefs.remove(_key);
      return null;
    }
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

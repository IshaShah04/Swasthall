import 'dart:async';

import 'package:flutter/material.dart';
import 'package:khalti_checkout_flutter/khalti_checkout_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../config/env_config.dart';

class KhaltiInitiateResult {
  final String pidx;
  final String purchaseOrderId;
  final String purchaseOrderName;
  final String? expiresAt;

  const KhaltiInitiateResult({
    required this.pidx,
    required this.purchaseOrderId,
    required this.purchaseOrderName,
    this.expiresAt,
  });

  factory KhaltiInitiateResult.fromJson(Map<String, dynamic> json) {
    return KhaltiInitiateResult(
      pidx: json['pidx']?.toString() ?? '',
      purchaseOrderId: json['purchase_order_id']?.toString() ?? '',
      purchaseOrderName: json['purchase_order_name']?.toString() ?? '',
      expiresAt: json['expires_at']?.toString(),
    );
  }
}

class KhaltiVerifyResult {
  final bool verified;
  final String status;
  final String pidx;
  final String transactionCode;
  final String totalAmount;
  final String? error;

  const KhaltiVerifyResult({
    required this.verified,
    required this.status,
    required this.pidx,
    required this.transactionCode,
    required this.totalAmount,
    this.error,
  });

  bool get isComplete => verified && status.toLowerCase() == 'completed';

  bool get isPending {
    final normalized = status.toLowerCase();
    return normalized == 'pending' ||
        normalized == 'initiated' ||
        normalized == 'created';
  }

  bool get isTerminalFailure {
    const terminal = <String>{
      'failed',
      'error',
      'expired',
      'canceled',
      'cancelled',
      'refunded',
      'not_found',
      'invalid',
      'user canceled',
    };
    return terminal.contains(status.toLowerCase());
  }

  factory KhaltiVerifyResult.fromJson(Map<String, dynamic> json) {
    return KhaltiVerifyResult(
      verified: json['verified'] == true,
      status: json['status']?.toString() ?? 'UNKNOWN',
      pidx: json['pidx']?.toString() ?? '',
      transactionCode: json['transaction_code']?.toString() ?? '',
      totalAmount: json['total_amount']?.toString() ?? '0',
      error: json['error']?.toString(),
    );
  }

  factory KhaltiVerifyResult.failure(
    String reason, {
    String status = 'FAILED',
    String pidx = '',
    String totalAmount = '0',
  }) {
    return KhaltiVerifyResult(
      verified: false,
      status: status,
      pidx: pidx,
      transactionCode: '',
      totalAmount: totalAmount,
      error: reason,
    );
  }
}

class KhaltiSdkPaymentService {
  static final _supabase = Supabase.instance.client;
  static final _uuid = const Uuid();
  static const _timeout = Duration(minutes: 8);

  static Future<String> _freshAccessToken() async {
    final current = _supabase.auth.currentSession;
    if (current == null) {
      throw Exception('Please sign in again before payment.');
    }

    Session? session;
    try {
      final refreshed = await _supabase.auth.refreshSession();
      session = refreshed.session ?? _supabase.auth.currentSession;
    } catch (_) {
      session = _supabase.auth.currentSession;
    }

    final accessToken = session?.accessToken;
    if (accessToken == null || accessToken.isEmpty) {
      throw Exception('Session expired. Please sign in again.');
    }
    return accessToken;
  }

  static Future<FunctionResponse> _invokeAuthed(
    String functionName, {
    Map<String, dynamic>? body,
  }) async {
    final accessToken = await _freshAccessToken();
    return _supabase.functions.invoke(
      functionName,
      headers: {
        'Authorization': 'Bearer $accessToken',
      },
      body: body,
    );
  }

  static Future<KhaltiInitiateResult> initiate({
    required int amountPaisa,
    required String purchaseOrderId,
    required String purchaseOrderName,
    required String orderType,
    required String orderId,
    String? customerName,
    String? customerEmail,
    String? customerPhone,
  }) async {
    final response = await _invokeAuthed(
      'khalti-initiate',
      body: {
        'amount_paisa': amountPaisa,
        'purchase_order_id': purchaseOrderId,
        'purchase_order_name': purchaseOrderName,
        'order_type': orderType,
        'order_id': orderId,
        'customer_name': customerName,
        'customer_email': customerEmail,
        'customer_phone': customerPhone,
      },
    );

    if (response.status != 200) {
      final msg = (response.data as Map?)?['error'] ??
          (response.data as Map?)?['message'] ??
          'khalti-initiate failed (${response.status})';
      throw Exception(msg.toString());
    }

    return KhaltiInitiateResult.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  static Future<KhaltiVerifyResult> verify({
    required String pidx,
    required int amountPaisa,
  }) async {
    final response = await _invokeAuthed(
      'khalti-verify',
      body: {
        'pidx': pidx,
        'amount_paisa': amountPaisa,
      },
    );

    final map = Map<String, dynamic>.from(
      (response.data as Map?) ?? <String, dynamic>{},
    );

    if (response.status == 200 || response.status == 400) {
      return KhaltiVerifyResult.fromJson(map);
    }

    final msg =
        map['error'] ?? map['message'] ?? 'khalti-verify failed (${response.status})';
    return KhaltiVerifyResult.failure(
      msg.toString(),
      status: 'UNKNOWN',
      pidx: pidx,
      totalAmount: amountPaisa.toString(),
    );
  }

  static Future<KhaltiVerifyResult> start({
    required BuildContext context,
    double? amount,
    String? bookingId,
    required String orderType,
    required String orderIdSeed,
    required String productName,
    String? customerName,
    String? customerEmail,
    String? customerPhone,
  }) async {
    final publicKey = EnvConfig.khaltiPublicKey.trim();
    if (publicKey.isEmpty) {
      return KhaltiVerifyResult.failure(
        'Khalti SDK is not configured in this build. Add KHALTI_PUBLIC_KEY and rebuild the app.',
        status: 'CONFIG_ERROR',
      );
    }
    if (EnvConfig.supabaseUrl.trim().isEmpty) {
      return KhaltiVerifyResult.failure(
        'Supabase URL is missing. Please rebuild the app with valid env values.',
        status: 'CONFIG_ERROR',
      );
    }

    // Security: When bookingId is provided, fetch the authoritative amount
    // from the server instead of trusting the client-supplied value.
    double resolvedAmount;
    if (bookingId != null && bookingId.isNotEmpty) {
      try {
        final feeRes = await _supabase
            .rpc('get_booking_fee', params: {'p_booking_id': bookingId});
        resolvedAmount = (feeRes as num).toDouble();
      } catch (e) {
        return KhaltiVerifyResult.failure(
          'Could not fetch booking fee from server: $e',
          status: 'FEE_FETCH_FAILED',
        );
      }
    } else if (amount != null) {
      resolvedAmount = amount;
    } else {
      return KhaltiVerifyResult.failure(
        'Either amount or bookingId must be provided.',
        status: 'CONFIG_ERROR',
      );
    }

    final amountPaisa = (resolvedAmount * 100).round();
    final purchaseOrderId = _buildPurchaseOrderId(orderType, orderIdSeed);

    final initiateResult = await initiate(
      amountPaisa: amountPaisa,
      purchaseOrderId: purchaseOrderId,
      purchaseOrderName: _truncate(productName, 120),
      orderType: orderType,
      orderId: orderIdSeed,
      customerName: customerName,
      customerEmail: customerEmail,
      customerPhone: customerPhone,
    );

    final environment = EnvConfig.khaltiEnvironment.toLowerCase() == 'live'
        ? Environment.prod
        : Environment.test;

    final completer = Completer<KhaltiVerifyResult>();
    var handled = false;

    void complete(KhaltiVerifyResult result) {
      if (handled || completer.isCompleted) return;
      handled = true;
      completer.complete(result);
    }

    Future<void> closeIfMounted(Khalti khaltiInstance) async {
      if (!context.mounted) return;
      try {
        khaltiInstance.close(context);
      } catch (_) {}
    }

    Future<void> handleServerVerify(String pidx) async {
      try {
        final verifyResult = await _pollVerify(
          pidx: pidx,
          amountPaisa: amountPaisa,
          attempts: 6,
        );
        complete(verifyResult);
      } catch (e) {
        complete(
          KhaltiVerifyResult.failure(
            'Verification failed: $e',
            status: 'FAILED',
            pidx: pidx,
            totalAmount: amountPaisa.toString(),
          ),
        );
      }
    }

    Khalti? khalti;

    try {
      khalti = await Khalti.init(
        enableDebugging: EnvConfig.khaltiEnvironment.toLowerCase() != 'live',
        payConfig: KhaltiPayConfig(
          publicKey: publicKey,
          pidx: initiateResult.pidx,
          environment: environment,
        ),
        onPaymentResult: (paymentResult, khaltiInstance) {
          final sdkPidx = paymentResult.payload?.pidx?.toString().trim();
          final finalPidx = (sdkPidx == null || sdkPidx.isEmpty)
              ? initiateResult.pidx
              : sdkPidx;
          unawaited(handleServerVerify(finalPidx));
          unawaited(closeIfMounted(khaltiInstance));
        },
        onMessage: (
          khaltiInstance, {
          description,
          statusCode,
          event,
          needsPaymentConfirmation,
        }) async {
          if (needsPaymentConfirmation == true) {
            try {
              await khaltiInstance.verify();
            } catch (_) {}
            final verifyResult = await _pollVerify(
              pidx: initiateResult.pidx,
              amountPaisa: amountPaisa,
              attempts: 6,
            );
            if (verifyResult.isComplete || verifyResult.isTerminalFailure) {
              complete(verifyResult);
              await closeIfMounted(khaltiInstance);
            }
            return;
          }

          final eventText = event?.toString().toLowerCase() ?? '';
          if (eventText.contains('kpgdisposed') && !handled) {
            final verifyResult = await _pollVerify(
              pidx: initiateResult.pidx,
              amountPaisa: amountPaisa,
              attempts: 2,
            );
            if (verifyResult.isComplete) {
              complete(verifyResult);
            } else {
              complete(
                KhaltiVerifyResult.failure(
                  description?.toString() ?? 'Payment was cancelled.',
                  status: 'CANCELLED',
                  pidx: initiateResult.pidx,
                  totalAmount: amountPaisa.toString(),
                ),
              );
            }
            return;
          }

          if (statusCode != null && statusCode >= 400 && !handled) {
            complete(
              KhaltiVerifyResult.failure(
                description?.toString() ?? 'Khalti SDK reported an error.',
                status: 'FAILED',
                pidx: initiateResult.pidx,
                totalAmount: amountPaisa.toString(),
              ),
            );
          }
        },
        onReturn: () {},
      );
    } catch (e) {
      return KhaltiVerifyResult.failure(
        'Could not start Khalti SDK payment: $e',
        status: 'FAILED',
        pidx: initiateResult.pidx,
        totalAmount: amountPaisa.toString(),
      );
    }

    if (!context.mounted) {
  return KhaltiVerifyResult.failure(
    'Payment screen is no longer active.',
    status: 'CANCELLED',
    pidx: initiateResult.pidx,
    totalAmount: amountPaisa.toString(),
  );
}

try {
  khalti.open(context);
} catch (e) {
  return KhaltiVerifyResult.failure(
    'Failed to open Khalti SDK: $e',
    status: 'FAILED',
    pidx: initiateResult.pidx,
    totalAmount: amountPaisa.toString(),
  );
}

    return completer.future.timeout(
      _timeout,
      onTimeout: () async {
        final verifyResult = await _pollVerify(
          pidx: initiateResult.pidx,
          amountPaisa: amountPaisa,
          attempts: 2,
        );
        if (verifyResult.isComplete) return verifyResult;
        return KhaltiVerifyResult.failure(
          verifyResult.error ?? 'Payment timed out. Please try again.',
          status: verifyResult.status == 'UNKNOWN' ? 'EXPIRED' : verifyResult.status,
          pidx: initiateResult.pidx,
          totalAmount: amountPaisa.toString(),
        );
      },
    );
  }

  static Future<KhaltiVerifyResult> _pollVerify({
    required String pidx,
    required int amountPaisa,
    int attempts = 6,
    Duration delay = const Duration(seconds: 2),
  }) async {
    KhaltiVerifyResult? last;
    for (var i = 0; i < attempts; i++) {
      final result = await verify(
        pidx: pidx,
        amountPaisa: amountPaisa,
      );
      last = result;
      if (result.isComplete || result.isTerminalFailure) {
        return result;
      }
      if (i < attempts - 1) {
        await Future<void>.delayed(delay);
      }
    }

    return last ?? KhaltiVerifyResult.failure(
      'Payment could not be confirmed.',
      status: 'UNKNOWN',
      pidx: pidx,
      totalAmount: amountPaisa.toString(),
    );
  }

  static String _buildPurchaseOrderId(String type, String seed) {
    final cleanType = type
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '')
        .toUpperCase();
    final cleanSeed = seed
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '')
        .toUpperCase();
    final suffix = _uuid.v4().replaceAll('-', '').substring(0, 12).toUpperCase();
    return _truncate('${cleanType}_${cleanSeed}_$suffix', 50);
  }

  static String _truncate(String value, int max) {
    if (value.length <= max) return value;
    return value.substring(0, max);
  }
}

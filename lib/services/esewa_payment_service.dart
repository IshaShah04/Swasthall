// lib/services/esewa_payment_service.dart
//
// Secure eSewa payment service.
// Browser-flow helpers are kept for backward compatibility, but SDK flows
// should use verifySdk() after the native payment succeeds.

import 'package:supabase_flutter/supabase_flutter.dart';

class EsewaInitiateResult {
  final String checkoutUrl;
  final String transactionUuid;
  final String totalAmount;

  const EsewaInitiateResult({
    required this.checkoutUrl,
    required this.transactionUuid,
    required this.totalAmount,
  });

  factory EsewaInitiateResult.fromJson(Map<String, dynamic> json) {
    return EsewaInitiateResult(
      checkoutUrl: json['checkout_url']?.toString() ?? '',
      transactionUuid: json['transaction_uuid']?.toString() ?? '',
      totalAmount: json['total_amount']?.toString() ?? '0',
    );
  }
}

class EsewaVerifyResult {
  final bool verified;
  final String status;
  final String transactionUuid;
  final String transactionCode;
  final String totalAmount;
  final String? error;

  const EsewaVerifyResult({
    required this.verified,
    required this.status,
    required this.transactionUuid,
    required this.transactionCode,
    required this.totalAmount,
    this.error,
  });

  bool get isComplete => verified && status.toUpperCase() == 'COMPLETE';

  bool get isPending {
    final normalized = status.toUpperCase();
    return normalized == 'PENDING' || normalized == 'INITIATED' || normalized == 'CREATED';
  }

  bool get isTerminalFailure {
    const terminal = <String>{
      'FAILED',
      'FAIL',
      'CANCELLED',
      'CANCELED',
      'FULL_REFUND',
      'PARTIAL_REFUND',
      'EXPIRED',
      'NOT_FOUND',
      'INVALID',
    };
    return terminal.contains(status.toUpperCase());
  }

  factory EsewaVerifyResult.fromJson(Map<String, dynamic> json) {
    final txCode = json['transaction_code']?.toString() ?? json['ref_id']?.toString() ?? '';
    return EsewaVerifyResult(
      verified: json['verified'] == true,
      status: json['status']?.toString() ?? 'UNKNOWN',
      transactionUuid: json['transaction_uuid']?.toString() ?? '',
      transactionCode: txCode,
      totalAmount: json['total_amount']?.toString() ?? '0',
      error: json['error']?.toString(),
    );
  }

  factory EsewaVerifyResult.failure(
    String reason, {
    String status = 'FAILED',
    String transactionUuid = '',
    String totalAmount = '0',
  }) {
    return EsewaVerifyResult(
      verified: false,
      status: status,
      transactionUuid: transactionUuid,
      transactionCode: '',
      totalAmount: totalAmount,
      error: reason,
    );
  }
}

class EsewaPaymentService {
  static final _supabase = Supabase.instance.client;

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

  static Future<EsewaInitiateResult> initiate({
    required double amount,
  }) async {
    final response = await _invokeAuthed(
      'esewa-initiate',
      body: {'amount': amount},
    );

    if (response.status != 200) {
      final msg = (response.data as Map?)?['error'] ??
          (response.data as Map?)?['message'] ??
          'esewa-initiate failed (${response.status})';
      throw Exception(msg.toString());
    }

    return EsewaInitiateResult.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  static Future<EsewaVerifyResult> verify({
    required String base64Data,
  }) async {
    if (base64Data.isEmpty) {
      return EsewaVerifyResult.failure('Empty data from eSewa redirect');
    }

    final response = await _invokeAuthed(
      'esewa-verify',
      body: {'data': base64Data},
    );

    if (response.status != 200) {
      final msg = (response.data as Map?)?['error'] ??
          'esewa-verify failed (${response.status})';
      return EsewaVerifyResult.failure(msg.toString());
    }

    return EsewaVerifyResult.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  static Future<EsewaVerifyResult> checkStatus({
    required String transactionUuid,
  }) async {
    if (transactionUuid.trim().isEmpty) {
      return EsewaVerifyResult.failure('Missing transaction UUID', status: 'INVALID');
    }

    final response = await _invokeAuthed(
      'esewa-status',
      body: {'transaction_uuid': transactionUuid.trim()},
    );

    if (response.status != 200) {
      final msg = (response.data as Map?)?['error'] ??
          'esewa-status failed (${response.status})';
      return EsewaVerifyResult.failure(
        msg.toString(),
        status: 'UNKNOWN',
        transactionUuid: transactionUuid.trim(),
      );
    }

    return EsewaVerifyResult.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  static Future<EsewaVerifyResult> verifySdk({
    required String refId,
    required String productId,
    required String amount,
  }) async {
    final response = await _invokeAuthed(
      'esewa-verify-sdk',
      body: {
        'ref_id': refId,
        'product_id': productId,
        'amount': amount,
      },
    );

    if (response.status != 200) {
      final msg = (response.data as Map?)?['error'] ??
          (response.data as Map?)?['message'] ??
          'esewa-verify-sdk failed (${response.status})';
      return EsewaVerifyResult.failure(
        msg.toString(),
        status: 'UNKNOWN',
        transactionUuid: productId,
        totalAmount: amount,
      );
    }

    return EsewaVerifyResult.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }
}

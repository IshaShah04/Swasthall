import 'dart:async';

import 'package:esewa_flutter_sdk/esewa_config.dart';
import 'package:esewa_flutter_sdk/esewa_flutter_sdk.dart';
import 'package:esewa_flutter_sdk/esewa_payment.dart';
import 'package:esewa_flutter_sdk/esewa_payment_success_result.dart';
import 'package:uuid/uuid.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/env_config.dart';
import 'esewa_payment_service.dart';

class EsewaSdkPaymentService {
  static const _timeout = Duration(minutes: 6);
  static final _uuid = Uuid();

  static Future<EsewaVerifyResult> start({
    double? amount,
    String? bookingId,
    required String productName,
    required String productIdSeed,
    String orderType = 'consultation',
    String? orderId,
    String? ebpNo,
  }) async {
    final clientId = EnvConfig.esewaSdkClientId.trim();
    if (clientId.isEmpty) {
      return EsewaVerifyResult.failure(
        'eSewa SDK is not configured in this build. Add ESEWA_SDK_CLIENT_ID to env.json.',
        status: 'CONFIG_ERROR',
      );
    }
    if (EnvConfig.supabaseUrl.trim().isEmpty) {
      return EsewaVerifyResult.failure(
        'Supabase URL is missing. Please rebuild the app with valid env values.',
        status: 'CONFIG_ERROR',
      );
    }

    // Security: When bookingId is provided, fetch the authoritative amount
    // from the server instead of trusting the client-supplied value.
    double resolvedAmount;
    if (bookingId != null && bookingId.isNotEmpty) {
      try {
        final feeRes = await Supabase.instance.client
            .rpc('get_booking_fee', params: {'p_booking_id': bookingId});
        resolvedAmount = (feeRes as num).toDouble();
      } catch (e) {
        return EsewaVerifyResult.failure(
          'Could not fetch booking fee from server: $e',
          status: 'FEE_FETCH_FAILED',
        );
      }
    } else if (amount != null) {
      resolvedAmount = amount;
    } else {
      return EsewaVerifyResult.failure(
        'Either amount or bookingId must be provided.',
        status: 'CONFIG_ERROR',
      );
    }

    // Fetch the SDK secret from the server-side edge function.
    final String secretId;
    try {
      final secretRes = await Supabase.instance.client.functions
          .invoke('esewa-initiate', body: {'action': 'get_sdk_secret'});
      secretId = ((secretRes.data as Map?)?['secret_id'] ?? '').toString().trim();
      if (secretId.isEmpty) {
        return EsewaVerifyResult.failure(
          'Could not retrieve eSewa SDK secret from server.',
          status: 'CONFIG_ERROR',
        );
      }
    } catch (e) {
      return EsewaVerifyResult.failure(
        'Failed to fetch eSewa SDK secret: $e',
        status: 'CONFIG_ERROR',
      );
    }

    final environment = EnvConfig.esewaSdkEnvironment.toLowerCase() == 'live'
        ? Environment.live
        : Environment.test;

    final productId = _buildProductId(productIdSeed); // merchant transaction id used for strict verification

    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser == null) {
      return EsewaVerifyResult.failure(
        'Please sign in again before payment.',
        status: 'AUTH_REQUIRED',
        transactionUuid: productId,
        totalAmount: resolvedAmount.toStringAsFixed(2),
      );
    }

    try {
      await Supabase.instance.client.from('payment_transactions').insert({
        'user_id': currentUser.id,
        'provider': 'esewa',
        'order_type': orderType,
        'order_id': orderId ?? productIdSeed,
        'merchant_txn_id': productId,
        'amount_paisa': (resolvedAmount * 100).round(),
        'currency': 'NPR',
        'status': 'initiated',
        'verified': false,
        'raw_initiate_payload': {
          'source': 'esewa_flutter_sdk',
          'product_name': productName,
          'product_id_seed': productIdSeed,
        },
      });
    } catch (e) {
      return EsewaVerifyResult.failure(
        'Could not prepare eSewa payment transaction: $e',
        status: 'INIT_FAILED',
        transactionUuid: productId,
        totalAmount: resolvedAmount.toStringAsFixed(2),
      );
    }

    final callbackUrl =
        '${EnvConfig.supabaseUrl.replaceAll(RegExp(r'/+$'), '')}/functions/v1/esewa-sdk-callback';

    final completer = Completer<EsewaVerifyResult>();
    var handled = false;

    void complete(EsewaVerifyResult result) {
      if (handled || completer.isCompleted) return;
      handled = true;
      completer.complete(result);
    }

    Future<void> onSuccess(EsewaPaymentSuccessResult success) async {
      try {
        final verifyResult = await EsewaPaymentService.verifySdk(
          refId: success.refId,
          productId: success.productId,
          amount: success.totalAmount,
        );
        complete(verifyResult);
      } catch (e) {
        complete(
          EsewaVerifyResult.failure(
            'Verification failed: $e',
            status: 'FAILED',
            transactionUuid: success.productId, // SDK productId doubles as merchant transaction id
            totalAmount: success.totalAmount,
          ),
        );
      }
    }

    void onFailure(dynamic error) {
  final raw = error?.toString().trim() ?? '';
  complete(
    EsewaVerifyResult.failure(
      raw.isEmpty ? 'eSewa request could not be processed.' : 'eSewa failed: $raw',
      status: 'FAILED',
      transactionUuid: productId,
      totalAmount: resolvedAmount.toStringAsFixed(2),
    ),
  );
}

    void onCancellation(dynamic _) {
      complete(
        EsewaVerifyResult.failure(
          'Payment was cancelled.',
          status: 'CANCELLED',
          transactionUuid: productId,
          totalAmount: resolvedAmount.toStringAsFixed(2),
        ),
      );
    }

    try {
      EsewaFlutterSdk.initPayment(
        esewaConfig: EsewaConfig(
          clientId: clientId,
          secretId: secretId, // fetched from server-side edge function
          environment: environment,
        ),
        esewaPayment: EsewaPayment(
          productId: productId,
          productName: _truncate(productName, 60),
          productPrice: resolvedAmount.toStringAsFixed(2),
          callbackUrl: callbackUrl,
          ebpNo: ebpNo,
        ),
        onPaymentSuccess: (success) {
          unawaited(onSuccess(success));
        },
        onPaymentFailure: onFailure,
        onPaymentCancellation: onCancellation,
      );
    } catch (e) {
      return EsewaVerifyResult.failure(
        'Could not start eSewa SDK payment: $e',
        status: 'FAILED',
        transactionUuid: productId,
        totalAmount: resolvedAmount.toStringAsFixed(2),
      );
    }

    return completer.future.timeout(
      _timeout,
      onTimeout: () => EsewaVerifyResult.failure(
        'Payment timed out. Please try again.',
        status: 'EXPIRED',
        transactionUuid: productId,
        totalAmount: resolvedAmount.toStringAsFixed(2),
      ),
    );
  }

  static String _buildProductId(String seed) {
    final cleanSeed = seed
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '')
        .toUpperCase();
    final prefix = cleanSeed.isEmpty ? 'SWASTHALL' : cleanSeed;
    final suffix =
        _uuid.v4().replaceAll('-', '').substring(0, 12).toUpperCase();
    return _truncate('${prefix}_$suffix', 40);
  }

  static String _truncate(String value, int max) {
    if (value.length <= max) return value;
    return value.substring(0, max);
  }

}

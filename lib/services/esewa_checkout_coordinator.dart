import 'dart:async';

import 'package:url_launcher/url_launcher.dart';

import 'esewa_callback_handler.dart';
import 'esewa_payment_service.dart';
import 'esewa_pending_payment_service.dart';

class EsewaCheckoutCoordinator {
  static const Duration _maxWait = Duration(minutes: 10);
  static const Duration _pollInterval = Duration(seconds: 4);

  static Future<EsewaVerifyResult> start({
    required double amount,
  }) async {
    EsewaInitiateResult initiateResult;
    try {
      initiateResult = await EsewaPaymentService.initiate(amount: amount);
    } catch (e) {
      return EsewaVerifyResult.failure('Could not start eSewa checkout: $e');
    }

    if (initiateResult.checkoutUrl.trim().isEmpty) {
      return EsewaVerifyResult.failure('Server did not return a checkout URL.');
    }

    await EsewaPendingPaymentService.save(
      PendingEsewaPayment(
        transactionUuid: initiateResult.transactionUuid,
        checkoutUrl: initiateResult.checkoutUrl,
        totalAmount: initiateResult.totalAmount,
        startedAtMillis: DateTime.now().millisecondsSinceEpoch,
      ),
    );

    final callbackCompleter = Completer<Uri?>();
    EsewaCallbackHandler.register(callbackCompleter);

    final launched = await _launchCheckout(initiateResult.checkoutUrl);
    if (!launched) {
      EsewaCallbackHandler.cancel();
      await EsewaPendingPaymentService.clear();
      return EsewaVerifyResult.failure(
        'Could not open the eSewa checkout page on this device.',
        transactionUuid: initiateResult.transactionUuid,
      );
    }

    try {
      return await _waitForResolution(
        callbackCompleter: callbackCompleter,
        transactionUuid: initiateResult.transactionUuid,
      );
    } finally {
      EsewaCallbackHandler.cancel();
    }
  }

  static Future<bool> _launchCheckout(String rawUrl) async {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null) return false;

    try {
      final ok = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
      if (ok) return true;
    } catch (_) {}

    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (ok) return true;
    } catch (_) {}

    return false;
  }

  static Future<EsewaVerifyResult> _waitForResolution({
    required Completer<Uri?> callbackCompleter,
    required String transactionUuid,
  }) async {
    final deadline = DateTime.now().add(_maxWait);
    Uri? callbackUri;

    while (DateTime.now().isBefore(deadline)) {
      final remaining = deadline.difference(DateTime.now());
      final tick = remaining < _pollInterval ? remaining : _pollInterval;
      final event = await Future.any<Object?>([
        callbackCompleter.future.then<Object?>((value) => value),
        Future.delayed(tick, () => _PollTick.instance),
      ]);

      if (event is Uri?) {
        callbackUri = event;
        break;
      }

      final statusResult = await EsewaPaymentService.checkStatus(
        transactionUuid: transactionUuid,
      );
      if (statusResult.isComplete || statusResult.isTerminalFailure) {
        await EsewaPendingPaymentService.clear();
        return statusResult;
      }
    }

    final finalResult = await _resolveFromCallbackOrStatus(
      callbackUri: callbackUri,
      transactionUuid: transactionUuid,
    );
    await EsewaPendingPaymentService.clear();
    return finalResult;
  }

  static Future<EsewaVerifyResult> _resolveFromCallbackOrStatus({
    required Uri? callbackUri,
    required String transactionUuid,
  }) async {
    if (callbackUri == null) {
      final statusResult = await EsewaPaymentService.checkStatus(
        transactionUuid: transactionUuid,
      );
      if (statusResult.isComplete || statusResult.isTerminalFailure) {
        return statusResult;
      }
      return EsewaVerifyResult.failure(
        'Payment timed out. If money was deducted, reopen the app and contact support if the booking is still not confirmed.',
        status: statusResult.status,
        transactionUuid: transactionUuid,
      );
    }

    if (callbackUri.host == 'esewa-failure') {
      final statusResult = await EsewaPaymentService.checkStatus(
        transactionUuid: transactionUuid,
      );
      if (statusResult.isComplete) {
        return statusResult;
      }
      return EsewaVerifyResult.failure(
        statusResult.error ?? 'eSewa payment was cancelled or failed.',
        status: statusResult.status,
        transactionUuid: transactionUuid,
      );
    }

    final base64Data = callbackUri.queryParameters['data']?.trim() ?? '';
    if (base64Data.isNotEmpty) {
      final verifyResult = await EsewaPaymentService.verify(base64Data: base64Data);
      if (verifyResult.isComplete) {
        return verifyResult;
      }
    }

    final statusResult = await EsewaPaymentService.checkStatus(
      transactionUuid: transactionUuid,
    );
    if (statusResult.isComplete || statusResult.isTerminalFailure) {
      return statusResult;
    }

    return EsewaVerifyResult.failure(
      statusResult.error ?? 'Payment verification did not complete successfully.',
      status: statusResult.status,
      transactionUuid: transactionUuid,
    );
  }
}

class _PollTick {
  static const instance = _PollTick._();
  const _PollTick._();
}

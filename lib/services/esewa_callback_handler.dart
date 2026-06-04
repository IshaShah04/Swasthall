// lib/services/esewa_callback_handler.dart
//
// Bridges the eSewa browser payment flow back into the Flutter app.
// When eSewa redirects to swasthall://esewa-success?data=... or
// swasthall://esewa-failure, main.dart calls EsewaCallbackHandler.complete(uri).
// The waiting payment screen Completer unblocks and verifies.

import 'dart:async';

class EsewaCallbackHandler {
  EsewaCallbackHandler._();

  static Completer<Uri?>? _completer;

  /// Called by the payment screen just before opening the browser.
  static void register(Completer<Uri?> completer) {
    // Cancel any stale completer from a previous abandoned payment
    if (_completer != null && !_completer!.isCompleted) {
      _completer!.complete(null);
    }
    _completer = completer;
  }

  /// Called by main.dart _handleIncomingDeepLink when esewa-success/failure fires.
  static void complete(Uri uri) {
    if (_completer != null && !_completer!.isCompleted) {
      _completer!.complete(uri);
    }
    _completer = null;
  }

  /// Called on timeout or screen dispose to clean up.
  static void cancel() {
    if (_completer != null && !_completer!.isCompleted) {
      _completer!.complete(null);
    }
    _completer = null;
  }
}

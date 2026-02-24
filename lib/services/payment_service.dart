import 'dart:async';
import 'package:flutter/foundation.dart';

import '../models/payment_status.dart';

class MockPaymentService {
  // This simulates a network call to a payment gateway
  Future<PaymentStatus> processMockPayment(String method, double amount) async {
    if (kDebugMode) {
      print("Initiating $method payment for Rs $amount...");
    }
    
    // Simulate network delay
    await Future.delayed(const Duration(seconds: 2));

    // For now, let's make it always succeed
    // Later, you can add logic here to test "failure" cases
    return PaymentStatus.success;
  }
}
import 'package:supabase_flutter/supabase_flutter.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  BookingFeeService
//
//  Calls the Supabase `calculate_booking_fee` RPC function.
//  Dart NEVER computes fees — it only displays and passes values through.
//
//  Usage:
//    final fee = await BookingFeeService.calculate(
//      hospitalId:  doctorData['hospital_id'],
//      bookingType: 'physical',
//      baseAmount:  800,
//    );
//    // fee.totalPayable  → what patient pays
//    // fee.convenienceFee → Swasthall keeps
//    // fee.hospitalPayout → hospital gets monthly
// ─────────────────────────────────────────────────────────────────────────────

class BookingFeeBreakdown {
  final double baseAmount;
  final double convenienceFee;
  final double commissionRate;
  final double commissionAmount;
  final double totalPayable;
  final double hospitalPayout;

  const BookingFeeBreakdown({
    required this.baseAmount,
    required this.convenienceFee,
    required this.commissionRate,
    required this.commissionAmount,
    required this.totalPayable,
    required this.hospitalPayout,
  });

  @override
  String toString() =>
      'BookingFeeBreakdown(base=$baseAmount, convenience=$convenienceFee, '
      'commission=$commissionRate%=$commissionAmount, '
      'patientPays=$totalPayable, hospitalGets=$hospitalPayout)';
}

class BookingFeeException implements Exception {
  final String message;
  const BookingFeeException(this.message);
  @override
  String toString() => 'BookingFeeException: $message';
}

class BookingFeeService {
  static final _supabase = Supabase.instance.client;

  static Future<BookingFeeBreakdown> calculate({
    required String hospitalId,
    required String bookingType,
    required double baseAmount,
  }) async {
    try {
      final result = await _supabase.rpc(
        'calculate_booking_fee',
        params: {
          'p_hospital_id':  hospitalId,
          'p_booking_type': bookingType,
          'p_base_amount':  baseAmount,
        },
      );

      if (result == null) {
        // RPC returned null — do NOT fall back to client-side calculation.
        throw const BookingFeeException(
          'Fee calculation failed: RPC returned null. Cannot proceed.',
        );
      }

      final data = result as Map<String, dynamic>;
      return BookingFeeBreakdown(
        baseAmount:       _d(data['base_amount']),
        convenienceFee:   _d(data['convenience_fee']),
        commissionRate:   _d(data['commission_rate']),
        commissionAmount: _d(data['commission_amount']),
        totalPayable:     _d(data['total_payable']),
        hospitalPayout:   _d(data['hospital_payout']),
      );
    } catch (e) {
      // Do NOT fall back to client-side calculation — rethrow so
      // the caller can show a proper error to the user.
      throw BookingFeeException('Fee calculation failed: $e');
    }
  }

  static Future<BookingFeeBreakdown> forPhysical({
    required String hospitalId,
    required double baseAmount,
  }) =>
      calculate(hospitalId: hospitalId, bookingType: 'physical', baseAmount: baseAmount);

  static Future<BookingFeeBreakdown> forTelemedicine({
    required String hospitalId,
    required double baseAmount,
  }) =>
      calculate(hospitalId: hospitalId, bookingType: 'telemedicine', baseAmount: baseAmount);

  static Future<BookingFeeBreakdown> forLab({
    required String hospitalId,
    required double baseAmount,
  }) =>
      calculate(hospitalId: hospitalId, bookingType: 'lab', baseAmount: baseAmount);

  static Future<BookingFeeBreakdown> forInsurance({
    required String hospitalId,
    required double baseAmount,
  }) =>
      calculate(hospitalId: hospitalId, bookingType: 'insurance', baseAmount: baseAmount);

  static double _d(dynamic v) {
    if (v == null) return 0.0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }
}
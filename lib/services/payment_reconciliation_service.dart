import 'package:supabase_flutter/supabase_flutter.dart';

class PaymentReconciliationService {
  static final _supabase = Supabase.instance.client;

  /// Call this on every app launch after auth state is confirmed.
  /// Finds stuck 'initiated' transactions older than 15 minutes
  /// and attempts to verify them via the appropriate Edge Function.
  static Future<void> reconcileOnLaunch() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      // Find stuck transactions for current user
      // Use direct select here — this is a read query, RLS protects it
      final stuck = await _supabase
          .from('payment_transactions')
          .select('id, provider, merchant_txn_id, provider_session_id, amount_paisa')
          .eq('user_id', user.id)
          .eq('status', 'initiated')
          .eq('verified', false)
          .lt('created_at', 
              DateTime.now().subtract(const Duration(minutes: 15)).toIso8601String())
          .limit(10);

      if (stuck.isEmpty) return;

      for (final txn in stuck) {
        await _reconcileTransaction(txn);
      }
    } catch (e) {
      // Reconciliation is best-effort — never crash the app
    }
  }

  static Future<void> _reconcileTransaction(Map<String, dynamic> txn) async {
    final provider = txn['provider'] as String?;
    final merchantTxnId = txn['merchant_txn_id'] as String?;
    final providerSessionId = txn['provider_session_id'] as String?;
    final amountPaisa = txn['amount_paisa'] as int?;

    if (provider == null) return;

    try {
      switch (provider) {
        case 'khalti':
          if (providerSessionId == null) return;
          await _supabase.functions.invoke('khalti-verify', body: {
            'pidx': providerSessionId,
            'amount_paisa': amountPaisa ?? 0,
          });
          break;
        case 'esewa':
          // eSewa SDK stores provider as 'esewa'
          if (merchantTxnId == null) return;
          try {
            await _supabase.functions.invoke('esewa-verify-sdk', body: {
              'merchant_txn_id': merchantTxnId,
            });
          } catch (_) {
            // If esewa-verify-sdk fails, we can't auto-verify, mark as pending
            await _supabase.rpc('mark_payment_requires_review', params: {
              'p_merchant_txn_id': merchantTxnId,
            });
          }
          break;
      }
    } catch (_) {
      // Individual transaction failure should not stop reconciliation
    }
  }
}

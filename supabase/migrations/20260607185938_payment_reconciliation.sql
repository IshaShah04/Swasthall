-- Mark transactions stuck in 'initiated' for more than 30 minutes as 'failed'
-- This runs every 15 minutes via pg_cron
CREATE OR REPLACE FUNCTION reconcile_stuck_payments()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE payment_transactions
  SET 
    status = 'failed',
    error_message = 'Payment timed out — not verified within 30 minutes',
    updated_at = NOW()
  WHERE status = 'initiated'
  AND created_at < NOW() - INTERVAL '30 minutes'
  AND verified = false;
END;
$$;

-- Schedule reconciliation every 15 minutes
SELECT cron.schedule(
  'reconcile-stuck-payments',
  '*/15 * * * *',
  'SELECT reconcile_stuck_payments();'
);

CREATE OR REPLACE FUNCTION mark_payment_requires_review(
  p_merchant_txn_id TEXT
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE payment_transactions
  SET 
    status = 'pending',
    error_message = 'Could not auto-verify — pending manual review',
    updated_at = NOW()
  WHERE merchant_txn_id = p_merchant_txn_id
  AND user_id = auth.uid()
  AND verified = false;
END;
$$;

GRANT EXECUTE ON FUNCTION reconcile_stuck_payments TO postgres;
GRANT EXECUTE ON FUNCTION mark_payment_requires_review TO authenticated;

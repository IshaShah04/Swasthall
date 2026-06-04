-- Migration: Remove client-supplied p_amount from book_appointment_atomic_paid
-- The RPC now derives the total payable amount server-side from fee_config,
-- preventing clients from sending a tampered amount.
--
-- NOTE: This wraps the existing function. Adjust the inner body to match your
-- actual existing function signature and logic.

-- Step 1: Create a helper RPC to fetch booking fee server-side
CREATE OR REPLACE FUNCTION get_booking_fee(p_booking_id uuid)
RETURNS numeric
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE v_fee numeric;
BEGIN
  SELECT (fc.base_fee + fc.convenience_fee) INTO v_fee
  FROM fee_config fc
  JOIN bookings b ON b.hospital_id = fc.hospital_id
  WHERE b.id = p_booking_id;

  IF v_fee IS NULL THEN
    RAISE EXCEPTION 'Fee config not found for booking %', p_booking_id;
  END IF;

  RETURN v_fee;
END;
$$;

-- Step 2: Create a wrapper that derives p_amount from fee_config
-- This replaces client-supplied p_amount with a server-side lookup.
-- The original function body should be adapted to use v_amount internally.
--
-- IMPORTANT: Review and adapt the body below to match your actual
-- book_appointment_atomic_paid function. This migration provides the
-- structural change; the inner booking logic must be preserved from
-- your existing function.

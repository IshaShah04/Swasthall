-- RPC 1: record_payment_transaction
CREATE OR REPLACE FUNCTION record_payment_transaction(
  p_provider TEXT,
  p_order_type TEXT,
  p_order_id TEXT,
  p_merchant_txn_id TEXT,
  p_amount_paisa INTEGER,
  p_currency TEXT DEFAULT 'NPR',
  p_status TEXT DEFAULT 'initiated',
  p_raw_initiate_payload JSONB DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_expected_fee NUMERIC;
BEGIN
  -- Validate provider
  IF p_provider NOT IN ('esewa', 'khalti', 'fonepay', 'cash') THEN
    RAISE EXCEPTION 'Invalid payment provider: %', p_provider;
  END IF;

  -- Verify booking belongs to calling user (if order_type is consultation)
  IF p_order_type = 'consultation' THEN
    IF NOT EXISTS (
      SELECT 1 FROM bookings 
      WHERE id = p_order_id::uuid 
      AND user_id = auth.uid()
    ) THEN
      RAISE EXCEPTION 'Booking not found or access denied';
    END IF;

    -- Amount tamper protection
    SELECT fee INTO v_expected_fee FROM bookings WHERE id = p_order_id::uuid;
    IF v_expected_fee IS NOT NULL AND p_amount_paisa != ROUND(v_expected_fee * 100) THEN
      RAISE EXCEPTION 'Amount mismatch: expected % paisa, got % paisa', ROUND(v_expected_fee * 100), p_amount_paisa;
    END IF;
  END IF;

  INSERT INTO payment_transactions (
    user_id, provider, order_type, order_id, merchant_txn_id, 
    amount_paisa, currency, status, verified, raw_initiate_payload
  )
  VALUES (
    auth.uid(), p_provider, p_order_type, p_order_id, p_merchant_txn_id,
    p_amount_paisa, p_currency, p_status, false, p_raw_initiate_payload
  );
END;
$$;


-- RPC 2a: update_booking_status
CREATE OR REPLACE FUNCTION update_booking_status(
  p_booking_id UUID,
  p_status TEXT,
  p_patch JSONB DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_current_status TEXT;
  v_user_role TEXT;
BEGIN
  SELECT role INTO v_user_role FROM profiles WHERE id = auth.uid();
  SELECT status INTO v_current_status FROM bookings WHERE id = p_booking_id;

  IF v_current_status IS NULL THEN
    RAISE EXCEPTION 'Booking not found: %', p_booking_id;
  END IF;

  -- Validate allowed status values
  IF p_status NOT IN ('pending', 'confirmed', 'cancelled', 'completed', 'missed', 'triaged', 'calling', 'nurse_calling') THEN
    RAISE EXCEPTION 'Invalid status: %', p_status;
  END IF;

  -- Role-based transition rules
  IF p_status = 'cancelled' THEN
    IF v_user_role = 'patient' THEN
      IF NOT EXISTS (SELECT 1 FROM bookings WHERE id = p_booking_id AND user_id = auth.uid()) THEN
        RAISE EXCEPTION 'Access denied';
      END IF;
    ELSIF v_user_role NOT IN ('doctor', 'nurse', 'pharmacist', 'hospital', 'admin') THEN
      RAISE EXCEPTION 'Insufficient role to cancel booking';
    END IF;
  ELSIF p_status IN ('confirmed', 'completed', 'missed', 'triaged', 'calling', 'nurse_calling') THEN
    IF v_user_role NOT IN ('doctor', 'nurse', 'pharmacist', 'hospital', 'admin') THEN
      RAISE EXCEPTION 'Insufficient role to update booking status';
    END IF;
  END IF;

  -- If a patch is provided, update booking fields (like room_id, nurse_seen)
  IF p_patch IS NOT NULL THEN
    UPDATE bookings SET
      status = p_status,
      room_id = COALESCE(p_patch->>'room_id', room_id),
      patient_zego_uid = COALESCE(p_patch->>'patient_zego_uid', patient_zego_uid),
      provider_zego_uid = COALESCE(p_patch->>'provider_zego_uid', provider_zego_uid),
      nurse_seen = COALESCE((p_patch->>'nurse_seen')::boolean, nurse_seen),
      updated_at = NOW()
    WHERE id = p_booking_id;
  ELSE
    UPDATE bookings SET
      status = p_status,
      updated_at = NOW()
    WHERE id = p_booking_id;
  END IF;
END;
$$;


-- RPC 2b: update_lab_appointment_status
CREATE OR REPLACE FUNCTION update_lab_appointment_status(
  p_appointment_id UUID,
  p_status TEXT,
  p_patch JSONB DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_current_status TEXT;
  v_user_role TEXT;
BEGIN
  SELECT role INTO v_user_role FROM profiles WHERE id = auth.uid();
  SELECT status INTO v_current_status FROM lab_appointments WHERE id = p_appointment_id;

  IF v_current_status IS NULL THEN
    RAISE EXCEPTION 'Lab appointment not found: %', p_appointment_id;
  END IF;

  -- Only technicians and hospitals can update lab appointments
  IF v_user_role NOT IN ('technician', 'hospital', 'admin') THEN
    RAISE EXCEPTION 'Insufficient role to update lab appointment';
  END IF;

  IF p_patch IS NOT NULL THEN
    UPDATE lab_appointments SET
      status = p_status,
      nurse_seen = COALESCE((p_patch->>'nurse_seen')::boolean, nurse_seen),
      updated_at = NOW()
    WHERE id = p_appointment_id;
  ELSE
    UPDATE lab_appointments SET
      status = p_status,
      updated_at = NOW()
    WHERE id = p_appointment_id;
  END IF;
END;
$$;


GRANT EXECUTE ON FUNCTION record_payment_transaction TO authenticated;
GRANT EXECUTE ON FUNCTION update_booking_status TO authenticated;
GRANT EXECUTE ON FUNCTION update_lab_appointment_status TO authenticated;

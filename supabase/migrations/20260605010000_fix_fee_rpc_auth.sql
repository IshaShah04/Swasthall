CREATE OR REPLACE FUNCTION get_booking_fee(p_booking_id uuid)
RETURNS numeric
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_fee numeric;
BEGIN
  SELECT fee INTO v_fee
  FROM bookings b
  WHERE b.id = p_booking_id
    AND b.user_id = auth.uid();  -- ADD THIS LINE: enforce caller owns the booking

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Booking not found or access denied';
  END IF;

  RETURN v_fee;
END;
$$;

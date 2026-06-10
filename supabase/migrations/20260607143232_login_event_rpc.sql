CREATE OR REPLACE FUNCTION record_login_event(
  p_device_name TEXT,
  p_platform TEXT,
  p_location TEXT
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  INSERT INTO user_login_events (user_id, device_name, platform, location, logged_in_at)
  VALUES (auth.uid(), p_device_name, p_platform, p_location, NOW());
END;
$$;

GRANT EXECUTE ON FUNCTION record_login_event TO authenticated;

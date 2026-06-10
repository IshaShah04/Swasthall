CREATE OR REPLACE FUNCTION get_my_staff_emails()
RETURNS TABLE (id UUID, email TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'hospital'
  ) THEN
    RAISE EXCEPTION 'Access denied. Must be a hospital.';
  END IF;
  
  RETURN QUERY
  SELECT s.id, s.email FROM staff s WHERE s.hospital_id = auth.uid();
END;
$$;

GRANT EXECUTE ON FUNCTION get_my_staff_emails TO authenticated;

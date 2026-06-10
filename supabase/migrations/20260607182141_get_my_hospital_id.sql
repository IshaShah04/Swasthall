CREATE OR REPLACE FUNCTION get_my_hospital_id()
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_hospital_id UUID;
  v_role TEXT;
BEGIN
  SELECT role INTO v_role FROM profiles WHERE id = auth.uid();
  
  IF v_role IN ('doctor') THEN
    SELECT hospital_id INTO v_hospital_id 
    FROM staff_pairings 
    WHERE doctor_id = auth.uid()
    LIMIT 1;
  ELSIF v_role IN ('nurse', 'pharmacist', 'technician') THEN
    SELECT hospital_id INTO v_hospital_id 
    FROM staff_pairings 
    WHERE nurse_id = auth.uid()
    LIMIT 1;
  END IF;
  
  RETURN v_hospital_id;
END;
$$;

GRANT EXECUTE ON FUNCTION get_my_hospital_id TO authenticated;

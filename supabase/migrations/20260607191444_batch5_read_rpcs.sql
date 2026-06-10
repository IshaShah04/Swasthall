-- RPC 1: get_my_profile
-- Used by: registration_completion_screen, patient_settings, hospital_profile
CREATE OR REPLACE FUNCTION get_my_profile()
RETURNS SETOF profiles
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT * FROM profiles WHERE id = auth.uid();
END;
$$;

-- RPC 2: get_my_consents
-- Used by: registration_completion_screen
CREATE OR REPLACE FUNCTION get_my_consents()
RETURNS SETOF user_consents
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT * FROM user_consents WHERE user_id = auth.uid();
END;
$$;

-- RPC 3: get_my_provider_documents
-- Used by: registration_completion_screen
CREATE OR REPLACE FUNCTION get_my_provider_documents()
RETURNS SETOF provider_documents
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT * FROM provider_documents WHERE provider_id = auth.uid();
END;
$$;

-- RPC 4: get_my_family
-- Used by: patient_settings, patient_home
-- Returns linked children profiles in one call
CREATE OR REPLACE FUNCTION get_my_family()
RETURNS TABLE (
  child_id UUID,
  full_name TEXT,
  avatar_url TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT p.id, p.full_name, p.avatar_url
  FROM family_links fl
  JOIN profiles p ON p.id = fl.child_id
  WHERE fl.parent_id = auth.uid();
END;
$$;

-- RPC 5: get_medical_records
-- Used by: patient_records_screen
CREATE OR REPLACE FUNCTION get_medical_records(
  p_patient_id UUID DEFAULT NULL
)
RETURNS SETOF medical_records
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role TEXT;
  v_target_id UUID;
BEGIN
  SELECT role INTO v_role FROM profiles WHERE id = auth.uid();

  -- Patient can only see own records or linked family
  IF v_role = 'patient' THEN
    v_target_id := COALESCE(p_patient_id, auth.uid());
    -- Verify access: must be self or linked child
    IF v_target_id != auth.uid() THEN
      IF NOT EXISTS (
        SELECT 1 FROM family_links 
        WHERE parent_id = auth.uid() AND child_id = v_target_id
      ) THEN
        RAISE EXCEPTION 'Access denied to patient records';
      END IF;
    END IF;
  ELSIF v_role IN ('doctor', 'nurse', 'pharmacist', 'technician') THEN
    -- Provider sees records for specified patient
    v_target_id := COALESCE(p_patient_id, auth.uid());
  ELSE
    RAISE EXCEPTION 'Access denied';
  END IF;

  RETURN QUERY
  SELECT * FROM medical_records 
  WHERE patient_id = v_target_id
  ORDER BY created_at DESC;
END;
$$;

-- RPC 6: get_hospital_dashboard
-- Used by: hospital_profile (replaces 3 separate queries)
CREATE OR REPLACE FUNCTION get_hospital_dashboard()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role TEXT;
  v_profile JSON;
  v_staff JSON;
BEGIN
  SELECT role INTO v_role FROM profiles WHERE id = auth.uid();
  IF v_role != 'hospital' THEN
    RAISE EXCEPTION 'Access denied. Must be a hospital.';
  END IF;

  SELECT row_to_json(p) INTO v_profile
  FROM profiles p WHERE id = auth.uid();

  SELECT json_agg(s) INTO v_staff
  FROM staff s WHERE hospital_id = auth.uid();

  RETURN json_build_object(
    'profile', v_profile,
    'staff', COALESCE(v_staff, '[]'::json)
  );
END;
$$;

-- Skip: staff_queues (stream — cannot migrate)
-- Skip: main.dart preloader (public data, low risk)
-- Skip: insurance_screen (public data, low risk)
-- Skip: ai_assistant_screen lab_tests (public data, low risk)

GRANT EXECUTE ON FUNCTION get_my_profile TO authenticated;
GRANT EXECUTE ON FUNCTION get_my_consents TO authenticated;
GRANT EXECUTE ON FUNCTION get_my_provider_documents TO authenticated;
GRANT EXECUTE ON FUNCTION get_my_family TO authenticated;
GRANT EXECUTE ON FUNCTION get_medical_records TO authenticated;
GRANT EXECUTE ON FUNCTION get_hospital_dashboard TO authenticated;

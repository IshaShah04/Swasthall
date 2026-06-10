-- PART A: Schema changes

ALTER TABLE profiles 
ADD COLUMN IF NOT EXISTS verification_status TEXT 
  NOT NULL DEFAULT 'verified'
  CHECK (verification_status IN ('pending_verification', 'verified', 'rejected'));

UPDATE profiles 
SET verification_status = 'pending_verification'
WHERE role IN ('doctor', 'nurse', 'pharmacist', 'technician')
AND is_verified = false;

UPDATE profiles
SET verification_status = 'verified'
WHERE role IN ('doctor', 'nurse', 'pharmacist', 'technician', 'hospital')
AND is_verified = true;

ALTER TABLE availability_slots
ADD COLUMN IF NOT EXISTS hospital_id UUID REFERENCES hospitals(id) ON DELETE SET NULL;

ALTER TABLE staff_pairings
ADD COLUMN IF NOT EXISTS role TEXT;

-- PART B: Update upsert_user_profile

CREATE OR REPLACE FUNCTION upsert_user_profile(
  p_email TEXT,
  p_full_name TEXT,
  p_role TEXT,
  p_phone_number TEXT DEFAULT NULL,
  p_license_number TEXT DEFAULT NULL,
  p_avatar_url TEXT DEFAULT NULL,
  p_is_verified BOOLEAN DEFAULT FALSE,
  p_allow_research BOOLEAN DEFAULT FALSE,
  p_allow_newsletters BOOLEAN DEFAULT FALSE,
  p_blood_group TEXT DEFAULT NULL,
  p_height_cm DOUBLE PRECISION DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_verification_status TEXT;
BEGIN
  IF p_role IN ('hospital', 'admin') THEN
    RAISE EXCEPTION 'Role % cannot self-register. Contact administrator.', p_role;
  END IF;
  IF p_role NOT IN ('patient', 'doctor', 'nurse', 'pharmacist', 'technician') THEN
    RAISE EXCEPTION 'Invalid role: %', p_role;
  END IF;
  IF p_role = 'patient' THEN
    v_verification_status := 'verified';
  ELSE
    v_verification_status := 'pending_verification';
  END IF;
  INSERT INTO profiles (
    id, email, full_name, role, phone_number, license_number, avatar_url,
    is_verified, allow_research, allow_newsletters, blood_group, height_cm,
    verification_status, updated_at
  )
  VALUES (
    auth.uid(), p_email, p_full_name, p_role, p_phone_number, p_license_number,
    p_avatar_url, false, p_allow_research, p_allow_newsletters, p_blood_group,
    p_height_cm, v_verification_status, NOW()
  )
  ON CONFLICT (id) DO UPDATE SET
    email = EXCLUDED.email,
    full_name = EXCLUDED.full_name,
    role = EXCLUDED.role,
    phone_number = EXCLUDED.phone_number,
    license_number = EXCLUDED.license_number,
    avatar_url = EXCLUDED.avatar_url,
    allow_research = EXCLUDED.allow_research,
    allow_newsletters = EXCLUDED.allow_newsletters,
    blood_group = EXCLUDED.blood_group,
    height_cm = EXCLUDED.height_cm,
    verification_status = EXCLUDED.verification_status,
    updated_at = NOW();
END;
$$;

-- PART C: Update manage_availability_slot

CREATE OR REPLACE FUNCTION manage_availability_slot(
  p_action TEXT,
  p_slot_id UUID DEFAULT NULL,
  p_provider_id UUID DEFAULT NULL,
  p_hospital_id UUID DEFAULT NULL,
  p_date DATE DEFAULT NULL,
  p_start_time TIMESTAMPTZ DEFAULT NULL,
  p_end_time TIMESTAMPTZ DEFAULT NULL,
  p_slot_type TEXT DEFAULT NULL,
  p_hourly_cap INT DEFAULT NULL,
  p_current_bookings INT DEFAULT 0
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role TEXT;
  v_verification_status TEXT;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  SELECT role, verification_status 
  INTO v_role, v_verification_status 
  FROM profiles WHERE id = auth.uid();
  IF v_role NOT IN ('doctor', 'nurse', 'pharmacist', 'technician') THEN
    RAISE EXCEPTION 'Access denied. Invalid role for managing slots.';
  END IF;
  IF p_action = 'insert' AND v_verification_status != 'verified' THEN
    RAISE EXCEPTION 'Account pending verification. Cannot create availability slots yet.';
  END IF;
  IF p_action = 'insert' THEN
    IF p_provider_id != auth.uid() AND v_role != 'nurse' THEN
      RAISE EXCEPTION 'Access denied. provider_id mismatch.';
    END IF;
    INSERT INTO availability_slots (
      provider_id, hospital_id, date, start_time, end_time,
      slot_type, hourly_cap, current_bookings
    ) VALUES (
      p_provider_id, p_hospital_id, p_date, p_start_time, p_end_time,
      p_slot_type, p_hourly_cap, p_current_bookings
    );
  ELSIF p_action = 'delete_by_id' THEN
    DELETE FROM availability_slots 
    WHERE id = p_slot_id 
    AND (provider_id = auth.uid() OR v_role = 'nurse');
  ELSIF p_action = 'delete_by_provider' THEN
    IF p_provider_id != auth.uid() AND v_role != 'nurse' THEN
      RAISE EXCEPTION 'Access denied. Cannot delete another provider slots.';
    END IF;
    DELETE FROM availability_slots WHERE provider_id = p_provider_id;
  ELSE
    RAISE EXCEPTION 'Invalid action: %', p_action;
  END IF;
END;
$$;

-- PART D: link_staff_to_hospital

CREATE OR REPLACE FUNCTION link_staff_to_hospital(
  p_provider_email TEXT,
  p_role TEXT
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_provider_id UUID;
  v_hospital_role TEXT;
  v_hospital_verified TEXT;
BEGIN
  SELECT role, verification_status 
  INTO v_hospital_role, v_hospital_verified
  FROM profiles WHERE id = auth.uid();
  IF v_hospital_role != 'hospital' THEN
    RAISE EXCEPTION 'Only hospitals can link staff.';
  END IF;
  IF v_hospital_verified != 'verified' THEN
    RAISE EXCEPTION 'Hospital account not verified. Contact administrator.';
  END IF;
  SELECT id INTO v_provider_id 
  FROM profiles 
  WHERE email = p_provider_email 
  AND role = p_role;
  IF v_provider_id IS NULL THEN
    RAISE EXCEPTION 'No % found with email: %', p_role, p_provider_email;
  END IF;
  INSERT INTO staff_pairings (hospital_id, doctor_id, nurse_id, role)
  VALUES (
    auth.uid(),
    CASE WHEN p_role = 'doctor' THEN v_provider_id ELSE NULL END,
    CASE WHEN p_role IN ('nurse', 'pharmacist', 'technician') THEN v_provider_id ELSE NULL END,
    p_role
  )
  ON CONFLICT DO NOTHING;
  UPDATE profiles 
  SET verification_status = 'verified', is_verified = true
  WHERE id = v_provider_id;
END;
$$;

-- PART E: get_public_staff_directory

DROP FUNCTION IF EXISTS get_public_staff_directory(text, uuid, uuid[], text, integer);

CREATE OR REPLACE FUNCTION get_public_staff_directory(
  p_role TEXT DEFAULT NULL,
  p_hospital_id UUID DEFAULT NULL,
  p_provider_ids UUID[] DEFAULT NULL,
  p_search TEXT DEFAULT NULL,
  p_limit INT DEFAULT 60
)
RETURNS TABLE (
  id UUID,
  full_name TEXT,
  role TEXT,
  speciality TEXT,
  avatar_url TEXT,
  hospital_id UUID,
  hospital_name TEXT,
  first_consultation_fee NUMERIC,
  followup_consultation_fee NUMERIC,
  rating NUMERIC,
  degree TEXT,
  address TEXT,
  bio TEXT,
  description TEXT,
  available_dates DATE[]
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT DISTINCT ON (p.id, h.id)
    p.id,
    p.full_name,
    p.role,
    COALESCE(p.speciality, s.speciality) AS speciality,
    p.avatar_url,
    h.id AS hospital_id,
    h.name AS hospital_name,
    s.first_consultation_fee,
    s.followup_consultation_fee,
    COALESCE(
      (SELECT AVG(r.rating)::NUMERIC 
       FROM call_reviews r 
       WHERE r.doctor_id = p.id),
      4.5
    ) AS rating,
    s.degree,
    s.address,
    p.bio,
    p.description,
    ARRAY(
      SELECT DISTINCT a2.date 
      FROM availability_slots a2 
      WHERE a2.provider_id = p.id 
      AND a2.hospital_id = h.id
      AND a2.date >= CURRENT_DATE
      ORDER BY a2.date
      LIMIT 7
    ) AS available_dates
  FROM profiles p
  JOIN availability_slots a ON a.provider_id = p.id
  JOIN hospitals h ON h.id = a.hospital_id
  LEFT JOIN staff s ON s.profile_id = p.id
  WHERE p.verification_status = 'verified'
  AND p.is_verified = true
  AND p.role NOT IN ('patient', 'hospital', 'admin')
  AND (p_role IS NULL OR p.role = p_role)
  AND (p_hospital_id IS NULL OR h.id = p_hospital_id)
  AND (p_provider_ids IS NULL OR p.id = ANY(p_provider_ids))
  AND (p_search IS NULL OR 
       p.full_name ILIKE '%' || p_search || '%' OR
       p.speciality ILIKE '%' || p_search || '%' OR
       s.degree ILIKE '%' || p_search || '%')
  ORDER BY p.id, h.id, rating DESC
  LIMIT p_limit;
END;
$$;

-- PART F: Grants

GRANT EXECUTE ON FUNCTION upsert_user_profile TO authenticated;
GRANT EXECUTE ON FUNCTION manage_availability_slot TO authenticated;
GRANT EXECUTE ON FUNCTION link_staff_to_hospital TO authenticated;
GRANT EXECUTE ON FUNCTION get_public_staff_directory TO authenticated;
GRANT EXECUTE ON FUNCTION get_public_staff_directory TO anon;

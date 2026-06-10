-- RPC 1: upsert_user_profile
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
BEGIN
  IF p_role NOT IN ('patient', 'doctor', 'nurse', 'pharmacist', 'technician') THEN
    RAISE EXCEPTION 'Invalid role: %', p_role;
  END IF;

  INSERT INTO profiles (
    id, email, full_name, role, phone_number, license_number, avatar_url, 
    is_verified, allow_research, allow_newsletters, blood_group, height_cm, updated_at
  )
  VALUES (
    auth.uid(), p_email, p_full_name, p_role, p_phone_number, p_license_number, p_avatar_url, 
    p_is_verified, p_allow_research, p_allow_newsletters, p_blood_group, p_height_cm, NOW()
  )
  ON CONFLICT (id) DO UPDATE SET
    email = EXCLUDED.email,
    full_name = EXCLUDED.full_name,
    role = EXCLUDED.role,
    phone_number = EXCLUDED.phone_number,
    license_number = EXCLUDED.license_number,
    avatar_url = EXCLUDED.avatar_url,
    is_verified = EXCLUDED.is_verified,
    allow_research = EXCLUDED.allow_research,
    allow_newsletters = EXCLUDED.allow_newsletters,
    blood_group = EXCLUDED.blood_group,
    height_cm = EXCLUDED.height_cm,
    updated_at = NOW();
END;
$$;

-- RPC 2: upsert_provider_document
CREATE OR REPLACE FUNCTION upsert_provider_document(
  p_document_type TEXT,
  p_document_url TEXT,
  p_verification_status TEXT DEFAULT 'pending'
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO provider_documents (
    provider_id, document_type, document_url, verification_status, uploaded_at
  )
  VALUES (
    auth.uid(), p_document_type, p_document_url, p_verification_status, NOW()
  )
  ON CONFLICT (provider_id, document_type) DO UPDATE SET 
    document_url = EXCLUDED.document_url,
    verification_status = EXCLUDED.verification_status,
    uploaded_at = NOW();
END;
$$;

-- RPC 3: upsert_user_consent
CREATE OR REPLACE FUNCTION upsert_user_consent(
  p_terms_version TEXT,
  p_terms_accepted_at TIMESTAMPTZ,
  p_privacy_version TEXT,
  p_privacy_accepted_at TIMESTAMPTZ,
  p_telemedicine_version TEXT,
  p_telemedicine_accepted_at TIMESTAMPTZ
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO user_consents (
    user_id, terms_version, terms_accepted_at, privacy_version, privacy_accepted_at, telemedicine_version, telemedicine_accepted_at
  )
  VALUES (
    auth.uid(), p_terms_version, p_terms_accepted_at, p_privacy_version, p_privacy_accepted_at, p_telemedicine_version, p_telemedicine_accepted_at
  )
  ON CONFLICT (user_id) DO UPDATE SET
    terms_version = EXCLUDED.terms_version,
    terms_accepted_at = EXCLUDED.terms_accepted_at,
    privacy_version = EXCLUDED.privacy_version,
    privacy_accepted_at = EXCLUDED.privacy_accepted_at,
    telemedicine_version = EXCLUDED.telemedicine_version,
    telemedicine_accepted_at = EXCLUDED.telemedicine_accepted_at;
END;
$$;

-- RPC 4: update_patient_profile
CREATE OR REPLACE FUNCTION update_patient_profile(
  p_full_name TEXT DEFAULT NULL,
  p_phone_number TEXT DEFAULT NULL,
  p_avatar_url TEXT DEFAULT NULL,
  p_blood_group TEXT DEFAULT NULL,
  p_height_cm DOUBLE PRECISION DEFAULT NULL,
  p_allow_research BOOLEAN DEFAULT NULL,
  p_allow_newsletters BOOLEAN DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE profiles SET
    full_name = COALESCE(p_full_name, full_name),
    phone_number = COALESCE(p_phone_number, phone_number),
    avatar_url = COALESCE(p_avatar_url, avatar_url),
    blood_group = COALESCE(p_blood_group, blood_group),
    height_cm = COALESCE(p_height_cm, height_cm),
    allow_research = COALESCE(p_allow_research, allow_research),
    allow_newsletters = COALESCE(p_allow_newsletters, allow_newsletters),
    updated_at = NOW()
  WHERE id = auth.uid();
END;
$$;

-- RPC 5: request_account_deletion
CREATE OR REPLACE FUNCTION request_account_deletion(
  p_notes TEXT,
  p_status TEXT DEFAULT 'pending'
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO deletion_requests (user_id, status, notes, requested_at)
  VALUES (auth.uid(), 'pending', p_notes, NOW());
END;
$$;

-- RPC 6: link_family_member
CREATE OR REPLACE FUNCTION link_family_member(
  p_child_email TEXT
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_child_id UUID;
BEGIN
  SELECT id INTO v_child_id FROM profiles WHERE email = p_child_email;
  IF v_child_id IS NULL THEN
    RAISE EXCEPTION 'No user found with email: %', p_child_email;
  END IF;
  IF v_child_id = auth.uid() THEN
    RAISE EXCEPTION 'Cannot link yourself as a family member';
  END IF;
  INSERT INTO family_links (parent_id, child_id)
  VALUES (auth.uid(), v_child_id)
  ON CONFLICT DO NOTHING;
END;
$$;

-- Grant execute to authenticated users only
GRANT EXECUTE ON FUNCTION upsert_user_profile TO authenticated;
GRANT EXECUTE ON FUNCTION upsert_provider_document TO authenticated;
GRANT EXECUTE ON FUNCTION upsert_user_consent TO authenticated;
GRANT EXECUTE ON FUNCTION update_patient_profile TO authenticated;
GRANT EXECUTE ON FUNCTION request_account_deletion TO authenticated;
GRANT EXECUTE ON FUNCTION link_family_member TO authenticated;

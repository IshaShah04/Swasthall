-- Migration: Hospital Admin RPCs Patch

-- FIX 2: update_blood_inventory
CREATE OR REPLACE FUNCTION update_blood_inventory(
  p_id UUID,
  p_hospital_name TEXT,
  p_blood_group TEXT,
  p_quantity_ml INT,
  p_status TEXT
)
RETURNS void
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

  UPDATE blood_inventory 
  SET 
    hospital_name = p_hospital_name,
    blood_group = p_blood_group,
    quantity_ml = p_quantity_ml,
    status = p_status
  WHERE id = p_id AND hospital_id = auth.uid();
END;
$$;


-- FIX 3: upsert_staff_member
CREATE OR REPLACE FUNCTION upsert_staff_member(
  p_id UUID,
  p_hospital_id UUID,
  p_email TEXT,
  p_role TEXT,
  p_name TEXT,
  p_speciality TEXT,
  p_assigned_lab TEXT,
  p_payout NUMERIC,
  p_first_consultation_fee NUMERIC,
  p_followup_consultation_fee NUMERIC
)
RETURNS void
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

  INSERT INTO staff (
    id, hospital_id, email, role, name, speciality, assigned_lab, payout, first_consultation_fee, followup_consultation_fee
  )
  VALUES (
    p_id, p_hospital_id, p_email, p_role, p_name, p_speciality, p_assigned_lab, p_payout, p_first_consultation_fee, p_followup_consultation_fee
  )
  ON CONFLICT (hospital_id, email) DO UPDATE SET 
    id = EXCLUDED.id,
    role = EXCLUDED.role,
    name = EXCLUDED.name,
    speciality = EXCLUDED.speciality,
    assigned_lab = EXCLUDED.assigned_lab,
    payout = EXCLUDED.payout,
    first_consultation_fee = EXCLUDED.first_consultation_fee,
    followup_consultation_fee = EXCLUDED.followup_consultation_fee;
END;
$$;


-- FIX 5: update_staff_field
CREATE OR REPLACE FUNCTION update_staff_field(
  p_staff_id UUID,
  p_column TEXT,
  p_value TEXT
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Only allow specific safe columns to be updated
  IF p_column NOT IN ('name', 'speciality') THEN
    RAISE EXCEPTION 'Column update not allowed: %', p_column;
  END IF;
  
  -- Nurse (or staff) can only update their own staff record
  IF p_staff_id != auth.uid() THEN
    RAISE EXCEPTION 'Access denied.';
  END IF;
  
  -- Use dynamic SQL safely via CASE
  UPDATE staff SET
    name = CASE WHEN p_column = 'name' THEN p_value ELSE name END,
    speciality = CASE WHEN p_column = 'speciality' THEN p_value ELSE speciality END
  WHERE id = p_staff_id;
END;
$$;

GRANT EXECUTE ON FUNCTION update_blood_inventory TO authenticated;
GRANT EXECUTE ON FUNCTION upsert_staff_member TO authenticated;
GRANT EXECUTE ON FUNCTION update_staff_field TO authenticated;

-- Migration: Migrate clinical write from() calls to SECURITY DEFINER RPCs

-- 1. insert_patient_vital
CREATE OR REPLACE FUNCTION insert_patient_vital(
  p_patient_id UUID,
  p_type TEXT,
  p_reading JSONB
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

  INSERT INTO patient_vitals (patient_id, type, reading)
  VALUES (p_patient_id, p_type, p_reading);
END;
$$;

-- 2. delete_medical_record
CREATE OR REPLACE FUNCTION delete_medical_record(
  p_record_id UUID
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

  DELETE FROM medical_records
  WHERE id = p_record_id
    AND (patient_id = auth.uid() OR provider_id = auth.uid());
END;
$$;

-- 3. upsert_analytics_event
CREATE OR REPLACE FUNCTION upsert_analytics_event(
  p_doctor_id UUID,
  p_date_period TEXT, -- using TEXT assuming it corresponds to ISO string or date
  p_completed_count INT,
  p_cancelled_count INT,
  p_avg_rating NUMERIC,
  p_avg_duration NUMERIC
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

  IF p_doctor_id != auth.uid() THEN
    RAISE EXCEPTION 'Cannot update analytics for another provider';
  END IF;

  INSERT INTO professional_analytics_data (
    doctor_id, date_period, completed_count, cancelled_count, avg_rating, avg_duration
  ) VALUES (
    p_doctor_id, p_date_period::date, p_completed_count, p_cancelled_count, p_avg_rating, p_avg_duration
  )
  ON CONFLICT (doctor_id, date_period) DO UPDATE SET
    completed_count = EXCLUDED.completed_count,
    cancelled_count = EXCLUDED.cancelled_count,
    avg_rating = EXCLUDED.avg_rating,
    avg_duration = EXCLUDED.avg_duration;
END;
$$;

-- 4. manage_call_session
CREATE OR REPLACE FUNCTION manage_call_session(
  p_action TEXT,
  p_channel_name TEXT,
  p_status TEXT DEFAULT NULL,
  p_caller_id UUID DEFAULT NULL,
  p_caller_name TEXT DEFAULT NULL,
  p_callee_id UUID DEFAULT NULL,
  p_booking_id UUID DEFAULT NULL,
  p_call_type TEXT DEFAULT 'video'
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

  IF p_action = 'initiate' THEN
    INSERT INTO call_sessions (
      caller_id, caller_name, callee_id, receiver_id, booking_id, channel_name, call_type, status
    ) VALUES (
      p_caller_id, p_caller_name, p_callee_id, p_callee_id, p_booking_id, p_channel_name, p_call_type, 'ringing'
    );
  ELSIF p_action = 'update_status' THEN
    -- Verify caller is either caller_id OR callee_id in the session
    IF NOT EXISTS (
      SELECT 1 FROM call_sessions 
      WHERE channel_name = p_channel_name 
        AND (caller_id = auth.uid() OR callee_id = auth.uid())
    ) THEN
      RAISE EXCEPTION 'Not authorized to update this call session';
    END IF;

    UPDATE call_sessions
    SET status = p_status
    WHERE channel_name = p_channel_name;
  ELSE
    RAISE EXCEPTION 'Invalid action';
  END IF;
END;
$$;

-- 5. insert_consultation_request
CREATE OR REPLACE FUNCTION insert_consultation_request(
  p_patient_id UUID,
  p_hospital_id UUID,
  p_request_type TEXT,
  p_target_name TEXT,
  p_status TEXT DEFAULT 'pending'
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

  INSERT INTO consultation_requests (
    patient_id, hospital_id, request_type, target_name, status, created_at
  ) VALUES (
    p_patient_id, p_hospital_id, p_request_type, p_target_name, p_status, now()
  );
END;
$$;

-- 6. insert_prescription_scan
CREATE OR REPLACE FUNCTION insert_prescription_scan(
  p_medicines JSONB,
  p_interactions JSONB,
  p_notes TEXT
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

  INSERT INTO prescription_scans (
    patient_id, medicines, interactions, notes
  ) VALUES (
    auth.uid(), p_medicines, p_interactions, p_notes
  );
END;
$$;

-- 7. insert_call_review
CREATE OR REPLACE FUNCTION insert_call_review(
  p_booking_id UUID,
  p_doctor_id UUID,
  p_rating INT,
  p_review_text TEXT,
  p_duration_seconds INT
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

  INSERT INTO call_reviews (
    booking_id, doctor_id, patient_id, rating, review_text, duration_seconds
  ) VALUES (
    p_booking_id, p_doctor_id, auth.uid(), p_rating, p_review_text, p_duration_seconds
  );
END;
$$;

-- 8. insert_medical_record
CREATE OR REPLACE FUNCTION insert_medical_record(
  p_patient_id UUID,
  p_file_url TEXT,
  p_file_name TEXT,
  p_provider_role TEXT,
  p_appointment_id UUID DEFAULT NULL
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

  INSERT INTO medical_records (
    patient_id, provider_id, appointment_id, file_url, file_name, provider_role, created_at
  ) VALUES (
    p_patient_id, auth.uid(), p_appointment_id, p_file_url, p_file_name, p_provider_role, now()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION insert_patient_vital TO authenticated;
GRANT EXECUTE ON FUNCTION delete_medical_record TO authenticated;
GRANT EXECUTE ON FUNCTION upsert_analytics_event TO authenticated;
GRANT EXECUTE ON FUNCTION manage_call_session TO authenticated;
GRANT EXECUTE ON FUNCTION insert_consultation_request TO authenticated;
GRANT EXECUTE ON FUNCTION insert_prescription_scan TO authenticated;
GRANT EXECUTE ON FUNCTION insert_call_review TO authenticated;
GRANT EXECUTE ON FUNCTION insert_medical_record TO authenticated;

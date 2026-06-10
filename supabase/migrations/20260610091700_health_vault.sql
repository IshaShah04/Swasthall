CREATE TABLE IF NOT EXISTS vitals_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  systolic integer,
  diastolic integer,
  blood_sugar_mg_dl numeric,
  logged_at timestamptz DEFAULT now()
);
ALTER TABLE vitals_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users manage own vitals" ON vitals_log
  FOR ALL USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

CREATE TABLE IF NOT EXISTS health_documents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  file_url text NOT NULL,
  file_name text NOT NULL,
  category text NOT NULL CHECK (category IN ('diagnosis', 'prescription', 'lab_report', 'other')),
  uploaded_at timestamptz DEFAULT now()
);
ALTER TABLE health_documents ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users manage own documents" ON health_documents
  FOR ALL USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

ALTER TABLE hospitals
  ADD COLUMN IF NOT EXISTS contact_number text,
  ADD COLUMN IF NOT EXISTS description text,
  ADD COLUMN IF NOT EXISTS facilities jsonb DEFAULT '[]',
  ADD COLUMN IF NOT EXISTS is_open_24hrs boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS is_nabh_accredited boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS total_beds integer,
  ADD COLUMN IF NOT EXISTS review_count integer DEFAULT 0,
  ADD COLUMN IF NOT EXISTS latitude double precision,
  ADD COLUMN IF NOT EXISTS longitude double precision;

CREATE TABLE IF NOT EXISTS hospital_reviews (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  hospital_id uuid NOT NULL REFERENCES hospitals(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  rating integer NOT NULL CHECK (rating BETWEEN 1 AND 5),
  comment text,
  created_at timestamptz DEFAULT now()
);
ALTER TABLE hospital_reviews ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone can read reviews" ON hospital_reviews FOR SELECT USING (true);
CREATE POLICY "Auth users insert own review" ON hospital_reviews FOR INSERT WITH CHECK (user_id = auth.uid());

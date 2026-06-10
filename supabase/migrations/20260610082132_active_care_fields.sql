ALTER TABLE bookings ADD COLUMN IF NOT EXISTS notes text;
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS appointment_type text DEFAULT 'in_clinic';

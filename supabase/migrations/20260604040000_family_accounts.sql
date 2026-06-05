-- Create family_links table
CREATE TABLE public.family_links (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    parent_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    child_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(parent_id, child_id)
);

-- Enable RLS
ALTER TABLE public.family_links ENABLE ROW LEVEL SECURITY;

-- Policies for family_links
CREATE POLICY "Parents can view their family links" 
ON public.family_links FOR SELECT 
USING (auth.uid() = parent_id OR auth.uid() = child_id);

CREATE POLICY "Parents can insert family links" 
ON public.family_links FOR INSERT 
WITH CHECK (auth.uid() = parent_id);

CREATE POLICY "Parents can delete family links" 
ON public.family_links FOR DELETE 
USING (auth.uid() = parent_id);

-- Update RLS policies for medical_records to allow parents to view child records
CREATE POLICY "Parents can view child medical records"
ON public.medical_records FOR SELECT
USING (
    patient_id IN (
        SELECT child_id FROM public.family_links WHERE parent_id = auth.uid()
    )
);

-- Update RLS policies for patient_vitals
CREATE POLICY "Parents can view child vitals"
ON public.patient_vitals FOR SELECT
USING (
    patient_id IN (
        SELECT child_id FROM public.family_links WHERE parent_id = auth.uid()
    )
);

-- Update RLS policies for bookings
CREATE POLICY "Parents can view child bookings"
ON public.bookings FOR SELECT
USING (
    patient_id IN (
        SELECT child_id FROM public.family_links WHERE parent_id = auth.uid()
    )
);

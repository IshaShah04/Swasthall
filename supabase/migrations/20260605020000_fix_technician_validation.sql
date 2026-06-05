create or replace function public.sync_lab_test_assignments_atomic(
  p_hospital_id uuid,
  p_assignments jsonb default '[]'::jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_auth_uid uuid := auth.uid();
begin
  if v_auth_uid is null then
    raise exception 'Authentication required';
  end if;

  if v_auth_uid <> p_hospital_id then
    raise exception 'Unauthorized hospital assignment sync request';
  end if;

  if jsonb_typeof(coalesce(p_assignments, '[]'::jsonb)) <> 'array' then
    raise exception 'p_assignments must be a JSON array';
  end if;

  -- Validate all technician_ids belong to the calling hospital
  FOR i IN 0..jsonb_array_length(p_assignments) - 1 LOOP
    DECLARE
      v_tech_id uuid := (p_assignments->i->>'technician_id')::uuid;
      v_tech_hospital_id uuid;
    BEGIN
      SELECT hospital_id INTO v_tech_hospital_id
      FROM technicians
      WHERE id = v_tech_id;

      IF v_tech_hospital_id IS DISTINCT FROM p_hospital_id THEN
        RAISE EXCEPTION 'Technician % does not belong to hospital %', v_tech_id, p_hospital_id;
      END IF;
    END;
  END LOOP;

  delete from public.lab_test_assignments
  where hospital_id = p_hospital_id;

  insert into public.lab_test_assignments (
    hospital_id,
    lab_test_id,
    technician_id,
    is_active
  )
  select
    p_hospital_id,
    (item->>'lab_test_id')::uuid,
    (item->>'technician_id')::uuid,
    coalesce((item->>'is_active')::boolean, true)
  from jsonb_array_elements(coalesce(p_assignments, '[]'::jsonb)) as item
  where nullif(item->>'lab_test_id', '') is not null
    and nullif(item->>'technician_id', '') is not null;
end;
$$;

revoke all on function public.sync_lab_test_assignments_atomic(uuid, jsonb) from public;
grant execute on function public.sync_lab_test_assignments_atomic(uuid, jsonb) to authenticated;

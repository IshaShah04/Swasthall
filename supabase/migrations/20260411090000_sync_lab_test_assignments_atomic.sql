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

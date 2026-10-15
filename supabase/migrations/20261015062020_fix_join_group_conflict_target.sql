begin;

create or replace function public.join_group(p_invite_code text)
returns table (group_id bigint, group_name text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_group public.groups%rowtype;
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;

  select g.* into v_group
  from public.groups as g
  where g.invite_code = upper(btrim(p_invite_code));

  if not found then
    raise exception 'Invalid group invite code' using errcode = 'P0002';
  end if;

  insert into public.group_members (group_id, user_id, role)
  values (v_group.id, v_user_id, 'member')
  on conflict on constraint group_members_pkey do nothing;

  return query select v_group.id, v_group.name;
end;
$$;

revoke all on function public.join_group(text) from public, anon, authenticated;
grant execute on function public.join_group(text) to authenticated;

commit;

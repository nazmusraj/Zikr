begin;

create schema if not exists private;
revoke all on schema private from public;

create table public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default 'Zikr User',
  avatar_url text,
  timezone text not null default 'UTC',
  show_on_global_leaderboard boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_display_name_check
    check (char_length(btrim(display_name)) between 1 and 50),
  constraint profiles_avatar_url_check
    check (avatar_url is null or char_length(avatar_url) <= 2048),
  constraint profiles_timezone_length_check
    check (char_length(timezone) between 1 and 64)
);

create table public.user_stats (
  user_id uuid primary key references public.profiles(user_id) on delete cascade,
  total_count bigint not null default 0,
  ranked_count bigint not null default 0,
  last_active_date date,
  updated_at timestamptz not null default now(),
  constraint user_stats_counts_check
    check (total_count >= 0 and ranked_count >= 0 and ranked_count <= total_count)
);

create table public.daily_progress (
  user_id uuid not null references public.profiles(user_id) on delete cascade,
  progress_date date not null,
  zikr_id text not null,
  total_count bigint not null default 0,
  ranked_count bigint not null default 0,
  updated_at timestamptz not null default now(),
  primary key (user_id, progress_date, zikr_id),
  constraint daily_progress_zikr_id_check
    check (char_length(zikr_id) between 1 and 80 and zikr_id ~ '^[a-z0-9_:-]+$'),
  constraint daily_progress_counts_check
    check (total_count >= 0 and ranked_count >= 0 and ranked_count <= total_count)
);

create table public.zikr_progress (
  user_id uuid not null references public.profiles(user_id) on delete cascade,
  zikr_id text not null,
  total_count bigint not null default 0,
  ranked_count bigint not null default 0,
  updated_at timestamptz not null default now(),
  primary key (user_id, zikr_id),
  constraint zikr_progress_zikr_id_check
    check (char_length(zikr_id) between 1 and 80 and zikr_id ~ '^[a-z0-9_:-]+$'),
  constraint zikr_progress_counts_check
    check (total_count >= 0 and ranked_count >= 0 and ranked_count <= total_count)
);

create table public.progress_sync_devices (
  user_id uuid not null references public.profiles(user_id) on delete cascade,
  device_id uuid not null,
  last_sequence bigint not null default 0,
  last_synced_at timestamptz not null default now(),
  primary key (user_id, device_id),
  constraint progress_sync_devices_sequence_check check (last_sequence >= 0)
);

create table public.groups (
  id bigint generated always as identity primary key,
  owner_id uuid not null references public.profiles(user_id) on delete cascade,
  name text not null,
  invite_code text not null default upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10)),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint groups_name_check check (char_length(btrim(name)) between 1 and 60),
  constraint groups_invite_code_check check (invite_code ~ '^[A-F0-9]{10}$'),
  constraint groups_invite_code_key unique (invite_code)
);

create table public.group_members (
  group_id bigint not null references public.groups(id) on delete cascade,
  user_id uuid not null references public.profiles(user_id) on delete cascade,
  role text not null default 'member',
  joined_at timestamptz not null default now(),
  primary key (group_id, user_id),
  constraint group_members_role_check check (role in ('owner', 'member'))
);

create index user_stats_ranked_count_idx
  on public.user_stats (ranked_count desc, user_id);
create index daily_progress_date_user_idx
  on public.daily_progress (progress_date, user_id)
  include (ranked_count, total_count);
create index groups_owner_id_idx on public.groups (owner_id);
create index group_members_user_id_idx on public.group_members (user_id, group_id);

create or replace function private.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create or replace function private.validate_profile_timezone()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if not exists (
    select 1
    from pg_catalog.pg_timezone_names
    where name = new.timezone
  ) then
    raise exception 'Invalid timezone: %', new.timezone using errcode = '22023';
  end if;
  return new;
end;
$$;

create trigger profiles_validate_timezone
before insert or update of timezone on public.profiles
for each row execute function private.validate_profile_timezone();

create trigger profiles_set_updated_at
before update on public.profiles
for each row execute function private.set_updated_at();

create trigger groups_set_updated_at
before update on public.groups
for each row execute function private.set_updated_at();

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_display_name text;
  v_avatar_url text;
begin
  v_display_name := left(
    coalesce(
      nullif(btrim(new.raw_user_meta_data ->> 'full_name'), ''),
      nullif(btrim(new.raw_user_meta_data ->> 'name'), ''),
      'Zikr User'
    ),
    50
  );
  v_avatar_url := nullif(left(coalesce(new.raw_user_meta_data ->> 'avatar_url', ''), 2048), '');

  insert into public.profiles (user_id, display_name, avatar_url)
  values (new.id, v_display_name, v_avatar_url)
  on conflict (user_id) do nothing;

  insert into public.user_stats (user_id)
  values (new.id)
  on conflict (user_id) do nothing;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

insert into public.profiles (user_id, display_name, avatar_url)
select
  u.id,
  left(
    coalesce(
      nullif(btrim(u.raw_user_meta_data ->> 'full_name'), ''),
      nullif(btrim(u.raw_user_meta_data ->> 'name'), ''),
      'Zikr User'
    ),
    50
  ),
  nullif(left(coalesce(u.raw_user_meta_data ->> 'avatar_url', ''), 2048), '')
from auth.users as u
on conflict (user_id) do nothing;

insert into public.user_stats (user_id)
select p.user_id from public.profiles as p
on conflict (user_id) do nothing;

create or replace function private.is_group_member(p_group_id bigint)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.group_members as gm
    where gm.group_id = p_group_id
      and gm.user_id = (select auth.uid())
  );
$$;

create or replace function private.is_group_owner(p_group_id bigint)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.groups as g
    where g.id = p_group_id
      and g.owner_id = (select auth.uid())
  );
$$;

alter table public.profiles enable row level security;
alter table public.profiles force row level security;
alter table public.user_stats enable row level security;
alter table public.user_stats force row level security;
alter table public.daily_progress enable row level security;
alter table public.daily_progress force row level security;
alter table public.zikr_progress enable row level security;
alter table public.zikr_progress force row level security;
alter table public.progress_sync_devices enable row level security;
alter table public.progress_sync_devices force row level security;
alter table public.groups enable row level security;
alter table public.groups force row level security;
alter table public.group_members enable row level security;
alter table public.group_members force row level security;

create policy profiles_select_own
on public.profiles for select to authenticated
using ((select auth.uid()) = user_id);

create policy profiles_update_own
on public.profiles for update to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

create policy user_stats_select_own
on public.user_stats for select to authenticated
using ((select auth.uid()) = user_id);

create policy daily_progress_select_own
on public.daily_progress for select to authenticated
using ((select auth.uid()) = user_id);

create policy zikr_progress_select_own
on public.zikr_progress for select to authenticated
using ((select auth.uid()) = user_id);

create policy progress_sync_devices_select_own
on public.progress_sync_devices for select to authenticated
using ((select auth.uid()) = user_id);

create policy groups_select_for_members
on public.groups for select to authenticated
using ((select private.is_group_member(id)));

create policy group_members_select_for_members
on public.group_members for select to authenticated
using ((select private.is_group_member(group_id)));

create or replace function public.sync_progress(
  p_device_id uuid,
  p_sequence bigint,
  p_zikr_id text,
  p_progress_date date,
  p_tap_delta bigint default 0,
  p_manual_delta bigint default 0
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_last_sequence bigint;
  v_total_delta bigint;
  v_stats public.user_stats%rowtype;
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  if p_device_id is null or p_sequence is null or p_sequence <= 0 then
    raise exception 'A device ID and positive sequence are required' using errcode = '22023';
  end if;
  if p_zikr_id is null
     or char_length(p_zikr_id) not between 1 and 80
     or p_zikr_id !~ '^[a-z0-9_:-]+$' then
    raise exception 'Invalid zikr ID' using errcode = '22023';
  end if;
  if p_progress_date is null
     or p_progress_date < current_date - 90
     or p_progress_date > current_date + 1 then
    raise exception 'Progress date is outside the accepted sync window' using errcode = '22023';
  end if;
  if p_tap_delta is null or p_tap_delta < 0 or p_tap_delta > 5000 then
    raise exception 'Tap delta must be between 0 and 5000' using errcode = '22023';
  end if;
  if p_manual_delta is null or p_manual_delta < 0 or p_manual_delta > 100000 then
    raise exception 'Manual delta must be between 0 and 100000' using errcode = '22023';
  end if;

  v_total_delta := p_tap_delta + p_manual_delta;
  if v_total_delta <= 0 then
    raise exception 'At least one positive delta is required' using errcode = '22023';
  end if;

  insert into public.user_stats (user_id)
  values (v_user_id)
  on conflict (user_id) do nothing;

  insert into public.progress_sync_devices (user_id, device_id)
  values (v_user_id, p_device_id)
  on conflict (user_id, device_id) do nothing;

  select d.last_sequence
  into v_last_sequence
  from public.progress_sync_devices as d
  where d.user_id = v_user_id and d.device_id = p_device_id
  for update;

  if p_sequence <= v_last_sequence then
    select * into v_stats
    from public.user_stats
    where user_id = v_user_id;

    return jsonb_build_object(
      'applied', false,
      'last_sequence', v_last_sequence,
      'total_count', v_stats.total_count,
      'ranked_count', v_stats.ranked_count
    );
  end if;

  update public.progress_sync_devices
  set last_sequence = p_sequence,
      last_synced_at = now()
  where user_id = v_user_id and device_id = p_device_id;

  insert into public.daily_progress (
    user_id, progress_date, zikr_id, total_count, ranked_count
  )
  values (
    v_user_id, p_progress_date, p_zikr_id, v_total_delta, p_tap_delta
  )
  on conflict (user_id, progress_date, zikr_id) do update
  set total_count = public.daily_progress.total_count + excluded.total_count,
      ranked_count = public.daily_progress.ranked_count + excluded.ranked_count,
      updated_at = now();

  insert into public.zikr_progress (
    user_id, zikr_id, total_count, ranked_count
  )
  values (
    v_user_id, p_zikr_id, v_total_delta, p_tap_delta
  )
  on conflict (user_id, zikr_id) do update
  set total_count = public.zikr_progress.total_count + excluded.total_count,
      ranked_count = public.zikr_progress.ranked_count + excluded.ranked_count,
      updated_at = now();

  insert into public.user_stats (
    user_id, total_count, ranked_count, last_active_date
  )
  values (
    v_user_id, v_total_delta, p_tap_delta, p_progress_date
  )
  on conflict (user_id) do update
  set total_count = public.user_stats.total_count + excluded.total_count,
      ranked_count = public.user_stats.ranked_count + excluded.ranked_count,
      last_active_date = greatest(public.user_stats.last_active_date, excluded.last_active_date),
      updated_at = now()
  returning * into v_stats;

  return jsonb_build_object(
    'applied', true,
    'last_sequence', p_sequence,
    'total_count', v_stats.total_count,
    'ranked_count', v_stats.ranked_count
  );
end;
$$;

create or replace function public.create_group(p_name text)
returns table (group_id bigint, group_name text, invite_code text)
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
  if p_name is null or char_length(btrim(p_name)) not between 1 and 60 then
    raise exception 'Group name must be between 1 and 60 characters' using errcode = '22023';
  end if;

  insert into public.groups (owner_id, name)
  values (v_user_id, btrim(p_name))
  returning * into v_group;

  insert into public.group_members (group_id, user_id, role)
  values (v_group.id, v_user_id, 'owner');

  return query select v_group.id, v_group.name, v_group.invite_code;
end;
$$;

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
  on conflict (group_id, user_id) do nothing;

  return query select v_group.id, v_group.name;
end;
$$;

create or replace function public.leave_group(p_group_id bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  if (select private.is_group_owner(p_group_id)) then
    raise exception 'The owner must delete the group instead of leaving it' using errcode = '22023';
  end if;

  delete from public.group_members
  where group_id = p_group_id and user_id = v_user_id;
end;
$$;

create or replace function public.delete_group(p_group_id bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  if not (select private.is_group_owner(p_group_id)) then
    raise exception 'Only the group owner can delete this group' using errcode = '42501';
  end if;

  delete from public.groups where id = p_group_id;
end;
$$;

create or replace function public.update_group(
  p_group_id bigint,
  p_name text,
  p_regenerate_invite boolean default false
)
returns table (group_id bigint, group_name text, invite_code text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_group public.groups%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  if not (select private.is_group_owner(p_group_id)) then
    raise exception 'Only the group owner can update this group' using errcode = '42501';
  end if;
  if p_name is null or char_length(btrim(p_name)) not between 1 and 60 then
    raise exception 'Group name must be between 1 and 60 characters' using errcode = '22023';
  end if;

  update public.groups
  set name = btrim(p_name),
      invite_code = case
        when p_regenerate_invite then upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10))
        else invite_code
      end
  where id = p_group_id
  returning * into v_group;

  return query select v_group.id, v_group.name, v_group.invite_code;
end;
$$;

create or replace function private.leaderboard_scores(p_period text)
returns table (user_id uuid, score bigint)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_period not in ('daily', 'weekly', 'all') then
    raise exception 'Period must be daily, weekly, or all' using errcode = '22023';
  end if;

  if p_period = 'all' then
    return query
    select s.user_id, s.ranked_count
    from public.user_stats as s;
  elsif p_period = 'daily' then
    return query
    select d.user_id, sum(d.ranked_count)::bigint
    from public.daily_progress as d
    join public.profiles as p on p.user_id = d.user_id
    where d.progress_date = (now() at time zone p.timezone)::date
    group by d.user_id;
  else
    return query
    select d.user_id, sum(d.ranked_count)::bigint
    from public.daily_progress as d
    join public.profiles as p on p.user_id = d.user_id
    where d.progress_date between ((now() at time zone p.timezone)::date - 6)
                              and (now() at time zone p.timezone)::date
    group by d.user_id;
  end if;
end;
$$;

create or replace function public.get_global_leaderboard(
  p_period text default 'all',
  p_limit integer default 50
)
returns table (
  rank_position bigint,
  user_id uuid,
  display_name text,
  avatar_url text,
  score bigint,
  is_current_user boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  if p_limit not between 1 and 100 then
    raise exception 'Limit must be between 1 and 100' using errcode = '22023';
  end if;

  return query
  with ranked as (
    select
      rank() over (order by s.score desc) as rank_position,
      p.user_id,
      p.display_name,
      p.avatar_url,
      s.score
    from private.leaderboard_scores(p_period) as s
    join public.profiles as p on p.user_id = s.user_id
    where p.show_on_global_leaderboard and s.score > 0
  )
  select
    r.rank_position,
    r.user_id,
    r.display_name,
    r.avatar_url,
    r.score,
    r.user_id = auth.uid()
  from ranked as r
  order by r.score desc, r.user_id
  limit p_limit;
end;
$$;

create or replace function public.get_my_global_rank(p_period text default 'all')
returns table (rank_position bigint, score bigint)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;

  return query
  with ranked as (
    select
      rank() over (order by s.score desc) as rank_position,
      p.user_id,
      s.score
    from private.leaderboard_scores(p_period) as s
    join public.profiles as p on p.user_id = s.user_id
    where p.show_on_global_leaderboard and s.score > 0
  )
  select r.rank_position, r.score
  from ranked as r
  where r.user_id = auth.uid();
end;
$$;

create or replace function public.get_group_leaderboard(
  p_group_id bigint,
  p_period text default 'all',
  p_limit integer default 100
)
returns table (
  rank_position bigint,
  user_id uuid,
  display_name text,
  avatar_url text,
  score bigint,
  is_current_user boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  if not (select private.is_group_member(p_group_id)) then
    raise exception 'You are not a member of this group' using errcode = '42501';
  end if;
  if p_limit not between 1 and 100 then
    raise exception 'Limit must be between 1 and 100' using errcode = '22023';
  end if;

  return query
  with member_scores as (
    select
      gm.user_id,
      p.display_name,
      p.avatar_url,
      coalesce(s.score, 0)::bigint as score
    from public.group_members as gm
    join public.profiles as p on p.user_id = gm.user_id
    left join private.leaderboard_scores(p_period) as s on s.user_id = gm.user_id
    where gm.group_id = p_group_id
  ),
  ranked as (
    select
      rank() over (order by ms.score desc) as rank_position,
      ms.user_id,
      ms.display_name,
      ms.avatar_url,
      ms.score
    from member_scores as ms
  )
  select
    r.rank_position,
    r.user_id,
    r.display_name,
    r.avatar_url,
    r.score,
    r.user_id = auth.uid()
  from ranked as r
  order by r.score desc, r.user_id
  limit p_limit;
end;
$$;

create or replace function public.get_my_group_rank(
  p_group_id bigint,
  p_period text default 'all'
)
returns table (rank_position bigint, score bigint)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  if not (select private.is_group_member(p_group_id)) then
    raise exception 'You are not a member of this group' using errcode = '42501';
  end if;

  return query
  with member_scores as (
    select gm.user_id, coalesce(s.score, 0)::bigint as score
    from public.group_members as gm
    left join private.leaderboard_scores(p_period) as s on s.user_id = gm.user_id
    where gm.group_id = p_group_id
  ),
  ranked as (
    select
      rank() over (order by ms.score desc) as rank_position,
      ms.user_id,
      ms.score
    from member_scores as ms
  )
  select r.rank_position, r.score
  from ranked as r
  where r.user_id = auth.uid();
end;
$$;

revoke all on public.profiles from anon, authenticated;
revoke all on public.user_stats from anon, authenticated;
revoke all on public.daily_progress from anon, authenticated;
revoke all on public.zikr_progress from anon, authenticated;
revoke all on public.progress_sync_devices from anon, authenticated;
revoke all on public.groups from anon, authenticated;
revoke all on public.group_members from anon, authenticated;

grant select on public.profiles to authenticated;
grant update (display_name, avatar_url, timezone, show_on_global_leaderboard)
  on public.profiles to authenticated;
grant select on public.user_stats to authenticated;
grant select on public.daily_progress to authenticated;
grant select on public.zikr_progress to authenticated;
grant select on public.progress_sync_devices to authenticated;
grant select on public.groups to authenticated;
grant select on public.group_members to authenticated;

revoke all on function public.handle_new_user() from public, anon, authenticated;
revoke all on function private.set_updated_at() from public, anon, authenticated;
revoke all on function private.validate_profile_timezone() from public, anon, authenticated;
revoke all on function private.is_group_member(bigint) from public, anon, authenticated;
revoke all on function private.is_group_owner(bigint) from public, anon, authenticated;
revoke all on function private.leaderboard_scores(text) from public, anon, authenticated;

grant usage on schema private to authenticated;
grant execute on function private.is_group_member(bigint) to authenticated;
grant execute on function private.is_group_owner(bigint) to authenticated;

revoke all on function public.sync_progress(uuid, bigint, text, date, bigint, bigint)
  from public, anon, authenticated;
revoke all on function public.create_group(text) from public, anon, authenticated;
revoke all on function public.join_group(text) from public, anon, authenticated;
revoke all on function public.leave_group(bigint) from public, anon, authenticated;
revoke all on function public.delete_group(bigint) from public, anon, authenticated;
revoke all on function public.update_group(bigint, text, boolean) from public, anon, authenticated;
revoke all on function public.get_global_leaderboard(text, integer) from public, anon, authenticated;
revoke all on function public.get_my_global_rank(text) from public, anon, authenticated;
revoke all on function public.get_group_leaderboard(bigint, text, integer) from public, anon, authenticated;
revoke all on function public.get_my_group_rank(bigint, text) from public, anon, authenticated;

grant execute on function public.sync_progress(uuid, bigint, text, date, bigint, bigint)
  to authenticated;
grant execute on function public.create_group(text) to authenticated;
grant execute on function public.join_group(text) to authenticated;
grant execute on function public.leave_group(bigint) to authenticated;
grant execute on function public.delete_group(bigint) to authenticated;
grant execute on function public.update_group(bigint, text, boolean) to authenticated;
grant execute on function public.get_global_leaderboard(text, integer) to authenticated;
grant execute on function public.get_my_global_rank(text) to authenticated;
grant execute on function public.get_group_leaderboard(bigint, text, integer) to authenticated;
grant execute on function public.get_my_group_rank(bigint, text) to authenticated;

commit;

-- SOS Mesh 2.0: accounts, devices, activity log, synced SOS and the admin
-- audit trail.
--
-- Security model: the anon key is public (it ships in the app and the admin
-- web), so every rule lives here. Row Level Security is on for every table.
-- Users see and change only their own rows, and only the columns granted
-- below. Logs are append-only for everyone. Admins read everything, but
-- every admin change goes through a security-definer function that checks
-- the caller is an admin and writes admin_audit in the same transaction.

-- ---------------------------------------------------------------- types --

create type public.app_role as enum ('user', 'admin');

create type public.sos_status as enum (
  'open', 'acknowledged', 'resolved', 'false_alarm'
);

-- Everything the app may log. Adding an action is a migration, so a
-- compromised or buggy client cannot invent new kinds of records.
create type public.activity_action as enum (
  'sign_up', 'sign_in', 'sign_out', 'app_open', 'mesh_start', 'mesh_stop',
  'sos_sent', 'safe_sent', 'sos_received', 'profile_updated'
);

-- --------------------------------------------------------------- tables --

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  email text not null,
  display_name text not null default ''
    check (char_length(display_name) <= 80),
  phone text check (phone is null or phone ~ '^\+?[0-9 .-]{8,20}$'),
  emergency_contact text check (char_length(emergency_contact) <= 120),
  blood_type text check (
    blood_type in ('A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-')
  ),
  medical_notes text check (char_length(medical_notes) <= 500),
  role public.app_role not null default 'user',
  banned boolean not null default false,
  banned_reason text check (char_length(banned_reason) <= 300),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  -- Random id the app makes on first launch (8 bytes, hex). Deliberately
  -- not the mesh identity, so the server cannot link a phone's account to
  -- what it relays.
  install_id text not null check (install_id ~ '^[0-9a-f]{16}$'),
  model text check (char_length(model) <= 80),
  platform text check (char_length(platform) <= 40),
  app_version text check (char_length(app_version) <= 40),
  first_seen timestamptz not null default now(),
  last_seen timestamptz not null default now(),
  unique (user_id, install_id)
);

create table public.activity_logs (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles (id) on delete cascade,
  device_id uuid references public.devices (id) on delete set null,
  action public.activity_action not null,
  details jsonb not null default '{}'::jsonb
    check (jsonb_typeof(details) = 'object' and pg_column_size(details) <= 4096),
  -- When the phone says it happened (it may sync hours later); created_at is
  -- when the server got it and is the one to trust.
  client_time timestamptz,
  created_at timestamptz not null default now()
);

create table public.sos_reports (
  id uuid primary key default gen_random_uuid(),
  -- The mesh message id, so the same SOS synced twice stays one report.
  message_id text not null unique check (message_id ~ '^[0-9a-f]{32}$'),
  -- Who uploaded it: the sender, or (relayed) a phone that received it over
  -- the mesh and had Internet, which makes it a bridge for people offline.
  user_id uuid not null references public.profiles (id) on delete cascade,
  device_id uuid references public.devices (id) on delete set null,
  relayed boolean not null default false,
  -- From the simulator's demo network, not a real person.
  demo boolean not null default false,
  -- The sender as the mesh knows it (node id and the name it signed).
  origin_mesh_id text check (origin_mesh_id ~ '^[0-9a-f]{16}$'),
  sender_name text check (char_length(sender_name) <= 80),
  hops smallint check (hops between 0 and 15),
  body text not null check (char_length(body) <= 2000),
  latitude double precision check (latitude between -90 and 90),
  longitude double precision check (longitude between -180 and 180),
  accuracy real check (accuracy >= 0),
  address text check (char_length(address) <= 255),
  sent_at timestamptz not null,
  status public.sos_status not null default 'open',
  handled_by uuid references public.profiles (id) on delete set null,
  handled_at timestamptz,
  admin_note text check (char_length(admin_note) <= 500),
  created_at timestamptz not null default now(),
  check ((latitude is null) = (longitude is null))
);

create table public.admin_audit (
  id bigint generated always as identity primary key,
  admin_id uuid references public.profiles (id) on delete set null,
  action text not null,
  target_user uuid references public.profiles (id) on delete set null,
  target_sos uuid references public.sos_reports (id) on delete set null,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index activity_logs_user_time on public.activity_logs (user_id, created_at desc);
create index activity_logs_time on public.activity_logs (created_at desc);
create index activity_logs_action_time on public.activity_logs (action, created_at desc);
create index sos_reports_time on public.sos_reports (sent_at desc);
create index sos_reports_status on public.sos_reports (status, sent_at desc);
create index sos_reports_user on public.sos_reports (user_id);
create index devices_user on public.devices (user_id);
create index admin_audit_time on public.admin_audit (created_at desc);

-- ------------------------------------------------------------- helpers --
-- security definer + empty search_path: they read profiles without RLS
-- recursion and cannot be tricked by objects in another schema.

create function public.is_admin()
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'admin' and not banned
  );
$$;

create function public.is_active_user()
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.profiles where id = auth.uid() and not banned
  );
$$;

create function public.owns_device(device uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select device is null or exists (
    select 1 from public.devices where id = device and user_id = auth.uid()
  );
$$;

-- A profile for every new account, named from the sign-up form.
create function public.handle_new_user()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  insert into public.profiles (id, email, display_name)
  values (
    new.id,
    coalesce(new.email, ''),
    left(coalesce(new.raw_user_meta_data ->> 'display_name', ''), 80)
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

create function public.touch_updated_at()
returns trigger
language plpgsql set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger profiles_touch
  before update on public.profiles
  for each row execute function public.touch_updated_at();

-- At most 60 log rows a minute per account: enough for any real use, and a
-- leaked session cannot fill the table.
create function public.limit_activity()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if (
    select count(*) from public.activity_logs
    where user_id = new.user_id and created_at > now() - interval '1 minute'
  ) >= 60 then
    raise exception 'Quá nhiều nhật ký trong một phút' using errcode = '54000';
  end if;
  return new;
end;
$$;

create trigger activity_logs_limit
  before insert on public.activity_logs
  for each row execute function public.limit_activity();

-- ------------------------------------------------------------ RLS rules --

alter table public.profiles enable row level security;
alter table public.devices enable row level security;
alter table public.activity_logs enable row level security;
alter table public.sos_reports enable row level security;
alter table public.admin_audit enable row level security;

-- Start from nothing, then grant exactly what each role needs.
revoke all on public.profiles, public.devices, public.activity_logs,
  public.sos_reports, public.admin_audit from anon, authenticated;

grant select on public.profiles to authenticated;
grant update (display_name, phone, emergency_contact, blood_type, medical_notes)
  on public.profiles to authenticated;
create policy profiles_read on public.profiles for select to authenticated
  using (id = auth.uid() or public.is_admin());
create policy profiles_update_own on public.profiles for update to authenticated
  using (id = auth.uid() and not banned)
  with check (id = auth.uid());

grant select on public.devices to authenticated;
create policy devices_read on public.devices for select to authenticated
  using (user_id = auth.uid() or public.is_admin());

grant select, insert on public.activity_logs to authenticated;
create policy activity_read on public.activity_logs for select to authenticated
  using (user_id = auth.uid() or public.is_admin());
create policy activity_insert_own on public.activity_logs for insert to authenticated
  with check (
    user_id = auth.uid()
    and public.is_active_user()
    and public.owns_device(device_id)
    and (client_time is null or client_time < now() + interval '1 hour')
  );

grant select, insert on public.sos_reports to authenticated;
create policy sos_read on public.sos_reports for select to authenticated
  using (user_id = auth.uid() or public.is_admin());
create policy sos_insert_own on public.sos_reports for insert to authenticated
  with check (
    user_id = auth.uid()
    and public.is_active_user()
    and public.owns_device(device_id)
    and status = 'open'
    and handled_by is null
    and handled_at is null
    and admin_note is null
  );

grant select on public.admin_audit to authenticated;
create policy audit_read on public.admin_audit for select to authenticated
  using (public.is_admin());

-- ------------------------------------------------- functions for the app --

-- Registers (or refreshes) this phone for the signed-in user; returns its id.
create function public.register_device(
  p_install_id text, p_model text, p_platform text, p_app_version text
)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  result uuid;
begin
  if not public.is_active_user() then
    raise exception 'Tài khoản không hoạt động' using errcode = '42501';
  end if;
  insert into public.devices (user_id, install_id, model, platform, app_version)
  values (auth.uid(), p_install_id, left(p_model, 80), left(p_platform, 40),
          left(p_app_version, 40))
  on conflict (user_id, install_id) do update
    set model = excluded.model, platform = excluded.platform,
        app_version = excluded.app_version, last_seen = now()
  returning id into result;
  return result;
end;
$$;

-- -------------------------------------------- functions for the admin web --

create function public.require_admin()
returns uuid
language plpgsql stable security definer set search_path = ''
as $$
begin
  if not public.is_admin() then
    raise exception 'Chỉ quản trị viên được làm việc này' using errcode = '42501';
  end if;
  return auth.uid();
end;
$$;

create function public.admin_set_banned(
  p_user uuid, p_banned boolean, p_reason text default null
)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := public.require_admin();
begin
  if p_user = me then
    raise exception 'Không thể tự khóa tài khoản của mình' using errcode = '42501';
  end if;
  update public.profiles
    set banned = p_banned,
        banned_reason = case when p_banned then left(p_reason, 300) end
    where id = p_user;
  if not found then
    raise exception 'Không có người dùng này' using errcode = 'P0002';
  end if;
  insert into public.admin_audit (admin_id, action, target_user, details)
  values (me, case when p_banned then 'ban' else 'unban' end, p_user,
          jsonb_build_object('reason', p_reason));
end;
$$;

create function public.admin_set_role(p_user uuid, p_role public.app_role)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := public.require_admin();
  before public.app_role;
begin
  if p_user = me and p_role <> 'admin' then
    raise exception 'Không thể tự bỏ quyền quản trị của mình' using errcode = '42501';
  end if;
  select role into before from public.profiles where id = p_user for update;
  if not found then
    raise exception 'Không có người dùng này' using errcode = 'P0002';
  end if;
  update public.profiles set role = p_role where id = p_user;
  insert into public.admin_audit (admin_id, action, target_user, details)
  values (me, 'set_role', p_user,
          jsonb_build_object('from', before, 'to', p_role));
end;
$$;

create function public.admin_set_sos_status(
  p_report uuid, p_status public.sos_status, p_note text default null
)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := public.require_admin();
  before public.sos_status;
begin
  select status into before from public.sos_reports where id = p_report for update;
  if not found then
    raise exception 'Không có SOS này' using errcode = 'P0002';
  end if;
  update public.sos_reports
    set status = p_status,
        admin_note = coalesce(left(p_note, 500), admin_note),
        handled_by = case when p_status = 'open' then null else me end,
        handled_at = case when p_status = 'open' then null else now() end
    where id = p_report;
  insert into public.admin_audit (admin_id, action, target_sos, details)
  values (me, 'set_sos_status', p_report,
          jsonb_build_object('from', before, 'to', p_status, 'note', p_note));
end;
$$;

create function public.admin_stats()
returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
begin
  perform public.require_admin();
  return jsonb_build_object(
    'users', (select count(*) from public.profiles),
    'banned', (select count(*) from public.profiles where banned),
    'admins', (select count(*) from public.profiles where role = 'admin'),
    'devices_active_24h',
      (select count(*) from public.devices where last_seen > now() - interval '24 hours'),
    'sos_24h',
      (select count(*) from public.sos_reports where sent_at > now() - interval '24 hours'),
    'sos_open',
      (select count(*) from public.sos_reports where status = 'open' and not demo),
    'activity_24h',
      (select count(*) from public.activity_logs where created_at > now() - interval '24 hours')
  );
end;
$$;

-- Functions are callable by signed-in users only; each checks its own rules.
revoke execute on function public.is_admin(), public.is_active_user(),
  public.owns_device(uuid), public.register_device(text, text, text, text),
  public.require_admin(), public.admin_set_banned(uuid, boolean, text),
  public.admin_set_role(uuid, public.app_role),
  public.admin_set_sos_status(uuid, public.sos_status, text),
  public.admin_stats(), public.handle_new_user(), public.limit_activity()
  from public, anon;
grant execute on function public.is_admin(), public.is_active_user(),
  public.owns_device(uuid), public.register_device(text, text, text, text),
  public.require_admin(), public.admin_set_banned(uuid, boolean, text),
  public.admin_set_role(uuid, public.app_role),
  public.admin_set_sos_status(uuid, public.sos_status, text),
  public.admin_stats()
  to authenticated;

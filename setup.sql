-- Passion Project Workbook: database setup for Supabase.
-- Run this whole file once in Supabase: SQL Editor > New query > paste > Run.

-- ---------------------------------------------------------------
-- Settings the browser can never read (no policies are defined).
-- The sign-up code is checked on the server when an account is created.
-- ---------------------------------------------------------------
create table if not exists public.app_settings (
  key   text primary key,
  value text not null
);
alter table public.app_settings enable row level security;
revoke all on public.app_settings from anon, authenticated;
insert into public.app_settings (key, value)
values ('signup_code', 'CHANGE-THIS-CODE')
on conflict (key) do nothing;

-- ---------------------------------------------------------------
-- People
-- ---------------------------------------------------------------
create table if not exists public.profiles (
  id           uuid primary key references auth.users (id) on delete cascade,
  username     text not null unique check (username ~ '^[a-z0-9._-]{3,30}$'),
  display_name text not null check (char_length(display_name) between 1 and 80),
  role         text not null default 'student' check (role in ('student', 'advisor', 'admin')),
  advisor_id   uuid references public.profiles (id) on delete set null,
  created_at   timestamptz not null default now()
);
alter table public.profiles enable row level security;

-- One workbook per student, stored as a single JSON document.
create table if not exists public.workbooks (
  user_id    uuid primary key references public.profiles (id) on delete cascade,
  data       jsonb not null default '{}'::jsonb,
  version    integer not null default 0,
  updated_at timestamptz not null default now()
);
alter table public.workbooks enable row level security;

-- ---------------------------------------------------------------
-- Helpers (security definer so policies can look at profiles
-- without triggering recursive policy checks)
-- ---------------------------------------------------------------
create or replace function public.my_role()
returns text language sql stable security definer set search_path = public as $$
  select role from public.profiles where id = auth.uid()
$$;

create or replace function public.is_my_student(student uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = student and advisor_id = auth.uid())
$$;

create or replace function public.is_advisor(uid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = uid and role in ('advisor', 'admin'))
$$;

-- Names for the advisor drop-down on the sign-up form (works before sign-in).
create or replace function public.list_advisors()
returns table (id uuid, display_name text)
language sql stable security definer set search_path = public as $$
  select p.id, p.display_name from public.profiles p
  where p.role in ('advisor', 'admin') order by p.display_name
$$;
revoke all on function public.list_advisors() from public;
grant execute on function public.list_advisors() to anon, authenticated;

-- ---------------------------------------------------------------
-- Create a profile and an empty workbook whenever someone signs up.
-- Wrong class code = no account. Everyone starts as a student.
-- ---------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  wanted text;
  given  text;
  adv    uuid;
begin
  select value into wanted from public.app_settings where key = 'signup_code';
  given := new.raw_user_meta_data ->> 'code';
  if wanted is null or given is distinct from wanted then
    raise exception 'Invalid class code';
  end if;

  adv := nullif(new.raw_user_meta_data ->> 'advisor_id', '')::uuid;
  if adv is not null and not public.is_advisor(adv) then
    adv := null;
  end if;

  insert into public.profiles (id, username, display_name, advisor_id)
  values (
    new.id,
    lower(new.raw_user_meta_data ->> 'username'),
    left(new.raw_user_meta_data ->> 'display_name', 80),
    adv
  );
  insert into public.workbooks (user_id) values (new.id);
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  new.version := old.version + 1;
  return new;
end $$;

drop trigger if exists workbooks_touch on public.workbooks;
create trigger workbooks_touch
  before update on public.workbooks
  for each row execute function public.touch_updated_at();

-- ---------------------------------------------------------------
-- Who can see and change what
-- ---------------------------------------------------------------
drop policy if exists profiles_read on public.profiles;
create policy profiles_read on public.profiles for select to authenticated
  using (
    id = auth.uid()
    or advisor_id = auth.uid()
    or role in ('advisor', 'admin')
    or public.my_role() = 'admin'
  );

-- A person may edit their own row but never their own role.
drop policy if exists profiles_update_self on public.profiles;
create policy profiles_update_self on public.profiles for update to authenticated
  using (id = auth.uid())
  with check (
    id = auth.uid()
    and role = public.my_role()
    and (advisor_id is null or public.is_advisor(advisor_id))
  );

drop policy if exists profiles_admin_all on public.profiles;
create policy profiles_admin_all on public.profiles for update to authenticated
  using (public.my_role() = 'admin')
  with check (public.my_role() = 'admin');

drop policy if exists workbooks_read on public.workbooks;
create policy workbooks_read on public.workbooks for select to authenticated
  using (
    user_id = auth.uid()
    or public.is_my_student(user_id)
    or public.my_role() = 'admin'
  );

drop policy if exists workbooks_insert on public.workbooks;
create policy workbooks_insert on public.workbooks for insert to authenticated
  with check (user_id = auth.uid());

drop policy if exists workbooks_update on public.workbooks;
create policy workbooks_update on public.workbooks for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- Nobody can delete through the website. Remove accounts in the Supabase dashboard.

-- ---------------------------------------------------------------
-- After you create your own account on the site, make yourself an admin:
--   update public.profiles set role = 'admin'   where username = 'your-username';
-- Make an advisor (they sign up like everyone else first):
--   update public.profiles set role = 'advisor' where username = 'their-username';
-- Change the class code students need to create an account:
--   update public.app_settings set value = 'new-code' where key = 'signup_code';
-- ---------------------------------------------------------------

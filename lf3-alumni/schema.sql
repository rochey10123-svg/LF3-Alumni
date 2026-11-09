-- Beyond Campus · Supabase Postgres schema
-- Run in Supabase SQL Editor as a project owner.
create extension if not exists pgcrypto;

create table if not exists public.members (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  member_type text not null default 'student' check (member_type in ('student','alumnus')),
  graduation_year integer check (graduation_year between 1950 and 2100),
  created_at timestamptz not null default now()
);

create table if not exists public.alumni_profiles (
  user_id uuid primary key references public.members(id) on delete cascade,
  country text not null,
  city text not null,
  hospital text not null,
  specialty text not null,
  bio text not null default '',
  willing_to_help_with text[] not null default '{}',
  is_available boolean not null default true,
  consent_public boolean not null default false,
  approval_status text not null default 'pending' check (approval_status in ('pending','approved','rejected')),
  updated_at timestamptz not null default now(),
  constraint profile_lengths check (
    length(country) between 2 and 80 and length(city) between 2 and 100
    and length(hospital) between 2 and 160 and length(specialty) between 2 and 120
    and length(bio) <= 1200
  )
);

create table if not exists public.contact_requests (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references public.members(id) on delete cascade,
  alumnus_id uuid not null references public.alumni_profiles(user_id) on delete cascade,
  message text not null check (length(message) between 20 and 1200),
  status text not null default 'pending' check (status in ('pending','accepted','declined')),
  alumnus_reply text not null default '' check (length(alumnus_reply) <= 1500),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (requester_id <> alumnus_id)
);
create index if not exists requests_requester_idx on public.contact_requests(requester_id, created_at desc);
create index if not exists requests_alumnus_idx on public.contact_requests(alumnus_id, created_at desc);
create index if not exists alumni_country_idx on public.alumni_profiles(country);

create table if not exists public.admins (
  user_id uuid primary key references auth.users(id) on delete cascade
);

create or replace function public.is_admin() returns boolean
language sql security definer set search_path = '' stable
as $$ select exists (select 1 from public.admins where user_id = (select auth.uid())); $$;

create or replace function public.new_member() returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  insert into public.members(id, full_name, member_type)
  values (
    new.id,
    left(coalesce(new.raw_user_meta_data->>'full_name',''),150),
    case when new.raw_user_meta_data->>'member_type' = 'alumnus' then 'alumnus' else 'student' end
  );
  return new;
end;
$$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute procedure public.new_member();

create or replace function public.touch_updated_at() returns trigger
language plpgsql set search_path = ''
as $$ begin new.updated_at = now(); return new; end; $$;
drop trigger if exists alumni_touch on public.alumni_profiles;
create trigger alumni_touch before update on public.alumni_profiles for each row execute procedure public.touch_updated_at();
drop trigger if exists request_touch on public.contact_requests;
create trigger request_touch before update on public.contact_requests for each row execute procedure public.touch_updated_at();

-- A public-facing view omits emails and unapproved/unconsented alumni.
-- security_invoker ensures the underlying table's RLS also applies.
create or replace view public.directory_profiles with (security_invoker = true) as
select a.user_id, m.full_name, m.graduation_year,
  a.country, a.city, a.hospital, a.specialty, a.bio,
  a.willing_to_help_with, a.is_available
from public.alumni_profiles a join public.members m on m.id = a.user_id
where a.approval_status = 'approved' and a.consent_public = true;

alter table public.members enable row level security;
alter table public.alumni_profiles enable row level security;
alter table public.contact_requests enable row level security;
alter table public.admins enable row level security;

-- Only logged-in university members may browse the directory.
create policy member_visible on public.members for select to authenticated
using (id = (select auth.uid()) or (select public.is_admin()) or
 exists(select 1 from public.alumni_profiles a where a.user_id = members.id and a.approval_status='approved' and a.consent_public));
create policy member_own_update on public.members for update to authenticated
using (id = (select auth.uid())) with check (id = (select auth.uid()));

create policy alumni_visible on public.alumni_profiles for select to authenticated
using (user_id = (select auth.uid()) or (select public.is_admin()) or
 (approval_status='approved' and consent_public=true));
create policy alumni_own_insert on public.alumni_profiles for insert to authenticated
with check (user_id = (select auth.uid()) and approval_status='pending' and
 exists(select 1 from public.members m where m.id = (select auth.uid()) and m.member_type='alumnus'));
create policy alumni_own_update on public.alumni_profiles for update to authenticated
using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

create policy requests_select on public.contact_requests for select to authenticated
using (requester_id = (select auth.uid()) or alumnus_id = (select auth.uid()) or (select public.is_admin()));
create policy requests_insert on public.contact_requests for insert to authenticated
with check (requester_id = (select auth.uid()) and status='pending' and alumnus_reply='' and
 exists(select 1 from public.alumni_profiles a where a.user_id=alumnus_id
 and a.approval_status='approved' and a.consent_public and a.is_available));
create policy requests_alumnus_update on public.contact_requests for update to authenticated
using (alumnus_id = (select auth.uid())) with check (alumnus_id = (select auth.uid()));

-- Column-level permissions prevent owners setting their own approval_status,
-- or requesters modifying someone else's request/response.
revoke all on public.members from anon, authenticated;
revoke all on public.alumni_profiles from anon, authenticated;
revoke all on public.contact_requests from anon, authenticated;
revoke all on public.admins from anon, authenticated;
grant select on public.members, public.alumni_profiles, public.contact_requests to authenticated;
grant update (full_name, graduation_year) on public.members to authenticated;
grant insert (user_id,country,city,hospital,specialty,bio,willing_to_help_with,is_available,consent_public)
 on public.alumni_profiles to authenticated;
grant update (country,city,hospital,specialty,bio,willing_to_help_with,is_available,consent_public)
 on public.alumni_profiles to authenticated;
grant insert (requester_id,alumnus_id,message) on public.contact_requests to authenticated;
grant update (status,alumnus_reply) on public.contact_requests to authenticated;
grant select on public.directory_profiles to authenticated;

-- Admin approval must go through a checked security-definer RPC, not a client table UPDATE.
create or replace function public.review_alumnus(p_user_id uuid, p_status text)
returns void language plpgsql security definer set search_path = '' as $$
begin
 if not public.is_admin() then raise exception 'Not authorized'; end if;
 if p_status not in ('approved','rejected','pending') then raise exception 'Invalid decision'; end if;
 if not exists(select 1 from public.alumni_profiles where user_id=p_user_id) then raise exception 'Profile not found'; end if;
 update public.alumni_profiles set approval_status=p_status where user_id=p_user_id;
end $$;
revoke all on function public.review_alumnus(uuid,text) from public, anon;
grant execute on function public.review_alumnus(uuid,text) to authenticated;

create or replace function public.list_pending_alumni()
returns table(user_id uuid,full_name text,graduation_year integer,country text,city text,hospital text,specialty text,bio text,consent_public boolean)
language sql security definer set search_path = '' stable as $$
 select a.user_id,m.full_name,m.graduation_year,a.country,a.city,a.hospital,a.specialty,a.bio,a.consent_public
 from public.alumni_profiles a join public.members m on m.id=a.user_id
 where a.approval_status='pending' and public.is_admin() order by a.updated_at desc;
$$;
revoke all on function public.list_pending_alumni() from public, anon;
grant execute on function public.list_pending_alumni() to authenticated;

-- Prevent a malicious alumnus from repeatedly editing an accepted request
-- or switching it back to pending.
create or replace function public.validate_request_decision() returns trigger
language plpgsql set search_path = '' as $$
begin
 if old.status <> 'pending' then raise exception 'Request already decided'; end if;
 if new.status not in ('accepted','declined') then raise exception 'Decision must be accepted or declined'; end if;
 if new.requester_id <> old.requester_id or new.alumnus_id <> old.alumnus_id or new.message <> old.message then
  raise exception 'Original request cannot be changed';
 end if;
 return new;
end $$;
drop trigger if exists validate_request_update on public.contact_requests;
create trigger validate_request_update before update on public.contact_requests for each row execute procedure public.validate_request_decision();

-- After the first administrator signs up, run ONCE, replacing the address:
-- insert into public.admins(user_id)
-- select id from auth.users where email = 'YOUR_ADMIN_EMAIL@UNIVERSITY.EDU';
-- Never put service_role keys in frontend files.

-- LF3 safeguard: material edits to an approved profile require a fresh admin review.
-- Availability and consent may be changed by the alumnus without a fresh review.
create or replace function public.require_profile_rereview() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
 if old.approval_status='approved' and
   (new.country,new.city,new.hospital,new.specialty,new.bio,new.willing_to_help_with)
   is distinct from
   (old.country,old.city,old.hospital,old.specialty,old.bio,old.willing_to_help_with)
 then
   new.approval_status='pending';
 end if;
 return new;
end $$;
drop trigger if exists alumni_require_rereview on public.alumni_profiles;
create trigger alumni_require_rereview before update on public.alumni_profiles
for each row execute procedure public.require_profile_rereview();

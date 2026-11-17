-- =====================================================
-- Mechvac Contact Directory - COMPLETE Supabase setup (one file)
-- 1. Scroll to the very bottom and edit the 3 admin values
--    (v_username, v_password, v_fullname)
-- 2. Paste this whole file in Supabase > SQL Editor > Run
-- Creates: tables, security rules, Add/Remove user functions
-- and your first Admin login (username@mechvactech.com)
-- Safe to run again (it will not delete any data). To apply an
-- update later, leave v_password as 'ChangeMe@123' at the bottom
-- and no admin login is created or changed.
-- =====================================================

create extension if not exists pgcrypto with schema extensions;

-- 1. PROFILES (one row per login user) ---------------
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text unique not null,
  full_name text not null default '',
  role text not null default 'member' check (role in ('admin','member')),
  approved boolean not null default false,
  created_at timestamptz not null default now()
);

-- First user to sign up becomes admin and is auto-approved.
-- Everyone after that is a member and waits for admin approval.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare n int;
begin
  select count(*) into n from public.profiles;
  insert into public.profiles (id, username, full_name, role, approved)
  values (
    new.id,
    lower(coalesce(new.raw_user_meta_data->>'username', split_part(new.email,'@',1))),
    coalesce(new.raw_user_meta_data->>'full_name',''),
    case when n = 0 then 'admin' else 'member' end,
    n = 0
  );
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- 2. HELPER FUNCTIONS ---------------------------------
create or replace function public.is_admin()
returns boolean language sql security definer stable set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'admin' and approved);
$$;

create or replace function public.is_approved()
returns boolean language sql security definer stable set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and approved);
$$;

-- 3. INDUSTRIES ---------------------------------------
create table if not exists public.industries (
  name text primary key
);
insert into public.industries (name) values
  ('Pharmaceuticals'),('Chemicals'),('Petrochemicals'),('Food & Dairy'),('Packaging'),
  ('Plastics'),('Rubber'),('Automotive'),('Transformer / Electrical'),('Solar'),
  ('Battery'),('Medical Devices'),('EPC'),('Other Manufacturing')
on conflict do nothing;

-- 4. CONTACTS -----------------------------------------
create table if not exists public.contacts (
  id uuid primary key default gen_random_uuid(),
  first_name text not null,
  last_name text default '',
  nickname text default '',
  designation text default '',
  company text default '',
  industry text default '',
  location text default '',
  address text default '',
  phone text default '',
  alt_phone text default '',
  whatsapp text default '',
  email text default '',
  linkedin text default '',
  source text default '',
  pump_in_use text default '',
  tags text[] default '{}',
  created_by uuid references auth.users(id) on delete set null,
  created_by_name text default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists contacts_company_idx on public.contacts (lower(company));
create index if not exists contacts_industry_idx on public.contacts (industry);

-- Stamp the creator server-side so nobody can fake "added by"
create or replace function public.contacts_before_insert()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  new.created_by := auth.uid();
  new.created_by_name := coalesce(
    (select nullif(full_name,'') from public.profiles where id = auth.uid()),
    (select username from public.profiles where id = auth.uid()), '');
  new.created_at := now();
  new.updated_at := now();
  return new;
end $$;

create or replace function public.contacts_before_update()
returns trigger language plpgsql as $$
begin
  new.created_by := old.created_by;
  new.created_by_name := old.created_by_name;
  new.created_at := old.created_at;
  new.updated_at := now();
  return new;
end $$;

drop trigger if exists trg_contacts_ins on public.contacts;
create trigger trg_contacts_ins before insert on public.contacts
  for each row execute function public.contacts_before_insert();
drop trigger if exists trg_contacts_upd on public.contacts;
create trigger trg_contacts_upd before update on public.contacts
  for each row execute function public.contacts_before_update();

-- 4b. PRIVATE REMARKS: only the person who added the contact can read/write ----
create table if not exists public.contact_remarks (
  contact_id uuid primary key references public.contacts(id) on delete cascade,
  remarks text not null default '',
  updated_at timestamptz not null default now()
);

-- move remarks from the old contacts.remarks column (if it still exists) and drop it
do $$
begin
  if exists (select 1 from information_schema.columns
             where table_schema='public' and table_name='contacts' and column_name='remarks') then
    insert into public.contact_remarks (contact_id, remarks)
      select id, remarks from public.contacts where coalesce(remarks,'') <> ''
      on conflict (contact_id) do nothing;
    alter table public.contacts drop column remarks;
  end if;
end $$;

-- 4c. DUPLICATE NUMBERS ARE BLOCKED (phone / alt phone / WhatsApp, last 10 digits) --
create or replace function public.norm_phone(p text)
returns text language sql immutable as $$
  select case when length(regexp_replace(coalesce(p,''), '\D', '', 'g')) < 7 then null
              else right(regexp_replace(p, '\D', '', 'g'), 10) end
$$;

create or replace function public.contacts_check_dup()
returns trigger language plpgsql security definer set search_path = public as $$
declare n text; d public.contacts%rowtype;
begin
  foreach n in array array[public.norm_phone(new.phone), public.norm_phone(new.alt_phone), public.norm_phone(new.whatsapp)] loop
    if n is not null then
      select * into d from public.contacts c
       where c.id <> new.id
         and n in (coalesce(public.norm_phone(c.phone),''), coalesce(public.norm_phone(c.alt_phone),''), coalesce(public.norm_phone(c.whatsapp),''))
       limit 1;
      if found then
        raise exception 'Number % already exists: % % (%), added by %',
          n, d.first_name, coalesce(d.last_name,''), coalesce(d.company,''), coalesce(d.created_by_name,'?')
          using errcode = '23505';
      end if;
    end if;
  end loop;
  return new;
end $$;

drop trigger if exists trg_contacts_dup on public.contacts;
create trigger trg_contacts_dup before insert or update of phone, alt_phone, whatsapp on public.contacts
  for each row execute function public.contacts_check_dup();

-- 4d. DELETE REQUESTS: anyone can ask, only an admin can approve (and delete) -----
create table if not exists public.delete_requests (
  id uuid primary key default gen_random_uuid(),
  contact_id uuid references public.contacts(id) on delete set null,
  contact_name text default '',
  contact_company text default '',
  reason text default '',
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  requested_by uuid references auth.users(id) on delete set null,
  requested_by_name text default '',
  created_at timestamptz not null default now(),
  decided_by uuid references auth.users(id) on delete set null,
  decided_at timestamptz
);
create unique index if not exists delete_requests_one_pending
  on public.delete_requests (contact_id) where status = 'pending';

create or replace function public.delete_requests_before_insert()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  new.status := 'pending';
  new.requested_by := auth.uid();
  new.created_at := now();
  new.decided_by := null;
  new.decided_at := null;
  new.requested_by_name := coalesce(
    (select nullif(full_name,'') from public.profiles where id = auth.uid()),
    (select username from public.profiles where id = auth.uid()), '');
  select trim(first_name || ' ' || coalesce(last_name,'')), coalesce(company,'')
    into new.contact_name, new.contact_company
    from public.contacts where id = new.contact_id;
  return new;
end $$;
drop trigger if exists trg_delreq_ins on public.delete_requests;
create trigger trg_delreq_ins before insert on public.delete_requests
  for each row execute function public.delete_requests_before_insert();

-- when a contact is deleted, its pending request is marked approved
create or replace function public.contacts_before_delete()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update public.delete_requests
     set status = 'approved', decided_by = auth.uid(), decided_at = now()
   where contact_id = old.id and status = 'pending';
  return old;
end $$;
drop trigger if exists trg_contacts_del on public.contacts;
create trigger trg_contacts_del before delete on public.contacts
  for each row execute function public.contacts_before_delete();

-- 5. ROW LEVEL SECURITY -------------------------------
alter table public.profiles   enable row level security;
alter table public.industries enable row level security;
alter table public.contacts   enable row level security;

-- profiles
drop policy if exists "profiles_select" on public.profiles;
create policy "profiles_select" on public.profiles for select
  using (id = auth.uid() or public.is_approved());
drop policy if exists "profiles_admin_update" on public.profiles;
create policy "profiles_admin_update" on public.profiles for update
  using (public.is_admin()) with check (public.is_admin());

-- industries
drop policy if exists "industries_select" on public.industries;
create policy "industries_select" on public.industries for select using (public.is_approved());
drop policy if exists "industries_insert" on public.industries;
create policy "industries_insert" on public.industries for insert with check (public.is_approved());
drop policy if exists "industries_delete" on public.industries;
create policy "industries_delete" on public.industries for delete using (public.is_admin());

-- contacts: everyone approved can read and add;
-- only the creator or an admin can edit; only an admin can delete
drop policy if exists "contacts_select" on public.contacts;
create policy "contacts_select" on public.contacts for select using (public.is_approved());
drop policy if exists "contacts_insert" on public.contacts;
create policy "contacts_insert" on public.contacts for insert with check (public.is_approved());
drop policy if exists "contacts_update" on public.contacts;
create policy "contacts_update" on public.contacts for update
  using (public.is_approved() and (public.is_admin() or created_by = auth.uid()))
  with check (public.is_approved() and (public.is_admin() or created_by = auth.uid()));
drop policy if exists "contacts_delete" on public.contacts;
create policy "contacts_delete" on public.contacts for delete
  using (public.is_admin());

-- remarks: ONLY the user who added the contact (nobody else, not even admins)
alter table public.contact_remarks enable row level security;
drop policy if exists "remarks_select" on public.contact_remarks;
create policy "remarks_select" on public.contact_remarks for select
  using (public.is_approved() and exists (select 1 from public.contacts c where c.id = contact_id and c.created_by = auth.uid()));
drop policy if exists "remarks_insert" on public.contact_remarks;
create policy "remarks_insert" on public.contact_remarks for insert
  with check (public.is_approved() and exists (select 1 from public.contacts c where c.id = contact_id and c.created_by = auth.uid()));
drop policy if exists "remarks_update" on public.contact_remarks;
create policy "remarks_update" on public.contact_remarks for update
  using (public.is_approved() and exists (select 1 from public.contacts c where c.id = contact_id and c.created_by = auth.uid()))
  with check (public.is_approved() and exists (select 1 from public.contacts c where c.id = contact_id and c.created_by = auth.uid()));
drop policy if exists "remarks_delete" on public.contact_remarks;
create policy "remarks_delete" on public.contact_remarks for delete
  using (public.is_approved() and exists (select 1 from public.contacts c where c.id = contact_id and c.created_by = auth.uid()));

-- delete requests: admin sees all, others see only their own; approve/reject only via admin functions
alter table public.delete_requests enable row level security;
drop policy if exists "delreq_select" on public.delete_requests;
create policy "delreq_select" on public.delete_requests for select
  using (public.is_admin() or (public.is_approved() and requested_by = auth.uid()));
drop policy if exists "delreq_insert" on public.delete_requests;
create policy "delreq_insert" on public.delete_requests for insert
  with check (public.is_approved());
drop policy if exists "delreq_cancel" on public.delete_requests;
create policy "delreq_cancel" on public.delete_requests for delete
  using (requested_by = auth.uid() and status = 'pending');

-- 6. ADMIN USER MANAGEMENT (Add / Remove / Reset password) --
-- Add user (admin only)
create or replace function public.admin_create_user(
  p_username text, p_password text, p_full_name text, p_role text default 'member')
returns void language plpgsql security definer set search_path = public, extensions as $$
declare
  v_id uuid := gen_random_uuid();
  v_user text := lower(trim(p_username));
  v_email text;
begin
  if not public.is_admin() then raise exception 'Only an admin can add users'; end if;
  if v_user !~ '^[a-z0-9._-]{3,24}$' then
    raise exception 'User ID must be 3-24 letters, numbers, dot, dash or underscore'; end if;
  if length(coalesce(p_password,'')) < 6 then
    raise exception 'Password must be at least 6 characters'; end if;
  if p_role not in ('admin','member') then raise exception 'Invalid role'; end if;

  v_email := v_user || '@mechvactech.com';
  if exists (select 1 from auth.users where email = v_email) then
    raise exception 'User ID "%" already exists', v_user; end if;

  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    confirmation_token, recovery_token, email_change, email_change_token_new
  ) values (
    '00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated',
    v_email, extensions.crypt(p_password, extensions.gen_salt('bf')), now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object('username', v_user, 'full_name', coalesce(trim(p_full_name),'')),
    now(), now(), '', '', '', ''
  );

  insert into auth.identities (
    id, user_id, provider_id, provider, identity_data, last_sign_in_at, created_at, updated_at
  ) values (
    gen_random_uuid(), v_id, v_id::text, 'email',
    jsonb_build_object('sub', v_id::text, 'email', v_email, 'email_verified', true),
    now(), now(), now()
  );

  -- the signup trigger created the profile; approve it and set the role
  update public.profiles
     set role = p_role, approved = true,
         full_name = coalesce(nullif(trim(p_full_name),''), full_name)
   where id = v_id;
end $$;

-- 2. Remove user (admin only; contacts they added are kept)
create or replace function public.admin_delete_user(p_id uuid)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.is_admin() then raise exception 'Only an admin can remove users'; end if;
  if p_id = auth.uid() then raise exception 'You cannot remove your own account'; end if;
  delete from auth.users where id = p_id;
end $$;

-- 3. Reset password (admin only)
create or replace function public.admin_set_password(p_id uuid, p_password text)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.is_admin() then raise exception 'Only an admin can change passwords'; end if;
  if length(coalesce(p_password,'')) < 6 then
    raise exception 'Password must be at least 6 characters'; end if;
  update auth.users
     set encrypted_password = extensions.crypt(p_password, extensions.gen_salt('bf')), updated_at = now()
   where id = p_id;
end $$;

-- 4. Only logged-in users can call these (and each one re-checks is_admin())
revoke all on function public.admin_create_user(text,text,text,text) from public, anon;
revoke all on function public.admin_delete_user(uuid) from public, anon;
revoke all on function public.admin_set_password(uuid,text) from public, anon;
grant execute on function public.admin_create_user(text,text,text,text) to authenticated;
grant execute on function public.admin_delete_user(uuid) to authenticated;
grant execute on function public.admin_set_password(uuid,text) to authenticated;

-- Approve a delete request: deletes the contact (admin only)
create or replace function public.admin_approve_delete(p_request uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_contact uuid;
begin
  if not public.is_admin() then raise exception 'Only an admin can approve delete requests'; end if;
  select contact_id into v_contact from public.delete_requests where id = p_request and status = 'pending';
  if v_contact is null then raise exception 'Request not found or already handled'; end if;
  delete from public.contacts where id = v_contact;  -- trigger marks the request approved
end $$;

-- Reject a delete request: contact stays (admin only)
create or replace function public.admin_reject_delete(p_request uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Only an admin can reject delete requests'; end if;
  update public.delete_requests
     set status = 'rejected', decided_by = auth.uid(), decided_at = now()
   where id = p_request and status = 'pending';
end $$;

revoke all on function public.admin_approve_delete(uuid) from public, anon;
revoke all on function public.admin_reject_delete(uuid) from public, anon;
grant execute on function public.admin_approve_delete(uuid) to authenticated;
grant execute on function public.admin_reject_delete(uuid) to authenticated;

-- =====================================================
-- 7. CREATE YOUR ADMIN LOGIN  <-- EDIT THE 3 VALUES BELOW
-- Run again with a new password to reset it. If v_password stays 'ChangeMe@123', this step is skipped.
-- =====================================================
do $$
declare
  v_username  text := 'het.patel';        -- <-- User ID used to log in (lowercase, no spaces)
  v_password  text := 'ChangeMe@123';     -- <-- Password (min 6 characters)
  v_fullname  text := 'Het Patel';        -- <-- Name shown in "Added by"

  v_email text := lower(v_username) || '@mechvactech.com';  -- must match EMAIL_DOMAIN in index.html
  v_id    uuid;
begin
  if v_password = 'ChangeMe@123' then
    raise notice 'Admin step skipped (password still ChangeMe@123). Change v_password to create or reset an admin.';
    return;
  end if;
  create extension if not exists pgcrypto with schema extensions;

  select id into v_id from auth.users where email = v_email;

  if v_id is null then
    -- New user
    v_id := gen_random_uuid();

    insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
      confirmation_token, recovery_token, email_change, email_change_token_new
    ) values (
      '00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated',
      v_email, extensions.crypt(v_password, extensions.gen_salt('bf')), now(),
      '{"provider":"email","providers":["email"]}'::jsonb,
      jsonb_build_object('username', lower(v_username), 'full_name', v_fullname),
      now(), now(), '', '', '', ''
    );

    insert into auth.identities (
      id, user_id, provider_id, provider, identity_data, last_sign_in_at, created_at, updated_at
    ) values (
      gen_random_uuid(), v_id, v_id::text, 'email',
      jsonb_build_object('sub', v_id::text, 'email', v_email, 'email_verified', true),
      now(), now(), now()
    );
  else
    -- User already exists: reset password
    update auth.users
       set encrypted_password = extensions.crypt(v_password, extensions.gen_salt('bf')),
           email_confirmed_at = coalesce(email_confirmed_at, now()),
           updated_at = now()
     where id = v_id;
  end if;

  -- Make sure a profile row exists, and force Admin + Approved
  insert into public.profiles (id, username, full_name, role, approved)
  values (v_id, lower(v_username), v_fullname, 'admin', true)
  on conflict (id) do update
    set role = 'admin', approved = true,
        full_name = excluded.full_name, username = excluded.username;

  raise notice 'Admin ready. Login ID: %  (internal email: %)', lower(v_username), v_email;
end $$;

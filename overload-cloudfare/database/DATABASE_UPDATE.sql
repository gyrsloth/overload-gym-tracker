-- =====================================================
-- OVERLOAD — UPDATE (run ONCE in Supabase SQL Editor,
-- after your original DATABASE_SETUP.sql)
-- Adds: usernames, username->email lookup, body weight log
-- =====================================================

-- 1. USERNAMES
alter table profiles add column if not exists username text;
create unique index if not exists profiles_username_key on profiles (lower(username));
alter table profiles drop constraint if exists username_format;
alter table profiles add constraint username_format
  check (username is null or username ~ '^[a-z0-9_]{3,20}$');

-- 2. LOGIN / SIGNUP HELPERS (callable before login)
create or replace function public.email_for_username(u text)
returns text language sql security definer set search_path = public as $$
  select email from profiles where lower(username) = lower(u) limit 1
$$;

create or replace function public.username_available(u text)
returns boolean language sql security definer set search_path = public as $$
  select not exists (select 1 from profiles where lower(username) = lower(u))
$$;

grant execute on function public.email_for_username(text) to anon, authenticated;
grant execute on function public.username_available(text) to anon, authenticated;

-- 3. SIGNUP TRIGGER NOW SAVES USERNAME TOO
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, display_name, email, username)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'display_name', 'Athlete'),
    new.email,
    nullif(lower(new.raw_user_meta_data->>'username'), '')
  )
  on conflict (id) do nothing;
  return new;
end;
$$ language plpgsql security definer;

-- 4. BODY WEIGHT LOG (one row per user per day)
create table if not exists body_weights (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  date date not null,
  weight_kg numeric(5,2) not null check (weight_kg between 20 and 300),
  note text,
  created_at timestamptz default now(),
  unique(user_id, date)
);
alter table body_weights enable row level security;

drop policy if exists "Users can view own weights"   on body_weights;
drop policy if exists "Users can insert own weights" on body_weights;
drop policy if exists "Users can update own weights" on body_weights;
drop policy if exists "Users can delete own weights" on body_weights;
create policy "Users can view own weights"   on body_weights for select using (auth.uid() = user_id);
create policy "Users can insert own weights" on body_weights for insert with check (auth.uid() = user_id);
create policy "Users can update own weights" on body_weights for update using (auth.uid() = user_id);
create policy "Users can delete own weights" on body_weights for delete using (auth.uid() = user_id);

-- 5. OPTIONAL: payments are gone, so this table is no longer used
-- drop table if exists payments;

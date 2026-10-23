-- Disposable local fixture matching the five columns reported by the project owner.
insert into auth.users values('10000000-0000-4000-8000-000000000004','old@example.test','{}');
insert into auth.users values('10000000-0000-4000-8000-000000000005','missing-profile@example.test','{}');
insert into auth.users values('10000000-0000-4000-8000-000000000006','old-name@example.test','{}');
create table public.profiles(
 id uuid primary key references auth.users(id) on delete cascade,
 username text not null unique,
 display_name text,
 license text not null default 'D' check(license in ('D','C','B','A','Pro')),
 created_at timestamptz not null default now()
);
insert into public.profiles(id,username,display_name,license,created_at)
values('10000000-0000-4000-8000-000000000004','legacy_1','Старый тренер','Pro','2025-01-01T00:00:00Z');
insert into public.profiles(id,username,display_name,license)
values('10000000-0000-4000-8000-000000000006','Old Coach/Тренер','Имя из старой версии','C');
alter table public.profiles enable row level security;
grant select on public.profiles to public;
grant update(license) on public.profiles to authenticated;
create policy old_profiles_public on public.profiles for select using(true);
create policy old_profile_update on public.profiles for update using(true);
create function public.handle_new_user() returns trigger language plpgsql security definer as $$
begin
 insert into public.profiles(id,username,display_name) values(new.id,new.raw_user_meta_data->>'username',new.raw_user_meta_data->>'nickname');
 return new;
end; $$;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

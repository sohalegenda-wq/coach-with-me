-- Compatibility prelude used ONLY by upgrade-legacy-profiles.sql.
-- It is not a standalone installation script.
DO $legacy_guard$
DECLARE r record; expected record; extra text; n integer; targets text[]; definition text;
BEGIN
 if to_regclass('public.profiles') is null then raise exception 'Нет старой public.profiles. Используйте setup-sql-editor.sql'; end if;
 if (select count(*) from information_schema.columns where table_schema='public' and table_name='profiles')<>5 then
  raise exception 'Структура profiles отличается от проверенной старой версии. Ничего не изменено';
 end if;
 for expected in select * from (values ('id','uuid'),('username','text'),('display_name','text'),('license','text'),('created_at','timestamp with time zone')) as x(name,type) loop
  if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='profiles' and column_name=expected.name and data_type=expected.type) then
   raise exception 'Неподдерживаемый столбец profiles: %. Ничего не изменено',expected.name;
  end if;
 end loop;
 for r in select unnest(array['app_roles','licenses','courses','lessons','assignments','lesson_progress','assignment_submissions','exams','exam_questions','exam_attempts','exam_answers','user_licenses','achievements','user_achievements','tutor_messages','practice_attempts','academy_settings','admin_audit']) as name loop
  if to_regclass(format('public.%I',r.name)) is not null then raise exception 'Таблица % уже существует. Нужна отдельная проверка частичной установки; ничего не изменено',r.name; end if;
 end loop;
 if to_regclass('private.cwm_legacy_profiles_backup') is not null or to_regclass('private.cwm_legacy_setup_backup') is not null then
  raise exception 'Архив предыдущего обновления уже существует. Повторный запуск остановлен';
 end if;
 if exists(select 1 from public.profiles where id is null or username is null or created_at is null) then raise exception 'В старых профилях есть пустые обязательные значения. Ничего не изменено'; end if;
 if exists(select 1 from public.profiles group by id having count(*)>1) or exists(select 1 from public.profiles group by username having count(*)>1) then
  raise exception 'В старых профилях есть повторяющиеся id/username. Ничего не изменено';
 end if;
 if exists(select 1 from pg_trigger where tgrelid='public.profiles'::regclass and not tgisinternal) then
  raise exception 'У profiles есть собственные триггеры. Нужна проверка их назначения; ничего не изменено';
 end if;
 -- Replace only recognisable profile-only Auth provisioning triggers.
 -- Leave unrelated Auth triggers alone and reject ambiguous profile provisioning.
 for r in select t.tgname,pg_get_functiondef(t.tgfoid) as body from pg_trigger t where t.tgrelid='auth.users'::regclass and not t.tgisinternal and (t.tgtype & 4)<>0 loop
  definition:=lower(replace(r.body,'"',''));
  if definition ~ '\mprofiles\M' then
   select array_agg(m[1]) into targets from regexp_matches(definition,'\minsert\s+into\s+([a-z_][a-z0-9_.]*)','g') m;
   if coalesce(cardinality(targets),0)<>1 or targets[1] not in ('profiles','public.profiles')
      or definition ~ '\m(execute|update|delete|perform|call)\M' then
    raise exception 'Auth-триггер % содержит дополнительную логику. Нужна отдельная проверка; ничего не изменено',r.tgname;
   end if;
  end if;
 end loop;
END;
$legacy_guard$;

-- This private copy preserves every original field and row, including old license values.
create table private.cwm_legacy_profiles_backup as table public.profiles;
revoke all on private.cwm_legacy_profiles_backup from public,anon,authenticated;
create table private.cwm_legacy_setup_backup(kind text not null, name text not null, definition text not null);
revoke all on private.cwm_legacy_setup_backup from public,anon,authenticated;
insert into private.cwm_legacy_setup_backup
select 'column',column_name,concat_ws(' | ',data_type,is_nullable,column_default)
from information_schema.columns where table_schema='public' and table_name='profiles';
insert into private.cwm_legacy_setup_backup
select 'constraint',conname,pg_get_constraintdef(oid) from pg_constraint where conrelid='public.profiles'::regclass;
insert into private.cwm_legacy_setup_backup
select 'policy',policyname,row_to_json(p)::text from pg_policies p where schemaname='public' and tablename='profiles';
insert into private.cwm_legacy_setup_backup
select 'grant',grantee||':'||privilege_type,row_to_json(g)::text from information_schema.table_privileges g where table_schema='public' and table_name='profiles';
insert into private.cwm_legacy_setup_backup
select 'column_grant',grantee||':'||column_name||':'||privilege_type,row_to_json(g)::text from information_schema.column_privileges g where table_schema='public' and table_name='profiles';

DO $legacy_security$
DECLARE r record; role_name text; definition text;
BEGIN
 for r in select t.tgname,pg_get_triggerdef(t.oid) as ddl,pg_get_functiondef(t.tgfoid) as body from pg_trigger t where t.tgrelid='auth.users'::regclass and not t.tgisinternal and (t.tgtype & 4)<>0 loop
  definition:=lower(replace(r.body,'"',''));
  if definition ~ '\mprofiles\M' then
   insert into private.cwm_legacy_setup_backup values('auth_trigger',r.tgname,r.ddl),('auth_trigger_function',r.tgname,r.body);
   execute format('drop trigger %I on auth.users',r.tgname);
  end if;
 end loop;
 -- Old permissive policies would OR together with the new owner-only policy.
 for r in select policyname from pg_policies where schemaname='public' and tablename='profiles' loop
  execute format('drop policy %I on public.profiles',r.policyname);
 end loop;
 revoke all on public.profiles from public,anon,authenticated;
 -- Table-level REVOKE does not remove pre-existing column grants.
 for r in select column_name from information_schema.columns where table_schema='public' and table_name='profiles' loop
  foreach role_name in array array['PUBLIC','anon','authenticated'] loop
   execute format('revoke all (%I) on public.profiles from %s',r.column_name,case when role_name='PUBLIC' then 'PUBLIC' else quote_ident(role_name) end);
  end loop;
 end loop;
 -- Retain old license text as history, but new accounts no longer receive its old default.
 -- Only single-column checks on this obsolete field are retired (definitions archived).
 for r in select conname from pg_constraint where conrelid='public.profiles'::regclass and contype='c'
  and conkey=array[(select attnum from pg_attribute where attrelid='public.profiles'::regclass and attname='license')]::smallint[] loop
  execute format('alter table public.profiles drop constraint %I',r.conname);
 end loop;
END;
$legacy_security$;

alter table public.profiles
 add column nickname text,
 add column bio text not null default '' check(char_length(bio)<=1000),
 add column club text not null default '' check(char_length(club)<=80),
 add column avatar text not null default '⚽' check(avatar in ('⚽','🧠','🏆','📋','🦅','🦁')),
 add column banned boolean not null default false,
 alter column license drop not null,
 alter column license drop default,
 alter column created_at set default now();
update public.profiles set nickname=case
 when char_length(btrim(coalesce(display_name,'')))>=2 then left(btrim(display_name),60)
 when char_length(username)>=2 then left(username,60)
 else 'Тренер FTCL' end;
alter table public.profiles alter column nickname set not null;
alter table public.profiles add constraint cwm_profile_nickname_length check(char_length(nickname) between 2 and 60);
create unique index cwm_profile_id_unique on public.profiles(id);
create unique index cwm_profile_username_unique on public.profiles(username);
-- Keep existing usernames verbatim. New signups are checked by the new Auth trigger.
-- A NOT VALID FK preserves historical orphan records while enforcing future writes.
DO $legacy_fk$
BEGIN
 if not exists(select 1 from pg_constraint where conrelid='public.profiles'::regclass and contype='f' and confrelid='auth.users'::regclass
  and conkey=array[(select attnum from pg_attribute where attrelid='public.profiles'::regclass and attname='id')]::smallint[]) then
  alter table public.profiles add constraint cwm_profile_auth_user foreign key(id) references auth.users(id) on delete cascade not valid;
 end if;
END;
$legacy_fk$;

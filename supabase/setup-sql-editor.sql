-- CWM: one-time installation through the Supabase Dashboard SQL Editor.
-- Use a project without existing CWM tables. Do not run after applying either migration.
-- Generated from the two canonical migrations by: npm run db:bundle
-- Includes schema, RLS, server functions and starter curriculum. No credentials.
-- All setup changes are atomic: an error rolls back the installation.
BEGIN;

-- CWM / Supabase PostgreSQL. Apply once via `supabase db push`.
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null unique check (username ~ '^[a-z0-9_]{3,24}$'),
  nickname text not null check (char_length(nickname) between 2 and 60),
  bio text not null default '' check (char_length(bio) <= 1000),
  club text not null default '' check (char_length(club) <= 80),
  avatar text not null default '⚽' check (avatar in ('⚽','🧠','🏆','📋','🦅','🦁')),
  banned boolean not null default false,
  created_at timestamptz not null default now()
);
create table public.app_roles (user_id uuid primary key references public.profiles(id) on delete cascade, role text not null check(role in ('student','admin')) default 'student');
create table public.licenses (id text primary key, rank integer not null unique, title text not null);
insert into public.licenses values ('D',1,'Основы тренерского дела'),('C',2,'Развитие игры'),('B',3,'Командная тактика'),('A',4,'Продвинутая тактика'),('Pro',5,'Тренерское мастерство');
create table public.courses (
  id text primary key check(id ~ '^[a-z0-9-]+$'), license_id text not null references public.licenses(id),
  title text not null, description text not null, tag text not null default 'Академия',
  duration text not null default '1 час', color text not null default 'green', icon text not null default '↗',
  position integer not null unique, published boolean not null default true
);
create table public.lessons (
  id text primary key check(id ~ '^[a-z0-9-]+$'), course_id text not null references public.courses(id),
  position integer not null check(position > 0), title text not null, content jsonb not null,
  published boolean not null default true, unique(course_id,position)
);
create table private.lesson_keys (lesson_id text primary key references public.lessons(id) on delete cascade, answers jsonb not null, criteria jsonb not null);
create table public.assignments (id text primary key, lesson_id text not null unique references public.lessons(id), prompt text not null, rubric jsonb not null);
create table public.lesson_progress (
  user_id uuid not null references public.profiles(id) on delete cascade, lesson_id text not null references public.lessons(id),
  step integer not null default 0 check(step between 0 and 5), state jsonb not null default '{}', completed boolean not null default false,
  quiz_score integer not null default 0, updated_at timestamptz not null default now(), primary key(user_id,lesson_id)
);
create table public.assignment_submissions (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id) on delete cascade,
  assignment_id text not null references public.assignments(id), answer jsonb not null, feedback jsonb not null,
  passed boolean not null, created_at timestamptz not null default now()
);
create table public.exams (id text primary key references public.licenses(id), title text not null, enabled boolean not null default true);
create table public.exam_questions (
  id uuid primary key default gen_random_uuid(), exam_id text not null references public.exams(id),
  position integer not null, kind text not null check(kind in ('theory','practice')), prompt text not null,
  options jsonb, rubric jsonb, unique(exam_id,position)
);
create table private.exam_keys (question_id uuid primary key references public.exam_questions(id) on delete cascade, correct integer not null check(correct between 0 and 5));
create table public.exam_attempts (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id) on delete cascade,
  exam_id text not null references public.exams(id), status text not null default 'in_progress' check(status in ('in_progress','submitted','graded','cancelled')),
  questions jsonb not null, draft jsonb not null default '{}', theory_score integer check(theory_score between 0 and 40),
  practice_score integer check(practice_score between 0 and 60), total integer check(total between 0 and 100),
  passed boolean, review jsonb, reviewer_id uuid references public.profiles(id),
  created_at timestamptz not null default now(), submitted_at timestamptz, reviewed_at timestamptz
);
create unique index one_open_attempt on public.exam_attempts(user_id,exam_id) where status in ('in_progress','submitted');
create table private.attempt_keys (attempt_id uuid primary key references public.exam_attempts(id) on delete cascade, answers jsonb not null);
create table public.exam_answers (
  attempt_id uuid not null references public.exam_attempts(id) on delete cascade,
  position integer not null, answer jsonb not null, primary key(attempt_id,position)
);
create table public.user_licenses (
  user_id uuid not null references public.profiles(id) on delete cascade, license_id text not null references public.licenses(id),
  attempt_id uuid unique references public.exam_attempts(id), certificate_id uuid not null default gen_random_uuid() unique,
  awarded_at timestamptz not null default now(), primary key(user_id,license_id)
);
create table public.achievements (id text primary key, title text not null, description text not null, icon text not null);
insert into public.achievements values ('first-lesson','Первый свисток','Завершён первый урок','⚑'),('first-course','На бровке','Завершён полный курс','◇'),('first-license','Тренер в игре','Получена первая лицензия FTCL','🏆');
create table public.user_achievements (user_id uuid not null references public.profiles(id) on delete cascade, achievement_id text not null references public.achievements(id), awarded_at timestamptz not null default now(), primary key(user_id,achievement_id));
create table public.tutor_messages (
  id bigint generated always as identity primary key, user_id uuid not null references public.profiles(id) on delete cascade,
  role text not null check(role in ('user','assistant')), mode text not null check(mode in ('explain','check','train')),
  content text not null check(char_length(content) between 1 and 6000), source text not null check(source in ('ai','guided')),
  created_at timestamptz not null default now()
);
create table public.practice_attempts (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id) on delete cascade,
  license_id text not null references public.licenses(id), score integer not null check(score between 0 and 100), answers jsonb not null,
  created_at timestamptz not null default now()
);
create table public.academy_settings (id boolean primary key default true check(id), tutor_enabled boolean not null default true, tutor_daily_limit integer not null default 15 check(tutor_daily_limit between 0 and 50));
insert into public.academy_settings values(true,true,15);
create table private.tutor_usage (user_id uuid not null references public.profiles(id) on delete cascade, day date not null default current_date, requests integer not null default 0, primary key(user_id,day));
create table public.admin_audit (id bigint generated always as identity primary key, actor_id uuid references public.profiles(id), action text not null, target text, details jsonb, created_at timestamptz not null default now());

create function private.is_admin() returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.app_roles r join public.profiles p on p.id=r.user_id where r.user_id=auth.uid() and r.role='admin' and not p.banned);
$$;
create function private.is_active() returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.profiles where id=auth.uid() and not banned);
$$;
create function private.handle_user() returns trigger language plpgsql security definer set search_path='' as $$
begin
 insert into public.profiles(id,username,nickname) values(new.id, lower(new.raw_user_meta_data->>'username'), new.raw_user_meta_data->>'nickname');
 insert into public.app_roles(user_id) values(new.id);
 return new;
end; $$;
create trigger cwm_user_created after insert on auth.users for each row execute function private.handle_user();
-- Support Auth accounts that predate this application (username can be found in Profile).
insert into public.profiles(id,username,nickname)
select id, 'legacy_' || row_number() over(order by id),
 case when char_length(btrim(coalesce(raw_user_meta_data->>'nickname','')))>=2
 then left(btrim(raw_user_meta_data->>'nickname'),60) else 'Тренер FTCL' end
from auth.users;
insert into public.app_roles(user_id) select id from public.profiles;

-- No client can write scores, roles, licenses, progress or official answers directly.
-- All mutations go through the checked, atomic RPC below (Edge Functions call it as the JWT user).
do $$ declare t text; begin
 foreach t in array array['profiles','app_roles','licenses','courses','lessons','assignments','lesson_progress','assignment_submissions','exams','exam_questions','exam_attempts','exam_answers','user_licenses','achievements','user_achievements','tutor_messages','practice_attempts','academy_settings','admin_audit'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('revoke all on public.%I from anon, authenticated',t);
  execute format('grant select on public.%I to authenticated',t);
 end loop;
end $$;
grant usage on schema private to authenticated, anon;
grant execute on function private.is_active(), private.is_admin() to authenticated, anon;
revoke all on all tables in schema private from public, anon, authenticated;
revoke all on function private.handle_user() from public, anon, authenticated;
revoke all on function private.is_active(), private.is_admin() from public;

grant select on public.courses, public.lessons, public.assignments, public.licenses, public.achievements to anon;
create policy catalog_courses on public.courses for select using(published or private.is_admin());
create policy catalog_lessons on public.lessons for select using((published and exists(select 1 from public.courses c where c.id=course_id and c.published)) or private.is_admin());
create policy catalog_assignments on public.assignments for select using(exists(select 1 from public.lessons l where l.id=lesson_id));
create policy catalog_licenses on public.licenses for select using(true);
create policy catalog_achievements on public.achievements for select using(true);
create policy own_profile on public.profiles for select to authenticated using(id=auth.uid() or private.is_admin());
create policy own_role on public.app_roles for select to authenticated using(user_id=auth.uid() or private.is_admin());
create policy exams_read on public.exams for select to authenticated using(private.is_active());
create policy questions_admin on public.exam_questions for select to authenticated using(private.is_admin());
create policy settings_read on public.academy_settings for select to authenticated using(private.is_active());
create policy audit_admin on public.admin_audit for select to authenticated using(private.is_admin());
do $$ declare t text; begin
 foreach t in array array['lesson_progress','assignment_submissions','exam_attempts','user_licenses','user_achievements','tutor_messages','practice_attempts'] loop
 execute format('create policy own_rows on public.%I for select to authenticated using ((user_id=auth.uid() and private.is_active()) or private.is_admin())',t);
 end loop;
end $$;
create policy own_answers on public.exam_answers for select to authenticated using(exists(select 1 from public.exam_attempts a where a.id=attempt_id and ((a.user_id=auth.uid() and private.is_active()) or private.is_admin())));
create index progress_user on public.lesson_progress(user_id);
create index submissions_user on public.assignment_submissions(user_id,created_at desc);
create index attempts_user on public.exam_attempts(user_id,created_at desc);
create index tutor_user on public.tutor_messages(user_id,created_at desc);
create index practice_user on public.practice_attempts(user_id,created_at desc);

create function public.academy(p_action text, p_payload jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare
 uid uuid := auth.uid(); obj jsonb; result jsonb; rec record; n integer; i integer; correct integer; total_score integer;
 lesson public.lessons%rowtype; key_row private.lesson_keys%rowtype; attempt public.exam_attempts%rowtype;
 qset jsonb; keyset jsonb; answers jsonb; essays jsonb; checks jsonb; board jsonb; criteria jsonb;
 v_passed boolean; level_rank integer; exam text; attempt_id uuid; target uuid; note text; v_review jsonb;
begin
 if uid is null or not private.is_active() then raise exception 'Требуется активный аккаунт' using errcode='42501'; end if;
 if octet_length(p_payload::text)>100000 then raise exception 'Слишком большой запрос'; end if;
 -- Serialize each user's writes: rate limits, double submits, license prerequisites.
 perform pg_advisory_xact_lock(hashtextextended(uid::text,0));
 if p_action like 'admin_%' and not private.is_admin() then raise exception 'Требуются права администратора' using errcode='42501'; end if;
 if p_action='profile' then
  update public.profiles set nickname=btrim(p_payload->>'nickname'), bio=coalesce(p_payload->>'bio',''), club=coalesce(p_payload->>'club',''), avatar=p_payload->>'avatar' where id=uid returning to_jsonb(profiles.*) into result;
  return result;
 elsif p_action in ('save_lesson','submit_lesson') then
  select * into lesson from public.lessons where id=p_payload->>'lesson_id' and published;
  if not found or not exists(select 1 from public.courses where id=lesson.course_id and published) then raise exception 'Урок недоступен'; end if;
  if exists(select 1 from public.lessons l where l.course_id=lesson.course_id and l.position<lesson.position and l.published and not exists(select 1 from public.lesson_progress lp where lp.user_id=uid and lp.lesson_id=l.id and lp.completed)) then raise exception 'Сначала завершите предыдущие уроки курса'; end if;
  select lk.* into key_row from private.lesson_keys lk where lk.lesson_id=lesson.id;
  if not found then raise exception 'Для урока не настроена проверка'; end if;
  obj:=p_payload->'state';
  if obj is null or jsonb_typeof(obj) is distinct from 'object' then raise exception 'Неверный прогресс'; end if;
  v_passed:=false; correct:=0; checks:='[]';
  if p_action='submit_lesson' then
   answers:=obj->'answers'; board:=obj->'board'; criteria:=key_row.criteria;
   if jsonb_typeof(answers) is distinct from 'array' or jsonb_array_length(answers)<>jsonb_array_length(key_row.answers) then raise exception 'Ответьте на все контрольные вопросы'; end if;
   for i in 0..jsonb_array_length(key_row.answers)-1 loop
    if answers->i=key_row.answers->i then correct:=correct+1; end if;
   end loop;
   if board is null or jsonb_typeof(board->'players') is distinct from 'array' or jsonb_array_length(board->'players')<>11 then raise exception 'На поле должно быть 11 игроков'; end if;
   n:=0;
   for rec in select value as p from jsonb_array_elements(board->'players') loop
    if jsonb_typeof(rec.p) is distinct from 'array' or jsonb_array_length(rec.p)<>2 or (rec.p->>0)::numeric not between 5 and 95 or (rec.p->>1)::numeric not between 6 and 94 then raise exception 'Неверные координаты игроков'; end if;
    if (rec.p->>1)::numeric<36 then n:=n+1; end if;
   end loop;
   checks:=jsonb_build_array(
    jsonb_build_object('label','Контрольные вопросы: минимум 80%','pass',correct::numeric/jsonb_array_length(key_row.answers)>=0.8),
    jsonb_build_object('label','Интенсивность прессинга','pass',coalesce(board->>'press'=criteria->>'press',false)),
    jsonb_build_object('label','Ширина команды','pass',coalesce(board->>'width'=criteria->>'width',false)),
    jsonb_build_object('label','Стиль атаки','pass',coalesce(board->>'attack'=criteria->>'attack',false)),
    jsonb_build_object('label','Позиции в верхней трети','pass',n>=(criteria->>'minHigh')::integer),
    jsonb_build_object('label','Объяснение: минимум 40 слов','pass',cardinality(regexp_split_to_array(btrim(coalesce(board->>'rationale','')), E'\\s+'))>=40),
    jsonb_build_object('label','Замена с описанием роли (для Pro)','pass',not coalesce((criteria->>'substitution')::boolean,false) or cardinality(regexp_split_to_array(btrim(coalesce(board->>'substitution','')), E'\\s+'))>=6));
   select bool_and((value->>'pass')::boolean) into v_passed from jsonb_array_elements(checks);
   if (select count(*) from public.assignment_submissions where user_id=uid and created_at>now()-interval '1 minute')>=12 then raise exception 'Слишком много попыток. Подождите минуту'; end if;
   insert into public.assignment_submissions(user_id,assignment_id,answer,feedback,passed) select uid,id,board,checks,v_passed from public.assignments where lesson_id=lesson.id;
  end if;
  insert into public.lesson_progress(user_id,lesson_id,step,state,completed,quiz_score) values(uid,lesson.id,case when v_passed then 5 else least(4,greatest(0,coalesce((p_payload->>'step')::integer,0))) end,obj,v_passed,correct)
  on conflict(user_id,lesson_id) do update set state=excluded.state,step=greatest(lesson_progress.step,excluded.step),completed=lesson_progress.completed or excluded.completed,quiz_score=greatest(lesson_progress.quiz_score,excluded.quiz_score),updated_at=now();
  if v_passed then
   insert into public.user_achievements values(uid,'first-lesson',now()) on conflict do nothing;
   if not exists(select 1 from public.lessons l where l.course_id=lesson.course_id and l.published and not exists(select 1 from public.lesson_progress p where p.lesson_id=l.id and p.user_id=uid and p.completed)) then
    insert into public.user_achievements values(uid,'first-course',now()) on conflict do nothing;
   end if;
  end if;
  return jsonb_build_object('passed',v_passed,'checks',checks,'quiz_score',correct);
 elsif p_action='practice_test' then
  answers:=p_payload->'answers';
  if jsonb_typeof(answers) is distinct from 'array' or jsonb_array_length(answers)<>5 then raise exception 'Нужно 5 ответов'; end if;
  select count(*)::integer into correct from jsonb_array_elements(answers) with ordinality a(value,idx) where value=to_jsonb((array[1,0,1,1,0])[idx]);
  insert into public.practice_attempts(user_id,license_id,score,answers) values(uid,p_payload->>'license_id',correct*20,answers);
  return jsonb_build_object('score',correct*20);
 elsif p_action='start_exam' then
  exam:=p_payload->>'exam_id';
  if not exists(select 1 from public.exams where id=exam and enabled) then raise exception 'Экзамен недоступен'; end if;
  select rank into level_rank from public.licenses where id=exam;
  if level_rank>1 and not exists(select 1 from public.user_licenses ul join public.licenses l on l.id=ul.license_id where ul.user_id=uid and l.rank=level_rank-1) then raise exception 'Сначала получите предыдущую лицензию'; end if;
  if exists(select 1 from public.user_licenses where user_id=uid and license_id=exam) then raise exception 'Эта лицензия уже получена'; end if;
  if not exists(select 1 from public.lessons l join public.courses c on c.id=l.course_id where c.license_id=exam and c.published and l.published) or exists(select 1 from public.lessons l join public.courses c on c.id=l.course_id where c.license_id=exam and c.published and l.published and not exists(select 1 from public.lesson_progress lp where lp.user_id=uid and lp.lesson_id=l.id and lp.completed)) then raise exception 'Сначала завершите все уроки уровня'; end if;
  select * into attempt from public.exam_attempts where user_id=uid and exam_id=exam and status in ('in_progress','submitted');
  if found then return to_jsonb(attempt); end if;
  if (select count(*) from public.exam_attempts where user_id=uid and created_at>now()-interval '1 day')>=3 then raise exception 'Не более трёх официальных попыток за 24 часа'; end if;
  if (select count(*) from public.exam_questions where exam_id=exam and kind='theory')<>20 or (select count(*) from public.exam_questions where exam_id=exam and kind='practice')<>3 then raise exception 'Администратор должен подготовить 20 вопросов и 3 задачи'; end if;
  if (select count(*) from public.exam_questions q join private.exam_keys k on k.question_id=q.id where q.exam_id=exam and q.kind='theory')<>20 then raise exception 'Не настроены ключи экзамена'; end if;
  select jsonb_agg(jsonb_build_object('id',q.id,'kind',q.kind,'prompt',q.prompt,'options',q.options,'rubric',q.rubric,'position',q.position) order by q.position), jsonb_agg(jsonb_build_object('position',q.position,'correct',k.correct) order by q.position) filter(where q.kind='theory') into qset,keyset from public.exam_questions q left join private.exam_keys k on k.question_id=q.id where q.exam_id=exam;
  insert into public.exam_attempts(user_id,exam_id,questions) values(uid,exam,qset) returning id into attempt_id;
  insert into private.attempt_keys values(attempt_id,keyset);
  return (select to_jsonb(a.*) from public.exam_attempts a where a.id=attempt_id);
 elsif p_action in ('save_exam','submit_exam') then
  select * into attempt from public.exam_attempts where id=(p_payload->>'attempt_id')::uuid and user_id=uid for update;
  if not found or attempt.status<>'in_progress' then raise exception 'Попытка уже отправлена или недоступна'; end if;
  obj:=p_payload->'answers';
  if obj is null or jsonb_typeof(obj) is distinct from 'object' then raise exception 'Неверные ответы'; end if;
  if p_action='save_exam' then
   update public.exam_attempts set draft=obj where id=attempt.id;
   return jsonb_build_object('saved',true);
  end if;
  correct:=0;
  for rec in select value as q from jsonb_array_elements(attempt.questions) loop
   note:=rec.q->>'position';
   if rec.q->>'kind'='theory' then
    if not coalesce((obj->>note) ~ '^[0-9]$',false) or (obj->>note)::integer>=jsonb_array_length(rec.q->'options') then raise exception 'Ответьте на все 20 вопросов'; end if;
    select (value->>'correct')::integer into n from jsonb_array_elements((select k.answers from private.attempt_keys k where k.attempt_id=attempt.id)) where value->>'position'=note;
    if obj->>note=n::text then correct:=correct+2; end if;
   else
    if char_length(coalesce(obj->>note,''))>10000 or cardinality(regexp_split_to_array(btrim(coalesce(obj->>note,'')), E'\\s+'))<80 then raise exception 'Каждая практическая задача: от 80 слов до 10000 символов'; end if;
   end if;
   insert into public.exam_answers values(attempt.id,(rec.q->>'position')::integer,obj->note);
  end loop;
  update public.exam_attempts set status='submitted',theory_score=correct,draft=obj,submitted_at=now() where id=attempt.id returning to_jsonb(exam_attempts.*) into result;
  return result;
 elsif p_action='tutor_reserve' then
  select * into rec from public.academy_settings where id;
  if not rec.tutor_enabled then return jsonb_build_object('allowed',false); end if;
  insert into private.tutor_usage(user_id,day,requests) values(uid,current_date,0) on conflict do nothing;
  update private.tutor_usage set requests=requests+1 where user_id=uid and day=current_date and requests<rec.tutor_daily_limit returning requests into n;
  return jsonb_build_object('allowed',found);
 elsif p_action='tutor_log' then
  -- User-scoped history only: not used as trusted instructions for the AI.
  if p_payload->>'mode' not in ('explain','check','train') or p_payload->>'source' not in ('ai','guided') then raise exception 'Неверный режим'; end if;
  if (select count(*) from public.tutor_messages where user_id=uid and created_at>now()-interval '1 minute')>=20 then raise exception 'Слишком много сообщений'; end if;
  insert into public.tutor_messages(user_id,role,mode,content,source) values(uid,'user',p_payload->>'mode',p_payload->>'question',p_payload->>'source'),(uid,'assistant',p_payload->>'mode',p_payload->>'answer',p_payload->>'source');
  return jsonb_build_object('saved',true);
 elsif p_action='admin_review' then
  select * into attempt from public.exam_attempts where id=(p_payload->>'attempt_id')::uuid for update;
  if not found or attempt.status<>'submitted' then raise exception 'Работа уже проверена или не отправлена'; end if;
  if attempt.user_id=uid then raise exception 'Нельзя проверять собственный экзамен'; end if;
  v_review:=p_payload->'review';
  if jsonb_typeof(v_review) is distinct from 'array' or jsonb_array_length(v_review)<>3 then raise exception 'Оцените три задачи'; end if;
  total_score:=0;
  for rec in select value as r from jsonb_array_elements(v_review) loop
   if char_length(btrim(coalesce(rec.r->>'feedback','')))<20 or jsonb_typeof(rec.r->'scores') is distinct from 'array' or jsonb_array_length(rec.r->'scores')<>4 then raise exception 'Для каждой задачи: 4 критерия и отзыв от 20 символов'; end if;
   for obj in select value from jsonb_array_elements(rec.r->'scores') loop
    if obj::text !~ '^[0-5]$' then raise exception 'Каждый критерий: целое число 0–5'; end if;
    total_score:=total_score+obj::text::integer;
   end loop;
  end loop;
  v_passed:=attempt.theory_score+total_score>=70;
  update public.exam_attempts set status='graded',practice_score=total_score,total=theory_score+total_score,passed=v_passed,review=v_review,reviewer_id=uid,reviewed_at=now() where id=attempt.id;
  if v_passed then
   insert into public.user_licenses(user_id,license_id,attempt_id) values(attempt.user_id,attempt.exam_id,attempt.id) on conflict(user_id,license_id) do nothing;
   insert into public.user_achievements values(attempt.user_id,'first-license',now()) on conflict do nothing;
  end if;
  insert into public.admin_audit(actor_id,action,target,details) values(uid,p_action,attempt.id::text,p_payload);
  return jsonb_build_object('passed',v_passed,'total',attempt.theory_score+total_score);
 elsif p_action='admin_block' then
  target:=(p_payload->>'user_id')::uuid;
  if target=uid or exists(select 1 from public.app_roles where user_id=target and role='admin') then raise exception 'Нельзя блокировать администратора'; end if;
  update public.profiles set banned=(p_payload->>'banned')::boolean where id=target;
 elsif p_action='admin_license' then
  target:=(p_payload->>'user_id')::uuid; note:=btrim(p_payload->>'reason');
  if char_length(coalesce(note,''))<20 then raise exception 'Причина: минимум 20 символов'; end if;
  if (p_payload->>'revoke')::boolean then delete from public.user_licenses where user_id=target and license_id=p_payload->>'license_id';
  else insert into public.user_licenses(user_id,license_id) values(target,p_payload->>'license_id') on conflict do nothing; end if;
 elsif p_action='admin_cancel' then
  note:=btrim(p_payload->>'reason');
  if char_length(coalesce(note,''))<20 then raise exception 'Укажите причину отмены'; end if;
  update public.exam_attempts set status='cancelled',review=jsonb_build_object('reason',note) where id=(p_payload->>'attempt_id')::uuid and status in ('in_progress','submitted');
 elsif p_action='admin_settings' then
  update public.academy_settings set tutor_enabled=(p_payload->>'enabled')::boolean,tutor_daily_limit=(p_payload->>'daily_limit')::integer where id;
 elsif p_action='admin_course' then
  obj:=p_payload->'course';
  insert into public.courses(id,license_id,title,description,tag,duration,position,published) values(obj->>'id',obj->>'license_id',obj->>'title',obj->>'description',coalesce(obj->>'tag','Академия'),coalesce(obj->>'duration','1 час'),(obj->>'position')::integer,coalesce((obj->>'published')::boolean,true))
  on conflict(id) do update set title=excluded.title,description=excluded.description,tag=excluded.tag,duration=excluded.duration,published=excluded.published;
 elsif p_action='admin_lesson' then
  obj:=p_payload->'lesson'; answers:=p_payload->'answers'; criteria:=p_payload->'criteria';
  if jsonb_typeof(obj->'content'->'quiz') is distinct from 'array' or jsonb_array_length(obj->'content'->'quiz')=0 or jsonb_array_length(answers)<>jsonb_array_length(obj->'content'->'quiz') then raise exception 'Нужны вопросы и ключи каждого ответа'; end if;
  if criteria->>'press' not in ('low','medium','high') or criteria->>'width' not in ('compact','balanced','wide') or criteria->>'attack' not in ('balanced','direct','possession') or (criteria->>'minHigh')::integer not between 0 and 10 then raise exception 'Неверные критерии доски'; end if;
  insert into public.lessons(id,course_id,position,title,content,published) values(obj->>'id',obj->>'course_id',(obj->>'position')::integer,obj->>'title',obj->'content',coalesce((obj->>'published')::boolean,true)) on conflict(id) do update set title=excluded.title,content=excluded.content,published=excluded.published;
  insert into private.lesson_keys values(obj->>'id',answers,criteria) on conflict(lesson_id) do update set answers=excluded.answers,criteria=excluded.criteria;
  insert into public.assignments values(obj->>'id'||'-task',obj->>'id',obj->'content'->>'scenario',criteria) on conflict(lesson_id) do update set prompt=excluded.prompt,rubric=excluded.rubric;
 elsif p_action='admin_question' then
  obj:=p_payload->'question';
  if obj->>'kind'='theory' and (jsonb_typeof(obj->'options') is distinct from 'array' or jsonb_array_length(obj->'options')<2 or (p_payload->>'correct')::integer not between 0 and jsonb_array_length(obj->'options')-1) then raise exception 'Неверные варианты или ключ'; end if;
  if obj->>'kind'='practice' and (jsonb_typeof(obj->'rubric') is distinct from 'array' or jsonb_array_length(obj->'rubric')<>4) then raise exception 'Для задачи нужны четыре критерия'; end if;
  insert into public.exam_questions(exam_id,position,kind,prompt,options,rubric) values(obj->>'exam_id',(obj->>'position')::integer,obj->>'kind',obj->>'prompt',obj->'options',obj->'rubric') on conflict(exam_id,position) do update set prompt=excluded.prompt,options=excluded.options,rubric=excluded.rubric,kind=excluded.kind returning id into target;
  if obj->>'kind'='theory' then insert into private.exam_keys values(target,(p_payload->>'correct')::integer) on conflict(question_id) do update set correct=excluded.correct; else delete from private.exam_keys where question_id=target; end if;
 else
  raise exception 'Неизвестная операция';
 end if;
 insert into public.admin_audit(actor_id,action,target,details) values(uid,p_action,coalesce(p_payload->>'user_id',p_payload->>'attempt_id',p_payload->'course'->>'id',p_payload->'lesson'->>'id',p_payload->'question'->>'exam_id','settings'),p_payload);
 return jsonb_build_object('saved',true);
end; $$;
revoke all on function public.academy(text,jsonb) from public, anon;
grant execute on function public.academy(text,jsonb) to authenticated;


-- Generated by npm run db:seed from src/catalog.js. Apply after schema migration.
insert into public.courses(id,license_id,title,description,tag,duration,color,icon,position) values('pressing','D','Искусство высокого прессинга','Научитесь возвращать мяч там, где начинается атака соперника. От первого триггера до согласованной работы всей команды.','Основы игры','2 ч 40 мин','green','↗',1);
insert into public.courses(id,license_id,title,description,tag,duration,color,icon,position) values('build-up','C','Выход из-под давления','Создавайте свободного игрока и проходите первую линию прессинга через короткий пас, третьего и смену фланга.','Владение мячом','1 ч 30 мин','blue','⇄',2);
insert into public.courses(id,license_id,title,description,tag,duration,color,icon,position) values('defense','B','Организация обороны','Управляйте расстояниями, страхуйте партнёров и защищайте пространство между линиями.','Командная тактика','1 ч 40 мин','orange','◇',3);
insert into public.courses(id,license_id,title,description,tag,duration,color,icon,position) values('transitions','A','Переходные фазы','Первые секунды после потери и отбора: решения, которые определяют следующий эпизод.','Продвинутая тактика','1 ч 35 мин','purple','↯',4);
insert into public.courses(id,license_id,title,description,tag,duration,color,icon,position) values('management','Pro','Управление командой','Постройте недельный цикл, подготовьте план матча и принимайте решения под давлением.','Тренерское мастерство','1 ч 50 мин','gold','✳',5);
insert into public.lessons(id,course_id,position,title,content) values('pressing-1','pressing',1,'Что такое прессинг?','{"subtitle":"Давление — это коллективное действие","theory":"Прессинг — согласованное ограничение времени и пространства соперника с целью вернуть мяч. Один бегущий нападающий не создаёт системного давления: партнёры должны закрыть ближайшие варианты передачи.","example":"В схеме 4-3-3 форвард направляет центрального защитника к боковой линии дугообразным движением. Вингер закрывает крайнего защитника, а восьмёрка контролирует опорного.","duration":17,"quiz":[{"prompt":"Почему одного игрока недостаточно?","options":["Потому что он мало бегает","Партнёры должны перекрыть варианты передачи","Нужно всегда фолить"],"correct":1,"explanation":"Партнёры должны перекрыть варианты передачи"},{"prompt":"Как перенести принцип в тренировку?","options":["Проверить в игровом упражнении с обратной связью","Только выучить определение","Игнорировать действия партнёров"],"correct":0,"explanation":"Игровое упражнение позволяет увидеть расстояния, решения и взаимодействия."}],"scenario":"Соперник начинает атаку через крайнего защитника. Организуйте высокий прессинг: поднимите линию атаки, выберите интенсивное давление и объясните триггер, страховку и план при выходе соперника.","criteria":{"press":"high","width":"balanced","attack":"direct","minHigh":3}}'::jsonb);
insert into private.lesson_keys values('pressing-1','[1,0]'::jsonb,'{"press":"high","width":"balanced","attack":"direct","minHigh":3}'::jsonb);
insert into public.assignments values('pressing-1-task','pressing-1','Соперник начинает атаку через крайнего защитника. Организуйте высокий прессинг: поднимите линию атаки, выберите интенсивное давление и объясните триггер, страховку и план при выходе соперника.','{"press":"high","width":"balanced","attack":"direct","minHigh":3}'::jsonb);
insert into public.lessons(id,course_id,position,title,content) values('pressing-2','pressing',2,'Триггеры начала прессинга','{"subtitle":"Увидеть момент раньше соперника","theory":"Триггер — сигнал для совместного начала давления: плохой приём, пас назад, передача к боковой линии или мяч на неудобную ногу. Без общего сигнала линия растягивается.","example":"Мяч передают крайнему защитнику у бровки. Вингер ускоряется после передачи, восьмёрка закрывает пас внутрь. Защитная линия поднимается только при давлении на мяч.","duration":19,"quiz":[{"prompt":"Какой эпизод удобен для давления?","options":["Соперник свободно смотрит вперёд","Плохой приём у бровки","Наш защитник лежит на газоне"],"correct":1,"explanation":"Плохой приём у бровки"},{"prompt":"Как перенести принцип в тренировку?","options":["Проверить в игровом упражнении с обратной связью","Только выучить определение","Игнорировать действия партнёров"],"correct":0,"explanation":"Игровое упражнение позволяет увидеть расстояния, решения и взаимодействия."}],"scenario":"Соперник начинает атаку через крайнего защитника. Организуйте высокий прессинг: поднимите линию атаки, выберите интенсивное давление и объясните триггер, страховку и план при выходе соперника.","criteria":{"press":"high","width":"balanced","attack":"direct","minHigh":3}}'::jsonb);
insert into private.lesson_keys values('pressing-2','[1,0]'::jsonb,'{"press":"high","width":"balanced","attack":"direct","minHigh":3}'::jsonb);
insert into public.assignments values('pressing-2-task','pressing-2','Соперник начинает атаку через крайнего защитника. Организуйте высокий прессинг: поднимите линию атаки, выберите интенсивное давление и объясните триггер, страховку и план при выходе соперника.','{"press":"high","width":"balanced","attack":"direct","minHigh":3}'::jsonb);
insert into public.lessons(id,course_id,position,title,content) values('pressing-3','pressing',3,'Компактность команды','{"subtitle":"Двигаться как единое целое","theory":"Компактность — небольшие расстояния между игроками и линиями. При смещении к мячу дальний фланг сужается, но контролирует возможный перевод. Слишком высокая линия без давления на пасующего открывает глубину.","example":"Когда мяч слева, опорный смещается за восьмёркой, дальний вингер входит в полуфланг. Центральные защитники оценивают угрозу забегания за спину.","duration":21,"quiz":[{"prompt":"Когда опасно поднимать линию?","options":["Когда на пасующего нет давления","Когда соперник спиной к воротам","Когда мяч за боковой"],"correct":0,"explanation":"Когда на пасующего нет давления"},{"prompt":"Как перенести принцип в тренировку?","options":["Проверить в игровом упражнении с обратной связью","Только выучить определение","Игнорировать действия партнёров"],"correct":0,"explanation":"Игровое упражнение позволяет увидеть расстояния, решения и взаимодействия."}],"scenario":"Соперник начинает атаку через крайнего защитника. Организуйте высокий прессинг: поднимите линию атаки, выберите интенсивное давление и объясните триггер, страховку и план при выходе соперника.","criteria":{"press":"high","width":"balanced","attack":"direct","minHigh":3}}'::jsonb);
insert into private.lesson_keys values('pressing-3','[0,0]'::jsonb,'{"press":"high","width":"balanced","attack":"direct","minHigh":3}'::jsonb);
insert into public.assignments values('pressing-3-task','pressing-3','Соперник начинает атаку через крайнего защитника. Организуйте высокий прессинг: поднимите линию атаки, выберите интенсивное давление и объясните триггер, страховку и план при выходе соперника.','{"press":"high","width":"balanced","attack":"direct","minHigh":3}'::jsonb);
insert into public.lessons(id,course_id,position,title,content) values('pressing-4','pressing',4,'Перекрытие линий передач','{"subtitle":"Закрыть пас, а не только игрока","theory":"Тень прессинга — пространство за игроком, недоступное для прямой передачи из-за угла его сближения. Бег по дуге позволяет давить на защитника и одновременно закрывать опорного.","example":"Форвард подходит со стороны центра, оставляя пас на фланг. Ближайший вингер готов встретить адресата; команда создаёт ловушку у бровки.","duration":23,"quiz":[{"prompt":"Что даёт движение по дуге?","options":["Больше случайных рывков","Одновременное давление и перекрытие паса","Гарантированный отбор"],"correct":1,"explanation":"Одновременное давление и перекрытие паса"},{"prompt":"Как перенести принцип в тренировку?","options":["Проверить в игровом упражнении с обратной связью","Только выучить определение","Игнорировать действия партнёров"],"correct":0,"explanation":"Игровое упражнение позволяет увидеть расстояния, решения и взаимодействия."}],"scenario":"Соперник начинает атаку через крайнего защитника. Организуйте высокий прессинг: поднимите линию атаки, выберите интенсивное давление и объясните триггер, страховку и план при выходе соперника.","criteria":{"press":"high","width":"balanced","attack":"direct","minHigh":3}}'::jsonb);
insert into private.lesson_keys values('pressing-4','[1,0]'::jsonb,'{"press":"high","width":"balanced","attack":"direct","minHigh":3}'::jsonb);
insert into public.assignments values('pressing-4-task','pressing-4','Соперник начинает атаку через крайнего защитника. Организуйте высокий прессинг: поднимите линию атаки, выберите интенсивное давление и объясните триггер, страховку и план при выходе соперника.','{"press":"high","width":"balanced","attack":"direct","minHigh":3}'::jsonb);
insert into public.lessons(id,course_id,position,title,content) values('pressing-5','pressing',5,'Если соперник вышел из давления','{"subtitle":"Уметь вовремя отступить","theory":"Когда первая линия пройдена, ближайший игрок задерживает атаку, остальные возвращаются за линию мяча. Продолжение разрозненных рывков создаёт свободные зоны.","example":"После передачи за спину восьмёрке опорный замедляет соперника, защитники сохраняют глубину, вингеры возвращаются в средний блок.","duration":25,"quiz":[{"prompt":"Что делать после провала давления?","options":["Всем бежать к мячу","Задержать атаку и восстановить блок","Оставить опорного одного"],"correct":1,"explanation":"Задержать атаку и восстановить блок"},{"prompt":"Как перенести принцип в тренировку?","options":["Проверить в игровом упражнении с обратной связью","Только выучить определение","Игнорировать действия партнёров"],"correct":0,"explanation":"Игровое упражнение позволяет увидеть расстояния, решения и взаимодействия."}],"scenario":"Соперник начинает атаку через крайнего защитника. Организуйте высокий прессинг: поднимите линию атаки, выберите интенсивное давление и объясните триггер, страховку и план при выходе соперника.","criteria":{"press":"high","width":"balanced","attack":"direct","minHigh":3}}'::jsonb);
insert into private.lesson_keys values('pressing-5','[1,0]'::jsonb,'{"press":"high","width":"balanced","attack":"direct","minHigh":3}'::jsonb);
insert into public.assignments values('pressing-5-task','pressing-5','Соперник начинает атаку через крайнего защитника. Организуйте высокий прессинг: поднимите линию атаки, выберите интенсивное давление и объясните триггер, страховку и план при выходе соперника.','{"press":"high","width":"balanced","attack":"direct","minHigh":3}'::jsonb);
insert into public.lessons(id,course_id,position,title,content) values('pressing-6','pressing',6,'Практический тактический разбор','{"subtitle":"Спланировать ловушку","theory":"Оценивайте не только исходную схему, но и положение мяча, дистанции и страховку. Направляйте соперника туда, где у вашей команды численное преимущество.","example":"Соперник начинает через левого защитника. Правый вингер встречает его, форвард закрывает возврат в центр, восьмёрка берёт ближнего полузащитника.","duration":27,"quiz":[{"prompt":"Где полезно создать ловушку?","options":["У боковой линии с поддержкой партнёров","В центре без страховки","У своих ворот без вратаря"],"correct":0,"explanation":"У боковой линии с поддержкой партнёров"},{"prompt":"Как перенести принцип в тренировку?","options":["Проверить в игровом упражнении с обратной связью","Только выучить определение","Игнорировать действия партнёров"],"correct":0,"explanation":"Игровое упражнение позволяет увидеть расстояния, решения и взаимодействия."}],"scenario":"Соперник начинает атаку через крайнего защитника. Организуйте высокий прессинг: поднимите линию атаки, выберите интенсивное давление и объясните триггер, страховку и план при выходе соперника.","criteria":{"press":"high","width":"balanced","attack":"direct","minHigh":3}}'::jsonb);
insert into private.lesson_keys values('pressing-6','[0,0]'::jsonb,'{"press":"high","width":"balanced","attack":"direct","minHigh":3}'::jsonb);
insert into public.assignments values('pressing-6-task','pressing-6','Соперник начинает атаку через крайнего защитника. Организуйте высокий прессинг: поднимите линию атаки, выберите интенсивное давление и объясните триггер, страховку и план при выходе соперника.','{"press":"high","width":"balanced","attack":"direct","minHigh":3}'::jsonb);
insert into public.lessons(id,course_id,position,title,content) values('pressing-7','pressing',7,'Контрольное испытание','{"subtitle":"Соединить все принципы","theory":"Система давления включает триггер, направление, компактность и план на случай выхода соперника. Проверяйте каждый элемент на тренировке в игровых условиях, а не только на доске.","example":"В упражнении 7 на 7 команда получает дополнительное очко за отбор после паса к бровке. После каждой серии обсуждайте расстояния и работу дальних игроков.","duration":29,"quiz":[{"prompt":"Как оценить качество прессинга?","options":["Только по километражу","По согласованности и перекрытым вариантам","Только по числу подкатов"],"correct":1,"explanation":"По согласованности и перекрытым вариантам"},{"prompt":"Как перенести принцип в тренировку?","options":["Проверить в игровом упражнении с обратной связью","Только выучить определение","Игнорировать действия партнёров"],"correct":0,"explanation":"Игровое упражнение позволяет увидеть расстояния, решения и взаимодействия."}],"scenario":"Соперник начинает атаку через крайнего защитника. Организуйте высокий прессинг: поднимите линию атаки, выберите интенсивное давление и объясните триггер, страховку и план при выходе соперника.","criteria":{"press":"high","width":"balanced","attack":"direct","minHigh":3}}'::jsonb);
insert into private.lesson_keys values('pressing-7','[1,0]'::jsonb,'{"press":"high","width":"balanced","attack":"direct","minHigh":3}'::jsonb);
insert into public.assignments values('pressing-7-task','pressing-7','Соперник начинает атаку через крайнего защитника. Организуйте высокий прессинг: поднимите линию атаки, выберите интенсивное давление и объясните триггер, страховку и план при выходе соперника.','{"press":"high","width":"balanced","attack":"direct","minHigh":3}'::jsonb);
insert into public.lessons(id,course_id,position,title,content) values('build-up-1','build-up',1,'Свободный игрок','{"subtitle":"Создать численное преимущество","theory":"При двух нападающих соперника вратарь и два центральных защитника образуют 3 против 2. Широкие позиции создают угол передачи; опорный не должен прятаться за форвардом.","example":"Вратарь привлекает нападающего и отдаёт свободному центральному защитнику. Опорный открывается в другую линию.","duration":17,"quiz":[{"prompt":"Кто помогает создать 3 против 2?","options":["Судья","Вратарь","Только крайний нападающий"],"correct":1,"explanation":"Вратарь"},{"prompt":"Как перенести принцип в тренировку?","options":["Проверить в игровом упражнении с обратной связью","Только выучить определение","Игнорировать действия партнёров"],"correct":0,"explanation":"Игровое упражнение позволяет увидеть расстояния, решения и взаимодействия."}],"scenario":"Соперник прессингует двумя нападающими. Создайте ширину и варианты короткого паса. Объясните роль вратаря, свободного игрока и действия при потере.","criteria":{"press":"medium","width":"wide","attack":"possession","minHigh":2}}'::jsonb);
insert into private.lesson_keys values('build-up-1','[1,0]'::jsonb,'{"press":"medium","width":"wide","attack":"possession","minHigh":2}'::jsonb);
insert into public.assignments values('build-up-1-task','build-up-1','Соперник прессингует двумя нападающими. Создайте ширину и варианты короткого паса. Объясните роль вратаря, свободного игрока и действия при потере.','{"press":"medium","width":"wide","attack":"possession","minHigh":2}'::jsonb);
insert into public.lessons(id,course_id,position,title,content) values('build-up-2','build-up',2,'Игра через третьего','{"subtitle":"Передача ради следующей передачи","theory":"Третий игрок принимает пас после короткой комбинации с партнёром, который играет в касание. Это помогает обойти персональную опеку без рискованного дриблинга.","example":"Защитник отдаёт опорному спиной к воротам соперника. Тот сбрасывает восьмёрке, уже открывшейся лицом вперёд.","duration":19,"quiz":[{"prompt":"Для чего нужен третий?","options":["Для выхода лицом вперёд за линией давления","Для затяжки времени","Для офсайда"],"correct":0,"explanation":"Для выхода лицом вперёд за линией давления"},{"prompt":"Как перенести принцип в тренировку?","options":["Проверить в игровом упражнении с обратной связью","Только выучить определение","Игнорировать действия партнёров"],"correct":0,"explanation":"Игровое упражнение позволяет увидеть расстояния, решения и взаимодействия."}],"scenario":"Соперник прессингует двумя нападающими. Создайте ширину и варианты короткого паса. Объясните роль вратаря, свободного игрока и действия при потере.","criteria":{"press":"medium","width":"wide","attack":"possession","minHigh":2}}'::jsonb);
insert into private.lesson_keys values('build-up-2','[0,0]'::jsonb,'{"press":"medium","width":"wide","attack":"possession","minHigh":2}'::jsonb);
insert into public.assignments values('build-up-2-task','build-up-2','Соперник прессингует двумя нападающими. Создайте ширину и варианты короткого паса. Объясните роль вратаря, свободного игрока и действия при потере.','{"press":"medium","width":"wide","attack":"possession","minHigh":2}'::jsonb);
insert into public.lessons(id,course_id,position,title,content) values('build-up-3','build-up',3,'Смена фланга','{"subtitle":"Найти пространство вдали от мяча","theory":"Сначала привлеките соперника на один фланг, затем переведите мяч через свободного игрока. Проверяйте положение дальнего защитника и качество первого касания.","example":"Левый защитник возвращает мяч центральному, который через вратаря переводит направо. Вингер сохраняет ширину.","duration":21,"quiz":[{"prompt":"Когда перевод полезен?","options":["При любом пасе назад","Когда соперник стянулся к мячу","Когда дальний игрок в офсайде"],"correct":1,"explanation":"Когда соперник стянулся к мячу"},{"prompt":"Как перенести принцип в тренировку?","options":["Проверить в игровом упражнении с обратной связью","Только выучить определение","Игнорировать действия партнёров"],"correct":0,"explanation":"Игровое упражнение позволяет увидеть расстояния, решения и взаимодействия."}],"scenario":"Соперник прессингует двумя нападающими. Создайте ширину и варианты короткого паса. Объясните роль вратаря, свободного игрока и действия при потере.","criteria":{"press":"medium","width":"wide","attack":"possession","minHigh":2}}'::jsonb);
insert into private.lesson_keys values('build-up-3','[1,0]'::jsonb,'{"press":"medium","width":"wide","attack":"possession","minHigh":2}'::jsonb);
insert into public.assignments values('build-up-3-task','build-up-3','Соперник прессингует двумя нападающими. Создайте ширину и варианты короткого паса. Объясните роль вратаря, свободного игрока и действия при потере.','{"press":"medium","width":"wide","attack":"possession","minHigh":2}'::jsonb);
insert into public.lessons(id,course_id,position,title,content) values('defense-1','defense',1,'Средний блок','{"subtitle":"Контролировать опасное пространство","theory":"Средний блок защищает центр и направляет атаку на фланг. Расстояния между линиями важнее формального названия расстановки.","example":"Две четвёрки смещаются к мячу; нападающий закрывает опорного, а дальний крайний защитник сужается.","duration":17,"quiz":[{"prompt":"Что защищать в первую очередь?","options":["Бровку любой ценой","Центр и пространство между линиями","Только игрока с мячом"],"correct":1,"explanation":"Центр и пространство между линиями"},{"prompt":"Как перенести принцип в тренировку?","options":["Проверить в игровом упражнении с обратной связью","Только выучить определение","Игнорировать действия партнёров"],"correct":0,"explanation":"Игровое упражнение позволяет увидеть расстояния, решения и взаимодействия."}],"scenario":"Вы ведёте 1:0. Настройте компактный средний блок. Объясните страховку, защиту центра и реакцию на перевод мяча.","criteria":{"press":"medium","width":"compact","attack":"balanced","minHigh":1}}'::jsonb);
insert into private.lesson_keys values('defense-1','[1,0]'::jsonb,'{"press":"medium","width":"compact","attack":"balanced","minHigh":1}'::jsonb);
insert into public.assignments values('defense-1-task','defense-1','Вы ведёте 1:0. Настройте компактный средний блок. Объясните страховку, защиту центра и реакцию на перевод мяча.','{"press":"medium","width":"compact","attack":"balanced","minHigh":1}'::jsonb);
insert into public.lessons(id,course_id,position,title,content) values('defense-2','defense',2,'Страховка','{"subtitle":"Второй защитник делает отбор безопасным","theory":"Первый защитник сдерживает, второй страхует под углом и чуть глубже. Плоское расположение открывает путь одним пасом.","example":"Крайний защитник встречает вингера, центральный страхует полуфланг и контролирует рывок за спину.","duration":19,"quiz":[{"prompt":"Где располагается страхующий?","options":["На одной линии вплотную","За воротами","Под углом и глубже"],"correct":2,"explanation":"Под углом и глубже"},{"prompt":"Как перенести принцип в тренировку?","options":["Проверить в игровом упражнении с обратной связью","Только выучить определение","Игнорировать действия партнёров"],"correct":0,"explanation":"Игровое упражнение позволяет увидеть расстояния, решения и взаимодействия."}],"scenario":"Вы ведёте 1:0. Настройте компактный средний блок. Объясните страховку, защиту центра и реакцию на перевод мяча.","criteria":{"press":"medium","width":"compact","attack":"balanced","minHigh":1}}'::jsonb);
insert into private.lesson_keys values('defense-2','[2,0]'::jsonb,'{"press":"medium","width":"compact","attack":"balanced","minHigh":1}'::jsonb);
insert into public.assignments values('defense-2-task','defense-2','Вы ведёте 1:0. Настройте компактный средний блок. Объясните страховку, защиту центра и реакцию на перевод мяча.','{"press":"medium","width":"compact","attack":"balanced","minHigh":1}'::jsonb);
insert into public.lessons(id,course_id,position,title,content) values('defense-3','defense',3,'Защита штрафной','{"subtitle":"Видеть и мяч, и соперника","theory":"При подаче защитники распределяют ближнюю, центральную и дальнюю зоны и контролируют движение нападающих. Опорный защищает подбор у линии штрафной.","example":"Ближний защитник не даёт прострелить, центральные контролируют рывки, дальний закрывает дальнюю штангу.","duration":21,"quiz":[{"prompt":"Кто контролирует подбор?","options":["Только вратарь","Опорный полузащитник","Судья"],"correct":1,"explanation":"Опорный полузащитник"},{"prompt":"Как перенести принцип в тренировку?","options":["Проверить в игровом упражнении с обратной связью","Только выучить определение","Игнорировать действия партнёров"],"correct":0,"explanation":"Игровое упражнение позволяет увидеть расстояния, решения и взаимодействия."}],"scenario":"Вы ведёте 1:0. Настройте компактный средний блок. Объясните страховку, защиту центра и реакцию на перевод мяча.","criteria":{"press":"medium","width":"compact","attack":"balanced","minHigh":1}}'::jsonb);
insert into private.lesson_keys values('defense-3','[1,0]'::jsonb,'{"press":"medium","width":"compact","attack":"balanced","minHigh":1}'::jsonb);
insert into public.assignments values('defense-3-task','defense-3','Вы ведёте 1:0. Настройте компактный средний блок. Объясните страховку, защиту центра и реакцию на перевод мяча.','{"press":"medium","width":"compact","attack":"balanced","minHigh":1}'::jsonb);
insert into public.lessons(id,course_id,position,title,content) values('transitions-1','transitions',1,'Реакция на потерю','{"subtitle":"Оценить возможность вернуть мяч","theory":"Контрпрессинг полезен, если рядом с потерей есть партнёры и закрыт первый пас вперёд. Иначе команда должна быстро восстановить оборонительную структуру.","example":"После потери у угла штрафной ближайшая тройка закрывает мяч, пас внутрь и пас вдоль бровки.","duration":17,"quiz":[{"prompt":"Когда контрпрессинг оправдан?","options":["Всегда без исключений","Есть поддержка и закрыт пас вперёд","Когда рядом только один игрок"],"correct":1,"explanation":"Есть поддержка и закрыт пас вперёд"},{"prompt":"Как перенести принцип в тренировку?","options":["Проверить в игровом упражнении с обратной связью","Только выучить определение","Игнорировать действия партнёров"],"correct":0,"explanation":"Игровое упражнение позволяет увидеть расстояния, решения и взаимодействия."}],"scenario":"Мяч потерян в атаке. Сохраните баланс за мячом и выберите контрпрессинг. Объясните, кто давит, кто страхует и когда нужно отступить.","criteria":{"press":"high","width":"balanced","attack":"direct","minHigh":3}}'::jsonb);
insert into private.lesson_keys values('transitions-1','[1,0]'::jsonb,'{"press":"high","width":"balanced","attack":"direct","minHigh":3}'::jsonb);
insert into public.assignments values('transitions-1-task','transitions-1','Мяч потерян в атаке. Сохраните баланс за мячом и выберите контрпрессинг. Объясните, кто давит, кто страхует и когда нужно отступить.','{"press":"high","width":"balanced","attack":"direct","minHigh":3}'::jsonb);
insert into public.lessons(id,course_id,position,title,content) values('transitions-2','transitions',2,'Атака после отбора','{"subtitle":"Первый взгляд — вперёд","theory":"После отбора оцените пространство за линией соперника. Если вертикальный пас закрыт, сохраните владение и подключите поддержку; форсирование атаки не самоцель.","example":"Опорный перехватывает пас и видит свободный фланг. Вингер ускоряется, форвард фиксирует центрального защитника.","duration":19,"quiz":[{"prompt":"Если быстрый пас закрыт?","options":["Бить вперёд наугад","Сохранить мяч и дождаться поддержки","Остановиться и ждать свистка"],"correct":1,"explanation":"Сохранить мяч и дождаться поддержки"},{"prompt":"Как перенести принцип в тренировку?","options":["Проверить в игровом упражнении с обратной связью","Только выучить определение","Игнорировать действия партнёров"],"correct":0,"explanation":"Игровое упражнение позволяет увидеть расстояния, решения и взаимодействия."}],"scenario":"Мяч потерян в атаке. Сохраните баланс за мячом и выберите контрпрессинг. Объясните, кто давит, кто страхует и когда нужно отступить.","criteria":{"press":"high","width":"balanced","attack":"direct","minHigh":3}}'::jsonb);
insert into private.lesson_keys values('transitions-2','[1,0]'::jsonb,'{"press":"high","width":"balanced","attack":"direct","minHigh":3}'::jsonb);
insert into public.assignments values('transitions-2-task','transitions-2','Мяч потерян в атаке. Сохраните баланс за мячом и выберите контрпрессинг. Объясните, кто давит, кто страхует и когда нужно отступить.','{"press":"high","width":"balanced","attack":"direct","minHigh":3}'::jsonb);
insert into public.lessons(id,course_id,position,title,content) values('transitions-3','transitions',3,'Остаточная оборона','{"subtitle":"Атаковать, сохраняя баланс","theory":"Остаточная оборона — позиции игроков, страхующих команду во время атаки. Контролируйте нападающих соперника и зоны возможного первого паса.","example":"При атаке пятью игроками опорный остаётся перед центральными защитниками и перекрывает вертикальную передачу.","duration":21,"quiz":[{"prompt":"Зачем сохранять баланс?","options":["Чтобы не атаковать","Чтобы задержать контратаку после потери","Чтобы постоянно играть назад"],"correct":1,"explanation":"Чтобы задержать контратаку после потери"},{"prompt":"Как перенести принцип в тренировку?","options":["Проверить в игровом упражнении с обратной связью","Только выучить определение","Игнорировать действия партнёров"],"correct":0,"explanation":"Игровое упражнение позволяет увидеть расстояния, решения и взаимодействия."}],"scenario":"Мяч потерян в атаке. Сохраните баланс за мячом и выберите контрпрессинг. Объясните, кто давит, кто страхует и когда нужно отступить.","criteria":{"press":"high","width":"balanced","attack":"direct","minHigh":3}}'::jsonb);
insert into private.lesson_keys values('transitions-3','[1,0]'::jsonb,'{"press":"high","width":"balanced","attack":"direct","minHigh":3}'::jsonb);
insert into public.assignments values('transitions-3-task','transitions-3','Мяч потерян в атаке. Сохраните баланс за мячом и выберите контрпрессинг. Объясните, кто давит, кто страхует и когда нужно отступить.','{"press":"high","width":"balanced","attack":"direct","minHigh":3}'::jsonb);
insert into public.lessons(id,course_id,position,title,content) values('management-1','management',1,'Недельный микроцикл','{"subtitle":"Нагрузка должна служить игре","theory":"После матча нужны восстановление и анализ; самые интенсивные занятия проводят с запасом до следующего матча. Учитывайте минуты на поле и состояние каждого игрока.","example":"После воскресного матча понедельник посвящён восстановлению, среда — интенсивной игровой работе, суббота — короткой активации.","duration":17,"quiz":[{"prompt":"От чего зависит нагрузка?","options":["От желания наказать команду","От календаря и состояния игрока","Только от возраста"],"correct":1,"explanation":"От календаря и состояния игрока"},{"prompt":"Как перенести принцип в тренировку?","options":["Проверить в игровом упражнении с обратной связью","Только выучить определение","Игнорировать действия партнёров"],"correct":0,"explanation":"Игровое упражнение позволяет увидеть расстояния, решения и взаимодействия."}],"scenario":"Вы проигрываете 0:2 к 60-й минуте против 5-4-1. Добавьте ширину, спланируйте замену и сохраните страховку. Объясните план возвращения в матч.","criteria":{"press":"high","width":"wide","attack":"balanced","minHigh":3,"substitution":true}}'::jsonb);
insert into private.lesson_keys values('management-1','[1,0]'::jsonb,'{"press":"high","width":"wide","attack":"balanced","minHigh":3,"substitution":true}'::jsonb);
insert into public.assignments values('management-1-task','management-1','Вы проигрываете 0:2 к 60-й минуте против 5-4-1. Добавьте ширину, спланируйте замену и сохраните страховку. Объясните план возвращения в матч.','{"press":"high","width":"wide","attack":"balanced","minHigh":3,"substitution":true}'::jsonb);
insert into public.lessons(id,course_id,position,title,content) values('management-2','management',2,'План на матч','{"subtitle":"Подготовить решения, а не обещания","theory":"Выберите наблюдаемые особенности соперника, определите приоритеты и сигналы для изменения плана. Формулируйте игрокам несколько ясных принципов.","example":"Против низкого 5-4-1 растяните линию шириной, создайте перегруз на фланге и подготовьте страховку на случай потери.","duration":19,"quiz":[{"prompt":"Что должно быть в плане?","options":["Только стартовый состав","Приоритеты и условия корректировки","Гарантия победы"],"correct":1,"explanation":"Приоритеты и условия корректировки"},{"prompt":"Как перенести принцип в тренировку?","options":["Проверить в игровом упражнении с обратной связью","Только выучить определение","Игнорировать действия партнёров"],"correct":0,"explanation":"Игровое упражнение позволяет увидеть расстояния, решения и взаимодействия."}],"scenario":"Вы проигрываете 0:2 к 60-й минуте против 5-4-1. Добавьте ширину, спланируйте замену и сохраните страховку. Объясните план возвращения в матч.","criteria":{"press":"high","width":"wide","attack":"balanced","minHigh":3,"substitution":true}}'::jsonb);
insert into private.lesson_keys values('management-2','[1,0]'::jsonb,'{"press":"high","width":"wide","attack":"balanced","minHigh":3,"substitution":true}'::jsonb);
insert into public.assignments values('management-2-task','management-2','Вы проигрываете 0:2 к 60-й минуте против 5-4-1. Добавьте ширину, спланируйте замену и сохраните страховку. Объясните план возвращения в матч.','{"press":"high","width":"wide","attack":"balanced","minHigh":3,"substitution":true}'::jsonb);
insert into public.lessons(id,course_id,position,title,content) values('management-3','management',3,'Замены и коммуникация','{"subtitle":"Менять роль осознанно","theory":"Замена должна решать конкретную задачу: добавить ширину, улучшить контроль центра или снизить риск из-за усталости. Объясните новую роль игроку и партнёрам.","example":"На 60-й минуте при 0:2 выпустите свежего вингера, сохраните опорного и договоритесь, кто страхует подключение защитника.","duration":21,"quiz":[{"prompt":"Как обосновать замену?","options":["Только эмоциями","Назвать задачу и изменение роли","Случайным выбором"],"correct":1,"explanation":"Назвать задачу и изменение роли"},{"prompt":"Как перенести принцип в тренировку?","options":["Проверить в игровом упражнении с обратной связью","Только выучить определение","Игнорировать действия партнёров"],"correct":0,"explanation":"Игровое упражнение позволяет увидеть расстояния, решения и взаимодействия."}],"scenario":"Вы проигрываете 0:2 к 60-й минуте против 5-4-1. Добавьте ширину, спланируйте замену и сохраните страховку. Объясните план возвращения в матч.","criteria":{"press":"high","width":"wide","attack":"balanced","minHigh":3,"substitution":true}}'::jsonb);
insert into private.lesson_keys values('management-3','[1,0]'::jsonb,'{"press":"high","width":"wide","attack":"balanced","minHigh":3,"substitution":true}'::jsonb);
insert into public.assignments values('management-3-task','management-3','Вы проигрываете 0:2 к 60-й минуте против 5-4-1. Добавьте ширину, спланируйте замену и сохраните страховку. Объясните план возвращения в матч.','{"press":"high","width":"wide","attack":"balanced","minHigh":3,"substitution":true}'::jsonb);
insert into public.exams(id,title) values('D','Лицензия D · официальный экзамен');
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('D',1,'theory','При пасе к бровке что делает дальний вингер?','["Остаётся у бровки","Сужает позицию, сохраняя контроль перевода","Стоит у ворот соперника"]'::jsonb) returning id) insert into private.exam_keys select id,1 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('D',2,'theory','Пасующий не находится под давлением. Как защитить глубину?','["Игнорировать рывки","Контролировать забегания и дать глубину","Поднять линию любой ценой"]'::jsonb) returning id) insert into private.exam_keys select id,1 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('D',3,'theory','Какой триггер подходит для прессинга?','["Мяч у судьи","Плохой приём соперника","Наш защитник травмирован"]'::jsonb) returning id) insert into private.exam_keys select id,1 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('D',4,'theory','После провала первой линии давления нужно…','["Продолжить одиночные рывки","Восстановить компактный блок","Всем идти на мяч"]'::jsonb) returning id) insert into private.exam_keys select id,1 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('D',5,'theory','Два форварда прессингуют двух центральных защитников. Кто создаёт перевес?','["Вратарь","Никто","Арбитр"]'::jsonb) returning id) insert into private.exam_keys select id,0 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('D',6,'theory','Игра через третьего позволяет…','["Не двигаться без мяча","Выйти за линию давления лицом вперёд","Избежать любых потерь"]'::jsonb) returning id) insert into private.exam_keys select id,1 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('D',7,'theory','Когда перевод мяча полезен?','["Когда дальний фланг свободен","Когда все закрыты","Только в начале матча"]'::jsonb) returning id) insert into private.exam_keys select id,0 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('D',8,'theory','При персональной опеке опорного эффективнее…','["Менять линию открывания и использовать третьего","Ждать на месте","Прятаться за форвардом"]'::jsonb) returning id) insert into private.exam_keys select id,0 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('D',9,'theory','Главный приоритет среднего блока?','["Только бровка","Защита центра и межлинейного пространства","Преследование вратаря"]'::jsonb) returning id) insert into private.exam_keys select id,1 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('D',10,'theory','Страхующий защитник располагается…','["Под углом и глубже","Вплотную на одной линии","За лицевой"]'::jsonb) returning id) insert into private.exam_keys select id,0 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('D',11,'theory','Кто контролирует подбор у штрафной?','["Только вратарь","Нападающий в офсайде","Опорный полузащитник"]'::jsonb) returning id) insert into private.exam_keys select id,2 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('D',12,'theory','Дальний защитник при атаке с противоположного фланга…','["Выключается","Сужается и контролирует дальнюю штангу","Стоит у бровки без контроля"]'::jsonb) returning id) insert into private.exam_keys select id,1 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('D',13,'theory','Контрпрессинг оправдан, если…','["Рядом есть поддержка и перекрыт первый пас","Вся команда впереди мяча без страховки","Соперник уже убежал"]'::jsonb) returning id) insert into private.exam_keys select id,0 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('D',14,'theory','После отбора первый взгляд направлен…','["Только назад","На скамейку","Вперёд, с оценкой риска"]'::jsonb) returning id) insert into private.exam_keys select id,2 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('D',15,'theory','Если вертикальный пас после отбора закрыт…','["Бить наугад","Сохранить владение","Отдать мяч сопернику"]'::jsonb) returning id) insert into private.exam_keys select id,1 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('D',16,'theory','Остаточная оборона нужна для…','["Контроля возможной контратаки","Отказа от атаки","Постоянного офсайда"]'::jsonb) returning id) insert into private.exam_keys select id,0 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('D',17,'theory','Интенсивность микроцикла зависит от…','["Только погоды","Желания наказать","Календаря, минут и состояния игроков"]'::jsonb) returning id) insert into private.exam_keys select id,2 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('D',18,'theory','Замена должна…','["Менять только номер","Решать задачу с ясной ролью","Быть случайной"]'::jsonb) returning id) insert into private.exam_keys select id,1 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('D',19,'theory','Против низкого 5-4-1 полезно…','["Использовать ширину и страховку","Играть только в перегруженный центр","Убрать всех защитников"]'::jsonb) returning id) insert into private.exam_keys select id,0 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('D',20,'theory','Качественный план матча содержит…','["Обещание победы","Только фамилии","Приоритеты и сигналы корректировки"]'::jsonb) returning id) insert into private.exam_keys select id,2 from q;
insert into public.exam_questions(exam_id,position,kind,prompt,rubric) values('D',21,'practice','[Уровень D] Вы проигрываете 0:2 к 60-й минуте против 5-4-1. Предложите план атаки, замен и защиты от контратак. ','["Диагноз структуры соперника","Ширина и создание моментов","Замены и роли","Страховка и критерий изменения плана"]'::jsonb);
insert into public.exam_questions(exam_id,position,kind,prompt,rubric) values('D',22,'practice','[Уровень D] Ваша команда 4-2-3-1 не может выйти из-под прессинга двух форвардов. Опишите перестроение и действия при потере. ','["Определение свободного игрока","Углы и последовательность передач","Движение без мяча","Баланс и реакция на потерю"]'::jsonb);
insert into public.exam_questions(exam_id,position,kind,prompt,rubric) values('D',23,'practice','[Уровень D] Команда ведёт 1:0 за 15 минут до конца. Соперник усилил фланги. Опишите оборону, замены и способы сохранить угрозу впереди. ','["Защита фланга и страховка","Компактность и контроль центра","Замены с обоснованием","Выход из обороны и управление риском"]'::jsonb);
insert into public.exams(id,title) values('C','Лицензия C · официальный экзамен');
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('C',1,'theory','Два форварда прессингуют двух центральных защитников. Кто создаёт перевес?','["Вратарь","Никто","Арбитр"]'::jsonb) returning id) insert into private.exam_keys select id,0 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('C',2,'theory','Игра через третьего позволяет…','["Не двигаться без мяча","Выйти за линию давления лицом вперёд","Избежать любых потерь"]'::jsonb) returning id) insert into private.exam_keys select id,1 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('C',3,'theory','Когда перевод мяча полезен?','["Когда дальний фланг свободен","Когда все закрыты","Только в начале матча"]'::jsonb) returning id) insert into private.exam_keys select id,0 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('C',4,'theory','При персональной опеке опорного эффективнее…','["Менять линию открывания и использовать третьего","Ждать на месте","Прятаться за форвардом"]'::jsonb) returning id) insert into private.exam_keys select id,0 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('C',5,'theory','Главный приоритет среднего блока?','["Только бровка","Защита центра и межлинейного пространства","Преследование вратаря"]'::jsonb) returning id) insert into private.exam_keys select id,1 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('C',6,'theory','Страхующий защитник располагается…','["Под углом и глубже","Вплотную на одной линии","За лицевой"]'::jsonb) returning id) insert into private.exam_keys select id,0 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('C',7,'theory','Кто контролирует подбор у штрафной?','["Только вратарь","Нападающий в офсайде","Опорный полузащитник"]'::jsonb) returning id) insert into private.exam_keys select id,2 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('C',8,'theory','Дальний защитник при атаке с противоположного фланга…','["Выключается","Сужается и контролирует дальнюю штангу","Стоит у бровки без контроля"]'::jsonb) returning id) insert into private.exam_keys select id,1 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('C',9,'theory','Контрпрессинг оправдан, если…','["Рядом есть поддержка и перекрыт первый пас","Вся команда впереди мяча без страховки","Соперник уже убежал"]'::jsonb) returning id) insert into private.exam_keys select id,0 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('C',10,'theory','После отбора первый взгляд направлен…','["Только назад","На скамейку","Вперёд, с оценкой риска"]'::jsonb) returning id) insert into private.exam_keys select id,2 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('C',11,'theory','Если вертикальный пас после отбора закрыт…','["Бить наугад","Сохранить владение","Отдать мяч сопернику"]'::jsonb) returning id) insert into private.exam_keys select id,1 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('C',12,'theory','Остаточная оборона нужна для…','["Контроля возможной контратаки","Отказа от атаки","Постоянного офсайда"]'::jsonb) returning id) insert into private.exam_keys select id,0 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('C',13,'theory','Интенсивность микроцикла зависит от…','["Только погоды","Желания наказать","Календаря, минут и состояния игроков"]'::jsonb) returning id) insert into private.exam_keys select id,2 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('C',14,'theory','Замена должна…','["Менять только номер","Решать задачу с ясной ролью","Быть случайной"]'::jsonb) returning id) insert into private.exam_keys select id,1 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('C',15,'theory','Против низкого 5-4-1 полезно…','["Использовать ширину и страховку","Играть только в перегруженный центр","Убрать всех защитников"]'::jsonb) returning id) insert into private.exam_keys select id,0 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('C',16,'theory','Качественный план матча содержит…','["Обещание победы","Только фамилии","Приоритеты и сигналы корректировки"]'::jsonb) returning id) insert into private.exam_keys select id,2 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('C',17,'theory','При пасе к бровке что делает дальний вингер?','["Стоит у ворот соперника","Остаётся у бровки","Сужает позицию, сохраняя контроль перевода"]'::jsonb) returning id) insert into private.exam_keys select id,2 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('C',18,'theory','Пасующий не находится под давлением. Как защитить глубину?','["Поднять линию любой ценой","Игнорировать рывки","Контролировать забегания и дать глубину"]'::jsonb) returning id) insert into private.exam_keys select id,2 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('C',19,'theory','Какой триггер подходит для прессинга?','["Наш защитник травмирован","Мяч у судьи","Плохой приём соперника"]'::jsonb) returning id) insert into private.exam_keys select id,2 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('C',20,'theory','После провала первой линии давления нужно…','["Всем идти на мяч","Продолжить одиночные рывки","Восстановить компактный блок"]'::jsonb) returning id) insert into private.exam_keys select id,2 from q;
insert into public.exam_questions(exam_id,position,kind,prompt,rubric) values('C',21,'practice','[Уровень C] Вы проигрываете 0:2 к 60-й минуте против 5-4-1. Предложите план атаки, замен и защиты от контратак. ','["Диагноз структуры соперника","Ширина и создание моментов","Замены и роли","Страховка и критерий изменения плана"]'::jsonb);
insert into public.exam_questions(exam_id,position,kind,prompt,rubric) values('C',22,'practice','[Уровень C] Ваша команда 4-2-3-1 не может выйти из-под прессинга двух форвардов. Опишите перестроение и действия при потере. ','["Определение свободного игрока","Углы и последовательность передач","Движение без мяча","Баланс и реакция на потерю"]'::jsonb);
insert into public.exam_questions(exam_id,position,kind,prompt,rubric) values('C',23,'practice','[Уровень C] Команда ведёт 1:0 за 15 минут до конца. Соперник усилил фланги. Опишите оборону, замены и способы сохранить угрозу впереди. ','["Защита фланга и страховка","Компактность и контроль центра","Замены с обоснованием","Выход из обороны и управление риском"]'::jsonb);
insert into public.exams(id,title) values('B','Лицензия B · официальный экзамен');
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('B',1,'theory','Главный приоритет среднего блока?','["Только бровка","Защита центра и межлинейного пространства","Преследование вратаря"]'::jsonb) returning id) insert into private.exam_keys select id,1 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('B',2,'theory','Страхующий защитник располагается…','["Под углом и глубже","Вплотную на одной линии","За лицевой"]'::jsonb) returning id) insert into private.exam_keys select id,0 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('B',3,'theory','Кто контролирует подбор у штрафной?','["Только вратарь","Нападающий в офсайде","Опорный полузащитник"]'::jsonb) returning id) insert into private.exam_keys select id,2 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('B',4,'theory','Дальний защитник при атаке с противоположного фланга…','["Выключается","Сужается и контролирует дальнюю штангу","Стоит у бровки без контроля"]'::jsonb) returning id) insert into private.exam_keys select id,1 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('B',5,'theory','Контрпрессинг оправдан, если…','["Рядом есть поддержка и перекрыт первый пас","Вся команда впереди мяча без страховки","Соперник уже убежал"]'::jsonb) returning id) insert into private.exam_keys select id,0 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('B',6,'theory','После отбора первый взгляд направлен…','["Только назад","На скамейку","Вперёд, с оценкой риска"]'::jsonb) returning id) insert into private.exam_keys select id,2 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('B',7,'theory','Если вертикальный пас после отбора закрыт…','["Бить наугад","Сохранить владение","Отдать мяч сопернику"]'::jsonb) returning id) insert into private.exam_keys select id,1 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('B',8,'theory','Остаточная оборона нужна для…','["Контроля возможной контратаки","Отказа от атаки","Постоянного офсайда"]'::jsonb) returning id) insert into private.exam_keys select id,0 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('B',9,'theory','Интенсивность микроцикла зависит от…','["Только погоды","Желания наказать","Календаря, минут и состояния игроков"]'::jsonb) returning id) insert into private.exam_keys select id,2 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('B',10,'theory','Замена должна…','["Менять только номер","Решать задачу с ясной ролью","Быть случайной"]'::jsonb) returning id) insert into private.exam_keys select id,1 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('B',11,'theory','Против низкого 5-4-1 полезно…','["Использовать ширину и страховку","Играть только в перегруженный центр","Убрать всех защитников"]'::jsonb) returning id) insert into private.exam_keys select id,0 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('B',12,'theory','Качественный план матча содержит…','["Обещание победы","Только фамилии","Приоритеты и сигналы корректировки"]'::jsonb) returning id) insert into private.exam_keys select id,2 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('B',13,'theory','При пасе к бровке что делает дальний вингер?','["Стоит у ворот соперника","Остаётся у бровки","Сужает позицию, сохраняя контроль перевода"]'::jsonb) returning id) insert into private.exam_keys select id,2 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('B',14,'theory','Пасующий не находится под давлением. Как защитить глубину?','["Поднять линию любой ценой","Игнорировать рывки","Контролировать забегания и дать глубину"]'::jsonb) returning id) insert into private.exam_keys select id,2 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('B',15,'theory','Какой триггер подходит для прессинга?','["Наш защитник травмирован","Мяч у судьи","Плохой приём соперника"]'::jsonb) returning id) insert into private.exam_keys select id,2 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('B',16,'theory','После провала первой линии давления нужно…','["Всем идти на мяч","Продолжить одиночные рывки","Восстановить компактный блок"]'::jsonb) returning id) insert into private.exam_keys select id,2 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('B',17,'theory','Два форварда прессингуют двух центральных защитников. Кто создаёт перевес?','["Арбитр","Вратарь","Никто"]'::jsonb) returning id) insert into private.exam_keys select id,1 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('B',18,'theory','Игра через третьего позволяет…','["Избежать любых потерь","Не двигаться без мяча","Выйти за линию давления лицом вперёд"]'::jsonb) returning id) insert into private.exam_keys select id,2 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('B',19,'theory','Когда перевод мяча полезен?','["Только в начале матча","Когда дальний фланг свободен","Когда все закрыты"]'::jsonb) returning id) insert into private.exam_keys select id,1 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('B',20,'theory','При персональной опеке опорного эффективнее…','["Прятаться за форвардом","Менять линию открывания и использовать третьего","Ждать на месте"]'::jsonb) returning id) insert into private.exam_keys select id,1 from q;
insert into public.exam_questions(exam_id,position,kind,prompt,rubric) values('B',21,'practice','[Уровень B] Вы проигрываете 0:2 к 60-й минуте против 5-4-1. Предложите план атаки, замен и защиты от контратак. Включите альтернативный план, наблюдаемые показатели и тренировочное упражнение.','["Диагноз структуры соперника","Ширина и создание моментов","Замены и роли","Страховка и критерий изменения плана"]'::jsonb);
insert into public.exam_questions(exam_id,position,kind,prompt,rubric) values('B',22,'practice','[Уровень B] Ваша команда 4-2-3-1 не может выйти из-под прессинга двух форвардов. Опишите перестроение и действия при потере. Включите альтернативный план, наблюдаемые показатели и тренировочное упражнение.','["Определение свободного игрока","Углы и последовательность передач","Движение без мяча","Баланс и реакция на потерю"]'::jsonb);
insert into public.exam_questions(exam_id,position,kind,prompt,rubric) values('B',23,'practice','[Уровень B] Команда ведёт 1:0 за 15 минут до конца. Соперник усилил фланги. Опишите оборону, замены и способы сохранить угрозу впереди. Включите альтернативный план, наблюдаемые показатели и тренировочное упражнение.','["Защита фланга и страховка","Компактность и контроль центра","Замены с обоснованием","Выход из обороны и управление риском"]'::jsonb);
insert into public.exams(id,title) values('A','Лицензия A · официальный экзамен');
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('A',1,'theory','Контрпрессинг оправдан, если…','["Рядом есть поддержка и перекрыт первый пас","Вся команда впереди мяча без страховки","Соперник уже убежал"]'::jsonb) returning id) insert into private.exam_keys select id,0 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('A',2,'theory','После отбора первый взгляд направлен…','["Только назад","На скамейку","Вперёд, с оценкой риска"]'::jsonb) returning id) insert into private.exam_keys select id,2 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('A',3,'theory','Если вертикальный пас после отбора закрыт…','["Бить наугад","Сохранить владение","Отдать мяч сопернику"]'::jsonb) returning id) insert into private.exam_keys select id,1 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('A',4,'theory','Остаточная оборона нужна для…','["Контроля возможной контратаки","Отказа от атаки","Постоянного офсайда"]'::jsonb) returning id) insert into private.exam_keys select id,0 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('A',5,'theory','Интенсивность микроцикла зависит от…','["Только погоды","Желания наказать","Календаря, минут и состояния игроков"]'::jsonb) returning id) insert into private.exam_keys select id,2 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('A',6,'theory','Замена должна…','["Менять только номер","Решать задачу с ясной ролью","Быть случайной"]'::jsonb) returning id) insert into private.exam_keys select id,1 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('A',7,'theory','Против низкого 5-4-1 полезно…','["Использовать ширину и страховку","Играть только в перегруженный центр","Убрать всех защитников"]'::jsonb) returning id) insert into private.exam_keys select id,0 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('A',8,'theory','Качественный план матча содержит…','["Обещание победы","Только фамилии","Приоритеты и сигналы корректировки"]'::jsonb) returning id) insert into private.exam_keys select id,2 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('A',9,'theory','При пасе к бровке что делает дальний вингер?','["Стоит у ворот соперника","Остаётся у бровки","Сужает позицию, сохраняя контроль перевода"]'::jsonb) returning id) insert into private.exam_keys select id,2 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('A',10,'theory','Пасующий не находится под давлением. Как защитить глубину?','["Поднять линию любой ценой","Игнорировать рывки","Контролировать забегания и дать глубину"]'::jsonb) returning id) insert into private.exam_keys select id,2 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('A',11,'theory','Какой триггер подходит для прессинга?','["Наш защитник травмирован","Мяч у судьи","Плохой приём соперника"]'::jsonb) returning id) insert into private.exam_keys select id,2 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('A',12,'theory','После провала первой линии давления нужно…','["Всем идти на мяч","Продолжить одиночные рывки","Восстановить компактный блок"]'::jsonb) returning id) insert into private.exam_keys select id,2 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('A',13,'theory','Два форварда прессингуют двух центральных защитников. Кто создаёт перевес?','["Арбитр","Вратарь","Никто"]'::jsonb) returning id) insert into private.exam_keys select id,1 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('A',14,'theory','Игра через третьего позволяет…','["Избежать любых потерь","Не двигаться без мяча","Выйти за линию давления лицом вперёд"]'::jsonb) returning id) insert into private.exam_keys select id,2 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('A',15,'theory','Когда перевод мяча полезен?','["Только в начале матча","Когда дальний фланг свободен","Когда все закрыты"]'::jsonb) returning id) insert into private.exam_keys select id,1 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('A',16,'theory','При персональной опеке опорного эффективнее…','["Прятаться за форвардом","Менять линию открывания и использовать третьего","Ждать на месте"]'::jsonb) returning id) insert into private.exam_keys select id,1 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('A',17,'theory','Главный приоритет среднего блока?','["Преследование вратаря","Только бровка","Защита центра и межлинейного пространства"]'::jsonb) returning id) insert into private.exam_keys select id,2 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('A',18,'theory','Страхующий защитник располагается…','["За лицевой","Под углом и глубже","Вплотную на одной линии"]'::jsonb) returning id) insert into private.exam_keys select id,1 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('A',19,'theory','Кто контролирует подбор у штрафной?','["Опорный полузащитник","Только вратарь","Нападающий в офсайде"]'::jsonb) returning id) insert into private.exam_keys select id,0 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('A',20,'theory','Дальний защитник при атаке с противоположного фланга…','["Стоит у бровки без контроля","Выключается","Сужается и контролирует дальнюю штангу"]'::jsonb) returning id) insert into private.exam_keys select id,2 from q;
insert into public.exam_questions(exam_id,position,kind,prompt,rubric) values('A',21,'practice','[Уровень A] Вы проигрываете 0:2 к 60-й минуте против 5-4-1. Предложите план атаки, замен и защиты от контратак. Включите альтернативный план, наблюдаемые показатели и тренировочное упражнение.','["Диагноз структуры соперника","Ширина и создание моментов","Замены и роли","Страховка и критерий изменения плана"]'::jsonb);
insert into public.exam_questions(exam_id,position,kind,prompt,rubric) values('A',22,'practice','[Уровень A] Ваша команда 4-2-3-1 не может выйти из-под прессинга двух форвардов. Опишите перестроение и действия при потере. Включите альтернативный план, наблюдаемые показатели и тренировочное упражнение.','["Определение свободного игрока","Углы и последовательность передач","Движение без мяча","Баланс и реакция на потерю"]'::jsonb);
insert into public.exam_questions(exam_id,position,kind,prompt,rubric) values('A',23,'practice','[Уровень A] Команда ведёт 1:0 за 15 минут до конца. Соперник усилил фланги. Опишите оборону, замены и способы сохранить угрозу впереди. Включите альтернативный план, наблюдаемые показатели и тренировочное упражнение.','["Защита фланга и страховка","Компактность и контроль центра","Замены с обоснованием","Выход из обороны и управление риском"]'::jsonb);
insert into public.exams(id,title) values('Pro','Лицензия Pro · официальный экзамен');
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('Pro',1,'theory','Интенсивность микроцикла зависит от…','["Только погоды","Желания наказать","Календаря, минут и состояния игроков"]'::jsonb) returning id) insert into private.exam_keys select id,2 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('Pro',2,'theory','Замена должна…','["Менять только номер","Решать задачу с ясной ролью","Быть случайной"]'::jsonb) returning id) insert into private.exam_keys select id,1 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('Pro',3,'theory','Против низкого 5-4-1 полезно…','["Использовать ширину и страховку","Играть только в перегруженный центр","Убрать всех защитников"]'::jsonb) returning id) insert into private.exam_keys select id,0 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('Pro',4,'theory','Качественный план матча содержит…','["Обещание победы","Только фамилии","Приоритеты и сигналы корректировки"]'::jsonb) returning id) insert into private.exam_keys select id,2 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('Pro',5,'theory','При пасе к бровке что делает дальний вингер?','["Стоит у ворот соперника","Остаётся у бровки","Сужает позицию, сохраняя контроль перевода"]'::jsonb) returning id) insert into private.exam_keys select id,2 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('Pro',6,'theory','Пасующий не находится под давлением. Как защитить глубину?','["Поднять линию любой ценой","Игнорировать рывки","Контролировать забегания и дать глубину"]'::jsonb) returning id) insert into private.exam_keys select id,2 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('Pro',7,'theory','Какой триггер подходит для прессинга?','["Наш защитник травмирован","Мяч у судьи","Плохой приём соперника"]'::jsonb) returning id) insert into private.exam_keys select id,2 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('Pro',8,'theory','После провала первой линии давления нужно…','["Всем идти на мяч","Продолжить одиночные рывки","Восстановить компактный блок"]'::jsonb) returning id) insert into private.exam_keys select id,2 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('Pro',9,'theory','Два форварда прессингуют двух центральных защитников. Кто создаёт перевес?','["Арбитр","Вратарь","Никто"]'::jsonb) returning id) insert into private.exam_keys select id,1 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('Pro',10,'theory','Игра через третьего позволяет…','["Избежать любых потерь","Не двигаться без мяча","Выйти за линию давления лицом вперёд"]'::jsonb) returning id) insert into private.exam_keys select id,2 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('Pro',11,'theory','Когда перевод мяча полезен?','["Только в начале матча","Когда дальний фланг свободен","Когда все закрыты"]'::jsonb) returning id) insert into private.exam_keys select id,1 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('Pro',12,'theory','При персональной опеке опорного эффективнее…','["Прятаться за форвардом","Менять линию открывания и использовать третьего","Ждать на месте"]'::jsonb) returning id) insert into private.exam_keys select id,1 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('Pro',13,'theory','Главный приоритет среднего блока?','["Преследование вратаря","Только бровка","Защита центра и межлинейного пространства"]'::jsonb) returning id) insert into private.exam_keys select id,2 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('Pro',14,'theory','Страхующий защитник располагается…','["За лицевой","Под углом и глубже","Вплотную на одной линии"]'::jsonb) returning id) insert into private.exam_keys select id,1 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('Pro',15,'theory','Кто контролирует подбор у штрафной?','["Опорный полузащитник","Только вратарь","Нападающий в офсайде"]'::jsonb) returning id) insert into private.exam_keys select id,0 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('Pro',16,'theory','Дальний защитник при атаке с противоположного фланга…','["Стоит у бровки без контроля","Выключается","Сужается и контролирует дальнюю штангу"]'::jsonb) returning id) insert into private.exam_keys select id,2 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('Pro',17,'theory','Контрпрессинг оправдан, если…','["Соперник уже убежал","Рядом есть поддержка и перекрыт первый пас","Вся команда впереди мяча без страховки"]'::jsonb) returning id) insert into private.exam_keys select id,1 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('Pro',18,'theory','После отбора первый взгляд направлен…','["Вперёд, с оценкой риска","Только назад","На скамейку"]'::jsonb) returning id) insert into private.exam_keys select id,0 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('Pro',19,'theory','Если вертикальный пас после отбора закрыт…','["Отдать мяч сопернику","Бить наугад","Сохранить владение"]'::jsonb) returning id) insert into private.exam_keys select id,2 from q;
with q as (insert into public.exam_questions(exam_id,position,kind,prompt,options) values('Pro',20,'theory','Остаточная оборона нужна для…','["Постоянного офсайда","Контроля возможной контратаки","Отказа от атаки"]'::jsonb) returning id) insert into private.exam_keys select id,1 from q;
insert into public.exam_questions(exam_id,position,kind,prompt,rubric) values('Pro',21,'practice','[Уровень Pro] Вы проигрываете 0:2 к 60-й минуте против 5-4-1. Предложите план атаки, замен и защиты от контратак. Включите альтернативный план, наблюдаемые показатели и тренировочное упражнение.','["Диагноз структуры соперника","Ширина и создание моментов","Замены и роли","Страховка и критерий изменения плана"]'::jsonb);
insert into public.exam_questions(exam_id,position,kind,prompt,rubric) values('Pro',22,'practice','[Уровень Pro] Ваша команда 4-2-3-1 не может выйти из-под прессинга двух форвардов. Опишите перестроение и действия при потере. Включите альтернативный план, наблюдаемые показатели и тренировочное упражнение.','["Определение свободного игрока","Углы и последовательность передач","Движение без мяча","Баланс и реакция на потерю"]'::jsonb);
insert into public.exam_questions(exam_id,position,kind,prompt,rubric) values('Pro',23,'practice','[Уровень Pro] Команда ведёт 1:0 за 15 минут до конца. Соперник усилил фланги. Опишите оборону, замены и способы сохранить угрозу впереди. Включите альтернативный план, наблюдаемые показатели и тренировочное упражнение.','["Защита фланга и страховка","Компактность и контроль центра","Замены с обоснованием","Выход из обороны и управление риском"]'::jsonb);


COMMIT;

-- Expected: courses = 5, lessons = 19, exam_questions = 115.
SELECT
  (SELECT count(*) FROM public.courses) AS courses,
  (SELECT count(*) FROM public.lessons) AS lessons,
  (SELECT count(*) FROM public.exam_questions) AS exam_questions;

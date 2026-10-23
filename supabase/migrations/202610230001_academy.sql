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

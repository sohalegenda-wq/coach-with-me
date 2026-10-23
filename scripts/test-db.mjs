import pg from 'pg';
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
import { lessons } from '../src/catalog.js';
// Destructive reset is allowed ONLY on this throwaway local database, never a hosted project.
const url=process.env.CWM_TEST_DATABASE_URL||'postgresql://postgres:cwm-local-only@127.0.0.1:55432/postgres';
const parsed=new URL(url);
if(!['127.0.0.1','localhost'].includes(parsed.hostname)||parsed.port!=='55432')throw new Error('Tests require a disposable local PostgreSQL database on port 55432');
const client=new pg.Client({connectionString:url});await client.connect();
let count=0;
async function test(name,fn){await fn();count++;console.log(`✓ ${name}`);}
const student='10000000-0000-4000-8000-000000000001',other='10000000-0000-4000-8000-000000000002',admin='10000000-0000-4000-8000-000000000003';
async function as(user){await client.query('reset role');await client.query("select set_config('request.jwt.claim.sub',$1,false)",[user||'']);await client.query(`set role ${user?'authenticated':'anon'}`);}
async function rpc(action,payload={}){return (await client.query('select public.academy($1,$2::jsonb) as result',[action,JSON.stringify(payload)])).rows[0].result;}
async function denied(fn,pattern){await assert.rejects(fn,pattern);}
try{
 await client.query('drop schema public cascade; drop schema if exists private cascade; drop schema if exists auth cascade; create schema public; grant usage on schema public to public;');
 const roles=await client.query("select rolname from pg_roles where rolname in ('anon','authenticated')");
 for(const {rolname} of roles.rows)await client.query(`drop role ${rolname}`);
 await client.query(readFileSync(new URL('../tests/auth-shim.sql',import.meta.url),'utf8'));
 if(process.env.CWM_TEST_LEGACY==='1') {
  await client.query(readFileSync(new URL('../tests/legacy-profiles.sql',import.meta.url),'utf8'));
  const upgrade=readFileSync(new URL('../supabase/upgrade-legacy-profiles.sql',import.meta.url),'utf8');
  const before=(await client.query('select * from public.profiles')).rows;
  await test('ambiguous legacy Auth trigger aborts upgrade without modifying profiles',async()=>{
   await client.query(`create function public.ambiguous_profile_trigger() returns trigger language plpgsql as $$ begin perform 1; insert into public.profiles(id,username) values(new.id,'ambiguous'); return new; end; $$;
    create trigger ambiguous_profile after insert on auth.users for each row execute function public.ambiguous_profile_trigger();`);
   await denied(()=>client.query(upgrade),/дополнительную логику/);
   await client.query('rollback');
   assert.deepEqual((await client.query('select * from public.profiles')).rows,before);
   assert.equal((await client.query("select to_regclass('private.cwm_legacy_profiles_backup') as archive")).rows[0].archive,null);
   await client.query('drop trigger ambiguous_profile on auth.users; drop function public.ambiguous_profile_trigger()');
  });
  await client.query(upgrade);
  await test('legacy rows, names and timestamps preserved with a private original backup',async()=>{
   assert.deepEqual((await client.query('select * from private.cwm_legacy_profiles_backup')).rows,before);
   const p=(await client.query('select * from public.profiles where id=$1',[before[0].id])).rows[0];
   for(const key of ['id','username','display_name','license','created_at'])assert.deepEqual(p[key],before[0][key]);
   assert.equal(p.nickname,'Старый тренер');
   const oldName=(await client.query("select username, nickname from public.profiles where id='10000000-0000-4000-8000-000000000006'")).rows[0];
   assert.deepEqual(oldName,{username:'Old Coach/Тренер',nickname:'Имя из старой версии'});
   assert.equal((await client.query("select username from public.profiles where id='10000000-0000-4000-8000-000000000005'")).rows[0].username,'legacy_2');
   assert.equal((await client.query('select * from public.user_licenses')).rows.length,0);
  });
  await test('legacy public policies and column update grants are removed',async()=>{
   await as(null);await denied(()=>client.query('select username from public.profiles'),/permission denied/);
   await as(before[0].id);
   assert.equal((await client.query('select * from public.profiles')).rows.length,1);
   await denied(()=>client.query("update public.profiles set license='Pro'"),/permission denied/);
   await denied(()=>client.query('select * from private.cwm_legacy_profiles_backup'),/permission denied/);
   await rpc('profile',{nickname:'Обновлённый тренер',bio:'',club:'',avatar:'⚽'});
   await client.query('reset role');
  });
  await test('legacy upgrade is one-time and repeated execution rolls back safely',async()=>{
   await denied(()=>client.query(upgrade),/Структура profiles отличается/);await client.query('rollback');
   assert.equal((await client.query('select count(*)::integer as n from public.courses')).rows[0].n,5);
  });
 } else {
  await client.query(readFileSync(new URL('../supabase/migrations/202610230001_academy.sql',import.meta.url),'utf8'));
  await client.query(readFileSync(new URL('../supabase/migrations/202610230002_content.sql',import.meta.url),'utf8'));
 }
 console.log('Schema and content migrations applied successfully');
 for(const [id,username] of [[student,'student_one'],[other,'student_two'],[admin,'admin_coach']])await client.query('insert into auth.users values($1,$2,$3)',[id,username+'@example.test',JSON.stringify({username,nickname:username})]);
 if(process.env.CWM_TEST_LEGACY==='1')await test('new signup uses one Auth trigger and never grants a legacy license',async()=>{
  const p=(await client.query('select * from public.profiles where id=$1',[student])).rows[0];
  assert.equal(p.nickname,'student_one');assert.equal(p.license,null);
  await denied(()=>client.query('insert into auth.users values($1,$2,$3)',['10000000-0000-4000-8000-000000000099','invalid@example.test',JSON.stringify({username:'INVALID NAME',nickname:'Неверный'})]),/Имя пользователя/);
 });
 await client.query("update public.app_roles set role='admin' where user_id=$1",[admin]);
 await test('anonymous can read curriculum, cannot read private profiles',async()=>{await as(null);assert.equal((await client.query('select count(*)::integer as n from public.lessons')).rows[0].n,19);await denied(()=>client.query('select * from public.profiles'),/permission denied/);});
 await as(student);
 await test('RLS isolates profiles and denies role escalation and key reads',async()=>{assert.equal((await client.query('select * from public.profiles')).rows.length,1);await denied(()=>client.query("update public.app_roles set role='admin' where user_id=$1",[student]),/permission denied/);await denied(()=>client.query('select * from private.exam_keys'),/permission denied/);assert.equal((await client.query('select * from public.exam_questions')).rows.length,0);});
 await test('official license and score writes are denied',async()=>{await denied(()=>client.query("insert into public.user_licenses(user_id,license_id) values($1,'Pro')",[student]),/permission denied/);await denied(()=>client.query("update public.exam_attempts set total=100"),/permission denied/);await denied(()=>rpc('admin_settings',{enabled:true,daily_limit:50}),/администратора/);});
 await test('exam prerequisites enforced on server',async()=>{await denied(()=>rpc('start_exam',{exam_id:'D'}),/уроки/);await denied(()=>rpc('start_exam',{exam_id:'C'}),/предыдущую лицензию/);});
 await test('cannot skip lesson prerequisites',async()=>{await denied(()=>rpc('save_lesson',{lesson_id:'pressing-2',state:{},step:3}),/предыдущие/);});
 const rational='Сначала наша команда ждёт плохой приём у боковой линии как сигнал давления. Нападающий закрывает передачу назад, вингер встречает защитника, а восьмёрка перекрывает ближайшего опорного игрока. Остальные партнёры сужают позиции и сохраняют страховку. Если соперник проходит первую линию давления, опорный задерживает атаку, а остальные быстро возвращаются за линию мяча в компактный блок.';
 const answer=l=>({answers:l.quiz.map(q=>q.correct),board:{formation:'4-3-3',players:[[50,91],[15,72],[38,76],[62,76],[85,72],[28,49],[50,56],[72,49],[16,25],[50,18],[84,25]],press:l.criteria.press,width:l.criteria.width,attack:l.criteria.attack,rationale:rational,substitution:'Свежий крайний нападающий добавит ширину и ускорения за спину'}});
 await test('draft is persisted and cannot mark itself complete',async()=>{await rpc('save_lesson',{lesson_id:'pressing-1',state:{fake:true,completed:true},step:5});const p=(await client.query('select * from public.lesson_progress')).rows[0];assert.equal(p.completed,false);assert.equal(p.step,4);assert.equal(p.state.fake,true);});
 await test('incorrect lesson answers fail with explicit feedback',async()=>{const v=answer(lessons[0]);v.answers=[0,1];const r=await rpc('submit_lesson',{lesson_id:'pressing-1',state:v});assert.equal(r.passed,false);assert(r.checks.some(c=>!c.pass));});
 await test('valid lesson earns completion and achievement; cross-user access blocked',async()=>{const r=await rpc('submit_lesson',{lesson_id:'pressing-1',state:answer(lessons[0])});assert.equal(r.passed,true);assert.equal((await client.query('select * from public.user_achievements')).rows.length,1);await as(other);assert.equal((await client.query('select * from public.lesson_progress')).rows.length,0);assert.equal((await client.query('select * from public.assignment_submissions')).rows.length,0);await as(student);assert.equal((await client.query('select * from public.lesson_progress')).rows[0].completed,true);});
 for(const l of lessons.filter(l=>l.course_id==='pressing'&&l.position>1))await rpc('submit_lesson',{lesson_id:l.id,state:answer(l)});
 let a;
 await test('official start creates immutable snapshots without keys and resumes same attempt',async()=>{a=await rpc('start_exam',{exam_id:'D'});assert.equal(a.questions.filter(q=>q.kind==='theory').length,20);assert.equal(a.questions.filter(q=>q.kind==='practice').length,3);assert(!JSON.stringify(a.questions).includes('correct'));assert.equal((await rpc('start_exam',{exam_id:'D'})).id,a.id);});
 await test('exam draft survives user session switch; foreign submissions rejected',async()=>{await rpc('save_exam',{attempt_id:a.id,answers:{1:0}});await as(other);assert.equal((await client.query('select * from public.exam_attempts')).rows.length,0);await denied(()=>rpc('submit_exam',{attempt_id:a.id,answers:{}}),/недоступна/);await as(student);assert.equal((await client.query('select * from public.exam_attempts')).rows[0].draft['1'],0);});
 await test('incomplete official exam cannot submit',async()=>{await denied(()=>rpc('submit_exam',{attempt_id:a.id,answers:{}}),/20 вопросов/);});
 await client.query('reset role');
 const keys=(await client.query('select answers from private.attempt_keys where attempt_id=$1',[a.id])).rows[0].answers;
 const answers=Object.fromEntries(keys.map(k=>[k.position,k.correct]));
 for(const q of a.questions.filter(q=>q.kind==='practice'))answers[q.position]=rational+' '+rational;
 await as(student);
 await test('official theory is graded on server, no license before manual review',async()=>{const result=await rpc('submit_exam',{attempt_id:a.id,answers});assert.equal(result.theory_score,40);assert.equal(result.status,'submitted');assert.equal((await client.query('select * from public.user_licenses')).rows.length,0);await denied(()=>rpc('submit_exam',{attempt_id:a.id,answers}),/уже отправлена/);});
 const review=Array.from({length:3},()=>({scores:[4,4,4,4],feedback:'Обоснованный план, понятные роли и страховка; уточните критерии корректировки.'}));
 await test('students cannot perform manual review',async()=>{await denied(()=>rpc('admin_review',{attempt_id:a.id,review}),/администратора/);});
 await as(admin);
 await test('review requires full rubric and prevents own grading',async()=>{await denied(()=>rpc('admin_review',{attempt_id:a.id,review:[{scores:[20],feedback:'x'}]}),/три задачи/);await client.query('reset role');await client.query('update public.exam_attempts set user_id=$1 where id=$2',[admin,a.id]);await as(admin);await denied(()=>rpc('admin_review',{attempt_id:a.id,review}),/собственный/);await client.query('reset role');await client.query('update public.exam_attempts set user_id=$1 where id=$2',[student,a.id]);await as(admin);});
 await test('admin review atomically grades and issues exactly one license; duplicate rejected',async()=>{const r=await rpc('admin_review',{attempt_id:a.id,review});assert.equal(r.total,88);assert.equal(r.passed,true);await denied(()=>rpc('admin_review',{attempt_id:a.id,review}),/уже проверена/);await as(student);const ls=(await client.query('select * from public.user_licenses')).rows;assert.equal(ls.length,1);assert.equal(ls[0].license_id,'D');assert.equal((await client.query('select * from public.exam_answers')).rows.length,23);});
 await as(admin);
 await test('admin CRUD publishes a course and lesson with server criteria',async()=>{await rpc('admin_course',{course:{id:'test-course',license_id:'D',title:'Тест курса',description:'Тестовое описание',position:6}});const l=structuredClone(lessons[0]);await rpc('admin_lesson',{lesson:{id:'test-lesson',course_id:'test-course',position:1,title:'Тест урока',content:l},answers:[1,0],criteria:l.criteria});assert.equal((await client.query("select * from public.lessons where id='test-lesson'")).rows.length,1);await rpc('admin_question',{question:{exam_id:'D',position:1,kind:'theory',prompt:'Новый вопрос',options:['А','Б'],rubric:null},correct:1});});
 await test('block prevents student writes and data access',async()=>{await rpc('admin_block',{user_id:other,banned:true});await as(other);await denied(()=>rpc('profile',{nickname:'blocked',avatar:'⚽'}),/активный аккаунт/);assert.equal((await client.query('select * from public.exam_attempts')).rows.length,0);});
 console.log(`${count} database integration checks passed.`);
}finally{await client.end();}

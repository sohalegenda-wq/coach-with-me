import {test} from 'node:test';
import assert from 'node:assert/strict';
import {courses,lessons,levels,formations} from '../src/catalog.js';
import {escapeHTML,words,evaluatePractice,safeReturnPath} from '../src/utils.js';
import {initialBoard} from '../src/board.js';
test('curriculum covers all licenses with ordered complete lessons',()=>{
 assert.deepEqual(courses.map(c=>c.license),levels);assert.equal(lessons.length,19);
 for(const c of courses){const list=lessons.filter(l=>l.course_id===c.id);assert(list.length>=3);assert.deepEqual(list.map(l=>l.position),list.map((_,i)=>i+1));for(const l of list){assert(l.theory.length>100);assert(l.scenario.length>50);assert(l.quiz.length>=2);for(const q of l.quiz){assert(q.correct>=0&&q.correct<q.options.length);assert(q.explanation);}}}
});
test('all formations have 11 unique players within pitch',()=>{for(const p of Object.values(formations)){assert.equal(p.length,11);assert.equal(new Set(p.map(v=>v.join(','))).size,11);assert(p.every(([x,y])=>x>=5&&x<=95&&y>=6&&y<=94));}});
test('HTML escapes scripts and attribute breakouts',()=>{assert.equal(escapeHTML('<script>"x" & \'y\'</script>'),'&lt;script&gt;&quot;x&quot; &amp; &#39;y&#39;&lt;/script&gt;');});
test('practical rubric fails empty explanations and wrong settings',()=>{const state=initialBoard();const checks=evaluatePractice(state,lessons[0].criteria);assert(checks.some(c=>!c.pass));state.press='high';state.attack='direct';state.rationale=Array(40).fill('страховка').join(' ');assert(evaluatePractice(state,lessons[0].criteria).every(c=>c.pass));});
test('word counts and safe return navigation',()=>{assert.equal(words('  один\nдва  три '),3);assert.equal(words(''),0);assert.equal(safeReturnPath('https://evil.test'),'#/dashboard');assert.equal(safeReturnPath('#/lesson/pressing-1'),'#/lesson/pressing-1');});

import { state, supabase } from './api.js';
import { catalog } from './pages-academy.js';
import { escapeHTML as e } from './utils.js';
import { pageHead, toast, run, icon } from './ui.js';
let guestHistory=[];
function guidedReply(message, mode, lesson) {
 if(mode==='explain')return `${lesson.title}\n\n${lesson.theory}\n\nПример: ${lesson.example}\n\nПодумайте: ${lesson.quiz[0].prompt}\n\nПопробуйте ответить в режиме «Проверь меня».`;
 if(mode==='train')return `${lesson.scenario}\n\nПлан ответа:\n1. Где мяч и кто свободен?\n2. Что служит сигналом?\n3. Кто давит, кто страхует?\n4. Что меняется, если план не сработал?\n\nПроверьте решение на тактической доске. Это подготовленное упражнение, а не ответ ИИ.`;
 const hasPlan=/страх|баланс|опорн|защит/iu.test(message),hasSignal=/триггер|сигнал|при[её]м|пас|потер/iu.test(message);
 return `Проверка по опорным словам (не смысловая оценка):\n${hasSignal?'✓ Упомянут сигнал или действие с мячом.':'○ Уточните сигнал для начала действия.'}\n${hasPlan?'✓ Упомянут баланс или страховка.':'○ Добавьте, кто страхует и что делать при потере.'}\n\nСопоставьте свой ответ с принципом: ${lesson.quiz[0].explanation}\n\n${lesson.example}\n\nСледующий шаг: объясните роли ближайшего и дальнего игрока. Для разбора свободного текста включите ИИ-режим, если провайдер подключён.`;
}
export async function tutorPage() {
 const {lessons}=catalog();let history=guestHistory;
 if(state.user){const {data,error}=await supabase.from('tutor_messages').select('*').eq('user_id',state.user.id).order('id',{ascending:false}).limit(40);if(error)throw error;history=(data||[]).reverse();}
 const next=lessons.find(l=>!state.progress.some(p=>p.lesson_id===l.id&&p.completed))||lessons[0];
 const bubble=m=>`<div class="message ${m.role==='user'?'user':'assistant'}"><div class="message-avatar">${m.role==='user'?'ВЫ':'C'}</div><div><div class="message-meta">${m.role==='user'?'Вы':m.source==='ai'?'Coach CWM · ИИ':'Coach CWM · учебный режим'}</div><p>${e(m.content)}</p></div></div>`;
 return {html:pageHead('ВАШ ЛИЧНЫЙ НАСТАВНИК','О чём поговорим, тренер?','Разбирайте сложное, задавайте вопросы и готовьтесь к игре.')+`<div class="tutor-layout"><section class="card chat-card"><div class="chat-header"><div class="coach-avatar small">C</div><div><strong>Coach CWM</strong><small>Футбольное мышление — шаг за шагом</small></div><span class="badge" id="tutor-status">Учебный режим</span></div><div class="mode-tabs" role="group" aria-label="Режим наставника"><button class="chip active" data-mode="explain">Объясни мне</button><button class="chip" data-mode="check">Проверь меня</button><button class="chip" data-mode="train">Тренируй меня</button></div><div id="messages" class="messages" role="log" aria-live="polite">${history.length?history.map(bubble).join(''):bubble({role:'assistant',source:'guided',content:'Привет! Я Coach CWM. Выберите тему и режим. Мы разберём принцип, проверим понимание и перейдём к практике. Учебный режим использует подготовленные материалы; свободный диалог доступен через подключённый ИИ.'})}</div><form id="tutor-form"><label class="sr-only" for="tutor-input">Ваш вопрос или ответ</label><div class="chat-input"><textarea id="tutor-input" name="message" rows="2" required minlength="3" maxlength="3000" placeholder="Например: как перекрыть пас на опорного?" ></textarea><button class="button primary" aria-label="Отправить сообщение">${icon('arrow')}</button></div></form><small class="chat-disclaimer">Учебный режим не использует ИИ и не оценивает официальные экзамены.</small></section><aside><section class="card"><h3>Настройки занятия</h3><label>Тема<select id="tutor-topic">${lessons.map(l=>`<option value="${e(l.id)}" ${l.id===next?.id?'selected':''}>${e(l.title)}</option>`).join('')}</select></label><label>Формат ответа<select id="tutor-provider"><option value="guided">Учебный · всегда доступен</option value="ai" ${!state.user?'disabled':''}>ИИ · требуется аккаунт и провайдер</option></select></label><p id="tutor-notice">Подготовленные объяснения и упражнения. Без внешних API и расходов.</p></section><section class="card"><span class="eyebrow">СОВЕТ НАСТАВНИКА</span><h3>Добавьте контекст</h3><p>Укажите схему, счёт, минуту матча и действия соперника. Чем конкретнее ситуация, тем полезнее разбор.</p><a href="#/practice">Открыть тактическую доску →</a></section></aside></div>`,bind(){
 let mode='explain';const messages=document.querySelector('#messages');messages.scrollTop=messages.scrollHeight;
 document.querySelectorAll('[data-mode]').forEach(b=>b.onclick=()=>{mode=b.dataset.mode;document.querySelectorAll('[data-mode]').forEach(x=>x.classList.toggle('active',x===b));});
 document.querySelector('#tutor-provider').onchange=ev=>{document.querySelector('#tutor-status').textContent=ev.target.value==='ai'?'ИИ-режим':'Учебный режим';document.querySelector('#tutor-notice').textContent=ev.target.value==='ai'?'Сообщение и учебный контекст передаются ИИ-провайдеру. При ошибке включится учебный режим.':'Подготовленные объяснения и упражнения. Без внешних API и расходов.';};
 document.querySelector('#tutor-form').onsubmit=ev=>{ev.preventDefault();const form=ev.target;const input=form.elements.message;const message=input.value.trim();if(message.length<3)return;run(form.querySelector('button'),async()=>{
  const lesson=lessons.find(l=>l.id===document.querySelector('#tutor-topic').value);let answer,source='guided';
  if(document.querySelector('#tutor-provider').value==='ai'){
   const {data,error}=await supabase.functions.invoke('coach',{body:{message,mode}});
   if(error)toast('ИИ недоступен. Переключаюсь на учебный разбор.');
   else if(data?.answer){answer=data.answer;source='ai';if(!data.saved)toast('Ответ получен, но история не сохранилась.');}
   else toast(data?.reason||data?.error||'Учебный режим доступен');
  }
  answer||=guidedReply(message,mode,lesson);
  if(source==='guided'&&state.user){const {error}=await supabase.rpc('academy',{p_action:'tutor_log',p_payload:{mode,question:message,answer,source}});if(error)toast('История не сохранилась: '+error.message,true);}
  const pair=[{role:'user',content:message,source},{role:'assistant',content:answer,source}];
  if(!state.user)guestHistory.push(...pair);messages.insertAdjacentHTML('beforeend',pair.map(bubble).join(''));input.value='';messages.scrollTop=messages.scrollHeight;
 });};
 }};
}

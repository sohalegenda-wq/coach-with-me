import './style.css';
import { state, supabase, initializeAuth, refreshData, configured, loadCatalog } from './api.js';
import { escapeHTML as e } from './utils.js';
import { icon, empty, toast, btn } from './ui.js';
import { dashboardPage, academyPage, lessonPage, practicePage, aboutPage } from './pages-academy.js';
import { authPage, profilePage } from './pages-auth.js';
import { tutorPage } from './pages-tutor.js';
import { examsPage } from './pages-exams.js';
import { adminPage } from './pages-admin.js';
const nav=[['dashboard','Обзор','home'],['academy','Академия','academy'],['tutor','Coach CWM','tutor'],['practice','Тактическая доска','practice'],['exams','Экзамены и лицензии','exams'],['profile','Мой профиль','profile']];
let renderId=0;
function shell(){
 const current=(location.hash.slice(2).split('/')[0]||'dashboard');
 document.querySelector('#app').innerHTML=`<aside class="sidebar" id="sidebar"><a class="brand" href="#/dashboard"><span class="brand-symbol">C<span>${icon('arrow')}</span></span><span>CWM<small>COACH WITH ME</small></span></a><div class="academy-label">АКАДЕМИЯ ТРЕНЕРОВ FTCL</div><div class="nav-label">ВАШЕ ПРОСТРАНСТВО</div><nav aria-label="Основная навигация">${nav.map(([id,title,ico])=>`<a href="#/${id}" class="nav-item ${current===id?'active':''}" ${current===id?'aria-current="page"':''}>${icon(ico)}<span>${title}</span>${id==='tutor'?'<span class="nav-new">COACH</span>':''}</a>`).join('')}${state.role==='admin'?`<a class="nav-item ${current==='admin'?'active':''}" href="#/admin">${icon('admin')} Администратор</a>`:''}</nav><div class="sidebar-bottom"><a href="#/about" class="community-box"><span>FTCL</span><div><strong>Одна лига. Одна игра.</strong><small>Знания, которые объединяют →</small></div></a><div class="sidebar-footer"><span class="status-dot"></span> ВАШ ПУТЬ В БОЛЬШОМ ФУТБОЛЕ</div></div></aside><div class="workspace"><header class="topbar"><button id="menu-toggle" class="icon-button mobile-only" aria-label="Открыть меню" aria-expanded="false">☰</button><div class="breadcrumb">Академия <span>/</span> <strong>${e(nav.find(x=>x[0]===current)?.[1]||({login:'Вход',register:'Регистрация',about:'Об академии',admin:'Управление'}[current])||'CWM')}</strong></div><div class="topbar-right"><span class="free-label"><span class="status-dot"></span> УЧИТЕСЬ В СВОЁМ ТЕМПЕ</span>${state.user?`<a class="user-menu" href="#/profile"><span class="avatar">${e(state.profile?.avatar||'⚽')}</span><div><strong>${e(state.profile?.nickname||'Тренер')}</strong><small>Тренер FTCL</small></div></a><button id="logout" class="icon-button" aria-label="Выйти">${icon('logout')}</button>`:`<a class="login-link" href="#/login">Войти</a><a class="button primary small" href="#/register">Присоединиться ${icon('arrow')}</a>`}</div></header><main id="content" tabindex="-1"></main><footer class="footer"><span>© ${new Date().getFullYear()} CWM · Coach With Me</span><span>СОЗДАНО ДЛЯ ТЕХ, КТО МЕНЯЕТ ИГРУ</span><a href="#/about">Об академии и данных</a></footer></div>`;
 document.querySelector('#menu-toggle').onclick=ev=>{const open=document.querySelector('#sidebar').classList.toggle('open');ev.currentTarget.setAttribute('aria-expanded',String(open));};
 document.querySelector('#logout')?.addEventListener('click',async()=>{const {error}=await supabase.auth.signOut();if(error){toast(error.message,true);return;}Object.assign(state,{user:null,profile:null,role:'student',progress:[],licenses:[],attempts:[],achievements:[]});toast('Вы вышли из аккаунта');location.hash='#/login';await render();});
}
async function render(){
 const id=++renderId;shell();const content=document.querySelector('#content');content.innerHTML='<div class="loading" role="status">Загружаем вашу академию…</div>';
 const [route='dashboard',param]=location.hash.replace(/^#\//,'').split('/');
 const guarded=['profile','admin'].includes(route)||(route==='exams'&&param!=='practice');
 try {
  let page;
  if(guarded&&!state.user)page={html:empty('Продолжите с аккаунтом','Войдите, чтобы увидеть личные результаты, сдавать экзамены и сохранять лицензии.',btn('Войти','#/login')+' '+btn('Создать аккаунт','#/register','secondary')),bind(){}};
  else switch(route){
   case 'dashboard':case '':page=dashboardPage();break;
   case 'academy':page=academyPage(param);break;
   case 'lesson':page=lessonPage(param);break;
   case 'practice':page=practicePage();break;
   case 'tutor':page=await tutorPage();break;
   case 'exams':page=await examsPage(param);break;
   case 'profile':page=profilePage();break;
   case 'login':case 'register':case 'forgot':case 'reset':page=authPage(route);break;
   case 'about':page=aboutPage();break;
   case 'admin':page=await adminPage();break;
   default:page={html:empty('Страница не найдена','Вернитесь к обучению.',btn('В академию','#/academy')),bind(){}};
  }
  if(id!==renderId)return;content.innerHTML=page.html;page.bind?.();document.title=`${nav.find(x=>x[0]===route)?.[1]||'Академия'} · CWM — Coach With Me`;
  window.scrollTo(0,0);
 }catch(error){if(id!==renderId)return;content.innerHTML=empty('Не удалось загрузить данные',error.message,btn('Вернуться в академию','#/academy','secondary'));toast(error.message,true);}
}
window.addEventListener('hashchange',render);
// Supabase refreshes access tokens automatically. Defer DB work outside auth callbacks.
supabase?.auth.onAuthStateChange((event,session)=>{
 if(event==='PASSWORD_RECOVERY'){state.user=session?.user;setTimeout(()=>{location.hash='#/reset';},0);}
 if(event==='SIGNED_OUT'){state.user=null;}
 if(event==='SIGNED_IN'&&session&&state.user?.id!==session.user.id){state.user=session.user;setTimeout(async()=>{try{await refreshData();await render();}catch(err){toast(err.message,true);}},0);}
});
try {await initializeAuth();} catch(error){toast('Проверьте подключение Supabase: '+error.message,true);}
if(!location.hash)history.replaceState(null,'','#/dashboard');
await render();

if(configured&&!state.user){try{await loadCatalog();await render();}catch{toast('Онлайн-каталог пока недоступен. Открыты встроенные учебные материалы.');}}

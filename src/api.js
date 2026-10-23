import { createClient } from '@supabase/supabase-js';
const url = import.meta.env.VITE_SUPABASE_URL;
const key = import.meta.env.VITE_SUPABASE_ANON_KEY;
const localURL = url?.startsWith('http://127.0.0.1:') || url?.startsWith('http://localhost:');
export const configured = Boolean((url?.startsWith('https://') || localURL) && key && !url.includes('YOUR_PROJECT'));
export const supabase = configured ? createClient(url, key, {auth:{persistSession:true, autoRefreshToken:true, detectSessionInUrl:true, flowType:'pkce'}}) : null;
export const state = { user:null, profile:null, progress:[], licenses:[], attempts:[], achievements:[], role:'student', courses:[], lessons:[], catalogLoaded:false };
export async function loadCatalog() {
  if (!supabase) return;
  const results = await Promise.all(['courses','lessons'].map(name => supabase.from(name).select('*').eq('published',true).order('position').abortSignal(AbortSignal.timeout(7000))));
  for (const result of results) if (result.error) throw result.error;
  state.courses = results[0].data; state.lessons = results[1].data; state.catalogLoaded = true;
}
export async function refreshData() {
  if (!state.user) return;
  const names = ['profiles','lesson_progress','user_licenses','exam_attempts','user_achievements','app_roles','courses','lessons'];
  const results = await Promise.all(names.map(name => {
    let q = supabase.from(name).select('*');
    if (name === 'profiles') q = q.eq('id', state.user.id);
    if (['lesson_progress','user_licenses','exam_attempts','user_achievements'].includes(name)) q = q.eq('user_id', state.user.id);
    if (name === 'app_roles') q = q.eq('user_id', state.user.id);
    if (name === 'exam_attempts') q = q.order('created_at',{ascending:false});
    if (name === 'lessons' || name === 'courses') q = q.eq('published',true).order('position');
    return q;
  }));
  for (let i=0;i<results.length;i++) if(results[i].error) throw new Error(`Не удалось загрузить ${names[i]}: ${results[i].error.message}`);
  state.catalogLoaded = true;
  [state.profile, state.progress, state.licenses, state.attempts, state.achievements, state.role, state.courses, state.lessons] = [results[0].data[0], results[1].data, results[2].data, results[3].data, results[4].data, results[5].data[0]?.role || 'student',results[6].data,results[7].data];
}
export async function api(action, payload = {}) {
  if (!supabase) throw new Error('Подключите Supabase по инструкции в README. Учебные материалы доступны без аккаунта.');
  const {data,error} = await supabase.functions.invoke('academy-api',{body:{action,...payload}});
  if (error) {
    let message = error.message;
    try { message = (await error.context.json()).error || message; } catch { /* Network errors have no response. */ }
    throw new Error(message);
  }
  if (data?.error) throw new Error(data.error);
  return data;
}
export async function initializeAuth() {
  if (!supabase) return;
  const {data:{session},error} = await supabase.auth.getSession();
  if (error) throw error;
  state.user = session?.user || null;
  if (state.user) await refreshData();
}

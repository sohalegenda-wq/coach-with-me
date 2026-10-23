import { createClient } from 'npm:@supabase/supabase-js@2.118.0';
export function headers(request: Request) {
  const origin = request.headers.get('origin') || '';
  const allowed = (Deno.env.get('ALLOWED_ORIGINS') || '').split(',').map(s => s.trim()).filter(Boolean);
  return { 'Access-Control-Allow-Origin': allowed.includes(origin) ? origin : '', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type', 'Access-Control-Allow-Methods':'POST, OPTIONS', 'Vary':'Origin', 'Content-Type':'application/json; charset=utf-8', 'Cache-Control':'no-store' };
}
export function respond(request:Request, body:unknown, status=200) { return new Response(JSON.stringify(body),{status,headers:headers(request)}); }
export async function context(request:Request) {
  if(request.method!=='POST') throw new Error('Метод не поддерживается');
  const token=request.headers.get('Authorization');
  if(!token?.startsWith('Bearer ')) throw new Error('Требуется вход');
  const client=createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!, {global:{headers:{Authorization:token}},auth:{persistSession:false,autoRefreshToken:false}});
  const {data:{user},error}=await client.auth.getUser(token.slice(7));
  if(error || !user) throw new Error('Сессия истекла. Войдите снова');
  if (Number(request.headers.get('content-length') || 0)>100000) throw new Error('Слишком большой запрос');
  const raw=await request.text();
  if(raw.length>100000) throw new Error('Слишком большой запрос');
  const body=JSON.parse(raw);
  if(!body || typeof body!=='object' || Array.isArray(body)) throw new Error('Неверный запрос');
  return {client,user,body};
}
export function preflight(request:Request) { return request.method==='OPTIONS' ? new Response(null,{status:204,headers:headers(request)}) : null; }

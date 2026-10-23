import { handler as academy } from '../supabase/functions/academy-api/handler.ts';
import { handler as coach } from '../supabase/functions/coach/handler.ts';
const equal=(a:unknown,b:unknown)=>{if(JSON.stringify(a)!==JSON.stringify(b))throw new Error(`${JSON.stringify(a)} != ${JSON.stringify(b)}`);};
const originalFetch=globalThis.fetch;
Deno.env.set('SUPABASE_URL','https://test.supabase.co');
Deno.env.set('SUPABASE_ANON_KEY','public-test-key');
Deno.env.set('ALLOWED_ORIGINS','https://academy.example');
function req(body:unknown, token='valid-token',origin='https://academy.example') {return new Request('https://edge.example',{method:'POST',headers:{Authorization:`Bearer ${token}`,Origin:origin,'Content-Type':'application/json'},body:JSON.stringify(body)});}
function mock(options:{quota?:boolean;rpcError?:boolean;ai?:boolean}={}){
 let rpcCalls=0;const urls:string[]=[];
 globalThis.fetch=(async(input:RequestInfo|URL,init?:RequestInit)=>{
  const request=input instanceof Request?input:new Request(input,init);const url=request.url;urls.push(url);
  if(url.endsWith('/auth/v1/user'))return new Response(JSON.stringify(request.headers.get('Authorization')==='Bearer valid-token'?{id:'10000000-0000-4000-8000-000000000001',email:'test@example.test'}:{message:'Invalid JWT'}),{status:request.headers.get('Authorization')==='Bearer valid-token'?200:401,headers:{'Content-Type':'application/json'}});
  if(url.endsWith('/rpc/academy')){rpcCalls++;const payload=await request.json();const data=options.rpcError?{message:'Требуются права администратора',code:'42501'}:payload.p_action==='tutor_reserve'?{allowed:options.quota??true}:{saved:true};return new Response(JSON.stringify(data),{status:options.rpcError?403:200,headers:{'Content-Type':'application/json'}});}
  if(url.includes('/rest/v1/'))return new Response(JSON.stringify(url.includes('/profiles')?{nickname:'Тренер'}:[]),{headers:{'Content-Type':'application/json'}});
  if(url.includes('/chat/completions'))return new Response(JSON.stringify({error:'quota'}),{status:429,headers:{'Content-Type':'application/json'}});
  throw new Error('Unexpected request: '+url);
 }) as typeof fetch;
 return {urls,calls:()=>rpcCalls};
}
Deno.test('Edge rejects invalid JWT before any database operation',async()=>{const m=mock();try{const r=await academy(req({action:'admin_license'},'forged'));equal(r.status,401);equal(m.calls(),0);}finally{globalThis.fetch=originalFetch;}});
Deno.test('Edge forwards server permission errors and rejects unknown actions',async()=>{mock({rpcError:true});try{const r=await academy(req({action:'admin_settings'}));equal(r.status,403);equal((await r.json()).error,'Требуются права администратора');equal((await academy(req({action:'grant_me_admin'}))).status,400);}finally{globalThis.fetch=originalFetch;}});
Deno.test('CORS allows exact configured origins only',async()=>{mock();try{equal((await academy(req({action:'profile'}))).headers.get('access-control-allow-origin'),'https://academy.example');equal((await academy(req({action:'profile'},'valid-token','https://evil.example'))).headers.get('access-control-allow-origin'),'');}finally{globalThis.fetch=originalFetch;}});
Deno.test('Disabled tutor falls back without calling AI',async()=>{Deno.env.set('AI_PROVIDER','disabled');const m=mock();try{const r=await coach(req({mode:'explain',message:'Как начать прессинг?'}));equal(r.status,200);equal((await r.json()).fallback,true);equal(m.urls.some(u=>u.includes('/chat/completions')),false);}finally{globalThis.fetch=originalFetch;}});
Deno.test('Exhausted daily quota falls back before provider access',async()=>{Deno.env.set('AI_PROVIDER','openai');Deno.env.set('AI_API_KEY','server-secret');const m=mock({quota:false});try{const r=await coach(req({mode:'train',message:'Подготовь задачу'}));equal((await r.json()).fallback,true);equal(m.urls.some(u=>u.includes('/chat/completions')),false);}finally{globalThis.fetch=originalFetch;}});
Deno.test('Provider quota failure uses fallback, ignores browser URL, exposes no secret',async()=>{Deno.env.set('AI_PROVIDER','openai');Deno.env.set('AI_API_KEY','server-secret');const m=mock();try{const r=await coach(req({mode:'explain',message:'Как организовать страховку?',base_url:'https://evil.example',model:'evil'}));const raw=await r.text();equal(JSON.parse(raw).fallback,true);equal(raw.includes('server-secret'),false);equal(m.urls.some(u=>u.startsWith('https://api.openai.com/v1/')),true);equal(m.urls.some(u=>u.includes('evil.example')),false);}finally{globalThis.fetch=originalFetch;}});

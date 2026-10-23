import { context, preflight, respond } from '../_shared/http.ts';
const actions = new Set(['profile','save_lesson','submit_lesson','practice_test','start_exam','save_exam','submit_exam','admin_review','admin_block','admin_license','admin_cancel','admin_settings','admin_course','admin_lesson','admin_question']);
export async function handler(request: Request) {
 const cors=preflight(request); if(cors)return cors;
 try {
  const {client,body}=await context(request);
  const {action,...payload}=body;
  if(!actions.has(action))return respond(request,{error:'Неизвестная операция'},400);
  const {data,error}=await client.rpc('academy',{p_action:action,p_payload:payload});
  if(error)return respond(request,{error:error.message},error.code==='42501'?403:400);
  return respond(request,data);
 } catch(error) {return respond(request,{error:error instanceof Error?error.message:'Ошибка запроса'},401);}
}

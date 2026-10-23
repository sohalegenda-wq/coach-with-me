import { escapeHTML as e } from './utils.js';
export const icons = {
 home:'<path d="m3 10 9-7 9 7v10a1 1 0 0 1-1 1h-5v-7H9v7H4a1 1 0 0 1-1-1Z"/>',
 academy:'<path d="m2 8 10-5 10 5-10 5-10-5Zm4 3v6l6 3 6-3v-6M22 8v8"/>',
 tutor:'<path d="M21 11a8 8 0 0 1-8 8H8l-5 3 1-6a8 8 0 1 1 17-5Z"/><path d="M8 10h8M8 14h5"/>',
 practice:'<rect x="3" y="3" width="18" height="18" rx="2"/><path d="M3 12h18M8 3v4H3m18 10h-5v4"/><circle cx="12" cy="12" r="3"/>',
 exams:'<rect x="5" y="4" width="14" height="17" rx="2"/><path d="M9 4V2h6v2M9 10h6m-6 4h6m-6 4h3"/>',
 profile:'<circle cx="12" cy="8" r="4"/><path d="M4 22v-3a8 8 0 0 1 16 0v3"/>',
 admin:'<path d="m12 2 9 4v6c0 5-9 10-9 10S3 17 3 12V6Z"/><path d="m8 12 3 3 5-6"/>',
 arrow:'<path d="M5 12h14m-6-6 6 6-6 6"/>',
 clock:'<circle cx="12" cy="12" r="9"/><path d="M12 6v6l4 2"/>',
 check:'<path d="m5 12 4 4L20 5"/>',
 logout:'<path d="M9 21H4V3h5m5 4 5 5-5 5m-5-5h10"/>',
};
export const icon = (name,cls='')=>`<svg class="icon ${cls}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${icons[name]||icons.academy}</svg>`;
export const btn = (label,href,kind='primary') => `<a class="button ${kind}" href="${href}">${label}</a>`;
export function toast(message,error=false) {const node=document.querySelector('#toast');node.textContent=message;node.className='toast visible'+(error?' error':'');clearTimeout(toast.timer);toast.timer=setTimeout(()=>node.classList.remove('visible'),6500);}
export async function run(button,task) {if(button?.disabled)return; const text=button?.textContent;if(button){button.disabled=true;button.textContent='Подождите…';}try{return await task();}catch(error){toast(error.message||'Не удалось выполнить действие',true);return null;}finally{if(button?.isConnected){button.disabled=false;button.textContent=text;}}}
export const empty = (title,description,link='') => `<div class="empty"><span class="empty-icon">◇</span><h3>${e(title)}</h3><p>${e(description)}</p>${link}</div>`;
export const pageHead = (eyebrow,title,desc,extra='') => `<div class="page-heading"><div><span class="eyebrow">${eyebrow}</span><h1>${title}</h1><p>${desc}</p></div>${extra}</div>`;
export const callout = (text,kind='info') => `<div class="callout ${kind}">${text}</div>`;
export function pitchArt() {return `<svg class="hero-art" viewBox="0 0 500 340" fill="none" aria-hidden="true"><defs><linearGradient id="grass" x1="0" y1="0" x2="500" y2="340"><stop stop-color="#213e2e"/><stop offset="1" stop-color="#15251d"/></linearGradient><marker id="arrow" markerWidth="7" markerHeight="7" refX="5" refY="3" orient="auto"><path d="m0 0 6 3-6 3" stroke="#4ade80" fill="none"/></marker></defs><g transform="translate(28 0) rotate(9 220 170)"><rect x="25" y="30" width="400" height="275" rx="3" fill="url(#grass)" stroke="#497456"/><path d="M25 168h400M92 30v275m66-275v275m67-275v275m67-275v275m66-275v275" stroke="#466e51" stroke-opacity=".15" stroke-width="32"/><path d="M25 168h400M155 30v44h140V30m-102 0v16h65V30M155 305v-44h140v44m-102 0v-16h65v16" stroke="#73a885" stroke-opacity=".4"/><circle cx="225" cy="168" r="40" stroke="#73a885" stroke-opacity=".4"/><path d="M117 218 168 163m80 83 47-72m-23-70 43-33M167 129l39-42" stroke="#4ade80" stroke-width="2" stroke-dasharray="6 5" marker-end="url(#arrow)"/>${[[225,284],[95,239],[177,247],[272,247],[352,238],[139,178],[225,203],[308,178],[101,115],[225,92],[350,115]].map(([x,y],i)=>`<circle cx="${x}" cy="${y}" r="${i===0?10:12}" fill="#4ade80" fill-opacity="${i===0?'.5':'1'}"/><circle cx="${x}" cy="${y}" r="18" stroke="#4ade80" stroke-opacity=".12"/>`).join('')}${[[100,70],[180,67],[268,67],[350,70],[145,133],[224,137],[300,135]].map(([x,y])=>`<circle cx="${x}" cy="${y}" r="8" fill="#b6c4bb" fill-opacity=".65"/>`).join('')}<circle cx="225" cy="73" r="4" fill="white"/></g></svg>`;}

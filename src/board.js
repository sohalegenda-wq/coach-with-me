import { formations } from './catalog.js';
import { escapeHTML as e } from './utils.js';
export function initialBoard() { return {formation:'4-3-3',players:structuredClone(formations['4-3-3']),press:'medium',width:'balanced',attack:'balanced',rationale:'',substitution:''}; }
export function boardHTML(value, id = 'tactic') {
  return `<div class="tactics-layout"><div><div class="pitch-label"><span>АТАКУЕМ ВВЕРХ ↑</span><span>11 × 11</span></div><div class="pitch interactive" id="${id}" aria-label="Тактическая доска: перетащите игроков или используйте стрелки клавиатуры"><div class="pitch-half"></div><div class="pitch-circle"></div><div class="penalty top"></div><div class="penalty bottom"></div>${value.players.map((p,i)=>`<button type="button" class="player" data-player="${i}" style="left:${p[0]}%;top:${p[1]}%" aria-label="Игрок ${i+1}, стрелки для перемещения">${i+1}</button>`).join('')}</div><small>Перетаскивайте игроков. Клавиатура: Tab → стрелки.</small></div><div class="board-controls"><label>Расстановка<select name="formation">${Object.keys(formations).map(v=>`<option ${value.formation===v?'selected':''}>${v}</option>`).join('')}</select></label><label>Прессинг<select name="press">${options([['low','Низкий'],['medium','Средний'],['high','Высокий']],value.press)}</select></label><label>Ширина<select name="width">${options([['compact','Компактная'],['balanced','Сбалансированная'],['wide','Широкая']],value.width)}</select></label><label>Стиль атаки<select name="attack">${options([['balanced','Сбалансированный'],['possession','Контроль мяча'],['direct','Вертикальная игра']],value.attack)}</select></label><label>Замены и новая роль<textarea name="substitution" rows="2" maxlength="1000" placeholder="Кого выпустить и какую задачу он решит?">${e(value.substitution)}</textarea></label></div></div><label class="rationale">Объясните решение <span class="muted">— минимум 40 слов</span><textarea name="rationale" rows="5" maxlength="5000" placeholder="Укажите сигнал, роли игроков, страховку и запасной план…">${e(value.rationale)}</textarea></label>`;
}
function options(values, current) {return values.map(([v,t])=>`<option value="${v}" ${v===current?'selected':''}>${t}</option>`).join('');}
export function bindBoard(container,value,onChange = ()=>{}) {
  const pitch = container.querySelector('.interactive');
  const move = (button,x,y) => {
    const index = Number(button.dataset.player);
    value.players[index] = [Math.round(Math.max(5,Math.min(95,x))), Math.round(Math.max(6,Math.min(94,y)))];
    button.style.left = value.players[index][0]+'%';button.style.top = value.players[index][1]+'%';onChange(value);
  };
  pitch.querySelectorAll('[data-player]').forEach(button=>{
    button.onpointerdown = ev => { button.setPointerCapture(ev.pointerId);button.dataset.drag='true'; };
    button.onpointerup = ()=>delete button.dataset.drag;
    button.onpointercancel = ()=>delete button.dataset.drag;
    button.onpointermove = ev => {if(!button.dataset.drag)return; const r=pitch.getBoundingClientRect();move(button,(ev.clientX-r.left)/r.width*100,(ev.clientY-r.top)/r.height*100);};
    button.onkeydown = ev => {const deltas={ArrowLeft:[-2,0],ArrowRight:[2,0],ArrowUp:[0,-2],ArrowDown:[0,2]};if(!deltas[ev.key])return;ev.preventDefault();const p=value.players[Number(button.dataset.player)];move(button,p[0]+deltas[ev.key][0],p[1]+deltas[ev.key][1]);};
  });
  for (const field of ['press','width','attack','rationale','substitution']) container.querySelector(`[name="${field}"]`).oninput=ev=>{value[field]=ev.target.value;onChange(value);};
  container.querySelector('[name="formation"]').onchange=ev=>{
    value.formation=ev.target.value;value.players=structuredClone(formations[value.formation]);
    pitch.querySelectorAll('[data-player]').forEach((button,i)=>{button.style.left=value.players[i][0]+'%';button.style.top=value.players[i][1]+'%';});onChange(value);
  };
}

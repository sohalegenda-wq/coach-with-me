export const escapeHTML = (value = '') => String(value).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
export const formatDate = value => value ? new Intl.DateTimeFormat('ru', {dateStyle:'medium'}).format(new Date(value)) : '—';
export const words = text => String(text || '').trim().split(/\s+/u).filter(Boolean).length;
export function evaluatePractice(state, criteria) {
  return [
    { label: 'Интенсивность прессинга соответствует задаче', pass: state.press === criteria.press },
    { label: 'Ширина соответствует сценарию', pass: state.width === criteria.width },
    { label: 'Выбран подходящий стиль атаки', pass: state.attack === criteria.attack },
    { label: `Не менее ${criteria.minHigh} игроков в верхней трети поля`, pass: state.players?.length === 11 && state.players.filter(p => p[1] < 36).length >= criteria.minHigh },
    { label: 'Есть минимум 40 слов: триггер, роли, страховка и запасной план', pass: words(state.rationale) >= 40 },
    ...(criteria.substitution ? [{label:'Запланирована замена с объяснением роли',pass:words(state.substitution) >= 6}] : []),
  ];
}
export function safeReturnPath(value) { return /^#\/(dashboard|academy|lesson|tutor|practice|exams|profile)(\/[-a-z0-9]+)?$/.test(value || '') ? value : '#/dashboard'; }
export function quizResult(quiz, answers) { return quiz.reduce((n,q,i)=> n + (Number(answers[i]) === q.correct ? 1 : 0),0); }

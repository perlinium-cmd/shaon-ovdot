import { createStore } from './data.js';

/* =========================================================
   Helpers
   ========================================================= */
const $ = (sel, root = document) => root.querySelector(sel);
const pad = (n) => String(n).padStart(2, '0');
const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const icon = (name, cls = 'ic') => `<svg class="${cls}" aria-hidden="true"><use href="#i-${name}"/></svg>`;
const round2 = (n) => Math.round(n * 100) / 100;

const toDateStr = (d) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
const todayStr = () => toDateStr(new Date());
const yesterdayStr = () => { const d = new Date(); d.setDate(d.getDate() - 1); return toDateStr(d); };
const currentMonth = () => todayStr().slice(0, 7);
const parseDate = (s) => { const [y, m, d] = s.split('-').map(Number); return new Date(y, m - 1, d); };
const shiftMonthBy = (month, delta) => {
  const [y, m] = month.split('-').map(Number);
  const d = new Date(y, m - 1 + delta, 1);
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}`;
};

const fmtMonth = (month) => new Intl.DateTimeFormat('he-IL', { month: 'long', year: 'numeric' }).format(parseDate(`${month}-01`));
const fmtMonthName = (month) => new Intl.DateTimeFormat('he-IL', { month: 'long' }).format(parseDate(`${month}-01`));
const fmtWeekday = (date) => new Intl.DateTimeFormat('he-IL', { weekday: 'short' }).format(parseDate(date));
const fmtDayMonth = (date) => { const d = parseDate(date); return `${d.getDate()}/${d.getMonth() + 1}`; };

const toMin = (t) => { const [h, m] = t.split(':').map(Number); return h * 60 + m; };
/** Minutes worked. If out is earlier than in, the shift crosses midnight. */
const shiftMinutes = (tin, tout) => {
  if (!tin || !tout) return 0;
  let diff = toMin(tout) - toMin(tin);
  if (diff < 0) diff += 24 * 60;
  return diff;
};
/** Time range that always reads start-on-the-right (matches the form: כניסה on the right). */
const rng = (a, b) => `<span class="num" dir="rtl"><bdi>${fmtTime(a)}</bdi> – <bdi>${fmtTime(b)}</bdi></span>`;
const nowHHMM = () => { const d = new Date(); return `${pad(d.getHours())}:${pad(d.getMinutes())}`; };
/** When an open shift started (local time, ms). */
const clockStart = (c) => { const d = parseDate(c.date); const [h, m] = c.in.split(':').map(Number); d.setHours(h, m, 0, 0); return d.getTime(); };
/** An open shift longer than this was surely forgotten: ask for the real exit time instead of "now". */
const MAX_OPEN_MIN = 18 * 60;
const isOvernight = (tin, tout) => tin && tout && toMin(tout) < toMin(tin);
const fmtHM = (min) => `${Math.floor(min / 60)}:${pad(Math.round(min % 60))}`;
const fmtHours = (min) => {
  const h = min / 60;
  return h.toLocaleString('he-IL', { maximumFractionDigits: 2 });
};
const fmtMoney = (n) => {
  const v = round2(n || 0);
  return `${v.toLocaleString('he-IL', { minimumFractionDigits: Number.isInteger(v) ? 0 : 2, maximumFractionDigits: 2 })} ₪`;
};
const parseRate = (v) => {
  const s = String(v ?? '').trim().replace(',', '.');
  if (s === '') return null;
  const n = Number(s);
  return Number.isFinite(n) && n >= 0 ? round2(n) : NaN;
};

const avatarStyle = (name) => {
  let h = 0;
  for (const ch of name || '') h = (h * 31 + ch.charCodeAt(0)) % 360;
  const hue = [168, 200, 262, 330, 24, 45, 140, 290][h % 8];
  return `--av-bg: color-mix(in srgb, hsl(${hue} 65% 50%) 18%, var(--surface)); --av-fg: color-mix(in srgb, hsl(${hue} 60% 38%) 85%, var(--text));`;
};
/* ---------- Illustrated avatars (generated locally as SVG) ----------
   An avatar is stored as "av:" + one base-36 char per feature: skin, hairStyle, hairColor, eyes, mouth, background, shirt, accessory, outfit. */
const AV = {
  skin: ['#FFCC4D'], // the classic emoji yellow, for everyone
  hair: ['#2B1B12', '#5A3520', '#8B5A2B', '#C9A24B', '#B5432A', '#8E8E93', '#7B3FA0', '#E86A9A', '#3D6FD6', '#F2E6C9', '#14B8A6', '#D62839', '#F28C28', '#B39DDB', '#7FD1AE', '#1E2A5A', '#C2571A', '#3A2A20'],
  bg: ['#CFE8E4', '#DDE7FA', '#EBDDF6', '#FBDDE6', '#FDE7CC', '#FFF2B8', '#D9F0CF', '#E4E4EA', '#C9E4F5', '#F8D0C4', '#D7D2F0', '#C8EBD8',
    // bold, saturated backgrounds
    '#FF5A5F', '#FF8A00', '#FFD400', '#22C55E', '#06B6D4', '#2563EB', '#7C3AED', '#EC4899', '#1F2937', '#F8FAFC', '#84CC16', '#14B8A6',
    // gradients
    ['#FF9A8B', '#FF6A88'], ['#43E97B', '#38F9D7'], ['#4FACFE', '#8E2DE2'], ['#FDC830', '#F37335']],
  shirt: ['#0F766E', '#3B6FD6', '#B4479B', '#E0603E', '#E5A82E', '#4C4C60', '#7A4FD0', '#2A9D5B', '#D6396B', '#2B2B33', '#F59E0B', '#0EA5E9', '#EF4444', '#F472B6', '#F5F5F5', '#A3E635'],
  counts: [1, 20, 18, 10, 9, 28, 16, 13, 4],
};
const avatarArt = (code) => {
  const [sk, hs, hc, ey, mo, bg, sh, ac, ou] = AV.counts.map((c, i) => (parseInt(code[3 + i], 36) || 0) % c);
  const skin = AV.skin[sk], hair = AV.hair[hc], shirt = AV.shirt[sh];
  const scarf = AV.shirt[(hc + 2) % AV.shirt.length];
  const cap = `<path d="M19 31C18 12 46 12 45 31C42 23 36 19 32 19C27 19 21 23 19 31Z" fill="${hair}"/>`;
  let back = '', front = cap, face = { rx: 13, ry: 15 };
  switch (hs) {
    case 0: back = `<path d="M17 32C15 10 49 10 47 32L50 58L14 58Z" fill="${hair}"/>`; break;
    case 1: back = `<path d="M17 30C16 10 48 10 47 30L47 42Q47 47 42 47L22 47Q17 47 17 42Z" fill="${hair}"/>`; break;
    case 2: back = `<circle cx="32" cy="11" r="6.5" fill="${hair}"/>`; break;
    case 3: back = [[18, 26], [17, 34], [46, 26], [47, 34], [22, 15], [32, 12], [42, 15]].map(([x, y]) => `<circle cx="${x}" cy="${y}" r="6.5" fill="${hair}"/>`).join('');
      front = cap + [[24, 17], [32, 15], [40, 17]].map(([x, y]) => `<circle cx="${x}" cy="${y}" r="5" fill="${hair}"/>`).join(''); break;
    case 4: back = `<path d="M43 22Q60 24 55 46Q51 34 44 33Z" fill="${hair}"/>`; break;
    case 5: front = `<path d="M18 33C15 10 49 10 46 33C44 26 40 22 36 21C30 25 22 24 19 33Z" fill="${hair}"/>`; break;
    case 6: back = `<path d="M17 32C15 10 49 10 47 32L50 58L14 58Z" fill="${hair}"/>`;
      front = `<path d="M18 32C16 11 48 11 46 32L45 27C38 28 31 24 27 18C23 22 20 26 19 32Z" fill="${hair}"/>`; break;
    case 11: back = `<ellipse cx="15.5" cy="24" rx="5" ry="9" transform="rotate(20 15.5 24)" fill="${hair}"/><ellipse cx="48.5" cy="24" rx="5" ry="9" transform="rotate(-20 48.5 24)" fill="${hair}"/>`; break;
    case 12: back = `<path d="M16 30C12 20 15 12 32 10C49 12 52 20 48 30C52 38 46 44 50 58L14 58C18 44 12 38 16 30Z" fill="${hair}"/>`; break;
    case 13: back = ''; front = `<path d="M17.5 30C15 9 49 9 46.5 30C40 24 24 24 17.5 30Z" fill="${scarf}"/><path d="M20 24C28 17 38 17 44 23" stroke="#fff" stroke-opacity=".35" stroke-width="2" fill="none"/><path d="M40 14Q49 13 47 22Q42 22 40 14Z" fill="${scarf}"/>`; break;
    case 14: back = '';
      front = cap + `<path d="M18 27C17 9 47 9 46 27Z" fill="${scarf}"/><rect x="16.5" y="25" width="31" height="5.5" rx="2.7" fill="${scarf}"/><rect x="16.5" y="25" width="31" height="5.5" rx="2.7" fill="#000" opacity=".12"/><circle cx="32" cy="9.5" r="4" fill="${scarf}"/>`; break;
    case 15: back = `<path d="M17 32C15 10 49 10 47 32L50 58L14 58Z" fill="${hair}"/>`;
      front = `<path d="M32 17C22 17 18 26 19 34L23 28C26 22 29 19 32 17Z M32 17C42 17 46 26 45 34L41 28C38 22 35 19 32 17Z" fill="${hair}"/><path d="M19 32C18 14 46 14 45 32C44 24 38 17 32 17C26 17 20 24 19 32Z" fill="${hair}"/>`; break;
    case 16: back = `<circle cx="32" cy="10.5" r="6.5" fill="${hair}"/>`;
      front = `<path d="M18 32C16 11 48 11 46 32L45 27C38 28 31 24 27 18C23 22 20 26 19 32Z" fill="${hair}"/>`; break;
    case 17: front = cap + [[21, 21], [26, 17], [32, 15.5], [38, 17], [43, 21], [19.5, 27], [44.5, 27]].map(([x, y]) => `<circle cx="${x}" cy="${y}" r="4" fill="${hair}"/>`).join(''); break;
    case 18: back = `<path d="M17 32C15 10 49 10 47 32L47 44L17 44Z" fill="${hair}"/><path d="M42 34Q54 42 45 60" stroke="${hair}" stroke-width="6.5" fill="none" stroke-linecap="round"/><circle cx="44.5" cy="58" r="2" fill="#E86A9A"/>`; break;
    case 19: back = `<path d="M17 30C16 10 48 10 47 30L47 42Q47 47 42 47L22 47Q17 47 17 42Z" fill="${hair}"/>`;
      front = `<path d="M18 30C17 11 47 11 46 30L46 25C38 22 26 22 18 25Z" fill="${hair}"/>`; break;
    case 8: back = ['M19 30Q13 44 18 57', 'M45 30Q51 44 46 57'].map((p) => `<path d="${p}" stroke="${hair}" stroke-width="6.5" fill="none" stroke-linecap="round"/>`).join(''); break;
    case 9: back = `<circle cx="32" cy="23" r="21" fill="${hair}"/>`; break;
    case 10: back = `<circle cx="20" cy="12" r="6.5" fill="${hair}"/><circle cx="44" cy="12" r="6.5" fill="${hair}"/>`; break;
    default: // 7: headscarf
      back = `<path d="M11 60C9 22 19 8 32 8C45 8 55 22 53 60Z" fill="${scarf}"/>`; front = '';
      face = { rx: 11, ry: 13.5 };
  }
  const eyes = [
    `<circle cx="26.5" cy="31" r="1.7" fill="#2b2b33"/><circle cx="37.5" cy="31" r="1.7" fill="#2b2b33"/>`,
    `<path d="M24 31.5Q26.5 28.3 29 31.5M35 31.5Q37.5 28.3 40 31.5" stroke="#2b2b33" stroke-width="1.6" fill="none" stroke-linecap="round"/>`,
    `<circle cx="26.5" cy="31" r="1.7" fill="#2b2b33"/><circle cx="37.5" cy="31" r="1.7" fill="#2b2b33"/><path d="M23.5 29.5l-1.5-1.2M25 28.5l-.5-1.6M40.5 29.5l1.5-1.2M39 28.5l.5-1.6" stroke="#2b2b33" stroke-width="1.1" stroke-linecap="round"/>`,
    `<circle cx="26.5" cy="31" r="2.6" fill="#2b2b33"/><circle cx="37.5" cy="31" r="2.6" fill="#2b2b33"/><circle cx="27.4" cy="30.1" r=".9" fill="#fff"/><circle cx="38.4" cy="30.1" r=".9" fill="#fff"/>`,
    `<circle cx="26.5" cy="31" r="1.7" fill="#2b2b33"/><path d="M35 31.5Q37.5 28.3 40 31.5" stroke="#2b2b33" stroke-width="1.6" fill="none" stroke-linecap="round"/>`,
    `<path d="M24.5 31.2H28.5M35.5 31.2H39.5" stroke="#2b2b33" stroke-width="1.7" stroke-linecap="round"/>`,
    `<circle cx="26.5" cy="31" r="3.4" fill="#fff" stroke="#2b2b33" stroke-width="1"/><circle cx="37.5" cy="31" r="3.4" fill="#fff" stroke="#2b2b33" stroke-width="1"/><circle cx="26.5" cy="31.3" r="1.7" fill="#2b2b33"/><circle cx="37.5" cy="31.3" r="1.7" fill="#2b2b33"/>`,
    `<path d="M26.5 33.3C22.5 30.6 24.2 27.8 26.5 29.6C28.8 27.8 30.5 30.6 26.5 33.3ZM37.5 33.3C33.5 30.6 35.2 27.8 37.5 29.6C39.8 27.8 41.5 30.6 37.5 33.3Z" fill="#E5384F"/>`,
    `<path d="M24 30.5Q26.5 33.5 29 30.5M35 30.5Q37.5 33.5 40 30.5" stroke="#2b2b33" stroke-width="1.6" fill="none" stroke-linecap="round"/>`,
    `<circle cx="26.5" cy="31.5" r="1.7" fill="#2b2b33"/><circle cx="37.5" cy="31.5" r="1.7" fill="#2b2b33"/><path d="M23.5 26.8Q26.5 24.8 29.5 26.4M34.5 26.4Q37.5 24.8 40.5 26.8" stroke="#2b2b33" stroke-width="1.3" fill="none" stroke-linecap="round"/>`,
  ][ey];
  const mouth = [
    `<path d="M27 38Q32 43 37 38" stroke="#8a3b3b" stroke-width="1.6" fill="none" stroke-linecap="round"/>`,
    `<path d="M27 38Q32 47 37 38Z" fill="#8a3b3b"/>`,
    `<path d="M29.5 39.5Q32 41.5 34.5 39.5" stroke="#8a3b3b" stroke-width="1.6" fill="none" stroke-linecap="round"/>`,
    `<path d="M28 39.5Q33 42.5 37 38.5" stroke="#8a3b3b" stroke-width="1.6" fill="none" stroke-linecap="round"/>`,
    `<path d="M27.5 38Q32 46 36.5 38Z" fill="#8a3b3b"/><path d="M30 41.6Q32 46 34 41.6Z" fill="#ff7a8a"/>`,
    `<path d="M27 38Q32 46 37 38Z" fill="#8a3b3b"/><path d="M27.6 38.2L36.4 38.2Q32 40.8 27.6 38.2Z" fill="#fff"/>`,
    `<ellipse cx="32" cy="40.2" rx="2.4" ry="3" fill="#8a3b3b"/>`,
    `<path d="M29 40H35" stroke="#8a3b3b" stroke-width="1.7" stroke-linecap="round"/>`,
    `<path d="M25.5 37.3Q32 50 38.5 37.3Z" fill="#8a3b3b"/><path d="M28.5 43.5Q32 41 35.5 43.5Q32 47 28.5 43.5Z" fill="#ff7a8a"/>`,
  ][mo];
  const acc = [
    '',
    `<g fill="none" stroke="#33333d" stroke-width="1.3"><circle cx="26.5" cy="31" r="4.8"/><circle cx="37.5" cy="31" r="4.8"/><path d="M31.3 31h1.4"/></g>`,
    `<g fill="#23232b"><rect x="21" y="28" width="10.5" height="6.5" rx="3"/><rect x="32.5" y="28" width="10.5" height="6.5" rx="3"/><rect x="31" y="29.5" width="2" height="1.4"/></g>`,
    `<circle cx="${face.rx > 12 ? 18.6 : 20.6}" cy="38" r="1.7" fill="#E5A82E"/><circle cx="${face.rx > 12 ? 45.4 : 43.4}" cy="38" r="1.7" fill="#E5A82E"/>`,
    `<g transform="translate(41 19)">${[0, 72, 144, 216, 288].map((r) => `<ellipse cx="0" cy="-3" rx="2" ry="2.8" fill="#FF7FA8" transform="rotate(${r})"/>`).join('')}<circle r="1.7" fill="#FFD84A"/></g>`,
    `<path d="M19 27C22 15 42 15 45 27" stroke="#E86A9A" stroke-width="2.6" fill="none" stroke-linecap="round"/>`,
    `<g transform="translate(40 17)"><path d="M0 0L-7-4.5V4.5ZM0 0L7-4.5V4.5Z" fill="#E5384F"/><circle r="2" fill="#B81F36"/></g>`,
    `<path d="M18 30C16 6 48 6 46 30" stroke="#33333d" stroke-width="2.4" fill="none"/><rect x="14.5" y="27" width="5" height="10" rx="2.5" fill="#E5384F"/><rect x="44.5" y="27" width="5" height="10" rx="2.5" fill="#E5384F"/>`,
    `<g fill="#B5712F" opacity=".7">${[[24, 35], [26.5, 36.6], [28.5, 34.8], [35.5, 34.8], [37.5, 36.6], [40, 35]].map(([x, y]) => `<circle cx="${x}" cy="${y}" r=".7"/>`).join('')}</g>`,
    `<g fill="#FF5C8A" stroke="#33333d" stroke-width="1"><path d="M26.5 35.5C20 31.5 22 26.5 26.5 29C31 26.5 33 31.5 26.5 35.5Z"/><path d="M37.5 35.5C31 31.5 33 26.5 37.5 29C42 26.5 44 31.5 37.5 35.5Z"/></g>`,
    `<g fill="none" stroke="#E5A82E" stroke-width="1.5"><circle cx="${face.rx > 12 ? 18.6 : 20.6}" cy="40.5" r="3"/><circle cx="${face.rx > 12 ? 45.4 : 43.4}" cy="40.5" r="3"/></g>`,
    `<path d="M22 20L24 12L28 17L32 10L36 17L40 12L42 20Z" fill="#FFD84A" stroke="#E5A82E" stroke-width="1" stroke-linejoin="round"/>`,
    `<path d="M40 13.5L41.4 16.6L44.8 17L42.3 19.3L43 22.6L40 20.9L37 22.6L37.7 19.3L35.2 17L38.6 16.6Z" fill="#FFD84A" stroke="#E5A82E" stroke-width=".8" stroke-linejoin="round"/>`,
  ][ac];
  return `<svg viewBox="0 0 64 64" width="100%" height="100%" aria-hidden="true">
    ${Array.isArray(AV.bg[bg])
      ? `<defs><linearGradient id="avg${bg}" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="${AV.bg[bg][0]}"/><stop offset="1" stop-color="${AV.bg[bg][1]}"/></linearGradient></defs><rect width="64" height="64" fill="url(#avg${bg})"/>`
      : `<rect width="64" height="64" fill="${AV.bg[bg]}"/>`}
    <clipPath id="avc"><path d="M8 66C8 53 18 48 32 48C46 48 56 53 56 66Z"/></clipPath>
    <path d="M8 66C8 53 18 48 32 48C46 48 56 53 56 66Z" fill="${shirt}"/>
    ${[
      '',
      `<path d="M25.5 48L32 58L38.5 48Z" fill="${skin}"/>`,
      `<g clip-path="url(#avc)" stroke="#fff" stroke-opacity=".4" stroke-width="2.2"><path d="M0 54H64M0 59H64M0 64H64"/></g>`,
      `<path d="M26 48.2L32 55L28 56.5L23.5 50Z M38 48.2L32 55L36 56.5L40.5 50Z" fill="#fff"/><path d="M26 48.2L32 55L38 48.2" fill="none" stroke="#000" stroke-opacity=".12" stroke-width=".8"/>`,
    ][ou]}
    ${back}
    <rect x="27.5" y="39" width="9" height="11" rx="3" fill="${skin}"/><rect x="27.5" y="39" width="9" height="4" fill="#000" opacity=".1"/>
    <ellipse cx="32" cy="30" rx="${face.rx}" ry="${face.ry}" fill="${skin}"/>
    <circle cx="23.5" cy="36.5" r="2.6" fill="#ff7a8a" opacity=".3"/><circle cx="40.5" cy="36.5" r="2.6" fill="#ff7a8a" opacity=".3"/>
    ${eyes}${mouth}${front}${acc}
  </svg>`;
};
const randomAvatar = () => 'av:' + AV.counts.map((n) => Math.floor(Math.random() * n).toString(36)).join('');

const EMOJIS = {
  'חיות': '🐶🐱🐭🐹🐰🦊🐻🐼🐨🐯🦁🐮🐷🐸🐵🐔🐧🐦🐤🦆🦉🦄🐝🦋🐌🐞🐢🐍🐙🦑🦀🐠🐬🐳🦈🐘🦒🦓🐪🦘🦔🦦🦥🦜🦩🐺🐗🐴🦇🦎🐡🦭',
  'פנים': '😀😃😄😁😆😊😇🙂😉😍🥰😎🤩🥳😜🤗🤓🥹😌😴🤠🥸😺😸😻👻👽🤖🎃🤡🧚🧜🦸🧙',
  'טבע': '🌸🌻🌹🌷🌼🍀🌿🌵🌴🌳🍁🍄🌈🌙⭐🌟✨⚡🔥💧🌊❄️☀️☁️🌍🪐🌺🪻',
  'אוכל': '🍎🍊🍋🍌🍉🍇🍓🍒🍑🥭🍍🥝🥑🍅🥕🌽🍕🍔🍟🌮🍩🍪🎂🧁🍫🍿🍦🍭☕🧋🥐🍯',
  'חפצים': '🎈🎨🎵🎸🎧📚✏️💎👑🎀🧸🎁🚀✈️⚽🏀🎯🎮🧩🔮🕶️💼🪴🧿🎹🎷🎺🎬📷🔭🧵🛼🚲⛵',
  'לבבות': '❤️🧡💛💚💙💜🩷🖤🤍🤎💖💝💫🎉🏆🥇🌠',
};
const ALL_EMOJIS = Object.values(EMOJIS).flatMap((g) => [...new Intl.Segmenter('he', { granularity: 'grapheme' }).segment(g)].map((x) => x.segment));
const emojiList = (cat) => [...new Intl.Segmenter('he', { granularity: 'grapheme' }).segment(EMOJIS[cat])].map((x) => x.segment);
/** `who` is an employee ({name, avatar}): drawn avatar, legacy emoji, or the first letter when nothing was picked. */
const avatar = (who, cls = '') => {
  const name = who?.name || '';
  const a = who?.avatar;
  if (a?.startsWith('av:')) return `<span class="avatar art ${cls}" aria-hidden="true">${avatarArt(a)}</span>`;
  const glyph = a || (name || '?').trim().charAt(0);
  return `<span class="avatar ${a ? 'emoji ' : ''}${cls}" style="${avatarStyle(a || name)}" aria-hidden="true">${esc(glyph)}</span>`;
};

/* ---------- Time format (24h / AM-PM) ---------- */
const is12 = () => (state.settings?.timeFormat || lsGet('timeFormat') || '24') === '12';
/** "HH:MM" (stored, 24h) → text in the chosen format. */
function fmtTime(t) {
  if (!t) return '';
  if (!is12()) return t;
  const [h, m] = t.split(':').map(Number);
  return `${h % 12 || 12}:${pad(m)} ${h < 12 ? 'AM' : 'PM'}`;
}
/** Parse typed digits ("8", "830", "0830", "8:30") → "HH:MM"; '' if empty, null if invalid.
 *  In AM/PM mode hours 1–12 use the given ampm; 0 or 13–23 are read as 24h. */
function parseTyped(text, ampm) {
  const d = String(text).replace(/\D/g, '').slice(0, 4);
  if (!d) return '';
  let h; let m;
  if (d.length <= 2) { h = +d; m = 0; } else if (d.length === 3) { h = +d[0]; m = +d.slice(1); } else { h = +d.slice(0, 2); m = +d.slice(2); }
  if (h > 23 || m > 59) return null;
  if (ampm && h >= 1 && h <= 12) h = (h % 12) + (ampm === 'PM' ? 12 : 0);
  return `${pad(h)}:${pad(m)}`;
}
const fmtToggleHTML = (lg = false) => `
  <div class="seg ${lg ? 'lg' : ''}" role="radiogroup" aria-label="תצוגת שעה">
    <button type="button" role="radio" data-fmt="24" aria-checked="${!is12()}">${lg ? '24 שעות (14:30)' : '24h'}</button>
    <button type="button" role="radio" data-fmt="12" aria-checked="${is12()}">${lg ? 'AM/PM (2:30 PM)' : 'AM/PM'}</button>
  </div>`;
const timeFieldHTML = (key, label) => `
  <div class="field">
    <label for="f-${key}">${label}</label>
    <div class="tfield">
      <input id="f-${key}" class="tfield-input" inputmode="numeric" autocomplete="off" maxlength="5" placeholder="${is12() ? '8:00' : '08:00'}">
      ${is12() ? `<button type="button" class="ampm" data-ampm="${key}" aria-label="החלפה בין AM ל-PM"></button>` : ''}
      <button type="button" class="wheel-btn" data-wheel="${key}" aria-label="בחירת שעת ${label} בגלגלת">${icon('clock')}</button>
    </div>
  </div>`;

const lsGet = (k) => { try { return localStorage.getItem(k); } catch { return null; } };
const lsSet = (k, v) => { try { localStorage.setItem(k, v); } catch { /* ignore */ } };
const lsDel = (k) => { try { localStorage.removeItem(k); } catch { /* ignore */ } };

/* =========================================================
   State
   ========================================================= */
const state = {
  store: null,
  user: null,
  settings: null, // null until loaded
  employees: null, // null until loaded
  shifts: null, // shifts of state.month; null until loaded
  clocks: {}, // open shifts (clocked in, no exit yet): empId → {date, in, note, special}
  month: sessionStorage.getItem('month') || currentMonth(),
};
let unsubs = [];
let unsubShifts = null;
let mounted = { key: null, view: null };

const effRate = (emp) => (emp && emp.rate != null ? emp.rate : (state.settings?.defaultRate ?? 0));
const shiftRate = (s, emp) => (s.rate != null ? s.rate : effRate(emp));
const empById = (id) => state.employees?.find((e) => e.id === id);
const sortShifts = (list) => [...list].sort((a, b) => (b.date.localeCompare(a.date)) || (b.in.localeCompare(a.in)));

/** Minutes of a shift paid at its special rate (all of it, or only `special.hours`). */
function specialMinutes(s) {
  if (!s.special || s.special.rate == null) return 0;
  const min = shiftMinutes(s.in, s.out);
  return s.special.hours == null ? min : Math.min(min, s.special.hours * 60);
}
/** Pay for one shift: regular rate, with an optional special hourly amount for all/part of it. */
function shiftPay(s, emp) {
  const min = shiftMinutes(s.in, s.out);
  const spMin = specialMinutes(s);
  return ((min - spMin) / 60) * shiftRate(s, emp) + (spMin / 60) * (s.special?.rate ?? 0);
}

function monthAgg() { return aggOf(state.shifts || []); }
/** Per-employee totals for any list of shifts: Map(empId → {shifts, minutes, pay, paidPay, paidCount}). */
function aggOf(list) {
  const map = new Map();
  for (const s of list) {
    const pay = shiftPay(s, empById(s.empId));
    const a = map.get(s.empId) || emptyAgg();
    a.shifts.push(s); a.minutes += shiftMinutes(s.in, s.out); a.pay += pay;
    if (s.paid) { a.paidPay += pay; a.paidCount += 1; }
    map.set(s.empId, a);
  }
  return map;
}
function emptyAgg() { return { shifts: [], minutes: 0, pay: 0, paidPay: 0, paidCount: 0 }; }
const unpaidOf = (a) => round2(a.pay - a.paidPay);
const nShifts = (n) => (n === 1 ? 'משמרת אחת' : `${n} משמרות`);
const byName = (a, b) => a.name.localeCompare(b.name, 'he');

/* =========================================================
   UI primitives: toast, sheet, confirm
   ========================================================= */
let toastTimer;
function toast(msg, { error = false, undo = null } = {}) {
  const el = $('#toast');
  el.innerHTML = `${icon(error ? 'alert' : 'check')}<span>${esc(msg)}</span>${undo ? '<button type="button" class="toast-undo">בטל</button>' : ''}`;
  el.classList.toggle('error', error);
  el.classList.toggle('has-action', !!undo);
  el.classList.add('show');
  clearTimeout(toastTimer);
  if (undo) {
    el.querySelector('.toast-undo').addEventListener('click', async () => {
      clearTimeout(toastTimer);
      el.classList.remove('show');
      try { await undo(); toast('הפעולה בוטלה'); } catch (e) { fail(e); }
    }, { once: true });
  }
  toastTimer = setTimeout(() => el.classList.remove('show'), undo ? 6000 : error ? 4000 : 2200);
}
const fail = (e) => { console.error(e); toast('משהו השתבש, נסה שוב', { error: true }); };

/** Run a change and offer "בטל" for a few seconds: puts back the given docs ({col, id})
 *  exactly as they were, and removes docs the action created (it returns them as [{col, id}]). */
async function withUndo(message, refs, action) {
  const snaps = await state.store.snapshot(refs);
  const created = (await action()) || [];
  toast(message, { undo: () => state.store.restore([...snaps, ...created.map((c) => ({ ...c, data: null }))]) });
}

/* ---------- Payments ---------- */
const PAY_METHODS = ['מזומן', 'העברה בנקאית', 'ביט', 'פייבוקס', 'צ׳ק', 'אחר'];
const lastMethod = () => lsGet('payMethod') || 'מזומן';
const fmtDate = (date) => { const d = parseDate(date); return `${d.getDate()}/${d.getMonth() + 1}/${d.getFullYear()}`; };
const shiftRefs = (sh) => [{ col: 'shifts', id: sh.id }, ...(sh.paymentId ? [{ col: 'payments', id: sh.paymentId }] : [])];
/** Mark shifts as paid and record them as one payment. Returns the created payment ref (for undo). */
async function payShifts(emp, list, { method = lastMethod(), date = todayStr() } = {}) {
  const amount = round2(list.reduce((t, sh) => t + shiftPay(sh, emp), 0));
  const ref = await state.store.addPayment({ empId: emp.id, date, amount, method, shiftIds: list.map((sh) => sh.id) });
  await state.store.updateShifts(list.map((sh) => sh.id), { paid: true, paidAt: Date.now(), paymentId: ref.id });
  lsSet('payMethod', method);
  return [{ col: 'payments', id: ref.id }];
}
/** Remove the "paid" mark of one shift and take it out of its payment record. */
async function unpayShift(sh, emp, payments) {
  const p = sh.paymentId && payments.find((x) => x.id === sh.paymentId);
  if (p) {
    const ids = (p.shiftIds || []).filter((x) => x !== sh.id);
    if (ids.length) await state.store.updatePayment(p.id, { shiftIds: ids, amount: round2(Math.max(0, p.amount - shiftPay(sh, emp))) });
    else await state.store.deletePayment(p.id);
  }
  await state.store.updateShifts([sh.id], { paid: false, paidAt: null, paymentId: null });
}
const methodPicker = (cur) => `
  <div class="chips" role="radiogroup" aria-label="אמצעי תשלום">
    ${PAY_METHODS.map((m) => `<button type="button" class="chip" role="radio" data-method="${m}" aria-checked="${m === cur}" aria-pressed="${m === cur}">${m}</button>`).join('')}
  </div>`;
function wireMethodPicker(root) {
  root.querySelectorAll('[data-method]').forEach((b) => b.addEventListener('click', () => {
    root.querySelectorAll('[data-method]').forEach((x) => { x.setAttribute('aria-pressed', String(x === b)); x.setAttribute('aria-checked', String(x === b)); });
  }));
}
const pickedMethod = (root) => root.querySelector('[data-method][aria-pressed="true"]')?.dataset.method || lastMethod();

/** Sheet: pay several shifts at once (choose method + date). */
function paySheet(emp, list) {
  const sum = list.reduce((t, sh) => t + shiftPay(sh, emp), 0);
  openSheet(`
    <div class="sheet-head">
      <h2 id="sheet-title">תשלום ל${esc(emp.name)}</h2>
      <button type="button" class="icon-btn" data-close aria-label="סגירה">${icon('x')}</button>
    </div>
    <div class="pay-summary"><span>${nShifts(list.length)} ב${esc(fmtMonthName(state.month))}</span><b class="num">${fmtMoney(sum)}</b></div>
    <div class="field"><span class="field-label">איך שולם?</span>${methodPicker(lastMethod())}</div>
    <div class="field"><label for="pay-date">תאריך התשלום</label><input type="date" id="pay-date" class="input input-date" value="${todayStr()}"></div>
    <div class="sheet-actions"><button type="submit" class="btn btn-primary btn-lg">${icon('check')}סימון כשולם</button></div>
  `, async (form) => {
    const method = pickedMethod(form);
    const date = $('#pay-date').value || todayStr();
    await withUndo(`שולם ${fmtMoney(sum)} · ${method}`, list.map((sh) => ({ col: 'shifts', id: sh.id })), () => payShifts(emp, list, { method, date }));
    return true;
  });
  wireMethodPicker(sheet);
}

/** Sheet: edit or delete an existing payment. */
function paymentSheet(p, emp) {
  openSheet(`
    <div class="sheet-head">
      <h2 id="sheet-title">תשלום של ${fmtMoney(p.amount)}</h2>
      <button type="button" class="icon-btn" data-close aria-label="סגירה">${icon('x')}</button>
    </div>
    <p class="muted">${nShifts(p.shiftIds?.length || 0)} · ${esc(emp.name)}</p>
    <div class="field"><span class="field-label">איך שולם?</span>${methodPicker(p.method)}</div>
    <div class="field"><label for="pay-date">תאריך התשלום</label><input type="date" id="pay-date" class="input input-date" value="${p.date}"></div>
    <div class="sheet-actions"><button type="submit" class="btn btn-primary btn-lg">שמירה</button></div>
    <button type="submit" value="delete" class="btn btn-danger-ghost">${icon('trash')}מחיקת התשלום (המשמרות יסומנו כלא שולמו)</button>
  `, async (form, submitter) => {
    const ids = p.shiftIds || [];
    if (submitter?.value === 'delete') {
      await withUndo('התשלום נמחק', [{ col: 'payments', id: p.id }, ...ids.map((id) => ({ col: 'shifts', id }))], async () => {
        if (ids.length) await state.store.updateShifts(ids, { paid: false, paidAt: null, paymentId: null });
        await state.store.deletePayment(p.id);
      });
      return true;
    }
    const method = pickedMethod(form);
    await withUndo('התשלום עודכן', [{ col: 'payments', id: p.id }], () => state.store.updatePayment(p.id, { method, date: $('#pay-date').value || p.date }));
    return true;
  });
  wireMethodPicker(sheet);
}

const sheet = $('#sheet');
function openSheet(html, onSubmit) {
  sheet.innerHTML = `<div class="grabber" aria-hidden="true"></div><form method="dialog" novalidate>${html}</form>`;
  const form = sheet.querySelector('form');
  form.addEventListener('submit', async (ev) => {
    ev.preventDefault();
    const btn = ev.submitter?.value === 'cancel' ? null : form.querySelector('[type=submit]');
    if (ev.submitter?.value === 'cancel') return sheet.close();
    btn?.classList.add('is-loading'); if (btn) btn.disabled = true;
    try {
      const ok = await onSubmit(form, ev.submitter);
      if (ok !== false) sheet.close();
    } catch (e) { fail(e); } finally {
      btn?.classList.remove('is-loading'); if (btn) btn.disabled = false;
    }
  });
  sheet.querySelectorAll('[data-close]').forEach((b) => b.addEventListener('click', () => sheet.close()));
  sheet.showModal();
  const first = form.querySelector('input:not([type=checkbox])');
  if (first && matchMedia('(pointer: fine)').matches) first.focus();
  return form;
}
sheet.addEventListener('click', (e) => { if (e.target === sheet) sheet.close(); }); // backdrop click

function confirmSheet({ title, text, okLabel, danger = true }) {
  return new Promise((resolve) => {
    openSheet(`
      <div class="sheet-head"><h2 id="sheet-title">${esc(title)}</h2></div>
      <p>${text}</p>
      <div class="sheet-actions">
        <button type="submit" class="btn ${danger ? 'btn-danger' : 'btn-primary'} btn-lg">${esc(okLabel)}</button>
        <button type="submit" value="cancel" class="btn btn-secondary btn-lg">ביטול</button>
      </div>`, () => { sheet.removeEventListener('close', onClose); resolve(true); });
    // cancel / Esc / backdrop. A late 'close' from the previous sheet arrives while this one is open — ignore it.
    const onClose = () => {
      if (sheet.open) return;
      sheet.removeEventListener('close', onClose);
      resolve(false);
    };
    sheet.addEventListener('close', onClose);
  });
}

/* =========================================================
   Employee add / edit sheet
   ========================================================= */
function employeeSheet(emp = null) {
  const isNew = !emp;
  const agg = emp ? (monthAgg().get(emp.id) || emptyAgg()) : emptyAgg();
  const def = state.settings?.defaultRate ?? 0;
  const startAvatar = emp?.avatar || randomAvatar();
  openSheet(`
    <div class="sheet-head">
      <h2 id="sheet-title">${isNew ? 'עובדת חדשה' : 'עריכת פרטים'}</h2>
      <button type="button" class="icon-btn" data-close aria-label="סגירה">${icon('x')}</button>
    </div>
    <div class="field avatar-field">
      <button type="button" class="av-edit" id="av-toggle" aria-expanded="false" aria-controls="av-panel" aria-label="החלפת אוואטר">
        <span id="av-preview">${avatar({ name: emp?.name, avatar: startAvatar }, 'xl')}</span>
        <span class="av-pencil" aria-hidden="true">${icon('pencil')}</span>
      </button>
      <input type="hidden" name="avatar" value="${esc(startAvatar)}">
      <div id="av-panel" hidden>
        <button type="button" class="btn btn-secondary btn-block" id="av-random">${icon('repeat')}הגרלה</button>
        <div class="seg" id="av-tabs" role="tablist">
          <button type="button" role="tab" data-mode="art">אוואטרים</button>
          <button type="button" role="tab" data-mode="emoji">אימוג'ים</button>
        </div>
        <div class="em-cats" id="em-cats" hidden>${Object.keys(EMOJIS).map((c) => `<button type="button" data-cat="${c}">${c}</button>`).join('')}</div>
        <div class="avatar-grid" id="av-grid" role="radiogroup" aria-label="בחירת אוואטר"></div>
      </div>
    </div>
    <div class="field">
      <label for="f-name">שם</label>
      <input id="f-name" name="name" class="input" autocomplete="off" required value="${esc(emp?.name || '')}" placeholder="לדוגמה: דנה">
      <p class="field-error" id="err-name"></p>
    </div>
    <div class="field">
      <label for="f-rate">תעריף שעתי אישי <span class="muted">(לא חובה)</span></label>
      <div class="input-wrap">
        <input id="f-rate" name="rate" class="input num" inputmode="decimal" autocomplete="off" value="${emp?.rate ?? ''}" placeholder="${def}">
        <span class="input-suffix">₪</span>
      </div>
      <p class="field-hint">השאר ריק כדי להשתמש בתעריף הכללי (${fmtMoney(def)} לשעה).</p>
      <p class="field-error" id="err-rate"></p>
    </div>
    ${!isNew && agg.shifts.length ? `
    <label class="check" id="apply-wrap" hidden>
      <input type="checkbox" name="apply" checked>
      <span>לעדכן את התעריף גם ב-${agg.shifts.length} המשמרות של ${esc(fmtMonth(state.month))}</span>
    </label>` : ''}
    <div class="sheet-actions">
      <button type="submit" class="btn btn-primary btn-lg">${isNew ? 'הוספה' : 'שמירה'}</button>
    </div>
    ${!isNew ? `<button type="submit" value="archive" class="btn ${emp.active === false ? 'btn-ghost' : 'btn-danger-ghost'}">
      ${emp.active === false ? 'החזרה לרשימת העובדות' : 'העברה לארכיון (הסתרה מהרשימה)'}</button>
    <button type="submit" value="delete" class="btn btn-danger-ghost">${icon('trash')}מחיקת העובדת לצמיתות</button>` : ''}
  `, async (form, submitter) => {
    if (submitter?.value === 'delete') {
      sheet.close();
      deleteEmployeeFlow(emp); // opens its own confirmation
      return false;
    }
    if (submitter?.value === 'archive') {
      const archiving = emp.active !== false;
      await state.store.updateEmployee(emp.id, { active: !archiving });
      toast(archiving ? `${emp.name} הועברה לארכיון` : `${emp.name} הוחזרה לרשימה`);
      if (archiving) location.hash = '#/';
      return true;
    }
    const name = form.name.value.trim();
    const rate = parseRate(form.rate.value);
    $('#err-name').textContent = name ? '' : 'צריך להזין שם';
    $('#err-rate').textContent = Number.isNaN(rate) ? 'תעריף לא תקין' : '';
    form.name.setAttribute('aria-invalid', String(!name));
    form.rate.setAttribute('aria-invalid', String(Number.isNaN(rate)));
    if (!name) { form.name.focus(); return false; }
    if (Number.isNaN(rate)) { form.rate.focus(); return false; }

    if (isNew) {
      const ref = await state.store.addEmployee({ name, rate, avatar: form.avatar.value, active: true });
      toast(`${name} נוספה`);
      location.hash = `#/e/${ref.id}`;
    } else {
      await state.store.updateEmployee(emp.id, { name, rate, avatar: form.avatar.value });
      const newEff = rate != null ? rate : def;
      if (form.apply?.checked && newEff !== effRate(emp)) {
        await state.store.updateShifts(agg.shifts.map((s) => s.id), { rate: newEff });
      }
      toast('הפרטים נשמרו');
    }
    return true;
  });

  // Avatar picker: drawn avatars or emoji; tap to choose, or roll a random one
  const avForm = $('#av-random').form;
  const grid = $('#av-grid');
  const panel = $('#av-panel');
  $('#av-toggle').addEventListener('click', (ev) => {
    panel.hidden = !panel.hidden;
    ev.currentTarget.setAttribute('aria-expanded', String(!panel.hidden));
  });
  const cats = $('#em-cats');
  let mode = startAvatar.startsWith('av:') ? 'art' : 'emoji';
  let cat = Object.keys(EMOJIS).find((c) => emojiList(c).includes(startAvatar)) || Object.keys(EMOJIS)[0];
  let options = [];
  const paint = () => {
    const cur = avForm.avatar.value;
    $('#av-preview').innerHTML = avatar({ avatar: cur }, 'xl');
    sheet.querySelectorAll('#av-tabs button').forEach((t) => t.setAttribute('aria-selected', String(t.dataset.mode === mode)));
    cats.hidden = mode !== 'emoji';
    cats.querySelectorAll('button').forEach((c) => c.setAttribute('aria-pressed', String(c.dataset.cat === cat)));
    grid.classList.toggle('emojis', mode === 'emoji');
    const list = mode === 'art' ? options : emojiList(cat);
    grid.innerHTML = list.map((o) => `<button type="button" class="av-opt" role="radio" data-av="${o}" aria-checked="${o === cur}" aria-label="${mode === 'art' ? 'אוואטר' : o}">${mode === 'art' ? avatar({ avatar: o }) : o}</button>`).join('');
  };
  const shuffle = () => {
    const cur = avForm.avatar.value;
    options = [cur.startsWith('av:') ? cur : randomAvatar(), ...Array.from({ length: 15 }, randomAvatar)];
    paint();
  };
  const pick = (v) => { avForm.avatar.value = v; paint(); };
  $('#av-random').addEventListener('click', () => {
    if (mode === 'art') { avForm.avatar.value = randomAvatar(); shuffle(); }
    else { const v = ALL_EMOJIS[Math.floor(Math.random() * ALL_EMOJIS.length)]; cat = Object.keys(EMOJIS).find((c) => emojiList(c).includes(v)); pick(v); }
  });
  $('#av-tabs').addEventListener('click', (ev) => {
    const t = ev.target.closest('button');
    if (!t || t.dataset.mode === mode) return;
    mode = t.dataset.mode;
    if (mode === 'art') { avForm.avatar.value = randomAvatar(); shuffle(); }
    else pick(emojiList(cat)[0]);
  });
  cats.addEventListener('click', (ev) => {
    const c = ev.target.closest('button');
    if (c) { cat = c.dataset.cat; paint(); }
  });
  grid.addEventListener('click', (ev) => {
    const o = ev.target.closest('.av-opt');
    if (o) pick(o.dataset.av);
  });
  shuffle();

  // Offer "apply to this month" only when the effective rate actually changes
  const rateInput = $('#f-rate');
  const applyWrap = $('#apply-wrap');
  if (applyWrap) {
    const sync = () => {
      const r = parseRate(rateInput.value);
      const newEff = r != null && !Number.isNaN(r) ? r : def;
      applyWrap.hidden = newEff === effRate(emp) || Number.isNaN(r);
    };
    rateInput.addEventListener('input', sync);
  }
}

async function deleteEmployeeFlow(emp) {
  let bundle;
  try { bundle = await state.store.employeeBundle(emp.id); } catch (e) { fail(e); return; }
  const n = bundle.filter((d) => d.col === 'shifts').length;
  const ok = await confirmSheet({
    title: `מחיקת ${emp.name}`,
    text: `${esc(emp.name)}${n === 1 ? ' והמשמרת שלה יימחקו' : n ? ` וכל ${n} המשמרות שלה (בכל החודשים) יימחקו` : ' תימחק'} לצמיתות. אי אפשר לבטל את הפעולה.
      <br><span class="muted" style="font-size:14px">רוצה רק להסתיר אותה ולשמור את ההיסטוריה? בחר "העברה לארכיון".</span>`,
    okLabel: 'מחיקה לצמיתות',
  });
  if (!ok) return;
  try {
    await state.store.restore(bundle.map((d) => ({ ...d, data: null })));
    location.hash = '#/';
    toast(`${emp.name} נמחקה`, { undo: () => state.store.restore(bundle) });
  } catch (e) { fail(e); }
}

/* =========================================================
   Views
   ========================================================= */
const loadingHTML = `<div class="empty"><div class="spinner" aria-hidden="true"></div><p class="muted">טוען נתונים…</p></div>`;
const isLoaded = () => state.settings && state.employees && state.shifts;

/* ---------- Home: employee cards ---------- */
const HomeView = {
  mount(el) { this.el = el; this.update(); },
  update() {
    const el = this.el;
    if (!isLoaded()) { el.innerHTML = loadingHTML; return; }

    // Step 1 of onboarding: default rate
    if (state.settings.defaultRate == null) {
      el.innerHTML = `
        <form class="card onboard" id="onb-rate" novalidate>
          <div class="steps" aria-hidden="true"><span class="on"></span><span></span></div>
          <h2>ברוך הבא! נתחיל בתעריף</h2>
          <p class="muted">מה התעריף השעתי הרגיל של העובדות? אפשר לשנות אותו בכל רגע, ולתת לעובדת מסוימת תעריף אחר.</p>
          <div class="field">
            <label for="onb-rate-in">תעריף שעתי כללי</label>
            <div class="input-wrap">
              <input id="onb-rate-in" class="input num" inputmode="decimal" placeholder="לדוגמה: 40" autocomplete="off">
              <span class="input-suffix">₪</span>
            </div>
            <p class="field-error" id="onb-err"></p>
          </div>
          <button class="btn btn-primary btn-lg btn-block" type="submit">המשך</button>
        </form>`;
      const form = $('#onb-rate');
      form.addEventListener('submit', async (e) => {
        e.preventDefault();
        const r = parseRate($('#onb-rate-in').value);
        if (r == null || Number.isNaN(r)) { $('#onb-err').textContent = 'צריך להזין תעריף, לדוגמה 40'; $('#onb-rate-in').focus(); return; }
        const btn = form.querySelector('button'); btn.classList.add('is-loading'); btn.disabled = true;
        try { await state.store.saveSettings({ defaultRate: r }); } catch (err) { fail(err); btn.classList.remove('is-loading'); btn.disabled = false; }
      });
      return;
    }

    const agg = monthAgg();
    const visible = state.employees
      .filter((e) => e.active !== false || agg.has(e.id))
      .sort(byName);

    // Step 2 of onboarding: first employee
    if (!visible.length) {
      el.innerHTML = `
        <div class="card onboard">
          <div class="steps" aria-hidden="true"><span class="on"></span><span class="on"></span></div>
          <h2>עכשיו נוסיף את העובדת הראשונה</h2>
          <p class="muted">לכל עובדת יש כרטיס משלה, ושם רושמים את השעות.</p>
          <button class="btn btn-primary btn-lg btn-block" id="add-first" type="button">${icon('plus')}הוספת עובדת</button>
        </div>`;
      $('#add-first').addEventListener('click', () => employeeSheet());
      return;
    }

    let totalMin = 0; let totalPay = 0;
    agg.forEach((a) => { totalMin += a.minutes; totalPay += a.pay; });

    // Search + sort appear only when the list is long enough to need them
    const many = visible.length >= 5;
    const hadFocus = document.activeElement?.id === 'emp-search';
    this.q ??= '';
    this.sort ??= lsGet('empSort') || 'name';
    let shown = visible;
    if (many) {
      const q = this.q.trim();
      if (q) shown = shown.filter((e) => e.name.includes(q));
      const A = (e) => agg.get(e.id) || emptyAgg();
      if (this.sort === 'hours') shown = [...shown].sort((x, y) => A(y).minutes - A(x).minutes || byName(x, y));
      if (this.sort === 'unpaid') shown = [...shown].sort((x, y) => unpaidOf(A(y)) - unpaidOf(A(x)) || byName(x, y));
    }

    el.innerHTML = `
      <div class="page-head">
        <h1>העובדות</h1>
        <span class="spacer"></span>
        <span class="muted num">${esc(fmtMonthName(state.month))}: ${fmtHM(totalMin)} שעות · ${fmtMoney(totalPay)}</span>
      </div>
      ${many ? `
      <div class="home-tools">
        <label class="search"><span class="sr-only">חיפוש עובדת</span>
          <input type="search" id="emp-search" class="input" placeholder="חיפוש עובדת…" value="${esc(this.q)}" autocomplete="off"></label>
        <label class="sort"><span class="sr-only">מיון</span>
          <select id="emp-sort" class="input">
            <option value="name" ${this.sort === 'name' ? 'selected' : ''}>לפי שם</option>
            <option value="hours" ${this.sort === 'hours' ? 'selected' : ''}>הכי הרבה שעות</option>
            <option value="unpaid" ${this.sort === 'unpaid' ? 'selected' : ''}>הכי הרבה לתשלום</option>
          </select></label>
      </div>` : ''}
      ${many && !shown.length ? `<p class="muted empty">לא נמצאה עובדת בשם "${esc(this.q.trim())}"</p>` : ''}
      <div class="emp-grid">
        ${shown.map((e) => {
          const a = agg.get(e.id) || emptyAgg();
          return `
          <a class="card emp-card" href="#/e/${e.id}" aria-label="${esc(e.name)}: ${fmtHM(a.minutes)} שעות, ${fmtMoney(a.pay)}">
            <div class="emp-card-top">
              ${avatar(e)}
              <div style="min-width:0">
                <div class="emp-card-name">${esc(e.name)}</div>
                ${state.clocks[e.id] ? `<div class="on-shift"><span class="live-dot" aria-hidden="true"></span>במשמרת מ-<bdi class="num">${fmtTime(state.clocks[e.id].in)}</bdi></div>` : ''}
                <div class="emp-card-sub">${e.active === false ? 'בארכיון · ' : ''}${a.shifts.length ? `${a.shifts.length} משמרות` : 'אין משמרות החודש'} · ${fmtMoney(effRate(e))}/שעה</div>
              </div>
              <span class="go">${icon('chev-l')}</span>
            </div>
            <div class="emp-card-stats">
              <div class="stat"><div class="stat-label">שעות</div><div class="stat-value num">${fmtHM(a.minutes)}</div></div>
              <div class="stat"><div class="stat-label">${a.shifts.length && unpaidOf(a) <= 0 ? 'תשלום' : a.paidPay > 0 ? 'נותר לתשלום' : 'לתשלום'}</div>
                <div class="stat-value num">${a.shifts.length && unpaidOf(a) <= 0 ? '<span class="paid-ok">שולם ✓</span>' : fmtMoney(unpaidOf(a))}</div></div>
            </div>
          </a>`;
        }).join('')}
        <button class="add-card" id="add-emp" type="button">${icon('plus')}עובדת חדשה</button>
      </div>`;
    $('#add-emp').addEventListener('click', () => employeeSheet());
    const search = $('#emp-search');
    if (search) {
      search.addEventListener('input', () => { this.q = search.value; this.update(); });
      if (hadFocus) { search.focus(); search.setSelectionRange(search.value.length, search.value.length); }
      $('#emp-sort').addEventListener('change', (ev) => { this.sort = ev.target.value; lsSet('empSort', this.sort); this.update(); });
    }
  },
};

/* ---------- Employee page: entry form + shifts ---------- */
const EmployeeView = {
  mount(el, id) {
    this.el = el; this.id = id;
    this.form = { date: this.defaultDate(), in: '', out: '', editingId: null };
    this.built = false;
    this.payments = [];
    this.showAllPays = false;
    this.clockKey = undefined;
    this.unsubPay?.();
    this.unsubPay = state.store.watchPayments(id, (list) => { this.payments = list; if (this.built) this.renderPayments(); }, onDataError);
    clearInterval(this.ticker);
    this.ticker = setInterval(() => this.tick(), 30000);
    this.update();
  },
  unmount() { this.unsubPay?.(); this.unsubPay = null; clearInterval(this.ticker); },
  clock() { return state.clocks[this.id] || null; },
  defaultDate() {
    return state.month === currentMonth() ? todayStr() : `${state.month}-01`;
  },
  emp() { return empById(this.id); },
  myShifts() { return sortShifts((state.shifts || []).filter((s) => s.empId === this.id)); },

  update() {
    if (!isLoaded()) { this.el.innerHTML = loadingHTML; this.built = false; return; }
    const emp = this.emp();
    if (!emp) {
      this.built = false;
      this.el.innerHTML = `<div class="empty"><h2>העובדת לא נמצאה</h2><a class="btn btn-secondary" href="#/">חזרה לעובדות</a></div>`;
      return;
    }
    if (!this.built) this.build();
    else if (this.fmt12 !== is12()) this.renderTimeFields();
    this.syncClock();
    this.renderClock();
    this.renderHead();
    this.renderList();
    this.renderPreview();
    this.renderPayments();
  },

  build() {
    this.built = true;
    this.el.innerHTML = `
      <div class="emp-head" id="emp-head"></div>
      <div class="emp-layout">
        <form class="card entry" id="entry" novalidate autocomplete="off">
          <div class="entry-title">
            <h2 id="entry-title">הוספת משמרת</h2>
            ${fmtToggleHTML()}
          </div>
          <div id="clock-wrap"></div>
          <div class="field">
            <span class="field-label" id="date-lbl">תאריך</span>
            <div class="chips" role="group" aria-labelledby="date-lbl">
              <button type="button" class="chip" data-date="today" aria-pressed="false">היום</button>
              <button type="button" class="chip" data-date="yesterday" aria-pressed="false">אתמול</button>
            </div>
            <input type="date" class="input input-date" id="f-date" aria-labelledby="date-lbl" required>
          </div>
          <div class="times" id="times"></div>
          <p class="field-hint">מקלידים (לדוגמה 830 או 0830) או לוחצים על השעון לבחירה בגלגלת</p>
          <div class="special">
            <label class="check"><input type="checkbox" id="sp-on"><span>תעריף מיוחד למשמרת הזו <span class="muted">(חג, שבת וכו׳)</span></span></label>
            <div class="sp-box" id="sp-box" hidden>
              <div class="field">
                <label for="sp-rate">סכום לשעה</label>
                <div class="input-wrap"><input id="sp-rate" class="input num" inputmode="decimal" autocomplete="off" placeholder="לדוגמה: 60"><span class="input-suffix">₪</span></div>
              </div>
              <div class="field">
                <span class="field-label" id="sp-scope-lbl">על אילו שעות?</span>
                <div class="seg lg" role="radiogroup" aria-labelledby="sp-scope-lbl">
                  <button type="button" role="radio" data-scope="all" aria-checked="true">כל המשמרת</button>
                  <button type="button" role="radio" data-scope="part" aria-checked="false">רק חלק מהשעות</button>
                </div>
                <div class="input-wrap wide" id="sp-part" hidden><input id="sp-hours" class="input num" inputmode="decimal" autocomplete="off" placeholder="כמה שעות? לדוגמה: 2"><span class="input-suffix">שעות</span></div>
              </div>
            </div>
          </div>
          <div class="note-field">
            <button type="button" class="link-btn" id="note-toggle">${icon('plus')}הערה</button>
            <div id="note-wrap" hidden>
              <label for="f-note" class="field-label">הערה</label>
              <input id="f-note" class="input input-note" maxlength="120" autocomplete="off" placeholder="לדוגמה: החליפה את מיכל">
            </div>
          </div>
          <div id="last-wrap"></div>
          <div id="dup-wrap"></div>
          <div class="preview" id="preview" aria-live="polite"></div>
          <p class="field-error" id="entry-err" role="alert"></p>
          <div class="entry-actions" id="entry-actions"></div>
        </form>

        <div>
          <section class="card list-card" aria-labelledby="list-title">
            <div class="list-head">
              <h2 id="list-title"></h2>
              <span class="muted num" id="list-count"></span>
            </div>
            <ul class="shift-list" id="shift-list"></ul>
          </section>
          <div class="totals" id="totals"></div>
          <section class="card list-card pay-card" id="pay-card" aria-labelledby="pay-title" hidden></section>
        </div>
      </div>`;
    $('#note-toggle').addEventListener('click', () => { this.setNote(''); $('#note-wrap').hidden = false; $('#note-toggle').hidden = true; $('#f-note').focus(); });
    $('#f-note').addEventListener('input', () => this.saveDraft());

    const f = $('#entry');
    this.fDate = $('#f-date');
    this.fDate.value = this.form.date;
    this.ampm = { in: 'AM', out: 'PM' };
    this.renderTimeFields();
    this.wireSpecial();

    f.querySelectorAll('[data-date]').forEach((b) => b.addEventListener('click', () => {
      this.fDate.value = b.dataset.date === 'today' ? todayStr() : yesterdayStr();
      this.onInput();
      if (!this.fIn.value && matchMedia('(pointer: fine)').matches) this.fIn.focus();
    }));
    this.fDate.addEventListener('input', () => this.onInput());
    this.fDate.addEventListener('change', () => this.onInput());
    f.addEventListener('submit', (e) => { e.preventDefault(); this.save(); });
    this.renderActions();
    this.syncChips();
  },

  onInput() {
    this.form.date = this.fDate.value;
    $('#entry-err').textContent = '';
    [this.fDate, this.fIn, this.fOut].forEach((i) => i.removeAttribute('aria-invalid'));
    this.syncChips();
    this.renderPreview();
    this.saveDraft();
  },

  /* ----- open shift (clocked in, exit later) -----
     The entry is stored the moment it's recorded (on the device first, then synced), so closing the app,
     a dead battery or no signal can't lose it: whenever the app is opened again it's waiting here for the exit. */
  syncClock() {
    const c = this.clock();
    const key = c ? `${c.date} ${c.in}` : null;
    if (key === this.clockKey) return;
    const first = this.clockKey === undefined;
    this.clockKey = key;
    if (this.form.editingId) return;
    if (c) {
      this.form.date = c.date; this.fDate.value = c.date;
      this.setTime('in', c.in);
      this.setSpecial(c.special && c.special.rate != null ? c.special : null);
      this.setNote(c.note || '');
    } else if (!first) { // closed here or on another device
      this.setTime('in', ''); this.setTime('out', '');
      this.setSpecial(null); this.setNote('');
    } else this.restoreDraft();
    this.syncChips();
  },
  /** Back to the open shift (or a clean form) after editing / saving another shift. */
  reattach() { this.clockKey = undefined; this.syncClock(); this.renderClock(); this.renderPreview(); },

  renderClock() {
    const wrap = $('#clock-wrap');
    if (!wrap) return;
    const c = this.clock();
    if (this.form.editingId) { wrap.innerHTML = ''; return; }
    if (!c) {
      wrap.innerHTML = `<button type="button" class="btn btn-secondary btn-block clock-in-btn" id="clock-in">${icon('clock')}<span>כניסה עכשיו <span class="muted">· היציאה תירשם אחר כך</span></span></button>`;
      $('#clock-in').addEventListener('click', () => this.clockInNow());
      return;
    }
    const min = Math.round((Date.now() - clockStart(c)) / 60000);
    const stale = min > MAX_OPEN_MIN;
    this.clockStale = stale;
    const when = c.date === todayStr() ? '' : c.date === yesterdayStr() ? 'אתמול ' : `${fmtDayMonth(c.date)} `;
    wrap.innerHTML = `
      <div class="clock-card${stale ? ' stale' : ''}">
        <div class="clock-info">
          <span class="live-dot" aria-hidden="true"></span>
          <div>
            <div class="clock-title">במשמרת · נכנסה ${when}ב-<bdi class="num">${fmtTime(c.in)}</bdi></div>
            <div class="clock-sub">${stale
              ? 'המשמרת פתוחה הרבה זמן. הזינו למטה את שעת היציאה האמיתית ולחצו "שמירת יציאה".'
              : `עד עכשיו <span class="num" id="clock-elapsed">${fmtHM(Math.max(0, min))}</span> שעות · הכניסה שמורה גם אם האפליקציה נסגרת`}</div>
          </div>
        </div>
        <div class="clock-actions">
          ${stale ? '' : `<button type="button" class="btn btn-primary" id="clock-out">${icon('logout')}יציאה עכשיו</button>`}
          <button type="button" class="link-btn" id="clock-cancel">ביטול הכניסה</button>
        </div>
      </div>`;
    $('#clock-out')?.addEventListener('click', () => this.clockOutNow());
    $('#clock-cancel').addEventListener('click', () => this.cancelClock());
  },
  tick() {
    const c = this.clock();
    if (!this.built || !c) return;
    const min = Math.round((Date.now() - clockStart(c)) / 60000);
    if ((min > MAX_OPEN_MIN) !== !!this.clockStale) { this.renderClock(); return; }
    const el = $('#clock-elapsed');
    if (el) el.textContent = fmtHM(Math.max(0, min));
  },
  async clockInNow() {
    const btn = $('#clock-in');
    const sp = this.readSpecial();
    const special = sp && sp.rate != null && !Number.isNaN(sp.rate) && !(sp.part && !(sp.hours > 0)) ? { rate: sp.rate, hours: sp.part ? sp.hours : null } : null;
    const note = $('#f-note').value.trim() || null;
    const t = nowHHMM();
    btn?.classList.add('is-loading'); if (btn) btn.disabled = true;
    try {
      await state.store.setClock(this.id, { date: todayStr(), in: t, startedAt: Date.now(), note, special });
      this.clearDraft();
      toast(`נרשמה כניסה ב-${fmtTime(t)}`);
    } catch (e) { fail(e); btn?.classList.remove('is-loading'); if (btn) btn.disabled = false; }
  },
  clockOutNow() {
    const c = this.clock();
    if (!c) return;
    if (!this.form.in) { this.form.date = c.date; this.fDate.value = c.date; this.setTime('in', c.in); }
    this.setTime('out', nowHHMM());
    this.save();
  },
  async cancelClock() {
    const c = this.clock();
    if (!c) return;
    const ok = await confirmSheet({
      title: 'ביטול הכניסה',
      text: `הכניסה של ${fmtTime(c.in)} תימחק ולא תירשם משמרת.`,
      okLabel: 'ביטול הכניסה',
    });
    if (!ok) return;
    const { id, ...data } = c;
    try {
      await state.store.clearClock(this.id);
      toast('הכניסה בוטלה', { undo: () => state.store.setClock(this.id, data) });
    } catch (e) { fail(e); }
  },

  /* ----- draft: a half-filled form survives the app closing (kept 12 hours) ----- */
  draftKey() { return `draft-${this.id}`; },
  saveDraft() {
    // clockKey is undefined until the form was filled once (open shift or draft): don't wipe the draft before that
    if (!this.built || this.clockKey === undefined || this.form.editingId || this.clock() || this.restoring) return;
    const note = $('#f-note')?.value.trim() || '';
    const { date, in: tin, out: tout } = this.form;
    if (!tin && !tout && !note) { lsDel(this.draftKey()); return; }
    lsSet(this.draftKey(), JSON.stringify({ date, in: tin, out: tout, note, t: Date.now() }));
  },
  clearDraft() { lsDel(this.draftKey()); },
  restoreDraft() {
    let d = null;
    try { d = JSON.parse(lsGet(this.draftKey()) || 'null'); } catch { /* ignore */ }
    if (!d || !(Date.now() - d.t < 12 * 3600 * 1000)) { this.clearDraft(); return; }
    this.restoring = true;
    if (d.date) { this.form.date = d.date; this.fDate.value = d.date; }
    this.setTime('in', d.in || ''); this.setTime('out', d.out || '');
    this.setNote(d.note || '');
    this.restoring = false;
  },

  /* ----- special rate (manual amount per shift) ----- */
  wireSpecial() {
    const on = $('#sp-on');
    const sync = () => { this.form.special = this.readSpecial(); $('#entry-err').textContent = ''; this.renderPreview(); };
    on.addEventListener('change', () => {
      $('#sp-box').hidden = !on.checked;
      if (on.checked && !$('#sp-rate').value) $('#sp-rate').focus();
      sync();
    });
    ['#sp-rate', '#sp-hours'].forEach((sel) => $(sel).addEventListener('input', sync));
    this.el.querySelectorAll('[data-scope]').forEach((b) => b.addEventListener('click', () => {
      this.el.querySelectorAll('[data-scope]').forEach((x) => x.setAttribute('aria-checked', String(x === b)));
      $('#sp-part').hidden = b.dataset.scope !== 'part';
      if (b.dataset.scope === 'part') $('#sp-hours').focus();
      sync();
    }));
  },
  /** null = no special rate; otherwise {rate, hours} (hours null = whole shift; NaN = invalid input). */
  readSpecial() {
    if (!$('#sp-on').checked) return null;
    const part = this.el.querySelector('[data-scope="part"]').getAttribute('aria-checked') === 'true';
    return { rate: parseRate($('#sp-rate').value), hours: part ? parseRate($('#sp-hours').value) : null, part };
  },
  setSpecial(sp) {
    $('#sp-on').checked = !!sp;
    $('#sp-box').hidden = !sp;
    $('#sp-rate').value = sp?.rate ?? '';
    const part = sp?.hours != null;
    this.el.querySelectorAll('[data-scope]').forEach((x) => x.setAttribute('aria-checked', String((x.dataset.scope === 'part') === part)));
    $('#sp-part').hidden = !part;
    $('#sp-hours').value = part ? sp.hours : '';
    this.form.special = sp ? { rate: sp.rate, hours: sp.hours ?? null, part } : null;
  },

  /* ----- time fields: typing + AM/PM + wheel ----- */
  renderTimeFields() {
    this.fmt12 = is12();
    $('#times').innerHTML = timeFieldHTML('in', 'כניסה') + timeFieldHTML('out', 'יציאה');
    this.fIn = $('#f-in'); this.fOut = $('#f-out');
    for (const k of ['in', 'out']) {
      const inp = this.input(k);
      inp.addEventListener('input', () => this.onTyped(k));
      inp.addEventListener('blur', () => this.onTimeBlur(k));
      inp.addEventListener('focus', () => inp.select());
    }
    $('#times').querySelectorAll('[data-ampm]').forEach((b) => b.addEventListener('click', () => {
      const k = b.dataset.ampm;
      this.ampm[k] = this.ampm[k] === 'AM' ? 'PM' : 'AM';
      this.ampmManual[k] = true;
      const v = parseTyped(this.input(k).value, this.ampm[k]);
      this.form[k] = v || '';
      this.syncAmpm(k);
      this.afterTimeChange();
    }));
    $('#times').querySelectorAll('[data-wheel]').forEach((b) => b.addEventListener('click', () => openWheel(b.dataset.wheel, this)));
    this.setTime('in', this.form.in);
    this.setTime('out', this.form.out);
  },
  input(k) { return k === 'in' ? this.fIn : this.fOut; },
  displayValue(t) {
    if (!t) return '';
    if (!is12()) return t;
    const [h, m] = t.split(':').map(Number);
    return `${h % 12 || 12}:${pad(m)}`;
  },
  syncAmpm(k) {
    const b = this.el.querySelector(`[data-ampm="${k}"]`);
    if (b) b.textContent = this.ampm[k];
  },
  setTime(k, t) {
    this.ampmManual ||= {};
    if (!t) this.ampmManual[k] = false;
    this.form[k] = t || '';
    if (t) this.ampm[k] = +t.slice(0, 2) < 12 ? 'AM' : 'PM';
    this.input(k).value = this.displayValue(t);
    this.syncAmpm(k);
    this.afterTimeChange();
  },
  onTyped(k) {
    const inp = this.input(k);
    const d = inp.value.replace(/\D/g, '').slice(0, 4);
    const formatted = d.length >= 3 ? `${d.slice(0, -2)}:${d.slice(-2)}` : d;
    if (formatted !== inp.value) inp.value = formatted;
    let v = parseTyped(d, is12() ? this.ampm[k] : null);
    if (v && is12()) {
      const typedH = +(d.length <= 2 ? d : d.slice(0, -2));
      if (typedH === 0 || typedH > 12) { // typed a 24h hour → reflect it on the AM/PM button
        this.ampm[k] = +v.slice(0, 2) < 12 ? 'AM' : 'PM'; this.syncAmpm(k);
      } else if (k === 'out' && this.form.in && !this.ampmManual?.out) {
        // pick AM/PM so the shift is the shortest one after clock-in (9:00 AM → "11" = 11:00 AM)
        const opts = ['AM', 'PM'].map((ap) => ({ ap, t: parseTyped(d, ap) }));
        const dur = (t) => shiftMinutes(this.form.in, t) || 24 * 60; // same time as clock-in = not a shift
        const best = opts.sort((x, y) => dur(x.t) - dur(y.t))[0];
        this.ampm.out = best.ap; this.syncAmpm('out'); v = best.t;
      }
    }
    this.form[k] = v || '';
    this.afterTimeChange();
    if (v && d.length === 4 && k === 'in' && !this.fOut.value) this.fOut.focus(); // jump to יציאה
  },
  onTimeBlur(k) {
    const inp = this.input(k);
    if (!inp.value.replace(/\D/g, '')) { this.form[k] = ''; return; }
    if (!this.form[k]) {
      inp.setAttribute('aria-invalid', 'true');
      $('#entry-err').textContent = 'שעה לא תקינה – לדוגמה 8:30 או 0830';
      return;
    }
    inp.value = this.displayValue(this.form[k]);
  },
  afterTimeChange() {
    $('#entry-err').textContent = '';
    this.fIn?.removeAttribute('aria-invalid'); this.fOut?.removeAttribute('aria-invalid');
    this.renderPreview();
    this.saveDraft();
  },

  syncChips() {
    const v = this.fDate.value;
    this.el.querySelector('[data-date=today]').setAttribute('aria-pressed', String(v === todayStr()));
    this.el.querySelector('[data-date=yesterday]').setAttribute('aria-pressed', String(v === yesterdayStr()));
  },

  renderHead() {
    const emp = this.emp();
    const personal = emp.rate != null;
    $('#emp-head').innerHTML = `
      <a href="#/" class="icon-btn back-btn" aria-label="חזרה לעובדות">${icon('chev-r')}</a>
      ${avatar(emp, 'lg')}
      <div class="titles">
        <h1>${esc(emp.name)}</h1>
        <div class="meta">
          <span class="badge ${personal ? 'personal' : ''}">${fmtMoney(effRate(emp))}/שעה · ${personal ? 'אישי' : 'כללי'}</span>
          ${emp.active === false ? '<span class="badge">בארכיון</span>' : ''}
        </div>
      </div>
      <div class="head-actions">
        <a class="btn btn-ghost" href="#/r/${emp.id}" aria-label="דוח חודשי להדפסה">${icon('file')}<span>דוח</span></a>
        <button type="button" class="btn btn-ghost" id="edit-emp">${icon('pencil')}<span>עריכה</span></button>
      </div>`;
    $('#edit-emp').addEventListener('click', () => employeeSheet(this.emp()));
  },

  renderList() {
    const list = this.myShifts();
    const emp = this.emp();
    $('#list-title').textContent = `משמרות ב${fmtMonthName(state.month)}`;
    const unpaid = list.filter((s) => !s.paid);
    $('#list-count').innerHTML = !list.length ? ''
      : unpaid.length ? `<button type="button" class="btn btn-ghost btn-sm" id="pay-all">${icon('check')}סימון הכל כשולם</button>`
        : '<span class="paid-ok">הכל שולם ✓</span>';
    $('#pay-all')?.addEventListener('click', () => paySheet(emp, unpaid));
    const ul = $('#shift-list');
    if (!list.length) {
      ul.innerHTML = `<li class="empty"><p class="muted">עוד אין משמרות ב${esc(fmtMonth(state.month))}.<br>הוסף משמרת בטופס${matchMedia('(min-width: 860px)').matches ? ' מימין' : ' למעלה'}.</p></li>`;
    } else {
      ul.innerHTML = list.map((s) => {
        const min = shiftMinutes(s.in, s.out);
        const pay = shiftPay(s, emp);
        const d = parseDate(s.date);
        const sp = s.special && s.special.rate != null
          ? `<span class="sp-badge">מיוחד ${fmtMoney(s.special.rate)}${s.special.hours != null ? ` · ${fmtHours(specialMinutes(s))} ש׳` : ''}</span>` : '';
        return `<li class="shift-row ${s.paid ? 'is-paid' : ''}">
          <button type="button" class="shift ${s.id === this.form.editingId ? 'selected' : ''}" data-id="${s.id}"
            aria-label="${fmtDayMonth(s.date)}, ${fmtTime(s.in)} עד ${fmtTime(s.out)}, ${fmtHM(min)} שעות, ${fmtMoney(pay)}. לחיצה לעריכה">
            <span class="shift-date"><span class="d num">${d.getDate()}</span><br><span class="w">${esc(fmtWeekday(s.date))}</span></span>
            <span class="shift-times">${rng(s.in, s.out)}${isOvernight(s.in, s.out) ? '<span class="night">לילה</span>' : ''}${sp}${s.note ? `<span class="shift-note">${esc(s.note)}</span>` : ''}</span>
            <span class="shift-amount"><span class="h num">${fmtHM(min)}</span><br><span class="p num">${fmtMoney(pay)}</span></span>
          </button>
          <button type="button" class="paid-btn" data-paid="${s.id}" aria-pressed="${!!s.paid}"
            aria-label="${s.paid ? 'שולם. לחיצה לביטול הסימון' : 'לא שולם. לחיצה לסימון כשולם'}">
            <span class="paid-dot">${icon('check')}</span><span class="paid-txt">${s.paid ? 'שולם' : 'לא שולם'}</span>
          </button>
        </li>`;
      }).join('');
      ul.querySelectorAll('.shift').forEach((b) => b.addEventListener('click', () => this.startEdit(b.dataset.id)));
      ul.querySelectorAll('.paid-btn').forEach((b) => b.addEventListener('click', async () => {
        const sh = list.find((x) => x.id === b.dataset.paid);
        if (!sh) return;
        const paid = !sh.paid;
        b.setAttribute('aria-pressed', String(paid)); // instant feedback
        b.closest('.shift-row').classList.toggle('is-paid', paid);
        try {
          if (paid) await withUndo(`סומן כשולם · ${lastMethod()}`, [{ col: 'shifts', id: sh.id }], () => payShifts(emp, [sh]));
          else await withUndo('הסימון "שולם" הוסר', shiftRefs(sh), () => unpayShift(sh, emp, this.payments));
        } catch (e) { fail(e); }
      }));
    }

    const a = monthAgg().get(this.id) || emptyAgg();
    $('#totals').innerHTML = `
      ${a.paidPay > 0
        ? (unpaidOf(a) <= 0
          ? `<div><div class="lbl">שולם הכל ✓</div><div class="val num">${fmtMoney(a.pay)}</div></div>`
          : `<div><div class="lbl">נותר לתשלום · מתוך ${fmtMoney(a.pay)}</div><div class="val num">${fmtMoney(unpaidOf(a))}</div></div>`)
        : `<div><div class="lbl">סה״כ ${esc(fmtMonthName(state.month))}</div><div class="val num">${fmtMoney(a.pay)}</div></div>`}
      <div class="grp">
        <div><div class="lbl">שעות</div><div class="val num">${fmtHM(a.minutes)}</div></div>
        <div><div class="lbl">משמרות</div><div class="val num">${a.shifts.length}</div></div>
      </div>`;
  },

  renderPayments() {
    const card = $('#pay-card');
    if (!card) return;
    const list = [...(this.payments || [])].sort((a, b) => b.date.localeCompare(a.date) || (b.createdAt || 0) - (a.createdAt || 0));
    card.hidden = !list.length;
    if (!list.length) { card.innerHTML = ''; return; }
    const shown = this.showAllPays ? list : list.slice(0, 5);
    const total = list.reduce((t, p) => t + (p.amount || 0), 0);
    card.innerHTML = `
      <div class="list-head"><h2 id="pay-title">היסטוריית תשלומים</h2><span class="muted num">סה״כ ${fmtMoney(total)}</span></div>
      <ul class="pay-list">${shown.map((p) => `
        <li><button type="button" class="pay-row" data-pay="${p.id}" aria-label="תשלום ${fmtMoney(p.amount)} ב-${fmtDate(p.date)}, ${esc(p.method)}. לחיצה לעריכה">
          <span class="pay-date num">${fmtDate(p.date)}</span>
          <span class="pay-method">${esc(p.method)} · ${nShifts(p.shiftIds?.length || 0)}</span>
          <span class="pay-amt num">${fmtMoney(p.amount)}</span>
        </button></li>`).join('')}
      </ul>
      ${list.length > 5 && !this.showAllPays ? `<button type="button" class="btn btn-ghost btn-block" id="pay-more">הצגת כל ${list.length} התשלומים</button>` : ''}`;
    card.querySelectorAll('[data-pay]').forEach((b) => b.addEventListener('click', () => {
      const p = this.payments.find((x) => x.id === b.dataset.pay);
      if (p) paymentSheet(p, this.emp());
    }));
    $('#pay-more')?.addEventListener('click', () => { this.showAllPays = true; this.renderPayments(); });
  },

  setNote(text) {
    $('#f-note').value = text || '';
    $('#note-wrap').hidden = !text;
    $('#note-toggle').hidden = !!text;
  },

  lastHours() {
    const own = this.myShifts().filter((s) => s.id !== this.form.editingId);
    if (own.length) return { in: own[0].in, out: own[0].out };
    const saved = lsGet(`last-${this.id}`);
    if (saved) { const [i, o] = saved.split('-'); if (i && o) return { in: i, out: o }; }
    return null;
  },

  renderPreview() {
    if (!this.built) return;
    const { date, in: tin, out: tout, editingId } = this.form;

    // Quick fill with the last used hours
    const last = this.lastHours();
    const lastWrap = $('#last-wrap');
    if (last && !editingId && !(tin === last.in && tout === last.out)) {
      lastWrap.innerHTML = `<button type="button" class="chip soft" id="use-last">${icon('repeat')}כמו בפעם הקודמת: ${rng(last.in, last.out)}</button>`;
      $('#use-last').addEventListener('click', () => {
        this.setTime('in', last.in); this.setTime('out', last.out);
        $('#entry button[type=submit]').focus();
      });
    } else lastWrap.innerHTML = '';

    // Duplicate-date warning
    const same = (state.shifts || []).filter((s) => s.empId === this.id && s.date === date && s.id !== editingId);
    $('#dup-wrap').innerHTML = same.length
      ? `<div class="notice">${icon('alert')}<span>כבר רשומה משמרת ב-${fmtDayMonth(date)}: ${same.map((s) => rng(s.in, s.out)).join(', ')}</span></div>`
      : '';

    const pv = $('#preview');
    if (tin && tout && tin !== tout) {
      const min = shiftMinutes(tin, tout);
      const editing = editingId && (state.shifts || []).find((s) => s.id === editingId);
      const rate = editing ? shiftRate(editing, this.emp()) : effRate(this.emp());
      const sp = this.form.special;
      const spValid = sp && sp.rate != null && !Number.isNaN(sp.rate) && !(sp.part && (sp.hours == null || Number.isNaN(sp.hours)));
      const draft = { in: tin, out: tout, rate, special: spValid ? { rate: sp.rate, hours: sp.hours } : null };
      const spMin = specialMinutes(draft);
      pv.className = 'preview';
      pv.innerHTML = `
        <div><div class="big num">${fmtHM(min)} <span style="font-size:15px;font-weight:500">שעות</span></div>
        ${isOvernight(tin, tout) ? '<div class="field-hint">משמרת לילה – היציאה למחרת</div>' : ''}
        ${spMin ? `<div class="field-hint num">${spMin === min ? 'כל השעות' : `${fmtHM(spMin)} שעות`} ב-${fmtMoney(sp.rate)}${spMin < min ? ` · השאר ב-${fmtMoney(rate)}` : ''}</div>` : ''}</div>
        <div class="pay num">${fmtMoney(shiftPay(draft, this.emp()))}</div>`;
    } else {
      pv.className = 'preview empty-state';
      pv.textContent = this.clock() && !editingId ? (this.clockStale ? 'הזינו את שעת היציאה האמיתית' : 'הזינו שעת יציאה, או לחצו "יציאה עכשיו"')
        : tin && !tout && !editingId ? 'אפשר לשמור עכשיו רק את הכניסה, ולרשום יציאה אחר כך'
          : 'בחר שעת כניסה ויציאה';
    }
    this.syncSubmit();
  },
  /** The main button says what it will do: save a shift, record only the entry, or record the exit. */
  syncSubmit() {
    if (this.form.editingId) return;
    const b = $('#entry button[type=submit]');
    if (!b || b.classList.contains('is-loading')) return;
    const label = this.clock() ? 'שמירת יציאה'
      : this.form.in && !this.form.out && !this.fOut.value ? 'שמירת כניסה · יציאה אחר כך' : 'שמירה';
    b.innerHTML = `${icon('check')}${label}`;
  },

  renderActions() {
    const editing = !!this.form.editingId;
    $('#entry').classList.toggle('editing', editing);
    $('#entry-title').textContent = editing ? 'עריכת משמרת' : 'הוספת משמרת';
    $('#entry-actions').innerHTML = editing
      ? `<div class="row">
           <button type="submit" class="btn btn-primary btn-lg">${icon('check')}עדכון</button>
           <button type="button" class="btn btn-secondary btn-lg" id="cancel-edit">ביטול</button>
         </div>
         <button type="button" class="btn btn-danger-ghost" id="del-shift">${icon('trash')}מחיקת המשמרת</button>`
      : `<button type="submit" class="btn btn-primary btn-lg btn-block">${icon('check')}שמירה</button>`;
    if (editing) {
      $('#cancel-edit').addEventListener('click', () => this.stopEdit());
      $('#del-shift').addEventListener('click', () => this.remove());
    }
    this.renderClock();
  },

  startEdit(id) {
    const s = (state.shifts || []).find((x) => x.id === id);
    if (!s) return;
    this.form = { date: s.date, in: s.in, out: s.out, editingId: id, special: null };
    this.fDate.value = s.date; this.setTime('in', s.in); this.setTime('out', s.out);
    this.setSpecial(s.special && s.special.rate != null ? s.special : null);
    this.setNote(s.note || '');
    $('#entry-err').textContent = '';
    this.renderActions(); this.syncChips(); this.renderList(); this.renderPreview();
    if (!matchMedia('(min-width: 860px)').matches) {
      $('#entry').scrollIntoView({ behavior: matchMedia('(prefers-reduced-motion: reduce)').matches ? 'auto' : 'smooth', block: 'start' });
    }
  },

  stopEdit() {
    this.form = { date: this.fDate.value || this.defaultDate(), in: '', out: '', editingId: null, special: null };
    this.setTime('in', ''); this.setTime('out', '');
    this.setSpecial(null);
    this.setNote('');
    $('#entry-err').textContent = '';
    this.renderActions(); this.renderList(); this.renderPreview();
    this.reattach();
  },

  async save() {
    const { date, in: tin, out: tout, editingId } = this.form;
    const err = $('#entry-err');
    let bad = null;
    if (!date) bad = [this.fDate, 'צריך לבחור תאריך'];
    else if (!tin) bad = [this.fIn, this.fIn.value ? 'שעת הכניסה לא תקינה' : 'צריך להזין שעת כניסה'];
    else if (!tout && (this.fOut.value || editingId || this.clock())) {
      bad = [this.fOut, this.fOut.value ? 'שעת היציאה לא תקינה' : this.clock() && !editingId && !this.clockStale ? 'צריך להזין שעת יציאה, או ללחוץ "יציאה עכשיו"' : 'צריך להזין שעת יציאה'];
    } else if (tout && tin === tout) bad = [this.fOut, 'שעת היציאה זהה לשעת הכניסה'];
    const sp = this.readSpecial();
    if (!bad && sp && (sp.rate == null || Number.isNaN(sp.rate))) bad = [$('#sp-rate'), 'צריך להזין סכום לשעה לתעריף המיוחד'];
    else if (!bad && sp?.part && (sp.hours == null || Number.isNaN(sp.hours) || sp.hours <= 0)) bad = [$('#sp-hours'), 'צריך להזין כמה שעות בתעריף המיוחד'];
    const special = sp ? { rate: sp.rate, hours: sp.part ? sp.hours : null } : null;
    const note = $('#f-note').value.trim() || null;
    if (bad) { bad[0].setAttribute('aria-invalid', 'true'); err.textContent = bad[1]; bad[0].focus(); return; }

    const btn = $('#entry button[type=submit]');
    btn.classList.add('is-loading'); btn.disabled = true;
    const month = date.slice(0, 7);
    const clock = !editingId && this.clock();
    try {
      if (!tout) { // entry only: the exit is recorded later, even if the app is closed in between
        await state.store.setClock(this.id, { date, in: tin, startedAt: Date.now(), note, special });
        this.clearDraft();
        toast(`נרשמה כניסה ב-${fmtTime(tin)} · היציאה תירשם אחר כך`);
        return;
      }
      if (editingId) {
        await withUndo('המשמרת עודכנה', [{ col: 'shifts', id: editingId }],
          () => state.store.updateShift(editingId, { date, month, in: tin, out: tout, special, note }));
        this.form.editingId = null;
        this.renderActions();
      } else {
        const shift = { empId: this.id, date, month, in: tin, out: tout, rate: effRate(this.emp()), special, note, paid: false };
        if (clock) await state.store.closeClock(this.id, shift); // adds the shift and closes the open one together
        else await state.store.addShift(shift);
        toast(`${clock ? 'נרשמה יציאה' : 'נשמר'}: ${fmtDayMonth(date)} · ${fmtHM(shiftMinutes(tin, tout))} שעות`);
      }
      this.clearDraft();
      lsSet(`last-${this.id}`, `${tin}-${tout}`);
      this.setTime('in', ''); this.setTime('out', '');
      this.setSpecial(null);
      this.setNote('');
      if (month !== state.month) setMonth(month, { keepForm: true });
      this.renderList(); this.renderPreview();
      this.reattach();
      if (matchMedia('(pointer: fine)').matches) this.fIn.focus();
    } catch (e) { fail(e); } finally {
      const b = $('#entry button[type=submit]');
      if (b) { b.classList.remove('is-loading'); b.disabled = false; }
      this.syncSubmit();
    }
  },

  async remove() {
    const s = (state.shifts || []).find((x) => x.id === this.form.editingId);
    if (!s) return;
    try {
      await withUndo(`המשמרת של ${fmtDayMonth(s.date)} נמחקה`, shiftRefs(s), async () => {
        if (s.paid) await unpayShift(s, this.emp(), this.payments);
        await state.store.deleteShift(s.id);
      });
      this.stopEdit();
    } catch (e) { fail(e); }
  },
};

/* ---------- Summary: month / date range / year ---------- */
const niceMax = (v) => {
  if (v <= 0) return 1000;
  const p = 10 ** Math.floor(Math.log10(v));
  const n = v / p;
  return (n <= 1 ? 1 : n <= 2 ? 2 : n <= 5 ? 5 : 10) * p;
};
const monthShort = (i) => new Intl.DateTimeFormat('he-IL', { month: 'short' }).format(new Date(2026, i, 1));

const SummaryView = {
  mode: sessionStorage.getItem('sumMode') || 'month',
  mount(el) {
    this.el = el;
    this.cache = null; // fetched shifts for range/year
    this.range ||= { from: `${state.month}-01`, to: state.month === currentMonth() ? todayStr() : toDateStr(new Date(+state.month.slice(0, 4), +state.month.slice(5, 7), 0)) };
    this.year ||= +state.month.slice(0, 4);
    this.update();
  },
  rowsFrom(list) {
    const agg = aggOf(list);
    return state.employees
      .filter((e) => (this.mode === 'month' ? e.active !== false : false) || agg.has(e.id))
      .sort(byName)
      .map((e) => ({ emp: e, ...(agg.get(e.id) || emptyAgg()) }));
  },
  /** Shifts for the active mode; null while loading. */
  data() {
    if (this.mode === 'month') return state.shifts;
    const [from, to] = this.mode === 'year' ? [`${this.year}-01-01`, `${this.year}-12-31`] : [this.range.from, this.range.to];
    const key = `${from}|${to}`;
    if (this.cache?.key === key) return this.cache.list;
    if (this.loadingKey !== key) {
      this.loadingKey = key;
      state.store.getShiftsRange(from, to)
        .then((list) => { this.cache = { key, list }; if (mounted.view === this) this.update(); })
        .catch(fail)
        .finally(() => { if (this.loadingKey === key) this.loadingKey = null; });
    }
    return null;
  },
  label() {
    if (this.mode === 'month') return fmtMonth(state.month);
    if (this.mode === 'year') return String(this.year);
    return `${fmtDate(this.range.from)} – ${fmtDate(this.range.to)}`;
  },
  fileTag() {
    if (this.mode === 'month') return state.month;
    if (this.mode === 'year') return String(this.year);
    return `${this.range.from}_${this.range.to}`;
  },
  setMode(mode) {
    this.mode = mode;
    sessionStorage.setItem('sumMode', mode);
    $('.month-switch').hidden = mode !== 'month';
    this.update();
  },

  update() {
    const el = this.el;
    if (!isLoaded()) { el.innerHTML = loadingHTML; return; }
    $('.month-switch').hidden = this.mode !== 'month';
    const tabs = `
      <div class="seg lg sum-tabs" role="tablist" aria-label="תקופת הסיכום">
        ${[['month', 'חודש'], ['range', 'טווח תאריכים'], ['year', 'שנה']].map(([k, t]) =>
          `<button type="button" role="tab" data-mode="${k}" aria-checked="${this.mode === k}" aria-selected="${this.mode === k}">${t}</button>`).join('')}
      </div>`;
    const controls = this.mode === 'range' ? `
      <div class="range-row">
        <div class="field"><label for="r-from">מתאריך</label><input type="date" id="r-from" class="input input-date" value="${this.range.from}"></div>
        <div class="field"><label for="r-to">עד תאריך</label><input type="date" id="r-to" class="input input-date" value="${this.range.to}"></div>
      </div>` : this.mode === 'year' ? `
      <div class="year-row">
        <button type="button" class="icon-btn" id="y-prev" aria-label="שנה קודמת">${icon('chev-r')}</button>
        <span class="year-label num">${this.year}</span>
        <button type="button" class="icon-btn" id="y-next" aria-label="שנה הבאה">${icon('chev-l')}</button>
      </div>` : '';

    const list = this.data();
    let body = loadingHTML;
    if (list) {
      const rows = this.rowsFrom(list);
      this.currentRows = rows;
      const tMin = rows.reduce((t, r) => t + r.minutes, 0);
      const tPay = rows.reduce((t, r) => t + r.pay, 0);
      const tPaid = rows.reduce((t, r) => t + r.paidPay, 0);
      const tShifts = rows.reduce((t, r) => t + r.shifts.length, 0);
      body = `
        ${this.mode === 'year' ? yearChart(list, this.year) : ''}
        <div class="kpis">
          <div class="card kpi"><div class="stat-label">נותר לתשלום</div><div class="stat-value num">${fmtMoney(tPay - tPaid)}</div></div>
          <div class="card kpi"><div class="stat-label">שולם</div><div class="stat-value num">${fmtMoney(tPaid)}</div></div>
          <div class="card kpi"><div class="stat-label">שעות</div><div class="stat-value num">${fmtHM(tMin)}</div></div>
        </div>
        ${rows.length ? `
        <section class="card list-card">
          <ul class="sum-list">
            ${rows.map((r) => {
              const rates = [...new Set(r.shifts.map((sh) => shiftRate(sh, r.emp)))];
              const rateTxt = rates.length > 1 ? 'תעריף משתנה' : `${fmtMoney(rates[0] ?? effRate(r.emp))}/שעה`;
              return `<li class="sum-row">
                ${avatar(r.emp)}
                <div style="min-width:0">
                  <a class="name" href="#/e/${r.emp.id}">${esc(r.emp.name)}</a>
                  <div class="sub num">${nShifts(r.shifts.length)} · ${fmtHM(r.minutes)} שעות · ${rateTxt}</div>
                </div>
                <div><div class="pay num">${fmtMoney(r.pay)}</div>
                  <div class="hrs num">${!r.shifts.length ? '—' : unpaidOf(r) <= 0 ? '<span class="paid-ok">שולם ✓</span>' : r.paidPay > 0 ? `נותר ${fmtMoney(unpaidOf(r))}` : 'לא שולם'}</div></div>
              </li>`;
            }).join('')}
          </ul>
          <div class="sum-total"><span>סה״כ ${esc(this.mode === 'month' ? 'החודש' : this.mode === 'year' ? 'השנה' : 'בטווח')}${tPaid > 0 ? ` · נותר ${fmtMoney(tPay - tPaid)}` : ''}</span><span class="val num">${fmtMoney(tPay)}</span></div>
        </section>` : `<div class="card empty"><p class="muted">אין משמרות בתקופה הזו.</p></div>`}
        <button class="btn btn-secondary btn-block export-btn" id="export" type="button" ${tShifts ? '' : 'disabled'}>${icon('download')}ייצוא לאקסל – ${esc(this.label())}</button>`;
    }

    el.innerHTML = `
      <div class="page-head"><h1>סיכום</h1></div>
      ${tabs}
      ${controls}
      <div id="sum-body">${body}</div>`;

    el.querySelectorAll('[data-mode]').forEach((b) => b.addEventListener('click', () => this.setMode(b.dataset.mode)));
    const onRange = () => {
      const from = $('#r-from').value; const to = $('#r-to').value;
      if (from && to && from <= to) { this.range = { from, to }; this.update(); }
    };
    $('#r-from')?.addEventListener('change', onRange);
    $('#r-to')?.addEventListener('change', onRange);
    $('#y-prev')?.addEventListener('click', () => { this.year -= 1; this.update(); });
    $('#y-next')?.addEventListener('click', () => { this.year += 1; this.update(); });
    $('#export')?.addEventListener('click', (e) => exportExcel(e.currentTarget, this.currentRows, this.fileTag()));
    wireYearChart(el, this);
  },
};

/** Column chart of pay per month (single series, no legend: the title names it). */
function yearChart(list, year) {
  const months = Array.from({ length: 12 }, () => ({ pay: 0, min: 0 }));
  list.forEach((sh) => {
    const m = months[+sh.date.slice(5, 7) - 1];
    m.pay += shiftPay(sh, empById(sh.empId));
    m.min += shiftMinutes(sh.in, sh.out);
  });
  const max = Math.max(...months.map((m) => m.pay));
  const top = niceMax(max);
  const peak = max > 0 ? months.findIndex((m) => m.pay === max) : -1;
  return `
    <figure class="card ychart">
      <figcaption class="ychart-title">תשלום לפי חודש · ${year}</figcaption>
      <div class="ychart-plot">
        <div class="ychart-grid" aria-hidden="true">
          ${[top, top / 2, 0].map((t) => `<div class="gl"><span class="num">${fmtMoney(t)}</span></div>`).join('')}
        </div>
        <div class="ychart-bars">
          ${months.map((m, i) => `
            <button type="button" class="ybar" data-i="${i}" data-pay="${m.pay}" data-min="${m.min}"
              aria-label="${monthShort(i)}: ${fmtMoney(m.pay)}, ${fmtHM(m.min)} שעות. לחיצה למעבר לחודש">
              <span class="ybar-track"><span class="ybar-fill" style="height:${(m.pay / top) * 100}%">
                ${i === peak ? `<span class="ybar-val num">${fmtMoney(Math.round(m.pay))}</span>` : ''}
              </span></span>
              <span class="ybar-lbl"><span class="lbl-long">${monthShort(i)}</span><span class="lbl-short num">${i + 1}</span></span>
            </button>`).join('')}
        </div>
      </div>
      <div class="ychart-tip" role="status" hidden></div>
    </figure>`;
}
function wireYearChart(root, view) {
  const fig = root.querySelector('.ychart');
  if (!fig) return;
  const tip = fig.querySelector('.ychart-tip');
  const show = (b) => {
    const i = +b.dataset.i;
    tip.innerHTML = `<b>${esc(fmtMonth(`${view.year}-${pad(i + 1)}`))}</b><span class="num">${fmtMoney(+b.dataset.pay)}</span><span class="num muted">${fmtHM(+b.dataset.min)} שעות</span>`;
    tip.hidden = false;
    const fr = fig.getBoundingClientRect(); const br = b.getBoundingClientRect();
    const x = Math.min(Math.max(br.left + br.width / 2 - fr.left, 70), fr.width - 70);
    tip.style.left = `${x}px`;
  };
  fig.querySelectorAll('.ybar').forEach((b) => {
    b.addEventListener('pointerenter', () => show(b));
    b.addEventListener('focus', () => show(b));
    b.addEventListener('click', () => { view.mode = 'month'; sessionStorage.setItem('sumMode', 'month'); setMonth(`${view.year}-${pad(+b.dataset.i + 1)}`); view.update(); });
  });
  fig.addEventListener('pointerleave', () => { tip.hidden = true; });
  fig.addEventListener('focusout', (e) => { if (!fig.contains(e.relatedTarget)) tip.hidden = true; });
}

/* ---------- Printable monthly report for one employee ---------- */
const ReportView = {
  mount(el, id) {
    this.el = el; this.id = id; this.payments = [];
    this.unsub?.();
    this.unsub = state.store.watchPayments(id, (list) => { this.payments = list; if (mounted.view === this) this.update(); }, onDataError);
    this.update();
  },
  unmount() { this.unsub?.(); this.unsub = null; },
  update() {
    const el = this.el;
    if (!isLoaded()) { el.innerHTML = loadingHTML; return; }
    const emp = empById(this.id);
    if (!emp) { el.innerHTML = `<div class="empty"><h2>העובדת לא נמצאה</h2><a class="btn btn-secondary" href="#/">חזרה</a></div>`; return; }
    const list = (state.shifts || []).filter((sh) => sh.empId === emp.id)
      .sort((a, b) => a.date.localeCompare(b.date) || a.in.localeCompare(b.in));
    const a = aggOf(list).get(emp.id) || emptyAgg();
    const pays = this.payments.filter((p) => p.date.startsWith(state.month)).sort((x, y) => x.date.localeCompare(y.date));
    const hasNotes = list.some((sh) => sh.note);
    el.innerHTML = `
      <div class="report-bar no-print">
        <a class="btn btn-ghost" href="#/e/${emp.id}">${icon('chev-r')}חזרה</a>
        <span class="spacer"></span>
        <button type="button" class="btn btn-primary" id="print">${icon('download')}הדפסה / שמירה כ-PDF</button>
      </div>
      <article class="card report">
        <header class="report-head">
          <div>
            <h1>דוח שעות ותשלום</h1>
            <p class="report-who">${esc(emp.name)} · ${esc(fmtMonth(state.month))}</p>
          </div>
          <p class="muted report-date">הופק ב-${fmtDate(todayStr())}</p>
        </header>
        ${list.length ? `
        <div class="rtable-wrap">
          <table class="rtable">
            <thead><tr><th>תאריך</th><th>יום</th><th>כניסה</th><th>יציאה</th><th>שעות</th><th>סכום</th><th>שולם</th>${hasNotes ? '<th>הערה</th>' : ''}</tr></thead>
            <tbody>${list.map((sh) => `<tr>
              <td class="num">${fmtDayMonth(sh.date)}</td><td>${esc(fmtWeekday(sh.date))}</td>
              <td class="num">${fmtTime(sh.in)}</td><td class="num">${fmtTime(sh.out)}</td>
              <td class="num">${fmtHM(shiftMinutes(sh.in, sh.out))}</td>
              <td class="num">${fmtMoney(shiftPay(sh, emp))}${sh.special?.rate != null ? ' *' : ''}</td>
              <td>${sh.paid ? '✓' : '—'}</td>${hasNotes ? `<td>${esc(sh.note || '')}</td>` : ''}
            </tr>`).join('')}</tbody>
            <tfoot><tr><td colspan="4">סה״כ</td><td class="num">${fmtHM(a.minutes)}</td><td class="num">${fmtMoney(a.pay)}</td><td></td>${hasNotes ? '<td></td>' : ''}</tr></tfoot>
          </table>
        </div>
        ${list.some((sh) => sh.special?.rate != null) ? '<p class="muted report-foot">* משמרת עם תעריף מיוחד</p>' : ''}` : '<p class="muted">אין משמרות בחודש הזה.</p>'}
        <div class="report-sum">
          <div><span class="muted">סה״כ שעות</span><b class="num">${fmtHM(a.minutes)}</b></div>
          <div><span class="muted">סה״כ לתשלום</span><b class="num">${fmtMoney(a.pay)}</b></div>
          <div><span class="muted">שולם</span><b class="num">${fmtMoney(a.paidPay)}</b></div>
          <div><span class="muted">נותר לתשלום</span><b class="num">${fmtMoney(unpaidOf(a))}</b></div>
        </div>
        ${pays.length ? `
        <h2 class="report-sub">תשלומים שבוצעו בחודש</h2>
        <ul class="report-pays">${pays.map((p) => `<li><span class="num">${fmtDate(p.date)}</span><span>${esc(p.method)}</span><b class="num">${fmtMoney(p.amount)}</b></li>`).join('')}</ul>` : ''}
      </article>`;
    $('#print').addEventListener('click', () => window.print());
  },
};

/* ---------- Settings ---------- */
const SettingsView = {
  mount(el) {
    this.el = el;
    if (!isLoaded()) { el.innerHTML = loadingHTML; this.built = false; return; }
    this.build();
  },
  build() {
    this.built = true;
    const def = state.settings.defaultRate;
    this.el.innerHTML = `
      <div class="page-head"><h1>הגדרות</h1></div>
      <div class="settings">
        <form class="card" id="rate-form" novalidate>
          <h2>תעריף שעתי כללי</h2>
          <p class="muted" style="font-size:14px">חל על כל העובדות שאין להן תעריף אישי. תעריף אישי מגדירים בכרטיס של העובדת (כפתור "עריכה").</p>
          <div class="field">
            <label for="s-rate" class="sr-only">תעריף שעתי כללי</label>
            <div class="input-wrap">
              <input id="s-rate" class="input num" inputmode="decimal" autocomplete="off" value="${def ?? ''}" placeholder="לדוגמה: 40">
              <span class="input-suffix">₪</span>
            </div>
            <p class="field-error" id="s-rate-err"></p>
          </div>
          <label class="check" id="s-apply-wrap" hidden>
            <input type="checkbox" id="s-apply" checked>
            <span id="s-apply-txt"></span>
          </label>
          <button class="btn btn-primary" type="submit">שמירה</button>
        </form>
        <section class="card">
          <h2>תצוגת שעה</h2>
          ${fmtToggleHTML(true)}
        </section>
        <section class="card">
          <h2>צליל גלגל שיניים בגלגלת</h2>
          <div class="seg lg" role="radiogroup" aria-label="צליל בגלגלת">
            <button type="button" role="radio" data-sound="on" aria-checked="${soundOn()}">מופעל</button>
            <button type="button" role="radio" data-sound="off" aria-checked="${!soundOn()}">כבוי</button>
          </div>
        </section>
        <section class="card" id="archived"></section>
        <section class="card">
          <h2>חשבון</h2>
          <div class="row-between">
            <span class="muted" dir="ltr" style="overflow:hidden;text-overflow:ellipsis">${esc(state.user?.email || '')}</span>
            <button class="btn btn-secondary" id="signout" type="button">${icon('logout')}${state.store.demo ? 'איפוס הדגמה' : 'התנתקות'}</button>
          </div>
        </section>
        <section class="card">
          <h2>הוספה למסך הבית בטלפון</h2>
          <p class="muted" style="font-size:14px">
            <b>אייפון:</b> פתח ב-Safari ← כפתור השיתוף ← "הוסף למסך הבית".<br>
            <b>אנדרואיד:</b> פתח ב-Chrome ← תפריט ⋮ ← "הוספה למסך הבית".
          </p>
        </section>
      </div>`;

    const input = $('#s-rate');
    const applyWrap = $('#s-apply-wrap');
    const affected = () => {
      const r = parseRate(input.value);
      if (r == null || Number.isNaN(r) || r === state.settings.defaultRate) return [];
      return (state.shifts || []).filter((s) => { const e = empById(s.empId); return e && e.rate == null; });
    };
    const sync = () => {
      const list = affected();
      applyWrap.hidden = !list.length;
      $('#s-apply-txt').textContent = `לעדכן גם את ${list.length} המשמרות של ${fmtMonth(state.month)} (של עובדות בתעריף הכללי)`;
    };
    input.addEventListener('input', sync);

    $('#rate-form').addEventListener('submit', async (e) => {
      e.preventDefault();
      const r = parseRate(input.value);
      if (r == null || Number.isNaN(r)) { $('#s-rate-err').textContent = 'צריך להזין תעריף תקין'; input.focus(); return; }
      $('#s-rate-err').textContent = '';
      const btn = e.currentTarget.querySelector('button[type=submit]');
      btn.classList.add('is-loading'); btn.disabled = true;
      try {
        const list = $('#s-apply').checked ? affected() : [];
        await state.store.saveSettings({ defaultRate: r });
        if (list.length) await state.store.updateShifts(list.map((s) => s.id), { rate: r });
        toast('התעריף נשמר');
        applyWrap.hidden = true;
      } catch (err) { fail(err); } finally { btn.classList.remove('is-loading'); btn.disabled = false; }
    });
    $('#signout').addEventListener('click', () => state.store.signOut());
    this.el.querySelectorAll('[data-sound]').forEach((b) => b.addEventListener('click', () => {
      lsSet('wheelSound', b.dataset.sound);
      this.el.querySelectorAll('[data-sound]').forEach((x) => x.setAttribute('aria-checked', String(x === b)));
      if (b.dataset.sound === 'on') { unlockAudio(); gearClick(); } // short preview
    }));
    this.renderArchived();
  },
  update() {
    if (!this.built) { if (isLoaded()) this.build(); return; }
    this.renderArchived();
  },
  renderArchived() {
    const arch = state.employees.filter((e) => e.active === false).sort(byName);
    const box = $('#archived');
    box.hidden = !arch.length;
    box.innerHTML = `<h2>עובדות בארכיון</h2>
      <ul class="archived-list">${arch.map((e) => `
        <li>${avatar(e)}<span class="name">${esc(e.name)}</span>
          <button class="btn btn-ghost" type="button" data-restore="${e.id}">החזרה</button></li>`).join('')}
      </ul>`;
    box.querySelectorAll('[data-restore]').forEach((b) => b.addEventListener('click', async () => {
      try { await state.store.updateEmployee(b.dataset.restore, { active: true }); toast('העובדת הוחזרה לרשימה'); } catch (e) { fail(e); }
    }));
  },
};

/* =========================================================
   Wheel time picker
   ========================================================= */
const ITEM_H = 44;

/* Gear/ratchet click, synthesized with Web Audio (no sound files): a short filtered noise
   burst for the "tooth" plus a tiny falling metallic knock. Can be turned off in settings (per device). */
let audioCtx = null;
let clickNoise = null;
let lastClickAt = 0;
const CLICK_GAP = 0.05; // seconds between clicks at most ~20/sec, so fast scrolling stays distinct ticks
const soundOn = () => lsGet('wheelSound') !== 'off';
function unlockAudio() {
  if (!soundOn()) return;
  try {
    audioCtx ||= new (window.AudioContext || window.webkitAudioContext)();
    if (audioCtx.state === 'suspended') audioCtx.resume();
  } catch { audioCtx = null; }
}
function gearClick() {
  if (!soundOn() || !audioCtx) return;
  try {
    const ctx = audioCtx;
    const t = ctx.currentTime;
    if (t - lastClickAt < CLICK_GAP) return;
    lastClickAt = t;
    if (!clickNoise) {
      clickNoise = ctx.createBuffer(1, Math.floor(ctx.sampleRate * 0.012), ctx.sampleRate);
      const d = clickNoise.getChannelData(0);
      for (let i = 0; i < d.length; i++) d[i] = (Math.random() * 2 - 1) * (1 - i / d.length) ** 6;
    }
    const noise = ctx.createBufferSource();
    noise.buffer = clickNoise;
    const band = ctx.createBiquadFilter();
    band.type = 'bandpass';
    band.frequency.value = 3000 + Math.random() * 500; // slight variation, like real teeth
    band.Q.value = 5;
    const ng = ctx.createGain();
    ng.gain.setValueAtTime(0.45, t);
    ng.gain.exponentialRampToValueAtTime(0.001, t + 0.012);
    noise.connect(band).connect(ng).connect(ctx.destination);
    noise.start(t);

    const knock = ctx.createOscillator();
    knock.type = 'square';
    knock.frequency.setValueAtTime(1700, t);
    knock.frequency.exponentialRampToValueAtTime(700, t + 0.008);
    const kg = ctx.createGain();
    kg.gain.setValueAtTime(0.06, t);
    kg.gain.exponentialRampToValueAtTime(0.001, t + 0.01);
    knock.connect(kg).connect(ctx.destination);
    knock.start(t);
    knock.stop(t + 0.012);
  } catch { /* audio unavailable */ }
}
/** Feedback on every number change: vibration where the browser allows it (Android phones),
 *  plus a short visual "click" of the selection band everywhere (browsers can't drive the Mac trackpad's haptics). */
function tick(wheel) {
  if (matchMedia('(pointer: coarse)').matches && navigator.userActivation?.hasBeenActive !== false) {
    try { navigator.vibrate?.(6); } catch { /* not supported */ }
  }
  gearClick();
  const band = wheel.closest('.wheels')?.querySelector('.wheel-band');
  if (!band) return;
  band.classList.remove('tick');
  void band.offsetWidth; // restart the animation
  band.classList.add('tick');
}
function openWheel(key, view) {
  unlockAudio();
  const dlg = $('#wheel');
  const twelve = is12();
  const last = view.lastHours();
  const start = view.form[key] || last?.[key] || (key === 'in' ? '08:00' : '16:00');
  const [h, m] = start.split(':').map(Number);
  const cols = [
    { id: 'h', label: 'שעות', items: twelve ? [12, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11].map(String) : [...Array(24)].map((_, i) => pad(i)), idx: twelve ? h % 12 : h },
    { id: 'm', label: 'דקות', items: [...Array(60)].map((_, i) => pad(i)), idx: m },
  ];
  if (twelve) cols.push({ id: 'ap', label: 'AM או PM', items: ['AM', 'PM'], idx: h < 12 ? 0 : 1 });
  const value = () => `${pad(cols[0].idx + (twelve && cols[2].idx === 1 ? 12 : 0))}:${pad(cols[1].idx)}`;

  dlg.innerHTML = `
    <div class="grabber" aria-hidden="true"></div>
    <div class="wheel-body">
      <div class="sheet-head">
        <h2 id="wheel-title">${key === 'in' ? 'שעת כניסה' : 'שעת יציאה'}</h2>
        <span class="wheel-value num" id="wheel-value" dir="ltr" aria-live="polite"></span>
      </div>
      <div class="wheels" dir="ltr">
        <div class="wheel-band" aria-hidden="true"></div>
        ${cols.map((c, ci) => `${ci === 1 ? '<div class="wheel-colon" aria-hidden="true">:</div>' : ''}
          <div class="wheel ${c.id === 'ap' ? 'narrow' : ''}" tabindex="0" role="listbox" aria-label="${c.label}">
            <div class="wheel-pad"></div>
            ${c.items.map((t, i) => `<div class="wheel-item" role="option" data-i="${i}">${t}</div>`).join('')}
            <div class="wheel-pad"></div>
          </div>`).join('')}
      </div>
      <p class="field-hint" style="text-align:center">גוללים למעלה/למטה או מקישים על מספר</p>
      <div class="sheet-actions">
        <button type="button" class="btn btn-primary btn-lg" id="wheel-ok">אישור</button>
        <button type="button" class="btn btn-secondary btn-lg" id="wheel-cancel">ביטול</button>
      </div>
    </div>`;

  const ok = () => { view.setTime(key, value()); dlg.close(); };
  const wheels = [...dlg.querySelectorAll('.wheel')];
  const smooth = matchMedia('(prefers-reduced-motion: reduce)').matches ? 'auto' : 'smooth';
  const markAll = () => {
    wheels.forEach((w, ci) => w.querySelectorAll('.wheel-item').forEach((it, i) => {
      const on = i === cols[ci].idx;
      it.classList.toggle('on', on);
      it.setAttribute('aria-selected', String(on));
    }));
    $('#wheel-value').textContent = fmtTime(value());
  };
  wheels.forEach((w, ci) => {
    const col = cols[ci];
    const clamp = (i) => Math.max(0, Math.min(col.items.length - 1, i));
    w.addEventListener('scroll', () => {
      const i = clamp(Math.round(w.scrollTop / ITEM_H));
      if (i !== col.idx) { col.idx = i; markAll(); tick(w); }
    }, { passive: true });
    w.addEventListener('click', (e) => {
      const it = e.target.closest('.wheel-item');
      if (it) w.scrollTo({ top: +it.dataset.i * ITEM_H, behavior: smooth });
    });
    w.addEventListener('keydown', (e) => {
      if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
        e.preventDefault();
        w.scrollTo({ top: clamp(col.idx + (e.key === 'ArrowDown' ? 1 : -1)) * ITEM_H, behavior: smooth });
      } else if (e.key === 'Enter') { e.preventDefault(); ok(); }
    });
  });
  $('#wheel-ok').addEventListener('click', ok);
  $('#wheel-cancel').addEventListener('click', () => dlg.close());
  dlg.showModal();
  wheels.forEach((w, ci) => { w.scrollTop = cols[ci].idx * ITEM_H; });
  markAll();
  wheels[0].focus({ preventScroll: true });
}
$('#wheel').addEventListener('click', (e) => { if (e.target.id === 'wheel') e.target.close(); });

/* ---------- switching 24h / AM-PM (synced to all devices via settings) ---------- */
function syncFmtToggles() {
  const fmt = is12() ? '12' : '24';
  document.querySelectorAll('[data-fmt]').forEach((b) => b.setAttribute('aria-checked', String(b.dataset.fmt === fmt)));
}
async function setTimeFormat(fmt) {
  if ((is12() ? '12' : '24') === fmt) return;
  lsSet('timeFormat', fmt);
  state.settings = { ...state.settings, timeFormat: fmt };
  refresh();
  try { await state.store.saveSettings({ timeFormat: fmt }); } catch (e) { fail(e); }
}
document.addEventListener('click', (e) => {
  const b = e.target.closest('[data-fmt]');
  if (b) setTimeFormat(b.dataset.fmt);
});

/* =========================================================
   Excel export (SheetJS, loaded on demand)
   ========================================================= */
let xlsxPromise;
function loadXLSX() {
  if (window.XLSX) return Promise.resolve(window.XLSX);
  xlsxPromise ||= new Promise((resolve, reject) => {
    const s = document.createElement('script');
    s.src = 'https://cdnjs.cloudflare.com/ajax/libs/xlsx/0.18.5/xlsx.full.min.js';
    s.onload = () => resolve(window.XLSX);
    s.onerror = () => { xlsxPromise = null; reject(new Error('xlsx load failed')); };
    document.head.appendChild(s);
  });
  return xlsxPromise;
}

async function exportExcel(btn, allRows, tag) {
  btn.classList.add('is-loading'); btn.disabled = true;
  try {
    const XLSX = await loadXLSX();
    const rows = allRows.filter((r) => r.shifts.length);
    const wb = XLSX.utils.book_new();
    wb.Workbook = { Views: [{ RTL: true }] };
    const hours = (min) => round2(min / 60);

    const sum = [['עובדת', 'משמרות', 'שעות (עשרוני)', 'שעות (ש:ד)', 'תעריף לשעה', 'סה״כ (₪)', 'שולם (₪)', 'נותר לתשלום (₪)']];
    rows.forEach((r) => {
      const rates = [...new Set(r.shifts.map((s) => shiftRate(s, r.emp)))];
      sum.push([r.emp.name, r.shifts.length, hours(r.minutes), fmtHM(r.minutes), rates.length > 1 ? 'משתנה' : rates[0], round2(r.pay), round2(r.paidPay), unpaidOf(r)]);
    });
    const tMin = rows.reduce((s, r) => s + r.minutes, 0);
    sum.push([], ['סה״כ', rows.reduce((s, r) => s + r.shifts.length, 0), hours(tMin), fmtHM(tMin), '', round2(rows.reduce((s, r) => s + r.pay, 0)), round2(rows.reduce((s, r) => s + r.paidPay, 0)), round2(rows.reduce((s, r) => s + r.pay - r.paidPay, 0))]);
    const ws = XLSX.utils.aoa_to_sheet(sum);
    ws['!cols'] = [{ wch: 18 }, { wch: 9 }, { wch: 14 }, { wch: 12 }, { wch: 12 }, { wch: 14 }];
    XLSX.utils.book_append_sheet(wb, ws, 'סיכום');

    const used = new Set(['סיכום']);
    rows.forEach((r) => {
      const data = [['תאריך', 'יום', 'כניסה', 'יציאה', 'שעות (עשרוני)', 'שעות (ש:ד)', 'תעריף לשעה', 'תעריף מיוחד', 'שעות בתעריף מיוחד', 'סכום (₪)', 'שולם', 'הערה']];
      [...r.shifts].sort((a, b) => a.date.localeCompare(b.date) || a.in.localeCompare(b.in)).forEach((s) => {
        const min = shiftMinutes(s.in, s.out);
        const rate = shiftRate(s, r.emp);
        const d = parseDate(s.date);
        data.push([`${pad(d.getDate())}/${pad(d.getMonth() + 1)}/${d.getFullYear()}`, fmtWeekday(s.date), fmtTime(s.in), fmtTime(s.out), hours(min), fmtHM(min), rate, s.special?.rate ?? '', s.special ? hours(specialMinutes(s)) : '', round2(shiftPay(s, r.emp)), s.paid ? 'כן' : 'לא', s.note || '']);
      });
      data.push([], ['סה״כ', '', '', '', hours(r.minutes), fmtHM(r.minutes), '', '', '', round2(r.pay), `שולם ${round2(r.paidPay)}`]);
      const sh = XLSX.utils.aoa_to_sheet(data);
      sh['!cols'] = [{ wch: 12 }, { wch: 8 }, { wch: 8 }, { wch: 8 }, { wch: 14 }, { wch: 12 }, { wch: 12 }, { wch: 12 }];
      let name = r.emp.name.replace(/[[\]:*?/\\]/g, ' ').trim().slice(0, 28) || 'עובדת';
      let n = 2; const baseName = name;
      while (used.has(name)) name = `${baseName.slice(0, 26)} ${n++}`;
      used.add(name);
      XLSX.utils.book_append_sheet(wb, sh, name);
    });

    XLSX.writeFile(wb, `שעות-${tag}.xlsx`);
    toast('הקובץ ירד');
  } catch (e) { fail(e); } finally { btn.classList.remove('is-loading'); btn.disabled = false; }
}

/* =========================================================
   Routing + month
   ========================================================= */
function parseRoute() {
  const h = location.hash.replace(/^#\/?/, '');
  const [name, id] = h.split('/');
  if (name === 'e' && id) return { name: 'employee', id, nav: 'home' };
  if (name === 'r' && id) return { name: 'report', id, nav: 'home' };
  if (name === 'summary') return { name: 'summary', nav: 'summary' };
  if (name === 'settings') return { name: 'settings', nav: 'settings' };
  return { name: 'home', nav: 'home' };
}
const VIEWS = { home: HomeView, employee: EmployeeView, report: ReportView, summary: SummaryView, settings: SettingsView };

function route() {
  const r = parseRoute();
  const key = `${r.name}/${r.id || ''}`;
  document.querySelectorAll('[data-nav]').forEach((a) => {
    if (a.dataset.nav === r.nav) a.setAttribute('aria-current', 'page'); else a.removeAttribute('aria-current');
  });
  $('.month-switch').hidden = r.name === 'settings' || (r.name === 'summary' && SummaryView.mode !== 'month');
  if (mounted.key === key) { mounted.view.update(); return; }
  mounted.view?.unmount?.();
  const view = VIEWS[r.name];
  mounted = { key, view };
  const main = $('#view');
  view.mount(main, r.id);
  window.scrollTo(0, 0);
}

function renderMonth() {
  const lbl = $('#m-label');
  lbl.textContent = fmtMonth(state.month);
  const isCur = state.month === currentMonth();
  lbl.classList.toggle('is-current', isCur);
  lbl.title = isCur ? '' : 'חזרה לחודש הנוכחי';
}

function setMonth(month, { keepForm = false } = {}) {
  if (month === state.month) return;
  state.month = month;
  sessionStorage.setItem('month', month);
  renderMonth();
  subscribeShifts();
  if (!keepForm && mounted.view === EmployeeView && !EmployeeView.form.editingId && EmployeeView.built && !EmployeeView.clock()) {
    EmployeeView.fDate.value = EmployeeView.defaultDate();
    EmployeeView.onInput();
  }
  if (mounted.view === EmployeeView && EmployeeView.form.editingId) EmployeeView.stopEdit();
  refresh();
}

const refresh = () => { if (mounted.view) mounted.view.update(); syncFmtToggles(); };

/* =========================================================
   Data subscriptions + auth
   ========================================================= */
function onDataError(e) {
  console.error(e);
  if (e?.code === 'permission-denied') {
    showScreen('denied');
    $('#denied-email').textContent = state.user?.email || '';
  } else {
    toast('בעיה בחיבור לנתונים', { error: true });
  }
}

function subscribeShifts() {
  unsubShifts?.();
  state.shifts = null;
  unsubShifts = state.store.watchShifts(state.month, (list) => { state.shifts = list; refresh(); }, onDataError);
}

function subscribeAll() {
  unsubs.forEach((u) => u()); unsubs = [];
  unsubs.push(state.store.watchSettings((s) => { state.settings = s; refresh(); }, onDataError));
  unsubs.push(state.store.watchEmployees((list) => { state.employees = list; refresh(); }, onDataError));
  unsubs.push(state.store.watchClocks((list) => {
    state.clocks = Object.fromEntries(list.map((c) => [c.id, c]));
    refresh();
  }, onDataError));
  subscribeShifts();
}

function showScreen(name) {
  ['boot', 'login', 'denied', 'app'].forEach((id) => { $(`#${id}`).hidden = id !== name; });
}

async function main() {
  try {
    state.store = await createStore();
  } catch (e) {
    console.error(e);
    $('#boot').innerHTML = '<p>לא הצלחתי לטעון את המערכת. בדוק את החיבור לאינטרנט ורענן את הדף.</p>';
    return;
  }
  $('#demo-banner').hidden = !state.store.demo;
  // A write that was saved on the device but later refused by the server (rare): say so instead of hiding it.
  state.store.onLateError = (e) => {
    if (e?.code === 'permission-denied') onDataError(e);
    else { console.error(e); toast('שינוי אחד לא הסתנכרן לשרת – כדאי לבדוק את הרשימה', { error: true }); }
  };
  const syncOnline = () => { $('#offline-banner').hidden = navigator.onLine; };
  window.addEventListener('online', syncOnline);
  window.addEventListener('offline', syncOnline);
  syncOnline();

  $('#btn-signin').addEventListener('click', async () => {
    const btn = $('#btn-signin');
    $('#login-error').textContent = '';
    btn.disabled = true;
    try { await state.store.signIn(); } catch (e) {
      if (e?.code !== 'auth/popup-closed-by-user' && e?.code !== 'auth/cancelled-popup-request') {
        console.error(e);
        $('#login-error').textContent = 'ההתחברות נכשלה. נסה שוב.';
      }
    } finally { btn.disabled = false; }
  });
  $('#btn-denied-out').addEventListener('click', () => state.store.signOut());

  $('#m-prev').addEventListener('click', () => setMonth(shiftMonthBy(state.month, -1)));
  $('#m-next').addEventListener('click', () => setMonth(shiftMonthBy(state.month, 1)));
  $('#m-label').addEventListener('click', () => setMonth(currentMonth()));
  window.addEventListener('hashchange', () => { if (state.user) route(); });

  state.store.onAuth((user) => {
    state.user = user;
    if (!user) {
      unsubs.forEach((u) => u()); unsubs = []; unsubShifts?.(); unsubShifts = null;
      state.settings = state.employees = state.shifts = null;
      state.clocks = {};
      mounted.view?.unmount?.();
      mounted = { key: null, view: null };
      showScreen('login');
      return;
    }
    showScreen('app');
    renderMonth();
    subscribeAll();
    route();
  });
}

// Keeps the app itself on the phone, so it opens even with no signal (data is already kept by Firestore).
if ('serviceWorker' in navigator && !new URLSearchParams(location.search).has('nosw')) {
  window.addEventListener('load', () => navigator.serviceWorker.register('sw.js').catch((e) => console.warn('sw', e)));
}

main();

// Shared tokens + component helpers for the CarePlix Ring design canvas.
// Values are the resolved dark-mode tokens from docs/ux/06-design-system.md.
export const T = {
  base: '#08090C', elevated: '#101319', card: '#171B22', recessed: '#0D1015',
  primary: '#F2F4F8', secondary: '#A7B0BF', tertiary: '#868F9C', hairline: '#282E38', strong: '#616977',
  crimson: '#E01B47', coral: '#FF6B57', ink: '#FF8A6B',
  optimal: '#06E19F', good: '#64BDE9', fair: '#DF9109', poor: '#F95725', abstained: '#969BA7',
  deep: '#3A5BD9', light: '#7C9BEA', rem: '#B48CF2', awake: '#F0A35E',
};
export const FONT = "-apple-system, 'SF Pro Text', 'SF Pro Display', system-ui, 'Helvetica Neue', sans-serif";

export const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

// ---------- icons (stroke, 24 grid) ----------
const ico = (paths, size = 22, color = 'currentColor', sw = 1.8) =>
  `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="${color}" stroke-width="${sw}" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" style="flex:none">${paths}</svg>`;
export const icons = {
  sun: (s, c) => ico('<path d="M3 17h18"></path><path d="M6 17a6 6 0 0 1 12 0"></path><path d="M12 5v2"></path><path d="M5 9l1.5 1.5"></path><path d="M19 9l-1.5 1.5"></path>', s, c),
  moon: (s, c) => ico('<path d="M20 14.5A8 8 0 0 1 9.5 4a8 8 0 1 0 10.5 10.5z"></path>', s, c),
  wave: (s, c) => ico('<path d="M2 12h3l2-6 3 12 3-9 2 5 2-2h5"></path>', s, c),
  wind: (s, c) => ico('<path d="M3 8h10a3 3 0 1 0-3-3"></path><path d="M3 12h15a3 3 0 1 1-3 3"></path><path d="M3 16h7a2 2 0 1 1-2 2"></path>', s, c),
  ring: (s, c) => ico('<circle cx="12" cy="12" r="8"></circle><circle cx="12" cy="12" r="4.5"></circle>', s, c),
  battery: (s, c) => ico('<rect x="2.5" y="7" width="16" height="10" rx="2.5"></rect><path d="M21 10.5v3"></path>', s, c),
  bolt: (s, c) => ico('<path d="M13 2 4 14h6l-1 8 9-12h-6z"></path>', s, c),
  chevron: (s, c) => ico('<path d="m9 6 6 6-6 6"></path>', s, c),
  check: (s, c) => ico('<path d="m5 12 4 4 10-10"></path>', s, c),
  heart: (s, c) => ico('<path d="M12 20s-7-4.4-7-10a4 4 0 0 1 7-2.6A4 4 0 0 1 19 10c0 5.6-7 10-7 10z"></path>', s, c),
  drop: (s, c) => ico('<path d="M12 3s6 6.5 6 11a6 6 0 0 1-12 0c0-4.5 6-11 6-11z"></path>', s, c),
  pulse: (s, c) => ico('<path d="M3 12h4l2-5 3 10 3-7 1.5 2H21"></path>', s, c),
  thermo: (s, c) => ico('<path d="M10 4a2 2 0 0 1 4 0v9.5a4 4 0 1 1-4 0z"></path><path d="M12 9v6"></path>', s, c),
  steps: (s, c) => ico('<path d="M8 3c-2 0-3 2-3 5s1 5 2.5 5S11 11 11 8 10 3 8 3z"></path><path d="M16 9c-2 0-3 2-3 5s1 5 2.5 5S19 17 19 14s-1-5-3-5z"></path>', s, c),
  bluetooth: (s, c) => ico('<path d="m6 7 12 10-6 5V2l6 5L6 17"></path>', s, c),
  sync: (s, c) => ico('<path d="M20 11a8 8 0 0 0-14.5-4"></path><path d="M4 13a8 8 0 0 0 14.5 4"></path><path d="M4 4v4h4"></path><path d="M20 20v-4h-4"></path>', s, c),
  brain: (s, c) => ico('<path d="M9 4a3 3 0 0 0-3 3 3 3 0 0 0-2 5 3 3 0 0 0 2 5 3 3 0 0 0 6 1V6a3 3 0 0 0-3-2z"></path><path d="M15 4a3 3 0 0 1 3 3 3 3 0 0 1 2 5 3 3 0 0 1-2 5 3 3 0 0 1-6 1V6a3 3 0 0 1 3-2z"></path>', s, c),
  hand: (s, c) => ico('<path d="M8 12V6a1.5 1.5 0 0 1 3 0v5"></path><path d="M11 11V4a1.5 1.5 0 0 1 3 0v7"></path><path d="M14 11V6a1.5 1.5 0 0 1 3 0v6"></path><path d="M17 12V9a1.5 1.5 0 0 1 3 0v6a6 6 0 0 1-6 6h-2a6 6 0 0 1-5-2.7L4.8 15a1.5 1.5 0 0 1 2.4-1.8L8 14"></path>', s, c),
  info: (s, c) => ico('<circle cx="12" cy="12" r="9"></circle><path d="M12 11v5"></path><path d="M12 8h.01"></path>', s, c),
  gear: (s, c) => ico('<circle cx="12" cy="12" r="3"></circle><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"></path>', s, c),
  plus: (s, c) => ico('<path d="M12 5v14"></path><path d="M5 12h14"></path>', s, c),
  play: (s, c) => ico('<path d="M7 4v16l13-8z"></path>', s, c),
  warn: (s, c) => ico('<path d="M12 3 2 20h20z"></path><path d="M12 9v5"></path><path d="M12 17h.01"></path>', s, c),
  back: (s, c) => ico('<path d="m15 6-6 6 6 6"></path>', s, c),
};

// ---------- primitives ----------
export const arc = (size, pct, color, stroke, track = T.recessed, extra = '') => {
  const r = (size - stroke) / 2, c = 2 * Math.PI * r, off = c * (1 - Math.max(0, Math.min(1, pct)));
  return `<svg width="${size}" height="${size}" viewBox="0 0 ${size} ${size}" aria-hidden="true" style="display:block">
<circle cx="${size / 2}" cy="${size / 2}" r="${r}" fill="none" stroke="${track}" stroke-width="${stroke}"></circle>
<circle cx="${size / 2}" cy="${size / 2}" r="${r}" fill="none" stroke="${color}" stroke-width="${stroke}" stroke-linecap="round" stroke-dasharray="${c.toFixed(2)}" stroke-dashoffset="${off.toFixed(2)}" transform="rotate(-90 ${size / 2} ${size / 2})"></circle>${extra}</svg>`;
};

export const sparkline = (vals, color, w = 88, h = 26, band = null, outlierIdx = []) => {
  const min = Math.min(...vals, band ? band[0] : Infinity), max = Math.max(...vals, band ? band[1] : -Infinity);
  const sx = (i) => (i / (vals.length - 1)) * (w - 4) + 2, sy = (v) => h - 3 - ((v - min) / (max - min || 1)) * (h - 6);
  const pts = vals.map((v, i) => `${sx(i).toFixed(1)},${sy(v).toFixed(1)}`).join(' ');
  const bandRect = band ? `<rect x="0" y="${sy(band[1]).toFixed(1)}" width="${w}" height="${(sy(band[0]) - sy(band[1])).toFixed(1)}" fill="${T.recessed}" rx="2"></rect>` : '';
  const dots = outlierIdx.map((i) => `<circle cx="${sx(i).toFixed(1)}" cy="${sy(vals[i]).toFixed(1)}" r="2.5" fill="${T.fair}"></circle>`).join('');
  const last = `<circle cx="${sx(vals.length - 1).toFixed(1)}" cy="${sy(vals[vals.length - 1]).toFixed(1)}" r="2.5" fill="${color}"></circle>`;
  return `<svg width="${w}" height="${h}" viewBox="0 0 ${w} ${h}" aria-hidden="true" style="display:block">${bandRect}<polyline points="${pts}" fill="none" stroke="${color}" stroke-width="1.6" stroke-linejoin="round" stroke-linecap="round"></polyline>${dots}${last}</svg>`;
};

// line chart with band, w x h, values array (null = gap), optional dots [{i,v}]
export const lineChart = (vals, { w = 326, h = 120, color = T.primary, band = null, dots = [], xLabels = [], yMin, yMax, gapAt = [] } = {}) => {
  const present = vals.filter((v) => v != null);
  const min = yMin ?? Math.min(...present, band ? band[0] : Infinity) - 2, max = yMax ?? Math.max(...present, band ? band[1] : -Infinity) + 2;
  const padL = 0, padB = 18, plotH = h - padB;
  const sx = (i) => padL + (i / (vals.length - 1)) * (w - padL - 2), sy = (v) => plotH - 4 - ((v - min) / (max - min || 1)) * (plotH - 8);
  let d = '', pen = false;
  vals.forEach((v, i) => { if (v == null) { pen = false; return; } d += (pen ? ' L' : ' M') + `${sx(i).toFixed(1)} ${sy(v).toFixed(1)}`; pen = true; });
  const bandRect = band ? `<rect x="0" y="${sy(band[1]).toFixed(1)}" width="${w}" height="${(sy(band[0]) - sy(band[1])).toFixed(1)}" fill="${T.recessed}" rx="3"></rect>` : '';
  const grid = [0.25, 0.5, 0.75].map((f) => `<line x1="0" x2="${w}" y1="${(plotH * f).toFixed(1)}" y2="${(plotH * f).toFixed(1)}" stroke="${T.hairline}" stroke-width="0.5"></line>`).join('');
  const dotsSvg = dots.map((p) => `<circle cx="${sx(p.i).toFixed(1)}" cy="${sy(p.v).toFixed(1)}" r="3.5" fill="${p.color || T.coral}" stroke="${T.card}" stroke-width="1.5"></circle>`).join('');
  const labels = xLabels.map((l, k) => `<text x="${(k / (xLabels.length - 1)) * (w - 2)}" y="${h - 4}" fill="${T.tertiary}" font-size="10" font-family="${FONT}" text-anchor="${k === 0 ? 'start' : k === xLabels.length - 1 ? 'end' : 'middle'}">${esc(l)}</text>`).join('');
  const gaps = gapAt.map(([a, b]) => `<rect x="${sx(a).toFixed(1)}" y="0" width="${(sx(b) - sx(a)).toFixed(1)}" height="${plotH}" fill="url(#hatch)" opacity="0.9"></rect>`).join('');
  return `<svg width="${w}" height="${h}" viewBox="0 0 ${w} ${h}" aria-hidden="true" style="display:block"><defs><pattern id="hatch" width="6" height="6" patternUnits="userSpaceOnUse" patternTransform="rotate(45)"><line x1="0" y1="0" x2="0" y2="6" stroke="${T.hairline}" stroke-width="2"></line></pattern></defs>${bandRect}${grid}${gaps}<path d="${d.trim()}" fill="none" stroke="${color}" stroke-width="1.8" stroke-linejoin="round" stroke-linecap="round"></path>${dotsSvg}${labels}</svg>`;
};

export const bars = (vals, { w = 326, h = 64, color = T.good, max = null, radius = 2, gap = 2 } = {}) => {
  const m = max ?? Math.max(...vals, 1), bw = (w - gap * (vals.length - 1)) / vals.length;
  return `<svg width="${w}" height="${h}" viewBox="0 0 ${w} ${h}" aria-hidden="true" style="display:block">${vals.map((v, i) => { const bh = Math.max(2, (v / m) * h); return `<rect x="${(i * (bw + gap)).toFixed(1)}" y="${(h - bh).toFixed(1)}" width="${bw.toFixed(1)}" height="${bh.toFixed(1)}" rx="${radius}" fill="${v === 0 ? T.hairline : color}"></rect>`; }).join('')}</svg>`;
};

// hypnogram: stages array of 'awake'|'rem'|'light'|'deep'|'gap', each = N minutes
export const hypnogram = (stages, { w = 326, h = 132, lossAt = null, labels = ['23:12', '01', '03', '05', '06:54'], labelFracs = null } = {}) => {
  const lanes = { awake: 0, rem: 1, light: 2, deep: 3 }, laneH = 22, gapY = 6, top = 4;
  const n = stages.length, bw = w / n;
  const laneLabels = Object.entries(lanes).map(([k, i]) => `<text x="0" y="${top + i * (laneH + gapY) + laneH / 2 + 3.5}" fill="${T.tertiary}" font-size="10" font-family="${FONT}">${k === 'rem' ? 'REM' : k[0].toUpperCase() + k.slice(1)}</text>`).join('');
  const offset = 44, pw = w - offset;
  const pbw = pw / n;
  let blocks = '', prev = null, start = 0;
  const flush = (end) => { if (prev == null) return; if (prev === 'gap') { blocks += `<rect x="${(offset + start * pbw).toFixed(1)}" y="${top}" width="${((end - start) * pbw).toFixed(1)}" height="${4 * laneH + 3 * gapY}" fill="url(#hatch2)"></rect>`; return; } const y = top + lanes[prev] * (laneH + gapY); blocks += `<rect x="${(offset + start * pbw).toFixed(1)}" y="${y}" width="${Math.max(2, (end - start) * pbw).toFixed(1)}" height="${laneH}" rx="3" fill="${T[prev]}"></rect>`; };
  stages.forEach((s, i) => { if (s !== prev) { flush(i); prev = s; start = i; } }); flush(n);
  // connectors between consecutive different stages
  let conn = ''; for (let i = 1; i < n; i++) { if (stages[i] !== stages[i - 1] && stages[i] !== 'gap' && stages[i - 1] !== 'gap') { const y1 = top + lanes[stages[i - 1]] * (laneH + gapY) + laneH / 2, y2 = top + lanes[stages[i]] * (laneH + gapY) + laneH / 2; conn += `<line x1="${(offset + i * pbw).toFixed(1)}" x2="${(offset + i * pbw).toFixed(1)}" y1="${y1}" y2="${y2}" stroke="${T.strong}" stroke-width="1"></line>`; } }
  const loss = lossAt != null ? `<line x1="${(offset + lossAt * pbw).toFixed(1)}" x2="${(offset + lossAt * pbw).toFixed(1)}" y1="0" y2="${h - 16}" stroke="${T.poor}" stroke-width="1.5" stroke-dasharray="3 3"></line>` : '';
  const xl = labels.map((l, k) => `<text x="${offset + (labelFracs ? labelFracs[k] : k / (labels.length - 1)) * pw}" y="${h - 2}" fill="${T.tertiary}" font-size="10" font-family="${FONT}" text-anchor="${k === 0 ? 'start' : k === labels.length - 1 ? 'end' : 'middle'}">${esc(l)}</text>`).join('');
  return `<svg width="${w}" height="${h}" viewBox="0 0 ${w} ${h}" aria-hidden="true" style="display:block"><defs><pattern id="hatch2" width="6" height="6" patternUnits="userSpaceOnUse" patternTransform="rotate(45)"><line x1="0" y1="0" x2="0" y2="6" stroke="${T.hairline}" stroke-width="2"></line></pattern></defs>${laneLabels}${conn}${blocks}${loss}${xl}</svg>`;
};

// ---------- components ----------
export const chip = (kind, text) => {
  const map = { typical: [T.good, icons.check], outside: [T.fair, icons.warn], learning: [T.abstained, icons.info], notmeasured: [T.abstained, icons.info], optimal: [T.optimal, icons.check], good: [T.good, icons.check], fair: [T.fair, icons.warn], low: [T.poor, icons.warn] };
  const [c, ic] = map[kind] || map.typical;
  return `<span style="display:inline-flex; align-items:center; gap:4px; padding:3px 8px 3px 6px; border-radius:999px; background:${c}1F; color:${c}; font-size:12px; font-weight:600; letter-spacing:0.1px; white-space:nowrap;">${ic(13, c)}${esc(text)}</span>`;
};

export const card = (inner, style = '') => `<div style="background:${T.card}; border:0.5px solid ${T.hairline}; border-radius:20px; padding:16px; display:flex; flex-direction:column; gap:12px; ${style}">${inner}</div>`;

export const eyebrow = (t) => `<div style="font-size:12px; font-weight:600; letter-spacing:0.8px; text-transform:uppercase; color:${T.tertiary};">${esc(t)}</div>`;
export const sectionHeader = (title, detail = '') => `<div style="display:flex; justify-content:space-between; align-items:baseline; padding:0 4px;"><div style="font-size:20px; font-weight:600; color:${T.primary}; letter-spacing:-0.2px;">${esc(title)}</div>${detail ? `<div style="font-size:13px; color:${T.tertiary};">${esc(detail)}</div>` : ''}</div>`;
export const provenance = (t) => `<div style="font-size:12px; color:${T.tertiary}; line-height:16px;">${esc(t)}</div>`;
export const wellnessTag = () => `<div style="display:inline-flex; align-items:center; gap:6px; font-size:11px; color:${T.tertiary}; border:0.5px solid ${T.hairline}; border-radius:999px; padding:4px 10px; align-self:flex-start;">${icons.info(12, T.tertiary)}Information only · not medical advice</div>`;

export const numeral = (v, unit, size = 44, unitSize = 17, color = T.primary) => `<div style="display:flex; align-items:baseline; gap:6px;"><span style="font-size:${size}px; font-weight:${size >= 60 ? 500 : 600}; letter-spacing:${size >= 44 ? '-1.5px' : '-0.5px'}; color:${color}; font-variant-numeric:tabular-nums; line-height:1;">${esc(v)}</span>${unit ? `<span style="font-size:${unitSize}px; font-weight:500; color:${T.secondary};">${esc(unit)}</span>` : ''}</div>`;

export const primaryButton = (t, style = '') => `<div style="display:flex; align-items:center; justify-content:center; height:52px; border-radius:16px; background:${T.primary}; color:${T.base}; font-size:17px; font-weight:600; ${style}">${esc(t)}</div>`;
export const secondaryButton = (t, style = '') => `<div style="display:flex; align-items:center; justify-content:center; height:52px; border-radius:16px; background:${T.card}; border:0.5px solid ${T.strong}; color:${T.primary}; font-size:17px; font-weight:600; ${style}">${esc(t)}</div>`;
export const brandButton = (t, style = '') => `<div style="display:flex; align-items:center; justify-content:center; height:52px; border-radius:16px; background:linear-gradient(135deg, ${T.crimson}, ${T.coral}); color:#FFFFFF; font-size:17px; font-weight:600; ${style}">${esc(t)}</div>`;

// vital tile: 2-col grid cell
export const vitalTile = ({ title, value, unit, state, stateText, hist, color = T.primary, band = null, outliers = [], prov }) => card(`
  <div style="display:flex; justify-content:space-between; align-items:center;"><div style="font-size:13px; font-weight:600; color:${T.secondary};">${esc(title)}</div></div>
  ${numeral(value, unit, 30, 14)}
  <div style="display:flex; justify-content:space-between; align-items:flex-end; gap:8px;">${chip(state, stateText)}${hist && hist.length > 1 ? sparkline(hist, color, 76, 24, band, outliers) : ''}</div>
  ${prov ? provenance(prov) : ''}`, 'padding:14px; gap:10px;');

// score shortcut: compact ring + label
export const scoreShortcut = (label, value, color, pct, sub) => `<div style="display:flex; flex-direction:column; align-items:center; gap:6px; flex:1;">
  <div style="position:relative; width:64px; height:64px;">${arc(64, pct, color, 6)}<div style="position:absolute; inset:0; display:flex; align-items:center; justify-content:center; font-size:20px; font-weight:600; color:${T.primary}; font-variant-numeric:tabular-nums;">${esc(value)}</div></div>
  <div style="font-size:13px; font-weight:600; color:${T.primary};">${esc(label)}</div>${sub ? `<div style="font-size:11px; color:${T.tertiary}; margin-top:-4px;">${esc(sub)}</div>` : ''}</div>`;

// ---------- chrome ----------
export const tabBar = (active, { accessory = 'connected' } = {}) => {
  const tabs = [['Today', icons.sun], ['Sleep', icons.moon], ['Measure', icons.wave], ['Breathe', icons.wind]];
  const acc = {
    connected: `<span style="width:8px; height:8px; border-radius:50%; background:${T.optimal}; flex:none;"></span><span style="font-weight:600; color:${T.primary};">LOOP-E5FF</span><span style="display:inline-flex; align-items:center; gap:4px; color:${T.secondary};">${icons.battery(16, T.optimal)}64%</span><span style="margin-left:auto; color:${T.tertiary}; overflow:hidden; text-overflow:ellipsis;">Synced 6 min ago</span>`,
    syncing: `<span style="width:8px; height:8px; border-radius:50%; background:${T.good}; flex:none;"></span><span style="font-weight:600; color:${T.primary};">LOOP-E5FF</span><span style="display:inline-flex; align-items:center; gap:4px; color:${T.secondary};">${icons.battery(16, T.optimal)}64%</span><span style="margin-left:auto; display:inline-flex; align-items:center; gap:6px; color:${T.good}; overflow:hidden;">${icons.sync(14, T.good)}Syncing…</span>`,
    low: `<span style="width:8px; height:8px; border-radius:50%; background:${T.optimal}; flex:none;"></span><span style="font-weight:600; color:${T.primary};">LOOP-E5FF</span><span style="display:inline-flex; align-items:center; gap:4px; color:${T.fair}; font-weight:600;">${icons.battery(16, T.fair)}24%</span><span style="margin-left:auto; color:${T.tertiary}; overflow:hidden; text-overflow:ellipsis;">Synced just now</span>`,
    charging: `<span style="width:8px; height:8px; border-radius:50%; background:${T.good}; flex:none;"></span><span style="font-weight:600; color:${T.primary};">LOOP-E5FF</span><span style="display:inline-flex; align-items:center; gap:4px; color:${T.good}; font-weight:600;">${icons.bolt(15, T.good)}71%</span><span style="margin-left:auto; color:${T.good}; overflow:hidden; text-overflow:ellipsis;">Charging</span>`,
    disconnected: `<span style="width:8px; height:8px; border-radius:50%; background:${T.abstained}; flex:none;"></span><span style="font-weight:600; color:${T.primary};">LOOP-E5FF</span><span style="color:${T.secondary};">Not connected</span><span style="margin-left:auto; color:${T.tertiary}; overflow:hidden; text-overflow:ellipsis;">Last sync 14:02</span>`,
    none: '',
  }[accessory];
  const accBar = acc ? `<div style="display:flex; align-items:center; gap:10px; height:44px; padding:0 14px; border-radius:16px; background:${T.elevated}E6; border:0.5px solid ${T.hairline}; font-size:13px; backdrop-filter:blur(20px); white-space:nowrap; overflow:hidden;">${acc}${icons.chevron(14, T.tertiary)}</div>` : '';
  return `<div style="position:absolute; left:16px; right:16px; bottom:22px; display:flex; flex-direction:column; gap:8px;">${accBar}
  <div style="display:flex; align-items:center; height:60px; padding:0 8px; border-radius:30px; background:${T.elevated}E6; border:0.5px solid ${T.hairline}; backdrop-filter:blur(24px); box-shadow:0 8px 30px rgba(0,0,0,0.45);">
    ${tabs.map(([l, ic]) => { const on = l === active; return `<div style="flex:1; display:flex; flex-direction:column; align-items:center; justify-content:center; gap:3px; height:48px; border-radius:24px; ${on ? `background:${T.card};` : ''}">${ic(22, on ? T.primary : T.tertiary)}<div style="font-size:10px; font-weight:600; color:${on ? T.primary : T.tertiary};">${l}</div></div>`; }).join('')}
  </div></div>`;
};

export const largeTitle = (title, sub = '', right = '') => `<div style="display:flex; justify-content:space-between; align-items:flex-end; padding:0 4px;"><div><div style="font-size:30px; font-weight:700; letter-spacing:-0.6px; color:${T.primary}; line-height:36px; white-space:nowrap;">${esc(title)}</div>${sub ? `<div style="font-size:15px; color:${T.secondary}; margin-top:2px;">${esc(sub)}</div>` : ''}</div>${right}</div>`;

export const avatar = () => `<div style="width:40px; height:40px; border-radius:50%; background:${T.card}; border:0.5px solid ${T.hairline}; display:flex; align-items:center; justify-content:center; font-size:15px; font-weight:600; color:${T.secondary};">AK</div>`;

// phone shell. h = frame height (tall frames show the whole scroll)
export const phone = ({ title, active, accessory = 'connected', h = 844, body, noChrome = false, bg = T.base }) => `<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <script src="./support.js"></script>
</head>
<body>
<x-dc>
<helmet>
  <style>
    body { margin: 0; background: ${bg}; font-family: ${FONT}; -webkit-font-smoothing: antialiased; color: ${T.primary}; }
    a { color: ${T.ink}; } a:hover { color: ${T.coral}; }
  </style>
</helmet>
<div style="position:relative; width:390px; height:${h}px; background:${bg}; overflow:hidden; border-radius:0;">
  <div style="position:absolute; inset:0; padding:64px 16px ${noChrome ? 40 : 150}px; display:flex; flex-direction:column; gap:20px; box-sizing:border-box;">
    ${body}
  </div>
  ${noChrome ? '' : tabBar(active, { accessory })}
</div>
</x-dc>
</body>
</html>`;

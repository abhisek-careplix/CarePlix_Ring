import { writeFileSync } from 'node:fs';
import { T, icons, arc, sparkline, lineChart, bars, hypnogram, chip, card, eyebrow, sectionHeader, provenance, wellnessTag, numeral, primaryButton, secondaryButton, brandButton, vitalTile, scoreShortcut, largeTitle, avatar, phone, esc } from './lib.mjs';

const out = {};

// ---------------- shared data ----------------
const rhrHist = [61, 60, 62, 59, 60, 58, 58], hrvHist = [44, 48, 41, 50, 52, 47, 55], spo2Hist = [97, 96, 97, 97, 96, 97, 97], brHist = [14.2, 14.5, 13.9, 14.8, 14.1, 14.3, 14.0], tempHist = [0.1, -0.1, 0.0, 0.2, 0.1, -0.2, 0.0], durHist = [6.9, 7.4, 6.2, 7.8, 7.1, 7.0, 7.7];

const vitalsGrid = (opts = {}) => `<div style="display:grid; grid-template-columns:repeat(2, minmax(0, 1fr)); gap:12px;">
  ${vitalTile({ title: 'Resting heart rate', value: '58', unit: 'bpm', state: 'typical', stateText: 'Typical', hist: rhrHist, band: [57, 63], prov: 'Lowest stable 5 min · 04:10' })}
  ${vitalTile({ title: 'HRV', value: '55', unit: 'ms', state: 'typical', stateText: 'Typical', hist: hrvHist, band: [40, 54], prov: 'Overnight average' })}
  ${vitalTile({ title: 'Blood oxygen', value: '97', unit: '%', state: 'typical', stateText: 'Typical', hist: spo2Hist, band: [95, 98], prov: 'Overnight, every 10 min' })}
  ${vitalTile({ title: 'Breathing rate', value: '14.0', unit: 'brpm', state: 'typical', stateText: 'Typical', hist: brHist, band: [13.5, 15], prov: 'Overnight average' })}
  ${vitalTile({ title: 'Skin temp change', value: '+0.0', unit: '°C', state: 'typical', stateText: 'Typical', hist: tempHist, band: [-0.3, 0.3], prov: 'vs your 14-night usual' })}
  ${vitalTile({ title: 'Sleep duration', value: '7:42', unit: 'h', state: 'typical', stateText: 'Typical', hist: durHist, band: [6.5, 7.8], prov: 'Goal 7:30' })}
</div>`;

// ---------------- Today · morning (Main) ----------------
{
  const hero = card(`
    <div style="display:flex; justify-content:space-between; align-items:center;">${eyebrow('Readiness · this morning')}${chip('optimal', 'Optimal')}</div>
    <div style="display:flex; align-items:center; gap:20px;">
      <div style="position:relative; width:150px; height:150px; flex:none;">${arc(150, 0.86, T.optimal, 14)}<div style="position:absolute; inset:0; display:flex; flex-direction:column; align-items:center; justify-content:center;"><div style="font-size:56px; font-weight:500; letter-spacing:-2px; color:${T.primary}; line-height:1; font-variant-numeric:tabular-nums;">86</div></div></div>
      <div style="display:flex; flex-direction:column; gap:8px;">
        <div style="font-size:20px; font-weight:600; color:${T.primary}; line-height:26px; letter-spacing:-0.2px;">Recovered. Take on the day.</div>
        <div style="font-size:14px; color:${T.secondary}; line-height:19px;">HRV above your usual, resting heart rate steady, a full night of sleep.</div>
      </div>
    </div>
    <div style="display:flex; gap:8px; flex-wrap:wrap;">
      ${['HRV ↑', 'Resting HR =', 'Sleep ✓', 'Temp ='].map((t, i) => `<span style="font-size:12px; font-weight:600; padding:5px 10px; border-radius:999px; background:${T.recessed}; color:${i === 0 ? T.optimal : T.secondary};">${t}</span>`).join('')}
    </div>
    ${provenance('From last night · 14 nights of your usual · Information only')}`);

  const scores = card(`<div style="display:flex; gap:8px;">${scoreShortcut('Readiness', '86', T.optimal, 0.86)}${scoreShortcut('Sleep', '82', T.good, 0.82)}${scoreShortcut('Activity', '41', T.fair, 0.41, '3,812 steps')}</div>`, 'padding:16px 8px;');

  const activity = card(`
    <div style="display:flex; justify-content:space-between; align-items:center;"><div style="font-size:15px; font-weight:600;">Movement</div><div style="font-size:13px; color:${T.tertiary};">Counted by your ring</div></div>
    <div style="display:flex; align-items:baseline; gap:10px;">${numeral('3,812', 'of 8,000 steps', 30, 13)}</div>
    <div style="height:6px; border-radius:3px; background:${T.recessed}; overflow:hidden;"><div style="width:48%; height:100%; background:${T.fair}; border-radius:3px;"></div></div>
    ${bars([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 120, 340, 90, 210, 480, 620, 150, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], { h: 44, color: T.good })}
    <div style="display:flex; gap:16px; font-size:13px; color:${T.secondary};"><span><b style="color:${T.primary}">2.7</b> km</span><span><b style="color:${T.primary}">148</b> active kcal</span><span style="margin-left:auto; color:${T.tertiary};">00 · 06 · 12 · 18 · 24</span></div>`);

  const timeline = card(`
    ${[['06:54', 'Woke up · night synced', icons.moon, T.secondary], ['06:58', 'Readiness 86 · vitals typical', icons.sun, T.optimal], ['08:20', 'Heart rate test · 72 bpm', icons.heart, T.coral], ['09:05', 'Ring synced', icons.sync, T.tertiary]].map(([t, l, ic, c], i, a) => `<div style="display:flex; gap:12px; align-items:center; ${i < a.length - 1 ? `padding-bottom:12px; border-bottom:0.5px solid ${T.hairline};` : ''}"><div style="width:44px; font-size:13px; color:${T.tertiary}; font-variant-numeric:tabular-nums;">${t}</div>${ic(18, c)}<div style="font-size:15px; color:${T.primary};">${l}</div></div>`).join('')}`, 'gap:12px;');

  out['Main.dc.html'] = phone({
    title: 'Today', active: 'Today', h: 1320, body: `
    ${largeTitle('Morning, Aisha', 'Friday 5 September', avatar())}
    ${hero}
    ${scores}
    ${sectionHeader('Overnight vitals', 'vs your usual')}
    ${vitalsGrid()}
    ${sectionHeader('Activity', 'Today')}
    ${activity}
    ${sectionHeader('Your day')}
    ${timeline}` });
}

// ---------------- Today · evening (Tonight hero, low battery) ----------------
{
  const hero = card(`
    <div style="display:flex; justify-content:space-between; align-items:center;">${eyebrow('Tonight')}<span style="font-size:13px; color:${T.tertiary};">Bedtime 23:00</span></div>
    <div style="display:flex; align-items:center; gap:18px;">
      <div style="position:relative; width:120px; height:120px; flex:none;">${arc(120, 0.24, T.fair, 12)}<div style="position:absolute; inset:0; display:flex; flex-direction:column; align-items:center; justify-content:center; gap:2px;">${icons.battery(20, T.fair)}<div style="font-size:30px; font-weight:600; letter-spacing:-1px; color:${T.primary}; line-height:1;">24%</div></div></div>
      <div style="display:flex; flex-direction:column; gap:8px;">
        <div style="font-size:20px; font-weight:600; line-height:26px; letter-spacing:-0.2px;">Charge your ring before bed.</div>
        <div style="font-size:14px; color:${T.secondary}; line-height:19px;">About 40 minutes on the charger covers tonight. It's 20:35 now.</div>
      </div>
    </div>
    <div style="display:flex; gap:10px;">${primaryButton('Remind me 22:15', 'flex:1; font-size:15px;')}${secondaryButton('Wind down', 'flex:1; font-size:15px;')}</div>`);

  const stress = card(`
    <div style="display:flex; justify-content:space-between; align-items:center;"><div style="font-size:15px; font-weight:600;">Stress today</div>${chip('typical', 'Typical')}</div>
    ${lineChart([22, 20, 18, 18, 21, 30, 44, 52, 48, 61, 58, 40, 35, 31, 42, 47, 36, 28, 25, null, null, null, null, null], { h: 96, color: T.primary, band: [18, 50], xLabels: ['06', '09', '12', '15', '18', '21', '00'] })}
    ${provenance('From heartbeat timing during the day · calm ↔ tense')}`);

  const scores = card(`<div style="display:flex; gap:8px;">${scoreShortcut('Readiness', '86', T.optimal, 0.86)}${scoreShortcut('Sleep', '82', T.good, 0.82)}${scoreShortcut('Activity', '78', T.good, 0.78, '7,240 steps')}</div>`, 'padding:16px 8px;');

  out['TodayEvening.dc.html'] = phone({ title: 'Today · evening', active: 'Today', accessory: 'low', h: 844, body: `
    ${largeTitle('Evening, Aisha', 'Friday 5 September', avatar())}
    ${hero}
    ${scores}
    ${stress}` });
}

// ---------------- Today · learning (night 3 of 7) ----------------
{
  const hero = card(`
    ${eyebrow('Learning your usual')}
    <div style="display:flex; align-items:center; gap:20px;">
      <div style="position:relative; width:150px; height:150px; flex:none;">${arc(150, 3 / 7, T.abstained, 14)}<div style="position:absolute; inset:0; display:flex; flex-direction:column; align-items:center; justify-content:center;"><div style="font-size:34px; font-weight:600; letter-spacing:-1px; line-height:1;">3<span style="font-size:18px; color:${T.tertiary}; font-weight:500;"> of 7</span></div><div style="font-size:12px; color:${T.tertiary}; margin-top:6px;">nights</div></div></div>
      <div style="display:flex; flex-direction:column; gap:8px;">
        <div style="font-size:19px; font-weight:600; line-height:25px; letter-spacing:-0.2px;">Three nights in. Four to go.</div>
        <div style="font-size:14px; color:${T.secondary}; line-height:19px;">Readiness appears once we know what your usual night looks like. Your vitals already show below.</div>
      </div>
    </div>`);
  const sleepCard = card(`
    <div style="display:flex; justify-content:space-between; align-items:center;"><div style="font-size:15px; font-weight:600;">Last night</div>${chip('learning', 'Ring’s estimate')}</div>
    <div style="display:flex; align-items:baseline; gap:10px;">${numeral('7:12', 'h asleep', 30, 13)}<span style="font-size:13px; color:${T.tertiary};">23:40 → 06:52</span></div>
    ${hypnogram(['awake', 'light', 'light', 'deep', 'deep', 'light', 'rem', 'light', 'deep', 'light', 'rem', 'rem', 'light', 'awake', 'light', 'deep', 'light', 'rem', 'light', 'awake'], { h: 118, labels: ['23:40', '01', '03', '05', '06:52'] })}`);
  const grid = `<div style="display:grid; grid-template-columns:repeat(2, minmax(0, 1fr)); gap:12px;">
    ${vitalTile({ title: 'Resting heart rate', value: '60', unit: 'bpm', state: 'learning', stateText: 'Learning · 3 of 7', hist: [61, 60, 60], prov: 'Range appears after 7 nights' })}
    ${vitalTile({ title: 'HRV', value: '46', unit: 'ms', state: 'learning', stateText: 'Learning · 3 of 7', hist: [44, 48, 46] })}
    ${vitalTile({ title: 'Blood oxygen', value: '97', unit: '%', state: 'learning', stateText: 'Learning · 3 of 7', hist: [97, 96, 97] })}
    ${vitalTile({ title: 'Skin temp change', value: '—', unit: '', state: 'notmeasured', stateText: 'Not measured', hist: [0, 0, 0], prov: 'Turn on in Ring → Overnight' })}
  </div>`;
  out['TodayLearning.dc.html'] = phone({ title: 'Today · learning', active: 'Today', accessory: 'syncing', h: 1080, body: `
    ${largeTitle('Morning, Aisha', 'Monday 1 September', avatar())}
    ${hero}
    ${sleepCard}
    ${sectionHeader('Overnight vitals', 'learning your usual')}
    ${grid}` });
}

// ---------------- Sleep ----------------
{
  const nightStrip = `<div style="display:flex; align-items:flex-end; gap:6px; height:56px; padding:0 4px;">${[6.9, 7.4, 6.2, 7.8, 7.1, 7.0, 5.4, 7.3, 6.8, 7.6, 7.2, 6.5, 7.0, 7.7].map((v, i) => `<div style="flex:1; display:flex; flex-direction:column; align-items:center; gap:4px;"><div style="width:100%; height:${Math.round((v / 8) * 40)}px; border-radius:3px; background:${i === 13 ? T.good : i === 6 ? T.fair : T.strong};"></div><div style="font-size:9px; color:${i === 13 ? T.primary : T.tertiary}; font-weight:${i === 13 ? 600 : 400};">${['M', 'T', 'W', 'T', 'F', 'S', 'S', 'M', 'T', 'W', 'T', 'F', 'S', 'S'][i]}</div></div>`).join('')}</div>`;

  const hero = card(`
    <div style="display:flex; justify-content:space-between; align-items:center;">${eyebrow('Last night · Thu → Fri')}${chip('good', 'Good')}</div>
    <div style="display:flex; align-items:center; gap:20px;">
      <div style="position:relative; width:120px; height:120px; flex:none;">${arc(120, 0.82, T.good, 12)}<div style="position:absolute; inset:0; display:flex; align-items:center; justify-content:center; font-size:44px; font-weight:500; letter-spacing:-1.5px; font-variant-numeric:tabular-nums;">82</div></div>
      <div style="display:flex; flex-direction:column; gap:6px;">
        ${numeral('7:42', 'h', 34, 15)}
        <div style="font-size:14px; color:${T.secondary};">23:12 → 06:54</div>
        <div style="font-size:14px; color:${T.secondary}; line-height:19px;">More deep sleep than usual. One long awakening at 03:20.</div>
      </div>
    </div>`);

  const stages = ['awake', 'awake', 'light', 'light', 'deep', 'deep', 'deep', 'light', 'rem', 'rem', 'light', 'deep', 'deep', 'light', 'light', 'awake', 'awake', 'light', 'rem', 'rem', 'rem', 'light', 'deep', 'light', 'rem', 'rem', 'light', 'awake'];
  const hyp = card(`<div style="font-size:15px; font-weight:600;">Stages</div>${hypnogram(stages, { h: 132 })}
    <div style="display:flex; gap:8px;">${[['Deep', '1:48', '23%', T.deep, 'usual 19%'], ['Light', '3:40', '48%', T.light, 'usual 50%'], ['REM', '1:36', '21%', T.rem, 'usual 22%'], ['Awake', '0:38', '8%', T.awake, 'usual 9%']].map(([n, d, p, c, u]) => `<div style="flex:1; display:flex; flex-direction:column; gap:4px; padding:10px; border-radius:12px; background:${T.recessed};"><div style="display:flex; align-items:center; gap:6px; font-size:12px; color:${T.secondary};"><span style="width:8px; height:8px; border-radius:2px; background:${c};"></span>${n}</div><div style="font-size:17px; font-weight:600; font-variant-numeric:tabular-nums;">${d}</div><div style="font-size:11px; color:${T.tertiary};">${p} · ${u}</div></div>`).join('')}</div>`);

  const contributors = card(`<div style="font-size:15px; font-weight:600;">What shaped the score</div>
    ${[['Duration', '7:42 of 7:30 goal', 'optimal', 'Optimal'], ['Efficiency', '92% of time in bed asleep', 'good', 'Good'], ['Awakenings', '2 · one of 18 min', 'fair', 'Fair'], ['Time to fall asleep', '11 min', 'good', 'Good'], ['Regularity', 'Bedtime within 25 min all week', 'optimal', 'Optimal']].map(([n, r, k, t], i, a) => `<div style="display:flex; align-items:center; gap:10px; ${i < a.length - 1 ? `padding-bottom:10px; border-bottom:0.5px solid ${T.hairline};` : ''}"><div style="flex:1;"><div style="font-size:15px;">${n}</div><div style="font-size:13px; color:${T.tertiary};">${r}</div></div>${chip(k, t)}</div>`).join('')}`, 'gap:10px;');

  const ov = (title, val, unit, vals, band, color, note, opts = {}) => `<div style="display:flex; flex-direction:column; gap:8px; padding:12px 0; border-bottom:0.5px solid ${T.hairline};"><div style="display:flex; justify-content:space-between; align-items:baseline;"><div style="font-size:15px;">${title}</div><div style="display:flex; align-items:baseline; gap:4px;"><span style="font-size:20px; font-weight:600; font-variant-numeric:tabular-nums;">${val}</span><span style="font-size:12px; color:${T.secondary};">${unit}</span></div></div>${lineChart(vals, { h: 64, color, band, xLabels: [], ...opts })}<div style="font-size:12px; color:${T.tertiary};">${note}</div></div>`;
  const overnight = card(`<div style="font-size:15px; font-weight:600;">Overnight vitals</div>
    ${ov('Heart rate', '58', 'bpm lowest', [66, 64, 62, 60, 59, 58, 58, 59, 61, 60, 58, 59, 62, 64, 63, 61, 60, 62, 65, 68], [57, 63], T.coral, 'Lowest at 04:10 · usual 57–63')}
    ${ov('HRV', '55', 'ms', [40, 44, 52, 58, 61, 55, 49, 57, 60, 62, 58, 54, 50, 56, 59, 52, 48, 51, 46, 42], [40, 54], T.good, 'Above your usual 40–54')}
    ${ov('Blood oxygen', '97', '%', [97, 97, 96, 97, 97, 96, 95, 97, 97, 97, 96, 97, 97, 97, 96, 97, 97, 97, 97, 97], [95, 98], T.optimal, 'Lowest 95% · no dips below 90%', { yMin: 88, yMax: 100 })}
    ${ov('Breathing rate', '14.0', 'brpm', [14.6, 14.2, 14.0, 13.8, 13.9, 14.0, 14.1, 13.7, 13.9, 14.2, 14.0, 13.8, 14.1, 14.3, 14.0, 13.9, 14.2, 14.4, 14.6, 14.8], [13.5, 15], T.light, 'Steady · usual 13.5–15')}
    <div style="display:flex; justify-content:space-between; align-items:center; padding-top:12px;"><div style="font-size:15px;">Skin temperature</div><div style="display:flex; align-items:center; gap:10px;"><span style="font-size:20px; font-weight:600;">+0.0 °C</span>${chip('typical', 'Typical')}</div></div>`, 'gap:0;');

  const debt = card(`<div style="display:flex; justify-content:space-between; align-items:center;"><div style="font-size:15px; font-weight:600;">Sleep debt · this week</div>${chip('good', 'Low')}</div>
    <div style="display:flex; align-items:baseline; gap:8px;">${numeral('1:10', 'h short', 30, 13)}<span style="font-size:13px; color:${T.tertiary};">need 7:30 × 7 · slept 51:20</span></div>
    ${bars([6.9, 7.4, 6.2, 7.8, 7.1, 5.4, 7.7].map((v) => v), { h: 40, color: T.good, max: 9 })}
    ${provenance('Short nights add up; long nights pay back. Two more nights near your goal clears it.')}`);

  out['Sleep.dc.html'] = phone({ title: 'Sleep', active: 'Sleep', h: 1560, body: `
    ${largeTitle('Sleep', '14 nights')}
    ${nightStrip}
    ${hero}
    ${hyp}
    ${contributors}
    ${overnight}
    ${debt}
    ${wellnessTag()}` });
}

// ---------------- Sleep · not worn ----------------
{
  const notWorn = card(`
    <div style="display:flex; flex-direction:column; align-items:center; gap:14px; padding:12px 0;">
      <div style="position:relative; width:140px; height:140px;">${arc(140, 0, T.abstained, 12)}<div style="position:absolute; inset:0; display:flex; align-items:center; justify-content:center;">${icons.hand(56, T.tertiary)}</div></div>
      <div style="font-size:20px; font-weight:600; text-align:center; letter-spacing:-0.2px;">Your ring wasn’t on your finger.</div>
      <div style="font-size:14px; color:${T.secondary}; text-align:center; line-height:19px;">No wear signal between 23:10 and 06:40. The ring was on the charger. Tonight it only needs to be on your finger.</div>
      ${primaryButton('Set a bedtime reminder', 'align-self:stretch;')}
    </div>`);
  const partial = card(`<div style="display:flex; justify-content:space-between; align-items:center;"><div style="font-size:15px; font-weight:600;">Two nights ago</div>${chip('fair', 'Ran out 02:14')}</div>
    ${hypnogram(['awake', 'light', 'light', 'deep', 'deep', 'light', 'rem', 'light', 'deep', 'gap', 'gap', 'gap', 'gap', 'gap', 'gap', 'gap', 'gap', 'gap', 'gap', 'gap'], { h: 118, lossAt: 9, labels: ['23:05', '01', '03', '05', '07'] })}
    ${provenance('Battery reached 0% at 02:14. The night after this one is complete.')}`);
  out['SleepNotWorn.dc.html'] = phone({ title: 'Sleep · not worn', active: 'Sleep', accessory: 'charging', h: 844, body: `
    ${largeTitle('Sleep', 'Last night')}
    ${notWorn}
    ${partial}` });
}

// ---------------- Measure ----------------
{
  const hr = card(`
    <div style="display:flex; justify-content:space-between; align-items:center;"><div style="font-size:15px; font-weight:600;">Heart rate today</div><div style="font-size:13px; color:${T.tertiary};">every 5 min</div></div>
    <div style="display:flex; align-items:baseline; gap:10px;">${numeral('74', 'bpm now', 34, 14)}<span style="font-size:13px; color:${T.tertiary};">resting 58 · range 55–118</span></div>
    ${lineChart([60, 58, 58, 59, 61, 60, 58, 59, 63, 68, 74, 92, 88, 76, 72, 70, 78, 118, 104, 84, 76, 72, 74, null, null, null, null, null, null, null, null, null], { h: 136, color: T.coral, band: [57, 63], dots: [{ i: 10, v: 72 }], xLabels: ['00', '04', '08', '12', '16', '20', '24'] })}
    ${provenance('Band shows your resting range · dot is a spot measurement · gaps are gaps')}`);
  const tile = (ic, title, last, enabled = true, reason = '') => `<div style="display:flex; flex-direction:column; gap:10px; padding:14px; border-radius:20px; background:${T.card}; border:0.5px solid ${T.hairline}; opacity:${enabled ? 1 : 0.55};"><div style="display:flex; justify-content:space-between; align-items:center;">${ic(22, enabled ? T.ink : T.tertiary)}${enabled ? icons.play(16, T.tertiary) : ''}</div><div style="font-size:15px; font-weight:600;">${title}</div><div style="font-size:12px; color:${T.tertiary};">${enabled ? last : reason}</div></div>`;
  const grid = `<div style="display:grid; grid-template-columns:repeat(2, minmax(0, 1fr)); gap:12px;">
    ${tile(icons.heart, 'Heart rate', 'Last 72 bpm · 08:20 · 30 s')}
    ${tile(icons.drop, 'Blood oxygen', 'Last 97% · yesterday · 30 s')}
    ${tile(icons.pulse, 'HRV', 'Last 51 ms · Tue · 60 s')}
    ${tile(icons.brain, 'Stress', 'Last 31 · Tue · 60 s')}
    ${tile(icons.thermo, 'Skin temperature', 'Last +0.1 °C · Mon')}
    ${tile(icons.wind, 'Breathing rate', 'In Breathe →')}
  </div>`;
  const recent = card(`${[['Heart rate', '72 bpm', 'Today 08:20', 'typical', 'Typical'], ['Blood oxygen', '97%', 'Yesterday 21:40', 'typical', 'Typical'], ['HRV', '51 ms', 'Tue 07:05', 'typical', 'Typical'], ['Stress', '31', 'Tue 15:12', 'typical', 'Calm']].map(([n, v, t, k, l], i, a) => `<div style="display:flex; align-items:center; gap:12px; ${i < a.length - 1 ? `padding-bottom:12px; border-bottom:0.5px solid ${T.hairline};` : ''}"><div style="flex:1;"><div style="font-size:15px;">${n}</div><div style="font-size:12px; color:${T.tertiary};">${t}</div></div><div style="font-size:17px; font-weight:600; font-variant-numeric:tabular-nums;">${v}</div>${chip(k, l)}</div>`).join('')}`, 'gap:12px;');
  out['Measure.dc.html'] = phone({ title: 'Measure', active: 'Measure', h: 1180, body: `
    ${largeTitle('Measure', 'How you are right now')}
    ${hr}
    ${sectionHeader('Measure now', 'ring on finger')}
    ${grid}
    ${sectionHeader('Recent')}
    ${recent}` });
}

// ---------------- Measure session (sheet) ----------------
{
  const sheet = `<div style="position:absolute; left:0; right:0; bottom:0; top:120px; background:${T.elevated}; border-radius:28px 28px 0 0; padding:12px 24px 40px; display:flex; flex-direction:column; gap:24px; box-sizing:border-box; border-top:0.5px solid ${T.hairline};">
    <div style="width:36px; height:5px; border-radius:3px; background:${T.strong}; align-self:center;"></div>
    <div style="display:flex; justify-content:space-between; align-items:center;"><div style="font-size:22px; font-weight:600; letter-spacing:-0.3px;">Heart rate</div><div style="font-size:15px; color:${T.ink}; font-weight:600;">Cancel</div></div>
    <div style="font-size:15px; color:${T.secondary}; line-height:21px;">Hold still and keep your hand relaxed. About 30 seconds.</div>
    <div style="display:flex; flex-direction:column; align-items:center; gap:18px; padding:20px 0;">
      <div style="position:relative; width:220px; height:220px;">${arc(220, 0.62, T.coral, 14, T.recessed)}
        <div style="position:absolute; inset:0; display:flex; flex-direction:column; align-items:center; justify-content:center; gap:4px;">${icons.heart(26, T.coral)}<div style="font-size:72px; font-weight:500; letter-spacing:-3px; line-height:1; font-variant-numeric:tabular-nums;">73</div><div style="font-size:15px; color:${T.secondary};">bpm · live</div></div></div>
      <div style="font-size:13px; color:${T.tertiary};">19 s left · signal good</div>
    </div>
    <div style="display:flex; gap:8px; align-items:center; padding:12px 14px; border-radius:14px; background:${T.card}; border:0.5px solid ${T.hairline}; font-size:13px; color:${T.secondary};">${icons.info(16, T.tertiary)}If the ring isn’t on your finger the test stops and says so. It never invents a number.</div>
    <div style="margin-top:auto; display:flex; flex-direction:column; gap:10px;">${secondaryButton('Stop')}</div>
  </div>`;
  out['MeasureSession.dc.html'] = phone({ title: 'Measure session', active: 'Measure', noChrome: true, h: 844, bg: T.base, body: `
    <div style="opacity:0.35;">${largeTitle('Measure', 'How you are right now')}</div>
    ${sheet}` });
}

// ---------------- Breathe ----------------
{
  const hero = card(`
    <div style="display:flex; justify-content:space-between; align-items:center;">${eyebrow('Breathing rate · last night')}${chip('typical', 'Typical')}</div>
    <div style="display:flex; align-items:center; gap:20px;">
      <div style="position:relative; width:120px; height:120px; flex:none;">${arc(120, 0.7, T.light, 12)}<div style="position:absolute; inset:0; display:flex; flex-direction:column; align-items:center; justify-content:center;"><div style="font-size:40px; font-weight:500; letter-spacing:-1.5px; line-height:1; font-variant-numeric:tabular-nums;">14.0</div><div style="font-size:12px; color:${T.secondary}; margin-top:4px;">breaths / min</div></div></div>
      <div style="display:flex; flex-direction:column; gap:8px;">
        <div style="font-size:17px; font-weight:600; line-height:23px;">Steady, within your usual.</div>
        ${sparkline(brHist.concat([14.3, 14.1, 13.9, 14.4, 14.2, 14.0, 14.0]), T.light, 150, 32, [13.5, 15])}
        <div style="font-size:12px; color:${T.tertiary};">14 nights · usual 13.5–15</div>
      </div>
    </div>`);
  const now = card(`<div style="display:flex; align-items:center; gap:14px;"><div style="width:44px; height:44px; border-radius:14px; background:${T.recessed}; display:flex; align-items:center; justify-content:center;">${icons.wind(22, T.ink)}</div><div style="flex:1;"><div style="font-size:15px; font-weight:600;">Breathing rate now</div><div style="font-size:12px; color:${T.tertiary};">60 s · ring on finger · last 15.2 on Tue</div></div>${icons.play(18, T.tertiary)}</div>`, 'padding:14px;');
  const guide = card(`
    <div style="display:flex; justify-content:space-between; align-items:center;"><div style="font-size:15px; font-weight:600;">Guided breathing</div><div style="display:flex; gap:6px;">${['1 min', '3 min', '5 min'].map((t, i) => `<span style="font-size:12px; font-weight:600; padding:5px 10px; border-radius:999px; background:${i === 1 ? T.primary : T.recessed}; color:${i === 1 ? T.base : T.secondary};">${t}</span>`).join('')}</div></div>
    <div style="display:flex; flex-direction:column; align-items:center; gap:14px; padding:12px 0 4px;">
      <div style="position:relative; width:180px; height:180px; display:flex; align-items:center; justify-content:center;">
        <div style="position:absolute; width:180px; height:180px; border-radius:50%; background:${T.light}14;"></div>
        <div style="position:absolute; width:132px; height:132px; border-radius:50%; background:${T.light}22;"></div>
        <div style="position:absolute; width:88px; height:88px; border-radius:50%; background:${T.light}55;"></div>
        <div style="position:relative; font-size:17px; font-weight:600;">Breathe in</div>
      </div>
      <div style="font-size:13px; color:${T.tertiary};">4 s in · 4 s hold · 6 s out · haptics on</div>
      ${brandButton('Start · 3 min', 'align-self:stretch;')}
    </div>
    ${provenance('Last session: heart rate settled from 78 to 66 bpm in 3 minutes.')}`);
  const oxygen = card(`
    <div style="display:flex; justify-content:space-between; align-items:center;"><div style="font-size:15px; font-weight:600;">Oxygen through the night</div>${chip('typical', 'Typical')}</div>
    ${lineChart([97, 97, 96, 97, 97, 96, 95, 97, 97, 97, 96, 97, 97, 97, 96, 97, 97, 97, 97, 97, 96, 97, 97, 97], { h: 96, color: T.optimal, band: [95, 98], yMin: 88, yMax: 100, xLabels: ['23:12', '01', '03', '05', '06:54'] })}
    <div style="display:flex; gap:16px; font-size:13px; color:${T.secondary};"><span>Average <b style="color:${T.primary}">97%</b></span><span>Lowest <b style="color:${T.primary}">95%</b></span><span>Dips below 90% <b style="color:${T.primary}">0</b></span></div>
    ${provenance('Breathing disturbances are a wellness estimate from oxygen dips, not a diagnosis.')}`);
  out['Breathe.dc.html'] = phone({ title: 'Breathe', active: 'Breathe', h: 1220, body: `
    ${largeTitle('Breathe', 'Your breathing, overnight and now')}
    ${hero}
    ${now}
    ${guide}
    ${oxygen}
    ${wellnessTag()}` });
}

// ---------------- Ring sheet ----------------
{
  const header = `<div style="display:flex; align-items:center; gap:16px;">
    <div style="width:72px; height:72px; border-radius:50%; background:radial-gradient(circle at 35% 30%, #3A404A, #14171D 70%); border:0.5px solid ${T.strong}; display:flex; align-items:center; justify-content:center;"><div style="width:40px; height:40px; border-radius:50%; background:${T.base}; box-shadow:inset 0 1px 2px rgba(255,255,255,0.08);"></div></div>
    <div style="flex:1;"><div style="font-size:22px; font-weight:600; letter-spacing:-0.3px;">LOOP-E5FF</div><div style="display:flex; align-items:center; gap:6px; font-size:13px; color:${T.secondary};"><span style="width:8px; height:8px; border-radius:50%; background:${T.optimal};"></span>Connected · firmware 2.4.1</div></div>
    ${icons.gear(22, T.tertiary)}</div>`;
  const battery = card(`
    <div style="display:flex; align-items:center; gap:20px;">
      <div style="position:relative; width:110px; height:110px; flex:none;">${arc(110, 0.64, T.optimal, 12)}<div style="position:absolute; inset:0; display:flex; flex-direction:column; align-items:center; justify-content:center; gap:2px;">${icons.battery(18, T.optimal)}<div style="font-size:30px; font-weight:600; letter-spacing:-1px; line-height:1;">64%</div></div></div>
      <div style="display:flex; flex-direction:column; gap:6px;">
        <div style="font-size:17px; font-weight:600;">About 3 nights left</div>
        <div style="font-size:13px; color:${T.secondary}; line-height:18px;">Using about 18% a day with overnight oxygen on. We’ll remind you 2 h before bed when it drops under 30%.</div>
      </div>
    </div>
    ${lineChart([100, 92, 84, 76, 68, 60, 52, 44, 36, 100, 95, 88, 80, 72, 64], { h: 64, color: T.optimal, xLabels: ['7 days ago', 'today'] })}
    ${provenance('Charged Wed 21:10 → 100% · full charge takes about 60 min')}`);
  const sync = card(`<div style="display:flex; align-items:center; gap:12px;"><div style="flex:1;"><div style="font-size:15px; font-weight:600;">Synced 6 min ago</div><div style="font-size:13px; color:${T.tertiary};">Your ring keeps 7 days of data when it’s away from your phone.</div></div>${secondaryButton('Sync now', 'height:40px; padding:0 14px; font-size:15px;')}</div>`);
  const row = (n, sub, on, cost) => `<div style="display:flex; align-items:center; gap:12px; padding:12px 0; border-bottom:0.5px solid ${T.hairline};"><div style="flex:1;"><div style="font-size:15px;">${n}</div><div style="font-size:12px; color:${T.tertiary};">${sub}</div></div><div style="font-size:11px; color:${T.tertiary};">${cost}</div><div style="width:44px; height:26px; border-radius:13px; background:${on ? T.optimal : T.strong}; position:relative;"><div style="position:absolute; top:2px; ${on ? 'right:2px' : 'left:2px'}; width:22px; height:22px; border-radius:50%; background:#FFFFFF;"></div></div></div>`;
  const monitoring = card(`<div style="font-size:15px; font-weight:600;">What your ring measures overnight</div>
    ${row('Heart rate', 'Every 5 min, all day', true, '')}
    ${row('HRV', '00:00 → 08:00', true, '')}
    ${row('Blood oxygen', 'Every 10 min while asleep', true, '−6% / night')}
    ${row('Skin temperature', 'Every 5 min while asleep', true, '−1% / night')}
    ${row('Stress', 'Every 30 min, daytime', false, '−3% / day')}
    ${provenance('Turning a sensor off removes its card from Today and Sleep. Nothing is estimated in its place.')}`, 'gap:0;');
  const wear = card(`<div style="display:flex; align-items:center; gap:12px;">${icons.hand(24, T.secondary)}<div style="flex:1;"><div style="font-size:15px;">Left hand · index finger</div><div style="font-size:12px; color:${T.tertiary};">Sensors face your palm side</div></div><div style="font-size:15px; color:${T.ink}; font-weight:600;">Edit</div></div>`, 'padding:14px;');
  const notif = card(`<div style="font-size:15px; font-weight:600;">Notifications</div>
    ${[['Night ready', 'On first sync after you wake', true], ['Charge before bed', '2 h before bedtime, under 30%', true], ['Ring charged', 'At 80% on the charger', true], ['Not worn at bedtime', '1 h after bedtime', false], ['Vitals outside typical', 'Only when two or more are', true]].map(([n, s, on]) => row(n, s, on, '')).join('')}`, 'gap:0;');
  const danger = card(`${[['Restart ring', T.primary], ['Pair a different ring', T.primary], ['Forget this ring', T.poor]].map(([t, c], i, a) => `<div style="display:flex; justify-content:space-between; align-items:center; padding:12px 0; ${i < a.length - 1 ? `border-bottom:0.5px solid ${T.hairline};` : ''} font-size:15px; color:${c};">${t}${icons.chevron(16, T.tertiary)}</div>`).join('')}`, 'gap:0; padding:4px 16px;');
  out['Ring.dc.html'] = phone({ title: 'Ring', active: 'Today', noChrome: true, h: 1400, bg: T.elevated, body: `
    <div style="display:flex; justify-content:space-between; align-items:center;"><div style="font-size:15px; color:${T.ink}; font-weight:600;">Done</div><div style="font-size:15px; font-weight:600;">Your ring</div><div style="width:40px;"></div></div>
    ${header}
    ${battery}
    ${sync}
    ${monitoring}
    ${sectionHeader('Wear')}
    ${wear}
    ${notif}
    ${danger}` });
}

// ---------------- Pairing ----------------
{
  const body = `
    <div style="display:flex; justify-content:space-between; align-items:center;">${icons.back(22, T.ink)}<div style="font-size:13px; color:${T.tertiary};">Step 3 of 4</div></div>
    <div style="display:flex; flex-direction:column; gap:8px; padding:0 4px;">${eyebrow('Your ring')}<div style="font-size:30px; font-weight:700; letter-spacing:-0.5px; line-height:36px;">We found your ring.</div><div style="font-size:15px; color:${T.secondary}; line-height:21px;">Keep it off the charger and close to your phone while we connect.</div></div>
    <div style="display:flex; flex-direction:column; align-items:center; gap:10px; padding:8px 0;">
      <div style="position:relative; width:180px; height:180px; display:flex; align-items:center; justify-content:center;">
        <div style="position:absolute; width:180px; height:180px; border-radius:50%; border:0.5px solid ${T.hairline};"></div>
        <div style="position:absolute; width:130px; height:130px; border-radius:50%; border:0.5px solid ${T.strong};"></div>
        <div style="width:84px; height:84px; border-radius:50%; background:radial-gradient(circle at 35% 30%, #3A404A, #14171D 70%); border:0.5px solid ${T.strong}; display:flex; align-items:center; justify-content:center;"><div style="width:46px; height:46px; border-radius:50%; background:${T.base};"></div></div>
      </div>
    </div>
    ${card(`${[['LOOP-E5FF', 'Strong signal · 30 cm', true], ['LOOP-2A91', 'Weak signal', false]].map(([n, s, on], i, a) => `<div style="display:flex; align-items:center; gap:12px; ${i < a.length - 1 ? `padding-bottom:12px; border-bottom:0.5px solid ${T.hairline};` : ''}"><div style="width:40px; height:40px; border-radius:50%; background:${T.recessed}; display:flex; align-items:center; justify-content:center;">${icons.ring(22, on ? T.ink : T.tertiary)}</div><div style="flex:1;"><div style="font-size:17px; font-weight:600;">${n}</div><div style="font-size:13px; color:${T.tertiary};">${s}</div></div>${on ? `<div style="display:flex; align-items:center; gap:6px; font-size:13px; font-weight:600; color:${T.good};">${icons.sync(14, T.good)}Connecting…</div>` : ''}</div>`).join('')}`, 'gap:12px;')}
    <div style="display:flex; align-items:flex-start; gap:10px; padding:12px 14px; border-radius:14px; background:${T.card}; border:0.5px solid ${T.hairline}; font-size:13px; color:${T.secondary}; line-height:18px;">${icons.info(16, T.tertiary)}<div>Searching stops after 15 seconds and tells you if nothing turned up. You can always search again.</div></div>
    <div style="margin-top:auto; display:flex; flex-direction:column; gap:10px;">${secondaryButton('Search again')}<div style="text-align:center; font-size:13px; color:${T.tertiary};">Not the right ring? Tap the other one.</div></div>`;
  out['Pairing.dc.html'] = phone({ title: 'Pairing', active: 'Today', noChrome: true, h: 844, body });
}

// ---------------- Profile · wear question ----------------
{
  const opt = (t, on) => `<div style="display:flex; align-items:center; justify-content:center; height:52px; border-radius:16px; border:${on ? `2px solid ${T.primary}` : `0.5px solid ${T.strong}`}; background:${on ? T.card : 'transparent'}; font-size:17px; font-weight:600; color:${on ? T.primary : T.secondary}; flex:1;">${t}</div>`;
  const body = `
    <div style="display:flex; justify-content:space-between; align-items:center;">${icons.back(22, T.ink)}<div style="display:flex; gap:4px;">${[1, 1, 1, 1, 1, 0, 0].map((f) => `<span style="width:${f ? 18 : 8}px; height:4px; border-radius:2px; background:${f ? T.primary : T.strong};"></span>`).join('')}</div></div>
    <div style="display:flex; flex-direction:column; gap:8px; padding:0 4px;">${eyebrow('About you · 5 of 7')}<div style="font-size:30px; font-weight:700; letter-spacing:-0.5px; line-height:36px;">Which finger will wear it?</div><div style="font-size:15px; color:${T.secondary}; line-height:21px;">Index or middle finger gives the steadiest signal. We use this to tell when the ring is off your hand, and to guide the fit.</div></div>
    <div style="display:flex; flex-direction:column; gap:10px;"><div style="display:flex; gap:10px;">${opt('Left hand', true)}${opt('Right hand', false)}</div><div style="display:flex; gap:10px;">${opt('Index', true)}${opt('Middle', false)}${opt('Ring', false)}</div></div>
    <div style="display:flex; align-items:center; gap:16px; padding:16px; border-radius:20px; background:${T.card}; border:0.5px solid ${T.hairline};">${icons.hand(48, T.secondary)}<div style="font-size:13px; color:${T.secondary}; line-height:18px;">Sensor bumps on the inside of the band go on the palm side. Snug enough not to spin, loose enough to slide over the knuckle.</div></div>
    ${card(`<div style="font-size:13px; font-weight:600; color:${T.secondary};">Already answered</div>${[['Born', 'March 1989'], ['Ranges based on', 'Female'], ['Height', '168 cm'], ['Weight', '61 kg']].map(([k, v]) => `<div style="display:flex; justify-content:space-between; font-size:15px;"><span style="color:${T.tertiary};">${k}</span><span>${v}</span></div>`).join('')}`, 'gap:8px;')}
    <div style="margin-top:auto;">${primaryButton('Continue')}</div>`;
  out['Profile.dc.html'] = phone({ title: 'Profile', active: 'Today', noChrome: true, h: 844, body });
}

// ---------------- Direction sketches (low-fi) ----------------
const lofi = (title, note, blocks) => `<!doctype html>
<html><head><meta charset="utf-8"><script src="./support.js"></script></head><body>
<x-dc>
<helmet><style> body { margin:0; background:#F6F3EC; font-family: 'Segoe Print', 'Bradley Hand', 'Comic Neue', cursive, sans-serif; color:#2B2A26; } a { color:#2B2A26; } a:hover { color:#000; } </style></helmet>
<div style="position:relative; width:390px; height:844px; background:#F6F3EC; overflow:hidden; padding:56px 20px 24px; box-sizing:border-box; display:flex; flex-direction:column; gap:14px;">
  <div style="font-size:22px; font-weight:700;">${esc(title)}</div>
  <div style="font-size:13px; color:#6B675E; line-height:17px;">${esc(note)}</div>
  ${blocks}
</div>
</x-dc></body></html>`;
const box = (h, label, extra = '') => `<div style="height:${h}px; border:2px dashed #8E877A; border-radius:14px; display:flex; align-items:center; justify-content:center; font-size:14px; color:#4A463F; text-align:center; padding:8px; ${extra}">${esc(label)}</div>`;
out['DirectionB.dc.html'] = lofi('Direction B · Vitals first', 'Apple-Vitals stance: no composite score, six overnight vitals as the hero list, one status word. Honest and calm; weaker daily motivation.', `
  ${box(64, 'Overnight: TYPICAL (blue) — one word, no number')}
  ${box(280, 'List of 6 vitals · each a row: name · value · range bar · 7-night dots')}
  ${box(90, 'Sleep 7:42 (bar vs goal)')}
  ${box(90, 'Ring: 64% · synced')}
  ${box(56, 'Tab bar: Today · Sleep · Measure · Breathe')}`);
out['DirectionC.dc.html'] = lofi('Direction C · Editorial narrative', 'One paragraph written from the data, then the evidence. Warmest voice; hardest to keep honest when data is missing.', `
  ${box(150, '"You slept 7 h 42 m, deeper than usual, and your heart settled to 58. Your body is ready." — set in large serif')}
  ${box(96, 'Three inline numbers underlined in the text link to details')}
  ${box(200, 'Evidence cards (same as chosen direction) below the fold')}
  ${box(90, 'Tonight card appears in the evening')}
  ${box(56, 'Tab bar')}`);

import { existsSync, readFileSync } from 'node:fs';
const measured = existsSync('heights.json') ? JSON.parse(readFileSync('heights.json', 'utf8')) : {};
const heights = {};
for (const [name, html] of Object.entries(out)) {
  const m = html.match(/width:390px; height:(\d+)px/);
  const h = Math.max(844, measured[name] ?? Number(m[1]));
  heights[name] = h;
  writeFileSync(name, html.replace(/width:390px; height:\d+px/, `width:390px; height:${h}px`));
}
const titles = { 'Pairing.dc.html': 'Pairing · found', 'Profile.dc.html': 'About you · wear finger', 'Main.dc.html': 'Today · morning', 'TodayEvening.dc.html': 'Today · evening, low battery', 'TodayLearning.dc.html': 'Today · learning (night 3)', 'Ring.dc.html': 'Ring sheet · battery & sync', 'Sleep.dc.html': 'Sleep · last night', 'SleepNotWorn.dc.html': 'Sleep · not worn / ran out', 'Measure.dc.html': 'Measure', 'MeasureSession.dc.html': 'Measure · heart rate test', 'Breathe.dc.html': 'Breathe', 'DirectionB.dc.html': 'Direction B · Vitals first', 'DirectionC.dc.html': 'Direction C · Editorial' };
const rows = [
  ['screens', ['Pairing.dc.html', 'Profile.dc.html', 'Main.dc.html', 'TodayEvening.dc.html', 'TodayLearning.dc.html', 'Ring.dc.html']],
  ['screens', ['Sleep.dc.html', 'SleepNotWorn.dc.html', 'Measure.dc.html', 'MeasureSession.dc.html', 'Breathe.dc.html']],
  ['directions', ['DirectionB.dc.html', 'DirectionC.dc.html']],
];
const artboards = []; let y = 0; const rowY = {};
for (const [page, files] of rows) {
  if (page === 'directions') y = 0;
  rowY[files[0]] = y;
  files.forEach((f, i) => artboards.push({ file: f, title: titles[f], x: i * 480, y, w: 390, h: heights[f], page }));
  y += Math.max(...files.map((f) => heights[f])) + 200;
}
const canvas = {
  pages: [{ id: 'screens', name: 'Screens' }, { id: 'directions', name: 'Direction sketches' }],
  artboards,
  annotations: [
    { id: 'brief', x: 0, y: -210, w: 420, page: 'screens', text: 'CarePlix Ring · redesign\nFour tabs: Today · Sleep · Measure · Breathe. The search bar is gone. The ring lives in a status shelf above the tab bar on every screen: connection · battery · last sync. Tall frames show the full scroll; the floating chrome is drawn once at the bottom of each frame.' },
    { id: 'hero-note', x: 960, y: -170, w: 380, page: 'screens', text: "Today's hero is time-aware: Readiness in the morning, Stress or Activity in the afternoon, Tonight (bedtime + battery) in the evening, and an honest Learning state for the first 7 nights." },
    { id: 'vitals-note', x: 1440, y: -110, w: 360, page: 'screens', text: "Every vital is shown against the wearer's own 14-night range and gets exactly one of: Typical · Outside typical · Learning · Not measured." },
    { id: 'sleep-note', x: 0, y: rowY['Sleep.dc.html'] - 150, w: 420, page: 'screens', text: "Sleep: hypnogram from the ring's per-minute stage line, gaps drawn as gaps, a red marker where the battery died. Not-worn and partial nights are first-class states, never blank." },
    { id: 'measure-note', x: 960, y: rowY['Sleep.dc.html'] - 150, w: 420, page: 'screens', text: 'Measure = how am I right now. Spot tests are gated by the ring\'s capability flags; every test has explicit exits: not on finger, ring busy, battery too low, timed out.' },
    { id: 'dir-note', x: 0, y: -170, w: 520, page: 'directions', text: "Two alternates to the chosen 'One big thing' direction on the Screens page. B is Apple-Vitals honesty with no composite score; C is an editorial narrative. Both kept low-fi so the structural difference is the only thing to compare." },
  ],
  launch: { view: 'canvas', page: 'screens' },
};
writeFileSync('canvas.json', JSON.stringify(canvas, null, 2) + '\n');
console.log(Object.entries(heights).map(([k, v]) => `${k}:${v}`).join(' '));

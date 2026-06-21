// ==UserScript==
// @name         melodia.ro → TopPresenter Song JSON
// @namespace    toppresenter.melodia
// @version      1.0.0
// @description  Export a melodia.ro song (versuri + acorduri + capo charts + metadata) to TopPresenter "TopPresenter Song" GOAT JSON. Mirrors melodia-scraper.mjs, but reads the React-rendered capo diagrams (guitar/ukulele) the Node scraper can't see.
// @match        https://melodia.ro/cantari/*
// @run-at       document-idle
// @grant        none
// ==/UserScript==
//
// One song per page → one JSON file. Click the floating "⬇ TopPresenter" button
// (or press Alt+T). Chords are stored ONCE in the song's own key as {sym,pos};
// every other key is derivable by transposition. The capo section is read from
// the live DOM, so the exact fret diagrams melodia draws for guitar AND ukulele
// are captured (shape name, sounding chord, frets, fingers, barre, recommended capo).
//
(function () {
  'use strict';

  const BASE = 'https://melodia.ro';

  // ── HTML helpers (run on the live, hydrated document) ─────────────────────────
  const html = () => document.documentElement.outerHTML;
  const NAMED = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ', hellip: '…',
    ndash: '–', mdash: '—', rsquo: '’', lsquo: '‘', rdquo: '”', ldquo: '“', laquo: '«', raquo: '»', copy: '©' };
  function decodeEntities(s) {
    if (!s || s.indexOf('&') < 0) return s || '';
    return s.replace(/&#(\d+);/g, (_, n) => String.fromCodePoint(+n))
      .replace(/&#x([0-9a-f]+);/gi, (_, n) => String.fromCodePoint(parseInt(n, 16)))
      .replace(/&([a-z]+);/gi, (m, n) => (n in NAMED ? NAMED[n] : m));
  }
  const stripTags = s => decodeEntities(String(s || '').replace(/<[^>]+>/g, ' ')).replace(/\s+/g, ' ').trim();
  function attr(h, name) { const m = h.match(new RegExp(name + '=(["\'])(.*?)\\1')); return m ? decodeEntities(m[2]) : ''; }
  function ldJsonBlocks(h) {
    const out = []; const re = /<script[^>]*type="application\/ld\+json"[^>]*>([\s\S]*?)<\/script>/gi;
    let m; while ((m = re.exec(h))) { try { out.push(JSON.parse(m[1])); } catch {} } return out;
  }
  function jsonScript(h, id) {
    const m = h.match(new RegExp('<script[^>]*id="' + id + '"[^>]*>([\\s\\S]*?)<\\/script>', 'i'));
    if (!m) return null; try { return JSON.parse(m[1]); } catch { return null; }
  }
  function faqAnswer(faq, q) {
    for (const it of (faq?.mainEntity || [])) if ((it.name || '').toLowerCase().includes(q)) return it.acceptedAnswer?.text || '';
    return '';
  }

  // ── Music theory (capo recommendation fallback) ───────────────────────────────
  const SEMI = { C: 0, 'C#': 1, Db: 1, D: 2, 'D#': 3, Eb: 3, E: 4, F: 5, 'F#': 6, Gb: 6, G: 7, 'G#': 8, Ab: 8, A: 9, 'A#': 10, Bb: 10, B: 11 };
  const GUITAR_PREF = ['G', 'D', 'C', 'A', 'E'], UKULELE_PREF = ['C', 'G', 'F', 'D', 'A'];
  function recommendCapo(key, pref, maxCapo = 8) {
    const minor = /m$/.test(key); const r = SEMI[key.replace(/m$/, '')]; if (r == null) return null;
    for (const pr of pref) { const sr = SEMI[pr]; const capo = (((r - sr) % 12) + 12) % 12;
      if (capo >= 1 && capo <= maxCapo) return { capo, shapeKey: pr + (minor ? 'm' : '') }; }
    return null;
  }

  // ── Sections + arrangement (dedupe identical re-rendered sections) ─────────────
  const SECTION_TYPES = ['verse', 'chorus', 'prechorus', 'pre-chorus', 'bridge', 'intro', 'outro', 'ending', 'tag', 'interlude'];
  const TYPE_PREFIX = { verse: 'v', chorus: 'c', prechorus: 'p', bridge: 'b', intro: 'i', outro: 'e', ending: 'e', tag: 't', interlude: 'in' };
  function typeFromClass(cls) { const c = (cls || '').toLowerCase(); for (const t of SECTION_TYPES) if (c.includes(t)) return t === 'pre-chorus' ? 'prechorus' : t; return 'verse'; }
  function labelFor(type, key) {
    const n = key.replace(/^[a-z]+/i, '');
    const base = { verse: 'Strofa', chorus: 'Refren', prechorus: 'Pre-refren', bridge: 'Punte', intro: 'Intro', ending: 'Final', tag: 'Tag', interlude: 'Interludiu' }[type] || 'Strofa';
    return n ? `${base} ${n}` : base;
  }
  const normText = lines => lines.map(l => l.text.trim()).join('\n').toLowerCase().replace(/\s+/g, ' ');
  function parseSectionLines(inner) {
    const lines = [];
    for (const raw of inner.split(/<br\s*\/?>/i)) {
      let text = '', chords = [];
      const re = /<div class="chord">([\s\S]*?)<\/div>|([^<]+)|<[^>]+>/gi; let m;
      while ((m = re.exec(raw))) {
        if (m[1] != null) { const sym = decodeEntities(m[1]).trim(); if (sym) chords.push({ sym, pos: text.length }); }
        else if (m[2] != null) text += decodeEntities(m[2]);
      }
      text = text.replace(/\s+$/g, '');
      if (text.trim() === '' && !chords.length) continue;
      const line = { text }; if (chords.length) line.chords = chords; lines.push(line);
    }
    return lines;
  }
  function balancedDivInner(h, start) {
    const re = /<\/?div\b[^>]*>/gi; re.lastIndex = start; let depth = 1, m;
    while ((m = re.exec(h))) { if (m[0][1] === '/') { if (--depth === 0) return h.slice(start, m.index); } else depth++; }
    return h.slice(start);
  }
  function parseSectionsAndArrangement(h) {
    const openRe = /<div class="((?:verse|chorus|prechorus|pre-chorus|bridge|intro|outro|ending|tag|interlude)[^"]*)" data-section-key="[^"]+">/gi;
    const sections = [], arrangement = [], idx = {}, byContent = new Map(); let m;
    while ((m = openRe.exec(h))) {
      const type = typeFromClass(m[1]); const lines = parseSectionLines(balancedDivInner(h, m.index + m[0].length)); if (!lines.length) continue;
      const sig = type + '|' + normText(lines); let key = byContent.get(sig);
      if (!key) { const p = TYPE_PREFIX[type] || 'v'; const n = (idx[p] = (idx[p] || 0) + 1); key = p + n;
        byContent.set(sig, key); sections.push({ id: key, type, label: labelFor(type, key), order: sections.length, lines }); }
      arrangement.push(key);
    }
    return { sections, arrangement };
  }

  // ── Metadata parsers (same as the .mjs) ───────────────────────────────────────
  function parseKeywords(h) {
    const out = [], seen = new Set(); const re = /\/cantari\?t=([^"'&]+)/gi; let m;
    while ((m = re.exec(h))) { const t = decodeEntities(decodeURIComponent(m[1].replace(/\+/g, ' '))).trim(); const k = t.toLowerCase();
      if (t && !seen.has(k)) { seen.add(k); out.push(t); } }
    return out;
  }
  function parseAvailableKeys(h) {
    const sel = h.match(/key-transpose-selector[\s\S]*?<\/select>/i); if (!sel) return [];
    const out = []; const re = /<option value="([^"]+)"/gi; let m; while ((m = re.exec(sel[0]))) if (m[1]) out.push(m[1]);
    return [...new Set(out)];
  }
  function parseAnatomia(h) {
    const i = h.indexOf('Anatomia Evangheliei'); if (i < 0) return null;
    const chunk = h.slice(i, i + 4000); const out = {};
    const score = chunk.match(/Anatomia Evangheliei[\s\S]{0,400}?>\s*(\d+)\s*\/\s*(\d+)\s*</);
    if (score) { out.score = +score[1]; out.scoreMax = +score[2]; }
    const desc = chunk.match(/font-style:\s*italic;[^>]*>([\s\S]*?)<\/p>/i); if (desc) out.description = stripTags(desc[1]);
    const cats = []; const catRe = /min-width:\s*88px;?[^>]*>([^<]+)<\/span>[\s\S]{0,200}?width:\s*(\d+)%/gi; let m;
    while ((m = catRe.exec(chunk))) cats.push({ name: decodeEntities(m[1]).trim(), percent: +m[2] });
    if (cats.length) out.categories = cats;
    return Object.keys(out).length ? out : null;
  }

  // ── Capo charts: read the rendered React chord diagrams (the unique value) ─────
  // Returns shapes [{ sounds, shape, frets, fingers, barre }] for the current
  // instrument tab. cx → string, cy → fret (spaces centered at 7,21,35,…).
  function readChordDiagrams(container) {
    const svgs = container.querySelectorAll('svg.chord-graph');
    const shapes = [];
    for (const svg of svgs) {
      // String x-positions: the fingerboard string labels (E/A/D/G/B/E or G/C/E/A) sit at y≈85.
      const labels = [...svg.querySelectorAll('text')].filter(t => Math.abs(+t.getAttribute('y') - 85) < 2);
      const xs = labels.map(t => +t.getAttribute('x')).sort((a, b) => a - b);
      const stringX = [...new Set(xs)];
      if (!stringX.length) continue;
      const nearestString = x => stringX.reduce((best, sx, i) => Math.abs(sx - x) < Math.abs(stringX[best] - x) ? i : best, 0);
      const fretForY = cy => Math.max(1, Math.round((cy + 7) / 14));
      const slots = new Array(stringX.length).fill('x');     // default muted
      const fingers = new Array(stringX.length).fill('0');
      // Open (cy≈-8 hollow circle) / muted ("x" text at y≈-5).
      for (const c of svg.querySelectorAll('circle')) {
        const cy = +c.getAttribute('cy'); const cx = +c.getAttribute('cx');
        if (cy < 0 && (c.getAttribute('fill') === 'none')) slots[nearestString(cx)] = '0';      // open
      }
      for (const t of svg.querySelectorAll('text')) {
        if ((t.textContent || '').trim() === 'x' && +t.getAttribute('y') < 0) slots[nearestString(+t.getAttribute('x'))] = 'x';
      }
      // Fretted notes (filled dots) + finger numbers.
      for (const c of svg.querySelectorAll('circle')) {
        const cy = +c.getAttribute('cy'); if (cy <= 0) continue;
        const r = +c.getAttribute('r'); if (!(r > 3)) continue;        // skip the small open markers
        const si = nearestString(+c.getAttribute('cx')); slots[si] = String(fretForY(cy));
      }
      for (const t of svg.querySelectorAll('text')) {
        const cy = +t.getAttribute('y'); const txt = (t.textContent || '').trim();
        if (cy > 0 && cy < 75 && /^[1-4]$/.test(txt)) fingers[nearestString(+t.getAttribute('x'))] = txt;
      }
      const barre = !!svg.querySelector('rect');
      const shapeName = (svg.querySelector('text[font-weight="bold"]')?.textContent || '').trim();
      const sounds = (svg.parentElement?.querySelector('.line-through')?.textContent || '').trim();
      shapes.push({ sounds, shape: shapeName, frets: slots.join(''), fingers: fingers.join(''), barre });
    }
    return shapes;
  }
  async function captureInstruments(key) {
    const container = document.getElementById('react-chord-section');
    const out = {};
    if (!container) {
      // No rendered diagrams → fall back to the computed recommendation.
      const g = recommendCapo(key, GUITAR_PREF), u = recommendCapo(key, UKULELE_PREF);
      if (g) out.guitar = { tuning: 'EADGBE', recommendedCapo: g.capo, shapeKey: g.shapeKey, source: 'computed' };
      if (u) out.ukulele = { tuning: 'GCEA', recommendedCapo: u.capo, shapeKey: u.shapeKey, source: 'computed' };
      return out;
    }
    const tabs = [...container.querySelectorAll('button')].filter(b => /chitar|ukulele/i.test(b.textContent || ''));
    const read = (instr, tuning) => {
      const header = container.querySelector('.widget-title')?.textContent || '';
      const cap = header.match(/\(([A-G][#b]?m?)\s*\+\s*(\d+)\s*Capo/i);
      const o = { tuning, source: 'melodia' };
      if (cap) { o.shapeKey = cap[1]; o.recommendedCapo = +cap[2]; }
      o.shapes = readChordDiagrams(container);
      return o;
    };
    // Guitar (default tab) then Ukulele.
    const guitarTab = tabs.find(b => /chitar/i.test(b.textContent));
    const ukuleleTab = tabs.find(b => /ukulele/i.test(b.textContent));
    if (guitarTab) guitarTab.click();
    await sleep(250);
    out.guitar = read('guitar', 'EADGBE');
    if (ukuleleTab) { ukuleleTab.click(); await sleep(350); out.ukulele = read('ukulele', 'GCEA'); if (guitarTab) guitarTab.click(); }
    return out;
  }
  const sleep = ms => new Promise(r => setTimeout(r, ms));

  // ── Build the document ────────────────────────────────────────────────────────
  async function build() {
    const h = html();
    const slug = decodeURIComponent(location.pathname.split('/cantari/')[1] || '').replace(/\/$/, '');
    const lds = ldJsonBlocks(h);
    const comp = lds.find(b => b['@type'] === 'MusicComposition') || {};
    const faq = lds.find(b => b['@type'] === 'FAQPage');
    const mobile = jsonScript(h, 'mobile-song-data') || {};

    const title = (comp.name || attr(h, 'data-song-title') || (h.match(/<title>([^,<]+)/) || [])[1] || slug).trim();
    const key = (mobile.key || (faqAnswer(faq, 'tonalitate').match(/tonalitatea\s+([A-G][#b]?m?)/i) || [])[1] || '').trim();
    const bpm = attr(h, 'data-bpm'); const beats = attr(h, 'data-beats');
    const authorsText = faqAnswer(faq, 'cine a scris') || '';
    const authorMusic = (authorsText.match(/Muzica:\s*([^.]+)/i) || [])[1]?.trim() || (comp.composer?.name || '').trim();
    const authorWords = (authorsText.match(/Versuri:\s*([^.]+)/i) || [])[1]?.trim() || '';
    const composedYear = +((h.match(/year-written[^>]*>Compus[ăa]\s+în\s*<b>(\d{4})<\/b>/i) || [])[1] || (faqAnswer(faq, 'compusa').match(/(\d{4})/) || [])[1] || 0) || null;
    const meetings = +((h.match(/Cântat[ăa]\s+în\s*<b>(\d+)<\/b>/i) || [])[1] || 0) || null;
    const copyrightBlock = stripTags((h.match(/<span>(All rights reserved[\s\S]*?)<\/span>/i) || [])[1] || '');

    const { sections, arrangement } = parseSectionsAndArrangement(h);
    const themes = parseKeywords(h);
    const instruments = await captureInstruments(key);

    const melodia = { id: attr(h, 'data-song-id') || undefined, slug, url: `${BASE}/cantari/${slug}` };
    if (composedYear) melodia.composedYear = composedYear;
    if (meetings != null) melodia.meetingsCount = meetings;
    if (bpm) melodia.bpm = +bpm;
    const availableKeys = parseAvailableKeys(h); if (availableKeys.length) melodia.availableKeys = availableKeys;
    melodia.availableCapos = [0, 1, 2, 3, 4, 5, 6, 7, 8];
    if (Object.keys(instruments).length) melodia.instruments = instruments;
    const anatomia = parseAnatomia(h); if (anatomia) melodia.anatomiaEvangheliei = anatomia;
    if ((mobile.songMap || []).length) melodia.songMap = mobile.songMap.filter(Boolean);

    const version = { name: '', language: 'ro', key, capo: 0, tempo: bpm || '', timeSignature: beats ? `${beats}/4` : '',
      source: `${BASE}/cantari/${slug}`, arrangement, sections };
    const song = { title, language: 'ro', themes, authorWords, authorMusic,
      author: [authorMusic, authorWords].filter(Boolean).filter((v, i, a) => a.indexOf(v) === i).join(', '),
      copyright: copyrightBlock, versions: [version], _extensions: { melodia } };
    return { schemaVersion: '1.0.0', format: 'TopPresenter Song',
      exportInfo: { source: 'melodia.ro', exportDate: new Date().toISOString(), exporterVersion: '1.0.0' }, song };
  }

  function sanitize(name) { return name.replace(/[\/\\:?%*|"<>]+/g, '-').replace(/\s+/g, ' ').trim().slice(0, 120); }
  function download(doc) {
    const blob = new Blob([JSON.stringify(doc, null, 2)], { type: 'application/json' });
    const a = document.createElement('a'); a.href = URL.createObjectURL(blob);
    a.download = sanitize(doc.song.title || doc.song._extensions.melodia.slug) + '.json';
    document.body.appendChild(a); a.click(); a.remove(); setTimeout(() => URL.revokeObjectURL(a.href), 1000);
  }

  async function run(btn) {
    const old = btn.textContent; btn.textContent = '⏳ citesc acordurile…'; btn.disabled = true;
    try { download(await build()); btn.textContent = '✅ descărcat'; }
    catch (e) { console.error('[melodia→TP]', e); btn.textContent = '⚠️ eroare (vezi consola)'; }
    finally { setTimeout(() => { btn.textContent = old; btn.disabled = false; }, 1800); }
  }

  // ── UI ────────────────────────────────────────────────────────────────────────
  function addButton() {
    if (document.getElementById('tp-melodia-btn')) return;
    const b = document.createElement('button');
    b.id = 'tp-melodia-btn'; b.textContent = '⬇ TopPresenter';
    b.style.cssText = 'position:fixed;right:16px;bottom:16px;z-index:99999;padding:10px 14px;border:0;border-radius:10px;background:#2563eb;color:#fff;font:600 13px system-ui;cursor:pointer;box-shadow:0 4px 14px rgba(0,0,0,.25)';
    b.title = 'Exportă în TopPresenter Song JSON (Alt+T)';
    b.addEventListener('click', () => run(b));
    document.body.appendChild(b);
    window.addEventListener('keydown', e => { if (e.altKey && (e.key === 't' || e.key === 'T')) run(b); });
  }
  if (document.readyState === 'complete' || document.readyState === 'interactive') addButton();
  else window.addEventListener('DOMContentLoaded', addButton);
})();

// ==UserScript==
// @name         worshiptogether.com → TopPresenter Song JSON
// @namespace    toppresenter.worshiptogether
// @version      1.0.0
// @description  Export a worshiptogether.com song (chords + lyrics + key/BPM/CCLI/themes/scripture) to TopPresenter "TopPresenter Song" GOAT JSON. Reads the rendered ChordPro DOM in your logged-in session. Mirrors worshiptogether-scraper.mjs.
// @match        https://www.worshiptogether.com/songs/*
// @run-at       document-idle
// @grant        none
// ==/UserScript==
//
// For personal/congregational use — projecting these lyrics still needs your
// church's CCLI license. Click the ⬇ button (or Alt+T) to download one song's JSON.
//
(function () {
  'use strict';
  const BASE = 'https://www.worshiptogether.com';

  const SECTION_RE = /^(intro|verse|chorus|pre[\s-]?chorus|bridge|tag|interlude|instrumental|ending|outro|refrain|vamp|turnaround|mod\.?\s*chorus|channel|breakdown|coda)\b/i;
  const REPEAT_RE = /^\s*(repeat|x\d)/i;
  const CHORD_RE = /^[A-G][#b]?(?:m|maj|min|dim|aug|sus|add)?[0-9]*(?:\([^)]*\))?(?:sus[0-9]*)?(?:\/[A-G][#b]?)?$/;
  const TYPE_PREFIX = { verse: 'v', chorus: 'c', prechorus: 'p', bridge: 'b', intro: 'i', tag: 't', interlude: 'in', ending: 'e' };
  function sectionType(label) {
    const l = label.toLowerCase();
    if (/pre[\s-]?chorus/.test(l)) return 'prechorus';
    if (/chorus/.test(l)) return 'chorus';
    if (/verse/.test(l)) return 'verse';
    if (/bridge/.test(l)) return 'bridge';
    if (/intro/.test(l)) return 'intro';
    if (/tag/.test(l)) return 'tag';
    if (/instrumental|interlude|vamp|turnaround|channel/.test(l)) return 'interlude';
    if (/ending|outro|coda/.test(l)) return 'ending';
    return 'verse';
  }
  const txt = el => (el ? el.textContent : '').replace(/ /g, ' ');

  // ── Parse the rendered ChordPro DOM ──────────────────────────────────────────
  function parseChords() {
    const lines = [...document.querySelectorAll('.chord-pro-line')];
    const sections = [], arrangement = [], counts = {};
    let cur = null;
    const startSection = (type, label) => {
      const p = TYPE_PREFIX[type] || 's'; counts[p] = (counts[p] || 0) + 1;
      cur = { id: p + counts[p], type, label: label || type, order: sections.length, lines: [] };
      sections.push(cur); arrangement.push(cur.id);
    };
    for (const ln of lines) {
      const segs = [...ln.querySelectorAll('.chord-pro-segment')].map(s => ({
        note: txt(s.querySelector('.chord-pro-note')).trim(),
        lyric: txt(s.querySelector('.chord-pro-lyric')),
      })).filter(s => s.note || s.lyric);
      if (!segs.length) continue;
      if (segs.length === 1 && !segs[0].note) {
        const lab = segs[0].lyric.trim(); if (!lab) continue;
        if (REPEAT_RE.test(lab) || /repeat/i.test(lab)) {
          const want = sectionType(lab.replace(/repeat/i, '').trim() || 'chorus');
          const reuse = [...sections].reverse().find(s => s.type === want) || [...sections].reverse().find(s => s.type === 'chorus');
          if (reuse) arrangement.push(reuse.id); cur = null; continue;
        }
        if (SECTION_RE.test(lab)) { startSection(sectionType(lab), lab); continue; }
      }
      if (!cur) startSection('verse', 'Verse');
      let text = ''; const chords = [];
      for (const seg of segs) {
        if (seg.note) { if (CHORD_RE.test(seg.note)) chords.push({ sym: seg.note, pos: text.length }); else text += seg.note + (seg.lyric ? ' ' : ''); }
        text += seg.lyric;
      }
      text = text.replace(/\s+$/g, '');
      if (text.trim() === '' && !chords.length) continue;
      const line = { text }; if (chords.length) line.chords = chords;
      cur.lines.push(line);
    }
    return { sections, arrangement };
  }

  // ── Metadata from the page ───────────────────────────────────────────────────
  function fieldValue(label) {
    // find an element whose text starts with the label, return the rest
    const el = [...document.querySelectorAll('li,div,span,p,dt,dd,td')].find(e => {
      const t = (e.textContent || '').trim(); return t.startsWith(label) && t.length < 220;
    });
    if (!el) return '';
    return (el.textContent || '').replace(new RegExp('^\\s*' + label.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '\\s*:?\\s*', 'i'), '').replace(/\s+/g, ' ').trim();
  }
  function parseMeta() {
    const m = {};
    const container = document.querySelector('[data-original-key]');
    m.originalKey = container ? container.getAttribute('data-original-key') : (fieldValue('Original Key').match(/[A-G][#b]?m?/) || [''])[0];
    m.ccli = (fieldValue('CCLI').match(/\d{4,}/) || [''])[0];
    m.bpm = (fieldValue('BPM').match(/\d{2,3}/) || [''])[0];
    m.tempo = fieldValue('Tempo').split(/\s{2,}/)[0];
    m.scripture = fieldValue('Scripture Reference').split(/\s{2,}/)[0];
    // theme + recommended-key link lists
    const after = (label, pred) => {
      const lbl = [...document.querySelectorAll('*')].find(e => (e.textContent || '').trim().startsWith(label) && e.querySelectorAll('a').length);
      return lbl ? [...new Set([...lbl.querySelectorAll('a')].map(a => a.textContent.trim()))].filter(pred) : [];
    };
    m.themes = after('Theme', t => t && !/worship together|search|view all/i.test(t)).slice(0, 12);
    m.recommendedKeys = after('Recommended Key', t => /^[A-G][#b]?m?$/.test(t)).slice(0, 8);
    m.copyright = (fieldValue('Copyright') || (document.body.textContent.match(/(©|Copyright)\s*[^\n<]{4,160}/) || [''])[0]).slice(0, 200).trim();
    m.writers = fieldValue('Writer(s)') || fieldValue('Writers') || '';
    return m;
  }

  function build() {
    const slug = (location.pathname.match(/\/songs\/([a-z0-9-]+)/i) || [, ''])[1];
    const lang = (location.pathname.includes('/es/') ? 'es' : location.pathname.includes('/pt/') ? 'pt' : 'en');
    const rawTitle = document.title.replace(/\s*\|\s*Worship Together.*$/i, '').trim();
    const parts = rawTitle.split(/\s+[-–]\s+/);
    const title = (parts[0] || rawTitle).trim();
    const artists = (parts.slice(1).join(' - ') || '').trim();
    const { sections, arrangement } = parseChords();
    const m = parseMeta();
    const wt = { url: location.href.split('#')[0], slug, artists };
    if (m.ccli) wt.ccli = m.ccli;
    if (m.originalKey) wt.originalKey = m.originalKey;
    if (m.recommendedKeys.length) wt.recommendedKeys = m.recommendedKeys;
    if (m.bpm) wt.bpm = +m.bpm;
    if (m.tempo) wt.tempoLabel = m.tempo;
    if (m.scripture) wt.scripture = m.scripture;
    if (m.themes.length) wt.themes = m.themes;
    return {
      schemaVersion: '1.0.0', format: 'TopPresenter Song',
      exportInfo: { source: 'worshiptogether.com', exportDate: new Date().toISOString(), exporterVersion: '1.0.0' },
      song: {
        title: title || slug, language: lang,
        author: m.writers || artists, authorMusic: m.writers || '', copyright: m.copyright || '',
        ccliNumber: m.ccli || '', themes: m.themes,
        versions: [{ name: '', language: lang, key: m.originalKey || '', tempo: m.bpm || '', arrangement, sections }],
        _extensions: { worshipTogether: wt },
      },
    };
  }

  const sanitize = n => String(n || '').replace(/[\/\\:?%*|"<>]+/g, '-').replace(/\s+/g, ' ').trim().slice(0, 120);
  function download(doc) {
    const blob = new Blob([JSON.stringify(doc, null, 2)], { type: 'application/json' });
    const a = document.createElement('a'); a.href = URL.createObjectURL(blob);
    a.download = sanitize(doc.song.title || doc.song._extensions.worshipTogether.slug) + '.json';
    document.body.appendChild(a); a.click(); a.remove(); setTimeout(() => URL.revokeObjectURL(a.href), 1000);
  }
  function run(btn) {
    const old = btn.textContent; btn.disabled = true; btn.textContent = '⏳…';
    try { download(build()); btn.textContent = '✅ downloaded'; }
    catch (e) { console.error('[wt→TP]', e); btn.textContent = '⚠️ error (console)'; }
    finally { setTimeout(() => { btn.textContent = old; btn.disabled = false; }, 1800); }
  }
  function addButton() {
    if (document.getElementById('wt-tp-btn')) return;
    const b = document.createElement('button');
    b.id = 'wt-tp-btn'; b.textContent = '⬇ TopPresenter';
    b.style.cssText = 'position:fixed;right:16px;bottom:16px;z-index:99999;padding:10px 14px;border:0;border-radius:10px;background:#111827;color:#fff;font:600 13px system-ui;cursor:pointer;box-shadow:0 4px 14px rgba(0,0,0,.3)';
    b.title = 'Export this song to TopPresenter Song JSON (Alt+T)';
    b.addEventListener('click', () => run(b));
    document.body.appendChild(b);
    window.addEventListener('keydown', e => { if (e.altKey && /^t$/i.test(e.key)) run(b); });
  }
  if (document.readyState === 'loading') window.addEventListener('DOMContentLoaded', addButton); else addButton();
})();

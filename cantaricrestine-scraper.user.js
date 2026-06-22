// ==UserScript==
// @name         cantaricrestine.ro → TopPresenter Song JSON
// @namespace    toppresenter.cantaricrestine
// @version      1.0.0
// @description  Export cantaricrestine.ro songs (lyrics + PowerPoint link + metadata) to TopPresenter "TopPresenter Song" GOAT JSON, via the site's public API. Export a single song, a whole book, or the entire catalog as one importable bundle.
// @match        https://www.cantaricrestine.ro/*
// @match        https://cantaricrestine.ro/*
// @run-at       document-idle
// @grant        none
// ==/UserScript==
//
// Mirrors cantaricrestine-scraper.mjs. The Node scraper is the workhorse for the
// full catalog + PowerPoint files; this userscript is for quick, in-browser
// exports: pick a book (or "Toate") and download a TopPresenter Songs bundle that
// imports in one go. PowerPoints aren't downloaded here (use the .mjs) — their
// URLs are preserved in each song's `_extensions.cantaricrestine.pptUrl`.
//
(function () {
  'use strict';

  const API = location.origin + '/api.php';
  const randToken = () => String(Math.floor(1e9 + Math.random() * 9e9));

  const CATEGORIES = [
    ['', 'Toate (toată baza)'], ['d', 'Diverse'], ['cr', 'Cântările Evangheliei (Roșie)'],
    ['cn', 'Cântările Evangheliei (Neagră)'], ['ca', 'Cântările Evangheliei (Albastră)'],
    ['ic', 'Imnuri Creștine (AZSMR)'], ['ic2', 'Imnuri Creștine'], ['ib', 'Imnurile Bucuriei'],
    ['ih', 'Imnurile Harului'], ['pdc', 'Pe drumul credinței'], ['ld', 'Laudele Domnului'],
    ['lpd', 'Lăudați pe Domnul'], ['lpdag', 'Lăudați pe Domnul (Groza)'], ['cb', 'Cântecele Bucuriei'],
    ['cc', 'Carte de cântări'], ['co', 'Colinde'], ['c', 'Copii'], ['t', 'Tineret'],
    ['an', 'An nou'], ['nu', 'Nuntă'], ['ci', 'Cina'], ['p', 'Paști'],
  ];

  // ── Lyrics → TopPresenter sections (same logic as the .mjs) ────────────────────
  const CHORUS_RE = /^\s*(R\d*[:.)]|Ref(?:ren|\.)?[:.)]?|Cor[:.)])/i;
  function parseLyrics(descriere) {
    const text = String(descriere || '').replace(/\r\n/g, '\n').trim();
    if (!text) return { sections: [], arrangement: [] };
    const blocks = text.split(/\n\s*\n+/).map(b => b.replace(/\s+$/g, '')).filter(b => b.trim());
    const sections = [], arrangement = []; let v = 0, c = 0, b = 0;
    for (const block of blocks) {
      const rawLines = block.split('\n');
      const isChorus = CHORUS_RE.test(rawLines[0]);
      const numMatch = rawLines[0].match(/^\s*(\d+)\s*[.)]\s*/);
      const number = numMatch ? numMatch[1] : '';
      const lines = rawLines.map((ln, idx) => {
        let t = ln;
        if (idx === 0) t = t.replace(/^\s*\d+\s*[.)]\s*/, '').replace(CHORUS_RE, '').trimStart();
        return { text: t };
      }).filter((l, idx) => !(idx === 0 && l.text === '' && rawLines.length > 1) || rawLines.length === 1);
      let id, type, label;
      if (isChorus) { c++; id = 'c' + c; type = 'chorus'; label = 'Refren' + (c > 1 ? ' ' + c : ''); }
      else if (/punte|bridge/i.test(rawLines[0])) { b++; id = 'b' + b; type = 'bridge'; label = 'Punte' + (b > 1 ? ' ' + b : ''); }
      else { v++; id = 'v' + v; type = 'verse'; label = 'Strofa ' + (number || v); }
      sections.push({ id, type, label, order: sections.length, lines });
      arrangement.push(id);
    }
    return { sections, arrangement };
  }
  const sanitize = n => String(n || '').replace(/[\/\\:?%*|"<>]+/g, '-').replace(/\s+/g, ' ').trim().slice(0, 120);

  function buildSong(s) {
    const denumire = String(s.denumire || '').trim();
    const m = denumire.match(/^(\d+[a-z]?)\s+(.+)$/i);
    const songNumber = m ? m[1] : '';
    const title = m ? m[2].trim() : denumire;
    const descriere = String(s.descriere || '');
    const pptUrl = s.url_fisier || '';
    const ext = (pptUrl.match(/\.(pptx?|key|odp)$/i) || [, 'pptx'])[1].toLowerCase();
    const { sections, arrangement } = parseLyrics(descriere);
    return {
      title: title || denumire || `cantare-${s.id}`, language: 'ro', songNumber,
      songbook: { name: s.categoria || 'Diverse', number: songNumber },
      versions: [{ name: '', language: 'ro', arrangement, sections }],
      _extensions: { cantaricrestine: {
        id: String(s.id || ''), url: s.url || '', pptUrl,
        pptFile: pptUrl ? `${sanitize(denumire)}.${ext}` : '',
        dataAdaugare: s.data_adaugare || '', downloads: +(s.nr_descarcari || 0) || 0,
        views: +(s.nr_vizualizari || 0) || 0, categorySymbol: s.categoria_simbol || '',
        hasLyrics: descriere.trim().length > 0, hasPptx: !!pptUrl,
      } },
    };
  }

  async function fetchPage(categorie, pagina, limita) {
    const q = new URLSearchParams({ token: randToken(), limita: String(limita), pagina: String(pagina) });
    if (categorie) q.set('categorie', categorie);
    const res = await fetch(`${API}?${q}`, { headers: { Accept: 'application/json' } });
    if (!res.ok) throw new Error('API ' + res.status);
    return res.json();
  }
  async function fetchAll(categorie, onProgress) {
    const first = await fetchPage(categorie, 1, 500);
    const pages = first.paginatie?.total_pagini || 1;
    let songs = Object.values(first.rezultate || {});
    for (let p = 2; p <= pages; p++) {
      const d = await fetchPage(categorie, p, 500);
      songs = songs.concat(Object.values(d.rezultate || {}));
      onProgress?.(songs.length, first.paginatie?.total_rezultate || songs.length);
    }
    return songs;
  }

  function download(obj, filename) {
    const blob = new Blob([JSON.stringify(obj, null, 2)], { type: 'application/json' });
    const a = document.createElement('a'); a.href = URL.createObjectURL(blob);
    a.download = filename; document.body.appendChild(a); a.click(); a.remove();
    setTimeout(() => URL.revokeObjectURL(a.href), 1000);
  }

  async function exportBundle(categorie, label, btn) {
    const old = btn.textContent; btn.disabled = true;
    try {
      btn.textContent = '⏳ descarc lista…';
      const songs = await fetchAll(categorie, (n, t) => { btn.textContent = `⏳ ${n}/${t}…`; });
      const bundle = {
        schemaVersion: '1.0.0', format: 'TopPresenter Songs',
        collection: { name: label, sourceFormat: 'cantaricrestine' },
        exportInfo: { source: 'cantaricrestine.ro', exportDate: new Date().toISOString(), exporterVersion: '1.0.0', totalSongs: songs.length },
        songs: songs.map(buildSong),
      };
      download(bundle, `cantaricrestine - ${sanitize(label)}.json`);
      btn.textContent = `✅ ${songs.length} cântări`;
    } catch (e) { console.error('[cc→TP]', e); btn.textContent = '⚠️ eroare'; }
    finally { setTimeout(() => { btn.textContent = old; btn.disabled = false; }, 2200); }
  }

  // ── UI ────────────────────────────────────────────────────────────────────────
  function addPanel() {
    if (document.getElementById('cc-tp-panel')) return;
    const wrap = document.createElement('div');
    wrap.id = 'cc-tp-panel';
    wrap.style.cssText = 'position:fixed;right:16px;bottom:16px;z-index:99999;background:#0f172a;color:#e2e8f0;padding:12px;border-radius:12px;box-shadow:0 8px 28px rgba(0,0,0,.35);font:13px system-ui;width:300px';
    const sel = document.createElement('select');
    sel.style.cssText = 'width:100%;padding:6px;margin:6px 0;border-radius:8px;border:1px solid #334155;background:#1e293b;color:#e2e8f0';
    for (const [code, name] of CATEGORIES) { const o = document.createElement('option'); o.value = code; o.textContent = name; sel.appendChild(o); }
    const btn = document.createElement('button');
    btn.textContent = '⬇ Exportă TopPresenter JSON';
    btn.style.cssText = 'width:100%;padding:9px;border:0;border-radius:9px;background:#2563eb;color:#fff;font-weight:600;cursor:pointer';
    btn.addEventListener('click', () => exportBundle(sel.value, sel.options[sel.selectedIndex].textContent, btn));
    const title = document.createElement('div');
    title.textContent = 'cantaricrestine → TopPresenter';
    title.style.cssText = 'font-weight:700;margin-bottom:2px';
    const hint = document.createElement('div');
    hint.textContent = 'Alege o carte (sau Toate) → un fișier bundle, gata de importat. (PowerPoint-urile: vezi scriptul .mjs)';
    hint.style.cssText = 'font-size:11px;color:#94a3b8;margin-top:6px;line-height:1.4';
    wrap.append(title, sel, btn, hint);
    document.body.appendChild(wrap);
  }
  if (document.readyState === 'loading') window.addEventListener('DOMContentLoaded', addPanel); else addPanel();
})();

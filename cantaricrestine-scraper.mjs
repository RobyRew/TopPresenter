#!/usr/bin/env node
//
// cantaricrestine-scraper.mjs
// ──────────────────────────────────────────────────────────────────────────────
// Scrapes cantaricrestine.ro ("Cântări Creștine în PowerPoint") into TopPresenter
// "TopPresenter Song" GOAT JSON — one file per song — and downloads each song's
// PowerPoint (.ppt/.pptx), organized into per-book folders.
//
// It uses the site's public JSON API (api.php) — no HTML scraping. `token` is just
// a random anti-bot value (no real auth); `limita=500` is honored. The whole
// catalog (~9.5k songs) paginates in ~20 calls. Each result carries the lyrics
// (`descriere`), the PowerPoint URL (`url_fisier`), date added, and category.
//
// Lyrics: `descriere` is numbered stanzas separated by blank lines, with `//: ://`
// repeat markers → parsed into TopPresenter sections (no chords; these are
// PowerPoint lyric songs). Songs with empty `descriere` are PowerPoint-only and
// flagged in the completeness report.
//
// Resilient to a full disk: PowerPoint writes that fail (ENOSPC, …) are flagged
// and the crawl keeps going — the small JSON is always written first.
//
// Usage:
//   node cantaricrestine-scraper.mjs                       # all songs + PowerPoints
//   node cantaricrestine-scraper.mjs --no-ppt              # JSON only (tiny)
//   node cantaricrestine-scraper.mjs --limit 20 --no-ppt   # smoke test
//   node cantaricrestine-scraper.mjs --print --id 8445     # print one song's JSON
//
// Options:
//   --out DIR          output folder      (default ./ExtraAssets/Songs/cantaricrestine.ro)
//   --no-ppt           skip PowerPoint downloads (JSON only)
//   --limit N          stop after N new songs (testing)
//   --limita N         API page size      (default 500)
//   --delay MS         pause between downloads (default 150)
//   --concurrency N    parallel PowerPoint downloads (default 4)
//   --retries N        retries per request (default 3)
//   --no-resume        re-write even if the file exists
//   --print            print one song's JSON (use with --id), no writes
//   --id ID            song id for --print
// ──────────────────────────────────────────────────────────────────────────────

import { writeFile, mkdir, readdir } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import path from 'node:path';

const BASE = 'https://www.cantaricrestine.ro';
const API = `${BASE}/api.php`;
const UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) TopPresenter-CantaricrestineScraper/1.0';
const sleep = ms => new Promise(r => setTimeout(r, ms));
const randToken = () => String(Math.floor(1e9 + Math.random() * 9e9));

// ── CLI ─────────────────────────────────────────────────────────────────────
function parseArgs(argv) {
  const o = {
    out: './ExtraAssets/Songs/cantaricrestine.ro', noPpt: false, limit: Infinity,
    limita: 500, delay: 150, concurrency: 4, retries: 3, resume: true, print: false, id: null,
  };
  for (let i = 2; i < argv.length; i++) {
    const a = argv[i], next = () => argv[++i];
    if (a === '--out') o.out = next();
    else if (a === '--no-ppt') o.noPpt = true;
    else if (a === '--limit') o.limit = +next();
    else if (a === '--limita') o.limita = Math.max(1, +next());
    else if (a === '--delay') o.delay = +next();
    else if (a === '--concurrency') o.concurrency = Math.max(1, +next());
    else if (a === '--retries') o.retries = +next();
    else if (a === '--no-resume') o.resume = false;
    else if (a === '--print') o.print = true;
    else if (a === '--id') o.id = next();
    else if (a === '-h' || a === '--help') { console.log('see header of this file'); process.exit(0); }
  }
  return o;
}

// ── Network ───────────────────────────────────────────────────────────────────
async function fetchJSON(url, retries) {
  for (let i = 0; i < retries; i++) {
    try {
      const res = await fetch(url, { headers: { 'User-Agent': UA, 'Accept': 'application/json' } });
      if (res.ok) return await res.json();
      res.body?.cancel?.();
    } catch { /* retry */ }
    await sleep(500 * (i + 1));
  }
  return null;
}
async function fetchBuffer(url, retries) {
  for (let i = 0; i < retries; i++) {
    try {
      const res = await fetch(encodeURI(url), { headers: { 'User-Agent': UA } });
      if (res.ok) return Buffer.from(await res.arrayBuffer());
      res.body?.cancel?.();
      if (res.status === 404) return null;
    } catch { /* retry */ }
    await sleep(500 * (i + 1));
  }
  return null;
}

// ── Lyrics → TopPresenter sections ──────────────────────────────────────────────
const CHORUS_RE = /^\s*(R\d*[:.)]|Ref(?:ren|\.)?[:.)]?|Cor[:.)])/i;
function parseLyrics(descriere) {
  const text = String(descriere || '').replace(/\r\n/g, '\n').trim();
  if (!text) return { sections: [], arrangement: [] };
  const blocks = text.split(/\n\s*\n+/).map(b => b.replace(/\s+$/g, '')).filter(b => b.trim());
  const sections = [], arrangement = [];
  let v = 0, c = 0, b = 0;
  for (const block of blocks) {
    const rawLines = block.split('\n');
    const isChorus = CHORUS_RE.test(rawLines[0]);
    // Pull a leading stanza number ("1." / "12.") off the first line.
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

// ── Build one TopPresenter Song document ────────────────────────────────────────
function buildSong(s) {
  const denumire = String(s.denumire || '').trim();
  const m = denumire.match(/^(\d+[a-z]?)\s+(.+)$/i);
  const songNumber = m ? m[1] : '';
  const title = m ? m[2].trim() : denumire;
  const descriere = String(s.descriere || '');
  const hasLyrics = descriere.trim().length > 0;
  const { sections, arrangement } = parseLyrics(descriere);
  const pptUrl = s.url_fisier || '';
  const ext = (pptUrl.match(/\.(pptx?|key|odp)$/i) || [, 'pptx'])[1].toLowerCase();

  const melodiaExt = {
    id: String(s.id || ''),
    url: s.url || '',
    pptUrl,
    pptFile: pptUrl ? `${sanitize(denumire)}.${ext}` : '',
    dataAdaugare: s.data_adaugare || '',
    downloads: +(s.nr_descarcari || 0) || 0,
    views: +(s.nr_vizualizari || 0) || 0,
    categorySymbol: s.categoria_simbol || '',
    hasLyrics,
    hasPptx: !!pptUrl,
  };

  const song = {
    title: title || denumire || `cantare-${s.id}`,
    language: 'ro',
    songNumber,
    songbook: { name: s.categoria || 'Diverse', number: songNumber },
    versions: [{ name: '', language: 'ro', arrangement, sections }],
    _extensions: { cantaricrestine: melodiaExt },
  };
  return {
    schemaVersion: '1.0.0', format: 'TopPresenter Song',
    exportInfo: { source: 'cantaricrestine.ro', exportDate: new Date().toISOString(), exporterVersion: '1.0.0' },
    song,
  };
}

// ── Filenames ─────────────────────────────────────────────────────────────────
function sanitize(name) {
  return String(name || '').replace(/[\/\\:?%*|"<>]+/g, '-').replace(/\s+/g, ' ').trim().slice(0, 120);
}
function bookFolder(s) {
  return sanitize(s.categoria || `cat-${s.categoria_simbol || 'diverse'}`) || 'Diverse';
}

// ── Enumerate the whole catalog via the API ─────────────────────────────────────
async function fetchAllSongs(o) {
  const token = randToken();
  const first = await fetchJSON(`${API}?token=${token}&limita=${o.limita}&pagina=1`, o.retries);
  if (!first || !first.paginatie) { console.error('API enumeration failed.'); return []; }
  const totalPages = first.paginatie.total_pagini || 1;
  const total = first.paginatie.total_rezultate || 0;
  process.stderr.write(`Catalog: ${total} songs, ${totalPages} pages of ${o.limita}\n`);
  const all = Object.values(first.rezultate || {});
  for (let p = 2; p <= totalPages; p++) {
    const data = await fetchJSON(`${API}?token=${randToken()}&limita=${o.limita}&pagina=${p}`, o.retries);
    if (data && data.rezultate) all.push(...Object.values(data.rezultate));
    if (p % 5 === 0) process.stderr.write(`  …enumerated ${all.length}/${total}\n`);
    await sleep(o.delay);
  }
  return all;
}

// ── Main ────────────────────────────────────────────────────────────────────────
async function main() {
  const o = parseArgs(process.argv);

  if (o.print) {
    const token = randToken();
    const data = o.id
      ? await fetchJSON(`${API}?token=${token}&id=${o.id}`, o.retries)
      : await fetchJSON(`${API}?token=${token}&limita=1`, o.retries);
    const s = Object.values(data?.rezultate || {})[0];
    if (!s) { console.error('not found'); process.exit(1); }
    console.log(JSON.stringify(buildSong(s), null, 2));
    return;
  }

  await mkdir(o.out, { recursive: true });
  const songs = await fetchAllSongs(o);
  if (!songs.length) { console.error('No songs.'); process.exit(1); }

  // Per-book existing-file sets (for resume).
  const existingByFolder = new Map();
  async function existsIn(folder, file) {
    if (!existingByFolder.has(folder)) {
      const dir = path.join(o.out, folder);
      existingByFolder.set(folder, new Set(await readdir(dir).catch(() => [])));
    }
    return existingByFolder.get(folder).has(file);
  }

  const stats = {};   // per categoria
  const bump = (cat, k, n = 1) => { (stats[cat] ||= { apiTotal: 0, fetched: 0, withLyrics: 0, pptxOnly: 0, pptxDownloaded: 0, pptxMissing: 0 })[k] += n; };

  let written = 0, skipped = 0, diskFull = false;
  const queue = songs.slice();

  async function worker() {
    while (queue.length) {
      if (written >= o.limit) return;
      const s = queue.shift();
      const cat = s.categoria || 'Diverse';
      const folder = bookFolder(s);
      const base = sanitize(s.denumire || `cantare-${s.id}`);
      const jsonName = `${base}.json`;
      await mkdir(path.join(o.out, folder), { recursive: true });

      const doc = buildSong(s);
      const ce = doc.song._extensions.cantaricrestine;
      bump(cat, 'fetched');
      if (ce.hasLyrics) bump(cat, 'withLyrics'); else bump(cat, 'pptxOnly');

      // JSON (always — small, written first so a full disk still preserves metadata).
      const jsonPath = path.join(o.out, folder, jsonName);
      if (o.resume && await existsIn(folder, jsonName)) {
        skipped++;
      } else {
        try { await writeFile(jsonPath, JSON.stringify(doc, null, 2), 'utf8'); written++; }
        catch (e) { if (e.code === 'ENOSPC') diskFull = true; process.stderr.write(`✗ json ${base}: ${e.message}\n`); continue; }
        if (written % 100 === 0) process.stderr.write(`  …${written} written\n`);
      }

      // PowerPoint.
      if (!o.noPpt && ce.pptUrl) {
        const pptName = ce.pptFile;
        if (o.resume && await existsIn(folder, pptName)) { bump(cat, 'pptxDownloaded'); }
        else {
          const buf = await fetchBuffer(ce.pptUrl, o.retries);
          if (!buf) { bump(cat, 'pptxMissing'); }
          else {
            try { await writeFile(path.join(o.out, folder, pptName), buf); bump(cat, 'pptxDownloaded'); }
            catch (e) { bump(cat, 'pptxMissing'); if (e.code === 'ENOSPC') { diskFull = true; process.stderr.write(`⚠ DISK FULL — keeping JSON, skipping PowerPoints\n`); } }
          }
          await sleep(o.delay);
        }
      }
    }
  }

  await Promise.all(Array.from({ length: o.concurrency }, worker));

  // Completeness report.
  for (const s of songs) bump(s.categoria || 'Diverse', 'apiTotal');
  const report = { generated: new Date().toISOString(), totalSongs: songs.length, diskFull, books: stats };
  try { await writeFile(path.join(o.out, '_completeness.json'), JSON.stringify(report, null, 2), 'utf8'); } catch {}

  const tot = Object.values(stats).reduce((a, b) => ({
    withLyrics: a.withLyrics + b.withLyrics, pptxOnly: a.pptxOnly + b.pptxOnly,
    pptxDownloaded: a.pptxDownloaded + b.pptxDownloaded, pptxMissing: a.pptxMissing + b.pptxMissing,
  }), { withLyrics: 0, pptxOnly: 0, pptxDownloaded: 0, pptxMissing: 0 });
  process.stderr.write(`\nDone. ${written} written, ${skipped} skipped, of ${songs.length}.\n`);
  process.stderr.write(`  lyrics: ${tot.withLyrics} | pptx-only: ${tot.pptxOnly} | pptx saved: ${tot.pptxDownloaded} | pptx missing: ${tot.pptxMissing}\n`);
  if (diskFull) process.stderr.write(`  ⚠ DISK FILLED during run — JSON is complete, re-run after freeing space to finish PowerPoints (--resume skips done).\n`);
}

main().catch(e => { console.error(e); process.exit(1); });

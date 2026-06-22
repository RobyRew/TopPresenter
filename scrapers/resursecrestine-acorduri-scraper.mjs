#!/usr/bin/env node
//
// resursecrestine-acorduri-scraper.mjs
// ──────────────────────────────────────────────────────────────────────────────
// Scrapes the chords section of resursecrestine.ro (/acorduri) into TopPresenter
// "TopPresenter Song" GOAT JSON — one file per song. Each acord page already holds
// the FULL lyrics WITH chords (chords rendered above the lyric line), so every
// acord is a complete song-with-chords — no merge step is needed: these JSONs are
// the chorded counterpart of the lyrics-only /cantece songs.
//
// Chord markup (server HTML): inside `class="stil-acorduri"`, lines are split by
// <br>. A chord line is `&nbsp;`-padded `<a class="nice-acord" rel="G">G</a>`
// anchors; the next line is its lyrics. Column position (counting `&nbsp;` = 1
// char, advancing past each chord label) → the chord's char offset in the lyric
// line below → TopPresenter SongLine.chords [{sym,pos}].
//
// Enumerate: /acorduri/index-alfabetic/<LETTER>/pagina/<N> → `a.listingTitleLink`
// hrefs `/acorduri/<id>/<slug>`. Dependency-free (Node 18+), resumable.
//
// Usage:
//   node resursecrestine-acorduri-scraper.mjs                 # crawl all letters
//   node resursecrestine-acorduri-scraper.mjs --letters A,B
//   node resursecrestine-acorduri-scraper.mjs --print --url /acorduri/325063/x
//
// Options:
//   --out DIR        output (default ./ExtraAssets/Songs/resursecrestine-acorduri)
//   --letters L,..   restrict letters (default A..Z)
//   --limit N        stop after N new songs
//   --delay MS       pause between requests (default 300)
//   --concurrency N  parallel song fetches (default 3)
//   --retries N      retries per request (default 3)
//   --no-resume      re-download even if the file exists
//   --print          print one song JSON (use with --url), no writes
//   --url PATH       acord path for --print
// ──────────────────────────────────────────────────────────────────────────────

import { writeFile, mkdir, readdir } from 'node:fs/promises';
import path from 'node:path';

const BASE = 'https://www.resursecrestine.ro';
const UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) TopPresenter-AcorduriScraper/1.0';
const LETTERS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.split('');
const sleep = ms => new Promise(r => setTimeout(r, ms));

function parseArgs(argv) {
  const o = { out: './ExtraAssets/Songs/resursecrestine-acorduri', letters: null, limit: Infinity,
    delay: 300, concurrency: 3, retries: 3, resume: true, print: false, url: null };
  for (let i = 2; i < argv.length; i++) {
    const a = argv[i], next = () => argv[++i];
    if (a === '--out') o.out = next();
    else if (a === '--letters') o.letters = next().split(',').map(s => s.trim().toUpperCase()).filter(Boolean);
    else if (a === '--limit') o.limit = +next();
    else if (a === '--delay') o.delay = +next();
    else if (a === '--concurrency') o.concurrency = Math.max(1, +next());
    else if (a === '--retries') o.retries = +next();
    else if (a === '--no-resume') o.resume = false;
    else if (a === '--print') o.print = true;
    else if (a === '--url') o.url = next();
  }
  return o;
}

async function fetchText(url, retries) {
  for (let i = 0; i < retries; i++) {
    try {
      const res = await fetch(url, { headers: { 'User-Agent': UA } });
      if (res.ok) return await res.text();
      res.body?.cancel?.();
      if (res.status === 404) return null;
    } catch { /* retry */ }
    await sleep(400 * (i + 1));
  }
  return null;
}

// nbsp → U+00A0 (kept distinct from formatting whitespace so we can tell real
// chord-chart indentation apart from source-code newlines/indent).
const NAMED = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ', hellip: '…',
  ndash: '–', mdash: '—', rsquo: '’', acirc: 'â', icirc: 'î', abreve: 'ă', scedil: 'ș', tcedil: 'ț' };
function decode(s) {
  return String(s || '')
    .replace(/&#(\d+);/g, (_, n) => String.fromCodePoint(+n))
    .replace(/&#x([0-9a-f]+);/gi, (_, n) => String.fromCodePoint(parseInt(n, 16)))
    .replace(/&([a-z]+);/gi, (m, n) => (n in NAMED ? NAMED[n] : m));
}
const stripTags = s => String(s || '').replace(/<[^>]+>/g, '');
const normTitle = s => decode(s).toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '')
  .replace(/[^a-z0-9]+/g, ' ').trim();

// ── Chord-over-lyrics parser ────────────────────────────────────────────────────
function parseAcordLines(stilInner) {
  // The page mixes <br />, <br>, and escaped <br \/> — match any <br…> form.
  const rawLines = stilInner.split(/<br[^>]*>/gi);
  const parsed = [];
  for (const line of rawLines) {
    if (/class="nice-acord"/i.test(line)) {
      const chords = []; let col = 0;
      const re = /&nbsp;|<a\b[^>]*class="nice-acord"[^>]*>(.*?)<\/a>|([^<]+)/gi;
      let t;
      while ((t = re.exec(line))) {
        if (t[1] != null) { const sym = decode(stripTags(t[1])).trim(); if (sym) { chords.push({ sym, pos: col }); col += sym.length; } }
        else if (t[2] != null) { col += decode(t[2]).replace(/\s+/g, '').length; }  // ignore format ws
        else col += 1; // &nbsp;
      }
      parsed.push({ type: 'chord', chords });
    } else {
      // Normalize nbsp→space (source uses literal U+00A0), strip leading
      // newlines/tabs (formatting) but keep leading spaces (real chord-chart
      // indentation so columns still line up); trim trailing whitespace.
      const text = decode(stripTags(line)).replace(/ /g, ' ').replace(/^[\n\r\t]+/, '').replace(/\s+$/g, '');
      parsed.push({ type: 'lyric', text });
    }
  }
  // pair chord line with the following lyric line
  const lines = [];
  for (let i = 0; i < parsed.length; i++) {
    const p = parsed[i];
    if (p.type === 'chord' && parsed[i + 1]?.type === 'lyric') {
      const lyr = parsed[i + 1];
      const line = { text: lyr.text }; if (p.chords.length) line.chords = p.chords;
      lines.push(line); i++;
    } else if (p.type === 'lyric') {
      if (p.text.trim()) lines.push({ text: p.text });
    } else if (p.type === 'chord' && p.chords.length) {
      lines.push({ text: '', chords: p.chords });   // trailing chord-only line (e.g. intro)
    }
  }
  return lines;
}

// split flat lines into sections at blank lines / "1." / "R:" markers
const CHORUS_RE = /^\s*(R\d*[:.)]|Ref(?:ren|\.)?[:.)]?)/i;
function linesToSections(lines) {
  const sections = []; let cur = null; let v = 0, c = 0, b = 0;
  const flush = () => { if (cur && cur.lines.length) { sections.push(cur); } cur = null; };
  for (const ln of lines) {
    const head = ln.text || '';
    const blank = head.trim() === '' && !(ln.chords && ln.chords.length);
    const num = head.match(/^\s*(\d+)\s*[.)]\s*/);
    const isChorus = CHORUS_RE.test(head);
    if (blank) { flush(); continue; }
    if (num || isChorus || !cur) {
      flush();
      if (isChorus) { c++; cur = { id: 'c' + c, type: 'chorus', label: 'Refren' + (c > 1 ? ' ' + c : ''), order: sections.length, lines: [] }; }
      else { v++; cur = { id: 'v' + v, type: 'verse', label: 'Strofa ' + (num ? num[1] : v), order: sections.length, lines: [] }; }
      // strip the leading marker from the first line's text (keep chord positions — they sit past the marker)
      const stripped = head.replace(/^\s*\d+\s*[.)]\s*/, '').replace(CHORUS_RE, '');
      cur.lines.push({ ...ln, text: stripped });
      continue;
    }
    cur.lines.push(ln);
  }
  flush();
  return sections;
}

function buildSong(acordPath, html) {
  const idSlug = acordPath.match(/\/acorduri\/(\d+)\/([a-z0-9-]+)/i) || [];
  const id = idSlug[1] || ''; const slug = idSlug[2] || '';
  const title = decode((html.match(/<title>([^<]+)/) || [])[1] || slug)
    .replace(/ /g, ' ').replace(/\s*[-|]\s*Resurse\b[\s\S]*$/i, '').trim();
  const author = decode(stripTags((html.match(/Autor:\s*<\/?[^>]*>?\s*([^<|\n]+)/i)
    || html.match(/Autor:\s*([^<|\n]+)/i) || [])[1] || '')).trim();
  const m = html.match(/class="stil-acorduri"[^>]*>([\s\S]*?)<\/(?:div|pre|p)>/i)
    || html.match(/class="stil-acorduri"[^>]*>([\s\S]*?)(?:<div class="|<\/div>\s*<\/div>)/i);
  const stil = m ? m[1] : '';
  const lines = parseAcordLines(stil);
  const sections = linesToSections(lines);
  const arrangement = sections.map(s => s.id);
  const hasChords = sections.some(s => s.lines.some(l => l.chords && l.chords.length));
  // Infer the key from the first chord (the page states no tonality). Root only,
  // keeping a minor quality so it groups/transposes sensibly.
  let key = '';
  for (const s of sections) { for (const l of s.lines) { if (l.chords && l.chords.length) { key = inferKey(l.chords[0].sym); break; } } if (key) break; }
  return {
    schemaVersion: '1.0.0', format: 'TopPresenter Song',
    exportInfo: { source: 'resursecrestine.ro/acorduri', exportDate: new Date().toISOString(), exporterVersion: '1.0.0' },
    song: {
      title: title || slug, language: 'ro', author,
      versions: [{ name: '', language: 'ro', key, arrangement, sections }],
      _extensions: { resursecrestineAcorduri: { id, slug, url: `${BASE}${acordPath}`, matchKey: normTitle(title), hasChords, keyInferred: !!key } },
    },
  };
}
/// Root (+ minor) of a chord symbol, e.g. "Em7" → "Em", "C#sus4" → "C#", "Bb/D" → "Bb".
function inferKey(sym) {
  const m = String(sym || '').match(/^([A-G][#b]?)(m(?!aj))?/);
  return m ? m[1] + (m[2] ? 'm' : '') : '';
}

// ── Enumerate acord links per letter ────────────────────────────────────────────
function pageLinks(html) {
  // Acord song URLs are id-first `/acorduri/<id>/<slug>`; the `\d+` excludes the
  // index-alfabetic / index-tematic / index-autori links.
  const out = []; const seen = new Set();
  const re = /\/acorduri\/\d+\/[a-z0-9\-]+/gi;
  let m;
  while ((m = re.exec(html))) { const u = m[0]; if (!seen.has(u)) { seen.add(u); out.push(u); } }
  return out;
}
function lastPage(html) {
  const nums = [...html.matchAll(/\/acorduri\/index-alfabetic\/[A-Z]\/pagina\/(\d+)/gi)].map(m => +m[1]);
  return nums.length ? Math.max(...nums) : 1;
}
async function enumerateLetter(letter, retries) {
  const first = await fetchText(`${BASE}/acorduri/index-alfabetic/${letter}/pagina/1`, retries);
  if (!first) return [];
  const pages = lastPage(first);
  let links = pageLinks(first);
  for (let p = 2; p <= pages; p++) {
    const h = await fetchText(`${BASE}/acorduri/index-alfabetic/${letter}/pagina/${p}`, retries);
    if (h) links = links.concat(pageLinks(h));
    await sleep(150);
  }
  return [...new Set(links)];
}

const sanitize = n => String(n || '').replace(/[\/\\:?%*|"<>]+/g, '-').replace(/\s+/g, ' ').trim().slice(0, 120);

async function main() {
  const o = parseArgs(process.argv);
  if (o.print && o.url) {
    const html = await fetchText(`${BASE}${o.url}`, o.retries);
    if (!html) { console.error('fetch failed'); process.exit(1); }
    console.log(JSON.stringify(buildSong(o.url, html), null, 2));
    return;
  }
  await mkdir(o.out, { recursive: true });
  const existing = new Set((await readdir(o.out).catch(() => [])).map(f => f.replace(/\.json$/i, '')));
  const letters = o.letters || LETTERS;

  let written = 0, skipped = 0, failed = 0, withChords = 0;
  for (const letter of letters) {
    if (written >= o.limit) break;
    process.stderr.write(`Letter ${letter}: enumerating… `);
    const links = await enumerateLetter(letter, o.retries);
    process.stderr.write(`${links.length} acorduri\n`);
    const queue = links.slice();
    async function worker() {
      while (queue.length) {
        if (written >= o.limit) return;
        const acordPath = queue.shift();
        const slug = (acordPath.match(/\/acorduri\/\d+\/([a-z0-9-]+)/i) || [])[1] || acordPath;
        const html = await fetchText(`${BASE}${acordPath}`, o.retries);
        if (!html) { failed++; await sleep(o.delay); continue; }
        let doc; try { doc = buildSong(acordPath, html); } catch (e) { failed++; process.stderr.write(`✗ ${slug}: ${e.message}\n`); continue; }
        const base = sanitize(doc.song.title || slug);
        if (o.resume && existing.has(base)) { skipped++; continue; }
        try {
          await writeFile(path.join(o.out, `${base}.json`), JSON.stringify(doc, null, 2), 'utf8');
          written++; existing.add(base);
          if (doc.song._extensions.resursecrestineAcorduri.hasChords) withChords++;
          if (written % 50 === 0) process.stderr.write(`  …${written} written\n`);
        } catch (e) { failed++; process.stderr.write(`✗ write ${base}: ${e.message}\n`); }
        await sleep(o.delay);
      }
    }
    await Promise.all(Array.from({ length: o.concurrency }, worker));
  }
  process.stderr.write(`\nDone. ${written} written (${withChords} with chords), ${skipped} skipped, ${failed} failed.\n`);
}

main().catch(e => { console.error(e); process.exit(1); });

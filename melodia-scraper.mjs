#!/usr/bin/env node
//
// melodia-scraper.mjs
// ──────────────────────────────────────────────────────────────────────────────
// Scrapes songs from melodia.ro/cantari into TopPresenter's "TopPresenter Song"
// GOAT JSON — ONE file per song — ready for bulk folder-import.
//
// The catalog (~2.6k songs) is enumerated from /sitemap.xml (every
// /cantari/<slug> URL). Each song page is server-rendered: the `verse`/`chorus`/
// `bridge` blocks (with inline <div class="chord">…</div> at the exact letter)
// become rich sections with chord positions; the song key, tempo (bpm), time
// signature (beats), authors (Muzica/Versuri), copyright, composed year, keywords
// (Cuvinte Cheie → themes), song map (→ arrangement) and the "Anatomia
// Evangheliei" analysis are all carried across into `song._extensions.melodia`.
//
// CHORDS / KEYS: chords are stored ONCE in the song's own key (F here) as
// {sym,pos}; every other key (C, C#, Db, D…) is reproducible by transposition,
// so we don't bake 12 copies. We DO record the list of keys melodia offers plus a
// computed capo recommendation per instrument. The exact capo fret diagrams that
// melodia draws are rendered client-side (React) and are NOT in this server HTML —
// the Tampermonkey userscript captures those; here we compute the recommendation.
//
// Dependency-free (Node 18+ global fetch, auto-gunzip). Resumable: re-running
// skips songs whose JSON already exists.
//
// Usage:
//   node melodia-scraper.mjs                          # crawl everything (sitemap)
//   node melodia-scraper.mjs --slugs Voi-canta-bunatatea-Ta,A-Ta-e-domnia
//   node melodia-scraper.mjs --limit 25               # smoke test (first 25)
//   node melodia-scraper.mjs --out ./ExtraAssets/Songs/melodia.ro --delay 300 --concurrency 4
//
// Options:
//   --out DIR          output folder        (default ./ExtraAssets/Songs/melodia.ro)
//   --slugs a,b,c      scrape only these slugs; skips sitemap enumeration
//   --limit N          stop after N new songs (testing)
//   --delay MS         pause between requests (default 250)
//   --concurrency N    parallel song fetches (default 4)
//   --retries N        retries per request   (default 3)
//   --no-resume        re-download even if the file exists
//   --manifest         also write _manifest.json (slug,title,id,file)
//   --print            print one song's JSON to stdout (with --slugs, no write)
// ──────────────────────────────────────────────────────────────────────────────

import { writeFile, mkdir, readdir } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import path from 'node:path';

const BASE = 'https://melodia.ro';
const UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) TopPresenter-MelodiaScraper/1.0';
const sleep = ms => new Promise(r => setTimeout(r, ms));

// ── CLI ─────────────────────────────────────────────────────────────────────
function parseArgs(argv) {
  const o = {
    out: './ExtraAssets/Songs/melodia.ro', delay: 250, concurrency: 4, retries: 3,
    resume: true, manifest: false, slugs: null, limit: Infinity, print: false,
  };
  for (let i = 2; i < argv.length; i++) {
    const a = argv[i], next = () => argv[++i];
    if (a === '--out') o.out = next();
    else if (a === '--delay') o.delay = +next();
    else if (a === '--concurrency') o.concurrency = Math.max(1, +next());
    else if (a === '--retries') o.retries = +next();
    else if (a === '--limit') o.limit = +next();
    else if (a === '--slugs') o.slugs = next().split(',').map(s => s.trim()).filter(Boolean);
    else if (a === '--no-resume') o.resume = false;
    else if (a === '--manifest') o.manifest = true;
    else if (a === '--print') o.print = true;
    else if (a === '-h' || a === '--help') { printHelp(); process.exit(0); }
  }
  return o;
}
function printHelp() {
  console.log(`melodia-scraper — scrape melodia.ro into TopPresenter Song JSON
  node melodia-scraper.mjs [--out DIR] [--slugs a,b] [--limit N] [--delay MS]
                           [--concurrency N] [--retries N] [--no-resume] [--manifest] [--print]`);
}

// ── Network ───────────────────────────────────────────────────────────────────
async function fetchText(url, retries) {
  for (let attempt = 0; attempt < retries; attempt++) {
    try {
      const res = await fetch(url, { headers: { 'User-Agent': UA, 'Accept-Encoding': 'gzip, br' } });
      if (res.ok) return await res.text();
      // Drain so the socket frees (undici leaks otherwise).
      res.body?.cancel?.();
      if (res.status === 404) return null;
    } catch { /* retry */ }
    await sleep(400 * (attempt + 1));
  }
  return null;
}

// ── HTML helpers (DOM-free regex; the page is server-rendered) ──────────────────
const NAMED = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ', hellip: '…',
  ndash: '–', mdash: '—', rsquo: '’', lsquo: '‘', rdquo: '”', ldquo: '“', laquo: '«', raquo: '»',
  acirc: 'â', Acirc: 'Â', icirc: 'î', Icirc: 'Î', abreve: 'ă', Abreve: 'Ă', scedil: 'ş', tcedil: 'ţ',
  copy: '©' };
function decodeEntities(s) {
  if (!s || s.indexOf('&') < 0) return s || '';
  return s
    .replace(/&#(\d+);/g, (_, n) => String.fromCodePoint(+n))
    .replace(/&#x([0-9a-f]+);/gi, (_, n) => String.fromCodePoint(parseInt(n, 16)))
    .replace(/&([a-z]+);/gi, (m, n) => (n in NAMED ? NAMED[n] : m));
}
const stripTags = s => decodeEntities(String(s || '').replace(/<[^>]+>/g, ' ')).replace(/\s+/g, ' ').trim();
function attr(html, name) {
  const m = html.match(new RegExp(name + '=(["\'])(.*?)\\1'));
  return m ? decodeEntities(m[2]) : '';
}
function ldJsonBlocks(html) {
  const out = [];
  const re = /<script[^>]*type="application\/ld\+json"[^>]*>([\s\S]*?)<\/script>/gi;
  let m; while ((m = re.exec(html))) { try { out.push(JSON.parse(m[1])); } catch {} }
  return out;
}
function jsonScript(html, id) {
  const m = html.match(new RegExp('<script[^>]*id="' + id + '"[^>]*>([\\s\\S]*?)<\\/script>', 'i'));
  if (!m) return null;
  try { return JSON.parse(m[1]); } catch { return null; }
}

// ── Music theory: chord parsing / transposition / capo ──────────────────────────
const SEMI = { C: 0, 'C#': 1, Db: 1, D: 2, 'D#': 3, Eb: 3, E: 4, F: 5, 'F#': 6, Gb: 6,
  G: 7, 'G#': 8, Ab: 8, A: 9, 'A#': 10, Bb: 10, B: 11 };
const SHARP = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
const FLAT  = ['C', 'Db', 'D', 'Eb', 'E', 'F', 'Gb', 'G', 'Ab', 'A', 'Bb', 'B'];
const FLAT_KEYS = new Set(['F', 'Bb', 'Eb', 'Ab', 'Db', 'Gb', 'Dm', 'Gm', 'Cm', 'Fm', 'Bbm']);

const rootSemi = root => (root in SEMI ? SEMI[root] : null);
function spell(semi, preferFlat) {
  semi = ((semi % 12) + 12) % 12;
  return (preferFlat ? FLAT : SHARP)[semi];
}
/// Transpose a chord symbol ("Dm7", "Bb", "D/F#") by `delta` semitones.
function transposeChord(sym, delta, preferFlat) {
  if (!sym || !delta) return sym;
  const one = part => {
    const m = part.match(/^([A-G][#b]?)(.*)$/);
    if (!m) return part;
    const r = rootSemi(m[1]);
    if (r == null) return part;
    return spell(r + delta, preferFlat) + m[2];
  };
  return sym.split('/').map(one).join('/');
}
/// Capo recommendation: the first open-shape key (in preference order) reachable
/// with a capo of 1..maxCapo. melodia favours G/D/C shapes on guitar (e.g. an F
/// song → D shapes, capo 3), which this order reproduces. Returns {capo,shapeKey}.
/// NOTE: this is a heuristic — the userscript captures melodia's exact value.
function recommendCapo(key, preferredRoots, maxCapo = 8) {
  const minor = /m$/.test(key);
  const r = rootSemi(key.replace(/m$/, ''));
  if (r == null) return null;
  for (const pr of preferredRoots) {
    const sr = rootSemi(pr);
    if (sr == null) continue;
    const capo = (((r - sr) % 12) + 12) % 12;
    if (capo >= 1 && capo <= maxCapo) return { capo, shapeKey: pr + (minor ? 'm' : '') };
  }
  return null;
}
const GUITAR_PREF = ['G', 'D', 'C', 'A', 'E'];
const UKULELE_PREF = ['C', 'G', 'F', 'D', 'A'];

// ── Section parsing ─────────────────────────────────────────────────────────────
const SECTION_TYPES = ['verse', 'chorus', 'prechorus', 'pre-chorus', 'bridge', 'intro', 'outro', 'ending', 'tag', 'interlude'];
function typeFromClass(cls) {
  const c = (cls || '').toLowerCase();
  for (const t of SECTION_TYPES) if (c.includes(t)) return t === 'pre-chorus' ? 'prechorus' : t;
  return 'verse';
}
const TYPE_PREFIX = { verse: 'v', chorus: 'c', prechorus: 'p', bridge: 'b', intro: 'i',
  outro: 'e', ending: 'e', tag: 't', interlude: 'in' };
const normText = lines => lines.map(l => l.text.trim()).join('\n').toLowerCase().replace(/\s+/g, ' ');
function labelFor(type, key) {
  const n = key.replace(/^[a-z]+/i, '');
  const base = { verse: 'Strofa', chorus: 'Refren', prechorus: 'Pre-refren', bridge: 'Punte',
    intro: 'Intro', ending: 'Final', tag: 'Tag', interlude: 'Interludiu' }[type] || 'Strofa';
  return n ? `${base} ${n}` : base;
}
/// Parse one section's inner HTML into [{text, chords:[{sym,pos}]}] lines.
function parseSectionLines(inner) {
  const rawLines = inner.split(/<br\s*\/?>/i);
  const lines = [];
  for (const raw of rawLines) {
    let text = '', chords = [];
    const re = /<div class="chord">([\s\S]*?)<\/div>|([^<]+)|<[^>]+>/gi;
    let m;
    while ((m = re.exec(raw))) {
      if (m[1] != null) {
        const sym = decodeEntities(m[1]).trim();
        if (sym) chords.push({ sym, pos: text.length });
      } else if (m[2] != null) {
        text += decodeEntities(m[2]);
      }
    }
    text = text.replace(/\s+$/g, '');
    if (text.trim() === '' && chords.length === 0) continue;
    const line = { text };
    if (chords.length) line.chords = chords;
    lines.push(line);
  }
  return lines;
}
/// Parse the song body into unique sections + the play-order arrangement.
/// melodia re-renders each occurrence of a section (the same chorus appears as
/// chorus-1, chorus-2, …) so we dedupe identical sections by content and let the
/// arrangement reference the canonical key each time it is sung — exactly what
/// TopPresenter's arrangement model is for.
/// Return a section div's inner HTML by balancing <div> depth from `start`
/// (just after the opening tag). Robust to nested <div class="chord"> and to any
/// whitespace between sibling sections — unlike a lookahead boundary.
function balancedDivInner(html, start) {
  const re = /<\/?div\b[^>]*>/gi; re.lastIndex = start;
  let depth = 1, m;
  while ((m = re.exec(html))) {
    if (m[0][1] === '/') { if (--depth === 0) return html.slice(start, m.index); }
    else depth++;
  }
  return html.slice(start);
}
function parseSectionsAndArrangement(html) {
  const openRe = /<div class="((?:verse|chorus|prechorus|pre-chorus|bridge|intro|outro|ending|tag|interlude)[^"]*)" data-section-key="[^"]+">/gi;
  const sections = [], arrangement = [], idxByType = {}, canonByContent = new Map();
  let m;
  while ((m = openRe.exec(html))) {
    const type = typeFromClass(m[1]);
    const lines = parseSectionLines(balancedDivInner(html, m.index + m[0].length));
    if (!lines.length) continue;
    const sig = type + '|' + normText(lines);
    let key = canonByContent.get(sig);
    if (!key) {
      const prefix = TYPE_PREFIX[type] || 'v';
      const n = (idxByType[prefix] = (idxByType[prefix] || 0) + 1);
      key = prefix + n;
      canonByContent.set(sig, key);
      sections.push({ id: key, type, label: labelFor(type, key), order: sections.length, lines });
    }
    arrangement.push(key);
  }
  return { sections, arrangement };
}

// ── Page metadata parsing ───────────────────────────────────────────────────────
function parseAnatomia(html) {
  const i = html.indexOf('Anatomia Evangheliei');
  if (i < 0) return null;
  const chunk = html.slice(i, i + 4000);
  const out = {};
  const score = chunk.match(/Anatomia Evangheliei[\s\S]{0,400}?>\s*(\d+)\s*\/\s*(\d+)\s*</);
  if (score) { out.score = +score[1]; out.scoreMax = +score[2]; }
  // Description = the italic <p> right after the score badge.
  const desc = chunk.match(/font-style:\s*italic;[^>]*>([\s\S]*?)<\/p>/i);
  if (desc) out.description = stripTags(desc[1]);
  // Categories: each row has a min-width:88px name span + a width:N% bar.
  const categories = [];
  const catRe = /min-width:\s*88px;?[^>]*>([^<]+)<\/span>[\s\S]{0,200}?width:\s*(\d+)%/gi;
  let m; while ((m = catRe.exec(chunk))) categories.push({ name: decodeEntities(m[1]).trim(), percent: +m[2] });
  if (categories.length) out.categories = categories;
  return Object.keys(out).length ? out : null;
}
function parseKeywords(html) {
  const out = [];
  const re = /\/cantari\?t=([^"'&]+)/gi;
  let m; const seen = new Set();
  while ((m = re.exec(html))) {
    const t = decodeEntities(decodeURIComponent(m[1].replace(/\+/g, ' '))).trim();
    const k = t.toLowerCase();
    if (t && !seen.has(k)) { seen.add(k); out.push(t); }
  }
  return out;
}
function parseAvailableKeys(html) {
  const sel = html.match(/key-transpose-selector[\s\S]*?<\/select>/i);
  if (!sel) return [];
  const out = [];
  const re = /<option value="([^"]+)"/gi; let m;
  while ((m = re.exec(sel[0]))) if (m[1]) out.push(m[1]);
  return [...new Set(out)];
}
function faqAnswer(faq, qIncludes) {
  for (const item of (faq?.mainEntity || [])) {
    if ((item.name || '').toLowerCase().includes(qIncludes)) return item.acceptedAnswer?.text || '';
  }
  return '';
}

// ── Build the TopPresenter Song JSON ────────────────────────────────────────────
function buildSong(slug, html) {
  const lds = ldJsonBlocks(html);
  const comp = lds.find(b => b['@type'] === 'MusicComposition') || {};
  const faq = lds.find(b => b['@type'] === 'FAQPage');
  const mobile = jsonScript(html, 'mobile-song-data') || {};

  const title = (comp.name || attr(html, 'data-song-title') ||
    (html.match(/<title>([^,<]+)/) || [])[1] || slug).trim();
  const songId = attr(html, 'data-song-id');
  const key = (mobile.key || (faqAnswer(faq, 'tonalitate').match(/tonalitatea\s+([A-G][#b]?m?)/i) || [])[1] || '').trim();
  const bpm = attr(html, 'data-bpm');
  const beats = attr(html, 'data-beats');
  const timeSignature = beats ? `${beats}/4` : '';

  // Authors: "Muzica: X. Versuri: Y"
  const authorsText = faqAnswer(faq, 'cine a scris') || '';
  const authorMusic = (authorsText.match(/Muzica:\s*([^.]+)/i) || [])[1]?.trim() ||
    (comp.composer?.name || '').trim();
  const authorWords = (authorsText.match(/Versuri:\s*([^.]+)/i) || [])[1]?.trim() || '';

  // Composed year + meetings + copyright
  const composedYear = +((html.match(/year-written[^>]*>Compus[ăa]\s+în\s*<b>(\d{4})<\/b>/i) || [])[1] ||
    (faqAnswer(faq, 'compusa').match(/(\d{4})/) || [])[1] || 0) || null;
  const meetings = +((html.match(/Cântat[ăa]\s+în\s*<b>(\d+)<\/b>/i) || [])[1] || 0) || null;
  const copyrightBlock = stripTags((html.match(/<span>(All rights reserved[\s\S]*?)<\/span>/i) || [])[1] || '');

  const themes = parseKeywords(html);
  const { sections, arrangement } = parseSectionsAndArrangement(html);
  const songMap = (mobile.songMap || []).filter(Boolean);

  // Capo recommendations (computed; exact diagrams come from the userscript).
  const availableKeys = parseAvailableKeys(html);
  const preferFlat = FLAT_KEYS.has(key);
  const instruments = {};
  if (key) {
    const g = recommendCapo(key, GUITAR_PREF);
    const u = recommendCapo(key, UKULELE_PREF);
    if (g) instruments.guitar = { tuning: 'EADGBE', recommendedCapo: g.capo, shapeKey: g.shapeKey };
    if (u) instruments.ukulele = { tuning: 'GCEA', recommendedCapo: u.capo, shapeKey: u.shapeKey };
  }

  // melodia-specific extras under a namespaced _extensions block.
  const melodia = { id: songId || undefined, slug, url: `${BASE}/cantari/${slug}` };
  if (composedYear) melodia.composedYear = composedYear;
  if (meetings != null) melodia.meetingsCount = meetings;
  if (bpm) melodia.bpm = +bpm;
  if (availableKeys.length) melodia.availableKeys = availableKeys;
  melodia.availableCapos = [0, 1, 2, 3, 4, 5, 6, 7, 8];
  if (Object.keys(instruments).length) melodia.instruments = instruments;
  const anatomia = parseAnatomia(html);
  if (anatomia) melodia.anatomiaEvangheliei = anatomia;
  if (songMap.length) melodia.songMap = songMap;

  const version = {
    name: '', language: 'ro', key, capo: 0, tempo: bpm || '', timeSignature,
    source: `${BASE}/cantari/${slug}`,
    arrangement, sections,
  };

  const song = {
    title, language: 'ro',
    themes,
    authorWords, authorMusic,
    author: [authorMusic, authorWords].filter(Boolean).filter((v, i, a) => a.indexOf(v) === i).join(', '),
    copyright: copyrightBlock,
    versions: [version],
    _extensions: { melodia },
  };
  return {
    schemaVersion: '1.0.0', format: 'TopPresenter Song',
    exportInfo: { source: 'melodia.ro', exportDate: new Date().toISOString(), exporterVersion: '1.0.0' },
    song,
  };
}

// ── Enumeration ─────────────────────────────────────────────────────────────────
async function enumerateSlugs(retries) {
  const xml = await fetchText(`${BASE}/sitemap.xml`, retries);
  if (!xml) return [];
  const slugs = [];
  // Single-segment song slugs only (skip /cantari/<a>/<b> sub-paths and queries).
  const re = /<loc>https?:\/\/melodia\.ro\/cantari\/([^<>?/]+)<\/loc>/gi;
  let m; const seen = new Set();
  while ((m = re.exec(xml))) {
    const slug = m[1].trim();
    if (slug && !seen.has(slug)) { seen.add(slug); slugs.push(slug); }
  }
  return slugs;
}

// ── Filenames ─────────────────────────────────────────────────────────────────
function sanitize(name) {
  return name.replace(/[\/\\:?%*|"<>]+/g, '-').replace(/\s+/g, ' ').trim().slice(0, 120);
}

// ── Main ────────────────────────────────────────────────────────────────────────
async function main() {
  const o = parseArgs(process.argv);

  if (o.print && o.slugs?.length) {
    const html = await fetchText(`${BASE}/cantari/${o.slugs[0]}`, o.retries);
    if (!html) { console.error('fetch failed'); process.exit(1); }
    console.log(JSON.stringify(buildSong(o.slugs[0], html), null, 2));
    return;
  }

  await mkdir(o.out, { recursive: true });

  let slugs = o.slugs;
  if (!slugs) {
    process.stderr.write('Enumerating sitemap… ');
    slugs = await enumerateSlugs(o.retries);
    process.stderr.write(`${slugs.length} songs\n`);
  }
  if (!slugs.length) { console.error('No songs found.'); process.exit(1); }

  const existing = new Set((await readdir(o.out).catch(() => [])).map(f => f.replace(/\.json$/i, '')));
  const manifest = [];
  let done = 0, written = 0, failed = 0, skipped = 0;

  const queue = slugs.slice();
  async function worker() {
    while (queue.length) {
      if (written >= o.limit) return;
      const slug = queue.shift();
      done++;
      const safe = sanitize(slug);
      if (o.resume && existing.has(safe)) { skipped++; continue; }
      const html = await fetchText(`${BASE}/cantari/${slug}`, o.retries);
      if (!html) { failed++; process.stderr.write(`✗ ${slug}\n`); await sleep(o.delay); continue; }
      try {
        const doc = buildSong(slug, html);
        if (doc.song.versions[0].sections.length === 0) {
          failed++; process.stderr.write(`✗ ${slug} (no sections)\n`);
        } else {
          const file = path.join(o.out, `${safe}.json`);
          await writeFile(file, JSON.stringify(doc, null, 2), 'utf8');
          written++;
          if (o.manifest) manifest.push({ slug, title: doc.song.title, id: doc.song._extensions.melodia.id, file: `${safe}.json` });
          if (written % 25 === 0) process.stderr.write(`  …${written} written (${done}/${slugs.length})\n`);
        }
      } catch (e) { failed++; process.stderr.write(`✗ ${slug}: ${e.message}\n`); }
      await sleep(o.delay);
    }
  }

  await Promise.all(Array.from({ length: o.concurrency }, worker));

  if (o.manifest) await writeFile(path.join(o.out, '_manifest.json'), JSON.stringify(manifest, null, 2), 'utf8');
  process.stderr.write(`\nDone. ${written} written, ${skipped} skipped, ${failed} failed, of ${slugs.length}.\n`);
}

main().catch(e => { console.error(e); process.exit(1); });

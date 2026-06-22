#!/usr/bin/env node
//
// resursecrestine-scraper.mjs
// ──────────────────────────────────────────────────────────────────────────────
// Scrapes songs from resursecrestine.ro/cantece into TopPresenter's GOAT
// "TopPresenter Song" JSON — ONE file per song — ready for bulk folder-import.
//
// The catalog (~28k songs) is enumerated through the alphabetical index
// (/cantece/index-alfabetic/{LETTER}/pagina/{N}); each song page's `.strofa`
// blocks become rich sections (verse/chorus + /: :/ repeat markers), and the
// Autor / Album / Tematica metadata + bible reference are carried across.
//
// Dependency-free (Node 18+ global fetch). Resumable: re-running skips songs
// whose JSON already exists, so you can crawl in chunks or recover from stops.
//
// Usage:
//   node resursecrestine-scraper.mjs                       # crawl everything
//   node resursecrestine-scraper.mjs --letters A,B,C       # only these letters
//   node resursecrestine-scraper.mjs --limit 50            # stop after 50 songs (smoke test)
//   node resursecrestine-scraper.mjs --ids 325194,325173   # specific song ids, skip enumeration
//   node resursecrestine-scraper.mjs --out ./songs --delay 300 --concurrency 4
//
// Options:
//   --out DIR          output folder            (default ./resursecrestine-songs)
//   --letters L,L,...  restrict to letters      (default: discovered A–Z …)
//   --ids ID,ID,...    scrape only these ids; skips enumeration entirely
//   --limit N          stop after N new songs   (testing)
//   --delay MS         pause between requests   (default 350)
//   --concurrency N    parallel song fetches    (default 4)
//   --retries N        retries per request      (default 3)
//   --no-resume        re-download even if the file already exists
//   --manifest         also write _manifest.json (id,title,url,file)
// ──────────────────────────────────────────────────────────────────────────────

import { writeFile, mkdir, readdir } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import path from 'node:path';

const BASE = 'https://www.resursecrestine.ro';
const UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) TopPresenter-SongScraper/1.0';

// ── CLI parsing ───────────────────────────────────────────────────────────────
function parseArgs(argv) {
  const o = {
    out: './resursecrestine-songs', delay: 350, concurrency: 4, retries: 3,
    resume: true, manifest: false, letters: null, ids: null, limit: Infinity,
  };
  for (let i = 2; i < argv.length; i++) {
    const a = argv[i];
    const next = () => argv[++i];
    if (a === '--out') o.out = next();
    else if (a === '--delay') o.delay = +next();
    else if (a === '--concurrency') o.concurrency = Math.max(1, +next());
    else if (a === '--retries') o.retries = +next();
    else if (a === '--limit') o.limit = +next();
    else if (a === '--letters') o.letters = next().split(',').map(s => s.trim()).filter(Boolean);
    else if (a === '--ids') o.ids = next().split(',').map(s => s.trim()).filter(Boolean);
    else if (a === '--no-resume') o.resume = false;
    else if (a === '--manifest') o.manifest = true;
    else if (a === '-h' || a === '--help') { printHelp(); process.exit(0); }
    else { console.error(`Unknown option: ${a}`); process.exit(1); }
  }
  return o;
}
function printHelp() {
  console.log(`Scrape resursecrestine.ro/cantece → TopPresenter Song JSON (one file per song).
Run with --limit 5 first to sanity-check the output, then drop --limit for the full crawl.
See the header of this file for all options.`);
}

const sleep = ms => new Promise(r => setTimeout(r, ms));

// ── Networking (retry + polite delay) ──────────────────────────────────────────
async function getText(url, opts) {
  for (let attempt = 1; attempt <= opts.retries; attempt++) {
    try {
      const res = await fetch(url, { headers: { 'User-Agent': UA, 'Accept-Language': 'ro,en;q=0.8' } });
      // Always drain/cancel the body — an unconsumed body keeps the undici
      // response alive and leaks memory over a long crawl.
      if (res.status === 404) { await res.body?.cancel?.(); return null; }
      if (!res.ok) { await res.body?.cancel?.(); throw new Error(`HTTP ${res.status}`); }
      return await res.text();
    } catch (err) {
      if (attempt === opts.retries) throw err;
      await sleep(opts.delay * attempt * 2);
    }
  }
}

// ── HTML helpers ────────────────────────────────────────────────────────────────
function decodeEntities(s) {
  return s
    .replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&').replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#0?39;|&apos;|&rsquo;/g, "'")
    .replace(/&hellip;/g, '…').replace(/&ndash;/g, '–').replace(/&mdash;/g, '—')
    .replace(/&#(\d+);/g, (_, n) => String.fromCodePoint(+n))
    .replace(/&#x([0-9a-f]+);/gi, (_, n) => String.fromCodePoint(parseInt(n, 16)));
}
const stripTags = s => decodeEntities(s.replace(/<[^>]+>/g, '')).replace(/[ \t]+/g, ' ').trim();
const attr = (html, name) => {
  const m = html.match(new RegExp(`<meta\\s+property="${name}"\\s+content="([^"]*)"`, 'i'))
    || html.match(new RegExp(`<meta\\s+name="${name}"\\s+content="([^"]*)"`, 'i'));
  return m ? decodeEntities(m[1]) : '';
};

// ── Enumeration ─────────────────────────────────────────────────────────────────
async function discoverLetters(opts) {
  if (opts.letters) return opts.letters;
  const html = await getText(`${BASE}/cantece`, opts);
  const set = new Set();
  for (const m of (html ?? '').matchAll(/index-alfabetic\/([^"\/]+)"/g)) set.add(decodeURIComponent(m[1]));
  const letters = [...set];
  return letters.length ? letters : 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.split('');
}

function songLinksFrom(html) {
  const ids = new Map();   // id -> slug
  for (const m of html.matchAll(/\/cantece\/(\d+)\/([a-z0-9-]+)/g)) {
    if (!ids.has(m[1])) ids.set(m[1], m[2]);
  }
  return ids;
}
function maxPageFor(letter, html) {
  let max = 1;
  const re = new RegExp(`index-alfabetic\\/${letter}\\/pagina\\/(\\d+)`, 'g');
  for (const m of html.matchAll(re)) max = Math.max(max, +m[1]);
  return max;
}

async function enumerateSongs(opts) {
  const letters = await discoverLetters(opts);
  const all = new Map();   // id -> slug
  for (const letter of letters) {
    const first = await getText(`${BASE}/cantece/index-alfabetic/${encodeURIComponent(letter)}`, opts);
    if (!first) continue;
    const pages = maxPageFor(letter, first);
    for (const [id, slug] of songLinksFrom(first)) all.set(id, slug);
    process.stderr.write(`  · letter ${letter}: ${pages} page(s)\n`);
    for (let p = 2; p <= pages; p++) {
      await sleep(opts.delay);
      const html = await getText(`${BASE}/cantece/index-alfabetic/${encodeURIComponent(letter)}/pagina/${p}`, opts);
      if (html) for (const [id, slug] of songLinksFrom(html)) all.set(id, slug);
    }
    await sleep(opts.delay);
  }
  return all;
}

// ── Section classification ───────────────────────────────────────────────────────
function classifySection(label, index, counters) {
  const l = label.toLowerCase();
  const num = (label.match(/\d+/) || [''])[0];
  const next = k => (counters[k] = (counters[k] || 0) + 1);
  if (/refren|cor\b/.test(l)) { const n = next('c'); return { type: 'chorus', key: n === 1 ? 'c' : `c${n}` }; }
  if (/pre-?refren|pre-?cor/.test(l)) { const n = next('p'); return { type: 'prechorus', key: `p${n}` }; }
  if (/punte|bridge/.test(l)) { const n = next('b'); return { type: 'bridge', key: `b${n}` }; }
  if (/intro/.test(l)) return { type: 'intro', key: 'i' };
  if (/final|încheiere|incheiere|coda|sfâr|sfar/.test(l)) return { type: 'ending', key: 'e' };
  if (/strof|vers/.test(l)) { const n = num || next('v'); return { type: 'verse', key: `v${n}` }; }
  const n = next('s');
  return { type: 'other', key: `s${n}` };
}

// The page prints the lyric block twice; if the list is an exact double
// (first half ≡ second half), keep only the first half.
function dropDoubled(blocks) {
  const n = blocks.length;
  if (n >= 2 && n % 2 === 0) {
    const half = n / 2;
    const sig = b => `${b.label} ${b.text}`;
    let mirrored = true;
    for (let i = 0; i < half; i++) {
      if (sig(blocks[i]) !== sig(blocks[i + half])) { mirrored = false; break; }
    }
    if (mirrored) return blocks.slice(0, half);
  }
  return blocks;
}

// `/: … :/  2x` → repeatCount, with the markers stripped from the text.
function extractRepeat(text) {
  let repeat = 1;
  if (/\/:/.test(text) || /:\//.test(text)) {
    const m = text.match(/:\/\s*\(?\s*(\d+)\s*x/i);
    repeat = m ? Math.max(2, +m[1]) : 2;
  }
  const cleaned = text
    .replace(/\/:/g, '').replace(/:\//g, '')
    .replace(/\(?\s*\d+\s*x\s*\)?/gi, '')
    .replace(/[ \t]+\n/g, '\n').replace(/\n{3,}/g, '\n\n');
  return { repeat, cleaned: cleaned.trim() };
}

// ── Song page → GOAT JSON ────────────────────────────────────────────────────────
function parseSong(html, id, slug) {
  const title = attr(html, 'og:title') ||
    (html.match(/class="wrap-text"[^>]*>([^<]+)/) || [, slug])[1];

  // Metadata block (Autor / Album / Tematica / Versuri / Muzica + bible ref).
  const grab = (label) => {
    const re = new RegExp(`${label}\\s*:?\\s*<a[^>]*href="([^"]*)"[^>]*>\\s*([^<]+?)\\s*<\\/a>`, 'i');
    const m = html.match(re);
    return m ? { href: m[1], text: decodeEntities(m[2]).trim() } : null;
  };
  const autor = grab('Autor');
  const versuri = grab('Versuri');
  const muzica = grab('Muzic[aă]');
  const album = grab('Album');
  const tema = grab('Tematica');

  const refM = html.match(/index-referinta\/([a-z0-9-]+)(?:\/capitol\/(\d+))?/i);
  const addedM = html.match(/Resursa adaugata de\s*<a[^>]*>\s*([^<]+?)\s*<\/a>\s*in\s*<span class="date">\s*([^<]+?)\s*<\/span>/i);

  // Collect raw .strofa blocks. The page renders the whole lyric twice (a
  // print/fullscreen clone), so we de-duplicate the exact double before
  // classifying — robust regardless of the surrounding wrapper markup.
  const blocks = [];
  const re = /<div class="strofa">\s*(?:<div class="strofa-label">(.*?)<\/div>)?\s*<div class="strofa-text">(.*?)<\/div>\s*<\/div>/gs;
  for (const m of html.matchAll(re)) {
    const label = m[1] ? stripTags(m[1]) : '';
    const rawText = m[2].replace(/<br\s*\/?>/gi, '\n').replace(/<[^>]+>/g, '');
    const text = decodeEntities(rawText).replace(/\r/g, '').replace(/[ \t]+\n/g, '\n').trim();
    if (text) blocks.push({ label, text });
  }
  // Fallback: older song pages have no .strofa markup — the lyrics live as plain
  // text in `resized-text` (numbered verses "N." + an "R …" / "Refren" chorus,
  // <br> line breaks, blank line between sections).
  if (blocks.length === 0) {
    const rt = html.match(/class="resized-text"[^>]*>([\s\S]*?)<\/div>/);
    if (rt) {
      // Single <br> = line break; 2+ consecutive <br> = stanza break. Source also
      // has literal newlines between markup, so collapse real whitespace first.
      let h = rt[1]
        .replace(/(?:<br\s*\/?>\s*){2,}/gi, ' @@PP@@ ')
        .replace(/<br\s*\/?>/gi, ' @@NL@@ ')
        .replace(/<[^>]+>/g, '');
      const plain = decodeEntities(h).replace(/[ \t\r\n]+/g, ' ')
        .replace(/\s*@@PP@@\s*/g, '\n\n').replace(/\s*@@NL@@\s*/g, '\n').trim();
      for (const chunk of plain.split(/\n{2,}/)) {
        const c = chunk.trim();
        if (!c) continue;
        const first = c.split('\n')[0].trim();
        let label = '', body = c;
        const numM = first.match(/^(\d+)[.)]\s*/);
        if (numM) { label = `Strofă ${numM[1]}`; body = c.replace(/^\s*\d+[.)]\s*/, ''); }
        else if (/^(refren\b|r\b|r:)/i.test(first)) { label = 'Refren'; body = c.replace(/^\s*(refren|r)\b[:.]?\s*/i, ''); }
        blocks.push({ label, text: body });
      }
    }
  }
  const deduped = dropDoubled(blocks);

  const sections = [];
  const counters = {};
  deduped.forEach((b, order) => {
    const label = b.label || `Strofă ${order + 1}`;
    const { repeat, cleaned } = extractRepeat(b.text);
    const lines = cleaned.split('\n').map(t => ({ text: t.trim() }));
    const { type, key } = classifySection(label, order, counters);
    const section = { id: key, type, label, order, lines };
    if (repeat > 1) section.repeat = repeat;
    sections.push(section);
  });

  const url = `${BASE}/cantece/${id}/${slug}`;
  const themes = tema ? [tema.text] : [];
  const ext = { id, url };
  if (autor?.href) ext.autorSlug = autor.href.split('index-autori/')[1]?.split(/[/"]/)[0] || '';
  if (tema?.href) ext.tematicaSlug = tema.href.split('index-tematic/')[1]?.split(/[/"]/)[0] || '';
  if (refM) ext.referintaBiblica = refM[2] ? `${refM[1]} ${refM[2]}` : refM[1];
  if (addedM) { ext.addedBy = decodeEntities(addedM[1]).trim(); ext.dateAdded = addedM[2].trim(); }

  const notes = refM ? `Referință biblică: ${(refM[1] || '').replace(/-/g, ' ')}${refM[2] ? ` ${refM[2]}` : ''}` : '';

  const version = {
    name: 'Original',
    language: 'ro',
    source: url,
    sections,
    _extensions: { resursecrestine: ext },
  };
  const albumName = album && !/fara album|fără album/i.test(album.text) ? album.text : '';
  if (albumName) version.songbook = { name: albumName };

  const song = {
    title: decodeEntities(String(title)).trim(),
    language: 'ro',
    themes,
    author: autor?.text || '',
    versions: [version],
  };
  if (versuri?.text) song.authorWords = versuri.text;
  if (muzica?.text) song.authorMusic = muzica.text;
  if (notes) song.notes = notes;
  if (albumName) song.songbook = { name: albumName };

  return {
    schemaVersion: '1.0.0',
    format: 'TopPresenter Song',
    exportInfo: { source: 'resursecrestine.ro', exportDate: new Date().toISOString(), exporterVersion: '1.0.0' },
    song,
  };
}

const sanitize = s => s.replace(/[\/\\:?%*|"<>]+/g, '-').slice(0, 110);

// ── Main ─────────────────────────────────────────────────────────────────────────
async function main() {
  const opts = parseArgs(process.argv);
  await mkdir(opts.out, { recursive: true });

  // Resume index: which ids already have a file on disk.
  const existing = new Set();
  if (opts.resume) {
    for (const f of await readdir(opts.out)) {
      const m = f.match(/^(\d+)-/);
      if (m) existing.add(m[1]);
    }
  }

  // Build the work list.
  let songs; // Map<id, slug>
  if (opts.ids) {
    songs = new Map(opts.ids.map(id => [id, 'song']));
    console.error(`Targeting ${songs.size} explicit id(s).`);
  } else {
    console.error('Enumerating catalog via alphabetical index…');
    songs = await enumerateSongs(opts);
    console.error(`Discovered ${songs.size} songs.`);
  }

  const work = [...songs].filter(([id]) => !existing.has(id)).slice(0, opts.limit);
  console.error(`To fetch: ${work.length} (skipping ${songs.size - work.length} already present / over limit).`);

  let done = 0, failed = 0;
  const manifest = [];
  const errors = [];

  // Simple concurrency pool with per-request politeness delay.
  let cursor = 0;
  async function worker() {
    while (cursor < work.length) {
      const [id, slug] = work[cursor++];
      await sleep(opts.delay);
      try {
        const html = await getText(`${BASE}/cantece/${id}/${slug}`, opts);
        if (!html) throw new Error('404 / empty');
        const doc = parseSong(html, id, slug);
        if (!doc.song.versions[0].sections.length) throw new Error('no lyrics (.strofa) found');
        const file = `${id}-${sanitize(slug)}.json`;
        await writeFile(path.join(opts.out, file), JSON.stringify(doc, null, 2), 'utf8');
        if (opts.manifest) manifest.push({ id, title: doc.song.title, url: doc.song.versions[0].source, file });
        done++;
      } catch (err) {
        failed++;
        errors.push(`${id}\t${slug}\t${err.message}`);
      }
      if ((done + failed) % 50 === 0 || (done + failed) === work.length) {
        process.stderr.write(`\r  ${done + failed}/${work.length} (ok ${done}, fail ${failed})   `);
      }
    }
  }
  await Promise.all(Array.from({ length: Math.min(opts.concurrency, work.length || 1) }, worker));
  process.stderr.write('\n');

  if (opts.manifest && manifest.length) {
    await writeFile(path.join(opts.out, '_manifest.json'), JSON.stringify(manifest, null, 2), 'utf8');
  }
  if (errors.length) {
    await writeFile(path.join(opts.out, '_errors.log'), errors.join('\n') + '\n', 'utf8');
  }
  console.error(`Done. Wrote ${done} song file(s) to ${opts.out}. ${failed ? failed + ' failed (see _errors.log).' : ''}`);
  console.error('Import into TopPresenter: Songs → Import → pick this folder (recursive folder import).');
}

main().catch(err => { console.error(err); process.exit(1); });

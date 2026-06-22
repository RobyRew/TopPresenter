#!/usr/bin/env node
//
// worshiptogether-scraper.mjs
// ──────────────────────────────────────────────────────────────────────────────
// Scrapes worshiptogether.com song pages into TopPresenter "TopPresenter Song"
// GOAT JSON — one file per song — organized by language (EN / ES / PT).
//
// The chords/lyrics + all metadata are in the public server HTML (WordPress).
// Chords render as ChordPro segments:
//   <div class="chord-pro-line">
//     <div class="chord-pro-segment">
//       <div class="chord-pro-note">B/D#</div>      ← chord (or &nbsp; = none)
//       <div class="chord-pro-lyric">wash away </div>← lyric after the chord
//     </div> …
//   </div>
// → parsed into TopPresenter sections with positional chords {sym,pos}. Section
// header lines (Intro / Verse 1 / Chorus / Bridge / Tag …) start new sections;
// "REPEAT CHORUS" etc. become arrangement reuse. Rich metadata captured: writers,
// CCLI #, original + recommended keys, BPM, tempo, themes, scripture references.
//
// Enumerate via the per-language sitemaps (sitemap-en/es/pt.xml). Dependency-free
// (Node 18+), resumable.
//
// NOTE: these are copyrighted worship songs — for personal/congregational use,
// and projecting the lyrics still requires your church's CCLI license.
//
// Usage:
//   node worshiptogether-scraper.mjs                       # all langs
//   node worshiptogether-scraper.mjs --langs en --limit 20 # smoke test
//   node worshiptogether-scraper.mjs --print --url /songs/10-000-reasons-bless-the-lord/
//
// Options:
//   --out DIR        output (default ./ExtraAssets/Songs/worshiptogether)
//   --langs a,b      languages: en,es,pt (default all three)
//   --limit N        stop after N new songs (testing)
//   --delay MS       pause between songs (default 250)
//   --concurrency N  parallel fetches (default 3)
//   --retries N      retries per request (default 3)
//   --no-resume      re-download even if the file exists
//   --print          print one song JSON (use with --url), no writes
//   --url PATH       song path for --print
// ──────────────────────────────────────────────────────────────────────────────

import { writeFile, mkdir, readdir } from 'node:fs/promises';
import path from 'node:path';

const BASE = 'https://www.worshiptogether.com';
const UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) TopPresenter-WorshipTogetherScraper/1.0';
const sleep = ms => new Promise(r => setTimeout(r, ms));

function parseArgs(argv) {
  const o = { out: './ExtraAssets/Songs/worshiptogether', langs: ['en', 'es', 'pt'],
    limit: Infinity, delay: 250, concurrency: 3, retries: 3, resume: true, print: false, url: null };
  for (let i = 2; i < argv.length; i++) {
    const a = argv[i], next = () => argv[++i];
    if (a === '--out') o.out = next();
    else if (a === '--langs') o.langs = next().split(',').map(s => s.trim().toLowerCase()).filter(Boolean);
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
    await sleep(500 * (i + 1));
  }
  return null;
}

const NAMED = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ', hellip: '…',
  ndash: '–', mdash: '—', rsquo: '’', lsquo: '‘', rdquo: '”', ldquo: '“', deg: '°' };
function decode(s) {
  return String(s || '')
    .replace(/&#(\d+);/g, (_, n) => String.fromCodePoint(+n))
    .replace(/&#x([0-9a-f]+);/gi, (_, n) => String.fromCodePoint(parseInt(n, 16)))
    .replace(/&([a-z]+);/gi, (m, n) => (n in NAMED ? NAMED[n] : m));
}
const stripTags = s => String(s || '').replace(/<[^>]+>/g, '');
const clean = s => decode(stripTags(s)).replace(/ /g, ' ').replace(/\s+/g, ' ').trim();

// ── ChordPro parsing ────────────────────────────────────────────────────────────
// Section headers — English + Spanish + Portuguese (verso, coro, ponte, …).
const SECTION_RE = /^(intro(?:duc\w+|du\w+)?|verse|verso|chorus|coro|refr[ãa]o|refrain|estribillo|pre[\s-]?(?:chorus|coro|refr\w*)|bridge|puente|ponte|tag|interlude|interludio|instrumental|ending|final|outro|refrain|vamp|turnaround|mod\.?\s*chorus|channel|breakdown|coda)\b/i;
const REPEAT_RE = /^\s*(repeat|repetir|x\d|\d+\s*x\b)/i;
const CHORD_RE = /^[A-G][#b]?(?:m|maj|min|dim|aug|sus|add)?[0-9]*(?:\([^)]*\))?(?:sus[0-9]*)?(?:\/[A-G][#b]?)?$/;
function sectionType(label) {
  const l = label.toLowerCase();
  if (/pre[\s-]?(chorus|coro|refr)/.test(l)) return 'prechorus';
  if (/chorus|coro|refr|estribillo/.test(l)) return 'chorus';
  if (/verse|verso/.test(l)) return 'verse';
  if (/bridge|puente|ponte/.test(l)) return 'bridge';
  if (/intro/.test(l)) return 'intro';
  if (/tag/.test(l)) return 'tag';
  if (/instrumental|interlude|interludio|vamp|turnaround|channel/.test(l)) return 'interlude';
  if (/ending|final|outro|coda/.test(l)) return 'ending';
  return 'verse';
}
const TYPE_PREFIX = { verse: 'v', chorus: 'c', prechorus: 'p', bridge: 'b', intro: 'i', tag: 't', interlude: 'in', ending: 'e' };
function parseChordPro(html) {
  const start = html.indexOf('chord-pro-line');
  if (start < 0) return { sections: [], arrangement: [] };
  const region = html.slice(start - 40);
  const blocks = region.split(/<div class="chord-pro-line">/i).slice(1);
  const sections = [], arrangement = [], counts = {};
  let cur = null;
  const startSection = (type, label) => {
    const p = TYPE_PREFIX[type] || 's';
    counts[p] = (counts[p] || 0) + 1;
    cur = { id: p + counts[p], type, label: label || type, order: sections.length, lines: [] };
    sections.push(cur); arrangement.push(cur.id);
  };
  for (const block of blocks) {
    // A segment has a chord-pro-note and OPTIONALLY a chord-pro-lyric (intro/
    // instrumental lines are note-only). Split per segment so note-only ones count.
    const segs = block.split(/<div class="chord-pro-segment">/i).slice(1).map(p => ({
      note: decode(stripTags((p.match(/<div class="chord-pro-note">([\s\S]*?)<\/div>/i) || [, ''])[1])).replace(/ /g, ' ').trim(),
      lyric: decode(stripTags((p.match(/<div class="chord-pro-lyric">([\s\S]*?)<\/div>/i) || [, ''])[1])).replace(/ /g, ' '),
    })).filter(s => s.note || s.lyric);
    if (!segs.length) continue;
    // Section header: a single segment, no chord, label text.
    if (segs.length === 1 && !segs[0].note) {
      const lab = segs[0].lyric.trim();
      if (!lab) continue;
      if (REPEAT_RE.test(lab)) {
        const rest = lab.replace(/^\s*(repeat|repetir)\s*/i, '').replace(/\b\d+\s*x\b/i, '').trim();
        const want = sectionType(rest || 'chorus');
        const num = (rest.match(/(\d+)/) || [])[1];
        let reuse = num ? sections.find(s => s.id === (TYPE_PREFIX[want] || 's') + num) : null;
        reuse = reuse || [...sections].reverse().find(s => s.type === want) || [...sections].reverse().find(s => s.type === 'chorus');
        if (reuse) arrangement.push(reuse.id);
        cur = null; continue;
      }
      if (SECTION_RE.test(lab)) { startSection(sectionType(lab), lab); continue; }
      // Otherwise treat as a normal one-segment lyric line.
    }
    if (!cur) startSection('verse', 'Verse');
    let text = ''; const chords = [];
    for (const seg of segs) {
      if (seg.note) {
        if (CHORD_RE.test(seg.note)) chords.push({ sym: seg.note, pos: text.length });
        else text += seg.note + (seg.lyric ? ' ' : '');   // instrumental progression token
      }
      text += seg.lyric;
    }
    text = text.replace(/\s+$/g, '');
    if (text.trim() === '' && !chords.length) continue;
    const line = { text }; if (chords.length) line.chords = chords;
    cur.lines.push(line);
  }
  return { sections, arrangement };
}

// ── Metadata ────────────────────────────────────────────────────────────────────
function labelValue(html, label) {
  // "<…>Label:</…> value" — grab the text right after the label up to the next block.
  const re = new RegExp(label + '\\s*:?\\s*</[^>]+>([\\s\\S]{0,400})', 'i');
  const m = html.match(re);
  return m ? m[1] : '';
}
function linkTexts(fragment) {
  return [...fragment.matchAll(/>([^<>]+)<\/a>/gi)].map(m => decode(m[1]).trim()).filter(Boolean);
}
function parseMeta(html) {
  const meta = {};
  const ccli = html.match(/CCLI\s*#?:?\s*(?:<[^>]+>\s*)*([0-9]{4,})/i);
  meta.ccli = ccli ? ccli[1] : '';
  const bpm = html.match(/BPM\s*:?\s*(?:<[^>]+>\s*)*([0-9]{2,3})\b/i);
  meta.bpm = bpm ? bpm[1] : '';
  const tempo = html.match(/Tempo\s*:?\s*(?:<[^>]+>\s*)*([A-Za-z][A-Za-z \-\/]{1,18}?)\s*</i);
  meta.tempo = tempo ? decode(tempo[1]).trim() : '';
  // Scripture references
  const scr = labelValue(html, 'Scripture Reference');
  meta.scripture = clean(scr).split(/\s{2,}|<|\n/)[0].replace(/^[:]\s*/, '').slice(0, 200).trim();
  // Themes + recommended keys are link lists right after their labels.
  const themeFrag = html.slice(html.indexOf('Theme(s)'), html.indexOf('Theme(s)') + 1500);
  meta.themes = [...new Set(linkTexts(themeFrag))].filter(t => !/worship together|search/i.test(t)).slice(0, 12);
  const recFrag = html.slice(html.indexOf('Recommended Key'), html.indexOf('Recommended Key') + 600);
  meta.recommendedKeys = [...new Set(linkTexts(recFrag))].filter(t => /^[A-G][#b]?m?$/.test(t)).slice(0, 8);
  // Original key: the chords container carries it as a data attribute.
  const dok = html.match(/data-original-key="([A-G][#b]?m?)"/i);
  meta.originalKey = dok ? dok[1] : (html.match(/Original Key[^A-G]{0,40}?([A-G][#b]?m?)\b/i) || [, ''])[1];
  // Writers / copyright (best-effort; labels vary).
  meta.writers = clean(labelValue(html, 'Writer\\(s\\)') || labelValue(html, 'Writers') || labelValue(html, 'Author\\(s\\)')).split(/\s{2,}|©|CCLI/)[0].slice(0, 200).trim();
  const cop = html.match(/(©|&copy;|Copyright)\s*([^<]{4,160})/i);
  meta.copyright = cop ? clean(cop[0]).slice(0, 200) : '';
  return meta;
}

// ── Build a TopPresenter Song document ──────────────────────────────────────────
function buildSong(songPath, html, lang) {
  const slug = (songPath.match(SLUG_RE) || [, ''])[1];
  const rawTitle = decode((html.match(/<title>([^<]+)/) || [])[1] || slug).replace(/\s*\|\s*Worship Together.*$/i, '').trim();
  const parts = rawTitle.split(/\s+[-–]\s+/);
  const title = (parts[0] || rawTitle).trim();
  const artists = (parts.slice(1).join(' - ') || '').replace(/\bft\.?\b/gi, 'feat.').trim();
  const { sections, arrangement } = parseChordPro(html);
  const m = parseMeta(html);
  const author = m.writers || artists;

  const wt = { url: `${BASE}${songPath}`, slug, artists };
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
      author, authorMusic: m.writers || '', copyright: m.copyright || '',
      ccliNumber: m.ccli || '',
      themes: m.themes,
      versions: [{ name: '', language: lang, key: m.originalKey || '', tempo: m.bpm || '', arrangement, sections }],
      _extensions: { worshipTogether: wt },
    },
  };
}

// ── Enumeration ─────────────────────────────────────────────────────────────────
// Each language uses its own song path: en /songs/, es /es/canciones/, pt /pt/cancoes/.
const SONG_PATH = { en: '/songs/', es: '/es/canciones/', pt: '/pt/cancoes/' };
const SLUG_RE = /\/(?:songs|canciones|cancoes)\/([a-z0-9-]+)/i;
async function enumerate(lang, retries) {
  const xml = await fetchText(`${BASE}/sitemap-${lang}.xml`, retries);
  if (!xml) return [];
  const base = (SONG_PATH[lang] || '/songs/').replace(/\//g, '\\/');
  const re = new RegExp('<loc>https?:\\/\\/www\\.worshiptogether\\.com(' + base + '[a-z0-9-]+\\/)<\\/loc>', 'gi');
  const seen = new Set(), out = [];
  let m; while ((m = re.exec(xml))) { if (!seen.has(m[1])) { seen.add(m[1]); out.push(m[1]); } }
  return out;
}
const sanitize = n => String(n || '').replace(/[\/\\:?%*|"<>]+/g, '-').replace(/\s+/g, ' ').trim().slice(0, 120);

async function main() {
  const o = parseArgs(process.argv);
  if (o.print && o.url) {
    const html = await fetchText(`${BASE}${o.url}`, o.retries);
    if (!html) { console.error('fetch failed'); process.exit(1); }
    const lang = o.langs[0] || 'en';
    console.log(JSON.stringify(buildSong(o.url, html, lang), null, 2));
    return;
  }
  await mkdir(o.out, { recursive: true });
  let written = 0, skipped = 0, failed = 0, withChords = 0;
  for (const lang of o.langs) {
    if (written >= o.limit) break;
    const dir = path.join(o.out, lang);
    await mkdir(dir, { recursive: true });
    const existing = new Set((await readdir(dir).catch(() => [])).map(f => f.replace(/\.json$/i, '')));
    process.stderr.write(`[${lang}] enumerating… `);
    const songs = await enumerate(lang, o.retries);
    process.stderr.write(`${songs.length} songs\n`);
    const queue = songs.slice();
    async function worker() {
      while (queue.length) {
        if (written >= o.limit) return;
        const sp = queue.shift();
        const slug = (sp.match(SLUG_RE) || [, sp])[1];
        if (o.resume && existing.has(sanitize(slug))) { skipped++; continue; }
        const html = await fetchText(`${BASE}${sp}`, o.retries);
        if (!html) { failed++; await sleep(o.delay); continue; }
        let doc; try { doc = buildSong(sp, html, lang); } catch (e) { failed++; process.stderr.write(`✗ ${slug}: ${e.message}\n`); continue; }
        if (!doc.song.versions[0].sections.length) { failed++; process.stderr.write(`✗ ${slug} (no chords/sections)\n`); await sleep(o.delay); continue; }
        const base = sanitize(slug);
        try {
          await writeFile(path.join(dir, `${base}.json`), JSON.stringify(doc, null, 2), 'utf8');
          written++; existing.add(base);
          if (doc.song.versions[0].sections.some(s => s.lines.some(l => l.chords?.length))) withChords++;
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

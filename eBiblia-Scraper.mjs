#!/usr/bin/env node
//
// eBiblia-Scraper.mjs
// ──────────────────────────────────────────────────────────────────────────────
// Node port of eBiblia-Scraper.user.js — exports Bible translations from
// eBiblia.ro to TopPresenter's GOAT "TopPresenter Bible" JSON (one file per
// translation), WITHOUT a browser.
//
// It uses eBiblia's public API endpoints directly (the same ones the userscript
// falls back to): verse data via `range/eb<ns>:BB:CCC:001/…:999`, metadata via
// `get/ebart:…`. The verse parsers (red-letter / Strong's / interlinear / refs)
// are ported verbatim from the userscript; only the handful of DOM helpers are
// reimplemented with regex.
//
// The catalog (which translations exist) lives in the page's JS app, so here you
// pass codes explicitly with --codes; --all uses a sensible default list.
//
// Usage:
//   node eBiblia-Scraper.mjs --codes vdcc                 # one translation (EDC100)
//   node eBiblia-Scraper.mjs --codes vdcc,ntr,kjv --out ./bibles
//   node eBiblia-Scraper.mjs --all                        # default fallback list
//   node eBiblia-Scraper.mjs --codes vdcc --books 1-5     # smoke-test a few books
//
// Options:
//   --codes a,b,c     translation codes to export (eBiblia internal codes)
//   --all             export the built-in fallback list
//   --books A-B       book range (default 1-66; >66 = Orthodox deuterocanon discovery)
//   --out DIR         output folder (default ./TopPresenter-Bibles), language-foldered
//   --delay MS        pause between chapter fetches (default 60)
//   --no-meta         skip the about/foreword metadata fetch
//   --no-resume       re-export even if the file already exists
// ──────────────────────────────────────────────────────────────────────────────

import { writeFile, mkdir, readdir } from 'node:fs/promises';
import path from 'node:path';

// ── CONFIG ──────────────────────────────────────────────────────────────────────
const CONFIG = {
  endpoints: ['a1.ebiblia.net', 'a2.ebiblia.net', 'a3.ebiblia.net'],
  proto: 'https://', pathPrefix: '/',
  maxRetries: 3, retryDelay: 800, delay: 60,
};
const FALLBACK_CODES = ['vdcc', 'edcr', 'ntr', 'vdc', 'vdcl', 'kjv', 'niv', 'web', 'esv'];
const sleep = ms => new Promise(r => setTimeout(r, ms));

// ── Tables (verbatim from the userscript) ─────────────────────────────────────────
const CHAPTERS = [
  50, 40, 27, 36, 34, 24, 21, 4, 31, 24, 22, 25, 29, 36, 10, 13, 10, 42, 150,
  31, 12, 8, 66, 52, 5, 48, 12, 14, 3, 9, 1, 4, 7, 3, 3, 3, 2, 14, 4, 28, 16,
  24, 21, 28, 16, 16, 13, 6, 6, 4, 4, 5, 3, 6, 4, 3, 1, 13, 5, 5, 3, 5, 1, 1,
  1, 22,
];
const chaptersFor = b => CHAPTERS[b - 1] || null;
const BOOKS_RO = [
  'Geneza', 'Exodul', 'Leviticul', 'Numeri', 'Deuteronomul', 'Iosua', 'Judecătorii', 'Rut',
  '1 Samuel', '2 Samuel', '1 Împărați', '2 Împărați', '1 Cronici', '2 Cronici', 'Ezra', 'Neemia',
  'Estera', 'Iov', 'Psalmii', 'Proverbele', 'Eclesiastul', 'Cântarea Cântărilor', 'Isaia', 'Ieremia',
  'Plângerile', 'Ezechiel', 'Daniel', 'Osea', 'Ioel', 'Amos', 'Obadia', 'Iona', 'Mica', 'Naum',
  'Habacuc', 'Țefania', 'Hagai', 'Zaharia', 'Maleahi', 'Matei', 'Marcu', 'Luca', 'Ioan',
  'Faptele Apostolilor', 'Romani', '1 Corinteni', '2 Corinteni', 'Galateni', 'Efeseni', 'Filipeni',
  'Coloseni', '1 Tesaloniceni', '2 Tesaloniceni', '1 Timotei', '2 Timotei', 'Tit', 'Filimon', 'Evrei',
  'Iacov', '1 Petru', '2 Petru', '1 Ioan', '2 Ioan', '3 Ioan', 'Iuda', 'Apocalipsa',
];
const SBOOKS_RO = [
  'Gen', 'Exod', 'Lev', 'Num', 'Deut', 'Ios', 'Jud', 'Rut', '1Sam', '2Sam', '1Împ', '2Împ',
  '1Cron', '2Cron', 'Ezr', 'Neem', 'Est', 'Iov', 'Ps', 'Prov', 'Ecl', 'Cânt', 'Isa', 'Ier',
  'Plg', 'Ezec', 'Dan', 'Osea', 'Ioel', 'Amos', 'Oba', 'Iona', 'Mica', 'Naum', 'Hab', 'Țef',
  'Hag', 'Zah', 'Mal', 'Mat', 'Mar', 'Luca', 'Ioan', 'Fapt', 'Rom', '1Cor', '2Cor', 'Gal',
  'Efes', 'Fil', 'Col', '1Tes', '2Tes', '1Tim', '2Tim', 'Tit', 'Flm', 'Evr', 'Iac', '1Pet',
  '2Pet', '1In', '2In', '3In', 'Iuda', 'Apoc',
];
const BOOKS_EN = [
  'Genesis', 'Exodus', 'Leviticus', 'Numbers', 'Deuteronomy', 'Joshua', 'Judges', 'Ruth',
  '1 Samuel', '2 Samuel', '1 Kings', '2 Kings', '1 Chronicles', '2 Chronicles', 'Ezra', 'Nehemiah',
  'Esther', 'Job', 'Psalms', 'Proverbs', 'Ecclesiastes', 'Song of Solomon', 'Isaiah', 'Jeremiah',
  'Lamentations', 'Ezekiel', 'Daniel', 'Hosea', 'Joel', 'Amos', 'Obadiah', 'Jonah', 'Micah', 'Nahum',
  'Habakkuk', 'Zephaniah', 'Haggai', 'Zechariah', 'Malachi', 'Matthew', 'Mark', 'Luke', 'John',
  'Acts', 'Romans', '1 Corinthians', '2 Corinthians', 'Galatians', 'Ephesians', 'Philippians',
  'Colossians', '1 Thessalonians', '2 Thessalonians', '1 Timothy', '2 Timothy', 'Titus', 'Philemon',
  'Hebrews', 'James', '1 Peter', '2 Peter', '1 John', '2 John', '3 John', 'Jude', 'Revelation',
];
const SBOOKS_EN = [
  'Gen', 'Exod', 'Lev', 'Num', 'Deut', 'Josh', 'Judg', 'Ruth', '1Sam', '2Sam', '1Kngs', '2Kngs',
  '1Chr', '2Chr', 'Ezra', 'Neh', 'Est', 'Job', 'Ps', 'Prov', 'Eccl', 'Song', 'Isa', 'Jer', 'Lam',
  'Ezk', 'Dan', 'Hos', 'Joel', 'Amos', 'Oba', 'Jona', 'Mic', 'Nah', 'Hab', 'Zeph', 'Hag', 'Zech',
  'Mal', 'Mat', 'Mk', 'Lk', 'Jn', 'Acts', 'Rom', '1Cor', '2Cor', 'Gal', 'Eph', 'Phil', 'Col',
  '1Thes', '2Thes', '1Tim', '2Tim', 'Tit', 'Phmon', 'Heb', 'James', '1Pet', '2Pet', '1Jn', '2Jn',
  '3Jn', 'Jude', 'Rev',
];
const CODE_MAP = { vdcc: 'EDC100' };
const LANG_FOLDERS = {
  ro: 'Romana', en: 'English', de: 'Deutsch', fr: 'Francais', es: 'Espanol', it: 'Italiano',
  hu: 'Magyar', ru: 'Russian', gr: 'Greek', ebr: 'Hebrew', lat: 'Latin', ukr: 'Ukrainian',
  nl: 'Nederlands', pg: 'Portugues', arab: 'Arabic', sb: 'Srpski', roma: 'Romani',
};
const LANG_NAMES = { ro: 'Română', en: 'English', de: 'Deutsch', fr: 'Français', es: 'Español', it: 'Italiano', hu: 'Magyar', ru: 'Русский' };

const mapTranslationCode = c => CODE_MAP[(c || '').toLowerCase()] || (c || '').toUpperCase();

// ── DOM-free HTML helpers (regex replacements for the userscript's DOM bits) ──────
function decodeEntities(s) {
  if (!s || s.indexOf('&') < 0) return s || '';
  const named = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ', hellip: '…', ndash: '–', mdash: '—', rsquo: '’', lsquo: '‘', rdquo: '”', ldquo: '“', laquo: '«', raquo: '»', acirc: 'â', Acirc: 'Â', icirc: 'î', Icirc: 'Î' };
  return s
    .replace(/&#(\d+);/g, (_, n) => String.fromCodePoint(+n))
    .replace(/&#x([0-9a-f]+);/gi, (_, n) => String.fromCodePoint(parseInt(n, 16)))
    .replace(/&([a-z]+);/gi, (m, n) => (n in named ? named[n] : m));
}
// Remove whole elements (open→close) by bare tag name and/or by class (single OR double quotes).
function removeElements(html, bareTags, classNames) {
  let out = html;
  if (bareTags && bareTags.length) {
    const re = new RegExp('<(' + bareTags.join('|') + ')\\b[^>]*>[\\s\\S]*?<\\/\\1>', 'gi');
    let prev; do { prev = out; out = out.replace(re, ''); } while (out !== prev);
    // self-closing / unclosed variants of those bare tags
    out = out.replace(new RegExp('<\\/?(' + bareTags.join('|') + ')\\b[^>]*>', 'gi'), '');
  }
  if (classNames && classNames.length) {
    const cls = classNames.join('|');
    const re = new RegExp('<(\\w+)\\b[^>]*\\bclass=["\'][^"\']*\\b(?:' + cls + ')\\b[^"\']*["\'][^>]*>[\\s\\S]*?<\\/\\1>', 'gi');
    let prev; do { prev = out; out = out.replace(re, ''); } while (out !== prev);
  }
  return out;
}
const stripTags = s => decodeEntities(String(s || '').replace(/<[^>]+>/g, ''));
function htmlToText(html) {
  if (!html) return '';
  return decodeEntities(String(html).replace(/<[^>]+>/g, '')).replace(/\s+/g, ' ').trim();
}
function articleToText(html) {
  if (!html) return '';
  const t = decodeEntities(
    String(html).replace(/<br\s*\/?>/gi, '\n').replace(/<\/(p|div|li|h[1-6]|blockquote|tr|section)>/gi, '\n').replace(/<[^>]+>/g, '')
  );
  return t.replace(/[ \t ]+/g, ' ').replace(/[ \t]*\n[ \t]*/g, '\n').replace(/\n{3,}/g, '\n\n').trim();
}
function extractForeword(html) {
  if (!html) return '';
  return articleToText(String(html).replace(/<blockquote[\s\S]*?<\/blockquote>/i, ''));
}
function extractYear(text) {
  if (!text) return null;
  const paren = String(text).match(/\((1\d{3}|20\d{2})\)/);
  if (paren) return parseInt(paren[1], 10);
  const all = String(text).match(/\b(1\d{3}|20\d{2})\b/g);
  return all && all.length ? parseInt(all[all.length - 1], 10) : null;
}
function parseAboutArticle(html) {
  const out = { abbreviation: '', description: '', copyright: '', languageName: '', source: '' };
  if (!html) return out;
  let s = String(html).replace(/<br\s*\/?>/gi, '\n').replace(/<\/(p|div|li|h\d)>/gi, '\n');
  const bq = s.match(/<blockquote[^>]*>([\s\S]*?)<\/blockquote>/i);
  const text = decodeEntities((bq ? bq[1] : s).replace(/<[^>]+>/g, ''));
  const stop = '(?:Prescurtare|Descriere|Copyright|Limba|Surs[\\u0103a](?:\\s*text)?)\\s*:';
  const grab = label => {
    const re = new RegExp(label + '\\s*:\\s*([\\s\\S]*?)(?=' + stop + '|$)', 'i');
    const m = text.match(re);
    return m && m[1] ? m[1].replace(/\s+/g, ' ').trim() : '';
  };
  out.abbreviation = grab('Prescurtare');
  out.description = grab('Descriere');
  out.copyright = grab('Copyright');
  out.languageName = grab('Limba');
  out.source = grab('Surs[\\u0103a]\\s*text') || grab('Surs[\\u0103a]');
  return out;
}

// ── Verse parsing (ported verbatim — pure string logic) ───────────────────────────
const isValidVerseKey = key => { const m = key.match(/^(\d{2}):(\d{3}):(\d{3})$/); if (!m) return false; const v = parseInt(m[3], 10); return v >= 1 && v <= 200; };
const getVerseNumber = key => parseInt(key.split(':')[2], 10);
const parseRefKey = key => { const m = key.match(/^(\d{2}:\d{3}:\d{3}):(xt|x|f|t)(\d+)$/); return m ? { verseKey: m[1], type: m[2], index: parseInt(m[3], 10) } : null; };

function cleanVerseText(html) {
  if (!html) return '';
  let s = html.replace(/<br\s*\/?>/gi, '');
  s = removeElements(s, ['sr', 'mf', 'script'], ['sr', 'xSym', 'fSym', 'x', 'f', 'cmp1', 'cmp2', 'cmp3', 'tp', 'noCopy']);
  let text = decodeEntities(s.replace(/<[^>]+>/g, ''));
  text = text.replace(/[*%^]/g, '').replace(/[ \t\r\n]+/g, ' ');
  text = text.replace(/\s*\s*/g, '\n').replace(/\n{2,}/g, '\n');
  text = text.replace(/\s+([,.;:!?»””»])/g, '$1');
  return text.trim();
}

const RICH_NOISE_TAGS = ['script', 'sup'];
const RICH_NOISE_CLASSES = ['xSym', 'fSym', 'x', 'f', 'cmp1', 'cmp2', 'cmp3', 'tp', 'noCopy'];
function tidyRich(t) {
  return t.replace(/[*%^]/g, '').replace(/[ \t]+/g, ' ').replace(/ *\n */g, '\n').replace(/\n{2,}/g, '\n').replace(/[ \t]+([,.;:!?»”»])/g, '$1').trim();
}
function tagInner(block, name) {
  const m = block.match(new RegExp('<' + name + '\\b[^>]*>([\\s\\S]*?)<\\/' + name + '>', 'i'));
  return m ? decodeEntities(m[1].replace(/<[^>]+>/g, '')) : '';
}
function parseInterlinear(cleanHtml) {
  const runs = [], words = [], glosses = []; let anySr = false, anyGloss = false;
  const re = /<i\b[^>]*>([\s\S]*?)<\/i>/gi; let m;
  while ((m = re.exec(cleanHtml))) {
    const b = m[1];
    const wd = tagInner(b, 'wd').replace(/\s+/g, ' ').trim();
    const sr = tagInner(b, 'sr').trim(), mf = tagInner(b, 'mf').trim(), en = tagInner(b, 'en').trim();
    if (!wd && !en) continue;
    const run = { text: wd };
    if (sr) { run.strong = sr; anySr = true; }
    if (mf) run.morph = mf;
    if (en) { run.gloss = en.replace(/\s+/g, ' ').trim(); anyGloss = true; }
    runs.push(run);
    if (wd) words.push(wd);
    if (en) glosses.push(en.trim());
  }
  return { text: tidyRich(words.join(' ')), runs, gloss: anyGloss ? tidyRich(glosses.join(' ')) : '', hasStrong: anySr, hasWoc: false, mode: 'interlinear' };
}
function parseInline(cleanHtml) {
  const toks = cleanHtml.split(/(<[^>]+>)/);
  const runs = []; let woc = 0, add = 0, cap = null, strongBuf = '';
  function pushText(t) {
    if (!t) return;
    const kind = woc > 0 ? 'woc' : (add > 0 ? 'add' : 'plain');
    const last = runs[runs.length - 1];
    if (last && (last.kind || 'plain') === kind && !last.strong) last.text += t;
    else runs.push({ text: t, kind });
  }
  for (let i = 0; i < toks.length; i++) {
    const tk = toks[i];
    if (i % 2 === 1) {
      const tl = tk.toLowerCase();
      if (/^<sr\b/.test(tl)) { cap = 'sr'; strongBuf = ''; }
      else if (/^<\/sr>/.test(tl)) {
        const s = strongBuf.trim(); cap = null;
        if (s) {
          const last = runs[runs.length - 1];
          if (last && !last.strong) {
            const mm = last.text.match(/(\s*)(\S+)\s*$/);
            if (mm) { const pre = last.text.slice(0, last.text.length - mm[0].length); if (pre) runs[runs.length - 1].text = pre; else runs.pop(); runs.push({ text: mm[1] + mm[2], kind: last.kind, strong: s }); }
            else last.strong = s;
          }
        }
      }
      else if (/^<em\b/.test(tl) || /^<i\b/.test(tl)) add++;
      else if (/^<\/em>/.test(tl) || /^<\/i>/.test(tl)) { if (add > 0) add--; }
      else if (/^<span\b/.test(tl) && /isus/i.test(tl)) woc++;
      else if (/^<\/span>/.test(tl)) { if (woc > 0) woc--; }
    } else {
      if (cap === 'sr') { strongBuf += tk; continue; }
      pushText(decodeEntities(tk));
    }
  }
  let anySr = false;
  runs.forEach(r => { r.text = r.text.replace(/[*%^]/g, '').replace(/[ \t]+/g, ' '); if (r.strong) anySr = true; });
  const merged = [];
  runs.forEach(r => { if (!r.text) return; const l = merged[merged.length - 1]; if (l && (l.kind || 'plain') === (r.kind || 'plain') && !l.strong && !r.strong) l.text += r.text; else merged.push(r); });
  const text = tidyRich(merged.map(r => r.text).join(''));
  const hasWoc = merged.some(r => r.kind === 'woc');
  merged.forEach(r => { if (r.kind === 'plain') delete r.kind; });
  return { text, runs: merged, gloss: '', hasStrong: anySr, hasWoc, mode: 'inline' };
}
function runsWocOnly(runs) {
  const merged = [];
  for (const r0 of runs) {
    const k = r0.kind || 'plain';
    const last = merged[merged.length - 1];
    if (last && (last.kind || 'plain') === k) last.text += r0.text;
    else merged.push({ text: r0.text, kind: r0.kind });
  }
  merged.forEach(r => { if (!r.kind) delete r.kind; });
  return merged;
}
function parseRichVerse(html) {
  if (!html) return { text: '', runs: [], gloss: '', hasStrong: false, hasWoc: false, mode: 'inline' };
  let clean = html.replace(/<br\s*\/?>/gi, '\n');
  clean = removeElements(clean, RICH_NOISE_TAGS, RICH_NOISE_CLASSES);
  return /<wd\b/i.test(clean) ? parseInterlinear(clean) : parseInline(clean);
}

// ── References (verbatim) ─────────────────────────────────────────────────────────
function classifyTitleLevel(text) {
  if (text.charAt(0) === '(' && text.charAt(text.length - 1) === ')') return 0;
  if (/^CAPITOLELE?\b/i.test(text)) return 2;
  if (text === text.toUpperCase() && text.length > 3 && /[A-ZÀ-Ž]/.test(text)) return 1;
  return 3;
}
function extractReferences(refEntries) {
  const result = { crossReferences: [], footnotes: [], titles: [] };
  if (!refEntries || !refEntries.length) return result;
  for (const entry of refEntries) {
    if (!entry || !entry.value || typeof entry.value !== 'string') continue;
    const raw = entry.value.trim();
    if (!raw) continue;
    if (entry.type === 'x' || entry.type === 'xt') {
      const refs = [];
      for (const part0 of raw.split(';')) {
        const part = part0.trim(); if (!part) continue;
        const segs = part.split(':');
        if (segs.length >= 2) { const bookIdx = parseInt(segs[0], 10); const bookName = SBOOKS_RO[bookIdx - 1] || ('Book ' + bookIdx); segs.shift(); refs.push(bookName + ' ' + segs.join(':')); }
        else refs.push(part);
      }
      if (refs.length) result.crossReferences.push({ targets: refs });
    } else if (entry.type === 'f') {
      const noteClean = raw.replace(/<[^>]*>/g, '').replace(/\s+/g, ' ').trim();
      if (noteClean) result.footnotes.push({ text: decodeEntities(noteClean) });
    } else if (entry.type === 't') {
      const titleText = raw.replace(/<[^>]*>/g, '').replace(/\s+/g, ' ').trim();
      if (titleText) result.titles.push({ text: decodeEntities(titleText), level: classifyTitleLevel(titleText) });
    }
  }
  return result;
}
function parseVerseData(data) {
  if (!data || typeof data !== 'object') return [];
  const verses = [], keys = Object.keys(data), refsByVerse = {};
  for (const rkey of keys) {
    if (rkey.charAt(0) === '_') continue;
    const refInfo = parseRefKey(rkey); if (!refInfo) continue;
    const refValue = data[rkey]; if (!refValue || typeof refValue !== 'string') continue;
    (refsByVerse[refInfo.verseKey] = refsByVerse[refInfo.verseKey] || []).push({ type: refInfo.type, index: refInfo.index, value: refValue });
  }
  for (const key of keys) {
    if (key.charAt(0) === '_' || !isValidVerseKey(key)) continue;
    const rawText = data[key];
    if (!rawText || typeof rawText !== 'string' || rawText.length < 2) continue;
    const cleanText = cleanVerseText(rawText);
    if (!cleanText) continue;
    verses.push({ number: getVerseNumber(key), text: cleanText, _rawHtml: rawText, _refEntries: refsByVerse[key] || [] });
  }
  verses.sort((a, b) => a.number - b.number);
  return verses;
}

// ── Network (Node fetch — the userscript's API fallback path) ──────────────────────
async function fetchFromAPI(p, retries = CONFIG.maxRetries) {
  let attempt = 0;
  while (attempt < retries) {
    const endpoint = CONFIG.endpoints[attempt % CONFIG.endpoints.length];
    const url = CONFIG.proto + endpoint + CONFIG.pathPrefix + p;
    attempt++;
    try {
      const res = await fetch(url);
      if (res.ok) { const text = await res.text(); try { return JSON.parse(text); } catch { return text; } }
      await sleep(CONFIG.retryDelay);
    } catch {
      if (attempt >= retries) throw new Error('fetch failed: ' + p);
      await sleep(CONFIG.retryDelay);
    }
  }
  throw new Error('Failed to fetch ' + p);
}
async function getArticle(key) {
  try {
    const r = await fetchFromAPI('get/' + encodeURIComponent(key), 1);
    if (r == null) return null;
    if (typeof r === 'string') return r;
    if (typeof r === 'object') return r[key] != null ? String(r[key]) : null;
    return String(r);
  } catch { return null; }
}
async function fetchTranslationMeta(code) {
  const lc = (code || '').toLowerCase();
  try {
    const [t, b] = await Promise.all([getArticle('ebart:b:t:' + lc), getArticle('ebart:b:' + lc)]);
    const fullName = htmlToText(t);
    const about = parseAboutArticle(b);
    return {
      fullName: fullName || '', description: about.description || '', copyright: about.copyright || '',
      languageName: about.languageName || '', source: about.source || '', abbreviation: about.abbreviation || '',
      year: extractYear(fullName) || extractYear(about.copyright) || extractYear(about.description) || null,
      foreword: extractForeword(b),
    };
  } catch { return null; }
}
const pad2 = n => String(n).padStart(2, '0');
const pad3 = n => String(n).padStart(3, '0');
async function fetchChapter(namespace, book, chapter) {
  const bookChap = pad2(book) + ':' + pad3(chapter);
  const [verseData, resData] = await Promise.all([
    fetchFromAPI('range/eb' + namespace + ':' + bookChap + ':001/' + bookChap + ':999').catch(() => ({})),
    fetchFromAPI('range/eb' + namespace + '-res:' + bookChap + ':*/').catch(() => ({})),
  ]);
  const merged = {};
  if (verseData && typeof verseData === 'object') for (const k of Object.keys(verseData)) merged[k] = verseData[k];
  if (resData && typeof resData === 'object') for (const k of Object.keys(resData)) merged[k] = resData[k];
  return parseVerseData(merged);
}

// ── JSON assembly ─────────────────────────────────────────────────────────────────
function createBibleJSON(code, m) {
  return {
    schemaVersion: '1.0.0', format: 'TopPresenter Bible',
    translation: {
      code: mapTranslationCode(code), name: m.name || mapTranslationCode(code), nameLocal: m.nameLocal || '',
      language: m.language || 'ro', languageName: m.languageName || '', copyright: m.copyright || '',
      description: m.description || '', about: m.about || '', source: m.source || '', year: m.year || null,
      direction: m.direction || 'ltr', versification: m.versification || null, canon: m.canon || null,
      incomplete: m.incomplete || false, hasWordsOfChrist: false, hasStrongs: false,
    },
    exportInfo: { source: 'eBiblia.ro', exportDate: new Date().toISOString(), exporterVersion: '1.0.0', totalBooks: 0, totalChapters: 0, totalVerses: 0 },
    books: [], _extensions: {},
  };
}
function createBookJSON(bookNumber, chapterCount) {
  const idx = bookNumber - 1;
  return {
    number: bookNumber, name: BOOKS_RO[idx] || ('Cartea ' + bookNumber), nameEnglish: BOOKS_EN[idx] || ('Book ' + bookNumber),
    abbreviation: SBOOKS_RO[idx] || ('C' + bookNumber), abbreviationEnglish: SBOOKS_EN[idx] || ('B' + bookNumber),
    testament: bookNumber <= 39 ? 'OT' : (bookNumber <= 66 ? 'NT' : 'DC'), expectedChapters: chapterCount, chapters: [], _extensions: {},
  };
}
function buildVerseObject(v, state, headingsOut) {
  const verse = { number: v.number, text: v.text };
  if (v._rawHtml) {
    const rich = parseRichVerse(v._rawHtml);
    if (rich.mode === 'interlinear') verse.text = rich.text;
    if (rich.hasStrong || rich.hasWoc) {
      verse.text = rich.text;
      verse.runs = rich.hasStrong ? rich.runs : runsWocOnly(rich.runs);
      if (rich.hasWoc) { verse.hasWordsOfChrist = true; state.hasWoc = true; }
      if (rich.hasStrong) { state.hasStrong = true; if (rich.gloss) verse.gloss = rich.gloss; }
    }
  }
  if (v._refEntries && v._refEntries.length) {
    const refs = extractReferences(v._refEntries);
    if (refs.crossReferences.length) verse.crossReferences = refs.crossReferences;
    if (refs.footnotes.length) verse.footnotes = refs.footnotes;
    if (headingsOut) for (const t of refs.titles) headingsOut.push({ beforeVerse: v.number, level: t.level, text: t.text });
  }
  return verse;
}

// ── Driver ────────────────────────────────────────────────────────────────────────
async function exportTranslation(code, opts) {
  const displayName = code.toLowerCase() === 'vdcc' ? 'EDC100 (VDCC)' : mapTranslationCode(code);
  let meta = null;
  if (opts.meta) { process.stderr.write(`  · ${displayName}: metadate…\n`); meta = await fetchTranslationMeta(code); }
  const fullName = (meta && meta.fullName) || displayName;
  const lang = 'ro';
  const state = { hasWoc: false, hasStrong: false };
  const bible = createBibleJSON(code, {
    name: fullName, nameLocal: fullName, language: lang, languageName: (meta && meta.languageName) || LANG_NAMES[lang] || lang,
    copyright: (meta && meta.copyright) || '', description: (meta && meta.description) || '', about: (meta && meta.foreword) || '',
    source: (meta && meta.source) || '', year: (meta && meta.year) || null, canon: opts.bookEnd > 66 ? 'orthodox' : null,
  });

  let totalVerses = 0;
  for (let bookNum = opts.bookStart; bookNum <= opts.bookEnd; bookNum++) {
    const known = chaptersFor(bookNum);
    const discovery = !known;
    const numChapters = known || 99;
    let consecutiveEmpty = 0;
    const bookData = createBookJSON(bookNum, known || 0);
    const bookName = BOOKS_RO[bookNum - 1] || ('Cartea ' + bookNum);

    // Probe chapters 1–2; both empty ⇒ book absent in this translation.
    let probeOK = false;
    for (let pc = 1; pc <= Math.min(2, numChapters) && !probeOK; pc++) {
      try { if ((await fetchChapter(code, bookNum, pc)).length) probeOK = true; } catch { /* empty */ }
      if (!probeOK) await sleep(CONFIG.delay);
    }
    if (!probeOK) { process.stderr.write(`    ↷ ${bookNum}. ${bookName} — indisponibilă, omisă\n`); continue; }

    for (let chap = 1; chap <= numChapters; chap++) {
      let verses = [];
      const maxAttempts = discovery ? 1 : CONFIG.maxRetries;
      for (let attempt = 0; attempt < maxAttempts && !verses.length; attempt++) {
        try { verses = await fetchChapter(code, bookNum, chap); } catch { /* retry */ }
        if (!verses.length && attempt + 1 < maxAttempts) await sleep(CONFIG.retryDelay);
      }
      if (!verses.length) {
        if (discovery && ++consecutiveEmpty >= 2) break;
        if (!discovery) process.stderr.write(`    ❌ ${bookName} ${chap}: 0 versete\n`);
        await sleep(CONFIG.delay);
        continue;
      }
      consecutiveEmpty = 0;
      const headings = [];
      const chapterVerses = verses.map(v => buildVerseObject(v, state, headings));
      const chapterObj = { number: chap, verses: chapterVerses, _extensions: {} };
      if (headings.length) chapterObj.headings = headings;
      bookData.chapters.push(chapterObj);
      totalVerses += chapterVerses.length;
      await sleep(CONFIG.delay);
    }
    if (bookData.chapters.length) {
      bible.books.push(bookData);
      process.stderr.write(`    📖 ${bookNum}. ${bookName} — ${bookData.chapters.length} cap.\n`);
    }
  }

  bible.translation.hasWordsOfChrist = state.hasWoc;
  bible.translation.hasStrongs = state.hasStrong;
  bible.exportInfo.totalBooks = bible.books.length;
  bible.exportInfo.totalChapters = bible.books.reduce((a, b) => a + b.chapters.length, 0);
  bible.exportInfo.totalVerses = totalVerses;
  return bible;
}

function bibleFilename(bible) {
  const code = (bible.translation.code || 'bible').replace(/[^\w-]/g, '');
  const name = (bible.translation.name || '').replace(/[\/\\:*?"<>|]/g, ' ').replace(/\s+/g, ' ').trim();
  let base = name && name.toUpperCase() !== code.toUpperCase() ? `${code} — ${name}` : code;
  if (base.length > 120) base = base.slice(0, 120).trim();
  return base + '.json';
}

// ── CLI ─────────────────────────────────────────────────────────────────────────
function parseArgs(argv) {
  const o = { codes: null, all: false, out: './TopPresenter-Bibles', delay: CONFIG.delay, meta: true, resume: true, bookStart: 1, bookEnd: 66 };
  for (let i = 2; i < argv.length; i++) {
    const a = argv[i], next = () => argv[++i];
    if (a === '--codes') o.codes = next().split(',').map(s => s.trim()).filter(Boolean);
    else if (a === '--all') o.all = true;
    else if (a === '--out') o.out = next();
    else if (a === '--delay') o.delay = +next();
    else if (a === '--no-meta') o.meta = false;
    else if (a === '--no-resume') o.resume = false;
    else if (a === '--books') { const m = next().split('-'); o.bookStart = +m[0] || 1; o.bookEnd = +(m[1] || m[0]) || 66; }
    else if (a === '-h' || a === '--help') { console.log('See header of this file for usage.'); process.exit(0); }
    else { console.error('Unknown option: ' + a); process.exit(1); }
  }
  return o;
}

async function main() {
  const opts = parseArgs(process.argv);
  CONFIG.delay = opts.delay;
  const codes = opts.codes || (opts.all ? FALLBACK_CODES : null);
  if (!codes || !codes.length) { console.error('Specify --codes a,b,c (or --all). eBiblia codes, e.g. vdcc, ntr, kjv.'); process.exit(1); }
  await mkdir(opts.out, { recursive: true });

  for (const code of codes) {
    process.stderr.write(`\n═══ ${mapTranslationCode(code)} (${code}) ═══\n`);
    try {
      const bible = await exportTranslation(code, opts);
      if (!bible.books.length) { console.error(`  (no books for ${code})`); continue; }
      const folder = path.join(opts.out, LANG_FOLDERS[bible.translation.language] || (bible.translation.language || 'xx').toUpperCase());
      await mkdir(folder, { recursive: true });
      const file = path.join(folder, bibleFilename(bible));
      if (opts.resume) { try { const have = await readdir(folder); if (have.includes(path.basename(file))) { console.error(`  ✓ exists, skipping ${path.basename(file)}`); continue; } } catch {} }
      await writeFile(file, JSON.stringify(bible, null, 2), 'utf8');
      console.error(`  ✅ ${path.basename(file)} — ${bible.exportInfo.totalBooks} books, ${bible.exportInfo.totalVerses} verses` +
        (bible.translation.hasWordsOfChrist ? ' · red-letter' : '') + (bible.translation.hasStrongs ? ' · Strong\'s' : ''));
    } catch (err) { console.error(`  ❌ ${code}: ${err.message}`); }
  }
}

main().catch(err => { console.error(err); process.exit(1); });

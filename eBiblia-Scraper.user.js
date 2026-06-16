// ==UserScript==
// @name         eBiblia Bible Exporter
// @namespace    https://ebiblia.ro
// @version      1.15.0
// @description  Export Bible translations from eBiblia.ro to TopPresenter's GOAT JSON — red-letter (words of Christ), headings, cross-refs, footnotes, full metadata + foreword, Strong's/morphology/interlinear glosses
// @author       TopPresenter
// @match        https://ebiblia.ro/*
// @match        https://ebiblia.app/*
// @grant        unsafeWindow
// @grant        GM_download
// @grant        GM_setClipboard
// @run-at       document-idle
// ==/UserScript==

(function () {
    'use strict';

    // ═══════════════════════════════════════════════════════════════
    // CONFIGURATION
    // ═══════════════════════════════════════════════════════════════

    const CONFIG = {
        chapterDelay: 50,
        bookDelay: 400,
        maxRetries: 3,
        retryDelay: 800,
        endpoints: ['a1.ebiblia.net', 'a2.ebiblia.net', 'a3.ebiblia.net'],
        proto: 'https://',
        pathPrefix: '/',
    };

    const CHAPTERS = [
        50, 40, 27, 36, 34, 24, 21, 4, 31, 24, 22, 25, 29, 36, 10, 13, 10, 42, 150,
        31, 12, 8, 66, 52, 5, 48, 12, 14, 3, 9, 1, 4, 7, 3, 3, 3, 2, 14, 4, 28, 16,
        24, 21, 28, 16, 16, 13, 6, 6, 4, 4, 5, 3, 6, 4, 3, 1, 13, 5, 5, 3, 5, 1, 1,
        1, 22
    ];

    /// Chapter count when known (canonical 66); null beyond — those books
    /// (Orthodox deuterocanon, e.g. BVB 67-83) are walked in DISCOVERY mode.
    function chaptersFor(bookNum) { return CHAPTERS[bookNum - 1] || null; }
    function chaptersEstimate(bookNum) { return CHAPTERS[bookNum - 1] || 12; }

    const BOOKS_RO = [
        'Geneza', 'Exodul', 'Leviticul', 'Numeri', 'Deuteronomul',
        'Iosua', 'Judecătorii', 'Rut', '1 Samuel', '2 Samuel',
        '1 Împărați', '2 Împărați', '1 Cronici', '2 Cronici',
        'Ezra', 'Neemia', 'Estera', 'Iov', 'Psalmii', 'Proverbele',
        'Eclesiastul', 'Cântarea Cântărilor', 'Isaia', 'Ieremia',
        'Plângerile', 'Ezechiel', 'Daniel', 'Osea', 'Ioel', 'Amos',
        'Obadia', 'Iona', 'Mica', 'Naum', 'Habacuc', 'Țefania',
        'Hagai', 'Zaharia', 'Maleahi',
        'Matei', 'Marcu', 'Luca', 'Ioan', 'Faptele Apostolilor',
        'Romani', '1 Corinteni', '2 Corinteni', 'Galateni', 'Efeseni',
        'Filipeni', 'Coloseni', '1 Tesaloniceni', '2 Tesaloniceni',
        '1 Timotei', '2 Timotei', 'Tit', 'Filimon', 'Evrei',
        'Iacov', '1 Petru', '2 Petru', '1 Ioan', '2 Ioan', '3 Ioan',
        'Iuda', 'Apocalipsa'
    ];

    const SBOOKS_RO = [
        'Gen', 'Exod', 'Lev', 'Num', 'Deut', 'Ios', 'Jud', 'Rut',
        '1Sam', '2Sam', '1Împ', '2Împ', '1Cron', '2Cron', 'Ezr', 'Neem',
        'Est', 'Iov', 'Ps', 'Prov', 'Ecl', 'Cânt', 'Isa', 'Ier',
        'Plg', 'Ezec', 'Dan', 'Osea', 'Ioel', 'Amos', 'Oba', 'Iona',
        'Mica', 'Naum', 'Hab', 'Țef', 'Hag', 'Zah', 'Mal',
        'Mat', 'Mar', 'Luca', 'Ioan', 'Fapt', 'Rom', '1Cor', '2Cor',
        'Gal', 'Efes', 'Fil', 'Col', '1Tes', '2Tes', '1Tim', '2Tim',
        'Tit', 'Flm', 'Evr', 'Iac', '1Pet', '2Pet', '1In', '2In',
        '3In', 'Iuda', 'Apoc'
    ];

    const BOOKS_EN = [
        'Genesis', 'Exodus', 'Leviticus', 'Numbers', 'Deuteronomy',
        'Joshua', 'Judges', 'Ruth', '1 Samuel', '2 Samuel',
        '1 Kings', '2 Kings', '1 Chronicles', '2 Chronicles',
        'Ezra', 'Nehemiah', 'Esther', 'Job', 'Psalms', 'Proverbs',
        'Ecclesiastes', 'Song of Solomon', 'Isaiah', 'Jeremiah',
        'Lamentations', 'Ezekiel', 'Daniel', 'Hosea', 'Joel', 'Amos',
        'Obadiah', 'Jonah', 'Micah', 'Nahum', 'Habakkuk', 'Zephaniah',
        'Haggai', 'Zechariah', 'Malachi',
        'Matthew', 'Mark', 'Luke', 'John', 'Acts',
        'Romans', '1 Corinthians', '2 Corinthians', 'Galatians', 'Ephesians',
        'Philippians', 'Colossians', '1 Thessalonians', '2 Thessalonians',
        '1 Timothy', '2 Timothy', 'Titus', 'Philemon', 'Hebrews',
        'James', '1 Peter', '2 Peter', '1 John', '2 John', '3 John',
        'Jude', 'Revelation'
    ];

    const SBOOKS_EN = [
        'Gen', 'Exod', 'Lev', 'Num', 'Deut', 'Josh', 'Judg', 'Ruth',
        '1Sam', '2Sam', '1Kngs', '2Kngs', '1Chr', '2Chr', 'Ezra', 'Neh',
        'Est', 'Job', 'Ps', 'Prov', 'Eccl', 'Song', 'Isa', 'Jer',
        'Lam', 'Ezk', 'Dan', 'Hos', 'Joel', 'Amos', 'Oba', 'Jona',
        'Mic', 'Nah', 'Hab', 'Zeph', 'Hag', 'Zech', 'Mal',
        'Mat', 'Mk', 'Lk', 'Jn', 'Acts', 'Rom', '1Cor', '2Cor',
        'Gal', 'Eph', 'Phil', 'Col', '1Thes', '2Thes', '1Tim', '2Tim',
        'Tit', 'Phmon', 'Heb', 'James', '1Pet', '2Pet', '1Jn', '2Jn',
        '3Jn', 'Jude', 'Rev'
    ];

    // ═══════════════════════════════════════════════════════════════
    // UTILITIES
    // ═══════════════════════════════════════════════════════════════

    function pad2(n) { return String(n).padStart(2, '0'); }
    function pad3(n) { return String(n).padStart(3, '0'); }
    function sleep(ms) { return new Promise(resolve => setTimeout(resolve, ms)); }

    /**
     * Check if a data key is a valid verse key.
     * Valid: "01:001:001" (exactly 3 colon-separated digit groups, verse >= 1)
     * Invalid: "_count_", "_ver_", "01:001:000" (title), "01:001:000:t0", "01:001:001:xt1"
     */
    function isValidVerseKey(key) {
        var match = key.match(/^(\d{2}):(\d{3}):(\d{3})$/);
        if (!match) return false;
        var verseNum = parseInt(match[3], 10);
        return verseNum >= 1 && verseNum <= 200;
    }

    function getVerseNumber(key) {
        return parseInt(key.split(':')[2], 10);
    }

    function cleanVerseText(html) {
        if (!html) return '';
        var div = document.createElement('div');
        // <br> = poetry line structure (BIV is written entirely in verse) —
        // keep it as a real newline instead of collapsing it into a space.
        div.innerHTML = html.replace(/<br\s*\/?>/gi, '\u0001');
        div.querySelectorAll('sr, mf, .sr, .xSym, .fSym, .x, .f, .cmp1, .cmp2, .cmp3, .tp, .noCopy, script').forEach(function(el) { el.remove(); });
        var text = div.textContent || div.innerText || '';
        // Strip cross-reference markers (*) and footnote markers (%) from text
        text = text.replace(/[*%^]/g, '');
        text = text.replace(/[ \t\r\n]+/g, ' ');
        text = text.replace(/\s*\u0001\s*/g, '\n').replace(/\n{2,}/g, '\n');
        // Interlinears (ASTL) tokenize punctuation as standalone words —
        // reattach " , " / " ." to the preceding word.
        text = text.replace(/\s+([,.;:!?»”\u201D\u00BB])/g, '$1');
        return text.trim();
    }

    // ── Rich verse parser ─────────────────────────────────────────────────
    // Reverse-engineered (Chrome live-DOM analysis, 2026-06-16) markup map:
    //   • Plain  (bvb, ntr, …)           — text only
    //   • Red-letter (vdcc/schl/kjv…)    — <span class='Isus'>…</span>
    //   • Italic / translator-added      — <em>…</em>
    //   • Inline Strong's (kjv)          — word<sr>G3107</sr>, poetry <br>
    //   • Interlinear-translation (astl) — <i><wd>Fericiți</wd><sr>3107</sr><mf>A-NPM</mf></i>
    //   • Interlinear-original (enint)   — <i><wd>Hbr</wd><sr>7225</sr><en>In the beginning</en></i>
    // parseRichVerse(html) → { text, runs[], gloss, hasWoc, hasStrong, mode }.
    // A run is { text, kind?(woc|add), strong?, morph?, gloss? }; runs[] always
    // concatenates back to `text`. eBiblia marker/symbol spans are stripped via
    // the DOM first so plain text stays clean.

    var _entScratch = null;
    function decodeEntities(s) {
        if (!s) return '';
        if (s.indexOf('&') < 0) return s;
        if (!_entScratch) _entScratch = document.createElement('textarea');
        _entScratch.innerHTML = s;
        return _entScratch.value;
    }
    var RICH_NOISE_SEL = '.xSym,.fSym,.x,.f,.cmp1,.cmp2,.cmp3,.tp,.noCopy,script,sup';

    function tidyRich(t) {
        return t.replace(/[*%^]/g, '')
                .replace(/[ \t]+/g, ' ')
                .replace(/ *\n */g, '\n').replace(/\n{2,}/g, '\n')
                .replace(/[ \t]+([,.;:!?»”»])/g, '$1')
                .trim();
    }
    function tagInner(block, name) {
        var m = block.match(new RegExp('<' + name + '\\b[^>]*>([\\s\\S]*?)<\\/' + name + '>', 'i'));
        return m ? decodeEntities(m[1].replace(/<[^>]+>/g, '')) : '';
    }

    /// <i><wd>W</wd><sr>S</sr><mf>M</mf>|<en>gloss</en></i> word units.
    function parseInterlinear(cleanHtml) {
        var runs = [], words = [], glosses = [], anySr = false, anyGloss = false;
        var re = /<i\b[^>]*>([\s\S]*?)<\/i>/gi, m;
        while ((m = re.exec(cleanHtml))) {
            var b = m[1];
            var wd = tagInner(b, 'wd').replace(/\s+/g, ' ').trim();
            var sr = tagInner(b, 'sr').trim(), mf = tagInner(b, 'mf').trim(), en = tagInner(b, 'en').trim();
            if (!wd && !en) continue;
            var run = { text: wd };
            if (sr) { run.strong = sr; anySr = true; }
            if (mf) run.morph = mf;
            if (en) { run.gloss = en.replace(/\s+/g, ' ').trim(); anyGloss = true; }
            runs.push(run);
            if (wd) words.push(wd);
            if (en) glosses.push(en.trim());
        }
        return { text: tidyRich(words.join(' ')), runs: runs,
                 gloss: anyGloss ? tidyRich(glosses.join(' ')) : '',
                 hasStrong: anySr, hasWoc: false, mode: 'interlinear' };
    }

    /// Flat markup: text + <sr> (Strong's, follows its word) + <em>/<i> (add)
    /// + <span class='Isus'> (woc). <br> already became a newline.
    function parseInline(cleanHtml) {
        var toks = cleanHtml.split(/(<[^>]+>)/);
        var runs = [], woc = 0, add = 0, cap = null, strongBuf = '';
        function pushText(t) {
            if (!t) return;
            var kind = woc > 0 ? 'woc' : (add > 0 ? 'add' : 'plain');
            var last = runs[runs.length - 1];
            if (last && (last.kind || 'plain') === kind && !last.strong) last.text += t;
            else runs.push({ text: t, kind: kind });
        }
        for (var i = 0; i < toks.length; i++) {
            var tk = toks[i];
            if (i % 2 === 1) {
                var tl = tk.toLowerCase();
                if (/^<sr\b/.test(tl)) { cap = 'sr'; strongBuf = ''; }
                else if (/^<\/sr>/.test(tl)) {
                    var s = strongBuf.trim(); cap = null;
                    if (s) { var last = runs[runs.length - 1];
                        if (last && !last.strong) {
                            var mm = last.text.match(/(\s*)(\S+)\s*$/);
                            if (mm) { var pre = last.text.slice(0, last.text.length - mm[0].length);
                                if (pre) runs[runs.length - 1].text = pre; else runs.pop();
                                runs.push({ text: mm[1] + mm[2], kind: last.kind, strong: s });
                            } else last.strong = s;
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
        var anySr = false;
        runs.forEach(function (r) { r.text = r.text.replace(/[*%^]/g, '').replace(/[ \t]+/g, ' '); if (r.strong) anySr = true; });
        var merged = [];
        runs.forEach(function (r) { if (!r.text) return; var l = merged[merged.length - 1];
            if (l && (l.kind || 'plain') === (r.kind || 'plain') && !l.strong && !r.strong) l.text += r.text;
            else merged.push(r); });
        var text = tidyRich(merged.map(function (r) { return r.text; }).join(''));
        var hasWoc = merged.some(function (r) { return r.kind === 'woc'; });
        merged.forEach(function (r) { if (r.kind === 'plain') delete r.kind; });
        return { text: text, runs: merged, gloss: '', hasStrong: anySr, hasWoc: hasWoc, mode: 'inline' };
    }

    function parseRichVerse(html) {
        if (!html) return { text: '', runs: [], gloss: '', hasStrong: false, hasWoc: false, mode: 'inline' };
        var div = document.createElement('div');
        div.innerHTML = html.replace(/<br\s*\/?>/gi, '\n');
        div.querySelectorAll(RICH_NOISE_SEL).forEach(function (el) { el.remove(); });
        var clean = div.innerHTML;
        return (/<wd\b/i.test(clean)) ? parseInterlinear(clean) : parseInline(clean);
    }

    /// Strip Strong's/morph/gloss from runs, re-merging adjacent same-kind runs
    /// (used when the Strong's toggle is off — keeps only woc/add colouring).
    function runsWocOnly(runs) {
        var merged = [];
        for (var i = 0; i < runs.length; i++) {
            var k = runs[i].kind || 'plain';
            var last = merged[merged.length - 1];
            if (last && (last.kind || 'plain') === k) last.text += runs[i].text;
            else merged.push({ text: runs[i].text, kind: runs[i].kind });
        }
        merged.forEach(function (r) { if (!r.kind) delete r.kind; });
        return merged;
    }

    /**
     * Map internal eBiblia translation codes to their official public codes.
     * e.g. "vdcc" → "EDC100" (eBiblia uses "VDCC" internally for EDC100).
     */
    var CODE_MAP = { 'vdcc': 'EDC100' };
    function mapTranslationCode(internalCode) {
        var lower = (internalCode || '').toLowerCase();
        return CODE_MAP[lower] || internalCode.toUpperCase();
    }

    /**
     * Extract cross-references, footnotes, and titles from raw data values.
     *
     * refEntries is an array of { type, index, value } where:
     *  - type 'x' or 'xt': cross-reference in eBiblia compact format
     *    e.g. "43:1,2;58:1:10"  means "book43 1:2; book58 1:10"
     *    Format: semicolon-separated entries, each is bookNum:chap:verse,...
     *  - type 'f': footnote as text (may contain HTML like <em>, <b>)
     *  - type 't': section title/heading text (index = t1, t2, t3 ordering)
     *
     * eBiblia's _prettyPrintXRefs(e, shortBooks):
     *   Split by ";", each part split by ":", first element is book index,
     *   rest is chapter:verse references. It uses shortBooks[bookIdx-1] as prefix.
     *
     * Returns { crossReferences: [...], footnotes: [...], titles: [...] }
     *
     * Titles are returned as structured heading objects:
     *   { text: string, level: number }
     * Level classification (auto-detected from content):
     *   0 = "bookRef"     — Parenthetical book-level reference, e.g. "(Psalmul 103:7. Neemia 9:9-20)"
     *   1 = "major"       — ALL-CAPS major section, e.g. "VREMURILE STRĂVECHI DE LA FACEREA LUMII..."
     *   2 = "division"    — Chapter range indicator, e.g. "CAPITOLELE 1:1–11:9"
     *   3 = "section"     — Normal mixed-case section heading, e.g. "Facerea lumii", "Lumina"
     */
    function classifyTitleLevel(text) {
        // Parenthetical book-level references: "(Psalmul 103:7. Neemia 9:9-20)"
        if (text.charAt(0) === '(' && text.charAt(text.length - 1) === ')') return 0;
        // Chapter range indicators: "CAPITOLELE 1:1–11:9" or "CAPITOLUL 5"
        if (/^CAPITOLELE?\b/i.test(text)) return 2;
        // ALL-CAPS major sections (at least 4 chars to avoid false positives like "NOE")
        if (text === text.toUpperCase() && text.length > 3 && /[A-ZÀ-Ž]/.test(text)) return 1;
        // Normal section headings
        return 3;
    }

    function extractReferences(refEntries) {
        var result = { crossReferences: [], footnotes: [], titles: [] };
        if (!refEntries || refEntries.length === 0) return result;

        for (var ri = 0; ri < refEntries.length; ri++) {
            var entry = refEntries[ri];
            if (!entry || !entry.value || typeof entry.value !== 'string') continue;
            var raw = entry.value.trim();
            if (raw.length === 0) continue;

            if (entry.type === 'x' || entry.type === 'xt') {
                // Cross-reference: compact format "bookIdx:ch:vs;bookIdx:ch:vs;..."
                // Parse like eBiblia's _prettyPrintXRefs does
                var parts = raw.split(';');
                var refs = [];
                for (var pi = 0; pi < parts.length; pi++) {
                    var part = parts[pi].trim();
                    if (!part) continue;
                    var segs = part.split(':');
                    if (segs.length >= 2) {
                        var bookIdx = parseInt(segs[0], 10);
                        var bookName = SBOOKS_RO[bookIdx - 1] || ('Book ' + bookIdx);
                        segs.shift(); // remove book index
                        var refStr = bookName + ' ' + segs.join(':');
                        refs.push(refStr);
                    } else {
                        // Single segment — use as-is
                        refs.push(part);
                    }
                }
                if (refs.length > 0) {
                    // GOAT v2 cross-reference shape: { targets: [...] }.
                    result.crossReferences.push({ targets: refs });
                }
            } else if (entry.type === 'f') {
                // Footnote: source may contain HTML (<em>, <b>) — flatten to
                // clean text (GOAT files carry no raw HTML).
                var noteClean = raw.replace(/<[^>]*>/g, '').replace(/\s+/g, ' ').trim();
                if (noteClean) {
                    result.footnotes.push({ text: noteClean });
                }
            } else if (entry.type === 't') {
                // Section title/heading — classify into hierarchy level
                var titleText = raw.replace(/<[^>]*>/g, '').replace(/\s+/g, ' ').trim();
                if (titleText) {
                    result.titles.push({
                        text: titleText,
                        level: classifyTitleLevel(titleText)
                    });
                }
            }
        }

        return result;
    }

    function formatDuration(seconds) {
        if (!seconds || seconds < 0) return '—';
        if (seconds < 60) return Math.round(seconds) + 's';
        if (seconds < 3600) return Math.floor(seconds / 60) + 'm ' + Math.round(seconds % 60) + 's';
        var h = Math.floor(seconds / 3600);
        var m = Math.floor((seconds % 3600) / 60);
        return h + 'h ' + m + 'm';
    }

    function formatSize(bytes) {
        if (bytes < 1024) return bytes + ' B';
        if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + ' KB';
        return (bytes / (1024 * 1024)).toFixed(2) + ' MB';
    }

    // ═══════════════════════════════════════════════════════════════
    // DATA FETCHING
    // ═══════════════════════════════════════════════════════════════

    function fetchFromAPI(path, retries) {
        retries = retries || CONFIG.maxRetries;
        var endpoints = CONFIG.endpoints;
        var attempt = 0;

        function tryNext() {
            if (attempt >= retries) {
                return Promise.reject(new Error('Failed to fetch ' + path + ' after ' + retries + ' attempts'));
            }
            var endpoint = endpoints[attempt % endpoints.length];
            var url = CONFIG.proto + endpoint + CONFIG.pathPrefix + path;
            attempt++;
            return fetch(url).then(function(response) {
                if (response.ok) {
                    return response.text().then(function(text) {
                        try { return JSON.parse(text); } catch(e) { return text; }
                    });
                }
                return sleep(CONFIG.retryDelay).then(tryNext);
            }).catch(function(err) {
                console.warn('[eBiblia Exporter] Attempt ' + attempt + ' failed: ' + err.message);
                if (attempt < retries) return sleep(CONFIG.retryDelay).then(tryNext);
                throw err;
            });
        }
        return tryNext();
    }

    // ── Translation metadata (the eBiblia "about" articles) ──
    // ebart:b:t:<code> → full display name with year, e.g.
    //   "NT Ediţia Dumitru Cornilescu Revizuită (2019)"
    // ebart:b:<code>   → an HTML <blockquote> of labelled fields:
    //   Prescurtare / Descriere / Copyright / Limba / Sursă text
    // Reading both lets us fill translation.name/description/copyright/year.

    function getArticleViaN(key) {
        return new Promise(function (resolve) {
            try {
                var win = unsafeWindow || window;
                var N = win.N;
                if (!N || !N.get) { resolve(null); return; }
                var settled = false;
                var done = function (v) { if (settled) return; settled = true; resolve(v); };
                N.get(key, function (v) { done(typeof v === 'string' ? v : (v == null ? null : String(v))); },
                            function () { done(null); });
                setTimeout(function () { done(null); }, 8000); // never hang the batch (cold article fetch)
            } catch (e) { resolve(null); }
        });
    }

    function getArticle(key) {
        return getArticleViaN(key).then(function (v) {
            if (v != null && v !== '') return v;
            // API fallback (single attempt — the data layer normally succeeds).
            return fetchFromAPI('get/' + encodeURIComponent(key), 1).then(function (r) {
                if (r == null) return null;
                if (typeof r === 'string') return r;
                if (typeof r === 'object') return r[key] != null ? String(r[key]) : null;
                return String(r);
            }).catch(function () { return null; });
        }).catch(function () { return null; });
    }

    function htmlToText(html) {
        if (!html) return '';
        var d = document.createElement('div');
        d.innerHTML = String(html);
        return (d.textContent || d.innerText || '').replace(/\s+/g, ' ').trim();
    }

    /// Pull the labelled fields out of the ebart:b:<code> "about" blockquote.
    function parseAboutArticle(html) {
        var out = { abbreviation: '', description: '', copyright: '', languageName: '', source: '' };
        if (!html) return out;
        var d = document.createElement('div');
        d.innerHTML = String(html).replace(/<br\s*\/?>/gi, '\n').replace(/<\/(p|div|li|h\d)>/gi, '\n');
        var bq = d.querySelector('blockquote') || d; // structured fields live in the leading blockquote
        var text = (bq.textContent || bq.innerText || '');
        var stop = '(?:Prescurtare|Descriere|Copyright|Limba|Surs[\\u0103a](?:\\s*text)?)\\s*:';
        var grab = function (label) {
            var re = new RegExp(label + '\\s*:\\s*([\\s\\S]*?)(?=' + stop + '|$)', 'i');
            var m = text.match(re);
            return (m && m[1]) ? m[1].replace(/\s+/g, ' ').trim() : '';
        };
        out.abbreviation = grab('Prescurtare');
        out.description = grab('Descriere');
        out.copyright = grab('Copyright');
        out.languageName = grab('Limba');
        out.source = grab('Surs[\\u0103a]\\s*text') || grab('Surs[\\u0103a]');
        return out;
    }

    function extractYear(text) {
        if (!text) return null;
        var paren = String(text).match(/\((1\d{3}|20\d{2})\)/); // full-name articles end with "(2019)"
        if (paren) return parseInt(paren[1], 10);
        var all = String(text).match(/\b(1\d{3}|20\d{2})\b/g);
        return (all && all.length) ? parseInt(all[all.length - 1], 10) : null;
    }

    /// Flatten an article's HTML to readable text, preserving paragraph and
    /// heading breaks as newlines (forewords/intros are multi-paragraph essays).
    function articleToText(html) {
        if (!html) return '';
        var d = document.createElement('div');
        d.innerHTML = String(html)
            .replace(/<br\s*\/?>/gi, '\n')
            .replace(/<\/(p|div|li|h[1-6]|blockquote|tr|section)>/gi, '\n');
        var t = (d.textContent || d.innerText || '');
        return t.replace(/[ \t ]+/g, ' ')
                .replace(/[ \t]*\n[ \t]*/g, '\n')
                .replace(/\n{3,}/g, '\n\n')
                .trim();
    }

    /// The foreword / introduction body of an "about" article — everything
    /// AFTER the leading structured blockquote (CUVÂNT ÎNAINTE, intros, etc.).
    function extractForeword(html) {
        if (!html) return '';
        var rest = String(html).replace(/<blockquote[\s\S]*?<\/blockquote>/i, '');
        return articleToText(rest);
    }

    /// Fetch + merge the metadata articles for a translation code. Returns the
    /// structured fields PLUS the full front-matter (foreword/intro) as text
    /// and the raw article HTML (for the offline HTML dump).
    function fetchTranslationMeta(code) {
        var lc = (code || '').toLowerCase();
        return Promise.all([
            getArticle('ebart:b:t:' + lc),
            getArticle('ebart:b:' + lc)
        ]).then(function (res) {
            var fullName = htmlToText(res[0]);
            var about = parseAboutArticle(res[1]);
            return {
                fullName: fullName || '',
                description: about.description || '',
                copyright: about.copyright || '',
                languageName: about.languageName || '',
                source: about.source || '',
                abbreviation: about.abbreviation || '',
                year: extractYear(fullName) || extractYear(about.copyright) || extractYear(about.description) || null,
                foreword: extractForeword(res[1]),   // CUVÂNT ÎNAINTE / intros, as text
                aboutHtml: res[1] || '',             // full article HTML, for the dump
            };
        }).catch(function () { return null; });
    }

    /**
     * Check if a data key is a cross-reference, footnote, or title key.
     *
     * From eBiblia's buildVerseData() in app.js, the key patterns are:
     *   Cross-references: "01:001:001:x1", "01:001:001:x2", etc.  (i[n+":x"+b++])
     *   Footnotes:        "01:001:001:f1", "01:001:001:f2", etc.  (i[n+":f"+b++])
     *   Title fn ref:     "01:001:001:xt1"                        (i[n+":xt1"])
     *   Titles:           "01:001:001:t1", "01:001:001:t2", etc.  (i[n+":t"+b++])
     *
     * Returns { verseKey, type ('x'|'f'|'xt'|'t'), index } or null.
     */
    function parseRefKey(key) {
        var match = key.match(/^(\d{2}:\d{3}:\d{3}):(xt|x|f|t)(\d+)$/);
        if (!match) return null;
        return { verseKey: match[1], type: match[2], index: parseInt(match[3], 10) };
    }

    /**
     * Parse verse data from raw object returned by N.range or API.
     * Returns array of { number, text, _rawHtml, _refEntries }.
     * _refEntries is an array of { type, value } from cross-ref/footnote keys.
     */
    function parseVerseData(data) {
        if (!data || typeof data !== 'object') return [];
        var verses = [];
        var keys = Object.keys(data);

        // First pass: collect cross-reference/footnote values by verse key
        var refsByVerse = {};
        for (var r = 0; r < keys.length; r++) {
            var rkey = keys[r];
            if (rkey.charAt(0) === '_') continue;
            var refInfo = parseRefKey(rkey);
            if (!refInfo) continue;
            var refValue = data[rkey];
            if (!refValue || typeof refValue !== 'string') continue;
            if (!refsByVerse[refInfo.verseKey]) refsByVerse[refInfo.verseKey] = [];
            refsByVerse[refInfo.verseKey].push({ type: refInfo.type, index: refInfo.index, value: refValue });
        }

        // Second pass: collect verses
        for (var i = 0; i < keys.length; i++) {
            var key = keys[i];
            if (key.charAt(0) === '_') continue;
            if (!isValidVerseKey(key)) continue;

            var rawText = data[key];
            if (!rawText || typeof rawText !== 'string') continue;
            if (rawText.length < 2) continue;

            var verseNum = getVerseNumber(key);
            var cleanText = cleanVerseText(rawText);
            if (!cleanText) continue;

            verses.push({
                number: verseNum,
                text: cleanText,
                _rawHtml: rawText,
                _refEntries: refsByVerse[key] || []
            });
        }

        verses.sort(function(a, b) { return a.number - b.number; });
        return verses;
    }

    function fetchChapterViaDataLayer(namespace, book, chapter) {
        return new Promise(function(resolve, reject) {
            try {
                var win = unsafeWindow || window;
                var N = win.N;
                if (!N || !N.range) { reject(new Error('N.range not available')); return; }

                var bookChap = pad2(book) + ':' + pad3(chapter);
                var verseKey = 'eb' + namespace + ':' + bookChap + ':*';
                var resKey = 'eb' + namespace + '-res:' + bookChap + ':*';

                // Fetch verse text data
                N.range(verseKey, null, function(verseData) {
                    try {
                        // Also fetch the -res (references) namespace
                        N.range(resKey, null, function(resData) {
                            try {
                                // Merge both datasets: verse text + references
                                var merged = {};
                                if (verseData && typeof verseData === 'object') {
                                    var vKeys = Object.keys(verseData);
                                    for (var vi = 0; vi < vKeys.length; vi++) {
                                        merged[vKeys[vi]] = verseData[vKeys[vi]];
                                    }
                                }
                                if (resData && typeof resData === 'object') {
                                    var rKeys = Object.keys(resData);
                                    for (var ri = 0; ri < rKeys.length; ri++) {
                                        merged[rKeys[ri]] = resData[rKeys[ri]];
                                    }
                                }
                                resolve(parseVerseData(merged));
                            } catch(err) { reject(err); }
                        }, function() {
                            // If -res fetch fails, parse verse data alone (no refs)
                            try { resolve(parseVerseData(verseData)); }
                            catch(err) { reject(err); }
                        });
                    } catch(err) {
                        // If -res call throws, still use verse data alone
                        try { resolve(parseVerseData(verseData)); }
                        catch(err2) { reject(err2); }
                    }
                }, function() {
                    reject(new Error('N.range callback error'));
                });
            } catch(err) { reject(err); }
        });
    }

    function fetchChapterViaAPI(namespace, book, chapter) {
        var bookChap = pad2(book) + ':' + pad3(chapter);
        var versePath = 'range/eb' + namespace + ':' + bookChap + ':001/' + bookChap + ':999';
        var resPath = 'range/eb' + namespace + '-res:' + bookChap + ':*/';

        // Fetch both verse text and references in parallel
        return Promise.all([
            fetchFromAPI(versePath).catch(function() { return {}; }),
            fetchFromAPI(resPath).catch(function() { return {}; })
        ]).then(function(results) {
            var verseData = results[0] || {};
            var resData = results[1] || {};

            // Merge both datasets
            var merged = {};
            if (typeof verseData === 'object') {
                var vKeys = Object.keys(verseData);
                for (var vi = 0; vi < vKeys.length; vi++) {
                    merged[vKeys[vi]] = verseData[vKeys[vi]];
                }
            }
            if (typeof resData === 'object') {
                var rKeys = Object.keys(resData);
                for (var ri = 0; ri < rKeys.length; ri++) {
                    merged[rKeys[ri]] = resData[rKeys[ri]];
                }
            }
            return parseVerseData(merged);
        }).catch(function(err) {
            console.error('[eBiblia Exporter] API fetch failed:', err);
            return [];
        });
    }

    function fetchChapter(namespace, book, chapter) {
        return fetchChapterViaDataLayer(namespace, book, chapter).then(function(verses) {
            if (verses && verses.length > 0) return verses;
            return fetchChapterViaAPI(namespace, book, chapter);
        }).catch(function() {
            return fetchChapterViaAPI(namespace, book, chapter);
        }).catch(function() { return []; });
    }

    // ═══════════════════════════════════════════════════════════════
    // JSON SCHEMA
    // ═══════════════════════════════════════════════════════════════

    function createBibleJSON(translationCode, metadata) {
        return {
            schemaVersion: '1.0.0',
            format: 'TopPresenter Bible',
            translation: {
                code: mapTranslationCode(translationCode),
                name: metadata.name || mapTranslationCode(translationCode),
                nameLocal: metadata.nameLocal || '',
                language: metadata.language || 'ro',
                languageName: metadata.languageName || '',
                copyright: metadata.copyright || '',
                description: metadata.description || '',
                about: metadata.about || '',
                source: metadata.source || '',
                year: metadata.year || null,
                direction: metadata.direction || 'ltr',
                versification: metadata.versification || null,
                canon: metadata.canon || null,
                incomplete: metadata.incomplete || false,
                hasWordsOfChrist: metadata.hasWordsOfChrist || false,
                hasStrongs: metadata.hasStrongs || false,
            },
            exportInfo: {
                source: 'eBiblia.ro',
                exportDate: new Date().toISOString(),
                exporterVersion: '1.15.0',
                totalBooks: 0, totalChapters: 0, totalVerses: 0,
            },
            books: [],
            _extensions: {}
        };
    }

    function createBookJSON(bookNumber, chapterCount) {
        var idx = bookNumber - 1;
        return {
            number: bookNumber,
            name: BOOKS_RO[idx] || ('Cartea ' + bookNumber),
            nameEnglish: BOOKS_EN[idx] || ('Book ' + bookNumber),
            abbreviation: SBOOKS_RO[idx] || ('C' + bookNumber),
            abbreviationEnglish: SBOOKS_EN[idx] || ('B' + bookNumber),
            testament: bookNumber <= 39 ? 'OT' : (bookNumber <= 66 ? 'NT' : 'DC'),
            expectedChapters: chapterCount,
            chapters: [],
            _extensions: {}
        };
    }

    // ═══════════════════════════════════════════════════════════════
    // AVAILABLE TRANSLATIONS
    // ═══════════════════════════════════════════════════════════════

    function getAvailableTranslations() {
        var win = unsafeWindow || window;
        var appBibles = win.app && win.app.BIBLES;
        var translations = {};

        if (appBibles) {
            for (var code in appBibles) {
                if (!appBibles.hasOwnProperty(code)) continue;
                var info = appBibles[code];
                var displayCode = mapTranslationCode(code);
                if (code.toLowerCase() === 'vdcc') displayCode = 'EDC100 (VDCC)';
                translations[code] = {
                    code: code, displayCode: displayCode,
                    lang: info.lang || 'ro', books: info.books || [1, 66],
                    copyright: info.copyright || '', incomplete: info.incomplete || false,
                };
            }
        } else {
            var fallback = ['vdcc', 'edcr', 'ntr', 'vdc', 'vdcl', 'kjv', 'niv', 'web', 'esv'];
            for (var i = 0; i < fallback.length; i++) {
                var c = fallback[i];
                translations[c] = { code: c, displayCode: c.toUpperCase(), lang: 'ro', books: [1,66], copyright: '', incomplete: false };
            }
        }
        return translations;
    }

    // ═══════════════════════════════════════════════════════════════
    // UI
    // ═══════════════════════════════════════════════════════════════

    var exportState = {
        running: false, paused: false, cancelled: false,
        currentBook: 0, currentChapter: 0,
        currentBookName: '', currentBookChapters: 0,
        totalBooks: 0, totalChapters: 0,
        completedChapters: 0, completedBooks: 0,
        totalVerses: 0, errors: [], bibleData: null,
        startTime: 0, bookVerseCount: 0,
    };

    // Batch mode: "Exportă toate" walks every translation sequentially and
    // auto-downloads each one into per-language folders.
    var batchState = { active: false, cancelled: false, index: 0, total: 0, done: [], failed: [] };

    /// ASCII-safe folder names per language (subfolder paths must stay plain).
    var LANG_FOLDERS = {
        'ro': 'Romana', 'en': 'English', 'de': 'Deutsch', 'fr': 'Francais',
        'es': 'Espanol', 'it': 'Italiano', 'hu': 'Magyar', 'ru': 'Russian',
        'gr': 'Greek', 'ebr': 'Hebrew', 'lat': 'Latin', 'ukr': 'Ukrainian',
        'nl': 'Nederlands', 'pg': 'Portugues', 'arab': 'Arabic',
        'sb': 'Srpski', 'roma': 'Romani',
    };

    function createUI() {
        if (document.getElementById('ebiblia-exporter-panel')) return;
        var panel = document.createElement('div');
        panel.id = 'ebiblia-exporter-panel';
        panel.innerHTML = '\
<style>\
#ebiblia-exporter-panel{position:fixed;bottom:20px;right:20px;width:400px;background:#1c1c1e;color:#e0e0e0;border-radius:12px;box-shadow:0 8px 32px rgba(0,0,0,0.4);z-index:999999;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;font-size:13px;overflow:hidden;transition:all .3s ease}\
#ebiblia-exporter-panel.minimized{width:48px;height:48px;border-radius:50%;cursor:pointer}\
#ebiblia-exporter-panel.minimized .exp-body{display:none}\
#ebiblia-exporter-panel.minimized .exp-header{padding:12px;justify-content:center}\
#ebiblia-exporter-panel.minimized .exp-header span,#ebiblia-exporter-panel.minimized .exp-minimize{display:none}\
.exp-header{background:#2c2c2e;padding:10px 14px;display:flex;align-items:center;justify-content:space-between;cursor:move;border-bottom:1px solid #3a3a3c}\
.exp-header span{font-weight:600;font-size:14px;color:#f2f2f2}\
.exp-minimize{cursor:pointer;color:#aaa;font-size:18px;background:none;border:none;padding:0 4px}\
.exp-minimize:hover{color:#fff}\
.exp-body{padding:14px}\
.exp-row{margin-bottom:10px}\
.exp-label{display:block;font-size:11px;color:#888;margin-bottom:4px;text-transform:uppercase;letter-spacing:.5px}\
.exp-select,.exp-input{width:100%;padding:8px 10px;background:#3a3a3c;border:1px solid #48484a;border-radius:6px;color:#e0e0e0;font-size:13px;outline:none;box-sizing:border-box}\
.exp-select:focus,.exp-input:focus{border-color:#f2f2f2}\
.exp-progress-bar{width:100%;height:8px;background:#3a3a3c;border-radius:4px;overflow:hidden;margin:8px 0}\
.exp-progress-fill{height:100%;width:0%;background:linear-gradient(90deg,#8e8e93,#f2f2f2);transition:width .3s ease;border-radius:4px}\
.exp-status{font-size:12px;color:#ccc;min-height:18px;margin-bottom:6px;word-break:break-word;line-height:1.4}\
.exp-detail-grid{display:grid;grid-template-columns:1fr 1fr;gap:4px 12px;margin-bottom:10px;font-size:12px;color:#aaa}\
.exp-detail-grid .exp-dv{color:#e0e0e0;font-weight:600;text-align:right}\
.exp-stats{display:grid;grid-template-columns:1fr 1fr 1fr 1fr;gap:6px;margin-bottom:10px}\
.exp-stat{background:#3a3a3c;border-radius:6px;padding:6px 4px;text-align:center}\
.exp-stat-val{font-size:15px;font-weight:700;color:#f2f2f2}\
.exp-stat-label{font-size:9px;color:#888;text-transform:uppercase}\
.exp-buttons{display:flex;gap:8px}\
.exp-btn{flex:1;padding:9px 8px;border:none;border-radius:6px;font-size:12px;font-weight:600;cursor:pointer;transition:all .2s ease}\
.exp-btn:disabled{opacity:.4;cursor:not-allowed}\
.exp-btn-primary{background:#e5e5e5;color:#1c1c1e}\
.exp-btn-primary:hover:not(:disabled){background:#ffffff}\
.exp-btn-secondary{background:#3a3a3c;color:#e0e0e0}\
.exp-btn-secondary:hover:not(:disabled){background:#48484a}\
.exp-btn-success{background:#a8a8ad;color:#1c1c1e}\
.exp-btn-success:hover:not(:disabled){background:#c4c4c8}\
.exp-btn-danger{background:#5a5a5e;color:#f2f2f2}\
.exp-btn-danger:hover:not(:disabled){background:#6e6e73}\
.exp-options{margin-bottom:10px}\
.exp-toggle-row{display:flex;align-items:center;gap:10px;margin-bottom:8px;cursor:pointer;-webkit-user-select:none;user-select:none}\
.exp-toggle-input{position:absolute!important;width:1px!important;height:1px!important;opacity:0!important;margin:0!important;padding:0!important;border:0!important;pointer-events:none!important;clip:rect(0 0 0 0)!important;clip-path:inset(50%)!important;-webkit-appearance:none!important;appearance:none!important}\
.exp-toggle-track{position:relative!important;flex:0 0 auto!important;display:inline-block!important;width:40px!important;height:23px!important;background:#5a5a5e!important;border-radius:999px!important;transition:background .18s ease!important;box-shadow:inset 0 0 0 1px rgba(255,255,255,.07)!important}\
.exp-toggle-track::after{content:""!important;position:absolute!important;top:2px!important;left:2px!important;width:19px!important;height:19px!important;border-radius:50%!important;background:#fff!important;transition:transform .18s ease!important;box-shadow:0 1px 3px rgba(0,0,0,.55)!important;display:block!important}\
.exp-toggle-input:checked + .exp-toggle-track{background:#34c759!important}\
.exp-toggle-input:checked + .exp-toggle-track::after{transform:translateX(17px)!important}\
.exp-toggle-input:disabled + .exp-toggle-track{opacity:.4!important}\
.exp-toggle-row.disabled{opacity:.5;cursor:not-allowed}\
.exp-toggle-text{font-size:12px;color:#ccc;line-height:1.3}\
#ebiblia-exporter-panel label::before,#ebiblia-exporter-panel label::after,#ebiblia-exporter-panel .exp-label::before,#ebiblia-exporter-panel .exp-label::after{content:none!important;display:none!important;background:none!important;border:none!important}\
.exp-range-row{display:flex;gap:8px;align-items:center}\
.exp-range-row .exp-input{width:70px;text-align:center}\
.exp-range-row span{color:#888}\
.exp-estimate{font-size:11px;color:#8e8e93;margin:6px 0 2px;line-height:1.4}\
.exp-estimate b{color:#d8d8dc;font-weight:600}\
.exp-log{max-height:120px;overflow-y:auto;background:#111113;border-radius:6px;padding:6px 8px;font-family:Menlo,Consolas,monospace;font-size:11px;color:#666;margin-top:8px;display:none}\
.exp-log.visible{display:block}\
.exp-log .err{color:#ffffff;font-weight:700}.exp-log .ok{color:#d4d4d8}.exp-log .info{color:#98989d}.exp-log .warn{color:#c6c6cc}.exp-log .data{color:#aeaeb2}\
.exp-separator{border:none;border-top:1px solid #3a3a3c;margin:10px 0}\
</style>\
<div class="exp-header">\
<span>📖 eBiblia Exporter</span>\
<button class="exp-minimize" id="exp-toggle-min" title="Minimize">−</button>\
</div>\
<div class="exp-body">\
<div class="exp-row"><div class="exp-label">Traducere / Translation</div><select class="exp-select" id="exp-translation"><option value="">Se încarcă...</option></select></div>\
<div class="exp-options"><div class="exp-label">Interval cărți / Book Range</div><div class="exp-range-row"><input type="number" class="exp-input" id="exp-book-start" min="1" max="83" value="1"><span>→</span><input type="number" class="exp-input" id="exp-book-end" min="1" max="83" value="83"><span class="exp-label" style="margin:0;white-space:nowrap" id="exp-range-info">≈ 1393 cap.</span></div></div>\
<div class="exp-options">\
<div class="exp-label">Conținut bogat (GOAT) / Rich content</div>\
<label class="exp-toggle-row"><input type="checkbox" class="exp-toggle-input" id="exp-include-woc" checked><span class="exp-toggle-track"></span><span class="exp-toggle-text">✝️ Cuvintele lui Isus (text roșu / red-letter)</span></label>\
<label class="exp-toggle-row"><input type="checkbox" class="exp-toggle-input" id="exp-include-refs" checked><span class="exp-toggle-track"></span><span class="exp-toggle-text">📎 Titluri, referințe încrucișate și note</span></label>\
<label class="exp-toggle-row"><input type="checkbox" class="exp-toggle-input" id="exp-include-meta" checked><span class="exp-toggle-track"></span><span class="exp-toggle-text">🏷️ Metadate complete (nume, an, descriere, copyright)</span></label>\
<label class="exp-toggle-row"><input type="checkbox" class="exp-toggle-input" id="exp-include-strong" checked><span class="exp-toggle-track"></span><span class="exp-toggle-text">🔢 Strong\x27s + morfologie + interlinear (mărește fișierul)</span></label>\
<div class="exp-label" style="margin-top:10px">Extra (analiză) / Analysis extras — oprite implicit</div>\
<label class="exp-toggle-row"><input type="checkbox" class="exp-toggle-input" id="exp-include-raw"><span class="exp-toggle-track"></span><span class="exp-toggle-text">🔤 HTML brut per verset (câmp rawHtml în JSON)</span></label>\
<label class="exp-toggle-row"><input type="checkbox" class="exp-toggle-input" id="exp-raw-dump"><span class="exp-toggle-track"></span><span class="exp-toggle-text">🧬 HTML brut al întregii Biblii (fișier .html separat)</span></label>\
<label class="exp-toggle-row"><input type="checkbox" class="exp-toggle-input" id="exp-save-log"><span class="exp-toggle-track"></span><span class="exp-toggle-text">📝 Jurnal cu debugging (fișier .txt separat)</span></label>\
</div>\
<div class="exp-row"><div class="exp-label">Delay între capitole (ms) — pt. Start și Toate</div><input type="number" class="exp-input" id="exp-delay" min="0" max="5000" value="50" step="25" style="width:100px"></div>\
<div class="exp-estimate" id="exp-estimate">⏱ Estimat: —</div>\
<hr class="exp-separator">\
<div class="exp-status" id="exp-batch-status" style="display:none;color:#d8d8dc;font-weight:600"></div>\
<div class="exp-progress-bar"><div class="exp-progress-fill" id="exp-progress"></div></div>\
<div class="exp-status" id="exp-status">Pregătit. Selectează o traducere și apasă Start.</div>\
<div class="exp-detail-grid" id="exp-details" style="display:none">\
<span>Carte curentă:</span><span class="exp-dv" id="exp-cur-book">—</span>\
<span>Capitol:</span><span class="exp-dv" id="exp-cur-chap">—</span>\
<span>Versete în carte:</span><span class="exp-dv" id="exp-cur-book-verses">—</span>\
<span>Timp scurs:</span><span class="exp-dv" id="exp-elapsed">—</span>\
<span>Timp estimat rămas:</span><span class="exp-dv" id="exp-eta">—</span>\
<span>Dimensiune JSON:</span><span class="exp-dv" id="exp-json-size">—</span>\
<span>Erori:</span><span class="exp-dv" id="exp-error-count">0</span>\
</div>\
<div class="exp-stats">\
<div class="exp-stat"><div class="exp-stat-val" id="exp-books-count">0</div><div class="exp-stat-label">Cărți</div></div>\
<div class="exp-stat"><div class="exp-stat-val" id="exp-chapters-count">0</div><div class="exp-stat-label">Capitole</div></div>\
<div class="exp-stat"><div class="exp-stat-val" id="exp-verses-count">0</div><div class="exp-stat-label">Versete</div></div>\
<div class="exp-stat"><div class="exp-stat-val" id="exp-progress-pct">0%</div><div class="exp-stat-label">Progres</div></div>\
</div>\
<div class="exp-buttons">\
<button class="exp-btn exp-btn-primary" id="exp-start">▶ Start</button>\
<button class="exp-btn exp-btn-primary" id="exp-start-all" title="Exportă TOATE traducerile, fiecare în fișierul ei, în foldere per limbă">⏬ Toate</button>\
<button class="exp-btn exp-btn-secondary" id="exp-pause" disabled>⏸ Pauză</button>\
<button class="exp-btn exp-btn-danger" id="exp-cancel" disabled>✕ Stop</button>\
<button class="exp-btn exp-btn-success" id="exp-download" disabled>⬇ JSON</button>\
</div>\
<div class="exp-log" id="exp-log"></div>\
</div>';

        document.body.appendChild(panel);

        document.getElementById('exp-toggle-min').addEventListener('click', toggleMinimize);
        document.getElementById('exp-start').addEventListener('click', startExport);
        document.getElementById('exp-start-all').addEventListener('click', startExportAll);
        document.getElementById('exp-pause').addEventListener('click', togglePause);
        document.getElementById('exp-cancel').addEventListener('click', cancelExport);
        document.getElementById('exp-download').addEventListener('click', downloadJSON);

        var updateRangeInfo = function() {
            var s = parseInt(document.getElementById('exp-book-start').value) || 1;
            var e = parseInt(document.getElementById('exp-book-end').value) || 66;
            document.getElementById('exp-range-info').textContent = '≈ ' + countChapters(s, e) + ' cap.';
            updateEstimate();
        };
        document.getElementById('exp-book-start').addEventListener('change', updateRangeInfo);
        document.getElementById('exp-book-end').addEventListener('change', updateRangeInfo);
        document.getElementById('exp-delay').addEventListener('input', updateEstimate);
        document.getElementById('exp-translation').addEventListener('change', updateEstimate);

        panel.addEventListener('click', function(e) {
            if (panel.classList.contains('minimized')) panel.classList.remove('minimized');
        });

        makeDraggable(panel);
        setTimeout(populateTranslations, 1500);
    }

    /// Chapters across a book range, using the canonical/estimated counts.
    function countChapters(start, end) {
        var total = 0;
        for (var i = Math.max(1, start); i <= Math.min(83, end); i++) total += chaptersEstimate(i);
        return total;
    }

    /// Rough wall-clock estimate: per chapter ≈ delay + fetch/parse overhead,
    /// plus a per-book pause. Deliberately a touch conservative so an export
    /// tends to finish at or before the shown time rather than after.
    function estimateSeconds(chapters, books, delay) {
        return (chapters * (delay + 40) + books * CONFIG.bookDelay) / 1000;
    }

    /// Live "timp estimat" for BOTH the selected translation and the whole set,
    /// recomputed whenever the translation, book range, or delay changes.
    function updateEstimate() {
        var el = document.getElementById('exp-estimate');
        if (!el) return;
        var delay = parseInt(document.getElementById('exp-delay').value);
        if (isNaN(delay)) delay = CONFIG.chapterDelay;
        var s = parseInt(document.getElementById('exp-book-start').value) || 1;
        var e = parseInt(document.getElementById('exp-book-end').value) || 83;
        var translations = getAvailableTranslations();
        var sel = document.getElementById('exp-translation');
        var code = sel ? sel.value : '';

        var oneTxt = '—', label = 'selecție';
        if (code && translations[code]) {
            var r = translations[code].books || [1, 66];
            var bs = Math.max(s, r[0]), be = Math.min(e, r[1]);
            var oneBooks = Math.max(0, be - bs + 1);
            oneTxt = formatDuration(estimateSeconds(countChapters(bs, be), oneBooks, delay));
            label = translations[code].displayCode;
        }

        var allCh = 0, allBooks = 0, n = 0;
        for (var k in translations) {
            if (!translations.hasOwnProperty(k)) continue;
            n++;
            var rr = translations[k].books || [1, 66];
            var abs = Math.max(s, rr[0]), abe = Math.min(e, rr[1]);
            if (abe >= abs) { allCh += countChapters(abs, abe); allBooks += (abe - abs + 1); }
        }
        var allTxt = formatDuration(estimateSeconds(allCh, allBooks, delay));
        el.innerHTML = '⏱ Estimat: ~<b>' + oneTxt + '</b> pentru ' + label
                     + ' · ~<b>' + allTxt + '</b> pentru toate (' + n + ')';
    }

    function toggleMinimize() {
        document.getElementById('ebiblia-exporter-panel').classList.toggle('minimized');
    }

    function makeDraggable(el) {
        var header = el.querySelector('.exp-header');
        var isDragging = false, offsetX, offsetY;
        header.addEventListener('mousedown', function(e) {
            if (e.target.tagName === 'BUTTON') return;
            isDragging = true;
            var rect = el.getBoundingClientRect();
            offsetX = e.clientX - rect.left; offsetY = e.clientY - rect.top;
            el.style.transition = 'none';
        });
        document.addEventListener('mousemove', function(e) {
            if (!isDragging) return;
            el.style.left = (e.clientX - offsetX) + 'px';
            el.style.top = (e.clientY - offsetY) + 'px';
            el.style.right = 'auto'; el.style.bottom = 'auto';
        });
        document.addEventListener('mouseup', function() {
            isDragging = false; el.style.transition = 'all 0.3s ease';
        });
    }

    function populateTranslations() {
        var select = document.getElementById('exp-translation');
        var translations = getAvailableTranslations();
        select.innerHTML = '';

        var groups = {};
        for (var code in translations) {
            if (!translations.hasOwnProperty(code)) continue;
            var info = translations[code];
            var lang = info.lang || 'other';
            if (!groups[lang]) groups[lang] = [];
            groups[lang].push(info);
        }

        var langNames = {
            'ro': 'Română', 'en': 'English', 'de': 'Deutsch', 'fr': 'Français',
            'es': 'Español', 'it': 'Italiano', 'hu': 'Magyar', 'ru': 'Русский',
            'gr': 'Ελληνικά', 'ebr': 'עברית', 'lat': 'Latina', 'ukr': 'Українська',
            'nl': 'Nederlands', 'pg': 'Português', 'arab': 'العربية',
            'sb': 'Srpski', 'roma': 'Romani',
        };

        var langOrder = ['ro', 'en'];
        for (var l in groups) {
            if (groups.hasOwnProperty(l) && l !== 'ro' && l !== 'en') langOrder.push(l);
        }

        for (var li = 0; li < langOrder.length; li++) {
            var lang = langOrder[li];
            if (!groups[lang]) continue;
            var group = document.createElement('optgroup');
            group.label = langNames[lang] || lang.toUpperCase();

            var sorted = groups[lang].sort(function(a, b) { return a.code.localeCompare(b.code); });
            for (var si = 0; si < sorted.length; si++) {
                var info = sorted[si];
                var option = document.createElement('option');
                option.value = info.code;
                var bookRange = info.books ? ' [' + info.books[0] + '-' + info.books[1] + ']' : '';
                var incomplete = info.incomplete ? ' ⚠' : '';
                option.textContent = info.displayCode + bookRange + incomplete;
                if (info.code === 'vdcc') option.selected = true;
                group.appendChild(option);
            }
            select.appendChild(group);
        }
        updateEstimate();
    }

    // ═══════════════════════════════════════════════════════════════
    // LOG & UI UPDATE
    // ═══════════════════════════════════════════════════════════════

    /// Full session log — saved to disk per export (the panel shows only the
    /// last 300 lines; this buffer keeps everything for the .log.txt files).
    var logBuffer = [];

    function log(msg, type) {
        type = type || 'info';
        logBuffer.push('[' + new Date().toLocaleTimeString() + '] [' + (type || 'info').toUpperCase() + '] ' + msg);
        if (logBuffer.length > 100000) logBuffer.splice(0, 20000);
        var logEl = document.getElementById('exp-log');
        if (!logEl) return;
        logEl.classList.add('visible');
        var line = document.createElement('div');
        line.className = type;
        line.textContent = '[' + new Date().toLocaleTimeString() + '] ' + msg;
        logEl.appendChild(line);
        logEl.scrollTop = logEl.scrollHeight;
        while (logEl.children.length > 300) logEl.removeChild(logEl.firstChild);
    }

    function updateUI() {
        var s = exportState;
        var pct = s.totalChapters > 0 ? (s.completedChapters / s.totalChapters * 100) : 0;

        var el = function(id) { return document.getElementById(id); };

        var progressEl = el('exp-progress');
        if (progressEl) progressEl.style.width = pct.toFixed(1) + '%';

        var pctEl = el('exp-progress-pct');
        if (pctEl) pctEl.textContent = pct.toFixed(1) + '%';

        var booksEl = el('exp-books-count');
        if (booksEl) booksEl.textContent = s.completedBooks;

        var chaptersEl = el('exp-chapters-count');
        if (chaptersEl) chaptersEl.textContent = s.completedChapters;

        var versesEl = el('exp-verses-count');
        if (versesEl) versesEl.textContent = s.totalVerses.toLocaleString();

        var detailsEl = el('exp-details');
        if (detailsEl && (s.running || s.paused)) {
            detailsEl.style.display = 'grid';

            var curBookEl = el('exp-cur-book');
            if (curBookEl) curBookEl.textContent = s.currentBookName + ' (' + (s.completedBooks + 1) + '/' + s.totalBooks + ')';

            var curChapEl = el('exp-cur-chap');
            if (curChapEl) curChapEl.textContent = s.currentChapter + ' / ' + s.currentBookChapters;

            var curBkVsEl = el('exp-cur-book-verses');
            if (curBkVsEl) curBkVsEl.textContent = s.bookVerseCount.toLocaleString();

            var elapsed = (Date.now() - s.startTime) / 1000;
            var elapsedEl = el('exp-elapsed');
            if (elapsedEl) elapsedEl.textContent = formatDuration(elapsed);

            var etaEl = el('exp-eta');
            if (etaEl && s.completedChapters > 0) {
                var rate = elapsed / s.completedChapters;
                var remaining = (s.totalChapters - s.completedChapters) * rate;
                etaEl.textContent = formatDuration(remaining);
            }

            var sizeEl = el('exp-json-size');
            if (sizeEl && s.bibleData) {
                var approxSize = s.totalVerses * 120;
                sizeEl.textContent = '~' + formatSize(approxSize);
            }

            var errEl = el('exp-error-count');
            if (errEl) {
                errEl.textContent = s.errors.length;
                errEl.style.color = s.errors.length > 0 ? '#ffffff' : '#98989d';
            }
        }
    }

    function setStatus(msg) {
        var statusEl = document.getElementById('exp-status');
        if (statusEl) statusEl.textContent = msg;
    }

    function setButtonStates(running, paused, hasData) {
        var el = function(id) { return document.getElementById(id); };
        var startBtn = el('exp-start');
        var pauseBtn = el('exp-pause');
        var cancelBtn = el('exp-cancel');
        var downloadBtn = el('exp-download');
        var translationSelect = el('exp-translation');

        if (startBtn) startBtn.disabled = running;
        var startAllBtn = el('exp-start-all');
        if (startAllBtn) startAllBtn.disabled = running;
        if (pauseBtn) {
            pauseBtn.disabled = !running;
            pauseBtn.textContent = paused ? '▶ Reia' : '⏸ Pauză';
        }
        if (cancelBtn) cancelBtn.disabled = !running;
        if (downloadBtn) downloadBtn.disabled = !hasData;
        if (translationSelect) translationSelect.disabled = running;

        // Disable settings while running (they're read once at start)
        var settingsLocked = running;
        var bookStartEl = el('exp-book-start');
        var bookEndEl = el('exp-book-end');
        var delayEl = el('exp-delay');
        var chkRefs = el('exp-include-refs');
        var chkWoc = el('exp-include-woc');
        var chkMeta = el('exp-include-meta');
        var chkStrong = el('exp-include-strong');
        var chkRaw = el('exp-include-raw');
        var chkRawDump = el('exp-raw-dump');
        var chkLog = el('exp-save-log');

        if (bookStartEl) bookStartEl.disabled = settingsLocked;
        if (bookEndEl) bookEndEl.disabled = settingsLocked;
        if (delayEl) delayEl.disabled = settingsLocked;
        if (chkRefs) chkRefs.disabled = settingsLocked;
        if (chkWoc) chkWoc.disabled = settingsLocked;
        if (chkMeta) chkMeta.disabled = settingsLocked;
        if (chkStrong) chkStrong.disabled = settingsLocked;
        if (chkRaw) chkRaw.disabled = settingsLocked;
        if (chkRawDump) chkRawDump.disabled = settingsLocked;
        if (chkLog) chkLog.disabled = settingsLocked;
    }

    // ═══════════════════════════════════════════════════════════════
    // EXPORT ENGINE
    // ═══════════════════════════════════════════════════════════════

    /// Reads the shared export options from the panel (applied to every export).
    function readExportOptions() {
        var bookStart = parseInt(document.getElementById('exp-book-start').value) || 1;
        var bookEnd = parseInt(document.getElementById('exp-book-end').value) || 66;
        var delay = parseInt(document.getElementById('exp-delay').value) || CONFIG.chapterDelay;
        if (bookStart < 1 || bookEnd > 83 || bookStart > bookEnd) return null;
        var woc = document.getElementById('exp-include-woc');
        var meta = document.getElementById('exp-include-meta');
        var refs = document.getElementById('exp-include-refs');
        var strong = document.getElementById('exp-include-strong');
        var raw = document.getElementById('exp-include-raw');
        var dump = document.getElementById('exp-raw-dump');
        var slog = document.getElementById('exp-save-log');
        return {
            bookStart: bookStart, bookEnd: bookEnd, delay: delay,
            includeRefs: refs ? refs.checked : true,
            includeWoc: woc ? woc.checked : true,
            includeMeta: meta ? meta.checked : true,
            includeStrong: strong ? strong.checked : true,
            // Analysis extras — opt-in (off by default), separate sidecar files.
            includeRaw: raw ? raw.checked : false,
            rawDump: dump ? dump.checked : false,
            saveLog: slog ? slog.checked : false,
            stripDiacritics: false,
        };
    }

    /// Builds one GOAT verse object from a fetched verse `v` per the options.
    /// Uses parseRichVerse to emit runs[] carrying red-letter (woc), Strong's,
    /// morphology and interlinear glosses; routes section titles into
    /// `headingsOut`; flips exportState.hasWoc / hasStrong as it finds them.
    function buildVerseObject(v, opts, headingsOut) {
        var verse = { number: v.number, text: v.text };
        if (opts.includeRaw && v._rawHtml) verse.rawHtml = v._rawHtml;

        if (v._rawHtml && (opts.includeWoc || opts.includeStrong)) {
            var rich = parseRichVerse(v._rawHtml);
            var wantStrong = opts.includeStrong && rich.hasStrong;
            var wantWoc = opts.includeWoc && rich.hasWoc;
            // Interlinear text comes ONLY from <wd> tokens — cleanVerseText
            // can't reconstruct it — so always adopt the parser's text there.
            if (rich.mode === 'interlinear') verse.text = rich.text;
            if (wantStrong || wantWoc) {
                verse.text = rich.text;                       // keep text ↔ runs aligned
                verse.runs = wantStrong ? rich.runs : runsWocOnly(rich.runs);
                if (rich.hasWoc) { verse.hasWordsOfChrist = true; exportState.hasWoc = true; }
                if (wantStrong) {
                    exportState.hasStrong = true;
                    if (rich.gloss) verse.gloss = rich.gloss; // interlinear English gloss
                }
            }
        }

        if (opts.includeRefs && v._refEntries && v._refEntries.length > 0) {
            var refs = extractReferences(v._refEntries);
            if (refs.crossReferences.length > 0) verse.crossReferences = refs.crossReferences;
            if (refs.footnotes.length > 0) verse.footnotes = refs.footnotes;
            if (headingsOut && refs.titles.length > 0) {
                for (var ti = 0; ti < refs.titles.length; ti++) {
                    headingsOut.push({ beforeVerse: v.number, level: refs.titles[ti].level, text: refs.titles[ti].text });
                }
            }
        }
        return verse;
    }

    /// Core engine: exports ONE translation with the given options.
    /// Returns the bibleData (possibly partial when cancelled) or null when
    /// the translation has no books in the requested range.
    async function runTranslationExport(translationCode, opts) {
        var translations = getAvailableTranslations();
        var translationInfo = translations[translationCode] || {};
        var availableBooks = translationInfo.books || [1, 66];
        var effectiveStart = Math.max(opts.bookStart, availableBooks[0]);
        var effectiveEnd = Math.min(opts.bookEnd, availableBooks[1]);
        if (effectiveStart > effectiveEnd) return null;

        var totalChapters = 0;
        for (var b = effectiveStart; b <= effectiveEnd; b++) totalChapters += chaptersEstimate(b);

        var displayName = mapTranslationCode(translationCode);
        if (translationCode.toLowerCase() === 'vdcc') displayName = 'EDC100 (VDCC)';

        var win = unsafeWindow || window;
        var appBibles = win.app && win.app.BIBLES;
        var copyright = '', lang = 'ro';
        if (appBibles && appBibles[translationCode]) {
            copyright = appBibles[translationCode].copyright || '';
            lang = appBibles[translationCode].lang || 'ro';
            var tempDiv = document.createElement('div');
            tempDiv.innerHTML = copyright;
            copyright = tempDiv.textContent || tempDiv.innerText || '';
        }

        var langNames = {
            'ro': 'Română', 'en': 'English', 'de': 'Deutsch', 'fr': 'Français',
            'es': 'Español', 'it': 'Italiano', 'hu': 'Magyar', 'ru': 'Русский',
        };

        // Deuterocanon present (book index past 66) ⇒ orthodox canon.
        var canon = availableBooks[1] > 66 ? 'orthodox' : null;
        var incomplete = !!translationInfo.incomplete;

        // Enrich from eBiblia's "about" articles — full name + year, description,
        // copyright, source. Two cached key reads per translation; cheap.
        var meta = null;
        if (opts.includeMeta) {
            setStatus('ℹ ' + displayName + ': citesc metadatele…');
            try { meta = await fetchTranslationMeta(translationCode); } catch (e) { meta = null; }
        }
        var fullName = (meta && meta.fullName) ? meta.fullName : displayName;
        var langName = (meta && meta.languageName) || langNames[lang] || lang;

        exportState = {
            running: true, paused: false, cancelled: false,
            currentBook: 0, currentChapter: 0,
            currentBookName: '', currentBookChapters: 0,
            totalBooks: effectiveEnd - effectiveStart + 1,
            totalChapters: totalChapters,
            completedChapters: 0, completedBooks: 0,
            totalVerses: 0, errors: [],
            bookVerseCount: 0, hasWoc: false, hasStrong: false,
            startTime: Date.now(),
            bibleData: createBibleJSON(translationCode, {
                name: fullName, nameLocal: fullName,
                language: lang, languageName: langName,
                copyright: copyright || (meta && meta.copyright) || '',
                description: (meta && meta.description) || '',
                about: (meta && meta.foreword) || '',
                source: (meta && meta.source) || '',
                year: (meta && meta.year) || null,
                canon: canon, incomplete: incomplete,
            }),
        };

        log('═══ Export pornit: ' + displayName + ' ═══', 'info');
        log('Cărți: ' + effectiveStart + '–' + effectiveEnd + ' (' + exportState.totalBooks + ' cărți, ' + totalChapters + ' capitole)', 'info');

        var dateStr = new Date().toISOString().slice(0, 10);
        var safeCode = mapTranslationCode(translationCode).replace(/[^\w-]/g, '');
        var missingBooks = [];
        var retryList = [];
        var logStartIndex = logBuffer.length;
        if (opts.includeMeta) {
            if (meta && meta.fullName) log('🏷️ Metadate: ' + meta.fullName + (meta.year ? ' (' + meta.year + ')' : ''), 'ok');
            else log('⚠ Metadate indisponibile la sursă — folosesc codul „' + displayName + '”', 'warn');
        }
        // Raw-HTML dump: the entire Bible's source markup in one file — the
        // front matter (about + foreword/intros), then every chapter's verses.
        var frontMatterHtml = (meta && meta.aboutHtml)
            ? '<section class="front-matter">\n<h1>Prefață / Front matter</h1>\n' + meta.aboutHtml + '\n</section>\n'
            : '';
        var rawParts = opts.rawDump
            ? ['<!DOCTYPE html>\n<html lang="' + lang + '">\n<head><meta charset="utf-8"><title>'
               + displayName + ' — raw eBiblia dump ' + dateStr + '</title></head>\n<body>\n'
               + '<header><h1>' + displayName + '</h1><p>' + copyright.replace(/</g, '&lt;') + '</p></header>\n'
               + frontMatterHtml]
            : null;

        for (var bookNum = effectiveStart; bookNum <= effectiveEnd; bookNum++) {
            if (exportState.cancelled) break;

            // Canonical books have known chapter counts; beyond 66 (Orthodox
            // deuterocanon) we DISCOVER chapters until two consecutive misses.
            var knownChapters = chaptersFor(bookNum);
            var discovery = !knownChapters;
            var numChapters = knownChapters || 99;
            var consecutiveEmpty = 0;
            var bookData = createBookJSON(bookNum, knownChapters || 0);
            var bookName = BOOKS_RO[bookNum - 1] || ('Cartea ' + bookNum);

            exportState.currentBook = bookNum;
            exportState.currentBookName = bookName;
            exportState.currentBookChapters = knownChapters || '?';
            exportState.bookVerseCount = 0;

            // PROBE: incomplete translations (e.g. BDTE) miss entire books.
            // One quick attempt on chapters 1 and 2 — both empty means the
            // book doesn't exist here; skip it instead of retry-hammering
            // every chapter (~4s × N wasted before).
            var probeOK = false;
            for (var probeChap = 1; probeChap <= Math.min(2, numChapters) && !probeOK; probeChap++) {
                if (exportState.cancelled) break;
                setStatus('🔎 ' + displayName + ': verific ' + bookName + '…');
                try {
                    var probeVerses = await fetchChapter(translationCode, bookNum, probeChap);
                    if (probeVerses.length > 0) probeOK = true;
                } catch (e) { /* counts as empty */ }
                if (!probeOK) await sleep(200);
            }
            if (!probeOK) {
                missingBooks.push(bookName);
                exportState.completedChapters += numChapters; // keep progress honest
                log('↷ ' + bookNum + '. ' + bookName + ' — indisponibilă în ' + displayName + ', omisă', 'warn');
                updateUI();
                continue;
            }

            var rawBookParts = opts.rawDump
                ? ['<section data-book="' + bookNum + '" data-name="' + bookName + '">\n<h1>' + bookNum + '. ' + bookName + '</h1>\n']
                : null;

            log('📖 ' + bookNum + '. ' + bookName + ' — ' + numChapters + ' capitole', 'info');

            for (var chap = 1; chap <= numChapters; chap++) {
                while (exportState.paused && !exportState.cancelled) {
                    setStatus('⏸ Pauză — ' + bookName + ' cap. ' + chap + '/' + numChapters + ' | Total: ' + exportState.totalVerses.toLocaleString() + ' versete');
                    await sleep(500);
                }
                if (exportState.cancelled) break;

                exportState.currentChapter = chap;
                setStatus('📖 ' + displayName + ': ' + bookName + ' — cap. ' + chap + '/' + numChapters);
                updateUI();

                var verses = [];
                var attempts = 0;
                var success = false;
                var maxAttempts = discovery ? 1 : CONFIG.maxRetries;

                while (attempts < maxAttempts && !success) {
                    try {
                        verses = await fetchChapter(translationCode, bookNum, chap);
                        if (verses.length > 0) {
                            success = true;
                        } else {
                            attempts++;
                            if (attempts < CONFIG.maxRetries) {
                                log('⚠ ' + bookName + ' ' + chap + ': 0 versete, reîncercare ' + attempts + '/' + CONFIG.maxRetries + '...', 'warn');
                                await sleep(CONFIG.retryDelay);
                            }
                        }
                    } catch(err) {
                        attempts++;
                        log('⚠ ' + bookName + ' ' + chap + ': ' + err.message + ' (încercare ' + attempts + '/' + CONFIG.maxRetries + ')', 'err');
                        if (attempts < CONFIG.maxRetries) await sleep(CONFIG.retryDelay);
                    }
                }

                if (verses.length === 0) {
                    if (discovery) {
                        consecutiveEmpty++;
                        if (consecutiveEmpty >= 2) {
                            log('🏁 ' + bookName + ': ' + bookData.chapters.length + ' capitole descoperite', 'info');
                            break;
                        }
                    } else {
                        log('❌ ' + bookName + ' cap. ' + chap + ': 0 versete — OMIS (reîncerc la final)', 'err');
                        exportState.errors.push(bookName + ' ' + chap);
                        retryList.push({ bookNum: bookNum, chap: chap, bookName: bookName });
                    }
                } else {
                    consecutiveEmpty = 0;
                    // Build chapter verses with optional extra fields
                    // Collect headings separately at chapter level
                    var chapterHeadings = [];
                    var chapterVerses = verses.map(function(v) {
                        return buildVerseObject(v, opts, chapterHeadings);
                    });

                    var chapterObj = {
                        number: chap,
                        verses: chapterVerses,
                        _extensions: {}
                    };
                    // Only add headings array if there are any
                    if (opts.includeRefs && chapterHeadings.length > 0) {
                        chapterObj.headings = chapterHeadings;
                    }
                    bookData.chapters.push(chapterObj);

                    if (rawBookParts) {
                        var rawChapter = ['<article data-chapter="' + chap + '">\n<h2>' + bookName + ' ' + chap + '</h2>\n'];
                        for (var rvi = 0; rvi < verses.length; rvi++) {
                            rawChapter.push('<p class="v" data-verse="' + verses[rvi].number + '">' + (verses[rvi]._rawHtml || verses[rvi].text) + '</p>\n');
                        }
                        rawChapter.push('</article>\n');
                        rawBookParts.push(rawChapter.join(''));
                    }

                    exportState.totalVerses += verses.length;
                    exportState.bookVerseCount += verses.length;

                    if (chap % 10 === 0 || chap === numChapters || numChapters <= 5) {
                        log('  cap. ' + chap + '/' + numChapters + ': ' + verses.length + ' vs → total carte: ' + exportState.bookVerseCount, 'data');
                    }
                }

                exportState.completedChapters++;
                updateUI();

                if (chap < numChapters || bookNum < effectiveEnd) {
                    await sleep(opts.delay);
                }
            }

            if (discovery) {
                bookData.expectedChapters = bookData.chapters.length;
                exportState.totalChapters += bookData.chapters.length - chaptersEstimate(bookNum);
            }

            if (!exportState.cancelled && bookData.chapters.length > 0) {
                exportState.bibleData.books.push(bookData);
                exportState.completedBooks++;
                log('✅ ' + bookName + ': ' + bookData.chapters.length + ' cap., ' + exportState.bookVerseCount.toLocaleString() + ' versete', 'ok');

                if (rawBookParts) {
                    rawBookParts.push('</section>\n');
                    rawParts.push(rawBookParts.join(''));
                }

            } else if (!exportState.cancelled) {
                missingBooks.push(bookName);
                log('↷ ' + bookName + ': niciun capitol valid — omisă din JSON', 'warn');
            }

            if (bookNum < effectiveEnd && !exportState.cancelled) {
                await sleep(CONFIG.bookDelay);
            }
        }

        // ── Recovery pass: transient 0-verse fetches (a momentary server
        // hiccup on a chapter that really exists) are retried once more here,
        // slower, and slotted back into their book. This is what fixes the
        // odd missing Proverbs/Daniel chapter on a fast run.
        if (!exportState.cancelled && retryList.length > 0) {
            log('🔁 Recuperare: reîncerc ' + retryList.length + ' capitole omise…', 'info');
            for (var ri = 0; ri < retryList.length; ri++) {
                if (exportState.cancelled) break;
                var item = retryList[ri];
                setStatus('🔁 Recuperare ' + item.bookName + ' ' + item.chap + ' (' + (ri + 1) + '/' + retryList.length + ')');
                var rverses = [];
                for (var ra = 0; ra < CONFIG.maxRetries && rverses.length === 0; ra++) {
                    try { rverses = await fetchChapter(translationCode, item.bookNum, item.chap); } catch (e) {}
                    if (rverses.length === 0) await sleep(CONFIG.retryDelay);
                }
                if (rverses.length === 0) {
                    log('❌ Tot gol după recuperare: ' + item.bookName + ' ' + item.chap + ' — lipsește la sursă (eBiblia)', 'err');
                    continue;
                }

                var rHeadings = [];
                var rverseObjs = rverses.map(function(v) {
                    return buildVerseObject(v, opts, rHeadings);
                });
                var tgt = null;
                for (var bi = 0; bi < exportState.bibleData.books.length; bi++) {
                    if (exportState.bibleData.books[bi].number === item.bookNum) { tgt = exportState.bibleData.books[bi]; break; }
                }
                if (!tgt) continue;
                var rChap = { number: item.chap, verses: rverseObjs, _extensions: {} };
                if (opts.includeRefs && rHeadings.length > 0) rChap.headings = rHeadings;
                tgt.chapters.push(rChap);
                tgt.chapters.sort(function(a, b) { return a.number - b.number; });
                exportState.totalVerses += rverses.length;
                exportState.completedChapters++;
                exportState.errors = exportState.errors.filter(function(e) { return e !== item.bookName + ' ' + item.chap; });
                log('✅ Recuperat ' + item.bookName + ' ' + item.chap + ': ' + rverses.length + ' versete', 'ok');
                await sleep(opts.delay);
            }
        }

        exportState.running = false;

        // ACTUAL counts (recomputed from the data) — not "attempted". The
        // discovery probes and skipped chapters used to inflate these.
        var actualChapters = 0, actualVerses = 0;
        for (var fi = 0; fi < exportState.bibleData.books.length; fi++) {
            var fb = exportState.bibleData.books[fi];
            actualChapters += fb.chapters.length;
            for (var fc = 0; fc < fb.chapters.length; fc++) actualVerses += fb.chapters[fc].verses.length;
        }
        exportState.completedChapters = actualChapters;
        exportState.totalVerses = actualVerses;
        exportState.bibleData.exportInfo.totalBooks = exportState.bibleData.books.length;
        exportState.bibleData.exportInfo.totalChapters = actualChapters;
        exportState.bibleData.exportInfo.totalVerses = actualVerses;
        // Promote the run's discoveries onto the translation flags.
        exportState.bibleData.translation.hasWordsOfChrist = !!exportState.hasWoc;
        exportState.bibleData.translation.hasStrongs = !!exportState.hasStrong;
        if (exportState.hasWoc) log('✝ Cuvintele lui Isus (text roșu) detectate și marcate', 'ok');
        if (exportState.hasStrong) log('🔢 Strong\x27s + morfologie detectate și marcate', 'ok');
        if (missingBooks.length > 0) {
            exportState.bibleData.exportInfo.missingBooks = missingBooks;
        }

        // Classify whatever is STILL missing: a gap is "versification" when it's
        // only the last chapter of a known book (e.g. Maleahi 4 — that Bible
        // numbers Malachi as 3 chapters). Anything mid-book is a REAL gap
        // (missing at eBiblia's source), which a re-run will NOT fix.
        var realGaps = [], versification = [];
        for (var ei = 0; ei < exportState.errors.length; ei++) {
            var parts = exportState.errors[ei].split(' ');
            var chNo = parseInt(parts.pop(), 10);
            var bName = parts.join(' ');
            var bObj = null;
            for (var bj = 0; bj < exportState.bibleData.books.length; bj++) {
                if ((BOOKS_RO[exportState.bibleData.books[bj].number - 1] || '') === bName) { bObj = exportState.bibleData.books[bj]; break; }
            }
            var known = bObj ? chaptersFor(bObj.number) : null;
            if (known && chNo === known && bObj.chapters.length === known - 1) {
                versification.push(exportState.errors[ei]);
            } else {
                realGaps.push(exportState.errors[ei]);
            }
        }
        if (realGaps.length > 0) exportState.bibleData.exportInfo.missingChapters = realGaps;
        if (versification.length > 0) exportState.bibleData.exportInfo.versificationChapters = versification;
        exportState._realGaps = realGaps;
        exportState._versification = versification;
        if (realGaps.length > 0) log('⚠ Capitole lipsă REAL (la sursă): ' + realGaps.join(', '), 'err');
        if (versification.length > 0) log('ℹ Diferență de versificare (normal): ' + versification.join(', '), 'info');

        // The continuous raw-HTML dump of everything that was fetched.
        if (rawParts && !exportState.cancelled && exportState.bibleData.books.length > 0) {
            rawParts.push('</body>\n</html>\n');
            var rawDoc = rawParts.join('');
            saveFile(rawDoc, languageFolder(lang) + '/' + safeCode + '_' + dateStr + '_raw.html', 'text/html');
            log('🧬 HTML brut: ' + formatSize(rawDoc.length) + ' salvat', 'ok');
        }

        // Persist the run's log next to the JSON (opt-in) — the gap report +
        // full debug transcript. Summary first, full transcript after.
        if (opts.saveLog && !exportState.cancelled && (exportState.bibleData.books.length > 0 || exportState.errors.length > 0)) {
            var summary = [
                '═══ ' + displayName + ' — export ' + dateStr + ' (exporter 1.15.0) ═══',
                'Cărți: ' + exportState.bibleData.books.length + ' | Capitole: ' + exportState.completedChapters + ' | Versete: ' + exportState.totalVerses,
                'Capitole lipsă REAL la sursă (' + (exportState._realGaps || []).length + '): ' + ((exportState._realGaps || []).join(', ') || '—'),
                'Diferențe de versificare, normale (' + (exportState._versification || []).length + '): ' + ((exportState._versification || []).join(', ') || '—'),
                'Cărți indisponibile (' + missingBooks.length + '): ' + (missingBooks.join(', ') || '—'),
                '',
                '── Jurnal complet ──',
            ];
            saveFile(
                summary.concat(logBuffer.slice(logStartIndex)).join('\n'),
                languageFolder(lang) + '/' + safeCode + '_' + dateStr + '_log.txt',
                'text/plain'
            );
        }
        return exportState.bibleData;
    }

    /// Final UI touches shared by both entry points.
    function finishExportUI(elapsed) {
        var detailsEl = document.getElementById('exp-details');
        if (detailsEl) detailsEl.style.display = 'grid';

        var sizeEl = document.getElementById('exp-json-size');
        if (sizeEl && exportState.bibleData) {
            try {
                var realSize = JSON.stringify(exportState.bibleData).length;
                sizeEl.textContent = formatSize(realSize);
            } catch(e) { sizeEl.textContent = '?'; }
        }

        var etaEl = document.getElementById('exp-eta');
        if (etaEl) etaEl.textContent = exportState.cancelled ? 'anulat' : 'terminat';

        var elapsedEl = document.getElementById('exp-elapsed');
        if (elapsedEl) elapsedEl.textContent = formatDuration(elapsed);

        var hasData = exportState.bibleData && exportState.bibleData.books.length > 0;
        setButtonStates(false, false, hasData);
        updateUI();
    }

    async function startExport() {
        var translationCode = document.getElementById('exp-translation').value;
        if (!translationCode) { setStatus('⚠ Selectează o traducere!'); return; }

        var opts = readExportOptions();
        if (!opts) { setStatus('⚠ Interval cărți invalid (1-83)!'); return; }

        var displayName = mapTranslationCode(translationCode);
        setButtonStates(true, false, false);
        log('Opțiuni: Text roșu=' + opts.includeWoc + ', Referințe=' + opts.includeRefs + ', Metadate=' + opts.includeMeta + ', Strong=' + opts.includeStrong + ', Delay=' + opts.delay + 'ms', 'info');

        var data = await runTranslationExport(translationCode, opts);
        var elapsed = (Date.now() - exportState.startTime) / 1000;

        if (data === null) {
            setStatus('⚠ Traducerea ' + displayName + ' nu are cărți în intervalul ales!');
            setButtonStates(false, false, false);
            return;
        }

        if (exportState.cancelled) {
            setStatus('❌ Export anulat. ' + exportState.completedBooks + ' cărți, ' + exportState.totalVerses.toLocaleString() + ' versete salvate.');
            log('Export anulat după ' + formatDuration(elapsed), 'err');
        } else {
            var rg = (exportState._realGaps || []).length;
            var errMsg = rg > 0 ? ' | ⚠ ' + rg + ' capitole lipsă la sursă' : ' | fără lipsuri reale';
            setStatus('✅ Complet! ' + exportState.completedBooks + ' cărți, ' + exportState.completedChapters + ' cap., ' + exportState.totalVerses.toLocaleString() + ' versete' + errMsg + ' | ' + formatDuration(elapsed));
            log('═══ Export finalizat în ' + formatDuration(elapsed) + ' ═══', 'ok');
            // Auto-save through the SAME spaced queue as the .html/.log sidecars
            // (a direct download here fires simultaneously and Safari drops one).
            // The ⬇ JSON button stays available for a manual re-download.
            if (exportState.bibleData && exportState.bibleData.books.length > 0) {
                exportState.bibleData.exportInfo.exportDate = new Date().toISOString();
                var autoJson = JSON.stringify(exportState.bibleData, null, 2);
                var autoName = bibleFilename(exportState.bibleData, false);
                saveFile(autoJson, autoName, 'application/json');
                log('⬇ ' + autoName + ' — ' + formatSize(autoJson.length) + ' (în coadă)', 'ok');
            }
        }
        finishExportUI(elapsed);
    }

    // ═══════════════════════════════════════════════════════════════
    // EXPORT ALL — every translation, one file each, foldered per language
    // ═══════════════════════════════════════════════════════════════

    // Safari's Tampermonkey has no working GM_download and no subfolder
    // support — there, EVERY file goes through a plain <a download> with the
    // folder flattened into the name. Downloads are queued with spacing so
    // Safari doesn't silently drop back-to-back automatic downloads.
    var IS_SAFARI = /apple/i.test(navigator.vendor || '');
    var downloadQueue = [];
    var downloadPumpRunning = false;

    function pumpDownloads() {
        if (downloadPumpRunning) return;
        downloadPumpRunning = true;
        var next = function() {
            var item = downloadQueue.shift();
            if (!item) { downloadPumpRunning = false; return; }
            performDownload(item.content, item.path, item.mime);
            setTimeout(next, 1100); // spacing so Safari doesn't drop back-to-back downloads
        };
        next();
    }

    function performDownload(content, path, mime) {
        var blob = new Blob([content], { type: (mime || 'application/json') + ';charset=utf-8' });
        var url = URL.createObjectURL(blob);

        var anchorSave = function() {
            var a = document.createElement('a');
            a.href = url; a.download = path.replace(/\//g, '_');
            a.style.display = 'none';
            document.body.appendChild(a);
            a.click();
            document.body.removeChild(a);
            setTimeout(function() { URL.revokeObjectURL(url); }, 30000);
        };

        // Safari: GM_download swallows files silently — never use it there.
        if (!IS_SAFARI && typeof GM_download === 'function') {
            try {
                GM_download({
                    url: url,
                    name: path,
                    saveAs: false,
                    onload: function() { setTimeout(function() { URL.revokeObjectURL(url); }, 30000); },
                    onerror: function(e) {
                        log('⚠ GM_download a refuzat calea (' + (e && e.error) + ') — salvez plat', 'warn');
                        anchorSave();
                    },
                });
            } catch (e) { anchorSave(); }
        } else {
            anchorSave();
        }
    }

    var safariHintShown = false;
    function saveFile(content, path, mime) {
        if (IS_SAFARI && !safariHintShown) {
            safariHintShown = true;
            log('ℹ Safari: aprobă „Permite descărcări multiple” când întreabă — fișierele vin plate în Downloads (Safari nu poate crea foldere)', 'info');
        }
        downloadQueue.push({ content: content, path: path, mime: mime });
        pumpDownloads();
    }

    function languageFolder(langCode) {
        return 'TopPresenter Bibles/' + (LANG_FOLDERS[langCode] || (langCode || 'xx').toUpperCase());
    }

    /// Standard library filename: "<CODE> — <Full Name>.json" (provenance lives
    /// in exportInfo.exportDate, so no date in the name). Falls back to the bare
    /// code when no confident full name is known.
    function bibleFilename(data, partial) {
        var code = (data.translation.code || 'bible').replace(/[^\w-]/g, '');
        var name = (data.translation.name || '').replace(/[\/\\:*?"<>|]/g, ' ').replace(/\s+/g, ' ').trim();
        var base = (name && name.toUpperCase() !== code.toUpperCase()) ? (code + ' — ' + name) : code;
        if (partial) base += ' (partial)';
        if (base.length > 120) base = base.slice(0, 120).trim();
        return base + '.json';
    }

    /// Serializes a finished export and saves it under
    /// "TopPresenter Bibles/<Language>/<CODE> — <Full Name>.json".
    function downloadTranslationFile(data, langCode) {
        data.exportInfo.exportDate = new Date().toISOString();
        if (exportState.errors.length > 0) {
            data.exportInfo.skippedChapters = exportState.errors.slice();
        }

        var jsonStr = JSON.stringify(data, null, 2);
        var fullPath = languageFolder(langCode) + '/' + bibleFilename(data, false);

        saveFile(jsonStr, fullPath, 'application/json');
        log('⬇ ' + fullPath + ' — ' + formatSize(jsonStr.length) + ', ' + data.books.length + ' cărți, ' + data.exportInfo.totalVerses.toLocaleString() + ' versete', 'ok');
        return fullPath;
    }

    function setBatchStatus(text) {
        var el = document.getElementById('exp-batch-status');
        if (!el) return;
        el.style.display = text ? 'block' : 'none';
        el.textContent = text || '';
    }

    async function startExportAll() {
        var opts = readExportOptions();
        if (!opts) { setStatus('⚠ Interval cărți invalid (1-83)!'); return; }

        var translations = getAvailableTranslations();
        var codes = Object.keys(translations).sort(function(a, b) {
            // ro first, then en, then the rest — same order as the picker
            var rank = function(c) {
                var l = translations[c].lang || 'zz';
                return (l === 'ro' ? '0' : l === 'en' ? '1' : '2' + l) + c;
            };
            return rank(a).localeCompare(rank(b));
        });

        if (codes.length === 0) { setStatus('⚠ Nicio traducere disponibilă!'); return; }

        var totalChapters = 0, totalBooks = 0;
        for (var i = 0; i < codes.length; i++) {
            var range = translations[codes[i]].books || [1, 66];
            var bs = Math.max(opts.bookStart, range[0]), be = Math.min(opts.bookEnd, range[1]);
            if (be >= bs) { totalChapters += countChapters(bs, be); totalBooks += (be - bs + 1); }
        }
        var estSeconds = estimateSeconds(totalChapters, totalBooks, opts.delay);
        if (!confirm('Export TOATE cele ' + codes.length + ' traduceri?\n\n~' + totalChapters.toLocaleString()
                     + ' capitole în total, estimat ' + formatDuration(estSeconds)
                     + '.\nFiecare traducere se descarcă automat în „TopPresenter Bibles/<limbă>/”.')) {
            return;
        }

        batchState = { active: true, cancelled: false, index: 0, total: codes.length, done: [], failed: [] };
        setButtonStates(true, false, false);
        var batchStart = Date.now();
        log('═══════ EXPORT TOATE: ' + codes.length + ' traduceri ═══════', 'info');

        for (var ti = 0; ti < codes.length; ti++) {
            if (batchState.cancelled) break;
            var code = codes[ti];
            batchState.index = ti + 1;
            var label = translations[code].displayCode + ' (' + (translations[code].lang || '?') + ')';
            setBatchStatus('⏬ [' + batchState.index + '/' + batchState.total + '] ' + label
                           + ' — gata: ' + batchState.done.length + ', eșuate: ' + batchState.failed.length);

            try {
                var data = await runTranslationExport(code, opts);
                // On Stop: keep the partial data for the manual ⬇ JSON button,
                // but don't auto-save an incomplete file.
                if (batchState.cancelled) break;

                if (data && data.books.length > 0) {
                    var path = downloadTranslationFile(data, translations[code].lang || 'ro');
                    batchState.done.push(path);
                } else if (data === null) {
                    log('↷ ' + label + ': fără cărți în intervalul ales — omis', 'warn');
                } else {
                    batchState.failed.push(code);
                }
            } catch (err) {
                log('❌ ' + label + ': ' + err.message + ' — trec mai departe', 'err');
                batchState.failed.push(code);
            }

            if (ti < codes.length - 1 && !batchState.cancelled) {
                await sleep(CONFIG.bookDelay * 2);
            }
        }

        var elapsed = (Date.now() - batchStart) / 1000;
        batchState.active = false;
        setBatchStatus('');

        if (batchState.cancelled) {
            setStatus('❌ Export-toate oprit: ' + batchState.done.length + ' traduceri descărcate.');
            log('Export-toate anulat după ' + formatDuration(elapsed) + ' — ' + batchState.done.length + ' fișiere salvate', 'err');
        } else {
            var failMsg = batchState.failed.length > 0 ? ' | eșuate: ' + batchState.failed.join(', ') : '';
            setStatus('✅ Toate gata! ' + batchState.done.length + '/' + batchState.total + ' traduceri descărcate' + failMsg + ' | ' + formatDuration(elapsed));
            log('═══════ EXPORT TOATE finalizat în ' + formatDuration(elapsed) + ': '
                + batchState.done.length + '/' + batchState.total + ' traduceri' + failMsg + ' ═══════', 'ok');
        }
        finishExportUI(elapsed);
    }

    function togglePause() {
        exportState.paused = !exportState.paused;
        var hasPartialData = exportState.bibleData && exportState.bibleData.books.length > 0;

        // When paused with data, allow download; when resumed, disable download
        setButtonStates(true, exportState.paused, exportState.paused && hasPartialData);

        if (exportState.paused) {
            log('⏸ Pauză activată — poți descărca datele parțiale', 'warn');
            setStatus('⏸ Pauză — ' + exportState.completedBooks + ' cărți, ' + exportState.totalVerses.toLocaleString() + ' versete. Poți descărca.');
        } else {
            log('▶ Export continuat', 'info');
        }
    }

    function cancelExport() {
        exportState.cancelled = true;
        batchState.cancelled = true;
        exportState.paused = false;
        var hasData = exportState.bibleData && exportState.bibleData.books.length > 0;
        setButtonStates(false, false, hasData);
        if (hasData) {
            log('Export oprit. ' + exportState.bibleData.books.length + ' cărți disponibile pentru descărcare.', 'warn');
        }
    }

    function downloadJSON() {
        if (!exportState.bibleData || exportState.bibleData.books.length === 0) {
            setStatus('⚠ Nu sunt date de descărcat!');
            return;
        }

        var data = JSON.parse(JSON.stringify(exportState.bibleData));

        var actualVerses = 0, actualChapters = 0;
        for (var bi = 0; bi < data.books.length; bi++) {
            var book = data.books[bi];
            actualChapters += book.chapters.length;
            for (var ci = 0; ci < book.chapters.length; ci++) {
                actualVerses += book.chapters[ci].verses.length;
            }
        }

        data.exportInfo.totalBooks = data.books.length;
        data.exportInfo.totalChapters = actualChapters;
        data.exportInfo.totalVerses = actualVerses;
        data.exportInfo.exportDate = new Date().toISOString();

        if (exportState.running || exportState.paused) {
            data.exportInfo.partial = true;
            data.exportInfo.note = 'Partial export — not all books were downloaded';
        }

        var jsonStr = JSON.stringify(data, null, 2);
        var blob = new Blob([jsonStr], { type: 'application/json;charset=utf-8' });
        var url = URL.createObjectURL(blob);

        var filename = bibleFilename(data, !!data.exportInfo.partial);

        var a = document.createElement('a');
        a.href = url; a.download = filename; a.style.display = 'none';
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
        URL.revokeObjectURL(url);

        log('⬇ ' + filename + ' — ' + formatSize(jsonStr.length) + ', ' + data.books.length + ' cărți, ' + actualVerses.toLocaleString() + ' versete', 'ok');
        setStatus('⬇ Descărcat: ' + filename + ' (' + formatSize(jsonStr.length) + ')');
    }

    // ═══════════════════════════════════════════════════════════════
    // INITIALIZATION
    // ═══════════════════════════════════════════════════════════════

    function init() {
        var checkReady = function() {
            var win = unsafeWindow || window;
            if (win.app && win.N) {
                console.log('[eBiblia Exporter] App and N module detected, initializing UI...');
                createUI();
            } else {
                console.log('[eBiblia Exporter] Waiting for app to load...');
                setTimeout(checkReady, 2000);
            }
        };

        if (document.readyState === 'complete') {
            setTimeout(checkReady, 3000);
        } else {
            window.addEventListener('load', function() { setTimeout(checkReady, 3000); });
        }
    }

    init();
})();

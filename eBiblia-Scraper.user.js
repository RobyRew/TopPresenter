// ==UserScript==
// @name         eBiblia Bible Exporter
// @namespace    https://ebiblia.ro
// @version      1.4.0
// @description  Export Bible translations from eBiblia.ro to extensible JSON format for TopPresenter
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
        chapterDelay: 800,
        bookDelay: 1500,
        maxRetries: 3,
        retryDelay: 2000,
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
        div.innerHTML = html;
        div.querySelectorAll('sr, mf, .sr, .xSym, .fSym, .x, .f, .cmp1, .cmp2, .cmp3, .tp, .noCopy, script').forEach(function(el) { el.remove(); });
        var text = div.textContent || div.innerText || '';
        // Strip cross-reference markers (*) and footnote markers (%) from text
        text = text.replace(/[*%^]/g, '');
        text = text.replace(/\s+/g, ' ').trim();
        return text;
    }

    function removeDiacritics(text) {
        if (!text) return '';
        return text
            .replace(/[ăâ]/g, 'a').replace(/[ĂÂ]/g, 'A')
            .replace(/[îÎ]/g, 'i')
            .replace(/[șş]/g, 's').replace(/[ȘŞ]/g, 'S')
            .replace(/[țţ]/g, 't').replace(/[ȚŢ]/g, 'T');
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
                    result.crossReferences.push({ references: refs });
                }
            } else if (entry.type === 'f') {
                // Footnote: may contain HTML markup (<em>, <b>, etc.)
                // Keep the HTML for rawHtml consumers, provide clean text too
                var noteClean = raw.replace(/<[^>]*>/g, '').replace(/\s+/g, ' ').trim();
                if (noteClean) {
                    result.footnotes.push({ text: noteClean, html: raw });
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
                year: metadata.year || null,
                direction: metadata.direction || 'ltr',
            },
            exportInfo: {
                source: 'eBiblia.ro',
                exportDate: new Date().toISOString(),
                exporterVersion: '1.4.0',
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
            name: BOOKS_RO[idx] || ('Book ' + bookNumber),
            nameEnglish: BOOKS_EN[idx] || ('Book ' + bookNumber),
            abbreviation: SBOOKS_RO[idx] || '',
            abbreviationEnglish: SBOOKS_EN[idx] || '',
            testament: bookNumber <= 39 ? 'OT' : 'NT',
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

    function createUI() {
        if (document.getElementById('ebiblia-exporter-panel')) return;
        var panel = document.createElement('div');
        panel.id = 'ebiblia-exporter-panel';
        panel.innerHTML = '\
<style>\
#ebiblia-exporter-panel{position:fixed;bottom:20px;right:20px;width:400px;background:#1a1a2e;color:#e0e0e0;border-radius:12px;box-shadow:0 8px 32px rgba(0,0,0,0.4);z-index:999999;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;font-size:13px;overflow:hidden;transition:all .3s ease}\
#ebiblia-exporter-panel.minimized{width:48px;height:48px;border-radius:50%;cursor:pointer}\
#ebiblia-exporter-panel.minimized .exp-body{display:none}\
#ebiblia-exporter-panel.minimized .exp-header{padding:12px;justify-content:center}\
#ebiblia-exporter-panel.minimized .exp-header span,#ebiblia-exporter-panel.minimized .exp-minimize{display:none}\
.exp-header{background:#16213e;padding:10px 14px;display:flex;align-items:center;justify-content:space-between;cursor:move;border-bottom:1px solid #0f3460}\
.exp-header span{font-weight:600;font-size:14px;color:#e94560}\
.exp-minimize{cursor:pointer;color:#aaa;font-size:18px;background:none;border:none;padding:0 4px}\
.exp-minimize:hover{color:#fff}\
.exp-body{padding:14px}\
.exp-row{margin-bottom:10px}\
.exp-label{display:block;font-size:11px;color:#888;margin-bottom:4px;text-transform:uppercase;letter-spacing:.5px}\
.exp-select,.exp-input{width:100%;padding:8px 10px;background:#0f3460;border:1px solid #1a1a5e;border-radius:6px;color:#e0e0e0;font-size:13px;outline:none;box-sizing:border-box}\
.exp-select:focus,.exp-input:focus{border-color:#e94560}\
.exp-progress-bar{width:100%;height:8px;background:#0f3460;border-radius:4px;overflow:hidden;margin:8px 0}\
.exp-progress-fill{height:100%;width:0%;background:linear-gradient(90deg,#e94560,#ff6b6b);transition:width .3s ease;border-radius:4px}\
.exp-status{font-size:12px;color:#ccc;min-height:18px;margin-bottom:6px;word-break:break-word;line-height:1.4}\
.exp-detail-grid{display:grid;grid-template-columns:1fr 1fr;gap:4px 12px;margin-bottom:10px;font-size:12px;color:#aaa}\
.exp-detail-grid .exp-dv{color:#e0e0e0;font-weight:600;text-align:right}\
.exp-stats{display:grid;grid-template-columns:1fr 1fr 1fr 1fr;gap:6px;margin-bottom:10px}\
.exp-stat{background:#0f3460;border-radius:6px;padding:6px 4px;text-align:center}\
.exp-stat-val{font-size:15px;font-weight:700;color:#e94560}\
.exp-stat-label{font-size:9px;color:#888;text-transform:uppercase}\
.exp-buttons{display:flex;gap:8px}\
.exp-btn{flex:1;padding:9px 8px;border:none;border-radius:6px;font-size:12px;font-weight:600;cursor:pointer;transition:all .2s ease}\
.exp-btn:disabled{opacity:.4;cursor:not-allowed}\
.exp-btn-primary{background:#e94560;color:#fff}\
.exp-btn-primary:hover:not(:disabled){background:#d63851}\
.exp-btn-secondary{background:#0f3460;color:#e0e0e0}\
.exp-btn-secondary:hover:not(:disabled){background:#1a1a5e}\
.exp-btn-success{background:#2ecc71;color:#fff}\
.exp-btn-success:hover:not(:disabled){background:#27ae60}\
.exp-btn-danger{background:#c0392b;color:#fff}\
.exp-btn-danger:hover:not(:disabled){background:#a93226}\
.exp-options{margin-bottom:10px}\
.exp-checkbox-row{display:flex;align-items:center;gap:6px;margin-bottom:4px;cursor:pointer}\
.exp-checkbox-row input[type="checkbox"]{accent-color:#e94560;cursor:pointer;width:16px;height:16px;flex-shrink:0}\
.exp-checkbox-row label{cursor:pointer;user-select:none;font-size:12px;color:#ccc}\
.exp-range-row{display:flex;gap:8px;align-items:center}\
.exp-range-row .exp-input{width:70px;text-align:center}\
.exp-range-row span{color:#888}\
.exp-log{max-height:120px;overflow-y:auto;background:#0a0a1a;border-radius:6px;padding:6px 8px;font-family:Menlo,Consolas,monospace;font-size:11px;color:#666;margin-top:8px;display:none}\
.exp-log.visible{display:block}\
.exp-log .err{color:#e94560}.exp-log .ok{color:#2ecc71}.exp-log .info{color:#3498db}.exp-log .warn{color:#f39c12}.exp-log .data{color:#9b59b6}\
.exp-separator{border:none;border-top:1px solid #0f3460;margin:10px 0}\
</style>\
<div class="exp-header">\
<span>📖 eBiblia Exporter</span>\
<button class="exp-minimize" id="exp-toggle-min" title="Minimize">−</button>\
</div>\
<div class="exp-body">\
<div class="exp-row"><label class="exp-label">Traducere / Translation</label><select class="exp-select" id="exp-translation"><option value="">Se încarcă...</option></select></div>\
<div class="exp-options"><label class="exp-label">Interval cărți / Book Range</label><div class="exp-range-row"><input type="number" class="exp-input" id="exp-book-start" min="1" max="66" value="1"><span>→</span><input type="number" class="exp-input" id="exp-book-end" min="1" max="66" value="66"><span class="exp-label" style="margin:0;white-space:nowrap" id="exp-range-info">= 1189 cap.</span></div></div>\
<div class="exp-options">\
<label class="exp-label">Câmpuri suplimentare în JSON / Extra fields</label>\
<div class="exp-checkbox-row"><input type="checkbox" id="exp-include-raw"><label for="exp-include-raw">🔤 Include HTML brut per verset</label></div>\
<div class="exp-checkbox-row"><input type="checkbox" id="exp-strip-diacritics"><label for="exp-strip-diacritics">🔡 Include text fără diacritice (searchable)</label></div>\
<div class="exp-checkbox-row"><input type="checkbox" id="exp-include-refs" checked><label for="exp-include-refs">📎 Include referințe și note de subsol</label></div>\
</div>\
<div class="exp-row"><label class="exp-label">Delay între capitole (ms)</label><input type="number" class="exp-input" id="exp-delay" min="200" max="5000" value="800" step="100" style="width:100px"></div>\
<hr class="exp-separator">\
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
<button class="exp-btn exp-btn-secondary" id="exp-pause" disabled>⏸ Pauză</button>\
<button class="exp-btn exp-btn-danger" id="exp-cancel" disabled>✕ Stop</button>\
<button class="exp-btn exp-btn-success" id="exp-download" disabled>⬇ JSON</button>\
</div>\
<div class="exp-log" id="exp-log"></div>\
</div>';

        document.body.appendChild(panel);

        document.getElementById('exp-toggle-min').addEventListener('click', toggleMinimize);
        document.getElementById('exp-start').addEventListener('click', startExport);
        document.getElementById('exp-pause').addEventListener('click', togglePause);
        document.getElementById('exp-cancel').addEventListener('click', cancelExport);
        document.getElementById('exp-download').addEventListener('click', downloadJSON);

        var updateRangeInfo = function() {
            var s = parseInt(document.getElementById('exp-book-start').value) || 1;
            var e = parseInt(document.getElementById('exp-book-end').value) || 66;
            var total = 0;
            for (var i = Math.max(1, s); i <= Math.min(66, e); i++) total += CHAPTERS[i - 1];
            document.getElementById('exp-range-info').textContent = '= ' + total + ' cap.';
        };
        document.getElementById('exp-book-start').addEventListener('change', updateRangeInfo);
        document.getElementById('exp-book-end').addEventListener('change', updateRangeInfo);

        panel.addEventListener('click', function(e) {
            if (panel.classList.contains('minimized')) panel.classList.remove('minimized');
        });

        makeDraggable(panel);
        setTimeout(populateTranslations, 1500);
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
                select.appendChild(option);
            }
            select.appendChild(group);
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // LOG & UI UPDATE
    // ═══════════════════════════════════════════════════════════════

    function log(msg, type) {
        type = type || 'info';
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
                errEl.style.color = s.errors.length > 0 ? '#e94560' : '#2ecc71';
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
        var chkRaw = el('exp-include-raw');
        var chkDia = el('exp-strip-diacritics');
        var chkRefs = el('exp-include-refs');

        if (bookStartEl) bookStartEl.disabled = settingsLocked;
        if (bookEndEl) bookEndEl.disabled = settingsLocked;
        if (delayEl) delayEl.disabled = settingsLocked;
        if (chkRaw) chkRaw.disabled = settingsLocked;
        if (chkDia) chkDia.disabled = settingsLocked;
        if (chkRefs) chkRefs.disabled = settingsLocked;
    }

    // ═══════════════════════════════════════════════════════════════
    // EXPORT ENGINE
    // ═══════════════════════════════════════════════════════════════

    async function startExport() {
        var translationCode = document.getElementById('exp-translation').value;
        if (!translationCode) { setStatus('⚠ Selectează o traducere!'); return; }

        var bookStart = parseInt(document.getElementById('exp-book-start').value) || 1;
        var bookEnd = parseInt(document.getElementById('exp-book-end').value) || 66;
        var delay = parseInt(document.getElementById('exp-delay').value) || CONFIG.chapterDelay;

        if (bookStart < 1 || bookEnd > 66 || bookStart > bookEnd) {
            setStatus('⚠ Interval cărți invalid (1-66)!'); return;
        }

        var translations = getAvailableTranslations();
        var translationInfo = translations[translationCode] || {};
        var availableBooks = translationInfo.books || [1, 66];
        var effectiveStart = Math.max(bookStart, availableBooks[0]);
        var effectiveEnd = Math.min(bookEnd, availableBooks[1]);

        if (effectiveStart > effectiveEnd) {
            setStatus('⚠ Traducerea ' + translationCode.toUpperCase() + ' nu are cărți în intervalul ' + bookStart + '-' + bookEnd + '!');
            return;
        }

        var totalChapters = 0;
        for (var b = effectiveStart; b <= effectiveEnd; b++) totalChapters += CHAPTERS[b - 1];

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

        // Read checkbox states ONCE at start
        var includeRaw = document.getElementById('exp-include-raw').checked;
        var stripDiacritics = document.getElementById('exp-strip-diacritics').checked;
        var includeRefs = document.getElementById('exp-include-refs').checked;

        exportState = {
            running: true, paused: false, cancelled: false,
            currentBook: 0, currentChapter: 0,
            currentBookName: '', currentBookChapters: 0,
            totalBooks: effectiveEnd - effectiveStart + 1,
            totalChapters: totalChapters,
            completedChapters: 0, completedBooks: 0,
            totalVerses: 0, errors: [],
            bookVerseCount: 0,
            startTime: Date.now(),
            bibleData: createBibleJSON(translationCode, {
                name: displayName, nameLocal: displayName,
                language: lang, languageName: langNames[lang] || lang,
                copyright: copyright,
            }),
        };

        setButtonStates(true, false, false);
        log('═══ Export pornit: ' + displayName + ' ═══', 'info');
        log('Cărți: ' + effectiveStart + '–' + effectiveEnd + ' (' + exportState.totalBooks + ' cărți, ' + totalChapters + ' capitole)', 'info');
        log('Opțiuni: HTML brut=' + includeRaw + ', Fără diacritice=' + stripDiacritics + ', Referințe=' + includeRefs + ', Delay=' + delay + 'ms', 'info');

        for (var bookNum = effectiveStart; bookNum <= effectiveEnd; bookNum++) {
            if (exportState.cancelled) break;

            var numChapters = CHAPTERS[bookNum - 1];
            var bookData = createBookJSON(bookNum, numChapters);
            var bookName = BOOKS_RO[bookNum - 1] || ('Cartea ' + bookNum);

            exportState.currentBook = bookNum;
            exportState.currentBookName = bookName;
            exportState.currentBookChapters = numChapters;
            exportState.bookVerseCount = 0;

            log('📖 ' + bookNum + '. ' + bookName + ' — ' + numChapters + ' capitole', 'info');

            for (var chap = 1; chap <= numChapters; chap++) {
                while (exportState.paused && !exportState.cancelled) {
                    setStatus('⏸ Pauză — ' + bookName + ' cap. ' + chap + '/' + numChapters + ' | Total: ' + exportState.totalVerses.toLocaleString() + ' versete');
                    await sleep(500);
                }
                if (exportState.cancelled) break;

                exportState.currentChapter = chap;
                setStatus('📖 ' + bookName + ' — cap. ' + chap + '/' + numChapters);
                updateUI();

                var verses = [];
                var attempts = 0;
                var success = false;

                while (attempts < CONFIG.maxRetries && !success) {
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
                    log('❌ ' + bookName + ' cap. ' + chap + ': 0 versete — OMIS', 'err');
                    exportState.errors.push(bookName + ' ' + chap);
                } else {
                    // Build chapter verses with optional extra fields
                    // Collect headings separately at chapter level
                    var chapterHeadings = [];
                    var chapterVerses = verses.map(function(v) {
                        var verse = { number: v.number, text: v.text };
                        if (includeRaw && v._rawHtml) verse.rawHtml = v._rawHtml;
                        if (stripDiacritics) verse.textNormalized = removeDiacritics(v.text);
                        if (includeRefs && v._refEntries && v._refEntries.length > 0) {
                            var refs = extractReferences(v._refEntries);
                            if (refs.crossReferences.length > 0) verse.crossReferences = refs.crossReferences;
                            if (refs.footnotes.length > 0) verse.footnotes = refs.footnotes;
                            // Titles → chapter-level headings (not verse property)
                            if (refs.titles.length > 0) {
                                for (var ti = 0; ti < refs.titles.length; ti++) {
                                    chapterHeadings.push({
                                        beforeVerse: v.number,
                                        level: refs.titles[ti].level,
                                        text: refs.titles[ti].text
                                    });
                                }
                            }
                        }
                        return verse;
                    });

                    var chapterObj = {
                        number: chap,
                        verses: chapterVerses,
                        _extensions: {}
                    };
                    // Only add headings array if there are any
                    if (includeRefs && chapterHeadings.length > 0) {
                        chapterObj.headings = chapterHeadings;
                    }
                    bookData.chapters.push(chapterObj);

                    exportState.totalVerses += verses.length;
                    exportState.bookVerseCount += verses.length;

                    if (chap % 10 === 0 || chap === numChapters || numChapters <= 5) {
                        log('  cap. ' + chap + '/' + numChapters + ': ' + verses.length + ' vs → total carte: ' + exportState.bookVerseCount, 'data');
                    }
                }

                exportState.completedChapters++;
                updateUI();

                if (chap < numChapters || bookNum < effectiveEnd) {
                    await sleep(delay);
                }
            }

            if (!exportState.cancelled) {
                exportState.bibleData.books.push(bookData);
                exportState.completedBooks++;
                log('✅ ' + bookName + ': ' + bookData.chapters.length + ' cap., ' + exportState.bookVerseCount.toLocaleString() + ' versete', 'ok');
            }

            if (bookNum < effectiveEnd && !exportState.cancelled) {
                await sleep(CONFIG.bookDelay);
            }
        }

        // Finalize
        exportState.running = false;
        var elapsed = (Date.now() - exportState.startTime) / 1000;

        if (exportState.cancelled) {
            setStatus('❌ Export anulat. ' + exportState.completedBooks + ' cărți, ' + exportState.totalVerses.toLocaleString() + ' versete salvate.');
            log('Export anulat după ' + formatDuration(elapsed), 'err');
        } else {
            exportState.bibleData.exportInfo.totalBooks = exportState.bibleData.books.length;
            exportState.bibleData.exportInfo.totalChapters = exportState.completedChapters;
            exportState.bibleData.exportInfo.totalVerses = exportState.totalVerses;

            var errCount = exportState.errors.length;
            var errMsg = errCount > 0 ? ' | ' + errCount + ' erori' : '';
            setStatus('✅ Complet! ' + exportState.completedBooks + ' cărți, ' + exportState.totalVerses.toLocaleString() + ' versete' + errMsg + ' | ' + formatDuration(elapsed));
            log('═══ Export finalizat în ' + formatDuration(elapsed) + ' ═══', 'ok');
            log(exportState.completedBooks + ' cărți, ' + exportState.completedChapters + ' capitole, ' + exportState.totalVerses.toLocaleString() + ' versete' + errMsg, 'ok');
        }

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

        var code = data.translation.code || 'bible';
        var dateStr = new Date().toISOString().slice(0, 10);
        var partial = data.exportInfo.partial ? '_partial' : '';
        var filename = code + '_' + dateStr + partial + '_TopPresenter.json';

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

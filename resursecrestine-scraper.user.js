// ==UserScript==
// @name         ResurseCrestine Song Exporter
// @namespace    https://resursecrestine.ro
// @version      1.0.0
// @description  Export songs from resursecrestine.ro/cantece to TopPresenter's GOAT "TopPresenter Song" JSON — sections (verse/chorus/bridge), /: :/ repeat markers, author/themes/album/bible-ref. Per-letter bundles for easy bulk import.
// @author       TopPresenter
// @match        https://www.resursecrestine.ro/*
// @match        https://resursecrestine.ro/*
// @grant        GM_download
// @grant        GM_setClipboard
// @run-at       document-idle
// ==/UserScript==

(function () {
    'use strict';

    // ═══════════════════════════════════════════════════════════════
    // CONFIG
    // ═══════════════════════════════════════════════════════════════
    var ORIGIN = location.origin;                 // same-origin fetches → no CORS
    var CONFIG = { delay: 250, retries: 3, retryDelay: 800 };

    var sleep = function (ms) { return new Promise(function (r) { setTimeout(r, ms); }); };

    // ═══════════════════════════════════════════════════════════════
    // PARSE LOGIC — kept byte-for-byte equivalent to resursecrestine-scraper.mjs
    // ═══════════════════════════════════════════════════════════════
    function decodeEntities(s) {
        return s
            .replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&').replace(/&lt;/g, '<')
            .replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#0?39;|&apos;|&rsquo;/g, "'")
            .replace(/&hellip;/g, '…').replace(/&ndash;/g, '–').replace(/&mdash;/g, '—')
            .replace(/&#(\d+);/g, function (_, n) { return String.fromCodePoint(+n); })
            .replace(/&#x([0-9a-f]+);/gi, function (_, n) { return String.fromCodePoint(parseInt(n, 16)); });
    }
    function stripTags(s) {
        return decodeEntities(s.replace(/<[^>]+>/g, '')).replace(/[ \t]+/g, ' ').trim();
    }
    function metaAttr(html, name) {
        var m = html.match(new RegExp('<meta\\s+property="' + name + '"\\s+content="([^"]*)"', 'i'))
            || html.match(new RegExp('<meta\\s+name="' + name + '"\\s+content="([^"]*)"', 'i'));
        return m ? decodeEntities(m[1]) : '';
    }

    function songLinksFrom(html) {
        var ids = new Map();
        var re = /\/cantece\/(\d+)\/([a-z0-9-]+)/g, m;
        while ((m = re.exec(html))) { if (!ids.has(m[1])) ids.set(m[1], m[2]); }
        return ids;
    }
    function maxPageFor(letter, html) {
        var max = 1;
        var re = new RegExp('index-alfabetic\\/' + letter + '\\/pagina\\/(\\d+)', 'g'), m;
        while ((m = re.exec(html))) { max = Math.max(max, +m[1]); }
        return max;
    }

    function classifySection(label, index, counters) {
        var l = label.toLowerCase();
        var num = (label.match(/\d+/) || [''])[0];
        var next = function (k) { counters[k] = (counters[k] || 0) + 1; return counters[k]; };
        if (/refren|cor\b/.test(l)) { var c = next('c'); return { type: 'chorus', key: c === 1 ? 'c' : 'c' + c }; }
        if (/pre-?refren|pre-?cor/.test(l)) { return { type: 'prechorus', key: 'p' + next('p') }; }
        if (/punte|bridge/.test(l)) { return { type: 'bridge', key: 'b' + next('b') }; }
        if (/intro/.test(l)) return { type: 'intro', key: 'i' };
        if (/final|încheiere|incheiere|coda|sfâr|sfar/.test(l)) return { type: 'ending', key: 'e' };
        if (/strof|vers/.test(l)) { var n = num || next('v'); return { type: 'verse', key: 'v' + n }; }
        return { type: 'other', key: 's' + next('s') };
    }

    function dropDoubled(blocks) {
        var n = blocks.length;
        if (n >= 2 && n % 2 === 0) {
            var half = n / 2;
            var sig = function (b) { return b.label + ' ' + b.text; };
            var mirrored = true;
            for (var i = 0; i < half; i++) { if (sig(blocks[i]) !== sig(blocks[i + half])) { mirrored = false; break; } }
            if (mirrored) return blocks.slice(0, half);
        }
        return blocks;
    }

    function extractRepeat(text) {
        var repeat = 1;
        if (/\/:/.test(text) || /:\//.test(text)) {
            var m = text.match(/:\/\s*\(?\s*(\d+)\s*x/i);
            repeat = m ? Math.max(2, +m[1]) : 2;
        }
        var cleaned = text
            .replace(/\/:/g, '').replace(/:\//g, '')
            .replace(/\(?\s*\d+\s*x\s*\)?/gi, '')
            .replace(/[ \t]+\n/g, '\n').replace(/\n{3,}/g, '\n\n');
        return { repeat: repeat, cleaned: cleaned.trim() };
    }

    function parseSong(html, id, slug) {
        var title = metaAttr(html, 'og:title') ||
            (html.match(/class="wrap-text"[^>]*>([^<]+)/) || [, slug])[1];

        var grab = function (label) {
            var re = new RegExp(label + '\\s*:?\\s*<a[^>]*href="([^"]*)"[^>]*>\\s*([^<]+?)\\s*<\\/a>', 'i');
            var m = html.match(re);
            return m ? { href: m[1], text: decodeEntities(m[2]).trim() } : null;
        };
        var autor = grab('Autor');
        var versuri = grab('Versuri');
        var muzica = grab('Muzic[aă]');
        var album = grab('Album');
        var tema = grab('Tematica');

        var refM = html.match(/index-referinta\/([a-z0-9-]+)(?:\/capitol\/(\d+))?/i);
        var addedM = html.match(/Resursa adaugata de\s*<a[^>]*>\s*([^<]+?)\s*<\/a>\s*in\s*<span class="date">\s*([^<]+?)\s*<\/span>/i);

        // Collect raw .strofa blocks then drop the print/fullscreen clone double.
        var blocks = [];
        var re = /<div class="strofa">\s*(?:<div class="strofa-label">([\s\S]*?)<\/div>)?\s*<div class="strofa-text">([\s\S]*?)<\/div>\s*<\/div>/g, m;
        while ((m = re.exec(html))) {
            var label = m[1] ? stripTags(m[1]) : '';
            var rawText = m[2].replace(/<br\s*\/?>/gi, '\n').replace(/<[^>]+>/g, '');
            var text = decodeEntities(rawText).replace(/\r/g, '').replace(/[ \t]+\n/g, '\n').trim();
            if (text) blocks.push({ label: label, text: text });
        }
        // Fallback: older song pages have no .strofa markup — lyrics live as plain
        // text in `resized-text` (numbered verses "N." + an "R …"/"Refren" chorus;
        // single <br> = line break, 2+ <br> = stanza break).
        if (blocks.length === 0) {
            var rt = html.match(/class="resized-text"[^>]*>([\s\S]*?)<\/div>/);
            if (rt) {
                var h = rt[1]
                    .replace(/(?:<br\s*\/?>\s*){2,}/gi, ' @@PP@@ ')
                    .replace(/<br\s*\/?>/gi, ' @@NL@@ ')
                    .replace(/<[^>]+>/g, '');
                var plain = decodeEntities(h).replace(/[ \t\r\n]+/g, ' ')
                    .replace(/\s*@@PP@@\s*/g, '\n\n').replace(/\s*@@NL@@\s*/g, '\n').trim();
                plain.split(/\n{2,}/).forEach(function (chunk) {
                    var c = chunk.trim();
                    if (!c) return;
                    var first = c.split('\n')[0].trim();
                    var label = '', body = c;
                    var numM = first.match(/^(\d+)[.)]\s*/);
                    if (numM) { label = 'Strofă ' + numM[1]; body = c.replace(/^\s*\d+[.)]\s*/, ''); }
                    else if (/^(refren\b|r\b|r:)/i.test(first)) { label = 'Refren'; body = c.replace(/^\s*(refren|r)\b[:.]?\s*/i, ''); }
                    blocks.push({ label: label, text: body });
                });
            }
        }
        var deduped = dropDoubled(blocks);

        var sections = [];
        var counters = {};
        deduped.forEach(function (b, order) {
            var label = b.label || ('Strofă ' + (order + 1));
            var er = extractRepeat(b.text);
            var lines = er.cleaned.split('\n').map(function (t) { return { text: t.trim() }; });
            var cls = classifySection(label, order, counters);
            var section = { id: cls.key, type: cls.type, label: label, order: order, lines: lines };
            if (er.repeat > 1) section.repeat = er.repeat;
            sections.push(section);
        });

        var url = ORIGIN + '/cantece/' + id + '/' + slug;
        var themes = tema ? [tema.text] : [];
        var ext = { id: id, url: url };
        if (autor && autor.href) ext.autorSlug = (autor.href.split('index-autori/')[1] || '').split(/[/"]/)[0];
        if (tema && tema.href) ext.tematicaSlug = (tema.href.split('index-tematic/')[1] || '').split(/[/"]/)[0];
        if (refM) ext.referintaBiblica = refM[2] ? (refM[1] + ' ' + refM[2]) : refM[1];
        if (addedM) { ext.addedBy = decodeEntities(addedM[1]).trim(); ext.dateAdded = addedM[2].trim(); }

        var notes = refM ? ('Referință biblică: ' + (refM[1] || '').replace(/-/g, ' ') + (refM[2] ? (' ' + refM[2]) : '')) : '';

        var version = { name: 'Original', language: 'ro', source: url, sections: sections, _extensions: { resursecrestine: ext } };
        var albumName = album && !/fara album|fără album/i.test(album.text) ? album.text : '';
        if (albumName) version.songbook = { name: albumName };

        var song = {
            title: decodeEntities(String(title)).trim(),
            language: 'ro',
            themes: themes,
            author: (autor && autor.text) || '',
            versions: [version],
        };
        if (versuri && versuri.text) song.authorWords = versuri.text;
        if (muzica && muzica.text) song.authorMusic = muzica.text;
        if (notes) song.notes = notes;
        if (albumName) song.songbook = { name: albumName };
        return song;
    }

    function wrapDoc(song) {
        return {
            schemaVersion: '1.0.0',
            format: 'TopPresenter Song',
            exportInfo: { source: 'resursecrestine.ro', exportDate: new Date().toISOString(), exporterVersion: '1.0.0' },
            song: song,
        };
    }
    function wrapBundle(songs) {
        return {
            schemaVersion: '1.0.0',
            format: 'TopPresenter Song',
            exportInfo: { source: 'resursecrestine.ro', exportDate: new Date().toISOString(), exporterVersion: '1.0.0', count: songs.length },
            songs: songs,
        };
    }

    // ═══════════════════════════════════════════════════════════════
    // NETWORK (same-origin fetch + retry)
    // ═══════════════════════════════════════════════════════════════
    function getText(pathOrUrl) {
        var url = pathOrUrl.indexOf('http') === 0 ? pathOrUrl : (ORIGIN + pathOrUrl);
        var attempt = 0;
        function tryOnce() {
            attempt++;
            return fetch(url, { credentials: 'omit' }).then(function (res) {
                if (res.status === 404) return null;
                if (!res.ok) throw new Error('HTTP ' + res.status);
                return res.text();
            }).catch(function (err) {
                if (attempt >= CONFIG.retries) throw err;
                return sleep(CONFIG.retryDelay * attempt).then(tryOnce);
            });
        }
        return tryOnce();
    }

    async function discoverLetters() {
        var html = await getText('/cantece');
        var set = new Set(), m;
        var re = /index-alfabetic\/([^"\/]+)"/g;
        while ((m = re.exec(html || ''))) set.add(decodeURIComponent(m[1]));
        var letters = Array.from(set);
        return letters.length ? letters : 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.split('');
    }

    async function enumerateLetter(letter) {
        var all = new Map();
        var first = await getText('/cantece/index-alfabetic/' + encodeURIComponent(letter));
        if (!first) return all;
        var pages = maxPageFor(letter, first);
        songLinksFrom(first).forEach(function (slug, id) { all.set(id, slug); });
        for (var p = 2; p <= pages; p++) {
            if (state.cancelled) break;
            await sleep(CONFIG.delay);
            var html = await getText('/cantece/index-alfabetic/' + encodeURIComponent(letter) + '/pagina/' + p);
            if (html) songLinksFrom(html).forEach(function (slug, id) { all.set(id, slug); });
        }
        return all;
    }

    async function fetchSong(id, slug) {
        var html = await getText('/cantece/' + id + '/' + slug);
        if (!html) throw new Error('404');
        var song = parseSong(html, id, slug);
        if (!song.versions[0].sections.length) throw new Error('fără versuri');
        return song;
    }

    // ═══════════════════════════════════════════════════════════════
    // EXPORT DRIVERS
    // ═══════════════════════════════════════════════════════════════
    var state = { running: false, cancelled: false, ok: 0, fail: 0 };

    async function exportLetters(letters) {
        state.running = true; state.cancelled = false; state.ok = 0; state.fail = 0;
        setButtons(true);
        try {
            for (var li = 0; li < letters.length; li++) {
                if (state.cancelled) break;
                var letter = letters[li];
                log('Litera ' + letter + ': enumerez…', 'info');
                var map = await enumerateLetter(letter);
                if (!map.size) { log('Litera ' + letter + ': 0 cântece', 'muted'); continue; }
                var songs = [];
                var entries = Array.from(map.entries());
                for (var i = 0; i < entries.length; i++) {
                    if (state.cancelled) break;
                    await sleep(CONFIG.delay);
                    try {
                        songs.push(await fetchSong(entries[i][0], entries[i][1]));
                        state.ok++;
                    } catch (e) { state.fail++; }
                    progress(letter, i + 1, entries.length);
                }
                if (songs.length) {
                    saveFile(JSON.stringify(wrapBundle(songs), null, 2), 'TopPresenter Songs/litera-' + letter + '.json', 'application/json');
                    log('Litera ' + letter + ': ' + songs.length + ' cântece descărcate', 'ok');
                }
            }
            log('Gata. ' + state.ok + ' ok, ' + state.fail + ' eșuate.', state.fail ? 'warn' : 'ok');
        } catch (e) {
            log('Eroare: ' + e.message, 'err');
        } finally {
            state.running = false; setButtons(false);
        }
    }

    async function exportCurrentSong(copyOnly) {
        var m = location.pathname.match(/\/cantece\/(\d+)\/([a-z0-9-]+)/);
        if (!m) { log('Deschide întâi pagina unui cântec.', 'warn'); return; }
        try {
            var song = parseSong(document.documentElement.outerHTML, m[1], m[2]);
            var doc = wrapDoc(song);
            var json = JSON.stringify(doc, null, 2);
            if (copyOnly) {
                if (typeof GM_setClipboard === 'function') GM_setClipboard(json, { type: 'text', mimetype: 'text/plain' });
                log('JSON copiat în clipboard: ' + song.title, 'ok');
            } else {
                saveFile(json, 'TopPresenter Songs/' + sanitize(m[1] + '-' + m[2]) + '.json', 'application/json');
                log('Descărcat: ' + song.title, 'ok');
            }
        } catch (e) { log('Eroare: ' + e.message, 'err'); }
    }

    function currentLetter() {
        var m = location.pathname.match(/index-alfabetic\/([^\/]+)/);
        return m ? decodeURIComponent(m[1]) : '';
    }

    var sanitize = function (s) { return s.replace(/[\/\\:?%*|"<>]+/g, '-').slice(0, 110); };

    // ═══════════════════════════════════════════════════════════════
    // DOWNLOAD (GM_download + <a download> fallback, Safari-safe, spaced)
    // ═══════════════════════════════════════════════════════════════
    var IS_SAFARI = /apple/i.test(navigator.vendor || '');
    var dlQueue = [], dlPumping = false;
    function pump() {
        if (dlPumping) return; dlPumping = true;
        (function next() {
            var item = dlQueue.shift();
            if (!item) { dlPumping = false; return; }
            performDownload(item.content, item.path, item.mime);
            setTimeout(next, 1100);
        })();
    }
    function performDownload(content, path, mime) {
        var blob = new Blob([content], { type: (mime || 'application/json') + ';charset=utf-8' });
        var url = URL.createObjectURL(blob);
        var anchor = function () {
            var a = document.createElement('a');
            a.href = url; a.download = path.replace(/\//g, '_'); a.style.display = 'none';
            document.body.appendChild(a); a.click(); document.body.removeChild(a);
            setTimeout(function () { URL.revokeObjectURL(url); }, 30000);
        };
        if (!IS_SAFARI && typeof GM_download === 'function') {
            try {
                GM_download({ url: url, name: path, saveAs: false,
                    onload: function () { setTimeout(function () { URL.revokeObjectURL(url); }, 30000); },
                    onerror: function () { anchor(); } });
            } catch (e) { anchor(); }
        } else { anchor(); }
    }
    function saveFile(content, path, mime) { dlQueue.push({ content: content, path: path, mime: mime }); pump(); }

    // ═══════════════════════════════════════════════════════════════
    // UI
    // ═══════════════════════════════════════════════════════════════
    function el(id) { return document.getElementById(id); }
    function log(msg, kind) {
        var box = el('rc-log'); if (!box) return;
        box.style.display = 'block';
        var c = { ok: '#34c759', warn: '#ff9f0a', err: '#ff453a', info: '#0a84ff', muted: '#666' }[kind] || '#aaa';
        var line = document.createElement('div'); line.style.color = c; line.textContent = msg;
        box.appendChild(line); box.scrollTop = box.scrollHeight;
    }
    function progress(letter, done, total) {
        var p = el('rc-progress'); if (p) p.textContent = letter + ': ' + done + '/' + total + ' (ok ' + state.ok + ', fail ' + state.fail + ')';
    }
    function setButtons(running) {
        ['rc-song', 'rc-copy', 'rc-letter', 'rc-all'].forEach(function (id) { var b = el(id); if (b) b.disabled = running; });
        var c = el('rc-cancel'); if (c) c.style.display = running ? 'block' : 'none';
    }

    function createUI() {
        if (el('rc-exporter-panel')) return;
        var panel = document.createElement('div');
        panel.id = 'rc-exporter-panel';
        panel.innerHTML = '\
<style>\
#rc-exporter-panel{position:fixed;bottom:20px;right:20px;width:320px;background:#1c1c1e;color:#e0e0e0;border-radius:12px;box-shadow:0 8px 32px rgba(0,0,0,.4);z-index:999999;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;font-size:13px;overflow:hidden}\
#rc-exporter-panel .rc-head{background:#2c2c2e;padding:10px 14px;display:flex;align-items:center;justify-content:space-between;cursor:move;border-bottom:1px solid #3a3a3c}\
#rc-exporter-panel .rc-head b{font-size:14px;color:#f2f2f2}\
#rc-exporter-panel .rc-body{padding:12px;display:flex;flex-direction:column;gap:8px}\
#rc-exporter-panel button{padding:8px 10px;border:0;border-radius:7px;color:#fff;font-size:13px;cursor:pointer;background:#0a84ff}\
#rc-exporter-panel button.sec{background:#3a3a3c}\
#rc-exporter-panel button#rc-cancel{background:#ff453a;display:none}\
#rc-exporter-panel button:disabled{opacity:.5;cursor:default}\
#rc-exporter-panel .rc-row{display:flex;gap:6px;align-items:center}\
#rc-exporter-panel input{width:56px;background:#3a3a3c;border:1px solid #48484a;border-radius:6px;color:#e0e0e0;padding:5px}\
#rc-progress{font-size:11px;color:#8e8e93;min-height:14px}\
#rc-log{max-height:120px;overflow-y:auto;background:#111113;border-radius:6px;padding:6px 8px;font-family:Menlo,Consolas,monospace;font-size:11px;margin-top:4px;display:none}\
</style>\
<div class="rc-head"><b>🎵 ResurseCrestine → TopPresenter</b><span id="rc-min" style="cursor:pointer;color:#aaa">—</span></div>\
<div class="rc-body" id="rc-bodywrap">\
<button id="rc-song" class="sec">⬇︎ Descarcă cântecul curent</button>\
<button id="rc-copy" class="sec">📋 Copiază JSON cântec curent</button>\
<button id="rc-letter">⬇︎ Descarcă litera curentă</button>\
<button id="rc-all">⬇︎ Descarcă tot (A–Z)</button>\
<div class="rc-row"><span style="color:#8e8e93">pauză (ms)</span><input id="rc-delay" type="number" value="250" min="0"></div>\
<button id="rc-cancel">■ Oprește</button>\
<div id="rc-progress"></div>\
<div id="rc-log"></div>\
</div>';
        document.body.appendChild(panel);

        el('rc-delay').addEventListener('change', function () { CONFIG.delay = Math.max(0, +this.value || 0); });
        el('rc-song').addEventListener('click', function () { exportCurrentSong(false); });
        el('rc-copy').addEventListener('click', function () { exportCurrentSong(true); });
        el('rc-letter').addEventListener('click', function () {
            var L = currentLetter();
            if (!L) { var input = prompt('Ce literă? (ex: A)'); L = (input || '').trim().toUpperCase(); }
            if (L) exportLetters([L]);
        });
        el('rc-all').addEventListener('click', async function () {
            if (!confirm('Descarc TOATE cântecele (~28.000) ca pachete pe literă? Poate dura ~40 min.')) return;
            exportLetters(await discoverLetters());
        });
        el('rc-cancel').addEventListener('click', function () { state.cancelled = true; log('Se oprește…', 'warn'); });
        el('rc-min').addEventListener('click', function () {
            var b = el('rc-bodywrap'); b.style.display = b.style.display === 'none' ? 'flex' : 'none';
        });
        makeDraggable(panel, panel.querySelector('.rc-head'));
    }

    function makeDraggable(panel, handle) {
        var dx = 0, dy = 0, down = false;
        handle.addEventListener('mousedown', function (e) {
            if (e.target.id === 'rc-min') return;
            down = true; dx = e.clientX - panel.offsetLeft; dy = e.clientY - panel.offsetTop;
            panel.style.bottom = 'auto'; panel.style.right = 'auto';
        });
        document.addEventListener('mousemove', function (e) {
            if (!down) return; panel.style.left = (e.clientX - dx) + 'px'; panel.style.top = (e.clientY - dy) + 'px';
        });
        document.addEventListener('mouseup', function () { down = false; });
    }

    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', createUI);
    else createUI();
})();

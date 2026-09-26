#!/usr/bin/env node
/**
 * Contract test for the JavaScript extension runtime.
 *
 * The prelude in lib/extensions/js_prelude.dart is the API every extension
 * author codes against, but it only runs inside QuickJS on a device. This
 * harness executes it in Node with a stubbed host that mimics what
 * JsRuntimeHost does in Dart — including the asynchronous settle round trip
 * — so the bridge contract is verified on every push.
 */
const fs = require('fs');
const vm = require('vm');
const path = require('path');
const assert = require('assert');

const root = path.resolve(__dirname, '..');

// ---------------------------------------------------------------- extract
const preludeDart = fs.readFileSync(
  path.join(root, 'lib/extensions/js_prelude.dart'),
  'utf8'
);
const match = preludeDart.match(/const String kJsPrelude = r'''([\s\S]*?)''';/);
assert(match, 'could not extract kJsPrelude from js_prelude.dart');
const prelude = match[1];

// ------------------------------------------------------------- fake host
const SAMPLE_HTML = `
<html><body>
  <div class="grid">
    <div class="card"><a href="/series/1" title="Alpha"><img src="/c/1.jpg"></a></div>
    <div class="card"><a href="/series/2" title="Beta"><img src="/c/2.jpg"></a></div>
  </div>
</body></html>`;

function makeContext() {
  const store = new Map();
  const calls = [];
  let docSeq = 0;

  const ctx = {
    Promise, JSON, Date, Error, String, Array, Object, Math,
    isNaN, parseInt, parseFloat, setTimeout,
  };
  ctx.globalThis = ctx;

  ctx.sendMessage = function (channel, payload) {
    assert.strictEqual(channel, 'host', 'prelude must use the "host" channel');
    const msg = JSON.parse(payload);
    calls.push(msg.method);

    // Async, exactly like Dart's unawaited dispatch.
    setTimeout(() => {
      let ok = true;
      let result = null;
      try {
        const p = msg.params;
        switch (msg.method) {
          case 'log':
            break;
          case 'http':
            result = {
              status: p.url.includes('/404') ? 404 : 200,
              url: p.url,
              headers: { 'content-type': 'text/html' },
              body: p.url.includes('/json')
                ? JSON.stringify({ hello: 'world' })
                : SAMPLE_HTML,
            };
            break;
          case 'parse':
            result = { id: ++docSeq, baseUrl: p.baseUrl };
            break;
          case 'select': {
            if (p.selector === 'div.card') {
              result = [1, 2].map((n) => ({
                path: 'e' + n, tag: 'div', text: '', html: '',
                outerHtml: '', attrs: {},
              }));
            } else if (p.selector === 'a') {
              const n = p.scope === 'e1' ? 1 : 2;
              result = [{
                path: 'a' + n, tag: 'a', text: n === 1 ? 'Alpha' : 'Beta',
                html: '', outerHtml: '',
                attrs: { href: '/series/' + n, title: n === 1 ? 'Alpha' : 'Beta' },
              }];
            } else {
              result = [];
            }
            break;
          }
          case 'absUrl':
            result = 'https://site.test' + p.value;
            break;
          case 'resolve':
            result = p.base.replace(/\/$/, '') + p.url;
            break;
          case 'docText':
            result = 'Alpha Beta';
            break;
          case 'sleep':
            break;
          case 'storeGet':
            result = store.has(p.key) ? store.get(p.key) : null;
            break;
          case 'storeSet':
            store.set(p.key, p.value);
            break;
          case 'renderJs':
            result = '<html><body><div id="done">rendered</div></body></html>';
            break;
          case 'solveChallenge':
            result = true;
            break;
          case 'cookies':
            result = 'cf_clearance=abc123';
            break;
          default:
            ok = false;
            result = { message: 'unknown host method ' + msg.method };
        }
      } catch (e) {
        ok = false;
        result = { message: String(e) };
      }
      ctx.__settle(msg.id, ok, JSON.stringify(result));
    }, 0);
  };

  vm.createContext(ctx);
  vm.runInContext(prelude, ctx);
  return { ctx, calls, store };
}

// -------------------------------------------------------------- the tests
const tests = [];
function test(name, fn) { tests.push([name, fn]); }
const run = (ctx, code) => vm.runInContext(`(async () => { ${code} })()`, ctx);

test('prelude exposes the documented globals', () => {
  const { ctx } = makeContext();
  for (const g of ['http', 'dom', 'utils', 'console', 'fetch',
                   'webview', 'cloudflare', 'registerSource',
                   'registerMangaSource', 'registerAnimeSource']) {
    assert(ctx[g] !== undefined, `missing global: ${g}`);
  }
});

test('registerSource collects sources; manga/anime aliases set type', async () => {
  const { ctx } = makeContext();
  vm.runInContext(`
    registerMangaSource({ id: 'm', name: 'M' });
    registerAnimeSource({ id: 'a', name: 'A' });
  `, ctx);
  assert.strictEqual(ctx.__sources.length, 2);
  assert.strictEqual(ctx.__sources[0].type, 'manga');
  assert.strictEqual(ctx.__sources[1].type, 'anime');
});

test('http.get resolves through the async bridge', async () => {
  const { ctx } = makeContext();
  const res = JSON.parse(await run(ctx,
    `const r = await http.get('https://site.test/x'); return JSON.stringify({s:r.status,u:r.url});`));
  assert.strictEqual(res.s, 200);
  assert.strictEqual(res.u, 'https://site.test/x');
});

test('http throws on 4xx unless allowError', async () => {
  const { ctx } = makeContext();
  const threw = await run(ctx,
    `try { await http.get('https://site.test/404'); return 'no'; } catch (e) { return 'yes'; }`);
  assert.strictEqual(threw, 'yes', '404 should reject by default');

  const allowed = await run(ctx,
    `const r = await http.get('https://site.test/404', { allowError: true }); return String(r.status);`);
  assert.strictEqual(allowed, '404', 'allowError should suppress the throw');
});

test('http.getJson parses JSON', async () => {
  const { ctx } = makeContext();
  const out = await run(ctx,
    `const j = await http.getJson('https://site.test/json'); return j.hello;`);
  assert.strictEqual(out, 'world');
});

test('scoped DOM selection and absUrl work end to end', async () => {
  const { ctx } = makeContext();
  const out = JSON.parse(await run(ctx, `
    const doc = await http.getDoc('https://site.test/popular');
    const cards = await doc.select('div.card');
    const items = [];
    for (const c of cards) {
      const a = await c.selectFirst('a');
      items.push({ url: await a.absUrl('href'), title: a.attr('title') });
    }
    return JSON.stringify(items);
  `));
  assert.deepStrictEqual(out, [
    { url: 'https://site.test/series/1', title: 'Alpha' },
    { url: 'https://site.test/series/2', title: 'Beta' },
  ]);
});

test('el.attr returns null for a missing attribute', async () => {
  const { ctx } = makeContext();
  const out = await run(ctx, `
    const doc = await dom.parse('<p></p>', 'https://site.test');
    const a = (await doc.select('a'))[0] || null;
    const cards = await doc.select('div.card');
    const first = await cards[0].selectFirst('a');
    return String(first.attr('nope'));
  `);
  assert.strictEqual(out, 'null');
});

test('utils.store round-trips and is namespaced by the host', async () => {
  const { ctx, store } = makeContext();
  const out = await run(ctx,
    `await utils.store.set('token', 'xyz'); return await utils.store.get('token');`);
  assert.strictEqual(out, 'xyz');
  assert.strictEqual(store.get('token'), 'xyz');
});

test('webview.renderDoc returns a queryable Document', async () => {
  const { ctx, calls } = makeContext();
  const out = await run(ctx, `
    const doc = await webview.renderDoc('https://site.test/spa', { waitFor: '#done' });
    return String(doc.baseUrl);
  `);
  assert.strictEqual(out, 'https://site.test/spa');
  assert(calls.includes('renderJs'), 'should have called the renderJs host method');
});

test('cloudflare helpers reach the host', async () => {
  const { ctx } = makeContext();
  assert.strictEqual(
    await run(ctx, `return String(await cloudflare.solve('https://site.test'));`), 'true');
  assert.strictEqual(
    await run(ctx, `return await cloudflare.cookies('https://site.test');`),
    'cf_clearance=abc123');
});

test('a full source implementation behaves as the app expects', async () => {
  const { ctx } = makeContext();
  vm.runInContext(`
    class S {
      constructor() {
        this.id = 'en.test'; this.name = 'Test'; this.lang = 'en';
        this.baseUrl = 'https://site.test'; this.type = 'manga';
      }
      async popular(page) {
        const doc = await http.getDoc(this.baseUrl + '/p/' + page);
        const cards = await doc.select('div.card');
        const items = [];
        for (const c of cards) {
          const a = await c.selectFirst('a');
          items.push({ url: await a.absUrl('href'), title: a.attr('title') });
        }
        return { items, hasNext: page < 3 };
      }
      async chapters(item) {
        return [{ url: item.url + '/1', name: 'Chapter 1', number: 1 }];
      }
      async pages() { return ['https://cdn.test/1.jpg']; }
    }
    registerSource(new S());
  `, ctx);

  // Mirrors JsRuntimeHost.callSource / readSourceManifests exactly.
  const manifests = JSON.parse(vm.runInContext(`
    JSON.stringify(globalThis.__sources.map(function (s, i) {
      return { index: i, id: s.id, name: s.name, lang: s.lang || 'en',
               baseUrl: s.baseUrl || '', type: s.type || 'manga',
               supportsLatest: s.supportsLatest !== false,
               hasFilters: typeof s.getFilters === 'function' };
    }))
  `, ctx));
  assert.strictEqual(manifests.length, 1);
  assert.strictEqual(manifests[0].id, 'en.test');
  assert.strictEqual(manifests[0].supportsLatest, true);
  assert.strictEqual(manifests[0].hasFilters, false);

  const page = JSON.parse(await run(ctx,
    `return JSON.stringify(await globalThis.__sources[0].popular(1));`));
  assert.strictEqual(page.items.length, 2);
  assert.strictEqual(page.hasNext, true);

  const chapters = JSON.parse(await run(ctx,
    `return JSON.stringify(await globalThis.__sources[0].chapters({url:'/s/1'}));`));
  assert.strictEqual(chapters[0].url, '/s/1/1');
});

test('an error thrown inside a source rejects rather than hanging', async () => {
  const { ctx } = makeContext();
  vm.runInContext(`registerSource({ id:'x', name:'X', async popular(){ throw new Error('boom'); } });`, ctx);
  const out = await run(ctx,
    `try { await globalThis.__sources[0].popular(1); return 'no'; } catch (e) { return e.message; }`);
  assert.strictEqual(out, 'boom');
});

test('the bundled demo extensions register correctly', async () => {
  for (const [dir, expectType] of [['en.sampleManga', 'manga'], ['en.sampleAnime', 'anime']]) {
    const { ctx } = makeContext();
    const code = fs.readFileSync(
      path.join(root, 'extensions_repo/src', dir, 'index.js'), 'utf8');
    vm.runInContext(code, ctx);

    assert.strictEqual(ctx.__sources.length, 1, `${dir} should register one source`);
    const s = ctx.__sources[0];
    assert.strictEqual(s.type, expectType, `${dir} type`);
    assert(s.id && s.name && s.lang, `${dir} missing metadata`);

    const page = JSON.parse(await run(ctx,
      `return JSON.stringify(await globalThis.__sources[0].popular(1));`));
    assert(page.items.length > 0, `${dir} popular() returned nothing`);
    for (const it of page.items) {
      assert(it.url, `${dir} item missing url`);
      assert(it.title, `${dir} item missing title`);
    }

    const details = JSON.parse(await run(ctx,
      `return JSON.stringify(await globalThis.__sources[0].details(${JSON.stringify(page.items[0])}));`));
    assert(details.description, `${dir} details() missing description`);

    const method = expectType === 'manga' ? 'chapters' : 'episodes';
    const units = JSON.parse(await run(ctx,
      `return JSON.stringify(await globalThis.__sources[0].${method}(${JSON.stringify(page.items[0])}));`));
    assert(units.length > 0, `${dir} ${method}() returned nothing`);
    assert(units[0].url && units[0].name, `${dir} unit missing url/name`);

    const leaf = expectType === 'manga' ? 'pages' : 'videos';
    const out = JSON.parse(await run(ctx,
      `return JSON.stringify(await globalThis.__sources[0].${leaf}(${JSON.stringify(units[0])}));`));
    assert(out.length > 0, `${dir} ${leaf}() returned nothing`);
  }
});

// ------------------------------------------------------------------ runner
(async () => {
  let failed = 0;
  for (const [name, fn] of tests) {
    try {
      await fn();
      console.log(`  \u2713 ${name}`);
    } catch (e) {
      failed++;
      console.error(`  \u2717 ${name}\n      ${e.message}`);
    }
  }
  console.log(`\n${tests.length - failed}/${tests.length} runtime contract tests passed`);
  process.exit(failed ? 1 : 0);
})();

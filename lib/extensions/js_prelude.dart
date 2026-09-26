/// JavaScript injected into every extension runtime before the extension
/// itself is evaluated. It provides the standard library that extension
/// authors code against, and the promise plumbing that lets synchronous
/// QuickJS call back into asynchronous Dart.
///
/// Host calls work like this:
///   JS  -> sendMessage('host', {id, method, params})
///   Dart-> does the async work, then evaluates `__settle(id, ok, jsonString)`
const String kJsPrelude = r'''
(function () {
  var __seq = 0;
  var __pending = Object.create(null);

  globalThis.__settle = function (id, ok, payload) {
    var p = __pending[id];
    if (!p) return;
    delete __pending[id];
    var data;
    try { data = payload === undefined ? undefined : JSON.parse(payload); }
    catch (e) { data = payload; }
    if (ok) p.resolve(data); else p.reject(new Error(data && data.message ? data.message : String(data)));
  };

  function hostCall(method, params) {
    var id = ++__seq;
    return new Promise(function (resolve, reject) {
      __pending[id] = { resolve: resolve, reject: reject };
      sendMessage('host', JSON.stringify({ id: id, method: method, params: params || {} }));
    });
  }
  globalThis.hostCall = hostCall;

  // ---------------------------------------------------------------- console
  globalThis.console = {
    log:   function () { hostCall('log', { level: 'log',   args: Array.prototype.map.call(arguments, String) }); },
    warn:  function () { hostCall('log', { level: 'warn',  args: Array.prototype.map.call(arguments, String) }); },
    error: function () { hostCall('log', { level: 'error', args: Array.prototype.map.call(arguments, String) }); }
  };

  // ------------------------------------------------------------------- http
  function request(method, url, opts) {
    opts = opts || {};
    return hostCall('http', {
      method: method,
      url: url,
      headers: opts.headers || {},
      body: opts.body,
      form: opts.form
    }).then(function (res) {
      if (res.status >= 400 && !opts.allowError) {
        throw new Error('HTTP ' + res.status + ' for ' + url);
      }
      res.json = function () { return JSON.parse(res.body); };
      return res;
    });
  }

  globalThis.http = {
    get:  function (url, opts) { return request('GET', url, opts); },
    post: function (url, opts) { return request('POST', url, opts); },
    // Convenience: fetch and parse straight to a document.
    getDoc: function (url, opts) {
      return request('GET', url, opts).then(function (r) { return dom.parse(r.body, r.url); });
    },
    getJson: function (url, opts) {
      return request('GET', url, opts).then(function (r) { return JSON.parse(r.body); });
    }
  };

  // Minimal fetch shim so ported code using fetch mostly works.
  globalThis.fetch = function (url, init) {
    init = init || {};
    return request(init.method || 'GET', url, { headers: init.headers, body: init.body, allowError: true })
      .then(function (r) {
        return {
          ok: r.status < 400,
          status: r.status,
          url: r.url,
          headers: r.headers,
          text: function () { return Promise.resolve(r.body); },
          json: function () { return Promise.resolve(JSON.parse(r.body)); }
        };
      });
  };

  // -------------------------------------------------------------------- dom
  // A jQuery/jsoup-flavoured wrapper over host-side CSS selection.
  // `dom.parse` returns a Document handle; selection is resolved host-side
  // against the cached HTML, which keeps the JS side tiny and fast.
  function wrapNodes(docId, nodes) {
    return nodes.map(function (n) { return new Element(docId, n); });
  }

  function Element(docId, raw) {
    this._doc = docId;
    this._path = raw.path;
    this.tag = raw.tag;
    this.text = raw.text;
    this.html = raw.html;
    this.outerHtml = raw.outerHtml;
    this.attrs = raw.attrs || {};
  }
  Element.prototype.attr = function (name) {
    var v = this.attrs[name];
    return v === undefined ? null : v;
  };
  // Resolves href/src against the document base URL, host-side.
  Element.prototype.absUrl = function (name) {
    return hostCall('absUrl', { doc: this._doc, value: this.attrs[name] || '' });
  };
  Element.prototype.select = function (sel) {
    var self = this;
    return hostCall('select', { doc: this._doc, scope: this._path, selector: sel })
      .then(function (nodes) { return wrapNodes(self._doc, nodes); });
  };
  Element.prototype.selectFirst = function (sel) {
    return this.select(sel).then(function (a) { return a.length ? a[0] : null; });
  };

  function Document(id, baseUrl) { this._id = id; this.baseUrl = baseUrl; }
  Document.prototype.select = function (sel) {
    var self = this;
    return hostCall('select', { doc: this._id, scope: null, selector: sel })
      .then(function (nodes) { return wrapNodes(self._id, nodes); });
  };
  Document.prototype.selectFirst = function (sel) {
    return this.select(sel).then(function (a) { return a.length ? a[0] : null; });
  };
  Document.prototype.text = function () {
    return hostCall('docText', { doc: this._id });
  };

  globalThis.dom = {
    parse: function (html, baseUrl) {
      return hostCall('parse', { html: html, baseUrl: baseUrl || '' })
        .then(function (r) { return new Document(r.id, r.baseUrl); });
    }
  };

  // ------------------------------------------------------------------ utils
  globalThis.utils = {
    absolute: function (base, url) { return hostCall('resolve', { base: base, url: url }); },
    sleep: function (ms) { return hostCall('sleep', { ms: ms }); },
    // Persisted key/value storage scoped to this extension (cookies, tokens...)
    store: {
      get: function (k) { return hostCall('storeGet', { key: k }); },
      set: function (k, v) { return hostCall('storeSet', { key: k, value: v }); }
    },
    parseDate: function (s) { var t = Date.parse(s); return isNaN(t) ? null : t; }
  };

  // --------------------------------------------------------------- registry
  globalThis.__sources = [];
  globalThis.registerSource = function (src) { globalThis.__sources.push(src); };
  // Aniyomi/Tachiyomi muscle memory:
  globalThis.registerMangaSource = function (s) { s.type = 'manga'; registerSource(s); };
  globalThis.registerAnimeSource = function (s) { s.type = 'anime'; registerSource(s); };
})();
''';

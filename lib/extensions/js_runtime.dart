import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_js/flutter_js.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import 'js_prelude.dart';

/// Persisted key/value storage handed to an extension (`utils.store`).
abstract class ExtensionStore {
  Future<String?> get(String key);
  Future<void> set(String key, String? value);
}

class InMemoryExtensionStore implements ExtensionStore {
  final _m = <String, String>{};
  @override
  Future<String?> get(String key) async => _m[key];
  @override
  Future<void> set(String key, String? value) async {
    if (value == null) {
      _m.remove(key);
    } else {
      _m[key] = value;
    }
  }
}

/// Owns one QuickJS instance and services the host calls the prelude makes.
///
/// Each installed extension gets its own [JsRuntimeHost] so that a broken or
/// hostile extension cannot corrupt the state of another.
class JsRuntimeHost {
  JsRuntimeHost({
    required this.extensionId,
    required this.store,
    Dio? dio,
  }) : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 20),
              receiveTimeout: const Duration(seconds: 30),
              followRedirects: true,
              validateStatus: (_) => true,
              responseType: ResponseType.plain,
            ));

  final String extensionId;
  final ExtensionStore store;
  final Dio _dio;

  late final JavascriptRuntime _rt;
  Timer? _pump;
  bool _ready = false;

  /// Parsed documents, keyed by handle id, so JS can query them repeatedly
  /// without shipping the whole DOM across the bridge.
  final Map<int, _DocHandle> _docs = {};
  int _docSeq = 0;

  static const _defaultUserAgent =
      'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/124.0.0.0 Mobile Safari/537.36';

  final List<String> logs = [];

  Future<void> init(String extensionCode) async {
    if (_ready) return;
    _rt = getJavascriptRuntime(xhr: false);

    _rt.onMessage('host', (dynamic args) {
      // Fire-and-forget: the JS side is waiting on a promise that we settle.
      unawaited(_dispatch(args));
      return null;
    });

    final pre = _rt.evaluate(kJsPrelude);
    if (pre.isError) {
      throw StateError('Prelude failed: ${pre.stringResult}');
    }

    final res = _rt.evaluate(extensionCode);
    if (res.isError) {
      throw StateError('Extension $extensionId failed to load: ${res.stringResult}');
    }

    // QuickJS needs its microtask queue drained manually.
    _pump = Timer.periodic(const Duration(milliseconds: 8), (_) {
      try {
        _rt.executePendingJob();
      } catch (_) {/* runtime disposed mid-tick */}
    });

    _ready = true;
  }

  void dispose() {
    _pump?.cancel();
    _docs.clear();
    if (_ready) {
      try {
        _rt.dispose();
      } catch (_) {}
    }
    _ready = false;
  }

  // ---------------------------------------------------------------- calling

  /// Invokes `__sources[index].<method>(...args)` and awaits the promise.
  Future<dynamic> callSource(
    int index,
    String method,
    List<Object?> args,
  ) async {
    final argJson = args.map((a) => jsonEncode(a)).join(',');
    final code = '''
      (async () => {
        const s = globalThis.__sources[$index];
        if (!s) throw new Error('No source at index $index');
        if (typeof s.$method !== 'function') throw new Error('$method not implemented');
        const out = await s.$method($argJson);
        return JSON.stringify(out === undefined ? null : out);
      })()
    ''';
    final promise = await _rt.evaluateAsync(code);
    final result = await _rt.handlePromise(promise, timeout: const Duration(seconds: 60));
    if (result.isError) {
      throw ExtensionException(extensionId, method, result.stringResult);
    }
    final raw = result.stringResult;
    if (raw.isEmpty || raw == 'null' || raw == 'undefined') return null;
    return jsonDecode(raw);
  }

  /// Reads the metadata each registered source declares.
  Future<List<Map<String, dynamic>>> readSourceManifests() async {
    final res = _rt.evaluate('''
      JSON.stringify(globalThis.__sources.map(function (s, i) {
        return {
          index: i,
          id: s.id, name: s.name, lang: s.lang || 'en',
          baseUrl: s.baseUrl || '', type: s.type || 'manga',
          supportsLatest: s.supportsLatest !== false,
          hasFilters: typeof s.getFilters === 'function'
        };
      }))
    ''');
    if (res.isError) throw StateError(res.stringResult);
    return (jsonDecode(res.stringResult) as List)
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
  }

  // -------------------------------------------------------------- dispatch

  Future<void> _dispatch(dynamic raw) async {
    Map<String, dynamic> msg;
    try {
      msg = raw is String
          ? (jsonDecode(raw) as Map).cast<String, dynamic>()
          : (raw as Map).cast<String, dynamic>();
    } catch (e) {
      return;
    }
    final id = msg['id'];
    final method = '${msg['method']}';
    final params = ((msg['params'] ?? {}) as Map).cast<String, dynamic>();

    try {
      final result = await _handle(method, params);
      _settle(id, true, result);
    } catch (e) {
      _settle(id, false, {'message': e.toString()});
    }
  }

  void _settle(Object? id, bool ok, Object? payload) {
    if (!_ready) return;
    final encoded = jsonEncode(jsonEncode(payload));
    try {
      _rt.evaluate('__settle($id, $ok, $encoded);');
      _rt.executePendingJob();
    } catch (_) {}
  }

  Future<Object?> _handle(String method, Map<String, dynamic> p) async {
    switch (method) {
      case 'log':
        final line = '[$extensionId] ${(p['args'] as List?)?.join(' ')}';
        logs.add(line);
        if (logs.length > 300) logs.removeAt(0);
        if (kDebugMode) debugPrint(line);
        return null;

      case 'http':
        return _http(p);

      case 'parse':
        final handle = _DocHandle(
          html_parser.parse('${p['html']}'),
          '${p['baseUrl'] ?? ''}',
        );
        final id = ++_docSeq;
        _docs[id] = handle;
        // Bound memory: extensions rarely need more than a few live documents.
        if (_docs.length > 12) _docs.remove(_docs.keys.first);
        return {'id': id, 'baseUrl': handle.baseUrl};

      case 'select':
        final doc = _docs[p['doc'] as int];
        if (doc == null) throw StateError('Document handle expired');
        final scope = p['scope'] as String?;
        final root = scope == null ? doc.document : doc.resolve(scope);
        if (root == null) return <Object>[];
        final found = root.querySelectorAll('${p['selector']}');
        return found.map((e) => doc.describe(e)).toList();

      case 'docText':
        return _docs[p['doc'] as int]?.document.body?.text ?? '';

      case 'absUrl':
        final doc = _docs[p['doc'] as int];
        return _resolve(doc?.baseUrl ?? '', '${p['value']}');

      case 'resolve':
        return _resolve('${p['base']}', '${p['url']}');

      case 'sleep':
        await Future<void>.delayed(
            Duration(milliseconds: (p['ms'] as num?)?.toInt() ?? 0));
        return null;

      case 'storeGet':
        return store.get('$extensionId:${p['key']}');

      case 'storeSet':
        await store.set('$extensionId:${p['key']}', p['value']?.toString());
        return null;

      default:
        throw UnsupportedError('Unknown host method "$method"');
    }
  }

  Future<Map<String, dynamic>> _http(Map<String, dynamic> p) async {
    final url = '${p['url']}';
    final headers = <String, String>{
      'User-Agent': _defaultUserAgent,
      ...((p['headers'] as Map?)?.map((k, v) => MapEntry('$k', '$v')) ?? {}),
    };

    Object? body = p['body'];
    if (p['form'] is Map) {
      body = (p['form'] as Map).entries
          .map((e) =>
              '${Uri.encodeQueryComponent('${e.key}')}=${Uri.encodeQueryComponent('${e.value}')}')
          .join('&');
      headers.putIfAbsent(
          'Content-Type', () => 'application/x-www-form-urlencoded');
    }

    final res = await _dio.request<String>(
      url,
      data: body,
      options: Options(method: '${p['method'] ?? 'GET'}', headers: headers),
    );

    return {
      'status': res.statusCode ?? 0,
      'url': res.realUri.toString(),
      'headers': res.headers.map.map((k, v) => MapEntry(k, v.join(', '))),
      'body': res.data ?? '',
    };
  }

  static String _resolve(String base, String url) {
    if (url.isEmpty) return '';
    try {
      return Uri.parse(base).resolve(url).toString();
    } catch (_) {
      return url;
    }
  }
}

/// Keeps a parsed document alive and assigns stable paths to elements so the
/// JS side can hold references to them across bridge calls.
class _DocHandle {
  _DocHandle(this.document, this.baseUrl);
  final dom.Document document;
  final String baseUrl;

  final Map<String, dom.Element> _paths = {};
  int _seq = 0;

  dom.Element? resolve(String path) => _paths[path];

  Map<String, dynamic> describe(dom.Element e) {
    final path = 'e${++_seq}';
    _paths[path] = e;
    return {
      'path': path,
      'tag': e.localName,
      'text': e.text.trim(),
      'html': e.innerHtml,
      'outerHtml': e.outerHtml,
      'attrs': e.attributes.map((k, v) => MapEntry('$k', v)),
    };
  }
}

class ExtensionException implements Exception {
  ExtensionException(this.extensionId, this.method, this.message);
  final String extensionId;
  final String method;
  final String message;

  @override
  String toString() => 'Extension "$extensionId" failed in $method(): $message';
}

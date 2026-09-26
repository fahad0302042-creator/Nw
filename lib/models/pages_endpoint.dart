/// Describes how to resolve the readable pages of a manga chapter, or the
/// playable video links of an anime episode (same shape is reused for both).
///
/// Three modes:
///  - `simple`: one request returns the final list of image/video URLs
///    directly (HTML, JSON, "regex_json" - a regex pulls an embedded JSON
///    blob out of an HTML/JS response, common on manga reader pages that
///    inline `var pages = [...]` - or `static` for bundled demo data).
///  - `compose`: a first request resolves a small set of named variables
///    (e.g. MangaDex's `/at-home/server/{id}` endpoint returning a base URL,
///    a hash, and a file list) which are then combined via [urlTemplate] for
///    every element of [loopVar].
///  - `echo`: no request at all - the chapter/episode's own stored `url`
///    (optionally reshaped via [urlTemplate]) *is* the playable/readable
///    URL. Common for anime sources where the episode list already links
///    directly to a video file.
class PagesEndpoint {
  final String mode; // simple | compose

  // --- simple mode ---
  final String? url;
  final String method;
  final String responseType; // html | json | regex_json
  final String? itemSelector; // html
  final String? itemsPath; // json / regex_json
  final String? attr; // html: which attribute holds the image url
  final String? itemPath; // json/regex_json: sub-path per item (null = item is the url string)
  final String? regex;
  final int regexGroup;

  /// `static` mode (no network request): items are inlined directly here,
  /// used by bundled demo sources.
  final List<dynamic>? staticItems;

  // --- compose mode ---
  final String? resolveUrl;
  final String? resolveResponseType;
  final Map<String, String>? vars; // name -> json path, resolved from the resolve response
  final String? loopVar; // name of a var (must resolve to a List) to iterate
  final String? urlTemplate; // template using {varName} plus {item} for the current loop element

  /// Extra headers that must be sent when actually downloading/playing each
  /// resulting URL (e.g. `Referer` to defeat hotlink protection).
  final Map<String, String>? resourceHeaders;

  const PagesEndpoint({
    this.mode = 'simple',
    this.url,
    this.method = 'GET',
    this.responseType = 'html',
    this.itemSelector,
    this.itemsPath,
    this.attr = 'src',
    this.itemPath,
    this.regex,
    this.regexGroup = 1,
    this.staticItems,
    this.resolveUrl,
    this.resolveResponseType = 'json',
    this.vars,
    this.loopVar,
    this.urlTemplate,
    this.resourceHeaders,
  });

  factory PagesEndpoint.fromJson(Map<String, dynamic> json) {
    return PagesEndpoint(
      mode: json['mode'] as String? ?? 'simple',
      url: json['url'] as String?,
      method: (json['method'] as String? ?? 'GET').toUpperCase(),
      responseType: json['responseType'] as String? ?? 'html',
      itemSelector: json['itemSelector'] as String?,
      itemsPath: json['itemsPath'] as String?,
      attr: json['attr'] as String? ?? 'src',
      itemPath: json['itemPath'] as String?,
      regex: json['regex'] as String?,
      regexGroup: json['regexGroup'] as int? ?? 1,
      staticItems: json['items'] as List<dynamic>?,
      resolveUrl: json['resolveUrl'] as String?,
      resolveResponseType: json['resolveResponseType'] as String? ?? 'json',
      vars: (json['vars'] as Map?)?.map(
        (k, v) => MapEntry(k.toString(), v.toString()),
      ),
      loopVar: json['loopVar'] as String?,
      urlTemplate: json['urlTemplate'] as String?,
      resourceHeaders: (json['resourceHeaders'] as Map?)?.map(
        (k, v) => MapEntry(k.toString(), v.toString()),
      ),
    );
  }
}

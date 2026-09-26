/// A single extraction rule.
///
/// A rule describes *how* to pull one string out of an HTML element or a JSON
/// node. It is intentionally declarative so that extensions are plain JSON and
/// no code execution is required.
///
/// JSON forms accepted:
/// ```json
/// "h3 a"                       // css selector, text content
/// "img@data-src"               // css selector + attribute
/// "data.title"                 // json path (when the endpoint parses json)
/// {"sel": "a", "attr": "href"}
/// {"path": "cover", "prefix": "https://cdn.example/"}
/// {"regex": "\"url\":\"(.*?)\"", "group": 1}
/// ```
class Rule {
  const Rule({
    this.sel,
    this.attr,
    this.path,
    this.regex,
    this.group = 1,
    this.strip,
    this.prefix,
    this.suffix,
    this.value,
    this.all = false,
  });

  /// CSS selector, relative to the current node. `null` means "current node".
  final String? sel;

  /// Attribute to read. `text`, `html`, `outerHtml` or any DOM attribute.
  /// Multiple fallbacks can be given comma separated: `data-src,src`.
  final String? attr;

  /// Dotted json path, relative to the current node. Empty/`.` means "self".
  final String? path;

  /// Optional regex applied to the extracted string.
  final String? regex;

  /// Capture group used with [regex].
  final int group;

  /// Regex whose matches are removed from the result.
  final String? strip;

  final String? prefix;
  final String? suffix;

  /// Constant value; short circuits every other field.
  final String? value;

  /// Collect every match instead of the first one.
  final bool all;

  bool get isEmpty =>
      sel == null &&
      attr == null &&
      path == null &&
      regex == null &&
      value == null;

  List<String> get attrCandidates {
    final raw = attr;
    if (raw == null || raw.trim().isEmpty) return const <String>['text'];
    return raw
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
  }

  static Rule? maybe(dynamic json) {
    if (json == null) return null;
    return Rule.fromJson(json);
  }

  factory Rule.fromJson(dynamic json) {
    if (json is String) {
      // Shorthand. Kept usable for both html ("a@href") and json ("data.url")
      // endpoints by filling in both `sel`/`attr` and `path`.
      final at = json.indexOf('@');
      if (at >= 0) {
        return Rule(
          sel: at == 0 ? null : json.substring(0, at),
          attr: json.substring(at + 1),
          path: at == 0 ? null : json.substring(0, at),
        );
      }
      return Rule(sel: json, path: json);
    }
    if (json is Map) {
      final map = json.cast<String, dynamic>();
      return Rule(
        sel: _str(map['sel'] ?? map['selector'] ?? map['css']),
        attr: _str(map['attr'] ?? map['attribute']),
        path: _str(map['path'] ?? map['json'] ?? map['key']),
        regex: _str(map['regex'] ?? map['match']),
        group: _int(map['group']) ?? 1,
        strip: _str(map['strip'] ?? map['remove']),
        prefix: _str(map['prefix']),
        suffix: _str(map['suffix']),
        value: _str(map['value'] ?? map['const']),
        all: map['all'] == true,
      );
    }
    return const Rule();
  }

  /// Applies regex / strip / prefix / suffix post-processing.
  String? apply(String? raw) {
    if (raw == null) return null;
    var value = raw.trim();
    final pattern = regex;
    if (pattern != null && pattern.isNotEmpty) {
      final match = RegExp(pattern, dotAll: true).firstMatch(value);
      if (match == null) return null;
      final wanted = group <= match.groupCount ? match.group(group) : match.group(0);
      if (wanted == null) return null;
      value = wanted;
    }
    final stripPattern = strip;
    if (stripPattern != null && stripPattern.isNotEmpty) {
      value = value.replaceAll(RegExp(stripPattern, dotAll: true), '');
    }
    value = value.trim();
    if (prefix != null) value = '$prefix$value';
    if (suffix != null) value = '$value$suffix';
    return value;
  }

  static String? _str(dynamic value) {
    if (value == null) return null;
    final text = value.toString();
    return text.isEmpty ? null : text;
  }

  static int? _int(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }
}

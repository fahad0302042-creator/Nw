/// Describes how to pull a single field's value out of one catalog / detail
/// item, for either HTML (CSS selector) or JSON (dotted path) sources.
///
/// See `docs/EXTENSION_SPEC.md` for the full authoring guide.
class FieldSpec {
  /// CSS selector, relative to the item's root element (HTML mode only).
  final String? selector;

  /// What to pull from the matched element: `text`, `html`, `src`, `href`,
  /// or any other attribute name. Defaults to `text`.
  final String attr;

  /// Dotted/indexed path, relative to the item root (JSON mode only). See
  /// [resolveJsonPath] for the mini path language.
  final String? path;

  /// If set, ignores [selector]/[path] and instead builds the value by
  /// substituting `{otherField}` placeholders with values already extracted
  /// for this same item (extraction order follows manifest field order).
  final String? template;

  /// Resolve the extracted value into an absolute URL using the source's
  /// base URL.
  final bool absolute;

  /// Optional regex applied to the extracted raw string; only [regexGroup]
  /// is kept.
  final String? regex;
  final int regexGroup;

  /// When true, this field resolves to a `List<String>` instead of a single
  /// string: in HTML mode [selector] matches multiple elements and [attr] is
  /// read from each; in JSON mode [path] points at an array and [itemPath]
  /// (optional) extracts a sub-value from each element.
  final bool list;
  final String? itemPath;

  /// Literal value returned when nothing could be extracted.
  final String? fallback;

  const FieldSpec({
    this.selector,
    this.attr = 'text',
    this.path,
    this.template,
    this.absolute = false,
    this.regex,
    this.regexGroup = 1,
    this.list = false,
    this.itemPath,
    this.fallback,
  });

  factory FieldSpec.fromJson(dynamic json) {
    if (json is String) {
      // Shorthand: a bare string is treated as a JSON path or CSS selector
      // depending on context; the engine decides based on response type.
      return FieldSpec(path: json, selector: json);
    }
    final map = Map<String, dynamic>.from(json as Map);
    return FieldSpec(
      selector: map['selector'] as String?,
      attr: map['attr'] as String? ?? 'text',
      path: map['path'] as String?,
      template: map['template'] as String?,
      absolute: map['absolute'] as bool? ?? false,
      regex: map['regex'] as String?,
      regexGroup: map['regexGroup'] as int? ?? 1,
      list: map['list'] as bool? ?? false,
      itemPath: map['itemPath'] as String?,
      fallback: map['fallback'] as String?,
    );
  }
}

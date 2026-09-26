import 'package:html/dom.dart' as dom;

import '../../models/field_spec.dart';
import '../parsing/path_resolver.dart';
import '../parsing/template.dart';
import '../parsing/url_utils.dart';

/// Extracts every field declared in [fields] out of one HTML element or one
/// decoded JSON node ([itemRoot]), in declaration order so that `template`
/// fields can reference already-extracted siblings.
Map<String, dynamic> extractFields(
  dynamic itemRoot,
  Map<String, FieldSpec> fields,
  String responseType,
  String baseUrl,
) {
  final extracted = <String, dynamic>{};
  fields.forEach((name, spec) {
    extracted[name] = responseType == 'html'
        ? _extractHtmlField(itemRoot as dom.Element?, spec, extracted, baseUrl)
        : _extractJsonField(itemRoot, spec, extracted, baseUrl);
  });
  return extracted;
}

String? _readAttr(dom.Element el, String attr) {
  switch (attr) {
    case 'text':
      return el.text.trim();
    case 'html':
      return el.innerHtml;
    case 'ownText':
      return el.nodes
          .whereType<dom.Text>()
          .map((n) => n.text)
          .join()
          .trim();
    default:
      return el.attributes[attr];
  }
}

dynamic _extractHtmlField(
  dom.Element? itemRoot,
  FieldSpec spec,
  Map<String, dynamic> extracted,
  String baseUrl,
) {
  if (spec.template != null) {
    return applyTemplate(
      spec.template!,
      extracted.map((k, v) => MapEntry(k, v?.toString())),
    );
  }
  if (itemRoot == null) return spec.list ? const <String>[] : spec.fallback;

  if (spec.list) {
    final elements =
        (spec.selector == null || spec.selector!.isEmpty)
            ? [itemRoot]
            : itemRoot.querySelectorAll(spec.selector!);
    final values = elements
        .map((e) => _readAttr(e, spec.attr))
        .whereType<String>()
        .map((v) => spec.absolute ? (resolveUrl(v, baseUrl) ?? v) : v)
        .toList();
    return values;
  }

  final el = (spec.selector == null || spec.selector!.isEmpty)
      ? itemRoot
      : itemRoot.querySelector(spec.selector!);
  String? value = el != null ? _readAttr(el, spec.attr) : null;
  value ??= spec.fallback;
  if (value != null && spec.regex != null) {
    final match = RegExp(spec.regex!, dotAll: true).firstMatch(value);
    value = match?.group(spec.regexGroup);
  }
  if (value != null && spec.absolute) {
    value = resolveUrl(value, baseUrl);
  }
  return value;
}

dynamic _extractJsonField(
  dynamic itemRoot,
  FieldSpec spec,
  Map<String, dynamic> extracted,
  String baseUrl,
) {
  if (spec.template != null) {
    return applyTemplate(
      spec.template!,
      extracted.map((k, v) => MapEntry(k, v?.toString())),
    );
  }

  if (spec.list) {
    final listValue = resolveJsonPath(itemRoot, spec.path);
    if (listValue is! List) return const <String>[];
    return listValue
        .map((e) =>
            spec.itemPath != null ? resolveJsonPathAsString(e, spec.itemPath) : e?.toString())
        .whereType<String>()
        .map((v) => spec.absolute ? (resolveUrl(v, baseUrl) ?? v) : v)
        .toList();
  }

  String? value = resolveJsonPathAsString(itemRoot, spec.path) ?? spec.fallback;
  if (value != null && spec.regex != null) {
    final match = RegExp(spec.regex!, dotAll: true).firstMatch(value);
    value = match?.group(spec.regexGroup);
  }
  if (value != null && spec.absolute) {
    value = resolveUrl(value, baseUrl);
  }
  return value;
}

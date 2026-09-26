/// Replaces `{key}` placeholders in [template] using [vars].
///
/// Unknown placeholders are left untouched so authors can debug manifests
/// more easily, and URL-unsafe characters in substituted values can
/// optionally be percent-encoded via [encodeValues] (used for query
/// parameters such as search terms).
String applyTemplate(
  String template,
  Map<String, String?> vars, {
  bool encodeValues = false,
}) {
  var result = template;
  vars.forEach((key, value) {
    if (value == null) return;
    final replacement = encodeValues ? Uri.encodeComponent(value) : value;
    result = result.replaceAll('{$key}', replacement);
  });
  return result;
}

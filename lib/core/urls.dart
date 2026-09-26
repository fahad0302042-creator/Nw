/// URL helpers used when resolving relative links coming from extensions.

/// Resolves [url] against [base].
///
/// * absolute urls are returned untouched
/// * protocol relative urls (`//host/x`) get an `https:` prefix
/// * root relative urls (`/x`) are resolved against the origin of [base]
/// * everything else is appended to [base]
String resolveUrl(String base, String url) {
  final value = url.trim();
  if (value.isEmpty) return value;
  if (value.startsWith('http://') ||
      value.startsWith('https://') ||
      value.startsWith('data:')) {
    return value;
  }
  if (value.startsWith('//')) return 'https:$value';
  if (base.isEmpty) return value;

  final baseUri = Uri.tryParse(base);
  if (baseUri == null || !baseUri.hasScheme) return value;

  if (value.startsWith('/')) {
    return '${baseUri.scheme}://${baseUri.authority}$value';
  }
  final trimmedBase = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
  return '$trimmedBase/$value';
}

/// Replaces `{key}` placeholders inside [template] with values from [vars].
String applyTemplate(String template, Map<String, String> vars) {
  var out = template;
  vars.forEach((key, value) {
    out = out.replaceAll('{$key}', value);
  });
  return out;
}

/// Unescapes url fragments that were extracted from inline JavaScript.
String cleanExtractedUrl(String value) {
  var out = value.trim();
  out = out.replaceAll(r'\/', '/');
  out = out.replaceAll(r'\u002F', '/');
  out = out.replaceAll(r'\u003A', ':');
  out = out.replaceAll('&amp;', '&');
  return out;
}

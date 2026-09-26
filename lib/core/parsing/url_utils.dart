/// Resolves [maybeRelative] against [baseUrl] if it looks relative.
/// Leaves absolute (http/https/data) URLs untouched.
String? resolveUrl(String? maybeRelative, String baseUrl) {
  if (maybeRelative == null || maybeRelative.isEmpty) return maybeRelative;
  if (maybeRelative.startsWith('http://') ||
      maybeRelative.startsWith('https://') ||
      maybeRelative.startsWith('data:')) {
    return maybeRelative;
  }
  try {
    final base = Uri.parse(baseUrl);
    return base.resolve(maybeRelative).toString();
  } catch (_) {
    return maybeRelative;
  }
}

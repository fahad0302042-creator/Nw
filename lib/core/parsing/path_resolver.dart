/// Resolves a small, dependency-free "path" language against decoded JSON
/// (Maps / Lists / primitives). Used by JSON-mode extension sources so that
/// extension authors can pull values out of arbitrary API responses without
/// any code, only a manifest file.
///
/// Supported segment syntax (segments are separated by `.`):
///   - `foo`        -> Map key lookup
///   - `3`          -> List index lookup
///   - `key=value`  -> given the current value is a List<Map>, finds the
///                     first element whose `key` stringifies to `value`.
///                     Useful for relationship arrays, e.g.
///                     `relationships.type=cover_art.attributes.fileName`.
///
/// An empty path (or `.` / `\$`) returns the root value unchanged.
dynamic resolveJsonPath(dynamic root, String? path) {
  if (path == null || path.isEmpty || path == '.' || path == r'$') {
    return root;
  }
  dynamic current = root;
  for (final rawSegment in path.split('.')) {
    if (rawSegment.isEmpty) continue;
    if (current == null) return null;

    if (rawSegment.contains('=')) {
      final parts = rawSegment.split('=');
      final key = parts.first;
      final value = parts.sublist(1).join('=');
      if (current is List) {
        current = current.firstWhere(
          (e) => e is Map && '${e[key]}' == value,
          orElse: () => null,
        );
      } else {
        return null;
      }
      continue;
    }

    final index = int.tryParse(rawSegment);
    if (index != null && current is List) {
      current = (index >= 0 && index < current.length) ? current[index] : null;
    } else if (current is Map) {
      current = current[rawSegment];
    } else {
      return null;
    }
  }
  return current;
}

/// Convenience for cases where the resolved value should be a String.
String? resolveJsonPathAsString(dynamic root, String? path) {
  final value = resolveJsonPath(root, path);
  if (value == null) return null;
  return value.toString();
}

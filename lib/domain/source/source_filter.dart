/// Search filters declared by a source, mirroring Tachiyomi's filter list.
sealed class SourceFilter {
  const SourceFilter({required this.key, required this.name});
  final String key;
  final String name;

  static SourceFilter fromJson(Map<String, dynamic> j) {
    final key = (j['key'] ?? j['name'] ?? '').toString();
    final name = (j['name'] ?? key).toString();
    return switch ((j['type'] ?? 'text').toString()) {
      'select' => SelectFilter(
          key: key,
          name: name,
          options: (j['options'] as List? ?? const [])
              .map((e) => e is Map
                  ? FilterOption('${e['label']}', '${e['value']}')
                  : FilterOption('$e', '$e'))
              .toList(),
        ),
      'checkbox' => CheckboxFilter(key: key, name: name),
      'tristate' => TriStateFilter(key: key, name: name),
      'group' => GroupFilter(
          key: key,
          name: name,
          children: (j['filters'] as List? ?? const [])
              .map((e) => SourceFilter.fromJson((e as Map).cast<String, dynamic>()))
              .toList(),
        ),
      'sort' => SortFilter(
          key: key,
          name: name,
          options: (j['options'] as List? ?? const []).map((e) => '$e').toList(),
        ),
      _ => TextFilter(key: key, name: name),
    };
  }
}

class FilterOption {
  const FilterOption(this.label, this.value);
  final String label;
  final String value;
}

class TextFilter extends SourceFilter {
  const TextFilter({required super.key, required super.name});
}

class SelectFilter extends SourceFilter {
  const SelectFilter({
    required super.key,
    required super.name,
    required this.options,
  });
  final List<FilterOption> options;
}

class CheckboxFilter extends SourceFilter {
  const CheckboxFilter({required super.key, required super.name});
}

/// Include / exclude / ignore — the classic genre filter.
class TriStateFilter extends SourceFilter {
  const TriStateFilter({required super.key, required super.name});
}

class SortFilter extends SourceFilter {
  const SortFilter({
    required super.key,
    required super.name,
    required this.options,
  });
  final List<String> options;
}

class GroupFilter extends SourceFilter {
  const GroupFilter({
    required super.key,
    required super.name,
    required this.children,
  });
  final List<SourceFilter> children;
}

enum TriState { ignore, include, exclude }

/// A user-selected value for a filter, sent back to the source.
class FilterValue {
  const FilterValue(this.key, this.value);
  final String key;

  /// String, bool, int (sort index) or 'include'/'exclude'.
  final Object? value;

  Map<String, dynamic> toJson() => {'key': key, 'value': value};
}

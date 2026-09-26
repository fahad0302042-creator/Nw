/// A lightweight entry from a repository's `index.json`, before the full
/// extension manifest has been downloaded/installed.
class ExtensionSummary {
  final String id;
  final String name;
  final String lang;
  final String version;
  final String type; // manga | anime
  final String? icon;
  final String? description;

  /// Absolute URL to download the full manifest from. Empty when [inline]
  /// is provided instead.
  final String sourceUrl;

  /// Some repositories may embed the full manifest directly in the index
  /// instead of linking to a separate file.
  final Map<String, dynamic>? inline;

  final String repoUrl;

  const ExtensionSummary({
    required this.id,
    required this.name,
    required this.lang,
    required this.version,
    required this.type,
    required this.repoUrl,
    this.icon,
    this.description,
    this.sourceUrl = '',
    this.inline,
  });
}

/// A single readable page image (manga) or a playable video stream link
/// (anime).
class PageEntry {
  final String url;
  final Map<String, String>? headers;
  final String? label; // e.g. video quality: "1080p"

  const PageEntry({required this.url, this.headers, this.label});
}

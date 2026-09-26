/// Normalises the URLs people actually paste when adding a repository.
///
/// Nobody copies the raw `index.json` link. They copy the GitHub page they
/// are looking at, or the repo root, and expect it to work — so meet them
/// there instead of rejecting it.
library;

class RepoUrl {
  /// Rewrites a human-pasted URL into something that should return JSON.
  static String normalize(String input) {
    var url = input.trim();
    if (url.isEmpty) return url;

    // Bare host or path with no scheme.
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }

    Uri uri;
    try {
      uri = Uri.parse(url);
    } catch (_) {
      return url;
    }

    // A GitHub web page is not a file. Rewrite blob/tree links to raw.
    if (uri.host == 'github.com') {
      final seg = uri.pathSegments;
      final marker = seg.indexOf('blob') >= 0 ? 'blob' : 'tree';
      final at = seg.indexOf(marker);
      if (at >= 2 && seg.length > at + 1) {
        final owner = seg[0];
        final repo = seg[1];
        final rest = seg.sublist(at + 1);
        uri = Uri.https('raw.githubusercontent.com',
            '/$owner/$repo/${rest.join('/')}');
      }
    }

    // Anything that is not obviously a file gets the conventional filename.
    final path = uri.path;
    final last = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
    final looksLikeFile = last.contains('.');
    if (!looksLikeFile) {
      final base = path.endsWith('/') ? path : '$path/';
      uri = uri.replace(path: '${base}index.json');
    }

    return uri.toString();
  }

  /// True when the URL points at a GitHub page rather than a raw file, which
  /// is the single most common mistake.
  static bool isGithubPage(String url) {
    final uri = Uri.tryParse(url);
    return uri?.host == 'github.com';
  }
}

/// Minimal HLS playlist handling, enough to download an episode offline.
library;

class HlsVariant {
  const HlsVariant({required this.url, this.bandwidth = 0, this.resolution});
  final String url;
  final int bandwidth;
  final String? resolution;
}

class HlsPlaylist {
  const HlsPlaylist({
    required this.isMaster,
    this.variants = const [],
    this.segments = const [],
    this.encrypted = false,
    this.initSegment,
  });

  final bool isMaster;

  /// Populated when [isMaster]: the renditions to choose between.
  final List<HlsVariant> variants;

  /// Populated for a media playlist: the segments to fetch, in order.
  final List<String> segments;

  /// True when the playlist declares AES/SAMPLE-AES encryption. We refuse
  /// these rather than writing an unplayable file the user only discovers
  /// offline on a train.
  final bool encrypted;

  /// fMP4 initialisation segment, if the playlist uses EXT-X-MAP.
  final String? initSegment;
}

class Hls {
  static bool looksLikeHls(String url) {
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? url.toLowerCase();
    return path.endsWith('.m3u8') || path.endsWith('.m3u');
  }

  /// Parses a playlist, resolving every URI against [baseUrl].
  static HlsPlaylist parse(String body, String baseUrl) {
    final base = Uri.parse(baseUrl);
    String abs(String u) {
      try {
        return base.resolve(u.trim()).toString();
      } catch (_) {
        return u.trim();
      }
    }

    final lines = body
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    final variants = <HlsVariant>[];
    final segments = <String>[];
    var encrypted = false;
    String? initSegment;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];

      if (line.startsWith('#EXT-X-KEY')) {
        // METHOD=NONE is legal and means "not encrypted".
        if (!line.contains('METHOD=NONE')) encrypted = true;
        continue;
      }

      if (line.startsWith('#EXT-X-MAP')) {
        final m = RegExp(r'URI="([^"]+)"').firstMatch(line);
        if (m != null) initSegment = abs(m.group(1)!);
        continue;
      }

      if (line.startsWith('#EXT-X-STREAM-INF')) {
        final bandwidth = int.tryParse(
                RegExp(r'BANDWIDTH=(\d+)').firstMatch(line)?.group(1) ?? '') ??
            0;
        final resolution =
            RegExp(r'RESOLUTION=([0-9x]+)').firstMatch(line)?.group(1);
        // The URI is the next non-comment line.
        for (var j = i + 1; j < lines.length; j++) {
          if (!lines[j].startsWith('#')) {
            variants.add(HlsVariant(
              url: abs(lines[j]),
              bandwidth: bandwidth,
              resolution: resolution,
            ));
            i = j;
            break;
          }
        }
        continue;
      }

      if (!line.startsWith('#')) segments.add(abs(line));
    }

    final isMaster = variants.isNotEmpty;
    return HlsPlaylist(
      isMaster: isMaster,
      variants: variants,
      segments: isMaster ? const [] : segments,
      encrypted: encrypted,
      initSegment: initSegment,
    );
  }

  /// Highest-bandwidth rendition — offline copies should be the good one.
  static HlsVariant? bestVariant(HlsPlaylist playlist) {
    if (playlist.variants.isEmpty) return null;
    return playlist.variants
        .reduce((a, b) => b.bandwidth > a.bandwidth ? b : a);
  }
}

/// Raised when a stream cannot be stored offline, with a reason worth
/// showing to the user rather than a stack trace.
class UnsupportedStreamException implements Exception {
  UnsupportedStreamException(this.message);
  final String message;
  @override
  String toString() => message;
}

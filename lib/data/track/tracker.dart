import '../../domain/models/media.dart';
import '../../domain/models/track.dart';

/// Contract every tracking service implements.
///
/// Kept deliberately small: search, link, push progress. Anything richer
/// (custom lists, rewatch counts, notes) differs so much between services
/// that abstracting it would help nobody.
abstract class Tracker {
  TrackerId get id;
  String get name => id.label;

  /// Whether the user has authorised this service.
  bool get isLoggedIn;

  /// Display name of the signed-in account, when known.
  String? get accountName;

  /// Whether this service can track the given medium. MyAnimeList and
  /// AniList both handle manga and anime, but their APIs differ per medium.
  bool supports(MediaType type) => true;

  /// OAuth entry point. Returns the URL to open in a WebView.
  Uri authorizationUrl();

  /// Called with the redirect URL the WebView landed on. Returns true when
  /// a token was successfully extracted and stored.
  Future<bool> handleRedirect(Uri redirect);

  Future<void> logout();

  Future<List<TrackSearchResult>> search(String query, MediaType type);

  /// Reads the user's current entry for [remoteId], if any.
  Future<TrackLink?> fetch(String remoteId, MediaType type);

  /// Pushes progress/status/score. Implementations should be idempotent.
  Future<void> push(TrackLink link, MediaType type);
}

/// Thrown for authorisation problems, so the UI can prompt a re-login
/// instead of showing a raw HTTP error.
class TrackerAuthException implements Exception {
  TrackerAuthException(this.tracker, this.message);
  final TrackerId tracker;
  final String message;
  @override
  String toString() => '${tracker.label}: $message';
}

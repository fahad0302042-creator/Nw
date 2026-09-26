import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Local notifications for finished library updates.
///
/// Best-effort by design: if the user denies the permission, or the plugin
/// fails on some OEM ROM, the app must carry on working silently rather
/// than surfacing an error for a cosmetic feature.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _channelId = 'library_updates';
  static const _channelName = 'Library updates';

  Future<void> init() async {
    if (_ready) return;
    try {
      await _plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      _ready = true;
    } catch (e) {
      debugPrint('Notifications unavailable: $e');
    }
  }

  /// Android 13+ requires an explicit runtime permission.
  Future<bool> requestPermission() async {
    await init();
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      return await android?.requestNotificationsPermission() ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> showLibraryUpdate({
    required int titles,
    required int newUnits,
    required List<String> sampleTitles,
  }) async {
    if (newUnits <= 0) return;
    await init();
    if (!_ready) return;

    final body = sampleTitles.take(4).join(', ') +
        (sampleTitles.length > 4 ? ' and more' : '');

    try {
      await _plugin.show(
        1001,
        '$newUnits new ${newUnits == 1 ? 'chapter' : 'chapters'} '
        'in $titles ${titles == 1 ? 'title' : 'titles'}',
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: 'Notifies when new chapters or episodes arrive',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
            styleInformation: BigTextStyleInformation(''),
          ),
        ),
      );
    } catch (e) {
      debugPrint('Could not post notification: $e');
    }
  }
}

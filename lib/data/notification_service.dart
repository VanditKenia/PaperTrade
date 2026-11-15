import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final notificationServiceProvider = Provider<NotificationService>(
  (ref) => NotificationService(),
);

/// System notifications for price alerts, Android only. Everywhere else
/// (web, tests) every method is a no-op: the in-app snackbar covers it.
class NotificationService {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  // kIsWeb first: defaultTargetPlatform alone can report Android for a
  // browser on an Android phone.
  bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> _init() async {
    if (_initialized) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    _initialized = true;
  }

  /// Android 13+ asks the user once; older versions grant it at install.
  /// False if denied or unsupported. Never throws.
  Future<bool> requestPermission() async {
    if (!_supported) return false;
    try {
      await _init();
      return await _plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()
              ?.requestNotificationsPermission() ??
          false;
    } on Exception catch (e) {
      if (kDebugMode) debugPrint('Notification permission failed: $e');
      return false;
    }
  }

  /// Shows a notification; silently does nothing if not allowed. Never
  /// throws: a missing notification must not break the alert flow.
  Future<void> show(int id, String title, String body) async {
    if (!_supported) return;
    try {
      await _init();
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'price_alerts',
            'Price alerts',
            channelDescription: 'When a stock crosses a price you set',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
      );
    } on Exception catch (e) {
      if (kDebugMode) debugPrint('Showing notification failed: $e');
    }
  }
}

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

enum JourneyReminderResult {
  scheduledExact,
  scheduledInexact,
  shownNow,
  permissionDenied,
  failed,
}

class JourneyNotificationService {
  JourneyNotificationService._();

  static final JourneyNotificationService instance =
      JourneyNotificationService._();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  Future<void>? _initialisation;

  Future<void> initialise() {
    return _initialisation ??= _initialise();
  }

  Future<void> _initialise() async {
    tz_data.initializeTimeZones();
    // This application only plans journeys inside Malaysia.
    tz.setLocalLocation(tz.getLocation('Asia/Kuala_Lumpur'));

    await _notifications.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
  }

  Future<JourneyReminderResult> scheduleJourney({
    required String journeyId,
    required String origin,
    required String destination,
    required DateTime departureTime,
  }) async {
    try {
      return await _scheduleJourney(
        journeyId: journeyId,
        origin: origin,
        destination: destination,
        departureTime: departureTime,
      );
    } catch (_) {
      return JourneyReminderResult.failed;
    }
  }

  Future<JourneyReminderResult> _scheduleJourney({
    required String journeyId,
    required String origin,
    required String destination,
    required DateTime departureTime,
  }) async {
    await initialise();

    final android = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final androidNotificationsAllowed = await android
        ?.requestNotificationsPermission();
    if (androidNotificationsAllowed == false) {
      return JourneyReminderResult.permissionDenied;
    }

    final ios = _notifications
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    final iosNotificationsAllowed = await ios?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );
    if (iosNotificationsAllowed == false) {
      return JourneyReminderResult.permissionDenied;
    }

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'journey_departures',
        'Journey departures',
        channelDescription: 'Notifications when a planned journey begins',
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.reminder,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );
    final notificationId = _notificationId(journeyId);
    final body = '$origin to $destination is ready to start.';
    final now = DateTime.now();

    if (!departureTime.isAfter(now.add(const Duration(seconds: 5)))) {
      await _notifications.show(
        id: notificationId,
        title: 'Your planned journey starts now',
        body: body,
        notificationDetails: details,
        payload: journeyId,
      );
      return JourneyReminderResult.shownNow;
    }

    final exactAlarmAllowed =
        await android?.requestExactAlarmsPermission() ?? true;
    await _notifications.zonedSchedule(
      id: notificationId,
      title: 'Your planned journey starts now',
      body: body,
      scheduledDate: tz.TZDateTime.from(departureTime, tz.local),
      notificationDetails: details,
      androidScheduleMode: exactAlarmAllowed
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
      payload: journeyId,
    );
    return exactAlarmAllowed
        ? JourneyReminderResult.scheduledExact
        : JourneyReminderResult.scheduledInexact;
  }

  Future<void> cancelJourney(String journeyId) async {
    try {
      await initialise();
      await _notifications.cancel(id: _notificationId(journeyId));
    } catch (_) {
      // Removing a saved plan must still succeed if the platform notification
      // service is temporarily unavailable.
    }
  }

  int _notificationId(String journeyId) {
    var hash = 0x811C9DC5;
    for (final value in journeyId.codeUnits) {
      hash ^= value;
      hash = (hash * 0x01000193) & 0x7FFFFFFF;
    }
    return hash;
  }
}

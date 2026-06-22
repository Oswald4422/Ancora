import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

// Workmanager is mobile-only; web stub keeps chrome builds clean.
import '_workmanager_io.dart'
    if (dart.library.html) '_workmanager_web.dart';

final _localNotifs = FlutterLocalNotificationsPlugin();

const _kAndroidNotifDetails = AndroidNotificationDetails(
  'ancora_reminders',
  'Medication Reminders',
  importance: Importance.high,
  priority: Priority.high,
);
const _kNotifDetails = NotificationDetails(android: _kAndroidNotifDetails);

// v2: channel properties are immutable after creation — new ID forces fresh channel
// with alarm audio stream (separate volume from notifications, bypasses DND).
const _kAlarmChannelId = 'ancora_dose_alarm_v2';
const _kAndroidAlarmDetails = AndroidNotificationDetails(
  _kAlarmChannelId,
  'Dose Alarm',
  importance: Importance.max,
  priority: Priority.max,
  sound: UriAndroidNotificationSound('content://settings/system/alarm_alert'),
  playSound: true,
  enableVibration: true,
  audioAttributesUsage: AudioAttributesUsage.alarm,
  category: AndroidNotificationCategory.alarm,
);
const _kAlarmNotifDetails = NotificationDetails(android: _kAndroidAlarmDetails);

AndroidFlutterLocalNotificationsPlugin? get _androidPlugin =>
    _localNotifs.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

// Minutes before the dose time at which each cascading reminder fires.
// Index 0..3 are pre-dose warnings; index 4 fires at the exact dose time.
const _kReminderOffsets = [-60, -30, -10, -5, 0];

class NotificationService {
  static Future<void> init() async {
    tz_data.initializeTimeZones();
    if (!kIsWeb) {
      try {
        final tzName = await FlutterTimezone.getLocalTimezone();
        tz.setLocalLocation(tz.getLocation(tzName));
      } catch (e) {
        debugPrint('Timezone setup failed, defaulting to UTC: $e');
      }
    }

    if (!kIsWeb) {
      await _localNotifs
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              'ancora_reminders',
              'Medication Reminders',
              importance: Importance.high,
            ),
          );
      await _localNotifs
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              _kAlarmChannelId,
              'Dose Alarm',
              importance: Importance.max,
              sound: UriAndroidNotificationSound(
                  'content://settings/system/alarm_alert'),
              audioAttributesUsage: AudioAttributesUsage.alarm,
            ),
          );

      await _localNotifs.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );

      // Request POST_NOTIFICATIONS permission on Android 13+ (API 33+).
      await _androidPlugin?.requestNotificationsPermission();
      // Request exact alarm permission on Android 12+ (API 31+).
      await _androidPlugin?.requestExactAlarmsPermission();

      await initWorkmanager();
    }

    try {
      await _initFcm();
    } catch (e) {
      debugPrint('FCM init skipped: $e');
    }
  }

  /// Call this inside a workmanager isolate before using any local notification
  /// APIs, since init() only runs in the main isolate.
  static Future<void> initForIsolate() async {
    if (kIsWeb) return;
    tz_data.initializeTimeZones();
    try {
      final tzName = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(tzName));
    } catch (e) {
      debugPrint('Timezone setup failed, defaulting to UTC: $e');
    }
    await _localNotifs.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
  }

  static Future<void> _initFcm() async {
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(
        alert: true, badge: true, sound: true);

    final token = await messaging.getToken();
    if (token != null) await _storeToken(token);
    messaging.onTokenRefresh.listen(_storeToken);

    // Show foreground FCM messages as local notifications on mobile.
    if (!kIsWeb) {
      FirebaseMessaging.onMessage.listen((msg) {
        final n = msg.notification;
        if (n == null) return;
        _localNotifs.show(
          id: msg.hashCode,
          title: n.title,
          body: n.body,
          notificationDetails: _kNotifDetails,
        );
      });
    }
  }

  static Future<void> _storeToken(String token) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('fcmTokens')
        .doc(token)
        .set({
      'platform': kIsWeb ? 'web' : 'android',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Returns true if exact alarms are permitted on this device.
  /// Call from the UI and show a dialog prompting the user to enable
  /// Settings → Apps → Ancora → Special App Access → Alarms & Reminders if false.
  static Future<bool> canScheduleExact() async {
    if (kIsWeb) return false;
    final granted = await _androidPlugin?.requestExactAlarmsPermission();
    return granted ?? false;
  }

  static Future<void> deleteCurrentToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('fcmTokens')
            .doc(token)
            .delete();
      }
      await FirebaseMessaging.instance.deleteToken();
    } catch (e, st) {
      debugPrint('deleteCurrentToken failed: $e\n$st');
    }
  }

  static Future<void> scheduleMedication({
    required String medId,
    required String medName,
    required List<String> intakeTimes,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    if (kIsWeb) return;

    await cancelMedication(medId);

    final now = DateTime.now();
    final window = now.add(const Duration(hours: 48));
    final idBase = medId.hashCode.abs() % 100000;
    int slotIndex = 0;

    for (int dayOffset = 0; dayOffset <= 2; dayOffset++) {
      final day = now.add(Duration(days: dayOffset));
      final dayStart = DateTime(day.year, day.month, day.day);
      if (dayStart.isBefore(startDate) || dayStart.isAfter(endDate)) {
        continue;
      }

      for (final t in intakeTimes) {
        final parts = t.split(':');
        if (parts.length != 2) continue;
        final h = int.tryParse(parts[0]) ?? 0;
        final m = int.tryParse(parts[1]) ?? 0;
        final scheduledAt = DateTime(day.year, day.month, day.day, h, m);

        for (int ri = 0; ri < _kReminderOffsets.length; ri++) {
          final offsetMins = _kReminderOffsets[ri];
          final fireAt = scheduledAt.add(Duration(minutes: offsetMins));
          if (fireAt.isBefore(now) || fireAt.isAfter(window)) continue;

          final String title;
          final String body;
          if (offsetMins == 0) {
            title = 'Time for $medName!';
            body = 'Take your dose now.';
          } else if (offsetMins == -60) {
            title = '1 hour until your $medName dose';
            body = 'Tap to prepare for your upcoming dose.';
          } else {
            title = '${-offsetMins} minutes until your $medName dose';
            body = 'Tap to prepare for your upcoming dose.';
          }

          await _scheduleOne(
            id: idBase + slotIndex * 5 + ri,
            title: title,
            body: body,
            fireAt: fireAt,
          );
        }

        slotIndex++;
      }
    }
  }

  // Tries alarmClock mode first; falls back to exactAllowWhileIdle if
  // USE_EXACT_ALARM / SCHEDULE_EXACT_ALARM are not granted (common on Samsung).
  static Future<void> _scheduleOne({
    required int id,
    required String title,
    required String body,
    required DateTime fireAt,
  }) async {
    final tzDate = tz.TZDateTime.from(fireAt, tz.local);
    try {
      await _localNotifs.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: tzDate,
        notificationDetails: _kNotifDetails,
        androidScheduleMode: AndroidScheduleMode.alarmClock,
      );
      debugPrint('Notification $id scheduled (alarmClock) for $fireAt');
    } catch (e) {
      debugPrint('alarmClock mode failed for $id ($e); retrying with exactAllowWhileIdle');
      try {
        await _localNotifs.zonedSchedule(
          id: id,
          title: title,
          body: body,
          scheduledDate: tzDate,
          notificationDetails: _kNotifDetails,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        );
        debugPrint('Notification $id scheduled (exactAllowWhileIdle) for $fireAt');
      } catch (e2) {
        debugPrint('Both schedule modes failed for notification $id: $e2');
      }
    }
  }

  static Future<void> cancelMedication(String medId) async {
    if (kIsWeb) return;
    final base = medId.hashCode.abs() % 100000;
    for (int i = 0; i < 75; i++) {
      await _localNotifs.cancel(id: base + i);
    }
  }
}

/// Checks whether any dose reminder is due within the last 16 minutes and
/// fires it directly via show() — bypassing the Samsung-broken BroadcastReceiver.
/// Called from the WorkManager isolate every 15 minutes.
Future<void> checkAndShowDueNotifications() async {
  if (kIsWeb) return;

  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  final db = FirebaseFirestore.instance;
  final now = DateTime.now();
  // Look 14 minutes ahead so WorkManager fires notifications slightly early
  // rather than late — better for medication adherence than a late reminder.
  final windowStart = now.subtract(const Duration(minutes: 2));
  final windowEnd = now.add(const Duration(minutes: 14));

  final medsSnap = await db
      .collection('users')
      .doc(user.uid)
      .collection('medications')
      .get();

  for (final med in medsSnap.docs) {
    final data = med.data();
    if (data['archived'] == true) continue;

    final startTs = (data['startDate'] as Timestamp?)?.toDate();
    final endTs = (data['endDate'] as Timestamp?)?.toDate();
    if (startTs == null || endTs == null) continue;

    final startDay = DateTime(startTs.year, startTs.month, startTs.day);
    final endDay = DateTime(endTs.year, endTs.month, endTs.day);
    final today = DateTime(now.year, now.month, now.day);
    if (today.isBefore(startDay) || today.isAfter(endDay)) continue;

    final medName = (data['name'] as String?) ?? '';
    final times = List<String>.from(data['intakeTimes'] ?? []);
    final idBase = med.id.hashCode.abs() % 100000;
    int slotIndex = 0;

    for (final t in times) {
      final parts = t.split(':');
      if (parts.length != 2) continue;
      final h = int.tryParse(parts[0]) ?? 0;
      final m = int.tryParse(parts[1]) ?? 0;
      final doseTime = DateTime(now.year, now.month, now.day, h, m);

      for (int ri = 0; ri < _kReminderOffsets.length; ri++) {
        final offsetMins = _kReminderOffsets[ri];
        final fireAt = doseTime.add(Duration(minutes: offsetMins));

        if (!fireAt.isBefore(windowStart) && !fireAt.isAfter(windowEnd)) {
          final String title;
          final String body;
          if (offsetMins == 0) {
            title = 'Time for $medName!';
            body = 'Take your dose now.';
          } else if (offsetMins == -60) {
            title = '1 hour until your $medName dose';
            body = 'Tap to prepare for your upcoming dose.';
          } else {
            title = '${-offsetMins} minutes until your $medName dose';
            body = 'Tap to prepare for your upcoming dose.';
          }

          await _localNotifs.show(
            id: idBase + slotIndex * 5 + ri,
            title: title,
            body: body,
            notificationDetails:
                offsetMins == 0 ? _kAlarmNotifDetails : _kNotifDetails,
          );
          debugPrint('checkAndShow: fired "$title" (id ${idBase + slotIndex * 5 + ri})');
        }
      }
      slotIndex++;
    }
  }
}

/// Fetches all active medications for the current user and re-schedules
/// cascading reminders for each. Called by the workmanager sweep so
/// notifications never go stale. Must be top-level for workmanager isolate access.
Future<void> rescheduleAll() async {
  if (kIsWeb) return;

  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  final db = FirebaseFirestore.instance;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  final medsSnap = await db
      .collection('users')
      .doc(user.uid)
      .collection('medications')
      .get();

  for (final med in medsSnap.docs) {
    final data = med.data();
    if (data['archived'] == true) continue;

    final startTs = (data['startDate'] as Timestamp?)?.toDate();
    final endTs = (data['endDate'] as Timestamp?)?.toDate();
    if (startTs == null || endTs == null) continue;

    final startDay = DateTime(startTs.year, startTs.month, startTs.day);
    final endDay = DateTime(endTs.year, endTs.month, endTs.day);
    if (today.isBefore(startDay) || today.isAfter(endDay)) continue;

    await NotificationService.scheduleMedication(
      medId: med.id,
      medName: (data['name'] as String?) ?? '',
      intakeTimes: List<String>.from(data['intakeTimes'] ?? []),
      startDate: startDay,
      endDate: endDay,
    );
  }
}

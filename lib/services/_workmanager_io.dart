// Mobile-only: workmanager + background missed-dose sweep.
// Conditionally imported by notification_service.dart on non-web platforms.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:workmanager/workmanager.dart';
import '../firebase_options.dart';
import 'notification_service.dart';

const kMissedSweepTask = 'missedDoseSweep';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, _) async {
    if (taskName == kMissedSweepTask) {
      await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform);
      await NotificationService.initForIsolate();
      await checkAndShowDueNotifications();
      await runMissedDoseSweep();
      await rescheduleAll();
    }
    return true;
  });
}

Future<void> initWorkmanager() async {
  await Workmanager().initialize(callbackDispatcher);
  await Workmanager().registerPeriodicTask(
    kMissedSweepTask,
    kMissedSweepTask,
    frequency: const Duration(minutes: 15),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    constraints: Constraints(networkType: NetworkType.connected),
  );
}

Future<void> runMissedDoseSweep() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  final db = FirebaseFirestore.instance;
  final now = DateTime.now();
  const graceMins = 60;

  final medsSnap = await db
      .collection('users')
      .doc(user.uid)
      .collection('medications')
      .get();

  for (final med in medsSnap.docs) {
    final medData = med.data();
    final medId = med.id;
    final times = List<String>.from(medData['intakeTimes'] ?? []);
    final startTs = (medData['startDate'] as Timestamp?)?.toDate();
    final endTs = (medData['endDate'] as Timestamp?)?.toDate();
    if (startTs == null || endTs == null) continue;

    for (int dayOffset = 0; dayOffset <= 1; dayOffset++) {
      final day = now.subtract(Duration(days: dayOffset));
      final dayStart = DateTime(day.year, day.month, day.day);
      if (dayStart.isBefore(startTs) || dayStart.isAfter(endTs)) continue;

      final dateStr =
          '${day.year}${day.month.toString().padLeft(2, '0')}${day.day.toString().padLeft(2, '0')}';

      for (final t in times) {
        final parts = t.split(':');
        if (parts.length != 2) continue;
        final h = int.tryParse(parts[0]) ?? 0;
        final m = int.tryParse(parts[1]) ?? 0;
        final scheduledAt =
            DateTime(day.year, day.month, day.day, h, m);

        if (now.isBefore(
            scheduledAt.add(const Duration(minutes: graceMins)))) {
          continue;
        }

        final hhmm =
            '${h.toString().padLeft(2, '0')}${m.toString().padLeft(2, '0')}';
        final logId = '${medId}_${dateStr}_$hhmm';

        final logRef = db
            .collection('users')
            .doc(user.uid)
            .collection('doseLogs')
            .doc(logId);

        final existing = await logRef.get();
        if (!existing.exists) {
          await logRef.set({
            'medId': medId,
            'scheduledAt': Timestamp.fromDate(scheduledAt),
            'status': 'missed',
          });
        }
      }
    }
  }
}

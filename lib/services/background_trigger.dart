// background_trigger.dart
// Runs the trigger check every ~15 minutes even when Hug is closed, and shows
// a notification. When the student taps it, Hug opens the chat with Pat.
//
// Put this file in lib/services/ (same folder as trigger_runner.dart).
//
// Privacy: the notification text never shows health data. The facts for Pat
// are saved on the phone and only used when the student taps the notification.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:health/health.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workmanager/workmanager.dart';

import '../screens/chatbot_screen.dart';
import 'trigger_runner.dart';
import 'trigger_service.dart';

// ---------------------------------------------------
// TEST SWITCHES (set both to false before the real pilot)
// ---------------------------------------------------
// true = the trigger does NOT start the 6-hour cooldown, so you can test again.\
const bool kTriggerTestMode = false;

// true = very easy trigger (almost any heart rate, no cooldown, no quiet hours).
const bool kEasyTriggerForTesting = false;

// The trigger settings used everywhere (app open AND background).
const TriggerConfig kActiveTriggerConfig = kEasyTriggerForTesting
    ? TriggerConfig(
        hrAboveBaselineBpm: 0,
        fallbackHighHeartRate: 50,
        cooldown: Duration.zero,
        quietHourStart: 24,
        quietHourEnd: 0,
      )
    : TriggerConfig();

// Where the facts for Pat are saved until the student taps the notification.
const String kPendingContextKey = 'hug_pending_trigger_context';

// Notification history and last-check time (shown in the Notifications screen)
const String _kLogKey = 'hug_notification_log';
const String _kLastCheckKey = 'hug_last_trigger_check';

const String _kTaskName = 'hug_trigger_check';
const String _kTaskUnique = 'hug_trigger_check_periodic';
const String _kPayload = 'pat_checkin';

// One Pat check-in (a notification or an in-app trigger)
class PatCheckIn {
  final DateTime time;
  final String type; // TriggerType name, e.g. stressAnxiety
  final String source; // 'notification' or 'app'

  const PatCheckIn({
    required this.time,
    required this.type,
    required this.source,
  });

  Map<String, dynamic> toJson() => {
    'time': time.toIso8601String(),
    'type': type,
    'source': source,
  };

  static PatCheckIn? fromJson(Map<String, dynamic> json) {
    final time = DateTime.tryParse('${json['time']}');
    if (time == null) return null;
    return PatCheckIn(
      time: time,
      type: '${json['type']}',
      source: '${json['source']}',
    );
  }
}

// Saves the check-in history on the phone (no health numbers are stored here)
class NotificationLog {
  NotificationLog._();

  static Future<void> add(TriggerType type, {required String source}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final list = prefs.getStringList(_kLogKey) ?? <String>[];
    final entry = PatCheckIn(
      time: DateTime.now(),
      type: type.name,
      source: source,
    );
    list.insert(0, jsonEncode(entry.toJson()));
    await prefs.setStringList(_kLogKey, list.take(50).toList());
  }

  // Newest first
  static Future<List<PatCheckIn>> load() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final list = prefs.getStringList(_kLogKey) ?? <String>[];
    final result = <PatCheckIn>[];
    for (final text in list) {
      try {
        final item = PatCheckIn.fromJson(
          jsonDecode(text) as Map<String, dynamic>,
        );
        if (item != null) result.add(item);
      } catch (_) {}
    }
    return result;
  }

  // The last time Hug ran the trigger check (background or app open)
  static Future<void> markCheck() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLastCheckKey, DateTime.now().toIso8601String());
  }

  static Future<DateTime?> lastCheck() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final text = prefs.getString(_kLastCheckKey);
    return text == null ? null : DateTime.tryParse(text);
  }
}

// This runs in the BACKGROUND (separate from the app screens).
@pragma('vm:entry-point')
void hugCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      await HugBackground.runBackgroundCheck();
    } catch (e) {
      debugPrint('[HUG BACKGROUND] failed: $e');
    }
    return true; // always true so the next check still runs
  });
}

class HugBackground {
  HugBackground._();

  // The app uses this key to open Pat from anywhere.
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  // ---------------------------------------------------------------
  // Setup (call once in main())
  // ---------------------------------------------------------------
  static Future<void> init() async {
    await Workmanager().initialize(hugCallbackDispatcher);
    await _initNotifications(withTapHandler: true);
  }

  static Future<void> _initNotifications({bool withTapHandler = false}) async {
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _notifications.initialize(
      settings,
      onDidReceiveNotificationResponse: withTapHandler
          ? (NotificationResponse response) {
              if (response.payload == _kPayload) _openPat();
            }
          : null,
    );
  }

  // ---------------------------------------------------------------
  // Start / stop (call when the student connects / disconnects the watch)
  // ---------------------------------------------------------------
  static Future<void> startChecking() async {
    try {
      // Permission to show notifications (Android 13+)
      final android = _notifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await android?.requestNotificationsPermission();

      // Permission to read Health Connect while the app is closed
      final health = Health();
      await health.configure();
      if (await health.isHealthDataInBackgroundAvailable()) {
        final allowed = await health.isHealthDataInBackgroundAuthorized();
        if (!allowed) {
          await health.requestHealthDataInBackgroundAuthorization();
        }
      }
    } catch (e) {
      debugPrint('[HUG BACKGROUND] permission step failed: $e');
    }

    try {
      await Workmanager().registerPeriodicTask(
        _kTaskUnique,
        _kTaskName,
        frequency: const Duration(minutes: 15), // Android minimum
      );
    } catch (e) {
      debugPrint('[HUG BACKGROUND] could not start: $e');
    }
  }

  static Future<void> stopChecking() async {
    try {
      await Workmanager().cancelByUniqueName(_kTaskUnique);
    } catch (e) {
      debugPrint('[HUG BACKGROUND] could not stop: $e');
    }
  }

  // ---------------------------------------------------------------
  // The background check itself (runs about every 15 minutes)
  // ---------------------------------------------------------------
  static Future<void> runBackgroundCheck() async {
    final runner = TriggerRunner(config: kActiveTriggerConfig);

    // Saves the cooldown time when it triggers (unless test mode is on)
    final run = await runner.run(saveIfTriggered: !kTriggerTestMode);
    await NotificationLog.markCheck();
    if (run == null || !run.result.shouldTrigger) return;

    // Keep the facts for Pat until the student taps the notification
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kPendingContextKey, buildChatbotContext(run.result));

    await _initNotifications();
    await _notifications.show(
      1001,
      'Pat wants to check in',
      'Tap to chat for a minute.',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'hug_pat_checkin',
          'Pat check-ins',
          channelDescription: 'Gentle check-ins from Pat',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      payload: _kPayload,
    );
    await NotificationLog.add(run.result.type, source: 'notification');
  }

  // ---------------------------------------------------------------
  // Tap on the notification -> open Pat
  // ---------------------------------------------------------------

  // App was closed and the notification opened it (call after runApp)
  static Future<void> handleLaunchFromNotification() async {
    final details = await _notifications.getNotificationAppLaunchDetails();
    final opened = details?.didNotificationLaunchApp ?? false;
    if (opened && details?.notificationResponse?.payload == _kPayload) {
      // Small wait so the first screen is ready
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      await _openPat();
    }
  }

  static Future<void> _openPat() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload(); // the background check saved it from another process
    final ctx = prefs.getString(kPendingContextKey);
    if (ctx == null || ctx.trim().isEmpty) return;

    // Only open Pat for a signed-in student
    if (Supabase.instance.client.auth.currentSession == null) return;

    final nav = navigatorKey.currentState;
    if (nav == null) return;

    await prefs.remove(kPendingContextKey);
    nav.push(
      MaterialPageRoute(builder: (_) => ChatbotScreen(triggerContext: ctx)),
    );
  }
}

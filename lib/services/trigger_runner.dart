// trigger_runner.dart
// Glue code: reads the watch data, runs evaluateTrigger(), saves
// lastTriggerTime, and builds the text that is passed to the Gemini chatbot.
// It does NOT write any chatbot question or message.
//
// Put this file in the SAME folder as trigger_service.dart and health_reader.dart.

import 'health_reader.dart';
import 'health_service.dart';
import 'trigger_service.dart';

class TriggerRunResult {
  final HealthSnapshot snapshot; // what was read from the watch
  final TriggerResult result; // what the trigger decided

  const TriggerRunResult(this.snapshot, this.result);
}

class TriggerRunner {
  TriggerRunner({
    HealthReader? reader,
    this.config = const TriggerConfig(),
  }) : reader = reader ?? HealthReader(triggerConfig: config);

  final HealthReader reader;
  final TriggerConfig config;

  // Reads Health Connect, runs the trigger, and (if it triggered and
  // saveIfTriggered is true) saves the time so the 6-hour cooldown starts.
  // Returns null when the student has not connected a watch in Hug
  // (HealthService.isConnected() is false), so there is nothing to check.
  Future<TriggerRunResult?> run({bool saveIfTriggered = true}) async {
    if (!await HealthService.instance.isConnected()) return null;

    final snapshot = await reader.readSnapshot();
    final result = evaluateTrigger(snapshot.input, config: config);

    if (saveIfTriggered && result.shouldTrigger) {
      await reader.saveLastTriggerTime(snapshot.input.now);
    }

    // Print the result in the VS Code Debug Console (for testing).
    final i = snapshot.input;
    final b = i.baseline;
    // ignore: avoid_print
    print('[HUG TRIGGER] type=${result.type.name} '
        'shouldTrigger=${result.shouldTrigger}\n'
        '  recentHR=${i.recentHeartRate?.toStringAsFixed(1)} '
        '(samples=${snapshot.recentHrSamples}) '
        'recentSteps=${i.recentSteps}\n'
        '  sleepLastNight=${i.sleepHoursLastNight?.toStringAsFixed(1)} '
        'avgSteps3d=${i.averageDailyStepsRecent?.toStringAsFixed(0)}\n'
        '  baseline: restingHR=${b.restingHeartRate?.toStringAsFixed(1)} '
        'sleep=${b.sleepHours?.toStringAsFixed(1)} '
        'steps=${b.dailySteps?.toStringAsFixed(0)}\n'
        '  lastTrigger=${i.lastTriggerTime}\n'
        '  reasons=${result.reasons}');

    return TriggerRunResult(snapshot, result);
  }
}

// Text for Gemini. Pass it as hidden context (see the example at the bottom).
// It only states the facts and that the data is delayed. No questions.
String buildChatbotContext(TriggerResult result) {
  final signal = switch (result.type) {
    TriggerType.stressAnxiety => 'elevated heart rate pattern',
    TriggerType.earlyDepression => 'sleep and activity pattern',
    TriggerType.both => 'elevated heart rate and sleep/activity pattern',
    TriggerType.none => 'none',
  };
  return 'Wearable screening signal: $signal.\n'
      'Facts (watch data arrives 5-15 minutes late, so these describe '
      'earlier moments, not right now):\n'
      '${result.contextForChatbot}\n'
      'This is a screening aid only, not a diagnosis.';
}

// ---------------------------------------------------------------
// Example: how to connect it to the dashboard and the chatbot
//
// In your dashboard State class (needs: with WidgetsBindingObserver):
//
//   final _runner = TriggerRunner();
//   Timer? _timer;
//   bool _checking = false;
//
//   @override
//   void initState() {
//     super.initState();
//     WidgetsBinding.instance.addObserver(this);
//     _checkTrigger(); // when the dashboard opens
//     // Also check every 15 minutes while the app is open.
//     _timer = Timer.periodic(const Duration(minutes: 15), (_) => _checkTrigger());
//   }
//
//   @override
//   void didChangeAppLifecycleState(AppLifecycleState state) {
//     if (state == AppLifecycleState.resumed) _checkTrigger();
//   }
//
//   @override
//   void dispose() {
//     _timer?.cancel();
//     WidgetsBinding.instance.removeObserver(this);
//     super.dispose();
//   }
//
//   Future<void> _checkTrigger() async {
//     if (_checking) return;
//     _checking = true;
//     try {
//       final run = await _runner.run(); // saves lastTriggerTime if triggered
//       if (run != null && run.result.shouldTrigger && mounted) {
//         Navigator.push(
//           context,
//           MaterialPageRoute(
//             builder: (_) => ChatbotScreen( // <-- your own chatbot screen
//               triggerContext: buildChatbotContext(run.result),
//             ),
//           ),
//         );
//       }
//     } catch (e) {
//       debugPrint('Trigger check failed: $e');
//     } finally {
//       _checking = false;
//     }
//   }
//
// In your chatbot screen: add an optional `String? triggerContext` field.
// - Manual mood check-in: open the chatbot WITHOUT triggerContext (null).
// - Trigger: pass triggerContext, and give it to Gemini as hidden context
//   (system instruction, or the first message that the student does not see).
// ---------------------------------------------------------------

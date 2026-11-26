// trigger_service.dart
// Trigger logic only: decides WHEN the HUG chatbot (Gemini) should start a
// contextual validation chat. It does not write any question or message.
// Plain Dart only (no packages), so it is easy to test.
//
// "Referenced" values come from published sources (cite them in the paper).
// "Design parameter" values are NOT validated cutoffs. Review them with the
// OCPS and tune them during pilot testing.
// The result is only a screening aid, not a diagnosis.
//
// Note: watch data arrives with a delay of about 5-15 minutes, so the chatbot
// should talk about "earlier" and not "right now".

// What kind of trigger was detected.
enum TriggerType { none, stressAnxiety, earlyDepression, both }

// All thresholds in one place so they are easy to change later.
class TriggerConfig {
  // --- Stress / anxiety rule ---
  final double hrAboveBaselineBpm;
  final double fallbackHighHeartRate;
  final double exerciseStepsPerMinute;
  final bool skipWhenExercising;
  // Quiet hours are turned OFF by default (start 24 and end 0 means no hour
  // is ever "quiet"). Kept as settings so background_trigger.dart still works.
  final int quietHourStart;
  final int quietHourEnd;

  // --- Early depression rule ---
  final double minSleepHours;
  final double maxSleepHours;
  final double sleepChangeHours;
  final double lowDailySteps;

  // --- General ---
  final Duration cooldown;

  const TriggerConfig({
    this.hrAboveBaselineBpm = 9,
    this.fallbackHighHeartRate = 100,
    this.exerciseStepsPerMinute = 100,
    this.skipWhenExercising = false,
    this.quietHourStart = 24,
    this.quietHourEnd = 0,
    this.minSleepHours = 6,
    this.maxSleepHours = 11,
    this.sleepChangeHours = 2.5,
    this.lowDailySteps = 5000,
    this.cooldown = const Duration(hours: 6),
  });
}

// The student's own "normal", built from their past days.
class PersonalBaseline {
  final double? restingHeartRate;
  final double? sleepHours;
  final double? dailySteps;

  const PersonalBaseline({
    this.restingHeartRate,
    this.sleepHours,
    this.dailySteps,
  });

  factory PersonalBaseline.fromDailyValues({
    List<double> dailyRestingHr = const [],
    List<double> dailySleepHours = const [],
    List<int> dailySteps = const [],
    int minDays = 3,
  }) {
    double? average(List<num> values) {
      if (values.length < minDays) return null;
      return values.reduce((a, b) => a + b) / values.length;
    }

    return PersonalBaseline(
      restingHeartRate: average(dailyRestingHr),
      sleepHours: average(dailySleepHours),
      dailySteps: average(dailySteps),
    );
  }
}

// Everything the trigger needs. A null field means that check is skipped.
class TriggerInput {
  final DateTime now;
  final double? recentHeartRate;
  final int? recentSteps;
  final int recentWindowMinutes;
  final double? sleepHoursLastNight;
  final double? averageDailyStepsRecent;
  final PersonalBaseline baseline;
  final DateTime? lastTriggerTime;

  const TriggerInput({
    required this.now,
    this.recentHeartRate,
    this.recentSteps,
    this.recentWindowMinutes = 30,
    this.sleepHoursLastNight,
    this.averageDailyStepsRecent,
    this.baseline = const PersonalBaseline(),
    this.lastTriggerTime,
  });
}

// The result of the check.
class TriggerResult {
  final TriggerType type;
  final List<String> reasons;

  const TriggerResult({required this.type, required this.reasons});

  bool get shouldTrigger => type != TriggerType.none;

  String get contextForChatbot => reasons.join('\n');
}

const TriggerResult _noTrigger = TriggerResult(
  type: TriggerType.none,
  reasons: [],
);

// Main function: call this with the latest data.
TriggerResult evaluateTrigger(
  TriggerInput input, {
  TriggerConfig config = const TriggerConfig(),
}) {
  // Cooldown: do not trigger again too soon.
  final last = input.lastTriggerTime;
  if (last != null && input.now.difference(last) < config.cooldown) {
    return _noTrigger;
  }

  final reasons = <String>[];
  bool stressAnxiety = false;
  bool earlyDepression = false;

  // ---- Rule 1: elevated heart rate (stress / anxiety) ----
  // Runs at any hour (no quiet hours).
  if (input.recentHeartRate != null) {
    final baselineHr = input.baseline.restingHeartRate;
    final limit = baselineHr != null
        ? baselineHr + config.hrAboveBaselineBpm
        : config.fallbackHighHeartRate;

    final heartRateHigh = input.recentHeartRate! >= limit;

    double? stepsPerMinute;
    if (input.recentSteps != null && input.recentWindowMinutes > 0) {
      stepsPerMinute = input.recentSteps! / input.recentWindowMinutes;
    }
    final clearlyExercising =
        stepsPerMinute != null &&
        stepsPerMinute >= config.exerciseStepsPerMinute;

    if (heartRateHigh && !(config.skipWhenExercising && clearlyExercising)) {
      stressAnxiety = true;
      final stepsText = stepsPerMinute == null
          ? 'no steps data'
          : '${stepsPerMinute.toStringAsFixed(1)} steps per minute';
      reasons.add(
        'Earlier, the average heart rate was '
        '${input.recentHeartRate!.toStringAsFixed(0)} bpm '
        '(the usual limit for this student is ${limit.toStringAsFixed(0)} bpm), '
        'with $stepsText.',
      );
    }
  }

  // ---- Rule 2: sleep disruption + persistently low steps (early depression) ----
  bool sleepDisrupted = false;
  final sleep = input.sleepHoursLastNight;
  if (sleep != null) {
    final baselineSleep = input.baseline.sleepHours;
    final tooLittle = sleep < config.minSleepHours;
    final tooMuch = sleep > config.maxSleepHours;
    final changed =
        baselineSleep != null &&
        (sleep - baselineSleep).abs() >= config.sleepChangeHours;
    sleepDisrupted = tooLittle || tooMuch || changed;
  }

  bool stepsLow = false;
  final avgSteps = input.averageDailyStepsRecent;
  if (avgSteps != null) {
    final belowThreshold = avgSteps < config.lowDailySteps;
    final baselineSteps = input.baseline.dailySteps;
    final belowOwnUsual = baselineSteps == null || avgSteps < baselineSteps;
    stepsLow = belowThreshold && belowOwnUsual;
  }

  if (sleepDisrupted && stepsLow) {
    earlyDepression = true;
    reasons.add(
      'Last night the student slept ${sleep!.toStringAsFixed(1)} hours, and '
      'the average daily steps over the last days were '
      '${avgSteps!.toStringAsFixed(0)} '
      '(below ${config.lowDailySteps.toStringAsFixed(0)}).',
    );
  }

  // ---- Combine the results ----
  TriggerType type;
  if (stressAnxiety && earlyDepression) {
    type = TriggerType.both;
  } else if (stressAnxiety) {
    type = TriggerType.stressAnxiety;
  } else if (earlyDepression) {
    type = TriggerType.earlyDepression;
  } else {
    return _noTrigger;
  }

  return TriggerResult(type: type, reasons: reasons);
}

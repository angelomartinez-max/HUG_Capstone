// health_reader.dart
// Reads Health Connect (through the `health` package, v13) and builds the
// TriggerInput and PersonalBaseline that trigger_service.dart needs.
// It only READS data and saves lastTriggerTime. It does not decide anything:
// evaluateTrigger() in trigger_service.dart decides.
//
// Values marked "Design parameter" are NOT validated cutoffs. Review them
// with the OCPS and tune them during pilot testing.

import 'package:health/health.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'trigger_service.dart';

class HealthReaderConfig {
  // How far back we look for recent heart rate and steps (minutes).
  final int recentWindowMinutes;

  // The heart rate used by the trigger is the HIGHEST average over any block
  // of this many minutes inside the recent window (catches short spikes).
  final int peakWindowMinutes;

  // A peak block needs at least this many samples.
  final int minSamplesInPeakWindow;

  final int baselineDays;
  final int recentStepsDays;
  final int minHrSamplesPerValidDay;
  final int minValidDaysForRecentSteps;
  final double lowActivityStepsPerMinute;
  final int minRestingSamplesPerDay;

  // Awake hours used ONLY for the resting heart rate baseline.
  final int awakeStartHour; // 6 = 6 AM
  final int awakeEndHour; // 22 = 10 PM

  final int nightStartHour; // 18 = 6 PM of the previous day
  final int nightEndHour; // 14 = 2 PM of the morning day

  const HealthReaderConfig({
    this.recentWindowMinutes = 60,
    this.peakWindowMinutes = 5,
    this.minSamplesInPeakWindow = 1,
    this.baselineDays = 7,
    this.recentStepsDays = 3,
    this.minHrSamplesPerValidDay = 20,
    this.minValidDaysForRecentSteps = 2,
    this.lowActivityStepsPerMinute = 10,
    this.minRestingSamplesPerDay = 5,
    this.awakeStartHour = 6,
    this.awakeEndHour = 22,
    this.nightStartHour = 18,
    this.nightEndHour = 14,
  });
}

class DayDebug {
  final DateTime day;
  final int hrSamples;
  final bool valid;
  final int? steps;
  final double? restingHr;
  final double? sleepHours;

  const DayDebug({
    required this.day,
    required this.hrSamples,
    required this.valid,
    this.steps,
    this.restingHr,
    this.sleepHours,
  });
}

class HealthSnapshot {
  final TriggerInput input;
  final int recentHrSamples;
  final DateTime? latestHrTime;
  final Set<String> hrSources;
  final List<DayDebug> days;

  const HealthSnapshot({
    required this.input,
    required this.recentHrSamples,
    required this.latestHrTime,
    required this.hrSources,
    required this.days,
  });
}

class _Sample {
  final DateTime time;
  final double bpm;
  const _Sample(this.time, this.bpm);
}

class _Span {
  final DateTime start;
  final DateTime end;
  const _Span(this.start, this.end);
}

class HealthReader {
  HealthReader({
    Health? health,
    this.triggerConfig = const TriggerConfig(),
    this.config = const HealthReaderConfig(),
  }) : _health = health ?? Health();

  final Health _health;
  final TriggerConfig triggerConfig; // kept so other files still compile
  final HealthReaderConfig config;
  bool _configured = false;

  static const List<HealthDataType> _sleepTypes = [
    HealthDataType.SLEEP_SESSION,
    HealthDataType.SLEEP_ASLEEP,
    HealthDataType.SLEEP_LIGHT,
    HealthDataType.SLEEP_DEEP,
    HealthDataType.SLEEP_REM,
  ];

  static const Set<HealthDataType> _sleepStageTypes = {
    HealthDataType.SLEEP_ASLEEP,
    HealthDataType.SLEEP_LIGHT,
    HealthDataType.SLEEP_DEEP,
    HealthDataType.SLEEP_REM,
  };

  static const String _lastTriggerKey = 'hug_last_trigger_time';

  Future<void> _ensureConfigured() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  // ---- lastTriggerTime (saved on the phone) ----

  Future<DateTime?> loadLastTriggerTime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final text = prefs.getString(_lastTriggerKey);
    return text == null ? null : DateTime.tryParse(text);
  }

  Future<void> saveLastTriggerTime(DateTime time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastTriggerKey, time.toIso8601String());
  }

  Future<void> clearLastTriggerTime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lastTriggerKey);
  }

  // ---- Main function: read everything and build the trigger input ----

  Future<HealthSnapshot> readSnapshot() async {
    await _ensureConfigured();
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final weekStart = todayStart.subtract(Duration(days: config.baselineDays));

    final hrPoints = await _fetch([HealthDataType.HEART_RATE], weekStart, now);
    final stepPoints = await _fetch([HealthDataType.STEPS], weekStart, now);
    final sleepPoints = await _fetch(
      _sleepTypes,
      todayStart.subtract(Duration(days: config.baselineDays + 1)),
      now,
    );

    // ---- Heart rate samples ----
    final hr = <_Sample>[];
    final sources = <String>{};
    DateTime? latestHr;
    for (final p in hrPoints) {
      final bpm = _number(p);
      if (bpm <= 0) continue;
      hr.add(_Sample(p.dateFrom, bpm));
      sources.add('${p.sourceName}');
      if (latestHr == null || p.dateFrom.isAfter(latestHr)) {
        latestHr = p.dateFrom;
      }
    }

    // ---- Steps per minute (to find low-activity moments) ----
    final stepsPerMinute = <int, double>{};
    for (final p in stepPoints) {
      final total = _number(p);
      if (total <= 0) continue;
      final startMin = p.dateFrom.millisecondsSinceEpoch ~/ 60000;
      var endMin = p.dateTo.millisecondsSinceEpoch ~/ 60000;
      if (endMin <= startMin) endMin = startMin + 1;
      final length = endMin - startMin;
      if (length > 180) continue;
      final perMin = total / length;
      for (var m = startMin; m < endMin; m++) {
        final old = stepsPerMinute[m];
        if (old == null || perMin > old) stepsPerMinute[m] = perMin;
      }
    }

    // ---- Recent window: heart rate and steps ----
    final recentStart = now.subtract(
      Duration(minutes: config.recentWindowMinutes),
    );
    final recentSamples = hr
        .where((s) => !s.time.isBefore(recentStart) && !s.time.isAfter(now))
        .toList();
    // Highest 5-minute average inside the recent window (catches short spikes).
    final double? recentHeartRate = _peakAverage(recentSamples);
    final int? recentSteps = await _totalSteps(recentStart, now);

    // ---- Past days (newest first) ----
    final days = <DayDebug>[];
    for (var i = 1; i <= config.baselineDays; i++) {
      final dayStart = todayStart.subtract(Duration(days: i));
      final dayEnd = dayStart.add(const Duration(days: 1));
      final daySamples = hr
          .where((s) => !s.time.isBefore(dayStart) && s.time.isBefore(dayEnd))
          .toList();
      final valid = daySamples.length >= config.minHrSamplesPerValidDay;

      int? daySteps;
      double? restingHr;
      if (valid) {
        daySteps = await _totalSteps(dayStart, dayEnd) ?? 0;

        final resting = <double>[];
        for (final s in daySamples) {
          final hour = s.time.hour;
          final awake =
              hour >= config.awakeStartHour && hour < config.awakeEndHour;
          final spm =
              stepsPerMinute[s.time.millisecondsSinceEpoch ~/ 60000] ?? 0;
          if (awake && spm <= config.lowActivityStepsPerMinute) {
            resting.add(s.bpm);
          }
        }
        if (resting.length >= config.minRestingSamplesPerDay) {
          restingHr = _average(resting);
        }
      }

      days.add(
        DayDebug(
          day: dayStart,
          hrSamples: daySamples.length,
          valid: valid,
          steps: daySteps,
          restingHr: restingHr,
          sleepHours: _sleepHoursForNight(sleepPoints, dayStart),
        ),
      );
    }

    // ---- 7-day baseline ----
    final restingList = <double>[];
    final sleepList = <double>[];
    final stepsList = <int>[];
    for (final d in days) {
      final r = d.restingHr;
      final sl = d.sleepHours;
      final st = d.steps;
      if (r != null) restingList.add(r);
      if (sl != null) sleepList.add(sl);
      if (d.valid && st != null) stepsList.add(st);
    }
    final baseline = PersonalBaseline.fromDailyValues(
      dailyRestingHr: restingList,
      dailySleepHours: sleepList,
      dailySteps: stepsList,
    );

    // ---- Average steps over the last 3 full days (valid days only) ----
    final recentDays = days
        .take(config.recentStepsDays)
        .where((d) => d.valid)
        .toList();
    double? averageDailyStepsRecent;
    if (recentDays.length >= config.minValidDaysForRecentSteps) {
      var sum = 0;
      for (final d in recentDays) {
        sum += d.steps ?? 0;
      }
      averageDailyStepsRecent = sum / recentDays.length;
    }

    final sleepHoursLastNight = _sleepHoursForNight(sleepPoints, todayStart);

    final input = TriggerInput(
      now: now,
      recentHeartRate: recentHeartRate,
      recentSteps: recentSteps,
      recentWindowMinutes: config.recentWindowMinutes,
      sleepHoursLastNight: sleepHoursLastNight,
      averageDailyStepsRecent: averageDailyStepsRecent,
      baseline: baseline,
      lastTriggerTime: await loadLastTriggerTime(),
    );

    return HealthSnapshot(
      input: input,
      recentHrSamples: recentSamples.length,
      latestHrTime: latestHr,
      hrSources: sources,
      days: days,
    );
  }

  // ---- Sleep ----

  double? _sleepHoursForNight(
    List<HealthDataPoint> points,
    DateTime morningDay,
  ) {
    final windowStart = DateTime(
      morningDay.year,
      morningDay.month,
      morningDay.day - 1,
      config.nightStartHour,
    );
    final windowEnd = DateTime(
      morningDay.year,
      morningDay.month,
      morningDay.day,
      config.nightEndHour,
    );

    final stageSpans = <_Span>[];
    final sessionSpans = <_Span>[];
    for (final p in points) {
      if (!p.dateTo.isAfter(windowStart) || p.dateTo.isAfter(windowEnd)) {
        continue;
      }
      final span = _Span(p.dateFrom, p.dateTo);
      if (p.type == HealthDataType.SLEEP_SESSION) {
        sessionSpans.add(span);
      } else if (_sleepStageTypes.contains(p.type)) {
        stageSpans.add(span);
      }
    }

    final spans = stageSpans.isNotEmpty ? stageSpans : sessionSpans;
    if (spans.isEmpty) return null;
    final hours = _mergedHours(spans);
    return hours > 0 ? hours : null;
  }

  double _mergedHours(List<_Span> spans) {
    spans.sort((a, b) => a.start.compareTo(b.start));
    var totalSeconds = 0;
    var curStart = spans.first.start;
    var curEnd = spans.first.end;
    for (final s in spans.skip(1)) {
      if (s.start.isAfter(curEnd)) {
        totalSeconds += curEnd.difference(curStart).inSeconds;
        curStart = s.start;
        curEnd = s.end;
      } else if (s.end.isAfter(curEnd)) {
        curEnd = s.end;
      }
    }
    totalSeconds += curEnd.difference(curStart).inSeconds;
    return totalSeconds / 3600.0;
  }

  // ---- Small helpers ----

  Future<List<HealthDataPoint>> _fetch(
    List<HealthDataType> types,
    DateTime start,
    DateTime end,
  ) {
    return _health.getHealthDataFromTypes(
      types: types,
      startTime: start,
      endTime: end,
    );
  }

  Future<int?> _totalSteps(DateTime start, DateTime end) async {
    try {
      return await _health.getTotalStepsInInterval(start, end);
    } catch (_) {
      return null;
    }
  }

  double _number(HealthDataPoint p) {
    final value = p.value;
    if (value is NumericHealthValue) {
      return value.numericValue.toDouble();
    }
    return 0;
  }

  double? _average(List<double> values) {
    if (values.isEmpty) return null;
    var sum = 0.0;
    for (final v in values) {
      sum += v;
    }
    return sum / values.length;
  }

  // Highest average heart rate over any block of peakWindowMinutes.
  double? _peakAverage(List<_Sample> samples) {
    if (samples.isEmpty) return null;
    final sorted = [...samples]..sort((a, b) => a.time.compareTo(b.time));
    final blockLength = Duration(minutes: config.peakWindowMinutes);
    double? best;
    for (final start in sorted) {
      final end = start.time.add(blockLength);
      final block = <double>[];
      for (final s in sorted) {
        if (s.time.isBefore(start.time)) continue;
        if (s.time.isAfter(end)) break;
        block.add(s.bpm);
      }
      if (block.length < config.minSamplesInPeakWindow) continue;
      final avg = _average(block);
      if (avg != null && (best == null || avg > best)) best = avg;
    }
    return best;
  }
}

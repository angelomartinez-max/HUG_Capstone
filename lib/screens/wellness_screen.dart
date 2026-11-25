// Hug - Wellness screen (smartwatch status, vitals and PUP OCPS support)

import 'dart:async';

import 'package:health/health.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../constants/colors.dart';
import '../services/background_trigger.dart';
import '../services/health_service.dart';
import '../services/trigger_runner.dart';
import 'chatbot_screen.dart'; // same folder as this file

class WellnessScreen extends StatefulWidget {
  // Not used anymore (the name now comes from the logged-in user).
  // Kept so other files that pass it do not break.
  final String userName;

  // Called when the user taps "View OCPS contact details"
  // (the parent switches to the Profile tab)
  final VoidCallback? onOpenProfile;

  const WellnessScreen({super.key, this.userName = 'Juan', this.onOpenProfile});

  @override
  State<WellnessScreen> createState() => _WellnessScreenState();
}

class _WellnessScreenState extends State<WellnessScreen>
    with WidgetsBindingObserver {
  // ---------------------------------------------------
  // REAL DATA (from Health Connect through HealthService)
  // ---------------------------------------------------
  Timer? _timer;
  bool _connected = false;
  bool _loading = true;
  bool _refreshing = false; // true while a reload is running
  int? _steps;
  int? _heartRate;
  DateTime? _lastSynced;

  // ---------------------------------------------------
  // TRIGGER (decides when Pat starts a chat)
  // ---------------------------------------------------
  final TriggerRunner _runner = TriggerRunner(config: kActiveTriggerConfig);
  bool _checkingTrigger = false; // a check is running
  bool _chatOpen = false; // the chatbot is already on screen
  bool _backgroundStarted = false; // background check already started
  DateTime _lastCheck = DateTime.fromMillisecondsSinceEpoch(0);

  // How often the trigger is checked (not every 10 seconds)
  static const Duration kTriggerEvery = Duration(minutes: 15);

  // Sleep is not wired yet (waiting for real sleep records)
  static const String sleepStatus = '--';
  static const String sleepValue = '--';

  // How often the screen reloads by itself
  static const Duration kAutoRefresh = Duration(seconds: 10);

  // Data older than this is treated as "no recent data"
  static const Duration kFreshLimit = Duration(minutes: 15);

  // Colors only used in this screen
  static const Color kBackground = Color(0xFFF4F4F4);
  static const Color kChip = Color(0xFFFBEDEE);
  static const Color kHeartIcon = Color(0xFFB5566B);
  static const Color kStepsIcon = Color(0xFF6B5B95);
  static const Color kSleepIcon = Color(0xFFB59B5E);
  static const Color kConnectedDot = Color(0xFF7ED04B);
  static const Color kWatchBody = Color(0xFF2D3748);
  static const Color kWatchStrap = Color(0xFF8E9099);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();

    // Reload automatically while the app is open and connected
    _timer = Timer.periodic(kAutoRefresh, (_) {
      if (_connected) _loadData(silent: true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Reload when the user comes back to the app (e.g. from the watch app)
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_connected) {
        _loadData(silent: true);
      } else {
        _init();
      }
    }
  }

  // Check if the user connected inside Hug, then load the data
  Future<void> _init() async {
    bool connected = false;
    try {
      connected = await HealthService.instance.isConnected();
    } catch (_) {}
    if (!mounted) return;
    setState(() => _connected = connected);

    if (connected) {
      await _loadData();
      _startBackground();
    } else {
      setState(() => _loading = false);
    }
  }

  // silent = true: no "Loading..." text (used by the automatic reloads)
  Future<void> _loadData({bool silent = false}) async {
    if (_refreshing) return;
    _refreshing = true;
    if (!silent && mounted) setState(() => _loading = true);

    try {
      final steps = await HealthService.instance.todaySteps();
      final hr = await HealthService.instance.latestHeartRate();
      // The user may have disconnected while this was loading
      if (!mounted || !_connected) return;
      setState(() {
        _steps = steps;
        _heartRate = hr == null
            ? null
            : (hr.value as NumericHealthValue).numericValue.round();
        _lastSynced = hr?.dateTo;
        _loading = false;
      });
      _checkTrigger(); // runs at most once every 15 minutes
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    } finally {
      _refreshing = false;
    }
  }

  // Starts the 15-minute check that also works when Hug is closed
  Future<void> _startBackground() async {
    if (_backgroundStarted) return;
    _backgroundStarted = true;
    await HugBackground.startChecking();
  }

  // Checks the watch data and opens Pat if the trigger says so.
  // It does nothing if it ran less than 15 minutes ago, or if a check
  // is already running, or if the chatbot is already open.
  Future<void> _checkTrigger() async {
    if (_checkingTrigger || _chatOpen) return;
    if (DateTime.now().difference(_lastCheck) < kTriggerEvery) return;

    _checkingTrigger = true;
    try {
      // The background check saves from another process, so refresh first
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();

      final run = await _runner.run(saveIfTriggered: !kTriggerTestMode);
      _lastCheck = DateTime.now();
      await NotificationLog.markCheck();

      if (run != null && run.result.shouldTrigger && mounted) {
        _chatOpen = true;
        await prefs.remove(kPendingContextKey); // avoid a second chat later
        await NotificationLog.add(run.result.type, source: 'app');
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                ChatbotScreen(triggerContext: buildChatbotContext(run.result)),
          ),
        );
        _chatOpen = false;
      }
    } catch (e) {
      debugPrint('Trigger check failed: $e');
      _chatOpen = false;
    } finally {
      _checkingTrigger = false;
    }
  }

  // "Find your smartwatch" button: show the steps first, then ask permission
  Future<void> _findSmartwatch() async {
    final proceed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Find your smartwatch',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text(
              'Hug reads your data through Health Connect. Before you continue:',
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
            const SizedBox(height: 16),
            _sheetStep(
              '1',
              'Wear your compatible smartwatch and pair it with its app.',
            ),
            _sheetStep('2', 'In that app, turn on sync to Health Connect.'),
            _sheetStep(
              '3',
              'Tap Continue and allow heart rate, steps and sleep.',
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kCoral,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: const StadiumBorder(),
                ),
                child: const Text(
                  'Continue',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (proceed == true) await _connect();
  }

  Widget _sheetStep(String number, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: kChip,
            ),
            child: Text(
              number,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: kCoral,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  // Ask for permission, check for real watch data, then load it
  Future<void> _connect() async {
    final result = await HealthService.instance.connect();
    if (!mounted) return;

    switch (result) {
      case ConnectResult.connected:
        setState(() => _connected = true);
        await _loadData();
        _startBackground();
        break;
      case ConnectResult.notInstalled:
        _showMessage('Install Health Connect, then try again.');
        break;
      case ConnectResult.denied:
        _showMessage('Permission was not granted.');
        break;
      case ConnectResult.noData:
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: Colors.white,
            title: const Text('No smartwatch data found'),
            content: const Text(
              'Hug could not find any data from your smartwatch. '
              'Make sure your smartwatch is worn and paired, and that its app '
              'is syncing to Health Connect. Then try again.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK', style: TextStyle(color: kCoral)),
              ),
            ],
          ),
        );
        break;
    }
  }

  // Tap the "Connected" pill: ask first, then disconnect inside Hug only
  Future<void> _confirmDisconnect() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Disconnect smartwatch?'),
        content: const Text(
          'Hug will stop reading your smartwatch data. '
          'Your smartwatch app and Health Connect are not affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Disconnect', style: TextStyle(color: kCoral)),
          ),
        ],
      ),
    );

    if (yes != true) return;

    await HealthService.instance.disconnect();
    await HugBackground.stopChecking();
    _backgroundStarted = false;
    if (!mounted) return;
    setState(() {
      _connected = false;
      _loading = false;
      _steps = null;
      _heartRate = null;
      _lastSynced = null;
    });
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  // ---------------------------------------------------
  // HELPERS: turn raw numbers into text
  // ---------------------------------------------------

  // True when the newest heart rate record is recent enough
  bool get _hasRecentData {
    final t = _lastSynced;
    if (t == null) return false;
    return DateTime.now().difference(t) <= kFreshLimit;
  }

  String get _heartRateStatus {
    final hr = _heartRate;
    if (hr == null) return '--';
    if (hr < 60) return 'Low';
    if (hr <= 100) return 'Normal';
    return 'Elevated';
  }

  String get _heartRateValue => _heartRate == null ? '--' : '$_heartRate bpm';

  String get _stepsStatus {
    final s = _steps;
    if (s == null) return '--';
    if (s < 3000) return 'Low';
    if (s < 8000) return 'Moderate';
    return 'Active';
  }

  String get _stepsValue =>
      _steps == null ? '--' : '${_formatNumber(_steps!)} steps';

  // 12345 -> 12,345
  String _formatNumber(int n) {
    final s = n.toString();
    final buffer = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buffer.write(',');
      buffer.write(s[i]);
    }
    return buffer.toString();
  }

  // 19:34 -> 7:34 PM
  String get _lastSyncedText {
    final t = _lastSynced;
    if (t == null) return _loading ? 'Loading...' : 'No data yet';
    final hour12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final minute = t.minute.toString().padLeft(2, '0');
    final period = t.hour >= 12 ? 'PM' : 'AM';
    return '$hour12:$minute $period';
  }

  // Name shown on the smartwatch card:
  // "------" when no watch is connected, otherwise the logged-in
  // user's first name (saved in the metadata during sign up).
  String get _watchName {
    if (!_connected) return '------';
    final meta = Supabase.instance.client.auth.currentUser?.userMetadata;
    final first = (meta?['first_name'] as String?)?.trim() ?? '';
    return first.isEmpty ? 'My Smartwatch' : "$first's Smartwatch";
  }

  // Small text under the watch name
  String get _watchCaption {
    if (!_connected) return 'Connect to see your health data';
    if (_hasRecentData) return 'Last synced: $_lastSyncedText';
    if (_lastSynced == null) {
      return _loading
          ? 'Loading...'
          : 'No data yet. Open your smartwatch app to sync.';
    }
    return 'Last synced: $_lastSyncedText\nOpen your smartwatch app to sync.';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: kBackground,
      child: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          // Pull down still works, but it is no longer needed
          onRefresh: () async {
            if (_connected) await _loadData();
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            // Extra space at the bottom so the bottom bar does not cover content
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 130),
            child: Column(
              children: [
                const Text(
                  'Wellness',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 18),
                buildWatchCard(),
                const SizedBox(height: 12),
                buildMetricCard(
                  label: 'Heart Rate',
                  status: _heartRateStatus,
                  value: _heartRateValue,
                  icon: Icons.favorite,
                  iconColor: kHeartIcon,
                  onTap: () {
                    // TODO: open the Heart Rate details screen here
                  },
                ),
                const SizedBox(height: 10),
                buildMetricCard(
                  label: 'Steps Today',
                  status: _stepsStatus,
                  value: _stepsValue,
                  icon: Icons.directions_walk,
                  iconColor: kStepsIcon,
                  onTap: () {
                    // TODO: open the Steps details screen here
                  },
                ),
                const SizedBox(height: 10),
                buildMetricCard(
                  label: 'Sleep Duration',
                  status: sleepStatus,
                  value: sleepValue,
                  icon: Icons.nightlight_round,
                  iconColor: kSleepIcon,
                  onTap: () {
                    // TODO: open the Sleep details screen here
                  },
                ),
                const SizedBox(height: 10),
                buildOcpsCard(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------
  // SMARTWATCH CARD: watch picture, name, sync, status
  // ---------------------------------------------------
  Widget buildWatchCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: kCoral,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          buildWatchPicture(),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Smartwatch name
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    _watchName,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                // Last sync / hint
                Text(
                  _watchCaption,
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 11, color: Colors.white),
                ),
                const SizedBox(height: 12),
                _connected ? buildStatusPill() : buildFindButton(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // White pill: green "Connected" when data is recent, grey otherwise.
  // Tap it to disconnect (inside Hug only).
  Widget buildStatusPill() {
    final bool fresh = _hasRecentData;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: _confirmDisconnect,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: fresh ? kConnectedDot : Colors.grey,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                fresh ? 'Connected' : 'No recent data',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.keyboard_arrow_down,
                size: 16,
                color: Colors.black54,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // White pill button (shown when NOT connected)
  Widget buildFindButton() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: _findSmartwatch,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.watch_outlined, size: 16, color: Colors.black87),
              SizedBox(width: 6),
              Text(
                'Find your smartwatch',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Watch icon inside a white circle
  // TODO: replace the Icon with Image.asset(...) if you have your own image
  Widget buildWatchPicture() {
    return Container(
      width: 84,
      height: 84,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
      ),
      child: const Icon(Icons.watch, size: 46, color: kCoral),
    );
  }

  // ---------------------------------------------------
  // METRIC CARD: icon, label, big status, value chip, caption
  // ---------------------------------------------------
  Widget buildMetricCard({
    required String label,
    required String status,
    required String value,
    required IconData icon,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              // Icon on the left
              SizedBox(
                width: 76,
                child: Center(child: Icon(icon, size: 46, color: iconColor)),
              ),
              const SizedBox(width: 6),

              // Texts on the right
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Label and value chip on the same row
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            label,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.black,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: kChip,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            value,
                            style: const TextStyle(fontSize: 11, color: kCoral),
                          ),
                        ),
                      ],
                    ),
                    // Big status word
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        status,
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w700,
                          color: Colors.black,
                        ),
                      ),
                    ),
                    const Text(
                      'Captured by your smartwatch',
                      style: TextStyle(fontSize: 11, color: Colors.black54),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------
  // PUP OCPS CARD: support message and contact button
  // ---------------------------------------------------
  Widget buildOcpsCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Logo placeholder
              // TODO: replace with Image.asset('assets/images/ocps_logo.png')
              Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  border: Border.all(color: const Color(0xFFE0E0E0)),
                ),
                child: const Icon(
                  Icons.volunteer_activism_outlined,
                  color: kCoral,
                  size: 30,
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Talk to PUP OCPS',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.black,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Your recent patterns suggest extra support could help. '
                      'The Office of Counseling and Psychological Services '
                      'is here to listen.',
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.35,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Contact button: goes to the Profile tab (OCPS contact info is there)
          SizedBox(
            width: double.infinity,
            height: 40,
            child: ElevatedButton(
              onPressed: widget.onOpenProfile,
              style: ElevatedButton.styleFrom(
                backgroundColor: kCoral,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: const StadiumBorder(),
              ),
              child: const Text(
                'View OCPS contact details',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

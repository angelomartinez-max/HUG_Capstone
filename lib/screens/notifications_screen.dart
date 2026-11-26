// Hug - Notifications screen
// Shows (1) when each watch data type was last recorded in Health Connect and
// (2) the list of Pat check-ins (notifications and in-app triggers).
//
// Put this file in lib/screens/ (same folder as wellness_screen.dart).

import 'package:health/health.dart';
import 'package:material_ui/material_ui.dart';

import '../constants/colors.dart';
import '../services/background_trigger.dart';
import '../services/health_service.dart';
import 'chatbot_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  // Colors only used in this screen
  static const Color kBackground = Color(0xFFF4F4F4);
  static const Color kChip = Color(0xFFFBEDEE);
  static const Color kFresh = Color(0xFF7ED04B); // data is recent
  static const Color kLate = Color(0xFFE0A030); // data is a bit old

  static const List<String> _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  bool _loading = true;
  bool _connected = false;
  DateTime? _hrTime; // newest heart rate record
  DateTime? _stepsTime; // newest steps record
  DateTime? _sleepTime; // newest sleep record
  DateTime? _lastCheck; // last time Hug checked the trigger
  List<PatCheckIn> _checkIns = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ---------------------------------------------------
  // LOAD DATA
  // ---------------------------------------------------
  Future<void> _load() async {
    bool connected = false;
    DateTime? hr;
    DateTime? steps;
    DateTime? sleep;

    try {
      connected = await HealthService.instance.isConnected();
    } catch (_) {}

    if (connected) {
      final health = Health();
      try {
        await health.configure();
      } catch (_) {}
      hr = await _newest(
        health,
        [HealthDataType.HEART_RATE],
        const Duration(hours: 24),
      );
      steps = await _newest(
        health,
        [HealthDataType.STEPS],
        const Duration(hours: 24),
      );
      sleep = await _newest(
        health,
        [
          HealthDataType.SLEEP_SESSION,
          HealthDataType.SLEEP_ASLEEP,
          HealthDataType.SLEEP_LIGHT,
          HealthDataType.SLEEP_DEEP,
          HealthDataType.SLEEP_REM,
        ],
        const Duration(days: 3),
      );
    }

    final checkIns = await NotificationLog.load();
    final lastCheck = await NotificationLog.lastCheck();

    if (!mounted) return;
    setState(() {
      _connected = connected;
      _hrTime = hr;
      _stepsTime = steps;
      _sleepTime = sleep;
      _lastCheck = lastCheck;
      _checkIns = checkIns;
      _loading = false;
    });
  }

  // Newest record time for some data types (null if none or if reading fails)
  Future<DateTime?> _newest(
    Health health,
    List<HealthDataType> types,
    Duration back,
  ) async {
    try {
      final now = DateTime.now();
      final points = await health.getHealthDataFromTypes(
        types: types,
        startTime: now.subtract(back),
        endTime: now,
      );
      if (points.isEmpty) return null;
      DateTime newest = points.first.dateTo;
      for (final p in points) {
        if (p.dateTo.isAfter(newest)) newest = p.dateTo;
      }
      return newest;
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------
  // TEXT HELPERS
  // ---------------------------------------------------

  // 19:34 -> 7:34 PM
  String _clock(DateTime t) {
    final hour12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final minute = t.minute.toString().padLeft(2, '0');
    final period = t.hour >= 12 ? 'PM' : 'AM';
    return '$hour12:$minute $period';
  }

  // "7:34 PM", "Yesterday, 7:34 PM" or "Nov 24, 7:34 PM"
  String _when(DateTime t) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(t.year, t.month, t.day);
    final diffDays = today.difference(day).inDays;
    if (diffDays == 0) return _clock(t);
    if (diffDays == 1) return 'Yesterday, ${_clock(t)}';
    return '${_months[t.month - 1]} ${t.day}, ${_clock(t)}';
  }

  // "Just now", "12 min ago", "3 hr ago", "2 days ago"
  String _ago(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hr ago';
    return '${diff.inDays} days ago';
  }

  // Dot color for heart rate and steps (they should update all day)
  Color _dotColor(DateTime? t, {bool isSleep = false}) {
    if (t == null) return Colors.grey;
    if (isSleep) return kFresh; // sleep is saved only once a day
    final minutes = DateTime.now().difference(t).inMinutes;
    if (minutes <= 30) return kFresh;
    if (minutes <= 180) return kLate;
    return Colors.grey;
  }

  String _checkInText(PatCheckIn c) {
    switch (c.type) {
      case 'stressAnxiety':
        return 'Pat noticed your heart rate was higher than usual earlier.';
      case 'earlyDepression':
        return 'Pat noticed a change in your sleep and activity.';
      case 'both':
        return 'Pat noticed changes in your heart rate, sleep and activity.';
      default:
        return 'Pat checked in with you.';
    }
  }

  // ---------------------------------------------------
  // SCREEN
  // ---------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                  children: [
                    _sectionTitle('Watch data'),
                    _buildSyncCard(),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(4, 8, 4, 0),
                      child: Text(
                        'Data from your watch can arrive 5-15 minutes late, so '
                        'these times describe earlier moments. If the times '
                        'look old, open your watch app to sync.',
                        style: TextStyle(fontSize: 11, color: Colors.black54),
                      ),
                    ),
                    const SizedBox(height: 22),
                    _sectionTitle('Pat check-ins'),
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: Text('Loading...')),
                      )
                    else if (_checkIns.isEmpty)
                      _buildEmpty()
                    else
                      for (final c in _checkIns) _buildCheckInTile(c),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: const Icon(Icons.arrow_back, color: Colors.black, size: 26),
          ),
          const Expanded(
            child: Text(
              'Notifications',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Colors.black,
              ),
            ),
          ),
          // Same width as the arrow so the title stays in the middle
          const SizedBox(width: 26),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: Colors.black87,
        ),
      ),
    );
  }

  // ---------------------------------------------------
  // LAST SYNC CARD
  // ---------------------------------------------------
  Widget _buildSyncCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
      ),
      child: !_connected && !_loading
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text(
                'Smartwatch not connected. Connect it in the Wellness tab '
                'to see when your data was last recorded.',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
            )
          : Column(
              children: [
                _syncRow(Icons.favorite, 'Heart rate', _hrTime),
                const Divider(height: 1),
                _syncRow(Icons.directions_walk, 'Steps', _stepsTime),
                const Divider(height: 1),
                _syncRow(
                  Icons.nightlight_round,
                  'Sleep',
                  _sleepTime,
                  isSleep: true,
                ),
                const Divider(height: 1),
                _checkRow(),
              ],
            ),
    );
  }

  Widget _syncRow(
    IconData icon,
    String label,
    DateTime? time, {
    bool isSleep = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 22, color: kCoral),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _dotColor(time, isSleep: isSleep),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            time == null ? 'No data yet' : '${_when(time)}\n${_ago(time)}',
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 11, color: Colors.black54),
          ),
        ],
      ),
    );
  }

  // When Hug itself last checked the trigger
  Widget _checkRow() {
    final t = _lastCheck;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.sync, size: 22, color: kCoral),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Last Hug check',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
          Text(
            t == null ? 'Not yet' : '${_when(t)}\n${_ago(t)}',
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 11, color: Colors.black54),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------
  // PAT CHECK-INS
  // ---------------------------------------------------
  Widget _buildEmpty() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
      ),
      child: const Text(
        'No check-ins yet. When Pat notices a pattern in your watch data, '
        'it will show here.',
        style: TextStyle(fontSize: 12, color: Colors.black54),
      ),
    );
  }

  Widget _buildCheckInTile(PatCheckIn c) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ChatbotScreen()),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: kChip,
                  ),
                  child: const Icon(
                    Icons.notifications_active_outlined,
                    size: 20,
                    color: kCoral,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _checkInText(c),
                        style: const TextStyle(fontSize: 13, height: 1.3),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_when(c.time)} - '
                        '${c.source == 'notification' ? 'Notification' : 'In the app'}'
                        '\nTap to chat with Pat',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

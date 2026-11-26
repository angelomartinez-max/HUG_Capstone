// Hug - Daily Check In pop up
// Opens on top of the dashboard (the dashboard stays visible but blurred).
// Put this file in the same folder as dashboard_screen.dart

import 'dart:ui' show ImageFilter;

import 'package:material_ui/material_ui.dart';

import '../constants/colors.dart';
import 'dashboard_screen.dart' show WellnessRingPainter;

// ---------------------------------------------------
// Call this from the dashboard to show the pop up.
// It returns the chosen emotion ("Calm", "Okay", "Tired", "Stressed")
// or null if the user closed the pop up without saving.
// ---------------------------------------------------
Future<String?> showDailyCheckIn(
  BuildContext context, {
  required int wellnessScore,
}) {
  return showGeneralDialog<String>(
    context: context,
    barrierDismissible: true, // tap outside to close
    barrierLabel: 'Close',
    barrierColor: const Color(0x33000000),
    transitionDuration: const Duration(milliseconds: 250),
    pageBuilder: (context, animation, secondaryAnimation) {
      return DailyCheckInPopup(wellnessScore: wellnessScore);
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final CurvedAnimation curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOut,
      );

      return AnimatedBuilder(
        animation: curved,
        builder: (context, _) {
          // Blur grows while the pop up opens
          return BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: 8 * curved.value,
              sigmaY: 8 * curved.value,
            ),
            child: FadeTransition(
              opacity: curved,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.92, end: 1.0).animate(curved),
                child: child,
              ),
            ),
          );
        },
      );
    },
  );
}

class DailyCheckInPopup extends StatefulWidget {
  // Score shown in the ring (comes from the dashboard)
  final int wellnessScore;

  const DailyCheckInPopup({super.key, this.wellnessScore = 70});

  @override
  State<DailyCheckInPopup> createState() => _DailyCheckInPopupState();
}

// One emotion option
class CheckInOption {
  final String label;
  final IconData icon;

  const CheckInOption(this.label, this.icon);
}

class _DailyCheckInPopupState extends State<DailyCheckInPopup> {
  // The emotions the user can tap
  static const List<CheckInOption> options = [
    CheckInOption('Calm', Icons.sentiment_satisfied_alt),
    CheckInOption('Okay', Icons.sentiment_very_satisfied),
    CheckInOption('Tired', Icons.sentiment_neutral),
    CheckInOption('Stressed', Icons.sentiment_dissatisfied),
  ];

  // null = nothing selected yet
  String? selected;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: buildCard(),
        ),
      ),
    );
  }

  // ---------------------------------------------------
  // POP UP CARD: title, ring, emotion buttons and save
  // ---------------------------------------------------
  Widget buildCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: kCoral,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x40000000),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: "Daily Check In" pill + close button
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Daily Check In',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.black,
                  ),
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Icon(Icons.close, size: 24, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Text on the left, ring on the right
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'How are you\nfeeling today?',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Small check-ins help HUG understand your patterns.',
                      style: TextStyle(fontSize: 11, color: Colors.white),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 92,
                height: 92,
                child: CustomPaint(
                  painter: WellnessRingPainter(
                    progress: widget.wellnessScore / 100,
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${widget.wellnessScore}',
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                            color: kStarYellow,
                          ),
                        ),
                        const Text(
                          'Wellness',
                          style: TextStyle(fontSize: 11, color: kStarYellow),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),

          // The emotion options
          Row(
            children: [
              for (int i = 0; i < options.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(child: buildOption(options[i])),
              ],
            ],
          ),
          const SizedBox(height: 16),

          buildSaveButton(),
        ],
      ),
    );
  }

  // One tappable emotion button
  Widget buildOption(CheckInOption option) {
    final bool isSelected = selected == option.label;

    return Material(
      // Selected = white, not selected = see-through white
      color: isSelected ? Colors.white : const Color(0x33FFFFFF),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          setState(() {
            selected = option.label;
          });
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            children: [
              Icon(
                option.icon,
                size: 30,
                color: isSelected ? kCoral : Colors.white,
              ),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  option.label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: isSelected ? kCoral : Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------
  // SAVE BUTTON: sends the chosen emotion back to the dashboard
  // ---------------------------------------------------
  Widget buildSaveButton() {
    final bool canSave = selected != null;

    return Material(
      color: canSave ? Colors.white : const Color(0x33FFFFFF),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: canSave
            ? () {
                // TODO: save the check-in to the database here
                Navigator.pop(context, selected);
              }
            : null,
        child: SizedBox(
          width: double.infinity,
          height: 48,
          child: Center(
            child: Text(
              'Save Check-In',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: canSave ? kCoral : Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
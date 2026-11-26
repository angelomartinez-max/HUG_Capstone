// Hug - Main shell
// Holds the bottom bar and swaps the screen when a tab is tapped.

import 'package:material_ui/material_ui.dart';

import '../constants/colors.dart';
import 'chatbot_screen.dart';
import 'dashboard_screen.dart';
import 'insights_screen.dart';
import 'profile_screen.dart';
import 'wellness_screen.dart';

class MainShell extends StatefulWidget {
  // Name shown in the Home greeting (later this can come from the login)
  final String userName;

  const MainShell({super.key, this.userName = 'Juan'});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  // 0 = Home, 1 = Insights, 2 = Wellness, 3 = Profile
  int selectedTab = 0;

  @override
  Widget build(BuildContext context) {
    // The screens that the tabs switch between
    final List<Widget> pages = [
      DashboardScreen(userName: widget.userName),
      const InsightsScreen(),
      WellnessScreen(
        userName: widget.userName,
        // "View OCPS contact details" -> go to the Profile tab
        onOpenProfile: () => setState(() => selectedTab = 3),
      ),
      ProfileScreen(userName: widget.userName),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF4F4F4),
      body: Stack(
        children: [
          // IndexedStack keeps each screen alive when you switch tabs
          Positioned.fill(
            child: IndexedStack(index: selectedTab, children: pages),
          ),

          // Bottom bar with the big star button
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: buildBottomBar(context),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------
  // BOTTOM BAR: Home, Insights, big star, Wellness, Profile
  // ---------------------------------------------------
  Widget buildBottomBar(BuildContext context) {
    // Space for the phone's bottom gesture area
    final double bottomInset = MediaQuery.of(context).padding.bottom;

    return SizedBox(
      height: 100 + bottomInset,
      child: Stack(
        children: [
          // White bar
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 68 + bottomInset,
            child: Container(
              padding: EdgeInsets.only(bottom: bottomInset),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x1A000000),
                    blurRadius: 8,
                    offset: Offset(0, -2),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  buildNavItem(0, Icons.home_outlined, 'Home'),
                  buildNavItem(1, Icons.bar_chart, 'Insights'),
                  const SizedBox(width: 80), // empty space for the star
                  buildNavItem(2, Icons.monitor_heart_outlined, 'Wellness'),
                  buildNavItem(3, Icons.account_circle_outlined, 'Profile'),
                ],
              ),
            ),
          ),

          // Big star button in the middle (opens the chatbot)
          Align(
            alignment: Alignment.topCenter,
            child: GestureDetector(
              onTap: () {
                // Open the "Chat with Pat" screen on top of the shell.
                // The back arrow in the chatbot returns here.
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ChatbotScreen(),
                  ),
                );
              },
              child: Container(
                width: 74,
                height: 74,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: kCoral,
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x40000000),
                      blurRadius: 8,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: Padding(
                padding: const EdgeInsets.all(8),
               child: Image.asset(
               'assets/images/whitestar_logo.png',
               width: 58,
               height: 58,
              fit: BoxFit.contain,
              ),
              ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // One tab of the bottom bar
  Widget buildNavItem(int index, IconData icon, String label) {
    final bool selected = selectedTab == index;
    final Color color = selected ? kCoral : const Color(0xFF8E8E8E);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        setState(() {
          selectedTab = index;
        });
      },
      child: SizedBox(
        width: 60,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 26, color: color),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 10, color: color)),
          ],
        ),
      ),
    );
  }
}

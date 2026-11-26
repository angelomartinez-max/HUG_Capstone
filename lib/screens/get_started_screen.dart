
import 'package:material_ui/material_ui.dart';
import '../constants/colors.dart';
import '../widgets/collaboration_footer.dart';
import 'welcome_screen.dart';

class GetStartedScreen extends StatelessWidget {
  const GetStartedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  const Spacer(flex: 3),

                  // Title
                  const Text(
                    'Your mental\nwell-being matters!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 29,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                      color: Colors.black,
                    ),
                  ),

                  const Spacer(flex: 2),

                  // HUG Logo
                  Image.asset(
                    'assets/images/hug_logo.png',
                    width: 170,
                    height: 170,
                    fit: BoxFit.contain,
                  ),

                  const Spacer(flex: 2),

                  // Description
                  const Text(
                    "Let's get you set up to monitor your wellness "
                    "trends and find the support you deserve.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.7,
                      color: Colors.black87,
                    ),
                  ),

                  const SizedBox(height: 30),

                  // Get Started Button
                  SizedBox(
                    width: 230,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                const WelcomeScreen(),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kCoral,
                        foregroundColor: Colors.white,
                        elevation: 2,
                        shadowColor: kCoral.withOpacity(0.25),
                        shape: const StadiumBorder(),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                        ),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Get Started',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(width: 14),
                          Icon(
                            Icons.arrow_forward_rounded,
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                  ),

                  const Spacer(flex: 3),

                  // Collaboration Footer
                  const CollaborationFooter(),

                  const SizedBox(height: 16),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

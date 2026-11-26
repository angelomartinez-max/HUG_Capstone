// Hug - Welcome screen (Sign up / Log in)

import 'package:material_ui/material_ui.dart';
import '../constants/colors.dart';
import '../widgets/collaboration_footer.dart';
import '../widgets/welcome_star_painter.dart';
import 'login_screen.dart';
import 'signup_screen.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  // Whether the user accepted the terms (checkbox state)
  bool accepted = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SizedBox(
          width: double.infinity,
          child: Column(
            children: [
              const Spacer(flex: 3),

              // Star mascot with motion lines (tilted)
             // HUG Logo
           Image.asset(
          'assets/images/starlogo.png',
           width: 150,
           height: 150,
           fit: BoxFit.contain,
           ),
              const SizedBox(height: 4),

              // Title
              const Text(
                'Welcome to Hug',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 6),

              // Subtitle
              const Text(
                'Your Mental Well-being Companion',
                style: TextStyle(fontSize: 14, color: Colors.black87),
              ),
              const Spacer(flex: 3),

              // Checkbox + terms text
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 36),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Custom checkbox: coral rounded square
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          accepted = !accepted;
                        });
                      },
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: accepted ? kCoral : Colors.white,
                          border: Border.all(color: kCoral, width: 2),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: accepted
                            ? const Icon(Icons.check,
                            size: 14, color: Colors.white)
                            : null,
                      ),
                    ),
                    const SizedBox(width: 10),

                    // Terms text with pink links
                    const Expanded(
                      child: Text.rich(
                        TextSpan(
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.35,
                            color: Colors.black87,
                          ),
                          children: [
                            TextSpan(text: "I accept Hug's "),
                            TextSpan(
                              text: 'Terms and Conditions',
                              style: TextStyle(color: kLinkPink),
                            ),
                            TextSpan(
                                text: " and confirm that I've read the "),
                            TextSpan(
                              text: 'Privacy Policy.',
                              style: TextStyle(color: kLinkPink),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              // Sign up and Log in buttons
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 36),
                child: Row(
                  children: [
                    // Sign up (filled coral)
                    Expanded(
                      child: SizedBox(
                        height: 42,
                        child: ElevatedButton(
                          onPressed: () {
                            // VALIDATION: the terms must be accepted first
                            if (!accepted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Please accept the Terms and Conditions and Privacy Policy to continue.',
                                  ),
                                ),
                              );
                              return;
                            }

                            // Go to the Sign up screen
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const SignUpScreen(),
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kCoral,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: const StadiumBorder(),
                          ),
                          child: const Text(
                            'Sign up',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),

                    // Log in (light grey with coral text)
                    Expanded(
                      child: SizedBox(
                        height: 42,
                        child: ElevatedButton(
                          onPressed: () {
                            // VALIDATION: the terms must be accepted first
                            if (!accepted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Please accept the Terms and Conditions and Privacy Policy to continue.',
                                  ),
                                ),
                              );
                              return;
                            }

                            // Go to the Log in screen
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const LoginScreen(),
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kButtonGrey,
                            foregroundColor: kCoral,
                            elevation: 0,
                            shape: const StadiumBorder(),
                          ),
                          child: const Text(
                            'Log in',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(flex: 5),

              // Footer
              const CollaborationFooter(),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
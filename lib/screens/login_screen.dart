// Hug - Log in screen
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../constants/colors.dart';
import '../widgets/collaboration_footer.dart';
import 'main_shell.dart';
import 'signup_screen.dart';
import 'welcome_screen.dart';
import 'forgot_password_screen.dart';
import '../services/auth_service.dart';

// Turns everything the user types into CAPITAL letters.
// We use this on the student number so "mn" becomes "MN".
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // ---------------------------------------------------
  // TEXT BOXES AND FOCUS
  // ---------------------------------------------------
  // Text boxes: these hold what the user types
  final TextEditingController studentNumberController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  // Focus nodes: we use these to jump to the first box that has an error
  final FocusNode studentNumberFocus = FocusNode();
  final FocusNode passwordFocus = FocusNode();

  // true = password is hidden, false = password is shown
  bool hidePassword = true;

  // "Remember me" checkbox state
  bool rememberMe = false;

  // true = the Log in button was pressed at least once.
  // After that, the errors update live while the user types.
  bool submitted = false;

  // true = we are waiting for the server to check the login
  bool isLoggingIn = false;

  // ---------------------------------------------------
  // VALIDATION SETTINGS
  // ---------------------------------------------------
  // Red error message under each box (null = no error)
  String? studentNumberError;
  String? passwordError;

  // Red message for a wrong login (shown above the Log in button)
  String? loginError;

  // Message to show when checkLogin fails
  String loginFailMessage = 'Wrong student number or password.';

  // Student number format: 2024-13242-MN-0
  // (4 numbers - 5 numbers - 2 letters - 1 number)
  final RegExp studentNumberPattern = RegExp(r'^\d{4}-\d{5}-[A-Za-z]{2}-\d$');

  // Maximum lengths
  final int maxStudentNumberLength = 15;
  final int maxPasswordLength = 64;

  // ---------------------------------------------------
  // ONE CHECK PER BOX
  // ---------------------------------------------------

  // Student number check
  String? validateStudentNumber() {
    final String value = studentNumberController.text.trim();
    if (value.isEmpty) {
      return 'Student number is required.';
    }
    if (!studentNumberPattern.hasMatch(value)) {
      return 'Wrong format. Example: 2024-13242-MN-0';
    }
    return null;
  }

  // Password check.
  // On Log in we only check that it is not empty. We do NOT show the
  // password rules here, because that would give hints to attackers.
  String? validatePassword() {
    if (passwordController.text.isEmpty) {
      return 'Password is required.';
    }
    return null;
  }

  // ---------------------------------------------------
  // CHECK THE WHOLE FORM
  // ---------------------------------------------------

  // Checks every box. Returns true only if everything is correct.
  bool validateForm() {
    final String? studentError = validateStudentNumber();
    final String? createError = validatePassword();

    // Show all the errors at once
    setState(() {
      studentNumberError = studentError;
      passwordError = createError;
      loginError = null;
    });

    // Go to the first box (from top to bottom) that has an error
    if (studentError != null) {
      focusOn(studentNumberFocus);
    } else if (createError != null) {
      focusOn(passwordFocus);
    }

    return studentError == null && createError == null;
  }

  // Runs while the user types. It only works after Log in was pressed once,
  // so the user does not see errors before they finish typing.
  void refreshErrors() {
    if (!submitted) return;
    setState(() {
      studentNumberError = validateStudentNumber();
      passwordError = validatePassword();
      // The "wrong login" message goes away when the user edits a box
      loginError = null;
    });
  }

  // Moves the cursor to a box and scrolls the screen so it is visible
  void focusOn(FocusNode node) {
    // Wait one frame so the new error texts are already drawn
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      node.requestFocus();
      final BuildContext? boxContext = node.context;
      if (boxContext != null) {
        Scrollable.ensureVisible(
          boxContext,
          duration: const Duration(milliseconds: 300),
          alignment: 0.2,
        );
      }
    });
  }

  // ---------------------------------------------------
  // LOGIN CHECK (BACKEND)
  // ---------------------------------------------------
  // 1. Find the email that belongs to the student number
  //    (Supabase function: email_for_student_number)
  // 2. Sign in with that email and the password
  Future<bool> checkLogin(String studentNumber, String password) async {
    // Default: same message for wrong student number or wrong password
    loginFailMessage = 'Wrong student number or password.';
    try {
      final dynamic result = await Supabase.instance.client.rpc(
        'email_for_student_number',
        params: {'sn': studentNumber},
      );
      final String? email = result as String?;
      debugPrint('HUG step 1 - email found: $email');
      if (email == null || email.isEmpty) return false;

      final authService = AuthService();
      return await authService.signInWithEmail(
        email: email,
        password: password,
        studentNumber: studentNumber,
      );
    } on AuthException catch (error) {
      if (error.code == 'email_not_confirmed' ||
          error.message.toLowerCase().contains('email not confirmed')) {
        loginFailMessage = 'Your email is not verified yet. Check your inbox for the 6-digit code.';
      }
      debugPrint('HUG authentication failed: $error');
      return false;
    } catch (error) {
      debugPrint('HUG authentication failed: $error');
      return false;
    }
  }

  // Runs when the Log in button is pressed
  Future<void> handleLogin() async {
    // From now on, errors update live while typing
    submitted = true;

    // Check all the boxes first.
    // If something is wrong, stop here and show errors.
    if (!validateForm()) return;

    // Make the student number uppercase and remove extra spaces
    studentNumberController.text = studentNumberController.text
        .trim()
        .toUpperCase();

    // Ask the backend if the login is correct
    setState(() {
      isLoggingIn = true;
    });
    final bool success = await checkLogin(
      studentNumberController.text,
      passwordController.text,
    );

    // The screen may be closed while we waited
    if (!mounted) return;

    if (!success) {
      // We do not say which one is wrong (student number or password)
      setState(() {
        isLoggingIn = false;
        loginError = loginFailMessage;
      });
      return;
    }

    setState(() {
      isLoggingIn = false;
    });

    // TODO: if rememberMe is true, save the login here.
    // pushAndRemoveUntil clears the old screens,
    // so back does not return to Log in.
    // MainShell holds the bottom bar and the Home / Insights tabs.
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const MainShell()),
      (route) => false,
    );
  }

  // ---------------------------------------------------
  // WIDGET HELPERS
  // ---------------------------------------------------

  // Small red text shown under a box when it has an error
  Widget buildError(String? message) {
    if (message == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(left: 16, top: 6),
      child: Text(
        message,
        style: const TextStyle(fontSize: 12, color: Colors.red),
      ),
    );
  }

  @override
  void dispose() {
    // Free the memory used by the text boxes and focus nodes
    studentNumberController.dispose();
    passwordController.dispose();
    studentNumberFocus.dispose();
    passwordFocus.dispose();
    super.dispose();
  }

  // Builds one grey rounded text box (used for both fields)
  Widget buildField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String hint,
    required IconData icon,
    bool obscure = false,
    Widget? suffix,
    TextInputType keyboardType = TextInputType.text,
    TextCapitalization capitalization = TextCapitalization.none,
    List<TextInputFormatter>? formatters,
  }) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      obscureText: obscure,
      keyboardType: keyboardType,
      textCapitalization: capitalization,
      inputFormatters: formatters,
      // Passwords should not be auto-corrected or suggested
      autocorrect: !obscure,
      enableSuggestions: !obscure,
      // Check this box again every time the user types
      onChanged: (String value) {
        refreshErrors();
      },
      cursorColor: kCoral,
      style: const TextStyle(fontSize: 14, color: Colors.black87),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 14, color: Color(0xFFBDBDBD)),
        filled: true,
        fillColor: kButtonGrey,
        prefixIcon: Icon(icon, color: Colors.black54, size: 24),
        suffixIcon: suffix,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // The form can scroll when the keyboard is open
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),

                    // Back arrow
                    GestureDetector(
                      onTap: () {
                        if (Navigator.canPop(context)) {
                          Navigator.pop(context);
                        } else {
                          // Nothing to go back to (for example after log out),
                          // so go to the Welcome screen
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const WelcomeScreen(),
                            ),
                          );
                        }
                      },
                      child: const Icon(
                        Icons.arrow_back,
                        color: Colors.black,
                        size: 26,
                      ),
                    ),
                    const SizedBox(height: 22),

                    // Title
                    const Text(
                      'Log in',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 22),

                    // Student number
                    const Text(
                      'Student Number',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 8),
                    buildField(
                      controller: studentNumberController,
                      focusNode: studentNumberFocus,
                      hint: 'Student Number',
                      icon: Icons.numbers,
                      // Show capital letters on the keyboard
                      capitalization: TextCapitalization.characters,
                      formatters: [
                        // Only numbers, letters and hyphen
                        FilteringTextInputFormatter.allow(
                          RegExp(r'[0-9A-Za-z-]'),
                        ),
                        // Make letters uppercase while typing
                        UpperCaseTextFormatter(),
                        LengthLimitingTextInputFormatter(
                          maxStudentNumberLength,
                        ),
                      ],
                    ),
                    buildError(studentNumberError),
                    const SizedBox(height: 18),

                    // Password
                    const Text(
                      'Password',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 8),
                    buildField(
                      controller: passwordController,
                      focusNode: passwordFocus,
                      hint: 'Password',
                      icon: Icons.lock_outline,
                      obscure: hidePassword,
                      formatters: [
                        LengthLimitingTextInputFormatter(maxPasswordLength),
                      ],
                      // Eye button: show or hide the password
                      suffix: IconButton(
                        onPressed: () {
                          setState(() {
                            hidePassword = !hidePassword;
                          });
                        },
                        icon: Icon(
                          hidePassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          color: Colors.black54,
                        ),
                      ),
                    ),
                    buildError(passwordError),
                    const SizedBox(height: 22),

                    // Message for a wrong login (only shows when needed)
                    if (loginError != null) ...[
                      Center(
                        child: Text(
                          loginError!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.red,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    // Log in button
                    Center(
                      child: SizedBox(
                        width: 290,
                        height: 42,
                        child: ElevatedButton(
                          // Disabled while we wait for the server
                          onPressed: isLoggingIn ? null : handleLogin,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kCoral,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: kCoral,
                            disabledForegroundColor: Colors.white,
                            elevation: 0,
                            shape: const StadiumBorder(),
                          ),
                          child: isLoggingIn
                              // Small spinner while logging in
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  'Log in',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Remember me + Forgot password
                    Row(
                      children: [
                        // Custom checkbox: coral rounded square
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              rememberMe = !rememberMe;
                            });
                          },
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: rememberMe ? kCoral : Colors.white,
                              border: Border.all(color: kCoral, width: 2),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: rememberMe
                                ? const Icon(
                                    Icons.check,
                                    size: 14,
                                    color: Colors.white,
                                  )
                                : null,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Remember me',
                          style: TextStyle(fontSize: 14, color: Colors.black87),
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    const ForgotPasswordScreen(),
                              ),
                            );
                          },
                          child: const Text(
                            'Forgot Password?',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: kCoral,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    // Link to Sign up
                    Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            "Don't have an account? ",
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.black87,
                            ),
                          ),
                          GestureDetector(
                            onTap: () {
                              // Swap this screen for the Sign up screen
                              // (replace, so the screens do not pile up)
                              Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const SignUpScreen(),
                                ),
                              );
                            },
                            child: const Text(
                              'Sign Up',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: kCoral,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Footer
            const SizedBox(height: 12),
            const CollaborationFooter(),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

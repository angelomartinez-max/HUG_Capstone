
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<bool> signInWithEmail({
    required String email,
    required String password,
    required String studentNumber,
  }) async {
    await _supabase.auth.signOut();

    try {
      final response = await _supabase.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );

      final user = response.user;

      if (user == null || response.session == null) {
        return false;
      }

      final profile = await _supabase
          .from('student_profiles')
          .select('student_number')
          .eq('id', user.id)
          .maybeSingle();

      final storedStudentNumber =
          profile?['student_number'] as String?;

      if (storedStudentNumber == null ||
          storedStudentNumber.toUpperCase() !=
              studentNumber.trim().toUpperCase()) {
        await _supabase.auth.signOut();
        return false;
      }

      return true;
    } catch (error) {
      await _supabase.auth.signOut();
      rethrow;
    }
  }

  Future<void> signOut() async {
    await _supabase.auth.signOut();
  }

  bool get isLoggedIn =>
      _supabase.auth.currentSession != null;
}

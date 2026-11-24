
import 'package:supabase_flutter/supabase_flutter.dart';

class ChatbotService {
  final SupabaseClient _supabase = Supabase.instance.client;

  String? _sessionId;
  String? _ownerId;

  String? get sessionId => _sessionId;

  Future<String> getReply(String message) async {
    final user = _supabase.auth.currentUser;

    if (_supabase.auth.currentSession == null || user == null) {
      clearHistory();

      throw Exception(
        'Please sign in to your HUG account before chatting with Pat.',
      );
    }

    // Prevent sessions from carrying over to another student.
    if (_ownerId != user.id) {
      clearHistory();
      _ownerId = user.id;
    }

    final response = await _supabase.functions.invoke(
      'hug-chatbot',
      method: HttpMethod.post,
      body: {
        'message': message.trim(),
        'session_id': _sessionId,
      },
    );

    final data = response.data;

    if (data is! Map ||
        data['reply'] is! String ||
        data['session_id'] is! String) {
      throw Exception('Pat returned an unexpected response.');
    }

    // Verify that the account has not changed.
    if (_supabase.auth.currentUser?.id != user.id) {
      clearHistory();
      throw Exception('Your session has changed.');
    }

    // Retain the session ID for the next message.
    _sessionId = data['session_id'] as String;

    return data['reply'] as String;
  }

  // Start a new conversation without deleting saved messages.
  void clearHistory() {
    _sessionId = null;
    _ownerId = null;
  }
}

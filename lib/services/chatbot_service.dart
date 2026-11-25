import 'package:supabase_flutter/supabase_flutter.dart';

// What Pat decided after reading the student's answer.
enum ChatOutcome {
  // The conversation goes on, no decision yet.
  continueChat,

  // Signs of stress, anxiety or low mood: show the questionnaire button.
  offerScreening,

  // Ordinary explanation (exercise, coffee, rushing): nothing more to do.
  keepMonitoring,
}

// Pat's answer plus the decision label.
class ChatReply {
  final String reply;
  final ChatOutcome outcome;

  const ChatReply({required this.reply, required this.outcome});
}

class ChatbotService {
  final SupabaseClient _supabase = Supabase.instance.client;

  String? _sessionId;
  String? _ownerId;

  // Facts from the watch trigger (null = normal manual chat)
  String? _triggerContext;

  String? get sessionId => _sessionId;

  // Called by ChatbotScreen when it was opened by the watch trigger
  void setHiddenContext(String context) {
    _triggerContext = context;
  }

  // Pat's first message when the chat was opened by the trigger
  Future<ChatReply> getOpeningQuestion() {
    return _send(message: null, opening: true);
  }

  // Normal message from the student
  Future<ChatReply> getReply(String message) {
    return _send(message: message.trim(), opening: false);
  }

  // Turns the text label from the Edge Function into an enum.
  // Anything unknown or missing becomes "continue" so nothing breaks.
  ChatOutcome _parseOutcome(dynamic value) {
    switch (value) {
      case 'offer_screening':
        return ChatOutcome.offerScreening;
      case 'keep_monitoring':
        return ChatOutcome.keepMonitoring;
      default:
        return ChatOutcome.continueChat;
    }
  }

  Future<ChatReply> _send({
    required String? message,
    required bool opening,
  }) async {
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
        'message': message,
        'session_id': _sessionId,
        'opening': opening,
        'trigger_context': _triggerContext,
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

    return ChatReply(
      reply: data['reply'] as String,
      outcome: _parseOutcome(data['outcome']),
    );
  }

  // Start a new conversation without deleting saved messages.
  void clearHistory() {
    _sessionId = null;
    _ownerId = null;
    _triggerContext = null;
  }
}

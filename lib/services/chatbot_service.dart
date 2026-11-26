import 'package:supabase_flutter/supabase_flutter.dart';

enum ChatOutcome {
  continueChat,
  offerScreening,
  keepMonitoring,
  medicalAttention,
  urgentSupport,
}

class ChatReply {
  final String reply;
  final ChatOutcome outcome;
  final List<String> recommendedScreenings;

  const ChatReply({
    required this.reply,
    required this.outcome,
    this.recommendedScreenings = const [],
  });
}

class ChatbotService {
  final SupabaseClient _supabase = Supabase.instance.client;

  String? _sessionId;
  String? _ownerId;
  String? _triggerContext;

  String? get sessionId => _sessionId;

  void setHiddenContext(String context) {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      clearHistory();
      return;
    }

    if (_ownerId != user.id) {
      clearHistory();
      _ownerId = user.id;
    }

    _triggerContext = context;
  }

  Future<ChatReply> getOpeningQuestion() {
    return _send(message: null, opening: true);
  }

  Future<ChatReply> getReply(String message) {
    return _send(message: message.trim(), opening: false);
  }

  ChatOutcome _parseOutcome(dynamic value) {
    switch (value) {
      case 'offer_screening':
        return ChatOutcome.offerScreening;

      case 'keep_monitoring':
        return ChatOutcome.keepMonitoring;

      case 'medical_attention':
        return ChatOutcome.medicalAttention;

      case 'urgent_support':
        return ChatOutcome.urgentSupport;

      case 'continue':
      default:
        return ChatOutcome.continueChat;
    }
  }

  // Parse and validate recommended questionnaires.
  List<String> _parseScreenings(dynamic value) {
    const allowed = {'PSS-4', 'GAD-7', 'PHQ-9'};

    if (value is! List) {
      return const [];
    }

    return List<String>.unmodifiable(
      value.whereType<String>().where(allowed.contains).toSet(),
    );
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

    final outcome = _parseOutcome(data['outcome']);

    // Receive the recommended questionnaires.
    final recommendedScreenings = outcome == ChatOutcome.offerScreening
        ? _parseScreenings(data['recommended_screenings'])
        : const <String>[];

    // Return the reply, outcome, and recommendations.
    return ChatReply(
      reply: data['reply'] as String,
      outcome: outcome,
      recommendedScreenings: recommendedScreenings,
    );
  }

  // Start a new conversation without deleting saved messages.
  void clearHistory() {
    _sessionId = null;
    _ownerId = null;
    _triggerContext = null;
  }
}

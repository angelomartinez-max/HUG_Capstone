import 'package:supabase_flutter/supabase_flutter.dart';

class ScreeningService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // =========================================
  // BASE API REQUEST
  // =========================================

  Future<Map<String, dynamic>> _request(
    String action, {
    Map<String, dynamic>? parameters,
  }) async {
    final user = _supabase.auth.currentUser;

    if (_supabase.auth.currentSession == null || user == null) {
      throw Exception('Please sign in first.');
    }

    final response = await _supabase.functions.invoke(
      'hug-screening',
      method: HttpMethod.post,
      body: {...?parameters, 'action': action},
    );

    if (_supabase.auth.currentUser?.id != user.id) {
      throw Exception('Your session has changed.');
    }

    final data = response.data;

    if (data is! Map) {
      throw Exception('Invalid screening API response.');
    }

    final result = Map<String, dynamic>.from(data);

    if (result['success'] != true) {
      throw Exception(result['error'] ?? 'Screening request failed.');
    }

    return result;
  }

  // =========================================
  // 1. CONNECTION TEST
  // =========================================

  Future<Map<String, dynamic>> ping() async {
    return _request('ping');
  }

  // =========================================
  // 2. GET QUESTIONNAIRES
  // =========================================

  Future<List<Map<String, dynamic>>> getQuestionnaires({
    List<String>? codes,
  }) async {
    if (codes != null && codes.isEmpty) {
      return [];
    }

    final result = await _request(
      'get_questionnaires',
      parameters: {'codes': ?codes},
    );

    return List<Map<String, dynamic>>.from(result['questionnaires'] as List);
  }

  // =========================================
  // 3. GET QUESTIONS
  // =========================================

  Future<Map<String, dynamic>> getQuestions(String questionnaireId) async {
    return _request(
      'get_questions',
      parameters: {'questionnaire_id': questionnaireId},
    );
  }

  // =========================================
  // 4. START SCREENING
  // =========================================

  Future<Map<String, dynamic>> startScreening({
    required String questionnaireId,
    String? chatSessionId,
  }) async {
    return _request(
      'start_screening',
      parameters: {
        'questionnaire_id': questionnaireId,
        'chat_session_id': ?chatSessionId,
      },
    );
  }

  // =========================================
  // 5. GET ACTIVE SCREENING SESSIONS
  // =========================================

  Future<List<Map<String, dynamic>>> getActiveSessions() async {
    final result = await _request('get_active_sessions');

    return List<Map<String, dynamic>>.from(result['sessions'] as List);
  }

  // =========================================
  // 6. SAVE ANSWER
  // =========================================

  Future<Map<String, dynamic>> saveAnswer({
    required String screeningId,
    required String questionId,
    required int answerValue,
  }) async {
    if (answerValue < 0 || answerValue > 4) {
      throw Exception('Invalid answer value.');
    }

    return _request(
      'save_answer',
      parameters: {
        'screening_id': screeningId,
        'question_id': questionId,
        'answer_value': answerValue,
      },
    );
  }

  // =========================================
  // 7. RESUME SCREENING
  // =========================================

  Future<Map<String, dynamic>> resumeScreening(String screeningId) async {
    return _request(
      'resume_screening',
      parameters: {'screening_id': screeningId},
    );
  }

  // =========================================
  // 8. PAUSE SCREENING
  // =========================================

  Future<Map<String, dynamic>> pauseScreening(String screeningId) async {
    return _request(
      'pause_screening',
      parameters: {'screening_id': screeningId},
    );
  }

  // =========================================
  // 9. DECLINE SCREENING
  // =========================================

  Future<Map<String, dynamic>> declineScreening(String screeningId) async {
    return _request(
      'decline_screening',
      parameters: {'screening_id': screeningId},
    );
  }

  // =========================================
  // 10. COMPLETE SCREENING
  // =========================================

  Future<Map<String, dynamic>> completeScreening(String screeningId) async {
    return _request(
      'complete_screening',
      parameters: {'screening_id': screeningId},
    );
  }

  // =========================================
  // 11. GET SCREENING RESULTS
  // =========================================

  Future<Map<String, dynamic>> getResults(String screeningId) async {
    final result = await _request(
      'get_results',
      parameters: {'screening_id': screeningId},
    );

    return Map<String, dynamic>.from(result['result'] as Map);
  }
}

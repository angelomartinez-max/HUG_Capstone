// Hug - Chatbot screen ("Chat with Pat")
// Opened by the big star button in the bottom bar.
import '../services/chatbot_service.dart';
import '../services/screening_service.dart';

import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'dart:math';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../constants/colors.dart';

// One message in the chat
class ChatMessage {
  // The words of the message
  final String text;

  // true = written by the user, false = written by Pat
  final bool fromUser;

  const ChatMessage({required this.text, required this.fromUser});
}

class ChatbotScreen extends StatefulWidget {
  // null = the student opened the chat manually.
  // Has text = the watch trigger opened the chat (hidden context for Pat).
  final String? triggerContext;

  const ChatbotScreen({super.key, this.triggerContext});

  @override
  State<ChatbotScreen> createState() => _ChatbotScreenState();
}

class _ChatbotScreenState extends State<ChatbotScreen> {
  // ---------------------------------------------------
  // STATE
  // ---------------------------------------------------
  // The text box and the list scroll
  final ChatbotService chatbotService = ChatbotService();

  final TextEditingController messageController = TextEditingController();
  final ScrollController scrollController = ScrollController();

  // All the messages shown on the screen
  final List<ChatMessage> messages = [];

  // true = we are waiting for Pat to answer
  bool isWaiting = false;

  // true = the text box has something in it (turns the send button on)
  bool hasText = false;

  // true = Pat decided the student should see the questionnaire button
  final ScreeningService screeningService = ScreeningService();
  final String? ownerId = Supabase.instance.client.auth.currentUser?.id;
  StreamSubscription<AuthState>? authSubscription;
  List<Map<String, dynamic>> activeSessions = [];
  Map<String, dynamic>? screening;
  int? selectedAnswer;
  bool openingScreening = false;
  bool checking = true;
  bool checkFailed = false;
  bool accountChanged = false;
  bool get validOwner =>
      mounted &&
      !accountChanged &&
      ownerId != null &&
      Supabase.instance.client.auth.currentUser?.id == ownerId;
  bool get chatLocked =>
      checking ||
      checkFailed ||
      accountChanged ||
      activeSessions.isNotEmpty ||
      screening != null;
  bool get showScreeningButton =>
      activeSessions.isNotEmpty && screening == null;

  // Speech-to-text
  final stt.SpeechToText speech = stt.SpeechToText();

  bool speechEnabled = false;
  bool isListening = false;
  bool micBusy = false;
  bool acceptSpeechResults = false;

  // Maximum length of one message
  final int maxMessageLength = 500;

  // Quick reply buttons shown above the text box
  final List<String> quickReplies = ['I just want to talk', 'Help me be calm'];

  // Colors only used in this screen
  static const Color kBackground = Color(0xFFF4F4F4);

  // ---------------------------------------------------
  // START (trigger)
  // ---------------------------------------------------
  @override
  void initState() {
    super.initState();
    authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((
      event,
    ) {
      if (!mounted || event.session?.user.id == ownerId) return;
      acceptSpeechResults = false;
      speech.cancel();
      chatbotService.clearHistory();
      messageController.clear();
      setState(() {
        accountChanged = true;
        messages.clear();
        activeSessions = [];
        screening = null;
        selectedAnswer = null;
      });
    });
    initializeChat();
  }

  Future<void> initializeChat() async {
    await refreshScreenings();
    if (!validOwner || chatLocked) return;
    final ctx = widget.triggerContext;
    if (ctx != null && ctx.trim().isNotEmpty) {
      chatbotService.setHiddenContext(ctx);
      await startTriggeredChat();
    }
  }

  Future<void> refreshScreenings() async {
    if (!validOwner) return;
    setState(() {
      checking = true;
      checkFailed = false;
    });
    try {
      final ping = await screeningService.ping();
      if (!validOwner) return;
      final sessions = ping['test_access'] == true
          ? await screeningService.getActiveSessions()
          : <Map<String, dynamic>>[];
      if (!validOwner) return;
      setState(() {
        activeSessions = sessions;
        checking = false;
      });
      if (sessions.isNotEmpty &&
          sessions.first['status'] != 'pending' &&
          screening == null) {
        await openScreening();
      }
    } catch (_) {
      if (validOwner) {
        setState(() {
          checking = false;
          checkFailed = true;
        });
      }
    }
  }

  // Pat asks the first question when the watch trigger opened the chat
  Future<void> startTriggeredChat() async {
    setState(() {
      isWaiting = true;
    });

    String reply;
    try {
      final ChatReply result = await chatbotService.getOpeningQuestion();
      reply = result.reply;
    } catch (error) {
      debugPrint('Pat opening error: $error');
      // Only used when Pat cannot be reached (no internet or server error).
      reply = 'Hi, it\'s Pat. Just checking in. How are you feeling today?';
    }

    if (!validOwner) return;

    setState(() {
      messages.add(ChatMessage(text: reply, fromUser: false));
      isWaiting = false;
    });
    await refreshScreenings();
    scrollToBottom();
  }

  // ---------------------------------------------------
  // CHATBOT (BACKEND)
  // ---------------------------------------------------
  // Sends the user's message to the chatbot and returns Pat's answer
  // together with the decision label.
  Future<ChatReply> getPatReply(String userMessage) async {
    return await chatbotService.getReply(userMessage);
  }

  // ---------------------------------------------------
  // ACTIONS
  // ---------------------------------------------------
  Future<void> toggleListening() async {
    if (chatLocked || isWaiting || micBusy) return;

    micBusy = true;

    try {
      if (speech.isListening) {
        await speech.stop();

        if (!mounted) return;

        setState(() {
          isListening = false;
        });

        return;
      }

      if (!speechEnabled) {
        speechEnabled = await speech.initialize(
          onStatus: (status) {
            if (!mounted) return;

            setState(() {
              isListening = status == 'listening';
            });
          },
          onError: (error) {
            if (!mounted) return;

            setState(() {
              isListening = false;
              acceptSpeechResults = false;
            });
          },
        );
      }

      if (!mounted) return;

      if (!speechEnabled) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Speech recognition is unavailable. '
              'Please check your microphone permission.',
            ),
          ),
        );
        return;
      }

      acceptSpeechResults = true;

      await speech.listen(
        onResult: (result) {
          if (!mounted || !acceptSpeechResults || isWaiting || chatLocked) {
            return;
          }

          String recognizedText = result.recognizedWords;

          if (recognizedText.length > maxMessageLength) {
            recognizedText = recognizedText.substring(0, maxMessageLength);
          }

          setState(() {
            messageController.text = recognizedText;

            messageController.selection = TextSelection.collapsed(
              offset: recognizedText.length,
            );

            hasText = recognizedText.trim().isNotEmpty;
          });
        },
      );

      if (!mounted) return;

      setState(() {
        isListening = speech.isListening;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        isListening = false;
        acceptSpeechResults = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to start voice recognition.')),
      );
    } finally {
      micBusy = false;
    }
  }

  // Sends a message (typed text or a quick reply button)
  Future<void> sendMessage(String text) async {
    final String message = text.trim();

    // Do nothing for empty text, or while Pat is still answering
    if (message.isEmpty || isWaiting || chatLocked) return;

    acceptSpeechResults = false;

    if (speech.isListening) {
      await speech.stop();
    }

    if (!validOwner || isWaiting || chatLocked) return;

    isListening = false;

    setState(() {
      messages.add(ChatMessage(text: message, fromUser: true));
      messageController.clear();
      hasText = false;
      isWaiting = true;
    });
    scrollToBottom();

    ChatReply result;

    try {
      result = await getPatReply(message);
    } catch (error) {
      debugPrint('Pat chatbot error: $error');
      // When Pat cannot be reached, no decision is made.
      result = const ChatReply(
        reply:
            'Sorry, I am having trouble connecting right now. '
            'Please try again in a moment.',
        outcome: ChatOutcome.continueChat,
      );
    }

    // The screen may be closed while we waited
    if (!validOwner) return;

    setState(() {
      messages.add(ChatMessage(text: result.reply, fromUser: false));
      isWaiting = false;
    });
    await refreshScreenings();
    scrollToBottom();
  }

  Future<void> openScreening() async {
    if (!validOwner || openingScreening || activeSessions.isEmpty) return;
    setState(() => openingScreening = true);
    try {
      final data = await screeningService.resumeScreening(
        activeSessions.first['screening_id'] as String,
      );
      if (!validOwner) return;
      setState(() {
        screening = data;
        selectedAnswer = null;
      });
      scrollToBottom();
    } catch (_) {
      if (validOwner) showScreeningError();
    } finally {
      if (validOwner) setState(() => openingScreening = false);
    }
  }

  void showScreeningError() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Unable to update your check-in. Please try again.'),
      ),
    );
  }

  List<Map<String, dynamic>> get questions =>
      List<Map<String, dynamic>>.from(screening?['questions'] as List? ?? []);
  Map<String, dynamic>? get currentQuestion {
    final next = screening?['next_question'];
    for (final q in questions) {
      if (q['question_number'] == next) return q;
    }
    return null;
  }

  Future<void> advanceScreening() async {
    if (!validOwner || openingScreening || screening == null) return;
    final id = screening!['screening_id'] as String;
    final q = currentQuestion;
    final answer = selectedAnswer;
    if (screening!['ready_to_complete'] != true &&
        (q == null || answer == null)) {
      return;
    }
    setState(() => openingScreening = true);
    try {
      if (q != null && screening!['ready_to_complete'] != true) {
        final saved = await screeningService.saveAnswer(
          screeningId: id,
          questionId: q['question_id'] as String,
          answerValue: answer!,
        );
        if (!validOwner) return;
        final updated = await screeningService.resumeScreening(id);
        if (!validOwner) return;
        setState(() {
          screening = updated;
          selectedAnswer = null;
        });
        if (saved['safety_flag'] == true) {
          setState(
            () => messages.add(
              const ChatMessage(
                text: 'If you might hurt yourself or are in immediate danger, call 911 or go to the nearest emergency department. Reach out to someone you trust or a counselor.',
                fromUser: false,
              ),
            ),
          );
        }
      }
      if (screening!['ready_to_complete'] == true) {
        await screeningService.completeScreening(id);
        if (!validOwner) return;
        setState(() {
          screening = null;
          selectedAnswer = null;
          messages.add(
            const ChatMessage(
              text: 'Your check-in has been saved.',
              fromUser: false,
            ),
          );
        });
        await refreshScreenings();
      }
    } catch (_) {
      if (validOwner) showScreeningError();
    } finally {
      if (validOwner) setState(() => openingScreening = false);
      scrollToBottom();
    }
  }

  Widget buildScreeningCard() {
    final q = currentQuestion;
    final meta = screening!['questionnaire'] as Map;
    final ready = screening!['ready_to_complete'] == true;
    final number = (q?['question_number'] as int?) ?? questions.length;
    final options = (q?['answer_options'] as List?) ?? [];
    return Card(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '${meta['code']}',
                  style: const TextStyle(
                    color: kCoral,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Text('Question $number of ${questions.length}'),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: questions.isEmpty ? 0 : number / questions.length,
              color: kCoral,
            ),
            const SizedBox(height: 12),
            Text('${meta['instructions'] ?? ''}'),
            const SizedBox(height: 12),
            if (q != null)
              Text(
                '${q['question_text']}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            for (final option in options)
              InkWell(
                onTap: openingScreening
                    ? null
                    : () => setState(
                        () => selectedAnswer = option['value'] as int,
                      ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      Icon(
                        selectedAnswer == option['value']
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        color: kCoral,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${option['label'] ?? option['text'] ?? option['value']}',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (ready) const Text('Your answers are saved. Submit to finish.'),
            if (screening!['safety_flag'] == true ||
                (meta['code'] == 'PHQ-9' &&
                    number == 9 &&
                    (selectedAnswer ?? 0) > 0))
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'If you might hurt yourself or are in immediate danger, call 911 or go to the nearest emergency department. Reach out to someone you trust or a counselor. You do not need to finish this check-in to get help.',
                ),
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: kCoral,
                  foregroundColor: Colors.white,
                ),
                onPressed:
                    openingScreening || (!ready && selectedAnswer == null)
                    ? null
                    : advanceScreening,
                child: Text(
                  ready || number == questions.length
                      ? 'Submit check-in'
                      : 'Next question',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Scrolls the list down to the newest message
  void scrollToBottom() {
    // Wait one frame so the new message is already drawn
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !scrollController.hasClients) return;
      scrollController.animateTo(
        scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    authSubscription?.cancel();
    acceptSpeechResults = false;
    speech.cancel();
    chatbotService.clearHistory();
    messageController.dispose();
    scrollController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------
  // SCREEN
  // ---------------------------------------------------
  @override
  Widget build(BuildContext context) {
    // The start screen (mascot + greeting) shows until the first message.
    // When the trigger opened the chat, show the start view only until
    // Pat's first question arrives (the typing bubble shows instead).
    final bool isEmpty = messages.isEmpty && !isWaiting && !chatLocked;

    return Scaffold(
      backgroundColor: kBackground,
      body: SafeArea(
        child: Column(
          children: [
            buildHeader(),
            Expanded(child: isEmpty ? buildStartView() : buildMessageList()),
            // Quick replies only show before the chat starts
            if (isEmpty) buildQuickReplies(),
            // Shows only when Pat decided the student should do the check-in
            if (checking) const LinearProgressIndicator(),
            if (checkFailed)
              TextButton(
                onPressed: refreshScreenings,
                child: const Text('Retry check-in status'),
              ),
            if (chatLocked)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text(
                  'For urgent help, call 911 or contact a trusted person. You may leave this screen at any time.',
                  textAlign: TextAlign.center,
                ),
              ),
            buildInputBar(),
            buildDisclaimer(),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------
  // HEADER: back arrow and title
  // ---------------------------------------------------
  Widget buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              Navigator.pop(context);
            },
            child: const Icon(Icons.arrow_back, color: Colors.black, size: 26),
          ),
          const Expanded(
            child: Text(
              'Chat with Pat',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Colors.black,
              ),
            ),
          ),
          // Same width as the arrow so the title stays in the middle
          const SizedBox(width: 26),
        ],
      ),
    );
  }

  // ---------------------------------------------------
  // START VIEW: Pat the star and the greeting
  // ---------------------------------------------------
  Widget buildStartView() {
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
             width: 150,
             height: 150,
              child: Image.asset(
              'assets/images/hug_logo.png',
              fit: BoxFit.contain,
             ),
              ),
            const SizedBox(height: 14),
            const Text(
              'How can I assist\nyou today?',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                height: 1.3,
                color: Colors.black,
              ),
            ),
            // Room so the mascot is not too low when the screen is tall
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------
  // MESSAGE LIST
  // ---------------------------------------------------
  Widget buildMessageList() {
    // One extra row at the end for "Pat is typing..." while waiting
    final int count =
        messages.length +
        (isWaiting ? 1 : 0) +
        ((showScreeningButton || screening != null) ? 1 : 0);

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      itemCount: count,
      itemBuilder: (BuildContext context, int index) {
        if (index >= messages.length + (isWaiting ? 1 : 0)) {
          return screening != null
              ? buildScreeningCard()
              : buildScreeningButton();
        }
        if (index == messages.length) {
          return buildBubble('Pat is typing...', fromUser: false, faded: true);
        }
        final ChatMessage message = messages[index];
        return buildBubble(message.text, fromUser: message.fromUser);
      },
    );
  }

  // One chat bubble (coral on the right for the user, white on the left for Pat)
  Widget buildBubble(
    String text, {
    required bool fromUser,
    bool faded = false,
  }) {
    return Align(
      alignment: fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        // Bubbles never get wider than 75% of the screen
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: fromUser ? kCoral : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(fromUser ? 18 : 4),
            bottomRight: Radius.circular(fromUser ? 4 : 18),
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 14,
            height: 1.35,
            color: fromUser
                ? Colors.white
                : (faded ? Colors.black45 : Colors.black87),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------
  // QUICK REPLIES: small outlined buttons above the text box
  // ---------------------------------------------------
  Widget buildQuickReplies() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            for (final String reply in quickReplies)
              GestureDetector(
                onTap: () {
                  sendMessage(reply);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: kCoral, width: 1),
                  ),
                  child: Text(
                    reply,
                    style: const TextStyle(fontSize: 11, color: kCoral),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------
  // SCREENING BUTTON: shown when Pat decides to offer the questionnaire
  // ---------------------------------------------------
  Widget buildScreeningButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: GestureDetector(
        onTap: openingScreening || isWaiting ? null : openScreening,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: kCoral,
            borderRadius: BorderRadius.circular(24),
          ),
          child: const Text(
            'Start Mental Well-Being Check-In',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------
  // INPUT BAR: mic, text box and send button
  // ---------------------------------------------------
  Widget buildInputBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30),
          boxShadow: const [
            BoxShadow(
              color: Color(0x30000000),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            // Mic button
            IconButton(
              onPressed: isWaiting || chatLocked ? null : toggleListening,
              tooltip: isListening ? 'Stop listening' : 'Start voice input',
              icon: Icon(
                isListening ? Icons.mic : Icons.mic_none,
                color: isListening ? Colors.red : kCoral,
                size: 26,
              ),
            ),

            // Text box
            Expanded(
              child: TextField(
                controller: messageController,
                enabled: !chatLocked && !isWaiting,
                cursorColor: kCoral,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                inputFormatters: [
                  LengthLimitingTextInputFormatter(maxMessageLength),
                ],
                onChanged: (String value) {
                  setState(() {
                    hasText = value.trim().isNotEmpty;
                  });
                },
                onSubmitted: sendMessage,
                style: const TextStyle(fontSize: 14, color: Colors.black87),
                decoration: const InputDecoration(
                  hintText: "Share what's on your mind",
                  hintStyle: TextStyle(fontSize: 14, color: Colors.black45),
                  border: InputBorder.none,
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),

            // Send button (gray when it cannot send)
            GestureDetector(
              onTap: () {
                sendMessage(messageController.text);
              },
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: (hasText && !isWaiting && !chatLocked)
                      ? kCoral
                      : kCoral.withValues(alpha: 0.5),
                ),
                child: const Icon(Icons.send, color: Colors.white, size: 22),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------
  // SMALL NOTE UNDER THE INPUT BAR
  // ---------------------------------------------------
  Widget buildDisclaimer() {
    return const Padding(
      padding: EdgeInsets.fromLTRB(24, 10, 24, 14),
      child: Text(
        "Pat doesn't replace professional care. In a crisis, get immediate support.",
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 9, color: Colors.black54),
      ),
    );
  }
}

// =====================================================
// PAT THE STAR (yellow star with eyes and motion lines)
// =====================================================
class PatMascotPainter extends CustomPainter {
  const PatMascotPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;

    // Center and size of the star
    final Offset center = Offset(w * 0.55, h * 0.56);
    final double outerRadius = w * 0.40;
    final double innerRadius = outerRadius * 0.48;

    // Build the 5-point star shape (slightly tilted like the design)
    final Path star = Path();
    const double tilt = -0.12;
    for (int i = 0; i < 10; i++) {
      // Even points are the tips, odd points are the dents between them
      final double radius = i.isEven ? outerRadius : innerRadius;
      final double angle = -pi / 2 + tilt + i * pi / 5;
      final double x = center.dx + radius * cos(angle);
      final double y = center.dy + radius * sin(angle);
      if (i == 0) {
        star.moveTo(x, y);
      } else {
        star.lineTo(x, y);
      }
    }
    star.close();

    // Fill the star yellow
    final Paint fill = Paint();
    fill.color = kStarYellow;
    fill.style = PaintingStyle.fill;
    canvas.drawPath(star, fill);

    // Same color outline with round joins makes the tips rounded
    final Paint rounded = Paint();
    rounded.color = kStarYellow;
    rounded.style = PaintingStyle.stroke;
    rounded.strokeWidth = w * 0.06;
    rounded.strokeJoin = StrokeJoin.round;
    canvas.drawPath(star, rounded);

    // Eyes: white ovals with a black outline and a black dot
    final Paint eyeWhite = Paint();
    eyeWhite.color = Colors.white;
    eyeWhite.style = PaintingStyle.fill;

    final Paint eyeLine = Paint();
    eyeLine.color = Colors.black;
    eyeLine.style = PaintingStyle.stroke;
    eyeLine.strokeWidth = w * 0.014;

    final Paint pupil = Paint();
    pupil.color = Colors.black;
    pupil.style = PaintingStyle.fill;

    final List<Offset> eyes = [
      Offset(center.dx - w * 0.07, center.dy - h * 0.04),
      Offset(center.dx + w * 0.08, center.dy - h * 0.04),
    ];
    for (final Offset eye in eyes) {
      final Rect oval = Rect.fromCenter(
        center: eye,
        width: w * 0.10,
        height: h * 0.13,
      );
      canvas.drawOval(oval, eyeWhite);
      canvas.drawOval(oval, eyeLine);
      canvas.drawCircle(Offset(eye.dx, eye.dy + h * 0.01), w * 0.022, pupil);
    }

    // Motion lines at the top left (three short slanted lines)
    final Paint motion = Paint();
    motion.color = Colors.black;
    motion.style = PaintingStyle.stroke;
    motion.strokeWidth = w * 0.02;
    motion.strokeCap = StrokeCap.round;

    canvas.drawLine(
      Offset(w * 0.12, h * 0.20),
      Offset(w * 0.16, h * 0.10),
      motion,
    );
    canvas.drawLine(
      Offset(w * 0.18, h * 0.22),
      Offset(w * 0.23, h * 0.12),
      motion,
    );
    canvas.drawLine(
      Offset(w * 0.24, h * 0.25),
      Offset(w * 0.30, h * 0.16),
      motion,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

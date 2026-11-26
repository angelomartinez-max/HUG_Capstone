import 'package:material_ui/material_ui.dart';
import '../constants/colors.dart';
import '../services/screening_service.dart';
import 'chatbot_screen.dart' show PatMascotPainter;

class ScreeningScreen extends StatefulWidget {
  final String? questionnaireId, screeningId, chatSessionId;
  const ScreeningScreen({super.key, this.questionnaireId, this.screeningId,
    this.chatSessionId}) : assert(questionnaireId != null || screeningId != null);
  @override
  State<ScreeningScreen> createState() => _ScreeningScreenState();
}

class _ScreeningScreenState extends State<ScreeningScreen> {
  final _service = ScreeningService();
  String? _id, _error;
  bool _busy = true, _blocked = false, _done = false;
  int _index = 0;
  Map<String, dynamic> _form = {};
  List<Map<String, dynamic>> _questions = [];
  final Map<String, int> _answers = {};
  Map<String, dynamic> _result = {};
  List<Map<String, dynamic>> get _visible => _questions.where((q) =>
    q['is_scored'] == true || q['is_required'] == true ||
    _questions.any((s) => s['is_scored'] == true && (_answers[s['question_id']] ?? 0) > 0)).toList();
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    setState(() { _busy = true; _error = null; });
    try {
      _id ??= widget.screeningId;
      if (_id == null) {
        final r = await _service.startScreening(questionnaireId: widget.questionnaireId!, chatSessionId: widget.chatSessionId);
        _id = r['screening_id'] as String;
      }
      final r = await _service.resumeScreening(_id!);
      if (!mounted) return;
      setState(() {
        _form = Map<String, dynamic>.from(r['questionnaire'] as Map);
        _questions = List<Map<String, dynamic>>.from(r['questions'] as List)..sort((a,b) => (a['question_number'] as int).compareTo(b['question_number'] as int));
        _answers.clear();
        for (final a in r['answers'] as List) { _answers[a['question_id'] as String] = a['answer_value'] as int; }
        final i = _visible.indexWhere((q) => q['question_number'] == r['next_question']);
        _index = i >= 0 ? i : 0;
        _blocked = r['safety_flag'] == true;
        _busy = false;
      });
      if (_blocked) await _safety();
    } catch (_) { if (mounted) setState(() { _busy = false; _error = 'Unable to load screening. Please retry.'; }); }
  }
  void _message(String s) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  Future<void> _save(String id, int value) async {
    if (_busy || _blocked) return;
    setState(() => _busy = true);
    try {
      final r = await _service.saveAnswer(screeningId: _id!, questionId: id, answerValue: value);
      if (!mounted) return;
      setState(() {
        _answers[id] = value;
        final visibleIds = _visible.map((q) => q['question_id']).toSet();
        _answers.removeWhere((k,v) => !visibleIds.contains(k));
        _blocked = r['safety_flag'] == true || r['requires_safety_check'] == true;
        _busy = false;
      });
      if (_blocked) await _safety();
    } catch (_) { if (mounted) { setState(() { _busy = false; _error = 'Answer could not be confirmed. Reload to check saved progress.'; }); } }
  }
  Future<void> _safety() async {
    final safe = await showDialog<bool>(context: context, barrierDismissible: false, builder: (ctx) => AlertDialog(
      title: const Text('Your safety matters'),
      content: const SingleChildScrollView(child: Text('Thank you for sharing. Are you thinking about hurting yourself right now, or unsure whether you can stay safe? If you are in immediate danger, call 911 or go to the nearest emergency department. Stay with someone you trust if possible. You can also contact OCPS or a mental health professional.')),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('I need help / unsure / prefer not to answer')), TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('I feel safe right now'))]));
    if (!mounted) return;
    if (safe == true) { setState(() => _blocked = false); } else { await _exit('paused'); }
  }
  Future<void> _exit(String status) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (_id != null && !_done) {
        if (status == 'declined') { await _service.declineScreening(_id!); }
        else { await _service.pauseScreening(_id!); }
      }
      if (mounted) Navigator.pop(context, _done ? 'completed' : status);
    } catch (_) { if (mounted) { setState(() => _busy = false); _message('Unable to confirm status. Saved answers remain available.'); } }
  }
  Future<void> _next() async {
    if (_busy || _blocked) return;
    if (_index < _visible.length - 1) { setState(() => _index++); return; }
    final missing = _visible.indexWhere((q) => !_answers.containsKey(q['question_id']));
    if (missing >= 0) { setState(() => _index = missing); return; }
    final yes = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('Submit screening?'), content: const Text('Submitted answers cannot be edited.'), actions: [TextButton(onPressed: () => Navigator.pop(ctx,false), child: const Text('Review')), TextButton(onPressed: () => Navigator.pop(ctx,true), child: const Text('Submit'))]));
    if (!mounted || yes != true) return;
    setState(() => _busy = true);
    try {
      final r = await _service.completeScreening(_id!);
      if (!mounted) return;
      setState(() { _result = Map<String,dynamic>.from(r['result'] as Map); _done = true; _busy = false; });
    } catch (_) { if (mounted) { setState(() => _busy = false); _message('Submission not confirmed. Please retry.'); } }
  }
  Future<void> _decline() async {
    final yes = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('Stop screening?'), content: const Text('Participation is voluntary. Previously saved answers remain stored.'), actions: [TextButton(onPressed: () => Navigator.pop(ctx,false), child: const Text('Cancel')), TextButton(onPressed: () => Navigator.pop(ctx,true), child: const Text('Stop screening'))]));
    if (mounted && yes == true) await _exit('declined');
  }
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, result) { if (!didPop) _exit('paused'); },
    child: Scaffold(backgroundColor: const Color(0xFFF4F4F4), appBar: AppBar(backgroundColor: const Color(0xFFF4F4F4), title: const Text('Mental Health Check-in'), leading: IconButton(onPressed: _busy ? null : () => _exit('paused'), icon: const Icon(Icons.arrow_back)), actions: [if (!_done) IconButton(onPressed: _busy ? null : _decline, icon: const Icon(Icons.close))]), body: SafeArea(child: _body())));
  Widget _body() {
    if (_error != null) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Text(_error!), TextButton(onPressed: _busy ? null : _load, child: const Text('Retry'))]));
    if (_done) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [const Text('Check-in Completed', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)), Text('${_result['total_score']} / ${_form['max_score']}'), const Text('This score is not a diagnosis.'), TextButton(onPressed: () => _exit('completed'), child: const Text('Back to Pat'))]));
    final qs = _visible;
    if (qs.isEmpty) return Center(child: _busy ? const CircularProgressIndicator(color: kCoral) : const Text('No questions available.'));
    final q = qs[_index];
    final id = q['question_id'] as String;
    final options = List<Map<String,dynamic>>.from(q['answer_options'] as List);
    return ListView(padding: const EdgeInsets.all(20), children: [
      const Center(child: SizedBox(width: 90, height: 90, child: CustomPaint(painter: PatMascotPainter()))),
      const Text('How have you been feeling lately?', textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      const SizedBox(height: 20), Text('${_form['code']} — Question ${_index+1} of ${qs.length}'),
      LinearProgressIndicator(value: qs.where((x) => _answers.containsKey(x['question_id'])).length / qs.length, color: kCoral),
      const SizedBox(height: 20),
      Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (q['is_scored'] == true) Text(_form['instructions'] as String? ?? ''), const SizedBox(height: 12), Text(q['question_text'] as String, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), const SizedBox(height: 16),
        for (final o in options) Padding(padding: const EdgeInsets.only(bottom: 8), child: OutlinedButton(style: OutlinedButton.styleFrom(foregroundColor: Colors.black87, backgroundColor: _answers[id] == o['value'] ? kCoral.withValues(alpha: 0.12) : Colors.white, side: BorderSide(color: _answers[id] == o['value'] ? kCoral : Colors.black26)), onPressed: _busy || _blocked ? null : () => _save(id,o['value'] as int), child: Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Row(children: [Icon(_answers[id] == o['value'] ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: kCoral), const SizedBox(width: 10), Expanded(child: Text(o['label'] as String))])))),
      ])),
      const SizedBox(height: 12), if (_busy) const Center(child: Text('Saving...')) else if (_answers.containsKey(id)) const Center(child: Text('Answer saved', style: TextStyle(color: Colors.green))),
      if (_blocked) TextButton(onPressed: _busy ? null : _safety, child: const Text('Review safety support')),
      Row(children: [if (_index > 0) Expanded(child: TextButton(onPressed: _busy || _blocked ? null : () => setState(() => _index--), child: const Text('Previous'))), Expanded(child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: kCoral, foregroundColor: Colors.white), onPressed: _busy || _blocked || !_answers.containsKey(id) ? null : _next, child: Text(_index == qs.length-1 ? 'Submit screening' : 'Next question')))]),
      TextButton(onPressed: _busy ? null : () => _exit('paused'), child: const Text('Save and continue later', style: TextStyle(color: kCoral))),
      const Text('Participation is voluntary. This screening is not a medical diagnosis.', textAlign: TextAlign.center),
    ]);
  }
}

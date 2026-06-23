import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import '../services/supabase_service.dart';
import '../services/reminder_service.dart';
import '../services/cache_service.dart';
import '../utils/theme_provider.dart';
import '../widgets/common.dart';

// ─── Reactive State Model ────────────────────────────────────────────────────
class _ExamRoutineModel extends ChangeNotifier {
  List<Map<String, dynamic>> exams = [];
  bool initialLoading = true;
  bool isOffline = false;
  int semester;
  String search = '';
  bool examRemindersOn = false;
  bool remindersLoaded = false;
  StreamSubscription<List<Map<String, dynamic>>>? _examsSub;
  Completer<void>? _refreshCompleter;
  Timer? _autoRefreshTimer;

  _ExamRoutineModel(this.semester);

  static const examTypes = ['Mid', 'Final', 'Class Test'];

  static String normalizeType(String? type) {
    if (type == null) return 'Mid';
    final lower = type.toLowerCase().trim();
    if (lower.contains('mid')) return 'Mid';
    if (lower.contains('final')) return 'Final';
    if (lower.contains('class') || lower.contains('test') || lower.contains('ct')) return 'Class Test';
    return type;
  }

  List<Map<String, dynamic>> get filtered {
    if (search.trim().isEmpty) return exams;
    final q = search.toLowerCase();
    return exams.where((e) {
      final s = (e['subject'] ?? '').toString().toLowerCase();
      final sc = (e['subject_code'] ?? '').toString().toLowerCase();
      final t = (e['teacher'] ?? '').toString().toLowerCase();
      final r = (e['room'] ?? '').toString().toLowerCase();
      final et = (e['exam_type'] ?? '').toString().toLowerCase();
      return s.contains(q) || sc.contains(q) || t.contains(q) || r.contains(q) || et.contains(q);
    }).toList();
  }

  Map<String, List<Map<String, dynamic>>> get byType {
    final map = <String, List<Map<String, dynamic>>>{};
    for (final t in examTypes) {
      map[t] = filtered.where((e) => normalizeType(e['exam_type']?.toString()) == t).toList()
        ..sort((a, b) => (a['exam_date'] ?? '').toString().compareTo((b['exam_date'] ?? '').toString()));
    }
    return map;
  }

  Future<void> init() async {
    // ── Cache-first: show cached data immediately ──
    final cacheKey = CacheService.examsKeySemester(semester);
    if (!CacheService.isStale(cacheKey)) {
      final cached = CacheService.loadList(cacheKey);
      if (cached != null && cached.isNotEmpty) {
        exams = cached;
        initialLoading = false;
        notifyListeners();
      }
    }

    remindersLoaded = true;
    examRemindersOn = await ReminderService.areExamRemindersEnabled();
    notifyListeners();
    _subscribe();
    _startAutoRefresh();
  }

  void _subscribe() {
    _examsSub?.cancel();
    _examsSub = SupabaseService.getExamsStream(semester: semester == 0 ? null : semester).listen((data) {
      exams = data;
      initialLoading = false;
      isOffline = false;
      final cacheKey = CacheService.examsKeySemester(semester);
      CacheService.saveList(cacheKey, data);
      notifyListeners();
      if (_refreshCompleter != null && !_refreshCompleter!.isCompleted) {
        _refreshCompleter!.complete();
        _refreshCompleter = null;
      }
    }, onError: (e) {
      if (exams.isNotEmpty) {
        isOffline = true;
      } else {
        initialLoading = false;
      }
      notifyListeners();
      if (_refreshCompleter != null && !_refreshCompleter!.isCompleted) {
        _refreshCompleter!.completeError(e);
        _refreshCompleter = null;
      }
    });
  }

  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 20), (_) => _silentRefresh());
  }

  Future<void> _silentRefresh() async {
    try {
      final data = await SupabaseService.getExams(semester: semester == 0 ? null : semester);
      exams = data;
      initialLoading = false;
      isOffline = false;
      final cacheKey = CacheService.examsKeySemester(semester);
      CacheService.saveList(cacheKey, data);
      notifyListeners();
    } catch (_) {
      if (exams.isNotEmpty) {
        isOffline = true;
        notifyListeners();
      }
    }
  }

  Future<void> refresh() async {
    final completer = Completer<void>();
    _refreshCompleter = completer;
    _subscribe();
    await completer.future.timeout(const Duration(seconds: 15), onTimeout: () {
      if (!completer.isCompleted) completer.complete();
    });
  }

  void setSearch(String v) {
    search = v;
    notifyListeners();
  }

  void clearSearch() {
    search = '';
    notifyListeners();
  }

  Future<void> toggleExamReminders() async {
    examRemindersOn = !examRemindersOn;
    notifyListeners();
    await ReminderService.setExamRemindersEnabled(examRemindersOn);
    if (examRemindersOn) {
      await ReminderService.scheduleExamReminders(exams);
    } else {
      await ReminderService.cancelExamReminders();
    }
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _examsSub?.cancel();
    super.dispose();
  }
}

// ─── Screen ──────────────────────────────────────────────────────────────────
class ExamRoutineScreen extends StatefulWidget {
  final bool isAdmin;
  final int semester;
  final VoidCallback? onBack;
  const ExamRoutineScreen({super.key, required this.isAdmin, required this.semester, this.onBack});

  @override
  State<ExamRoutineScreen> createState() => _ExamRoutineScreenState();
}

class _ExamRoutineScreenState extends State<ExamRoutineScreen> {
  late final _model = _ExamRoutineModel(widget.semester);

  @override
  void initState() {
    super.initState();
    _model.init();
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  void _showForm([Map<String, dynamic>? exam]) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.colorsOf.bg2,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _ExamForm(
        exam: exam,
        semester: _model.semester == 0 ? 1 : _model.semester,
        onSaved: () => Navigator.pop(context),
      ),
    );
  }

  Future<void> _delete(String id) async {
    final c = context.colorsOf;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: c.bg2,
        title: Text('Delete Exam', style: TextStyle(color: c.white)),
        content: Text('This cannot be undone.', style: TextStyle(color: c.muted)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text('Delete', style: TextStyle(color: c.danger))),
        ],
      ),
    );
    if (ok != true) return;
    await SupabaseService.deleteExam(id);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: c.white),
          tooltip: 'Back',
          onPressed: widget.onBack ?? () => Navigator.pop(context),
        ),
        title: Text('Exam Routine', style: TextStyle(fontWeight: FontWeight.w700, color: c.white)),
        actions: [
          // ── Semester picker removed ──
          if (widget.isAdmin)
            IconButton(icon: Icon(Icons.add, color: c.accent), tooltip: 'Add Exam', onPressed: () => _showForm()),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListenableBuilder(
        listenable: _model,
        builder: (ctx, _) {
          final m = _model;
          return RefreshIndicator(
            onRefresh: m.refresh,
            color: c.accent,
            backgroundColor: c.bg2,
            child: m.initialLoading
                ? ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: 4,
                    itemBuilder: (_, __) => const Padding(padding: EdgeInsets.only(bottom: 12), child: ShimmerBox(height: 100)),
                  )
                : CustomScrollView(
                    slivers: [
                      // Reminder card
                      if (m.remindersLoaded)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: c.bg2,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: c.border),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        width: 28, height: 28,
                                        decoration: BoxDecoration(color: c.warn.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                                        child: Icon(Icons.notifications_active, size: 16, color: c.warn),
                                      ),
                                      const SizedBox(width: 10),
                                      Text('Reminders', style: TextStyle(color: c.white, fontWeight: FontWeight.w700, fontSize: 15)),
                                      const Spacer(),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(color: c.warn.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                                        child: Text('24h before', style: TextStyle(color: c.warn, fontSize: 10, fontWeight: FontWeight.w600)),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 14),
                                  Row(
                                    children: [
                                      Icon(Icons.quiz_outlined, size: 16, color: c.warn),
                                      const SizedBox(width: 8),
                                      Text('Exam reminder', style: TextStyle(color: c.white, fontSize: 13, fontWeight: FontWeight.w600)),
                                      const Spacer(),
                                      SizedBox(
                                        height: 28,
                                        child: Switch(
                                          value: m.examRemindersOn,
                                          onChanged: (_) => m.toggleExamReminders(),
                                          activeTrackColor: c.warn,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      // Search bar
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),                            child: Container(
                            decoration: BoxDecoration(color: const Color(0xFF08121E), borderRadius: BorderRadius.circular(14), border: Border.all(color: c.border)),
                            child: TextField(
                              onChanged: m.setSearch,
                              style: TextStyle(color: c.text, fontSize: 14),
                              decoration: InputDecoration(
                                hintText: 'Search exams by subject, teacher, room...',
                                hintStyle: TextStyle(color: c.muted, fontSize: 13),
                                prefixIcon: Icon(Icons.search, color: c.muted, size: 20),
                                suffixIcon: m.search.isNotEmpty
                                    ? IconButton(icon: Icon(Icons.close, color: c.muted, size: 18), tooltip: 'Clear Search', onPressed: m.clearSearch)
                                    : null,
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Content
                      if (m.filtered.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.search_off, size: 40, color: c.muted.withValues(alpha: 0.5)),
                                const SizedBox(height: 12),
                                Text(m.search.isNotEmpty ? 'No exams match your search' : 'No exams scheduled', style: TextStyle(color: c.muted, fontSize: 14)),
                                if (m.search.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  TextButton(onPressed: m.clearSearch, child: Text('Clear search', style: TextStyle(color: c.accent, fontSize: 13))),
                                ],
                              ],
                            ),
                          ),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.all(16),
                          sliver: SliverList(
                            delegate: SliverChildListDelegate(
                              _ExamRoutineModel.examTypes.asMap().entries.map((entry) {
                                final i = entry.key;
                                final type = entry.value;
                                final exams = m.byType[type] ?? [];
                                return _ExamTypeSection(
                                  type: type,
                                  exams: exams,
                                  isAdmin: widget.isAdmin,
                                  onEdit: widget.isAdmin ? (e) => _showForm(e) : null,
                                  onDelete: (id) => _delete(id),
                                ).animate().fadeIn(duration: 400.ms, delay: Duration(milliseconds: (i * 120).clamp(0, 500)), curve: Curves.easeOut)
                                    .slideY(begin: 0.05, end: 0, duration: 400.ms, delay: Duration(milliseconds: (i * 120).clamp(0, 500)), curve: Curves.easeOut);
                              }).toList(),
                            ),
                          ),
                        ),
                    ],
                  ),
          );
        },
      ),
    ),
    ],
    ));
  }
}

class _ExamTypeSection extends StatelessWidget {
  final String type;
  final List<Map<String, dynamic>> exams;
  final bool isAdmin;
  final Function(Map<String, dynamic>)? onEdit;
  final Function(String) onDelete;

  const _ExamTypeSection({
    required this.type,
    required this.exams,
    required this.isAdmin,
    this.onEdit,
    required this.onDelete,
  });

  Color _typeColor(ThemeColors c) {
    switch (type) {
      case 'Mid': return c.warn;
      case 'Final': return c.accent;
      case 'Class Test': return c.accent3;
      default: return c.muted;
    }
  }

  IconData get _typeIcon {
    switch (type) {
      case 'Mid': return Icons.edit_note;
      case 'Final': return Icons.school;
      case 'Class Test': return Icons.quiz;
      default: return Icons.assignment;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final typeClr = _typeColor(c);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: typeClr.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: typeClr.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_typeIcon, size: 14, color: typeClr),
                    const SizedBox(width: 6),
                    Text(type, style: TextStyle(color: typeClr, fontWeight: FontWeight.w700, fontSize: 13)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AppBadge(label: '${exams.length}', color: typeClr),
            ],
          ),
          const SizedBox(height: 8),
          if (exams.isEmpty)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: c.bg2, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.border)),
              child: Row(children: [
                Icon(Icons.event_busy, color: c.muted, size: 16),
                const SizedBox(width: 8),
                Text('No $type exams scheduled', style: TextStyle(color: c.muted, fontSize: 13)),
              ]),
            )
          else
            ...exams.map((exam) {
              final dateStr = exam['exam_date'] != null
                  ? DateFormat('MMM d, yyyy').format(DateTime.tryParse(exam['exam_date'].toString()) ?? DateTime.now())
                  : 'TBD';
              final startTime = _formatTime(exam['start_time']);
              final endTime = _formatTime(exam['end_time']);
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: c.bg2,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: typeClr.withValues(alpha: 0.1)),
                ),
                child: Row(
                  children: [
                    Container(width: 3, height: 44, decoration: BoxDecoration(color: typeClr, borderRadius: BorderRadius.circular(2))),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(exam['subject'] ?? '', style: TextStyle(color: c.white, fontWeight: FontWeight.w600, fontSize: 14)),
                          const SizedBox(height: 2),
                          Text('$dateStr  $startTime - $endTime', style: TextStyle(color: c.muted, fontSize: 11)),
                          const SizedBox(height: 2),
                          Wrap(
                            spacing: 8,
                            children: [
                              if (exam['subject_code'] != null && exam['subject_code'].toString().isNotEmpty)
                                Text(exam['subject_code'], style: TextStyle(color: typeClr, fontSize: 11, fontWeight: FontWeight.w600)),
                              if (exam['room'] != null && exam['room'].toString().isNotEmpty)
                                Text('Room: ${exam['room']}', style: TextStyle(color: c.muted, fontSize: 11)),
                              if (exam['teacher'] != null && exam['teacher'].toString().isNotEmpty)
                                Text(exam['teacher'], style: TextStyle(color: c.muted, fontSize: 11)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (isAdmin) ...[
                      if (onEdit != null)
                        GestureDetector(
                          onTap: () => onEdit!(exam),
                          child: Padding(padding: const EdgeInsets.only(right: 8), child: Icon(Icons.edit_outlined, size: 16, color: c.muted)),
                        ),
                      GestureDetector(
                        onTap: () => onDelete(exam['id'].toString()),
                        child: Icon(Icons.delete_outline, size: 16, color: c.danger),
                      ),
                    ],
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  String _formatTime(String? time) {
    if (time == null) return '';
    try {
      final parts = time.split(':');
      final h = int.parse(parts[0]);
      final m = parts.length > 1 ? parts[1].substring(0, 2) : '00';
      final period = h >= 12 ? 'PM' : 'AM';
      final h12 = h > 12 ? h - 12 : (h == 0 ? 12 : h);
      return '$h12:$m $period';
    } catch (_) {
      return time;
    }
  }
}

// -- Exam Form ----------------------------------------------------------------
class _ExamForm extends StatefulWidget {
  final Map<String, dynamic>? exam;
  final int semester;
  final VoidCallback onSaved;
  const _ExamForm({this.exam, required this.semester, required this.onSaved});

  @override
  State<_ExamForm> createState() => _ExamFormState();
}

class _ExamFormState extends State<_ExamForm> {
  final _formKey = GlobalKey<FormState>();
  late final _subjectCtrl = TextEditingController(text: widget.exam?['subject'] ?? '');
  late final _subjectCodeCtrl = TextEditingController(text: widget.exam?['subject_code'] ?? '');
  late final _roomCtrl = TextEditingController(text: widget.exam?['room'] ?? '');
  late final _teacherCtrl = TextEditingController(text: widget.exam?['teacher'] ?? '');
  String _examType = 'Mid';
  DateTime _examDate = DateTime.now();
  TimeOfDay _startTime = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 11, minute: 0);
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _examType = widget.exam?['exam_type'] ?? 'Mid';
    if (widget.exam?['exam_date'] != null) {
      _examDate = DateTime.tryParse(widget.exam!['exam_date'].toString()) ?? DateTime.now();
    }
    if (widget.exam?['start_time'] != null) {
      _startTime = _parseTime(widget.exam!['start_time'].toString());
    }
    if (widget.exam?['end_time'] != null) {
      _endTime = _parseTime(widget.exam!['end_time'].toString());
    }
  }

  TimeOfDay _parseTime(String time) {
    try {
      final parts = time.split(':');
      return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1].substring(0, 2)));
    } catch (_) {
      return const TimeOfDay(hour: 9, minute: 0);
    }
  }

  String _formatTimeOfDay(TimeOfDay t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m:00';
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _examDate,
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
      builder: (ctx, child) => Theme(
        data: buildDatePickerTheme(ctx, Theme.of(ctx)),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _examDate = picked);
  }

  Future<void> _pickTime(bool isStart) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _startTime : _endTime,
      builder: (ctx, child) => Theme(
        data: buildDatePickerTheme(ctx, Theme.of(ctx)),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() { if (isStart) { _startTime = picked; } else { _endTime = picked; } });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final data = {
        if (widget.exam != null) 'id': widget.exam!['id'],
        'exam_type': _examType,
        'subject': _subjectCtrl.text.trim(),
        'subject_code': _subjectCodeCtrl.text.trim(),
        'exam_date': _examDate.toIso8601String().substring(0, 10),
        'start_time': _formatTimeOfDay(_startTime),
        'end_time': _formatTimeOfDay(_endTime),
        'room': _roomCtrl.text.trim().isEmpty ? null : _roomCtrl.text.trim(),
        'teacher': _teacherCtrl.text.trim().isEmpty ? null : _teacherCtrl.text.trim(),
        'semester': widget.semester,
      };
      await SupabaseService.upsertExam(data);
      widget.onSaved();
    } catch (e) {
      debugPrint('[ExamForm] Save error: $e');
      if (mounted) showAppSnackbar(context, friendlyError(e), isError: true);
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.exam != null ? 'Edit Exam' : 'Add Exam', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.white)),
              const SizedBox(height: 20),
              Text('EXAM TYPE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c.muted)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: _ExamRoutineModel.examTypes.map((t) {
                final sel = _examType == t;
                return GestureDetector(
                  onTap: () => setState(() => _examType = t),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: sel ? c.accent.withValues(alpha: 0.15) : c.bg3,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: sel ? c.accent : c.border),
                    ),
                    child: Text(t, style: TextStyle(color: sel ? c.accent : c.muted, fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                );
              }).toList()),
              const SizedBox(height: 16),
              Row(children: [Expanded(
                child: GestureDetector(
                  onTap: _pickDate,
                  child: _DateTimeField(label: 'DATE', value: DateFormat('MMM d, yyyy').format(_examDate), icon: Icons.calendar_today_outlined),
                ),
              )]),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: GestureDetector(onTap: () => _pickTime(true), child: _DateTimeField(label: 'START TIME', value: _startTime.format(context), icon: Icons.access_time))),
                const SizedBox(width: 12),
                Expanded(child: GestureDetector(onTap: () => _pickTime(false), child: _DateTimeField(label: 'END TIME', value: _endTime.format(context), icon: Icons.access_time))),
              ]),
              const SizedBox(height: 14),
              AppTextField(label: 'Subject', controller: _subjectCtrl, validator: (v) => v == null || v.isEmpty ? 'Required' : null),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: AppTextField(label: 'Subject Code', hint: 'CSE-2301', controller: _subjectCodeCtrl)),
                const SizedBox(width: 12),
                Expanded(child: AppTextField(label: 'Room', controller: _roomCtrl)),
              ]),
              const SizedBox(height: 14),
              AppTextField(label: 'Teacher', controller: _teacherCtrl, prefixIcon: Icons.person_outline),
              const SizedBox(height: 24),
              PrimaryButton(label: 'Save Exam', onPressed: _save, loading: _saving, icon: Icons.save_outlined),
            ],
          ),
        ),
      ),
    );
  }
}

class _DateTimeField extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const _DateTimeField({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c.muted)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(color: c.bg3, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.border)),
          child: Row(children: [Icon(icon, size: 16, color: c.muted), const SizedBox(width: 8), Text(value, style: TextStyle(color: c.text, fontSize: 13))]),
        ),
      ],
    );
  }
}

import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/reminder_service.dart';
import '../services/routine_import_service.dart';
import '../services/routine_service.dart';
import '../services/supabase_service.dart';
import '../services/cache_service.dart';
import '../utils/file_io.dart';
import '../utils/theme_provider.dart';
import '../utils/responsive.dart';
import '../widgets/common.dart';
import 'exam_routine_screen.dart';

class RoutineScreen extends StatefulWidget {
  final bool isAdmin;
  final int initialSemester;

  const RoutineScreen({
    super.key,
    required this.isAdmin,
    this.initialSemester = 1,
  });

  @override
  State<RoutineScreen> createState() => _RoutineScreenState();
}

class _RoutineScreenState extends State<RoutineScreen> {
  List<ClassRoutine> _routine = [];
  bool _initialLoading = true;
  bool _isOffline = false;
  late int _semester;
  bool _showExam = false;
  String _search = '';
  bool _searchVisible = false;
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  bool _reminderExpanded = false;
  bool _classRemindersOn = false;
  bool _remindersLoaded = false;
  int _classReminderMinutes = 15;
  static const _minuteOptions = [5, 10, 15];
  static const _cleanupPrefsKey = 'routine_keep_3rd_only_v1';

  List<Map<String, dynamic>> _offDays = [];

  StreamSubscription<List<ClassRoutine>>? _routineSub;
  Completer<void>? _refreshCompleter;
  Timer? _autoRefreshTimer;

  @override
  void initState() {
    super.initState();
    _semester = widget.initialSemester == RoutineService.allSemesters
        ? RoutineService.allSemesters
        : RoutineService.parseSemester(widget.initialSemester);
    _loadReminderPrefs();
    if (widget.isAdmin) _cleanupNonThirdSemesterOnce();
    // ── Cache-first: show cached data immediately ──
    final cacheKey = CacheService.routineKey(_semester);
    if (!CacheService.isStale(cacheKey)) {
      final cached = CacheService.loadList(cacheKey);
      if (cached != null && cached.isNotEmpty) {
        _routine = cached.map((row) => ClassRoutine.fromRow(row)).toList();
        _initialLoading = false;
      }
    }
    _subscribe();
    _reload();
    _loadOffDays();
    _startAutoRefresh();
  }

  /// One-time cleanup requested: keep only 3rd-semester routines in Supabase.
  Future<void> _cleanupNonThirdSemesterOnce() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_cleanupPrefsKey) == true) return;

      final deleted = await RoutineService.deleteExceptSemester(
        RoutineService.defaultSemester,
      );
      await prefs.setBool(_cleanupPrefsKey, true);

      if (mounted && deleted > 0) {
        showAppSnackbar(
          context,
          'Removed $deleted non-3rd-semester routine entries',
          isError: false,
        );
        await _reload();
      }
    } catch (e) {
      debugPrint('[Routine] cleanup failed: $e');
    }
  }

  int get _importSemester => RoutineService.importTargetSemester(_semester);

  bool get _showAllSemesters => RoutineService.isAllSemesters(_semester);

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _routineSub?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  List<ClassRoutine> get _visibleRoutine =>
      RoutineService.search(_routine, _search);

  Map<String, List<ClassRoutine>> get _byDay =>
      RoutineService.groupByDay(_visibleRoutine);

  Future<void> _reload() async {
    try {
      final data = await RoutineService.fetch(_semester);
      if (mounted) {
        setState(() {
          _routine = data;
          _initialLoading = false;
          _isOffline = false;
        });
      }
      final cacheKey = CacheService.routineKey(_semester);
      CacheService.saveList(cacheKey, data.map((s) => s.toRow()).toList());
    } catch (_) {
      if (mounted && _routine.isNotEmpty) {
        setState(() => _isOffline = true);
      }
    }
  }

  void _subscribe() {
    _routineSub?.cancel();
    _routineSub = RoutineService.watch(_semester).listen(
      (data) {
        if (!mounted) return;
        setState(() {
          _routine = data;
          _initialLoading = false;
          _isOffline = false;
        });
        final cacheKey = CacheService.routineKey(_semester);
        CacheService.saveList(cacheKey, data.map((s) => s.toRow()).toList());
        _refreshReminders();
        if (_refreshCompleter != null && !_refreshCompleter!.isCompleted) {
          _refreshCompleter!.complete();
          _refreshCompleter = null;
          showAppSnackbar(context, 'Refreshed \u2713', isError: false);
        }
      },
      onError: (e) {
        if (!mounted) return;
        setState(() {
          _initialLoading = false;
          if (_routine.isNotEmpty) _isOffline = true;
        });
        if (_refreshCompleter != null && !_refreshCompleter!.isCompleted) {
          _refreshCompleter!.completeError(e);
          _refreshCompleter = null;
        }
        showAppSnackbar(context, friendlyError(e), isError: true);
      },
    );
  }

  Future<void> _refresh() async {
    final completer = Completer<void>();
    _refreshCompleter = completer;
    _subscribe();
    await _reload();
    await completer.future.timeout(const Duration(seconds: 15), onTimeout: () {});
  }

  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) _reload();
    });
  }


  Future<void> _loadOffDays() async {
    try {
      final data = await SupabaseService.getFutureOffDays();
      if (mounted) setState(() => _offDays = data);
    } catch (_) {}
  }

  Future<void> _loadReminderPrefs() async {
    final classEn = await ReminderService.areClassRemindersEnabled();
    final minutes = await ReminderService.getClassReminderMinutes();
    if (mounted) {
      setState(() {
        _classRemindersOn = classEn;
        _classReminderMinutes = minutes;
        _remindersLoaded = true;
      });
    }
  }

  Future<void> _toggleClassReminders(bool enabled) async {
    setState(() => _classRemindersOn = enabled);
    await ReminderService.setClassRemindersEnabled(enabled);
    if (enabled) {
      await ReminderService.scheduleClassReminders(
        _routine.map((slot) => slot.toReminderMap()).toList(),
      );
      if (mounted) showAppSnackbar(context, 'Class reminders turned on');
    } else {
      await ReminderService.cancelClassReminders();
      if (mounted) showAppSnackbar(context, 'Class reminders turned off');
    }
  }

  Future<void> _changeClassReminderMinutes(int minutes) async {
    setState(() => _classReminderMinutes = minutes);
    await ReminderService.setClassReminderMinutes(minutes);
    if (_classRemindersOn) {
      await ReminderService.scheduleClassReminders(
        _routine.map((slot) => slot.toReminderMap()).toList(),
      );
      if (mounted) showAppSnackbar(context, 'Reminder set to $minutes min before');
    }
  }

  void _refreshReminders() {
    if (!_classRemindersOn) return;
    ReminderService.scheduleClassReminders(
      _routine.map((slot) => slot.toReminderMap()).toList(),
    ).catchError((e) {
      debugPrint('[Reminder] Auto-reschedule failed: $e');
    });
  }

  Future<void> _importRoutine() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'docx'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      Uint8List? fileBytes = file.bytes;
      if (fileBytes == null && file.path != null) {
        fileBytes = await readFileBytes(file.path!);
      }
      if (fileBytes == null || fileBytes.isEmpty) {
        if (mounted) {
          showAppSnackbar(context, 'Could not read file bytes', isError: true);
        }
        return;
      }

      if (mounted) showAppSnackbar(context, 'Parsing ${file.name}...');

      final parsed = await RoutineImportService.parseFile(file.name, fileBytes);
      if (parsed.error != null) {
        if (mounted) {
          showAppSnackbar(context, 'Parse error: ${parsed.error}', isError: true);
        }
        return;
      }
      if (parsed.slots.isEmpty) {
        if (mounted) {
          showAppSnackbar(context, 'No routine data found in file', isError: true);
        }
        return;
      }

      if (mounted) _showImportPreview(parsed);
    } catch (e, st) {
      debugPrint('IMPORT ERROR: $e\n$st');
      if (mounted) showAppSnackbar(context, 'Import failed: $e', isError: true);
    }
  }

  void _showImportPreview(RoutineImportResult parsed) {
    final c = context.colorsOf;
    final byDay = <String, List<RoutineSlot>>{};
    for (final slot in parsed.slots) {
      byDay.putIfAbsent(slot.day, () => []).add(slot);
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.bg2,
        title: Row(
          children: [
            Icon(Icons.upload_file, color: c.accent, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Import Routine',
                style: TextStyle(
                  color: c.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: MediaQuery.of(ctx).size.height * 0.6,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${parsed.slots.length} classes for ${SupabaseService.semesterFromInt(_importSemester)} Semester',
                style: TextStyle(color: c.muted, fontSize: 12),
              ),
              if (parsed.warnings.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: c.warn.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: parsed.warnings
                        .take(5)
                        .map((w) => Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.warning_amber, size: 12, color: c.warn),
                          const SizedBox(width: 4),
                          Flexible(child: Text(w, style: TextStyle(color: c.warn, fontSize: 11))),
                        ],
                      ))
                        .toList(),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  children: byDay.entries.map((entry) {
                    final dayLabel = RoutineService.dayLabels[entry.key] ?? entry.key;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Text(
                            dayLabel,
                            style: TextStyle(
                              color: c.accent,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        ...entry.value.map((slot) {
                          final timeStr = slot.periodIndex < RoutineService.periodTimes.length
                              ? RoutineService.periodTimes[slot.periodIndex]
                              : 'Period ${slot.periodIndex + 1}';
                          return Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: c.bg3,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 90,
                                  child: Text(timeStr, style: TextStyle(color: c.muted, fontSize: 11)),
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        slot.subject,
                                        style: TextStyle(
                                          color: c.white,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Text(
                                        [
                                          slot.teacher,
                                          if (slot.room.isNotEmpty) 'Room ${slot.room}',
                                        ].where((s) => s.isNotEmpty).join(' · '),
                                        style: TextStyle(color: c.muted, fontSize: 11),
                                      ),
                                    ],
                                  ),
                                ),
                                if (slot.subjectCode.isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: c.accent.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      slot.subjectCode,
                                      style: TextStyle(color: c.accent, fontSize: 10),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        }),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: c.muted)),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.upload, size: 16),
            label: const Text('Import'),
            style: ElevatedButton.styleFrom(
              backgroundColor: c.accent,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await _doImport(parsed.slots);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _doImport(List<RoutineSlot> slots) async {
    try {
      final data = slots.map((s) => s.toMap(_importSemester)).toList();
      final count = await RoutineService.importBulk(data, _importSemester);
      if (mounted) {
        showAppSnackbar(context, 'Imported $count classes ✓');
        await _reload();
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString().replaceFirst('Exception: ', '');
        showAppSnackbar(context, msg, isError: true);
      }
    }
  }

  void _showForm([ClassRoutine? entry]) {
    final c = context.colorsOf;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: c.bg2,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _RoutineForm(
        entry: entry,
        semester: _semester,
        onSaved: () {
          Navigator.pop(context);
          _reload();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_showExam) {
      return ExamRoutineScreen(
        isAdmin: widget.isAdmin,
        semester: _showAllSemesters ? RoutineService.defaultSemester : _semester,
        onBack: () => setState(() => _showExam = false),
      );
    }

    final c = context.colors;
    final byDay = _byDay;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: Text(
          'Class Routine',
          style: TextStyle(fontWeight: FontWeight.w700, color: c.white),
        ),
        actions: [
          // ── Semester dropdown removed ──
          IconButton(
            icon: AnimatedSwitcher(
              duration: 200.ms,
              transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
              child: Icon(
                _searchVisible ? Icons.close : Icons.search,
                key: ValueKey(_searchVisible),
                color: c.accent,
                size: 20,
              ),
            ),
            tooltip: 'Search',
            onPressed: () {
              setState(() {
                _searchVisible = !_searchVisible;
                if (!_searchVisible) {
                  _search = '';
                  _searchController.clear();
                  _searchFocusNode.unfocus();
                } else {
                  Future.delayed(100.ms, () => _searchFocusNode.requestFocus());
                }
              });
            },
          ),
          IconButton(
            icon: Icon(Icons.quiz_outlined, color: c.warn),
            tooltip: 'Exam Routine',
            onPressed: () => setState(() => _showExam = true),
          ),
          if (widget.isAdmin)
            IconButton(
              icon: Icon(Icons.event_busy, color: c.warn.withValues(alpha: 0.8)),
              tooltip: 'Manage Off Days',
              onPressed: () async {
                await showOffDaysManager(context);
                _loadOffDays();
              },
            ),
          if (widget.isAdmin)
            IconButton(
              icon: Icon(Icons.file_upload_outlined, color: c.accent),
              tooltip: 'Import from file',
              onPressed: _importRoutine,
            ),
          if (widget.isAdmin)
            IconButton(
              icon: Icon(Icons.add, color: c.accent),
              tooltip: 'Add routine',
              onPressed: () => _showForm(),
            ),
        ],
      ),
      body: Column(
        children: [
          if (_remindersLoaded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _ReminderCard(
                expanded: _reminderExpanded,
                classRemindersOn: _classRemindersOn,
                classReminderMinutes: _classReminderMinutes,
                minuteOptions: _minuteOptions,
                onExpand: () => setState(() => _reminderExpanded = true),
                onCollapse: () => setState(() => _reminderExpanded = false),
                onToggleClassReminders: _toggleClassReminders,
                onChangeMinutes: _changeClassReminderMinutes,
              ),
            ),
          AnimatedContainer(
            duration: 300.ms,
            curve: Curves.easeOutCubic,
            color: c.bg2,
            height: _searchVisible ? 56 : 0,
            child: AnimatedOpacity(
              opacity: _searchVisible ? 1.0 : 0.0,
              duration: 200.ms,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Container(
                  decoration: BoxDecoration(
                    color: c.bg3,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: c.border.withValues(alpha: 0.5)),
                  ),
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    onChanged: (v) => setState(() => _search = v),
                    style: TextStyle(color: c.text, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Search by subject, code, teacher, room...',
                      hintStyle: TextStyle(color: c.muted.withValues(alpha: 0.6), fontSize: 13),
                      prefixIcon: Icon(Icons.search, color: c.muted, size: 18),
                      suffixIcon: _search.isNotEmpty
                          ? GestureDetector(
                              onTap: () {
                                _searchController.clear();
                                setState(() => _search = '');
                              },
                              child: Icon(Icons.close, color: c.muted, size: 16),
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Off Days Banner
          if (_offDays.any((d) {
            final today = DateTime.now().toIso8601String().substring(0, 10);
            final s = d['start_date']?.toString() ?? '';
            final e = d['end_date']?.toString() ?? '';
            return s.compareTo(today) <= 0 && today.compareTo(e) <= 0;
          }))
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
              child: OffDaysBanner(offDays: _offDays),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              color: c.accent,
              backgroundColor: c.bg2,
              child: _initialLoading
                  ? ListView.builder(
                      padding: EdgeInsets.fromLTRB(16, 16, 16, Responsive.screenPadding(context) + 88),
                      itemCount: 4,
                      itemBuilder: (_, __) => const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: ShimmerBox(height: 100),
                      ),
                    )
                  : _visibleRoutine.isEmpty
                      ? ListView(
                          children: [
                            const SizedBox(height: 120),
                            EmptyState(
                              icon: Icons.calendar_month,
                              title: _search.isEmpty ? 'No classes scheduled' : 'No matching classes',
                              subtitle: _search.isEmpty
                                  ? _showAllSemesters
                                      ? 'No routine entries yet.'
                                      : 'No routine for ${SupabaseService.semesterFromInt(_semester)} semester yet.'
                                  : 'Try a different search term.',
                            ),
                          ],
                        )
                      : ListView(
                          padding: EdgeInsets.fromLTRB(16, 16, 16, Responsive.screenPadding(context) + 88),
                          children: RoutineService.days.asMap().entries.map((entry) {
                            final idx = entry.key;
                            final day = entry.value;
                            return _DaySection(
                              day: day,
                              dayLabel: RoutineService.dayLabels[day] ?? day,
                              classes: byDay[day] ?? const [],
                              isAdmin: widget.isAdmin,
                              showSemester: _showAllSemesters,
                              index: idx,
                              onEdit: widget.isAdmin ? _showForm : null,
                              onDelete: (id) async {
                                final ok = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    backgroundColor: c.bg2,
                                    title: Text('Delete Class', style: TextStyle(color: c.white)),
                                    content: Text('This cannot be undone.', style: TextStyle(color: c.muted)),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(ctx, false),
                                        child: const Text('Cancel'),
                                      ),
                                      TextButton(
                                        onPressed: () => Navigator.pop(ctx, true),
                                        child: Text('Delete', style: TextStyle(color: c.danger)),
                                      ),
                                    ],
                                  ),
                                );
                                if (ok == true) {
                                  await RoutineService.delete(id);
                                  await _reload();
                                }
                              },
                            );
                          }).toList(),
                        ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReminderCard extends StatelessWidget {
  final bool expanded;
  final bool classRemindersOn;
  final int classReminderMinutes;
  final List<int> minuteOptions;
  final VoidCallback onExpand;
  final VoidCallback onCollapse;
  final ValueChanged<bool> onToggleClassReminders;
  final ValueChanged<int> onChangeMinutes;

  const _ReminderCard({
    required this.expanded,
    required this.classRemindersOn,
    required this.classReminderMinutes,
    required this.minuteOptions,
    required this.onExpand,
    required this.onCollapse,
    required this.onToggleClassReminders,
    required this.onChangeMinutes,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      onTap: expanded ? null : onExpand,
      child: AnimatedContainer(
        duration: 300.ms,
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.all(expanded ? 16 : 12),
        decoration: BoxDecoration(
          color: c.bg2,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: expanded ? c.accent.withValues(alpha: 0.3) : c.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!expanded)
              Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: c.accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      classRemindersOn ? Icons.notifications_active : Icons.notifications_outlined,
                      size: 16,
                      color: classRemindersOn ? c.accent : c.muted,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text('Reminders', style: TextStyle(color: c.white, fontWeight: FontWeight.w700, fontSize: 14)),
                  const Spacer(),
                  if (classRemindersOn)
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(color: c.accent3, shape: BoxShape.circle),
                    ),
                  const SizedBox(width: 6),
                  Icon(Icons.expand_more, color: c.muted, size: 18),
                ],
              ),
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: c.accent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.notifications_active, size: 16, color: c.accent),
                      ),
                      const SizedBox(width: 10),
                      Text('Reminders', style: TextStyle(color: c.white, fontWeight: FontWeight.w700, fontSize: 15)),
                      const Spacer(),
                      GestureDetector(
                        onTap: onCollapse,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(color: c.bg3, borderRadius: BorderRadius.circular(6)),
                          child: Icon(Icons.expand_less, color: c.muted, size: 16),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Icon(Icons.menu_book_outlined, size: 16, color: c.accent3),
                      const SizedBox(width: 8),
                      Text('Class', style: TextStyle(color: c.white, fontSize: 13, fontWeight: FontWeight.w600)),
                      const Spacer(),
                      _MinutePicker(
                        value: classReminderMinutes,
                        options: minuteOptions,
                        onChanged: onChangeMinutes,
                        enabled: classRemindersOn,
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        height: 28,
                        child: Switch(
                          value: classRemindersOn,
                          onChanged: onToggleClassReminders,
                          activeTrackColor: c.accent3,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(Icons.notifications_off_outlined, size: 13, color: c.warn),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Class reminders will be paused on off days',
                          style: TextStyle(color: c.warn.withValues(alpha: 0.8), fontSize: 11, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              crossFadeState: expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
              duration: 250.ms,
            ),
          ],
        ),
      ),
    );
  }
}

class _MinutePicker extends StatelessWidget {
  final int value;
  final List<int> options;
  final ValueChanged<int> onChanged;
  final bool enabled;

  const _MinutePicker({
    required this.value,
    required this.options,
    required this.onChanged,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: enabled ? c.bg3 : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: enabled ? c.border : c.border.withValues(alpha: 0.3)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: value,
          dropdownColor: c.bg2,
          isDense: true,
          icon: Icon(Icons.unfold_more, size: 14, color: enabled ? c.white : c.muted),
          style: TextStyle(color: c.white, fontSize: 12, fontWeight: FontWeight.w600),
          items: options
              .map(
                (m) => DropdownMenuItem<int>(
                  value: m,
                  child: Text('$m min', style: TextStyle(color: enabled ? c.white : c.muted, fontSize: 12)),
                ),
              )
              .toList(),
          onChanged: enabled ? (v) { if (v != null) onChanged(v); } : null,
        ),
      ),
    );
  }
}

class _DaySection extends StatelessWidget {
  final String day;
  final String dayLabel;
  final List<ClassRoutine> classes;
  final bool isAdmin;
  final bool showSemester;
  final void Function(ClassRoutine)? onEdit;
  final Future<void> Function(String) onDelete;
  final int index;

  const _DaySection({
    required this.day,
    required this.dayLabel,
    required this.classes,
    required this.isAdmin,
    this.showSemester = false,
    this.onEdit,
    required this.onDelete,
    required this.index,
  });

  bool get _isToday {
    const weekDays = ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];
    return day == weekDays[DateTime.now().weekday % 7];
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
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
                  color: _isToday ? c.accent.withValues(alpha: 0.2) : c.bg2,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _isToday ? c.accent : c.border),
                ),
                child: Text(
                  dayLabel,
                  style: TextStyle(
                    color: _isToday ? c.accent : c.muted,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
              if (_isToday) ...[
                const SizedBox(width: 8),
                AppBadge(label: 'TODAY', color: c.accent3),
              ],
            ],
          ),
          const SizedBox(height: 8),
          if (classes.isEmpty)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: c.bg2,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: c.border),
              ),
              child: Row(
                children: [
                  Icon(Icons.free_breakfast_outlined, color: c.muted, size: 16),
                  const SizedBox(width: 8),
                  Text('No classes', style: TextStyle(color: c.muted, fontSize: 13)),
                ],
              ),
            )
          else
            ...classes.map((slot) {
              final timeStr = slot.periodIndex < RoutineService.periodTimes.length
                  ? RoutineService.periodTimes[slot.periodIndex]
                  : 'Period ${slot.periodIndex + 1}';
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: c.bg2,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: c.accent.withValues(alpha: 0.1)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 3,
                      height: 40,
                      decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(2)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            slot.subject,
                            style: TextStyle(color: c.white, fontWeight: FontWeight.w600, fontSize: 14),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            [
                              timeStr,
                              slot.room ?? 'Room TBD',
                              if (slot.teacher != null && slot.teacher!.isNotEmpty) slot.teacher!,
                              if (showSemester)
                                '${SupabaseService.semesterFromInt(slot.semester)} Semester',
                            ].join(' · '),
                            style: TextStyle(color: c.muted, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    if (isAdmin) ...[
                      if (onEdit != null)
                        GestureDetector(
                          onTap: () => onEdit!(slot),
                          child: Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Icon(Icons.edit_outlined, size: 16, color: c.muted),
                          ),
                        ),
                      GestureDetector(
                        onTap: () => onDelete(slot.id),
                        child: Icon(Icons.delete_outline, size: 16, color: c.danger),
                      ),
                    ],
                  ],
                ),
              );
            }),
        ],
      ),
    ).animate().fadeIn(
          duration: 400.ms,
          delay: Duration(milliseconds: (index * 80).clamp(0, 600)),
        ).slideY(begin: 0.06, end: 0, duration: 400.ms, curve: Curves.easeOut);
  }
}

class _RoutineForm extends StatefulWidget {
  final ClassRoutine? entry;
  final int semester;
  final VoidCallback onSaved;

  const _RoutineForm({
    this.entry,
    required this.semester,
    required this.onSaved,
  });

  @override
  State<_RoutineForm> createState() => _RoutineFormState();
}

class _RoutineFormState extends State<_RoutineForm> {
  final _formKey = GlobalKey<FormState>();
  late final _subjectCtrl = TextEditingController(text: widget.entry?.subject ?? '');
  late final _subjectCodeCtrl = TextEditingController(text: widget.entry?.subjectCode ?? '');
  late final _roomCtrl = TextEditingController(text: widget.entry?.room ?? '');
  late final _teacherCtrl = TextEditingController(text: widget.entry?.teacher ?? '');
  late final _acronymCtrl = TextEditingController(text: widget.entry?.acronym ?? '');
  late String _day;
  late int _periodIndex;
  late int _formSemester;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _day = widget.entry?.day ?? 'SUN';
    _periodIndex = widget.entry?.periodIndex ?? 0;
    _formSemester = widget.entry?.semester ??
        RoutineService.importTargetSemester(widget.semester);
  }

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _subjectCodeCtrl.dispose();
    _roomCtrl.dispose();
    _teacherCtrl.dispose();
    _acronymCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await RoutineService.save(
        ClassRoutine(
          id: widget.entry?.id ?? '',
          semester: _formSemester,
          day: _day,
          periodIndex: _periodIndex,
          subject: _subjectCtrl.text.trim(),
          subjectCode: _subjectCodeCtrl.text.trim().isEmpty ? null : _subjectCodeCtrl.text.trim(),
          room: _roomCtrl.text.trim().isEmpty ? null : _roomCtrl.text.trim(),
          teacher: _teacherCtrl.text.trim().isEmpty ? null : _teacherCtrl.text.trim(),
          acronym: _acronymCtrl.text.trim().isEmpty ? null : _acronymCtrl.text.trim(),
        ),
      );
      widget.onSaved();
    } catch (e) {
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
              Text(
                widget.entry != null ? 'Edit Class' : 'Add Class',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.white),
              ),
              const SizedBox(height: 20),
              // Semester picker removed (uses inherited semester from context)
              const SizedBox(height: 14),
              Text('DAY', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c.muted)),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: RoutineService.days.map((d) {
                    final selected = _day == d;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () => setState(() => _day = d),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                            color: selected ? c.accent.withValues(alpha: 0.15) : c.bg3,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: selected ? c.accent : c.border),
                          ),
                          child: Text(
                            d,
                            style: TextStyle(
                              color: selected ? c.accent : c.muted,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 14),
              Text('PERIOD', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c.muted)),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                initialValue: _periodIndex,
                dropdownColor: c.bg2,
                style: TextStyle(color: c.white, fontSize: 13),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: c.bg3,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.border)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.border)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                items: List.generate(
                  RoutineService.periodTimes.length,
                  (i) {
                    final isCombined = i >= RoutineService.regularPeriodCount;
                    return DropdownMenuItem(
                      value: i,
                      child: Text(
                        isCombined
                            ? RoutineService.periodTimes[i]
                            : 'Period ${i + 1}  (${RoutineService.periodTimes[i]})',
                        style: TextStyle(color: c.white, fontSize: 12),
                      ),
                    );
                  },
                ),
                onChanged: (v) => setState(() => _periodIndex = v ?? 0),
              ),
              const SizedBox(height: 14),
              AppTextField(
                label: 'Subject',
                controller: _subjectCtrl,
                validator: (v) => v == null || v.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(child: AppTextField(label: 'Subject Code', hint: 'CSE-2301', controller: _subjectCodeCtrl)),
                  const SizedBox(width: 12),
                  Expanded(child: AppTextField(label: 'Acronym', hint: 'OOP', controller: _acronymCtrl)),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(child: AppTextField(label: 'Room', controller: _roomCtrl)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AppTextField(
                      label: 'Teacher',
                      controller: _teacherCtrl,
                      prefixIcon: Icons.person_outline,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              PrimaryButton(label: 'Save', onPressed: _save, loading: _saving),
            ],
          ),
        ),
      ),
    );
  }
}

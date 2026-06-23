import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import '../core/db/local_database.dart';
import '../services/attendance_service.dart';
import '../services/cache_service.dart';
import '../services/connectivity_service.dart';
import '../services/supabase_service.dart';
import '../utils/pdf_export.dart';
import '../utils/theme_provider.dart';
import '../utils/responsive.dart';
import '../widgets/common.dart';

// ─── Helpers ─────────────────────────────────────────────────────────────────

String _dateKey(String? iso) {
  if (iso == null || iso.isEmpty) return '';
  try {
    return DateFormat('yyyy-MM-dd').format(DateTime.parse(iso).toLocal());
  } catch (_) {
    return iso;
  }
}

/// Convert [t] (either "HH:mm" or an ISO timestamp) to minutes since midnight.
/// Returns null if neither format parses.
int? _timeToMinutes(String t) {
  if (t.isEmpty) return null;
  // Try "HH:mm" or "HH:mm:ss" first
  final parts = t.split(':');
  if (parts.length >= 2) {
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h != null && m != null) return h * 60 + m;
  }
  // Fall back to full ISO timestamp
  try {
    final dt = DateTime.parse(t).toLocal();
    return dt.hour * 60 + dt.minute;
  } catch (_) {
    return null;
  }
}

String _sessionDateKey(Map<String, dynamic> record) {
  final session = record['attendance_sessions'] as Map<String, dynamic>?;
  final classDate = session?['class_date']?.toString() ?? '';
  if (classDate.isNotEmpty) {
    try {
      final parts = classDate.split('-');
      if (parts.length == 3) {
        return '${parts[0]}-${parts[1].padLeft(2, '0')}-${parts[2].padLeft(2, '0')}';
      }
      return classDate;
    } catch (_) {
      return classDate;
    }
  }
  return _dateKey(record['marked_at']?.toString());
}

Map<String, String> _studentRow(Map<String, dynamic> record, Map<String, String> rollToReg) {
  final id = record['student_id']?.toString() ?? '';
  return {'name': record['student_name']?.toString() ?? '', 'roll': id, 'reg': rollToReg[id] ?? '\u2014'};
}

List<Map<String, dynamic>> _deduplicate(List<Map<String, dynamic>> records) {
  final seen = <String>{};
  return records.where((r) {
    final id = r['student_id']?.toString() ?? '';
    if (id.isEmpty || seen.contains(id)) return false;
    seen.add(id);
    return true;
  }).toList();
}

/// Deduplicate records by (name, roll, subject, date+time to minute).
/// If roll is different, both records are kept (different students).
/// If same name+roll+subject+date+time, it's a duplicate — keep the first.
List<Map<String, dynamic>> _deduplicateRecords(List<Map<String, dynamic>> records) {
  final seen = <String>{};
  return records.where((r) {
    final name = r['student_name']?.toString() ?? '';
    final roll = r['student_id']?.toString() ?? '';
    final session = r['attendance_sessions'] as Map<String, dynamic>?;
    final subject = session?['subject']?.toString() ?? '';
    final markedAt = r['marked_at']?.toString() ?? '';
    String timeKey = '';
    try {
      final dt = DateTime.parse(markedAt).toLocal();
      timeKey = DateFormat('yyyy-MM-dd HH:mm').format(dt);
    } catch (_) {
      timeKey = markedAt;
    }
    final key = '$name|$roll|$subject|$timeKey';
    if (key.isEmpty || seen.contains(key)) return false;
    seen.add(key);
    return true;
  }).toList();
}

// ─── Reactive State Model ────────────────────────────────────────────────────

class _AttendanceReportModel extends ChangeNotifier {
  List<Map<String, dynamic>> records = [];
  bool initialLoading = true;
  bool isOffline = false;
  bool exporting = false;
  Map<String, String> rollToRegistration = {};

  void loadCached() {
    if (!CacheService.isStale('cache_attendance_records')) {
      final cached = CacheService.loadList('cache_attendance_records');
      if (cached != null && cached.isNotEmpty) { records = cached; initialLoading = false; }
    }
  }

  Future<void> _mergeBlePending() async {
    final bleSessions = await LocalDatabase.getAllBleSessions();
    for (final session in bleSessions) {
      final sessionId = session['id']?.toString() ?? '';
      if (sessionId.isEmpty) continue;

      final pendingRecords = await LocalDatabase.getBlePendingBySession(sessionId);
      final finalRecords = await LocalDatabase.getBleFinalBySession(sessionId);

      // Add pending records that are NOT yet finalized (no sync yet)
      for (final p in pendingRecords) {
        final sid = p['student_id']?.toString() ?? '';
        if (sid.isEmpty) continue;
        final hasFinal = finalRecords.any((f) => f['student_id']?.toString() == sid);
        final alreadySynced = records.any((r) =>
          r['student_id']?.toString() == sid &&
          (r['attendance_sessions'] as Map<String, dynamic>?)?['id']?.toString() ==
              (session['unified_session_id']?.toString() ?? sessionId)
        );
        if (hasFinal) continue;
        if (alreadySynced) continue;
        records.add({
          'id': 'ble_pending_${p['id']}',
          'student_id': sid,
          'student_name': p['student_name']?.toString() ?? sid,
          'method': 'ble',
          'marked_at': p['created_at']?.toString() ?? DateTime.now().toUtc().toIso8601String(),
          'attendance_sessions': {
            'id': session['unified_session_id']?.toString() ?? sessionId,
            'subject': session['subject'],
            'semester': session['semester'],
            'department': session['department'],
            'teacher_id': session['teacher_id'],
            'class_date': null,
            'class_time': null,
            'created_at': session['created_at'],
          },
          '_ble_status': p['status']?.toString() ?? 'pending',
        });
      }
    }
  }

  Future<void> fetchData() async {
    // If offline, load from cache + local BLE data without network calls
    if (!ConnectivityService().isOnline.value) {
      final cached = CacheService.loadList('cache_attendance_records');
      if (cached != null && cached.isNotEmpty) {
        records = cached;
      }
      await _mergeBlePending();
      initialLoading = false;
      isOffline = true;
      notifyListeners();
      return;
    }

    try {
      final results = await Future.wait([AttendanceService.getAttendanceReport(), SupabaseService.getStudents()]);
      records = results[0];
      initialLoading = false;
      isOffline = false;
      CacheService.saveList('cache_attendance_records', records);
      final students = results[1];
      rollToRegistration = {};
      for (final s in students) {
        final roll = s['roll']?.toString();
        final reg = s['registration']?.toString();
        if (roll != null && roll.isNotEmpty) rollToRegistration[roll] = reg ?? '\u2014';
      }

      // Merge BLE pending-only records
      await _mergeBlePending();

      notifyListeners();
    } catch (_) {
      initialLoading = false;
      if (records.isEmpty) isOffline = true;
      notifyListeners();
    }
  }

  void setExporting(bool v) { exporting = v; notifyListeners(); }
  void refresh() { isOffline = false; notifyListeners(); fetchData(); }

  /// Remove a record by its ID from the local list, clear stale cache, and notify listeners.
  /// Called after successful DB deletion so all UI stays in sync.
  void removeRecordById(String recordId) {
    records.removeWhere((r) => r['id']?.toString() == recordId);
    CacheService.remove('cache_attendance_records');
    notifyListeners();
  }

  List<String> get dateKeys {
    final keys = records.map((r) => _sessionDateKey(r)).toSet();
    final sorted = keys.toList()..sort((a, b) => b.compareTo(a));
    return sorted;
  }

  List<Map<String, dynamic>> recordsForDate(String dateKey) {
    return records.where((r) => _sessionDateKey(r) == dateKey).toList();
  }

  List<String> subjectsForDate(String dateKey) {
    final subjects = recordsForDate(dateKey)
        .map((r) => (r['attendance_sessions'] as Map<String, dynamic>?)?['subject']?.toString() ?? '')
        .where((s) => s.isNotEmpty).toSet().toList();

    // Build a lookup of subject -> sortable time string (class_time or earliest marked_at)
    final timeMap = <String, String>{};
    for (final s in subjects) {
      final recs = recordsForSubject(dateKey, s);
      String bestTime = '';
      for (final r in recs) {
        final session = r['attendance_sessions'] as Map<String, dynamic>?;
        final t = session?['class_time']?.toString() ?? '';
        if (t.isNotEmpty) { bestTime = t; break; }
        final m = r['marked_at']?.toString() ?? '';
        if (m.isNotEmpty && (bestTime.isEmpty || m.compareTo(bestTime) < 0)) {
          bestTime = m;
        }
      }
      timeMap[s] = bestTime;
    }

    subjects.sort((a, b) {
      final ta = _timeToMinutes(timeMap[a] ?? '');
      final tb = _timeToMinutes(timeMap[b] ?? '');
      if (ta != null && tb != null) return ta.compareTo(tb);
      if (ta != null) return -1;
      if (tb != null) return 1;
      return a.compareTo(b);
    });
    return subjects;
  }

  List<Map<String, dynamic>> recordsForSubject(String dateKey, String subject) {
    final result = recordsForDate(dateKey).where((r) {
      final session = r['attendance_sessions'] as Map<String, dynamic>?;
      return session?['subject']?.toString() == subject;
    }).toList();
    result.sort((a, b) {
      final sa = a['attendance_sessions'] as Map<String, dynamic>?;
      final sb = b['attendance_sessions'] as Map<String, dynamic>?;
      final ta = _timeToMinutes(sa?['class_time']?.toString() ?? '');
      final tb = _timeToMinutes(sb?['class_time']?.toString() ?? '');
      if (ta != null && tb != null) return ta.compareTo(tb);
      if (ta != null) return -1;
      if (tb != null) return 1;
      final ma = _timeToMinutes(a['marked_at']?.toString() ?? '');
      final mb = _timeToMinutes(b['marked_at']?.toString() ?? '');
      if (ma != null && mb != null) return ma.compareTo(mb);
      return (a['marked_at']?.toString() ?? '').compareTo(b['marked_at']?.toString() ?? '');
    });
    return result;
  }

  List<Map<String, dynamic>> uniqueStudentsForSubject(String dateKey, String subject) {
    final seen = <String>{};
    return recordsForSubject(dateKey, subject).where((r) {
      final id = r['student_id']?.toString() ?? '';
      if (id.isEmpty || seen.contains(id)) return false;
      seen.add(id);
      return true;
    }).toList();
  }

  // ── Export helpers ────────────────────────────────────────────────────────

  List<String> get availableMonths {
    final months = records.map((r) {
      final dk = _sessionDateKey(r);
      return dk.length >= 7 ? dk.substring(0, 7) : '';
    }).where((m) => m.isNotEmpty).toSet().toList();
    months.sort((a, b) => b.compareTo(a));
    return months;
  }

  // ── Raw record filters (for detailed PDF) ──────────────────────────────

  List<Map<String, dynamic>> recordsForMonths(List<String> monthKeys) {
    return records.where((r) {
      final dk = _sessionDateKey(r);
      return monthKeys.any((m) => dk.startsWith(m));
    }).toList();
  }

  List<Map<String, String>> studentsForMonths(List<String> monthKeys) {
    return _deduplicate(recordsForMonths(monthKeys)).map((r) => _studentRow(r, rollToRegistration)).toList();
  }

  List<Map<String, dynamic>> recordsForDateKeys(List<String> keys) {
    return records.where((r) => keys.contains(_sessionDateKey(r))).toList();
  }

  List<Map<String, String>> studentsForDateKeys(List<String> keys) {
    return _deduplicate(recordsForDateKeys(keys)).map((r) => _studentRow(r, rollToRegistration)).toList();
  }

  List<Map<String, dynamic>> recordsForSubjects(List<String> subjects) {
    return records.where((r) {
      final session = r['attendance_sessions'] as Map<String, dynamic>?;
      return subjects.contains(session?['subject']?.toString());
    }).toList();
  }

  List<Map<String, String>> studentsForSubjects(List<String> subjects) {
    return _deduplicate(recordsForSubjects(subjects)).map((r) => _studentRow(r, rollToRegistration)).toList();
  }

  List<String> get allSubjects {
    return records
        .map((r) => (r['attendance_sessions'] as Map<String, dynamic>?)?['subject']?.toString() ?? '')
        .where((s) => s.isNotEmpty).toSet().toList()..sort();
  }

  int studentCountForMonth(String monthKey) {
    final matched = records.where((r) {
      final dk = _sessionDateKey(r);
      return dk.startsWith(monthKey);
    }).toList();
    return _deduplicate(matched).length;
  }

  int studentCountForDateKey(String dk) {
    return _deduplicate(recordsForDate(dk)).length;
  }

  int studentCountForSubject(String subject) {
    final matched = records.where((r) {
      final session = r['attendance_sessions'] as Map<String, dynamic>?;
      return session?['subject']?.toString() == subject;
    }).toList();
    return _deduplicate(matched).length;
  }

  String formatMonth(String m) {
    final parts = m.split('-');
    if (parts.length != 2) return m;
    final y = parts[0];
    final mo = int.tryParse(parts[1]);
    return mo != null ? '${_monthName(mo)} $y' : m;
  }

  String formatDateKey(String dk) {
    final parts = dk.split('-');
    if (parts.length != 3) return dk;
    final mo = int.tryParse(parts[1]);
    return '${int.parse(parts[2])} ${mo != null ? _monthName(mo) : ''} ${parts[0]}';
  }
}

// ─── Main Screen (Level 1: Dates) ───────────────────────────────────────────

class AttendanceReportScreen extends StatefulWidget {
  const AttendanceReportScreen({super.key});
  @override
  State<AttendanceReportScreen> createState() => _AttendanceReportScreenState();
}

class _AttendanceReportScreenState extends State<AttendanceReportScreen> {
  late final _model = _AttendanceReportModel();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  @override
  void initState() {
    super.initState();
    _model.loadCached(); _model.fetchData();
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      if (results.any((r) => r != ConnectivityResult.none) && _model.isOffline) {
        _model.refresh();
      }
    });
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    _model.dispose();
    super.dispose();
  }

  Future<void> _exportDetailed({
    required String title,
    required String fileName,
    required List<Map<String, dynamic>> records,
  }) async {
    if (records.isEmpty) { showAppSnackbar(context, 'No records found', isError: true); return; }
    final deduped = _deduplicateRecords(records);
    final subtitle = 'Generated: ${DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now())}';
    _model.setExporting(true);
    try {
      final bytes = await PdfExport.generateDetailedReportPdf(
        title: title,
        subtitle: subtitle,
        records: deduped,
        rollToRegistration: _model.rollToRegistration,
      );
      await PdfExport.sharePdf(bytes, fileName);
      if (mounted) showAppSnackbar(context, 'PDF shared successfully');
    } catch (e) {
      if (mounted) showAppSnackbar(context, friendlyError(e), isError: true);
    }
    if (mounted) _model.setExporting(false);
  }

  void _showExportDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ExportSheet(
        model: _model,
        onExport: ({required title, required fileName, required records}) {
          _exportDetailed(title: title, fileName: fileName, records: records);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg, foregroundColor: c.white,
        title: const Text('Attendance Reports', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        actions: [
          ListenableBuilder(
            listenable: _model,
            builder: (ctx, _) {
              if (_model.exporting) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: ctx.colorsOf.accent)),
                );
              }
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(icon: Icon(Icons.picture_as_pdf, color: ctx.colorsOf.danger), onPressed: _showExportDialog, tooltip: 'Export PDF'),
                  IconButton(icon: const Icon(Icons.refresh), onPressed: () => _model.refresh(), tooltip: 'Refresh'),
                ],
              );
            },
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _model,
        builder: (ctx, _) => _buildBody(ctx.colorsOf),
      ),
    );
  }

  Widget _buildBody(ThemeColors c) {
    final m = _model;

    return Column(
      children: [
        Expanded(child: _buildBodyContent(c, m)),
      ],
    );
  }

  Widget _buildBodyContent(ThemeColors c, _AttendanceReportModel m) {
    if (m.initialLoading) {
      return ListView.builder(
        padding: EdgeInsets.all(Responsive.screenPadding(context)), itemCount: 6,
        itemBuilder: (_, __) => const Padding(padding: EdgeInsets.only(bottom: 10), child: ShimmerBox(height: 80)),
      );
    }
    if (m.records.isEmpty) {
      return RefreshIndicator(
        color: c.accent, onRefresh: () async => m.refresh(),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(height: MediaQuery.of(context).size.height * 0.5,
            child: const EmptyState(icon: Icons.calendar_today, title: 'No attendance records', subtitle: 'Records will appear once sessions are conducted'),
          ),
        ),
      );
    }
    return RefreshIndicator(
      color: c.accent, onRefresh: () async => m.refresh(),
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(Responsive.screenPadding(context)),
        itemCount: m.dateKeys.length,
        itemBuilder: (ctx, i) => _buildDateCard(c, m.dateKeys[i], i, m),
      ),
    );
  }

  Widget _buildDateCard(ThemeColors c, String dateKey, int index, _AttendanceReportModel m) {
    final recordsOnDate = m.recordsForDate(dateKey);
    final subjects = m.subjectsForDate(dateKey);
    final dateParts = dateKey.split('-');
    final year = dateParts[0];
    final month = dateParts.length > 1 ? _monthName(int.parse(dateParts[1])) : '';
    final day = dateParts.length > 2 ? int.parse(dateParts[2]).toString() : '';

    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _DateDetailScreen(dateKey: dateKey, model: m))),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: c.bg2, borderRadius: BorderRadius.circular(16), border: Border.all(color: c.border)),
        child: Row(
          children: [
            Container(
              width: 60, height: 60,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [c.accent.withValues(alpha: 0.12), c.accent.withValues(alpha: 0.04)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(14), border: Border.all(color: c.accent.withValues(alpha: 0.2)),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(day, style: TextStyle(color: c.accent, fontSize: 20, fontWeight: FontWeight.w900, height: 1.1)),
                  Text(month, style: TextStyle(color: c.accent.withValues(alpha: 0.7), fontSize: 9, fontWeight: FontWeight.w700, height: 1.1)),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$day $month $year', style: TextStyle(color: c.white, fontWeight: FontWeight.w700, fontSize: 15)),
                  const SizedBox(height: 4),
                  Text('${subjects.length} subject(s) \u00b7 ${recordsOnDate.length} attendance(s)', style: TextStyle(color: c.muted, fontSize: 12)),
                ],
              ),
            ),
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(color: c.accent.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
              child: Icon(Icons.chevron_right, color: c.accent, size: 18),
            ),
          ],
        ),
      ),
    ).animate(delay: Duration(milliseconds: (index * 50).clamp(0, 500)))
        .fadeIn(duration: 300.ms)
        .slideX(begin: 0.03, end: 0, duration: 300.ms);
  }
}

// ─── Level 2: Subjects for a Date ──────────────────────────────────────────

class _DateDetailScreen extends StatefulWidget {
  final String dateKey;
  final _AttendanceReportModel model;
  const _DateDetailScreen({required this.dateKey, required this.model});

  @override
  State<_DateDetailScreen> createState() => _DateDetailScreenState();
}

class _DateDetailScreenState extends State<_DateDetailScreen> {
  @override
  void initState() {
    super.initState();
    widget.model.addListener(_onModelChanged);
  }

  @override
  void dispose() {
    widget.model.removeListener(_onModelChanged);
    super.dispose();
  }

  void _onModelChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _exportDate() async {
    final records = widget.model.recordsForDateKeys([widget.dateKey]);
    if (records.isEmpty) { showAppSnackbar(context, 'No records found', isError: true); return; }
    try {
      final parts = widget.dateKey.split('-');
      final dateStr = parts.length == 3 ? '${int.parse(parts[2])} ${_monthName(int.parse(parts[1]))} ${parts[0]}' : widget.dateKey;
      final subtitle = 'Generated: ${DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now())}';
      final deduped = _deduplicateRecords(records);
      final bytes = await PdfExport.generateDetailedReportPdf(
        title: 'Attendance Report - $dateStr',
        subtitle: subtitle,
        records: deduped,
        rollToRegistration: widget.model.rollToRegistration,
      );
      await PdfExport.sharePdf(bytes, 'Attendance_${widget.dateKey}.pdf');
      if (context.mounted) showAppSnackbar(context, 'PDF shared successfully');
    } catch (e) { if (context.mounted) showAppSnackbar(context, friendlyError(e), isError: true); }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final subjects = widget.model.subjectsForDate(widget.dateKey);
    final parts = widget.dateKey.split('-');
    final displayDate = parts.length == 3 ? '${int.parse(parts[2])} ${_monthName(int.parse(parts[1]))} ${parts[0]}' : widget.dateKey;

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg, foregroundColor: c.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [Text(displayDate, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)), Text('${subjects.length} subject(s)', style: TextStyle(fontSize: 11, color: c.muted, fontWeight: FontWeight.w500))],
        ),
        actions: [IconButton(icon: Icon(Icons.picture_as_pdf, color: c.danger), onPressed: _exportDate, tooltip: 'Export this date')],
      ),
      body: subjects.isEmpty
          ? const EmptyState(icon: Icons.menu_book, title: 'No subjects', subtitle: '')
          : ListView.builder(
              padding: EdgeInsets.all(Responsive.screenPadding(context)), itemCount: subjects.length,
              itemBuilder: (ctx, i) => _buildSubjectCard(ctx, c, subjects[i], i),
            ),
    );
  }

  Widget _buildSubjectCard(BuildContext ctx, ThemeColors c, String subject, int index) {
    final uniqueStudents = widget.model.uniqueStudentsForSubject(widget.dateKey, subject);
    return GestureDetector(
      onTap: () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => _SubjectDetailScreen(dateKey: widget.dateKey, subject: subject, model: widget.model))),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: c.bg2, borderRadius: BorderRadius.circular(16), border: Border.all(color: c.border)),
        child: Row(
          children: [
            Container(width: 44, height: 44, decoration: BoxDecoration(color: c.accent3.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)), child: Icon(Icons.menu_book_outlined, color: c.accent3, size: 22)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(subject, style: TextStyle(color: c.white, fontWeight: FontWeight.w700, fontSize: 15)),
                  const SizedBox(height: 3),
                  Text('${uniqueStudents.length} student(s) attended', style: TextStyle(color: c.muted, fontSize: 12)),
                ],
              ),
            ),
            Container(width: 32, height: 32, decoration: BoxDecoration(color: c.accent3.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)), child: Icon(Icons.chevron_right, color: c.accent3, size: 18)),
          ],
        ),
      ),
    ).animate(delay: Duration(milliseconds: (index * 40).clamp(0, 400))).fadeIn(duration: 250.ms).slideX(begin: 0.03, end: 0, duration: 250.ms);
  }
}

// ─── Level 3: Students for a Subject on a Date ─────────────────────────────

class _SubjectDetailScreen extends StatefulWidget {
  final String dateKey; final String subject; final _AttendanceReportModel model;
  const _SubjectDetailScreen({required this.dateKey, required this.subject, required this.model});

  @override
  State<_SubjectDetailScreen> createState() => _SubjectDetailScreenState();
}

class _SubjectDetailScreenState extends State<_SubjectDetailScreen> {
  late List<Map<String, dynamic>> _records;
  final Set<String> _deletingRecords = {};

  @override
  void initState() {
    super.initState();
    _syncRecords();
    widget.model.addListener(_onModelChanged);
  }

  @override
  void dispose() {
    widget.model.removeListener(_onModelChanged);
    super.dispose();
  }

  void _onModelChanged() {
    if (!mounted) return;
    setState(() {
      _syncRecords();
    });
  }

  void _syncRecords() {
    _records = widget.model.recordsForSubject(widget.dateKey, widget.subject);
  }

  Future<void> _exportSubject() async {
    final records = widget.model.recordsForSubject(widget.dateKey, widget.subject);
    if (records.isEmpty) { showAppSnackbar(context, 'No records found', isError: true); return; }
    try {
      final parts = widget.dateKey.split('-');
      final dateStr = parts.length == 3 ? '${int.parse(parts[2])} ${_monthName(int.parse(parts[1]))} ${parts[0]}' : widget.dateKey;
      final subtitle = 'Generated: ${DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now())}';
      final deduped = _deduplicateRecords(records);
      final bytes = await PdfExport.generateDetailedReportPdf(
        title: '${widget.subject} - $dateStr',
        subtitle: subtitle,
        records: deduped,
        rollToRegistration: widget.model.rollToRegistration,
      );
      await PdfExport.sharePdf(bytes, '${widget.subject.replaceAll(' ', '_')}_${widget.dateKey}.pdf');
      if (context.mounted) showAppSnackbar(context, 'PDF shared successfully');
    } catch (e) { if (context.mounted) showAppSnackbar(context, friendlyError(e), isError: true); }
  }

  Future<void> _deleteRecord(String recordId, Map<String, dynamic> record) async {
    final c = context.colorsOf;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.bg2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.warning_amber, color: c.danger, size: 22),
            const SizedBox(width: 10),
            Text('Delete Record', style: TextStyle(color: c.white, fontSize: 16, fontWeight: FontWeight.w700)),
          ],
        ),
        content: Text(
          'Are you sure you want to delete this attendance record?\n\nThis cannot be undone.',
          style: TextStyle(color: c.muted, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: c.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete', style: TextStyle(color: c.danger, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _deletingRecords.add(recordId));
    try {
      final isBleLegacy = recordId.startsWith('ble_');
      final isBleUnified = !isBleLegacy &&
          (record['method']?.toString() == 'ble');
      final session = record['attendance_sessions'] as Map<String, dynamic>?;
      final studentId = record['student_id']?.toString() ?? '';

      if (isBleLegacy) {
        // Old-style BLE record (local merge ID like 'ble_123')
        final sessionId = session?['id']?.toString() ?? '';
        if (recordId.startsWith('ble_pending_')) {
          await AttendanceService.deleteBleRecord(recordId);
        } else if (sessionId.isNotEmpty && studentId.isNotEmpty) {
          await AttendanceService.deleteBleFinalBySessionAndStudent(sessionId, studentId);
        } else {
          await AttendanceService.deleteBleRecord(recordId);
        }
      } else if (isBleUnified) {
        // BLE record from unified attendance_records (UUID ID)
        // Delete from attendance_records AND legacy ble_final_attendance
        await AttendanceService.deleteAttendanceRecord(recordId);
        // Also try legacy: find matching BLE session + final record
        final unifiedSessionId = session?['id']?.toString() ?? '';
        if (unifiedSessionId.isNotEmpty && studentId.isNotEmpty) {
          final sessions = await LocalDatabase.getAllBleSessions();
          for (final s in sessions) {
            if (s['unified_session_id']?.toString() == unifiedSessionId) {
              final bleSid = s['id']?.toString() ?? '';
              if (bleSid.isNotEmpty) {
                await AttendanceService.deleteBleFinalBySessionAndStudent(bleSid, studentId);
              }
              break;
            }
          }
        }
      } else {
        // Regular QR/manual record
        await AttendanceService.deleteAttendanceRecord(recordId);
      }

      if (!mounted) return;
      // Remove from central model (notifies listeners + clears cache)
      widget.model.removeRecordById(recordId);
      setState(() {
        _deletingRecords.remove(recordId);
      });
      if (mounted) showAppSnackbar(context, '\u2705 Record deleted');
    } catch (e) {
      if (mounted) {
        setState(() => _deletingRecords.remove(recordId));
        showAppSnackbar(context, friendlyError(e), isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final parts = widget.dateKey.split('-');
    final displayDate = parts.length == 3
        ? '${int.parse(parts[2])} ${_monthName(int.parse(parts[1]))} ${parts[0]}'
        : widget.dateKey;

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg, foregroundColor: c.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.subject, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            Text('$displayDate \u00b7 ${_records.length} record(s)',
                style: TextStyle(fontSize: 11, color: c.muted, fontWeight: FontWeight.w500)),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.picture_as_pdf, color: c.danger),
            onPressed: _exportSubject,
            tooltip: 'Export this subject',
          ),
        ],
      ),
      body: _records.isEmpty
          ? const EmptyState(icon: Icons.people_outline, title: 'No records', subtitle: '')
          : ListView.builder(
              padding: EdgeInsets.all(Responsive.screenPadding(context)),
              itemCount: _records.length,
              itemBuilder: (ctx, i) => _buildRecordRow(c, _records[i], i),
            ),
    );
  }

  Widget _buildRecordRow(ThemeColors c, Map<String, dynamic> record, int index) {
    final studentId = record['student_id']?.toString() ?? '';
    final studentName = record['student_name']?.toString() ?? '';
    final registration = widget.model.rollToRegistration[studentId] ?? '\u2014';
    final recordId = record['id']?.toString() ?? '';
    final isDeleting = _deletingRecords.contains(recordId);

    // Format time
    String time = '';
    final markedAt = record['marked_at']?.toString() ?? '';
    if (markedAt.isNotEmpty) {
      try {
        final dt = DateTime.parse(markedAt).toLocal();
        time = DateFormat('HH:mm').format(dt);
      } catch (_) {
        time = markedAt;
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: c.bg2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: c.accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                studentName.isNotEmpty ? studentName[0].toUpperCase() : '?',
                style: TextStyle(color: c.accent, fontWeight: FontWeight.w800, fontSize: 18),
              ),
            ),
          ),
          const SizedBox(width: 14),
          // Student info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(studentName,
                    style: TextStyle(color: c.white, fontWeight: FontWeight.w700, fontSize: 14),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Row(children: [
                  Icon(Icons.badge_outlined, size: 12, color: c.muted),
                  const SizedBox(width: 4),
                  Text('Roll: $studentId',
                      style: TextStyle(color: c.muted, fontSize: 11, fontWeight: FontWeight.w600)),
                ]),
                const SizedBox(height: 2),
                Row(children: [
                  Icon(Icons.access_time, size: 12, color: c.muted),
                  const SizedBox(width: 4),
                  Text(time,
                      style: TextStyle(color: c.muted, fontSize: 11)),
                ]),
                if (registration != '\u2014')
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(children: [
                      Icon(Icons.folder_outlined, size: 12, color: c.muted),
                      const SizedBox(width: 4),
                      Text('Reg: $registration',
                          style: TextStyle(color: c.muted, fontSize: 11)),
                    ]),
                  ),
              ],
            ),
          ),
          // Delete button
          SizedBox(
            width: 36,
            height: 36,
            child: isDeleting
                ? Center(
                    child: SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: c.muted),
                    ),
                  )
                  : Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => _deleteRecord(recordId, record),
                      child: Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          color: c.danger.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.delete_outline, size: 18, color: c.danger),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    ).animate(delay: Duration(milliseconds: (index * 25).clamp(0, 400)))
        .fadeIn(duration: 250.ms)
        .slideX(begin: 0.03, end: 0, duration: 250.ms);
  }
}

// ─── Export Sheet ──────────────────────────────────────────────────────────

enum _ExportTab { month, date, subject }

class _ExportSheet extends StatefulWidget {
  final _AttendanceReportModel model;
  final void Function({required String title, required String fileName, required List<Map<String, dynamic>> records}) onExport;
  const _ExportSheet({required this.model, required this.onExport});
  @override
  State<_ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<_ExportSheet> {
  _ExportTab _tab = _ExportTab.month;

  List<String> get _items {
    switch (_tab) {
      case _ExportTab.month: return widget.model.availableMonths;
      case _ExportTab.date: return widget.model.dateKeys;
      case _ExportTab.subject: return widget.model.allSubjects;
    }
  }

  String _label(String item) {
    switch (_tab) {
      case _ExportTab.month: return widget.model.formatMonth(item);
      case _ExportTab.date: return widget.model.formatDateKey(item);
      case _ExportTab.subject: return item;
    }
  }

  void _exportItem(String item) {
    final m = widget.model;
    String title;
    String fileName;
    List<Map<String, dynamic>> records;

    switch (_tab) {
      case _ExportTab.month:
        title = 'Attendance Report - ${m.formatMonth(item)}';
        fileName = 'Attendance_${item.replaceAll('-', '_')}.pdf';
        records = m.recordsForMonths([item]);
        break;
      case _ExportTab.date:
        title = 'Attendance Report - ${m.formatDateKey(item)}';
        fileName = 'Attendance_$item.pdf';
        records = m.recordsForDateKeys([item]);
        break;
      case _ExportTab.subject:
        title = 'Attendance Report - $item';
        fileName = 'Attendance_${item.replaceAll(' ', '_')}.pdf';
        records = m.recordsForSubjects([item]);
        break;
    }

    Navigator.pop(context);
    widget.onExport(title: title, fileName: fileName, records: records);
  }

  int _studentCount(String item) {
    final m = widget.model;
    switch (_tab) {
      case _ExportTab.month: return m.studentCountForMonth(item);
      case _ExportTab.date: return m.studentCountForDateKey(item);
      case _ExportTab.subject: return m.studentCountForSubject(item);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final items = _items;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          decoration: BoxDecoration(color: c.bg2, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(margin: const EdgeInsets.only(top: 10), width: 36, height: 4, decoration: BoxDecoration(color: c.muted.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(2))),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  children: [
                    Text('Export Attendance', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.white)),
                    const Spacer(),
                    Text('Tap item to export', style: TextStyle(color: c.muted, fontSize: 11)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    _tabChip(c, _ExportTab.month, Icons.calendar_month, 'Month'),
                    const SizedBox(width: 8),
                    _tabChip(c, _ExportTab.date, Icons.calendar_today, 'Date'),
                    const SizedBox(width: 8),
                    _tabChip(c, _ExportTab.subject, Icons.menu_book, 'Subject'),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.45),
                child: items.isEmpty
                    ? Padding(padding: const EdgeInsets.all(32), child: Text('No items available', style: TextStyle(color: c.muted, fontSize: 13)))
                    : ListView.builder(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                        itemCount: items.length,
                        itemBuilder: (ctx, i) {
                          final item = items[i];
                          final count = _studentCount(item);
                          return GestureDetector(
                            onTap: () => _exportItem(item),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                              decoration: BoxDecoration(
                                color: c.bg3,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: c.border),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 36, height: 36,
                                    decoration: BoxDecoration(color: c.accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                                    child: Icon(Icons.picture_as_pdf, color: c.danger, size: 18),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      _label(item),
                                      style: TextStyle(color: c.white, fontSize: 14, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: c.muted.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(100),
                                    ),
                                    child: Text('$count', style: TextStyle(color: c.muted, fontSize: 11, fontWeight: FontWeight.w700)),
                                  ),
                                  const SizedBox(width: 8),
                                  Icon(Icons.download_outlined, color: c.accent, size: 18),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tabChip(ThemeColors c, _ExportTab tab, IconData icon, String label) {
    final active = _tab == tab;
    return GestureDetector(
      onTap: () => setState(() { _tab = tab; }),
      child: AnimatedContainer(
        duration: 200.ms,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active ? c.accent.withValues(alpha: 0.15) : c.bg3,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(color: active ? c.accent : c.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: active ? c.accent : c.muted),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: active ? c.accent : c.muted, fontSize: 12, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

// ─── Shared helper ──────────────────────────────────────────────────────────

String _monthName(int m) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return (m >= 1 && m <= 12) ? months[m - 1] : '';
}

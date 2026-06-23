import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import '../services/supabase_service.dart';
import '../services/cache_service.dart';
import '../utils/pdf_export.dart';
import '../utils/responsive.dart';
import '../utils/theme_provider.dart';
import '../widgets/common.dart';
import 'student_profile_screen.dart';
import '../utils/page_transitions.dart';

class StudentsScreen extends StatefulWidget {
  final bool isAdmin;
  final bool isTeacher;

  /// External trigger to refresh the list (e.g., after an approval in the admin panel).
  final ValueNotifier<int>? refreshNotifier;

  const StudentsScreen({super.key, required this.isAdmin, this.isTeacher = false, this.refreshNotifier});

  @override
  State<StudentsScreen> createState() => _StudentsScreenState();
}

class _StudentsScreenState extends State<StudentsScreen> {
  List<Map<String, dynamic>> _students = [];
  List<Map<String, dynamic>> _profiles = [];
  bool _initialLoading = true;
  bool _isOffline = false;
  bool _profilesLoaded = false;
  String _search = '';
  StreamSubscription<List<Map<String, dynamic>>>? _studentsSub;
  StreamSubscription<List<Map<String, dynamic>>>? _profilesSub;
  Completer<void>? _refreshCompleter;

  @override
  void initState() {
    super.initState();
    _loadCache();
    _subscribe();
    widget.refreshNotifier?.addListener(_onExternalRefresh);
  }

  void _loadCache() {
    if (!CacheService.isStale(CacheService.studentsKey)) {
      final cached = CacheService.loadList(CacheService.studentsKey);
      if (cached != null && cached.isNotEmpty) {
      setState(() => _students = cached);
      _initialLoading = false;
      }
    }
    if (!CacheService.isStale(CacheService.profilesKey)) {
      final cached = CacheService.loadList(CacheService.profilesKey);
      if (cached != null && cached.isNotEmpty) {
      setState(() {
        _profiles = cached;
        _profilesLoaded = true;
        _initialLoading = false;
      });
      }
    }
  }

  @override
  void dispose() {
    widget.refreshNotifier?.removeListener(_onExternalRefresh);
    _studentsSub?.cancel();
    _profilesSub?.cancel();
    super.dispose();
  }

  void _onExternalRefresh() {
    if (mounted) _refresh();
  }

  Future<void> _refresh() async {
    final completer = Completer<void>();
    _refreshCompleter = completer;
    _subscribe();
    await completer.future.timeout(const Duration(seconds: 15), onTimeout: () {});
  }

  /// Returns only approved registered students (from profiles table).
  /// Legacy [students] table entries are excluded — only users who
  /// registered through the app and were approved are shown.
  List<Map<String, dynamic>> _merged() {
    final byKey = <String, Map<String, dynamic>>{};

    String keyFor(Map<String, dynamic> s) {
      final email = (s['email'] ?? '').toString().trim().toLowerCase();
      if (email.isNotEmpty) return 'email:$email';

      final roll = (s['roll'] ?? '').toString().trim().toLowerCase();
      if (roll.isNotEmpty) return 'roll:$roll';

      return 'id:${s['id'] ?? identityHashCode(s)}';
    }

    for (final s in _students) {
      byKey[keyFor(s)] = {
        ...s,
        '_source': s['_source'] ?? 'students',
      };
    }

    for (final p in _profiles) {
      byKey[keyFor(p)] = {
        ...p,
        '_source': 'profile',
      };
    }

    return byKey.values.toList()
      ..sort((a, b) => ((a['name'] ?? '') as String).compareTo(b['name'] ?? ''));
  }

  /// Show all students (both registered profiles and legacy students table entries).
  /// The registered badge is only shown to admin/teacher viewers in the card itself.
  List<Map<String, dynamic>> get _filtered {
    final all = _merged();
    if (_search.isEmpty) return all;
    final q = _search.toLowerCase();
    return all.where((s) =>
      (s['name'] ?? '').toString().toLowerCase().contains(q) ||
      (s['roll'] ?? '').toString().toLowerCase().contains(q) ||
      (s['email'] ?? '').toString().toLowerCase().contains(q)
    ).toList();
  }

  void _subscribe() {
    _studentsSub?.cancel();
    _profilesSub?.cancel();
    _profilesLoaded = false;

    void checkReady() {
      // Only need _profilesLoaded since _merged() only uses _profiles.
      // The _students stream is kept for the offline banner and caching
      // but must NOT block the loading state (normal users may lack RLS
      // access to the 'students' table).
      if (!_profilesLoaded && _students.isEmpty) return;
      if (!mounted) return;
      setState(() => _initialLoading = false);
      if (_refreshCompleter != null && !_refreshCompleter!.isCompleted) {
        _refreshCompleter!.complete();
        _refreshCompleter = null;
        showAppSnackbar(context, 'Refreshed ✓', isError: false);
      }
    }

    _studentsSub = SupabaseService.getStudentsStream().listen((data) {
      if (mounted) {
        setState(() {
          _students = data;
          _isOffline = false;
        });
        CacheService.saveList(CacheService.studentsKey, data);
        checkReady();
      }
    }, onError: (e) {
      if (mounted) {
        if (_students.isNotEmpty) _isOffline = true;
        setState(() {});
      }
    });

    _profilesSub = SupabaseService.getApprovedStudentProfilesStream().listen((data) {
      if (mounted) {
        // Filter client-side for approved status (stream filter API limitation)
        final approved = data.where((p) => p['status'] == 'approved').toList();
        setState(() => _profiles = approved);
        _profilesLoaded = true;
        CacheService.saveList(CacheService.profilesKey, approved);
        checkReady();
      }
    }, onError: (e) {
      if (mounted) {
        _profilesLoaded = true;
        // Fall back to cache if stream fails
        if (_profiles.isEmpty) {
          final cached = CacheService.loadList(CacheService.profilesKey);
          if (cached != null && cached.isNotEmpty) {
            setState(() => _profiles = cached);
          }
        }
        setState(() => _isOffline = true);
        checkReady();
        showAppSnackbar(context, friendlyError(e), isError: true);
      }
    });
  }

  double _gridAspectRatio(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    // Dynamically adjust aspect ratio based on screen width
    // Taller cards on smaller screens, wider on larger screens
    // Slightly taller ratios to accommodate larger flip card content
    if (w < 360) return 0.62;
    if (w < 480) return 0.66;
    if (w < 600) return 0.72;
    return 0.80;
  }

  void _showAddForm() {
    final c = context.colorsOf;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: c.bg2,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _StudentForm(onSaved: () => Navigator.pop(context)),
    );
  }

  Future<void> _exportPdf(List<Map<String, dynamic>> students) async {
    if (students.isEmpty) {
      showAppSnackbar(context, 'No students to export', isError: true);
      return;
    }

    try {
      final title = 'CST Student List';
      final dateStr = DateFormat('dd MMM yyyy').format(DateTime.now());

      // ── Only students registered in the app ──
      // Filter out legacy students_table entries; keep only those with
      // an approved profile (_source == 'profile').
      final appStudents = students.where((s) => s['_source'] == 'profile').toList();
      final legacySkipped = students.length - appStudents.length;

      if (appStudents.isEmpty) {
        if (mounted) {
          showAppSnackbar(context, 'No registered students found to export', isError: true);
        }
        return;
      }

      // ── Dedup by roll ──
      // If two entries share the same roll, keep only the first one.
      // Students with different rolls are kept even if names match.
      final seenRolls = <String>{};
      final deduped = <Map<String, dynamic>>[];
      int dupCount = 0;
      for (final s in appStudents) {
        final roll = (s['roll'] ?? '').toString().trim();
        if (roll.isEmpty || seenRolls.add(roll)) {
          deduped.add(s);
        } else {
          dupCount++;
        }
      }

      // ── Distribution counts (from deduped list) ──
      final semesterCounts = <int, int>{};
      final shiftCounts = <String, int>{};
      for (final s in deduped) {
        final sem = s['semester'];
        if (sem != null) {
          final key = sem is int ? sem : int.tryParse(sem.toString());
          if (key != null) semesterCounts[key] = (semesterCounts[key] ?? 0) + 1;
        }
        final shift = (s['shift'] ?? '').toString();
        if (shift.isNotEmpty) {
          shiftCounts[shift] = (shiftCounts[shift] ?? 0) + 1;
        }
      }

      final semParts = semesterCounts.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      final semStr = semParts.map((e) => 'Sem ${e.key}: ${e.value}').join(', ');
      final shiftStr = shiftCounts.entries
          .map((e) => '${e.key}: ${e.value}')
          .join(', ');

      final subtitle =
          'Generated: $dateStr \u2022 ${deduped.length} student(s)'
          '${semStr.isNotEmpty ? ' \u2022 $semStr' : ''}'
          '${shiftStr.isNotEmpty ? ' \u2022 $shiftStr' : ''}'
          '${dupCount > 0 ? ' \u2022 $dupCount duplicate(s) removed' : ''}'
          '${legacySkipped > 0 ? ' \u2022 $legacySkipped legacy entr(ies) excluded' : ''}';

      final studentRows = deduped.map((s) => {
        'name': (s['name'] ?? '').toString(),
        'roll': (s['roll'] ?? '').toString(),
        'reg': (s['registration'] ?? '').toString(),
      }).toList();

      final bytes = await PdfExport.generateStudentListPdf(
        title: title,
        subtitle: subtitle,
        students: studentRows,
      );

      final fileName = 'CST_Students_${DateFormat('yyyy-MM-dd').format(DateTime.now())}.pdf';
      await PdfExport.sharePdf(bytes, fileName);

      if (mounted) {
        final parts = <String>['Exported ${deduped.length} student(s)'];
        if (dupCount > 0) parts.add('$dupCount duplicate(s) skipped');
        if (legacySkipped > 0) parts.add('$legacySkipped legacy entr(ies) excluded');
        showAppSnackbar(context, parts.join(' · '));
      }
    } catch (e) {
      if (mounted) {
        showAppSnackbar(context, 'Failed to export: ${friendlyError(e)}', isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final filtered = _filtered;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: Text('Students', style: TextStyle(fontWeight: FontWeight.w700, color: c.white)),
        actions: [
          if (widget.isAdmin) ...[                  
            IconButton(icon: Icon(Icons.picture_as_pdf, color: c.accent), tooltip: 'Export to PDF', onPressed: () => _exportPdf(filtered)),
            IconButton(icon: Icon(Icons.person_add_outlined, color: c.accent), tooltip: 'Add student', onPressed: _showAddForm),
          ],
        ],
      ),
      body: Column(
        children: [
          Container(
            color: c.bg2,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              children: [
                TextField(
                  onChanged: (v) => setState(() => _search = v),
                  style: TextStyle(color: c.text, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Search by name, roll, email...',
                    prefixIcon: Icon(Icons.search, color: c.muted, size: 18),
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              color: c.accent,
              backgroundColor: c.bg2,
              child: _initialLoading
                  ? GridView.builder(
                      padding: EdgeInsets.fromLTRB(
                        Responsive.screenPadding(context),
                        Responsive.screenPadding(context),
                        Responsive.screenPadding(context),
                        Responsive.screenPadding(context) + 88,
                      ),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: Responsive.gridColumns(context, small: 2, medium: 2, large: 3),
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: _gridAspectRatio(context),
                      ),
                      itemCount: 6,
                      itemBuilder: (_, __) => const ShimmerBox(height: 150),
                    )
                  : filtered.isEmpty
                      ? ListView(
                          children: [
                            const SizedBox(height: 120),
                            const EmptyState(icon: Icons.people, title: 'No students found', subtitle: 'Try a different filter.'),
                            if (_profiles.isEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 16),
                                child: AppBadge(
                                  label: 'No registered students found',
                                  color: c.muted,
                                ),
                              ),
                          ],
                        )
                      : GridView.builder(
                          padding: EdgeInsets.fromLTRB(
                            Responsive.screenPadding(context),
                            Responsive.screenPadding(context),
                            Responsive.screenPadding(context),
                            Responsive.screenPadding(context) + 88,
                          ),
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: Responsive.gridColumns(context, small: 2, medium: 2, large: 3),
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: _gridAspectRatio(context),
                          ),
                          itemCount: filtered.length,
                          itemBuilder: (_, i) {
                            final student = filtered[i];
                            return _StudentCard(
                              key: ValueKey(student['id']),
                              student: student,
                              index: i,
                              isAdmin: widget.isAdmin,
                              isTeacher: widget.isTeacher,
                              onRefresh: () { if (mounted) _refresh(); },
                            );
                          },
                        ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StudentCard extends StatefulWidget {
  final Map<String, dynamic> student;
  final int index;
  final bool isAdmin;
  final bool isTeacher;
  final VoidCallback? onRefresh;

  const _StudentCard({
    super.key,
    required this.student,
    required this.index,
    required this.isAdmin,
    required this.isTeacher,
    this.onRefresh,
  });

  @override
  State<_StudentCard> createState() => _StudentCardState();
}

class _StudentCardState extends State<_StudentCard> {
  bool _isHovered = false;

  bool get _isFromProfile => widget.student['_source'] == 'profile';

  Future<void> _viewProfile() async {
    final changed = await Navigator.push<bool>(
      context,
      buildCupertinoRoute(StudentProfileScreen(
        student: widget.student,
        isAdmin: widget.isAdmin,
        isTeacher: widget.isTeacher,
      )),
    );
    if (changed == true) {
      widget.onRefresh?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = widget.student;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: _viewProfile,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: c.bg2,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: _isHovered
                  ? c.accent.withValues(alpha: 0.15)
                  : c.border.withValues(alpha: 0.15),
              width: 0.5,
            ),
            boxShadow: _isHovered
                ? [
                    BoxShadow(
                      color: c.accent.withValues(alpha: 0.08),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : [],
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final avatarSize = (constraints.maxWidth * 0.85).clamp(80.0, 140.0);
                      return Center(
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              width: avatarSize,
                              height: avatarSize,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(2),
                                gradient: LinearGradient(
                                  colors: [c.accent.withValues(alpha: 0.15), c.accentDim.withValues(alpha: 0.15)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: c.accent.withValues(alpha: 0.08),
                                    blurRadius: 14,
                                  ),
                                ],
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(0.5),
                                child: UserAvatar(
                                  name: s['name'] ?? '',
                                  photoUrl: s['photo_url'],
                                  size: avatarSize - 1,
                                  borderRadius: 2,
                                  borderOpacity: 0.15,
                                ),
                              ),
                            ),
                            if (_isFromProfile && (widget.isAdmin || widget.isTeacher))
                              Positioned(
                                right: -1,
                                bottom: 1,
                                child: Container(
                                  padding: const EdgeInsets.all(4.5),
                                  decoration: BoxDecoration(
                                    color: c.accent2.withValues(alpha: 0.95),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: c.bg2, width: 2.5),
                                  ),
                                  child: Icon(Icons.check_circle, size: 14, color: c.white),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  s['name'] ?? '',
                  style: TextStyle(
                    color: c.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    height: 1.2,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    ).animate(
      delay: Duration(milliseconds: (widget.index * 60).clamp(0, 600)),
    ).fadeIn(duration: 350.ms).scale(
      begin: const Offset(0.95, 0.95),
      end: const Offset(1, 1),
      duration: 350.ms,
      curve: Curves.easeOutBack,
    );
  }
}

class _StudentForm extends StatefulWidget {
  final VoidCallback onSaved;
  const _StudentForm({required this.onSaved});

  @override
  State<_StudentForm> createState() => _StudentFormState();
}

class _StudentFormState extends State<_StudentForm> {
  final _formKey = GlobalKey<FormState>();
  late final _nameCtrl = TextEditingController();
  late final _emailCtrl = TextEditingController();
  late final _rollCtrl = TextEditingController();
  late final _regCtrl = TextEditingController();
  late final _contactCtrl = TextEditingController();
  late final _sessionCtrl = TextEditingController();
  String _semester = '3rd';
  String _shift = 'Day';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final data = {
        'name': _nameCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
        'roll': _rollCtrl.text.trim(),
        'registration': _regCtrl.text.trim(),
        'contact': _contactCtrl.text.trim(),
        'semester': SupabaseService.semesterToInt(_semester),
        'shift': _shift,
        'session': _sessionCtrl.text.trim(),
      };
      await SupabaseService.insertStudent(data);
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
              Text('Add Student',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.white)),
              const SizedBox(height: 20),
              AppTextField(label: 'Full Name', controller: _nameCtrl, prefixIcon: Icons.person_outline, validator: (v) => v == null || v.isEmpty ? 'Required' : null),
              const SizedBox(height: 14),
              AppTextField(label: 'Email', controller: _emailCtrl, prefixIcon: Icons.email_outlined, keyboardType: TextInputType.emailAddress, validator: (v) => v == null || v.isEmpty ? 'Required' : null),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: AppTextField(label: 'Roll No', controller: _rollCtrl)),
                const SizedBox(width: 12),
                Expanded(child: AppTextField(label: 'Registration', controller: _regCtrl)),
              ]),
              const SizedBox(height: 14),
              AppTextField(label: 'Contact', controller: _contactCtrl, prefixIcon: Icons.phone_outlined, keyboardType: TextInputType.phone),
              const SizedBox(height: 14),
              AppTextField(label: 'Session', hint: 'e.g. 2021-2022', controller: _sessionCtrl, prefixIcon: Icons.calendar_today_outlined),
              // Semester picker removed (defaults to 3rd semester)
              const SizedBox(height: 14),
              Text('SHIFT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c.muted)),
              const SizedBox(height: 8),
              Row(
                children: ['Morning', 'Day'].map((sh) {
                  final sel = _shift == sh;
                  return Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: GestureDetector(
                      onTap: () => setState(() => _shift = sh),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: sel ? c.accent.withValues(alpha: 0.15) : c.bg3,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: sel ? c.accent : c.border),
                        ),
                        child: Text(sh, style: TextStyle(color: sel ? c.accent : c.white, fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
              PrimaryButton(label: 'Save Student', onPressed: _save, loading: _saving),
            ],
          ),
        ),
      ),
    );
  }
}


// ── Edit Student Bottom Sheet (admin only) ─────────────────────────────────

class _EditStudentSheet extends StatefulWidget {
  final Map<String, dynamic> student;
  final VoidCallback onSaved;

  const _EditStudentSheet({required this.student, required this.onSaved});

  @override
  State<_EditStudentSheet> createState() => _EditStudentSheetState();
}

class _EditStudentSheetState extends State<_EditStudentSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _rollCtrl;
  late final TextEditingController _regCtrl;
  late final TextEditingController _contactCtrl;
  late final TextEditingController _sessionCtrl;
  late String _shift;
  bool _saving = false;

  static const _shifts = ['Morning', 'Day'];

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.student['name'] ?? '');
    _rollCtrl = TextEditingController(text: widget.student['roll'] ?? '');
    _regCtrl = TextEditingController(text: widget.student['registration'] ?? '');
    _contactCtrl = TextEditingController(text: widget.student['contact'] ?? '');
    _sessionCtrl = TextEditingController(text: widget.student['session'] ?? '');
    _shift = widget.student['shift'] ?? 'Day';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _rollCtrl.dispose();
    _regCtrl.dispose();
    _contactCtrl.dispose();
    _sessionCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      final data = <String, dynamic>{
        'name': _nameCtrl.text.trim(),
        'roll': _rollCtrl.text.trim(),
        'registration': _regCtrl.text.trim(),
        'contact': _contactCtrl.text.trim(),
        'session': _sessionCtrl.text.trim(),
        'shift': _shift,
      };

      final email = widget.student['email']?.toString() ?? '';
      final studentId = widget.student['id']?.toString() ?? '';
      final source = widget.student['_source']?.toString() ?? '';

      // Update profiles table if the student has a registered profile
      if (source == 'profile' && email.isNotEmpty) {
        await SupabaseService.upsertProfile({
          'id': studentId,
          'email': email,
          ...data,
        });
      }

      // Update students table (always, for legacy compatibility)
      if (email.isNotEmpty) {
        await SupabaseService.updateStudentByEmail(email, data);
      } else if (studentId.isNotEmpty) {
        try {
          await SupabaseService.updateStudent(studentId, data);
        } catch (_) {}
      }

      widget.onSaved();
    } catch (e) {
      if (mounted) showAppSnackbar(context, friendlyError(e), isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(20, 20, 20, bottom + 20),
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(color: c.muted.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),
              Text('Edit Student Details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.white)),
              const SizedBox(height: 8),
              Text('Changes will be saved to both profile and student records.',
                  style: TextStyle(color: c.muted, fontSize: 12)),
              const SizedBox(height: 20),

              // Name
              TextFormField(
                controller: _nameCtrl,
                style: TextStyle(color: c.white),
                decoration: InputDecoration(
                  labelText: 'Full Name',
                  labelStyle: TextStyle(color: c.muted),
                  prefixIcon: Icon(Icons.person_outline, color: c.muted),
                  filled: true,
                  fillColor: c.bg2,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.border)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.border)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.accent)),
                ),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
              ),
              const SizedBox(height: 12),

              // Roll
              TextFormField(
                controller: _rollCtrl,
                style: TextStyle(color: c.white),
                decoration: InputDecoration(
                  labelText: 'Roll No',
                  labelStyle: TextStyle(color: c.muted),
                  prefixIcon: Icon(Icons.badge_outlined, color: c.muted),
                  filled: true,
                  fillColor: c.bg2,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.border)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.border)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.accent)),
                ),
              ),
              const SizedBox(height: 12),

              // Registration
              TextFormField(
                controller: _regCtrl,
                style: TextStyle(color: c.white),
                decoration: InputDecoration(
                  labelText: 'Registration No',
                  labelStyle: TextStyle(color: c.muted),
                  prefixIcon: Icon(Icons.card_membership_outlined, color: c.muted),
                  filled: true,
                  fillColor: c.bg2,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.border)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.border)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.accent)),
                ),
              ),
              const SizedBox(height: 12),

              // Contact
              TextFormField(
                controller: _contactCtrl,
                style: TextStyle(color: c.white),
                decoration: InputDecoration(
                  labelText: 'Contact',
                  labelStyle: TextStyle(color: c.muted),
                  prefixIcon: Icon(Icons.phone_outlined, color: c.muted),
                  filled: true,
                  fillColor: c.bg2,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.border)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.border)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.accent)),
                ),
              ),
              const SizedBox(height: 12),

              // Session
              TextFormField(
                controller: _sessionCtrl,
                style: TextStyle(color: c.white),
                decoration: InputDecoration(
                  labelText: 'Session',
                  labelStyle: TextStyle(color: c.muted),
                  prefixIcon: Icon(Icons.calendar_today_outlined, color: c.muted),
                  filled: true,
                  fillColor: c.bg2,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.border)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.border)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.accent)),
                ),
              ),
              const SizedBox(height: 12),

              // Shift only
              Text('SHIFT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c.muted)),
              const SizedBox(height: 8),
              Row(
                children: _shifts.map((sh) {
                  final sel = _shift == sh;
                  return Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: GestureDetector(
                      onTap: () => setState(() => _shift = sh),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: sel ? c.accent.withValues(alpha: 0.15) : c.bg3,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: sel ? c.accent : c.border),
                        ),
                        child: Text(sh, style: TextStyle(color: sel ? c.accent : c.white, fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),

              // Save button
              ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: c.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _saving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Save Changes', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

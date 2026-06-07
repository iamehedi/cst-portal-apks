import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/supabase_service.dart';
import '../services/cache_service.dart';
import '../utils/responsive.dart';
import '../utils/theme_provider.dart';
import '../widgets/common.dart';
import 'teacher_profile_screen.dart';
import '../utils/page_transitions.dart';

class TeachersScreen extends StatefulWidget {
  final bool isAdmin;

  /// External trigger to refresh the list (e.g., after an approval in the admin panel).
  final ValueNotifier<int>? refreshNotifier;

  const TeachersScreen({super.key, required this.isAdmin, this.refreshNotifier});

  @override
  State<TeachersScreen> createState() => _TeachersScreenState();
}

class _TeachersScreenState extends State<TeachersScreen> {
  List<Map<String, dynamic>> _teachers = [];
  bool _initialLoading = true;
  bool _isOffline = false;
  String _search = '';
  StreamSubscription<List<Map<String, dynamic>>>? _teachersSub;
  Completer<void>? _refreshCompleter;
  Timer? _autoRefreshTimer;

  @override
  void initState() {
    super.initState();
    // ── Cache-first: show cached data immediately ──
    if (!CacheService.isStale(CacheService.teachersKey)) {
      final cached = CacheService.loadList(CacheService.teachersKey);
      if (cached != null && cached.isNotEmpty) {
        _teachers = cached;
        _initialLoading = false;
      }
    }
    _subscribe();
    widget.refreshNotifier?.addListener(_onExternalRefresh);
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    widget.refreshNotifier?.removeListener(_onExternalRefresh);
    _teachersSub?.cancel();
    super.dispose();
  }

  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) _silentRefresh();
    });
  }

  Future<void> _silentRefresh() async {
    try {
      final data = await SupabaseService.getTeachers();
      if (mounted) {
        setState(() {
          _teachers = data;
          _initialLoading = false;
          _isOffline = false;
        });
        CacheService.saveList(CacheService.teachersKey, data);
      }
    } catch (_) {
      if (mounted && _teachers.isNotEmpty) {
        setState(() => _isOffline = true);
      }
    }
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

  void _subscribe() {
    _teachersSub?.cancel();      _teachersSub = SupabaseService.getTeachersStream().listen((data) {
      if (mounted) {
        setState(() {
          _teachers = data;
          _initialLoading = false;
          _isOffline = false;
        });
        CacheService.saveList(CacheService.teachersKey, data);
        if (_refreshCompleter != null && !_refreshCompleter!.isCompleted) {
          _refreshCompleter!.complete();
          _refreshCompleter = null;
          showAppSnackbar(context, 'Refreshed \u2713', isError: false);
        }
      }
    }, onError: (e) {
      if (mounted) {
        setState(() {
          _initialLoading = false;
          if (_teachers.isNotEmpty) _isOffline = true;
        });
        if (_refreshCompleter != null && !_refreshCompleter!.isCompleted) {
          _refreshCompleter!.completeError(e);
          _refreshCompleter = null;
        }
        showAppSnackbar(context, friendlyError(e), isError: true);
      }
    });
  }

  List<Map<String, dynamic>> get _filtered {
    if (_search.isEmpty) return _teachers;
    final q = _search.toLowerCase();
    return _teachers.where((t) =>
      (t['teacher_name'] ?? '').toString().toLowerCase().contains(q) ||
      (t['designation'] ?? '').toString().toLowerCase().contains(q) ||
      (t['subject'] ?? '').toString().toLowerCase().contains(q) ||
      (t['email'] ?? '').toString().toLowerCase().contains(q)
    ).toList();
  }

  double _gridAspectRatio(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    if (w < 360) return 0.72;
    if (w < 480) return 0.76;
    if (w < 600) return 0.80;
    return 0.85;
  }

  void _showForm([Map<String, dynamic>? teacher]) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.colors.bg2,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _TeacherForm(teacher: teacher, onSaved: () { Navigator.pop(context); }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: Text('Faculty', style: TextStyle(fontWeight: FontWeight.w700, color: c.white)),
        actions: [
          if (widget.isAdmin)
            IconButton(icon: Icon(Icons.person_add_outlined, color: c.accent), tooltip: 'Add teacher', onPressed: () => _showForm()),
        ],
      ),
      body: Column(
        children: [
          ConnectivityBanners(
            isOffline: _isOffline,
            onRefresh: () => _refresh(),
          ),
          Container(
            color: c.bg2,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              onChanged: (v) => setState(() => _search = v),
              style: TextStyle(color: c.text, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search by name, designation, subject...',
                prefixIcon: Icon(Icons.search, color: c.muted, size: 18),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              color: c.accent,
              backgroundColor: c.bg2,
              child: _initialLoading
                  ? GridView.builder(
                      padding: EdgeInsets.all(Responsive.screenPadding(context)),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: Responsive.gridColumns(context, small: 2, medium: 2, large: 3),
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: _gridAspectRatio(context),
                      ),
                      itemCount: 6,
                      itemBuilder: (_, __) => const ShimmerBox(height: 160),
                    )
                  : _filtered.isEmpty
                      ? ListView(
                          children: [
                            const SizedBox(height: 120),
                            EmptyState(icon: Icons.person, title: _search.isEmpty ? 'No faculty added' : 'No matching faculty', subtitle: _search.isEmpty ? 'Admin can add faculty members.' : 'Try a different search term.'),
                          ],
                        )
                      : GridView.builder(
                          padding: EdgeInsets.all(Responsive.screenPadding(context)),
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: Responsive.gridColumns(context, small: 2, medium: 2, large: 3),
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: _gridAspectRatio(context),
                          ),
                          itemCount: _filtered.length,
                          itemBuilder: (_, i) => _TeacherCard(
                            key: ValueKey(_filtered[i]['id']),
                            teacher: _filtered[i],
                            index: i,
                            isAdmin: widget.isAdmin,
                            onTap: () async {
                              final deleted = await Navigator.push<bool>(context, buildCupertinoRoute(TeacherProfileScreen(teacher: _filtered[i], isAdmin: widget.isAdmin)));
                              if (deleted == true && mounted) _refresh();
                            },
                            onEdit: () => _showForm(_filtered[i]),
                            onDelete: () async {
                              final tid = _filtered[i]['id'].toString();
                              final ok = await showDialog<bool>(
                                context: context,
                                builder: (_) => AlertDialog(
                                  backgroundColor: c.bg2,
                                  title: Text('Delete Faculty', style: TextStyle(color: c.white)),
                                  content: Text('This will remove the faculty completely. They can re-register with the same email.', style: TextStyle(color: c.muted)),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                                    TextButton(onPressed: () => Navigator.pop(context, true),
                                      child: Text('Delete', style: TextStyle(color: c.danger))),
                                  ],
                                ),
                              );
                              if (ok == true) {
                                await SupabaseService.deleteTeacher(tid);
                                await SupabaseService.safeDeleteUser(tid);
                                if (mounted) _refresh();
                              }
                            },
                          ),
                        ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TeacherCard extends StatefulWidget {
  final Map<String, dynamic> teacher;
  final int index;
  final bool isAdmin;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _TeacherCard({super.key, required this.teacher, required this.index, required this.isAdmin, required this.onTap, required this.onEdit, required this.onDelete});

  @override
  State<_TeacherCard> createState() => _TeacherCardState();
}

class _TeacherCardState extends State<_TeacherCard> {
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final name = widget.teacher['teacher_name'] ?? '';
    final initials = name.isNotEmpty ? name.split(' ').map((p) => p.isNotEmpty ? p[0] : '').take(2).join().toUpperCase() : '?';
    return RepaintBoundary(
      child: GestureDetector(
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: c.bg2,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.border, width: 1),
        ),
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 56, height: 56,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [c.accent, c.accentDim]),
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: c.accentGlow, blurRadius: 16)],
                ),
                child: Center(child: Text(initials, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white))),
              ),
              const SizedBox(height: 8),
              Text(name, style: TextStyle(color: c.white, fontWeight: FontWeight.w700, fontSize: 12), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 3),
              Text(widget.teacher['designation'] ?? '', style: TextStyle(color: c.accent, fontSize: 10, fontWeight: FontWeight.w600), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 3),
              Text(widget.teacher['subject'] ?? '', style: TextStyle(color: c.muted, fontSize: 10), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
              if (widget.isAdmin) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ActionIconButton(
                      icon: Icons.edit_outlined,
                      color: c.muted,
                      onTap: widget.onEdit,
                      tooltip: 'Edit',
                    ),
                    const SizedBox(width: 6),
                    ActionIconButton(
                      icon: Icons.delete_outline,
                      color: c.danger,
                      onTap: widget.onDelete,
                      tooltip: 'Delete',
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ).animate(delay: Duration(milliseconds: (widget.index * 60).clamp(0, 600))).fadeIn(duration: 350.ms).scale(begin: const Offset(0.95, 0.95), end: const Offset(1, 1), duration: 350.ms, curve: Curves.easeOutBack),
    );
  }
}

class _TeacherForm extends StatefulWidget {
  final Map<String, dynamic>? teacher;
  final VoidCallback onSaved;
  const _TeacherForm({this.teacher, required this.onSaved});

  @override
  State<_TeacherForm> createState() => _TeacherFormState();
}

class _TeacherFormState extends State<_TeacherForm> {
  final _formKey = GlobalKey<FormState>();
  late final _nameCtrl = TextEditingController(text: widget.teacher?['teacher_name'] ?? '');
  late final _designationCtrl = TextEditingController(text: widget.teacher?['designation'] ?? '');
  late final _subjectCtrl = TextEditingController(text: widget.teacher?['subject'] ?? '');
  late final _emailCtrl = TextEditingController(text: widget.teacher?['email'] ?? '');
  late final _contactCtrl = TextEditingController(text: widget.teacher?['phone'] ?? '');
  bool _saving = false;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await SupabaseService.upsertTeacher({
        if (widget.teacher != null) 'id': widget.teacher!['id'],
        'teacher_name': _nameCtrl.text.trim(),
        'designation': _designationCtrl.text.trim(),
        'subject': _subjectCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
        'phone': _contactCtrl.text.trim(),
      });
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
              Text(widget.teacher != null ? 'Edit Faculty' : 'Add Faculty',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.white)),
              const SizedBox(height: 20),
              AppTextField(label: 'Full Name', controller: _nameCtrl, prefixIcon: Icons.person_outline, validator: (v) => v == null || v.isEmpty ? 'Required' : null),
              const SizedBox(height: 14),
              AppTextField(label: 'Designation', hint: 'e.g. Lecturer', controller: _designationCtrl),
              const SizedBox(height: 14),
              AppTextField(label: 'Subject / Department', controller: _subjectCtrl),
              const SizedBox(height: 14),
              AppTextField(label: 'Email', controller: _emailCtrl, keyboardType: TextInputType.emailAddress, prefixIcon: Icons.email_outlined),
              const SizedBox(height: 14),
              AppTextField(label: 'Contact', controller: _contactCtrl, keyboardType: TextInputType.phone, prefixIcon: Icons.phone_outlined),
              const SizedBox(height: 24),
              PrimaryButton(label: 'Save Faculty', onPressed: _save, loading: _saving),
            ],
          ),
        ),
      ),
    );
  }
}

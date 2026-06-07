import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../screens/note_preview_screen.dart';
import '../services/supabase_service.dart';
import '../services/cache_service.dart';
import '../utils/theme_provider.dart';
import '../utils/animations.dart';
import '../utils/page_transitions.dart';
import '../widgets/common.dart';

// ─── Reactive State Model ────────────────────────────────────────────────────
class _NotesModel extends ChangeNotifier {
  List<Map<String, dynamic>> notes = [];
  bool initialLoading = true;
  bool isOffline = false;
  int? semester;
  String search = '';
  bool searchVisible = false;

  final searchController = TextEditingController();
  final searchFocusNode = FocusNode();

  StreamSubscription<List<Map<String, dynamic>>>? _notesSub;
  Completer<void>? _refreshCompleter;
  Timer? _autoRefreshTimer;

  // Filter constants removed (semester filter UI hidden for all users)

  List<Map<String, dynamic>> get filtered {
    if (search.isEmpty) return notes;
    final q = search.toLowerCase();
    return notes.where((n) =>
      (n['note_title'] ?? '').toString().toLowerCase().contains(q) ||
      (n['subject'] ?? '').toString().toLowerCase().contains(q)
    ).toList();
  }

  void init(int? defaultSemester) {
    semester = defaultSemester;
    if (!CacheService.isStale(CacheService.notesKey(semester))) {
      final cached = CacheService.loadList(CacheService.notesKey(semester));
      if (cached != null && cached.isNotEmpty) {
        notes = cached;
        initialLoading = false;
      }
    }
    _subscribe();
    _startAutoRefresh();
  }

  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 10), (_) => _silentRefresh());
  }

  Future<void> _silentRefresh() async {
    try {
      final data = await SupabaseService.getNotes(semester: semester);
      notes = data;
      isOffline = false;
      CacheService.saveList(CacheService.notesKey(semester), data);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> refresh() async {
    final completer = Completer<void>();
    _refreshCompleter = completer;
    _subscribe();
    await completer.future.timeout(const Duration(seconds: 15), onTimeout: () {});
  }

  void _subscribe() {
    _notesSub?.cancel();
    _notesSub = SupabaseService.getNotesStream(semester: semester).listen((data) {
      notes = data;
      initialLoading = false;
      isOffline = false;
      CacheService.saveList(CacheService.notesKey(semester), data);
      notifyListeners();
      if (_refreshCompleter != null && !_refreshCompleter!.isCompleted) {
        _refreshCompleter!.complete();
        _refreshCompleter = null;
      }
    }, onError: (_) {
      if (notes.isNotEmpty) {
        isOffline = true;
      } else {
        initialLoading = false;
      }
      notifyListeners();
      if (_refreshCompleter != null && !_refreshCompleter!.isCompleted) {
        _refreshCompleter!.completeError(_);
        _refreshCompleter = null;
      }
    });
  }


  void toggleSearch() {
    searchVisible = !searchVisible;
    if (!searchVisible) {
      search = '';
      searchController.clear();
      searchFocusNode.unfocus();
    } else {
      Future.delayed(100.ms, () => searchFocusNode.requestFocus());
    }
    notifyListeners();
  }

  void setSearch(String v) {
    search = v;
    notifyListeners();
  }

  void clearSearch() {
    search = '';
    searchController.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _notesSub?.cancel();
    searchController.dispose();
    searchFocusNode.dispose();
    super.dispose();
  }
}

// ─── Screen ──────────────────────────────────────────────────────────────────
class NotesScreen extends StatefulWidget {
  final bool isAdmin;
  final int? defaultSemester;
  const NotesScreen({super.key, required this.isAdmin, this.defaultSemester});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  late final _model = _NotesModel();

  @override
  void initState() {
    super.initState();
    _model.init(widget.defaultSemester);
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  Future<void> _showForm([Map<String, dynamic>? note]) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AnimatedNoteForm(
        note: note,
        onSaved: () {
          showAppSnackbar(context, note != null ? 'Note updated!' : 'Note published!');
          Navigator.pop(context, true);
        },
      ),
    );
    // Refresh immediately after the form closes
    _model.refresh();
  }

  Future<void> _delete(String id, [String? fileUrl]) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => const _AnimatedDeleteDialog(),
    );
    if (ok != true) return;
    if (fileUrl != null && fileUrl.isNotEmpty) {
      try { await SupabaseService.deleteNoteFile(fileUrl); } catch (_) {}
    }
    await SupabaseService.deleteNote(id);
  }

  IconData _fileIcon(String? url) {
    if (url == null) return Icons.description;
    final lower = url.toLowerCase();
    if (lower.contains('.pdf')) return Icons.picture_as_pdf;
    if (lower.contains('.doc')) return Icons.article;
    if (lower.contains('.ppt')) return Icons.slideshow;
    if (lower.contains('.zip')) return Icons.folder_zip;
    return Icons.description;
  }

  Color _fileColor(String? url, ThemeColors c) {
    if (url == null) return c.warn;
    final lower = url.toLowerCase();
    if (lower.contains('.pdf')) return c.danger;
    if (lower.contains('.doc')) return c.accentIndigo;
    if (lower.contains('.ppt')) return c.accentOrange;
    if (lower.contains('.zip')) return c.accent3;
    return c.warn;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: Text('Notes', style: TextStyle(fontWeight: FontWeight.w700, color: c.white)),
        actions: [
          ListenableBuilder(
            listenable: _model,
            builder: (ctx, _) {
              final m = _model;
              return IconButton(
                icon: AnimatedContainer(
                  duration: 250.ms,
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: m.searchVisible ? c.accent.withValues(alpha: 0.15) : c.bg3,
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(
                      color: m.searchVisible ? c.accent.withValues(alpha: 0.5) : c.border.withValues(alpha: 0.5),
                      width: m.searchVisible ? 1.0 : 0.5,
                    ),
                  ),
                  child: AnimatedSwitcher(
                    duration: 200.ms,
                    transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
                    child: Icon(
                      m.searchVisible ? Icons.close : Icons.search,
                      key: ValueKey(m.searchVisible),
                      color: m.searchVisible ? c.accent : c.muted,
                      size: 18,
                    ),
                  ),
                ),
                tooltip: m.searchVisible ? 'Close Search' : 'Search',
                onPressed: m.toggleSearch,
              );
            },
          ),
          if (widget.isAdmin)
            IconButton(
              icon: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: c.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.add, color: c.accent, size: 18),
              ),
              tooltip: 'Add Note',
              onPressed: () => _showForm(),
            ),
        ],
      ),
      body: Column(
        children: [
          ConnectivityBanners(
            isOffline: _model.isOffline,
            onRefresh: () => _model.refresh(),
          ),
          // ── Search bar ──
          ListenableBuilder(
            listenable: _model,
            builder: (ctx, _) {
              final m = _model;
              return AnimatedSize(
                duration: 300.ms,
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: m.searchVisible
                    ? Container(
                        color: c.bg2,
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: TextField(
                          controller: m.searchController,
                          focusNode: m.searchFocusNode,
                          onChanged: m.setSearch,
                          style: TextStyle(color: c.text, fontSize: 13),
                          decoration: InputDecoration(
                            hintText: 'Search by title or subject...',
                            hintStyle: TextStyle(color: c.muted.withValues(alpha: 0.6), fontSize: 12),
                            prefixIcon: Icon(Icons.search, color: c.muted, size: 16),
                            suffixIcon: m.search.isNotEmpty
                                ? GestureDetector(
                                    onTap: m.clearSearch,
                                    child: Icon(Icons.close, color: c.muted, size: 14),
                                  )
                                : null,
                            contentPadding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              );
            },
          ),
          // ── Semester filter chips removed ──
          // ── Content ──
          Expanded(
            child: _buildContent(c),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(ThemeColors c) {
    return ListenableBuilder(
      listenable: _model,
      builder: (ctx, _) {
        final m = _model;
        final filtered = m.filtered;

        return RefreshIndicator(
          onRefresh: m.refresh,
          color: c.accent,
          backgroundColor: c.bg2,
          child: m.initialLoading
              ? ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: 6,
                  itemBuilder: (_, __) => const Padding(
                    padding: EdgeInsets.only(bottom: 10),
                    child: ShimmerBox(height: 80, radius: 14),
                  ),
                )
              : filtered.isEmpty
                  ? ListView(
                      children: [
                        SizedBox(height: MediaQuery.of(context).size.height * 0.15),
                        Padding(
                          padding: const EdgeInsets.all(40),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 80, height: 80,
                                decoration: BoxDecoration(
                                  color: c.bg2,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: c.border),
                                ),
                                child: Center(
                                  child: Icon(m.search.isNotEmpty ? Icons.search : Icons.menu_book, size: 36, color: c.accent),
                                ),
                              ).animate().fadeIn(duration: 400.ms).scale(begin: const Offset(0.8, 0.8), duration: 400.ms, curve: Curves.easeOutBack),
                              const SizedBox(height: 16),
                              Text(
                                m.search.isNotEmpty ? 'No results found' : 'No materials yet',
                                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.white),
                              ).animate().fadeIn(duration: 400.ms, delay: 100.ms),
                              const SizedBox(height: 6),
                              Text(
                                m.search.isNotEmpty ? 'Try a different search term' : 'No materials available for this semester.',
                                style: TextStyle(color: c.muted, fontSize: 13),
                                textAlign: TextAlign.center,
                              ).animate().fadeIn(duration: 400.ms, delay: 200.ms),
                              if (m.search.isNotEmpty) ...[
                                const SizedBox(height: 20),
                                GhostButton(
                                  label: 'Clear search',
                                  icon: Icons.close,
                                  onPressed: m.clearSearch,
                                ).animate().fadeIn(duration: 400.ms, delay: 300.ms),
                              ],
                            ],
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(8, 16, 16, 16),
                      itemCount: filtered.length,
                      itemBuilder: (_, i) => _EnhancedNoteItem(
                        note: filtered[i],
                        isAdmin: widget.isAdmin,
                        fileIcon: _fileIcon,
                        fileColor: _fileColor,
                        onEdit: () => _showForm(filtered[i]),
                        onDelete: () => _delete(filtered[i]['id'].toString(), filtered[i]['note_file_url']),
                        index: i,
                        isLast: i == filtered.length - 1,
                      ),
                    ),
        );
      },
    );
  }
}

// ── Enhanced List Item ───────────────────────────────────────────────────────
class _EnhancedNoteItem extends StatelessWidget {
  final Map<String, dynamic> note;
  final bool isAdmin;
  final IconData Function(String?) fileIcon;
  final Color Function(String?, ThemeColors) fileColor;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final int index;
  final bool isLast;

  const _EnhancedNoteItem({
    required this.note,
    required this.isAdmin,
    required this.fileIcon,
    required this.fileColor,
    required this.onEdit,
    required this.onDelete,
    required this.index,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fileUrl = note['note_file_url'] ?? '';
    final icon = fileIcon(fileUrl);
    final color = fileColor(fileUrl, c);
    final hasPreview = fileUrl.isNotEmpty ||
        (note['note_content'] != null && note['note_content'].toString().trim().isNotEmpty);

    return RepaintBoundary(
      child: IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 32,
            child: Column(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(top: 20),
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.4),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    decoration: BoxDecoration(
                      gradient: isLast ? null : LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [color.withValues(alpha: 0.4), c.border.withValues(alpha: 0.2)],
                      ),
                      color: isLast ? Colors.transparent : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: c.bg2,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: c.border),
              ),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  splashColor: c.accent.withValues(alpha: 0.04),
                  highlightColor: c.accent.withValues(alpha: 0.02),
                  onTap: () => Navigator.push(context, buildCupertinoRoute(NotePreviewScreen(note: note))),
                  child: Stack(
                    children: [
                      Padding(
                        padding: EdgeInsets.fromLTRB(12, 12, (isAdmin || hasPreview) ? 68 : 12, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 36, height: 36,
                                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: color.withValues(alpha: 0.15), width: 0.5),
                                  ),
                                  child: Icon(icon, size: 16, color: color),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    physics: const BouncingScrollPhysics(),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(note['note_title'] ?? '', style: TextStyle(color: c.white, fontWeight: FontWeight.w600, fontSize: 13)),
                                        if (note['subject'] != null)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 2),
                                            child: Text(note['subject'] ?? '', style: TextStyle(color: c.muted, fontSize: 11, fontWeight: FontWeight.w500)),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (note['semester'] != null) ...[
                              const SizedBox(height: 8),
                              Center(child: SemesterBadge(label: '${SupabaseService.semesterFromInt(int.tryParse(note['semester']?.toString() ?? ''))} Semester')),
                            ],
                          ],
                        ),
                      ),
                      if (isAdmin)
                        Positioned(
                          top: 6, right: 6,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ActionIconButton(icon: Icons.edit_outlined, color: c.muted, onTap: onEdit, tooltip: 'Edit'),
                              const SizedBox(width: 4),
                              ActionIconButton(icon: Icons.delete_outline, color: c.danger, onTap: onDelete, tooltip: 'Delete'),
                            ],
                          ),
                        ),
                      if (!isAdmin && hasPreview)
                        Positioned(
                          top: 6, right: 6,
                          child: GestureDetector(
                            onTap: () => Navigator.push(context, buildCupertinoRoute(NotePreviewScreen(note: note))),
                            child: Container(
                              width: 26, height: 26,
                              decoration: BoxDecoration(
                                color: c.accent.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: c.accent.withValues(alpha: 0.15), width: 0.5),
                              ),
                              child: Icon(Icons.open_in_new, color: c.accent, size: 13),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      ),
    ).animate().fadeIn(
      duration: 350.ms,
      delay: staggerDelay(index, total: const Duration(milliseconds: 500)),
      curve: Curves.easeOut,
    ).slideX(
      begin: 0.04, end: 0,
      duration: 350.ms,
      delay: staggerDelay(index, total: const Duration(milliseconds: 500)),
      curve: Curves.easeOut,
    );
  }
}

// ── Animated Bottom Sheet Form ───────────────────────────────────────────────
class _AnimatedNoteForm extends StatefulWidget {
  final Map<String, dynamic>? note;
  final VoidCallback onSaved;
  const _AnimatedNoteForm({this.note, required this.onSaved});

  @override
  State<_AnimatedNoteForm> createState() => _AnimatedNoteFormState();
}

class _AnimatedNoteFormState extends State<_AnimatedNoteForm> {
  final _formKey = GlobalKey<FormState>();
  late final _titleCtrl = TextEditingController(text: widget.note?['note_title'] ?? '');
  late final _subjectCtrl = TextEditingController(text: widget.note?['subject'] ?? '');
  late final _urlCtrl = TextEditingController(text: widget.note?['note_file_url'] ?? '');
  late final _contentCtrl = TextEditingController(text: widget.note?['note_content'] ?? '');
  int _semester = 1;
  bool _saving = false;
  PlatformFile? _pickedFile;

  // Semester picker removed (uses default semester 3)

  @override
  void initState() {
    super.initState();
    _semester = int.tryParse(widget.note?['semester']?.toString() ?? '') ?? 3;
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx', 'ppt', 'pptx', 'zip', 'rar'],
      withData: true,
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() { _pickedFile = result.files.first; _urlCtrl.clear(); });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      String? fileUrl = _urlCtrl.text.trim();
      if (_pickedFile != null && _pickedFile!.bytes != null) {
        fileUrl = await SupabaseService.uploadNoteFile(_pickedFile!.bytes!, _pickedFile!.name);
      }
      final data = <String, dynamic>{
        'note_title': _titleCtrl.text.trim(),
        'subject': _subjectCtrl.text.trim(),
        'note_content': _contentCtrl.text.trim().isEmpty ? null : _contentCtrl.text.trim(),
        'note_file_url': fileUrl,
        'semester': _semester,
        'user_id': SupabaseService.currentUser?.id,
      };
      if (widget.note != null) {
        await SupabaseService.updateNote(widget.note!['id'].toString(), data);
      } else {
        await SupabaseService.insertNote(data);
      }
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
      child: Container(
        decoration: BoxDecoration(
          color: c.bg2,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(top: BorderSide(color: c.border)),
        ),
        child: DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (_, scrollController) => SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: Container(
                      width: 40, height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(color: c.muted.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(color: c.accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                        child: Icon(widget.note != null ? Icons.edit_outlined : Icons.add, color: c.accent, size: 18),
                      ),
                      const SizedBox(width: 12),
                      Text(widget.note != null ? 'Edit Note' : 'Add New Note', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.white)),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _FormFieldWrapper(delay: 0, child: AppTextField(label: 'Title', controller: _titleCtrl, prefixIcon: Icons.title_outlined, validator: (v) => v == null || v.isEmpty ? 'Required' : null)),
                  const SizedBox(height: 16),
                  _FormFieldWrapper(delay: 50, child: AppTextField(label: 'Subject', controller: _subjectCtrl, prefixIcon: Icons.book_outlined)),
                  const SizedBox(height: 16),
                  _FormFieldWrapper(delay: 75, child: AppTextField(label: 'Content (optional)', controller: _contentCtrl, prefixIcon: Icons.description_outlined, maxLines: 4, hint: 'Write notes, summaries, or study material...')),
                  const SizedBox(height: 16),
                  _FormFieldWrapper(delay: 100, child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text('PDF FILE'.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c.muted))),
                          if (_pickedFile != null) GestureDetector(onTap: () => setState(() => _pickedFile = null), child: Text('Clear', style: TextStyle(color: c.danger, fontSize: 11, fontWeight: FontWeight.w600))),
                        ],
                      ),
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: _pickFile,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            color: c.bg3,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: _pickedFile != null ? c.accent.withValues(alpha: 0.5) : c.border, width: _pickedFile != null ? 1.5 : 0.5),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 36, height: 36,
                                decoration: BoxDecoration(color: c.accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                                child: Icon(_pickedFile != null ? Icons.description : Icons.upload_file, color: c.accent, size: 18),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(_pickedFile != null ? _pickedFile!.name : 'Tap to select a PDF file', maxLines: 1, overflow: TextOverflow.ellipsis,
                                      style: TextStyle(color: _pickedFile != null ? c.white : c.muted, fontSize: 13, fontWeight: _pickedFile != null ? FontWeight.w600 : FontWeight.w400)),
                                    if (_pickedFile != null && _pickedFile!.size > 0)
                                      Text('${(_pickedFile!.size / 1024).toStringAsFixed(0)} KB', style: TextStyle(color: c.muted, fontSize: 10)),
                                  ],
                                ),
                              ),
                              Icon(Icons.folder_open, color: c.muted, size: 16),
                            ],
                          ),
                        ),
                      ),
                      if (_pickedFile == null) ...[
                        const SizedBox(height: 10),
                        Row(children: [Expanded(child: AppTextField(label: 'Or paste a URL / link', controller: _urlCtrl, prefixIcon: Icons.link_outlined, keyboardType: TextInputType.url))]),
                      ],
                    ],
                  )),
                  // Semester picker removed (defaults to 3rd semester)
                  const SizedBox(height: 28),
                  _FormFieldWrapper(delay: 200, child: PrimaryButton(label: widget.note != null ? 'Update Note' : 'Upload Note', onPressed: _save, loading: _saving, icon: widget.note != null ? Icons.save_outlined : Icons.cloud_upload_outlined)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FormFieldWrapper extends StatelessWidget {
  final Widget child;
  final int delay;
  const _FormFieldWrapper({required this.child, required this.delay});

  @override
  Widget build(BuildContext context) {
    return child.animate().fadeIn(duration: 350.ms, delay: Duration(milliseconds: delay), curve: Curves.easeOut)
        .slideY(begin: 0.04, end: 0, duration: 350.ms, delay: Duration(milliseconds: delay), curve: Curves.easeOut);
  }
}

class _AnimatedDeleteDialog extends StatelessWidget {
  const _AnimatedDeleteDialog();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Dialog(
      backgroundColor: c.bg2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: c.border, width: 0.5)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(color: c.danger.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16), border: Border.all(color: c.danger.withValues(alpha: 0.15))),
              child: Icon(Icons.delete_outline, color: c.danger, size: 28),
            ).animate().scale(begin: const Offset(0, 0), duration: 300.ms, curve: Curves.easeOutBack),
            const SizedBox(height: 16),
            Text('Delete Note', style: TextStyle(color: c.white, fontSize: 18, fontWeight: FontWeight.w700)).animate().fadeIn(duration: 300.ms, delay: 100.ms),
            const SizedBox(height: 8),
            Text('This action cannot be undone.', style: TextStyle(color: c.muted, fontSize: 13)).animate().fadeIn(duration: 300.ms, delay: 150.ms),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(child: TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancel', style: TextStyle(color: c.muted))).animate().fadeIn(duration: 300.ms, delay: 200.ms).slideX(begin: -0.02, end: 0)),
                const SizedBox(width: 12),
                Expanded(child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: c.danger.withValues(alpha: 0.15), foregroundColor: c.danger, elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: c.danger.withValues(alpha: 0.3))),
                  ),
                  child: const Text('Delete', style: TextStyle(fontWeight: FontWeight.w700)),
                ).animate().fadeIn(duration: 300.ms, delay: 250.ms).slideX(begin: 0.02, end: 0)),
              ],
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 200.ms).scale(begin: const Offset(0.9, 0.9), duration: 300.ms, curve: Curves.easeOutBack);
  }
}

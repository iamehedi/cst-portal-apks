import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import '../services/supabase_service.dart';
import '../utils/theme_provider.dart';
import '../widgets/common.dart';

// ─── Events Editor Screen ────────────────────────────────────────────────────
class EventsEditorScreen extends StatefulWidget {
  final bool isAdmin;
  /// Whether the current user can add/edit/delete events.
  /// Admins and teachers can edit; students can only view.
  final bool canEdit;
  const EventsEditorScreen({super.key, this.isAdmin = true, this.canEdit = true});

  @override
  State<EventsEditorScreen> createState() => _EventsEditorScreenState();
}

class _EventsEditorScreenState extends State<EventsEditorScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: c.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Events Editor',
            style: TextStyle(fontWeight: FontWeight.w700, color: c.white)),
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: c.accent,
          labelColor: c.accent,
          unselectedLabelColor: c.muted,
          indicatorSize: TabBarIndicatorSize.tab,
          indicatorWeight: 3,
          indicatorPadding: const EdgeInsets.symmetric(horizontal: 24),
          labelStyle:
              const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          tabs: [
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.event, size: 16),
                  const SizedBox(width: 6),
                  const Text('Events'),
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.event_busy, size: 16),
                  const SizedBox(width: 6),
                  const Text('Off Days'),
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.edit_note, size: 16),
                  const SizedBox(width: 6),
                  const Text('Exams'),
                ],
              ),
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _EventsTab(isAdmin: widget.isAdmin, canEdit: widget.canEdit),
          _OffDaysTab(isAdmin: widget.isAdmin, canEdit: widget.canEdit),
          _ExamsTab(isAdmin: widget.isAdmin, canEdit: widget.canEdit),
        ],
      ),
    );
  }
}

// ─── Events Tab (General College Events) ──────────────────────────────────
class _EventsTab extends StatefulWidget {
  final bool isAdmin;
  final bool canEdit;
  const _EventsTab({required this.isAdmin, this.canEdit = true});

  @override
  State<_EventsTab> createState() => _EventsTabState();
}

class _EventsTabState extends State<_EventsTab> {
  List<Map<String, dynamic>> _events = [];
  bool _loading = true;
  StreamSubscription<List<Map<String, dynamic>>>? _eventsSub;

  // Add form state
  bool _showForm = false;
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  DateTime _eventDate = DateTime.now();
  TimeOfDay _eventTime = const TimeOfDay(hour: 10, minute: 0);
  bool _hasTime = false;
  String _eventType = 'Seminar';
  bool _saving = false;

  static const _eventTypes = [
    'Seminar', 'Workshop', 'Cultural', 'Meeting', 'Sports',
    'Webinar', 'Competition', 'Festival', 'General',
  ];

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void dispose() {
    _eventsSub?.cancel();
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _locationCtrl.dispose();
    super.dispose();
  }

  void _subscribe() {
    _eventsSub?.cancel();
    _eventsSub = SupabaseService.getEventsStream().listen((data) {
      if (!mounted) return;
      // Filter for future events only
      final today = DateTime.now().toIso8601String().substring(0, 10);
      final filtered = data.where((e) {
        final date = e['event_date']?.toString() ?? '';
        return date.compareTo(today) >= 0;
      }).toList()
        ..sort((a, b) => (a['event_date'] ?? '').toString().compareTo(b['event_date']?.toString() ?? ''));
      setState(() { _events = filtered; _loading = false; });
    }, onError: (_) {
      if (mounted) setState(() => _loading = false);
    });
  }

  Future<void> _pickDate() async {
    final c = context.colors;
    final picked = await showDatePicker(
      context: context,
      initialDate: _eventDate,
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
      builder: (ctx, child) => Theme(
        data: buildDatePickerTheme(ctx, Theme.of(ctx)),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _eventDate = picked);
  }

  Future<void> _pickTime() async {
    final c = context.colors;
    final picked = await showTimePicker(
      context: context,
      initialTime: _eventTime,
      builder: (ctx, child) => Theme(
        data: buildDatePickerTheme(ctx, Theme.of(ctx)),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _eventTime = picked);
  }

  Future<void> _add() async {
    if (_titleCtrl.text.trim().isEmpty) {
      showAppSnackbar(context, 'Title is required', isError: true);
      return;
    }
    setState(() => _saving = true);
    try {
      await SupabaseService.insertEvent({
        'title': _titleCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'event_date': _eventDate.toIso8601String().substring(0, 10),
        'event_time': _hasTime ? '${_eventTime.hour.toString().padLeft(2, '0')}:${_eventTime.minute.toString().padLeft(2, '0')}:00' : null,
        'location': _locationCtrl.text.trim().isEmpty ? null : _locationCtrl.text.trim(),
        'event_type': _eventType,
        'created_by': SupabaseService.currentUser?.id,
      });
      _titleCtrl.clear();
      _descCtrl.clear();
      _locationCtrl.clear();
      _eventDate = DateTime.now();
      _eventTime = const TimeOfDay(hour: 10, minute: 0);
      _hasTime = false;
      _eventType = 'Seminar';
      setState(() => _showForm = false);
      if (mounted) showAppSnackbar(context, 'Event added');
    } catch (e) {
      if (mounted) showAppSnackbar(context, friendlyError(e), isError: true);
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _delete(String id) async {
    try {
      await SupabaseService.deleteEvent(id);
      if (mounted) showAppSnackbar(context, 'Event deleted');
    } catch (e) {
      if (mounted) showAppSnackbar(context, friendlyError(e), isError: true);
    }
  }

  Color _typeColor(String type, ThemeColors c) {
    switch (type) {
      case 'Seminar':
        return c.accent;
      case 'Workshop':
        return c.accent3;
      case 'Cultural':
        return c.accentOrange;
      case 'Meeting':
        return c.accentIndigo;
      case 'Sports':
        return Colors.green;
      case 'Webinar':
        return Colors.cyan;
      case 'Competition':
        return c.warn;
      case 'Festival':
        return Colors.pinkAccent;
      default:
        return c.muted;
    }
  }

  String _formatDate(String dateStr) {
    try {
      return DateFormat('MMM d, yyyy').format(DateTime.parse(dateStr));
    } catch (_) {
      return dateStr;
    }
  }

  String _formatTime(String? time) {
    if (time == null || time.isEmpty) return '';
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

  IconData _typeIcon(String type) {
    switch (type) {
      case 'Seminar':
        return Icons.mic;
      case 'Workshop':
        return Icons.build;
      case 'Cultural':
        return Icons.palette;
      case 'Meeting':
        return Icons.groups;
      case 'Sports':
        return Icons.sports_soccer;
      case 'Webinar':
        return Icons.laptop;
      case 'Competition':
        return Icons.emoji_events;
      case 'Festival':
        return Icons.celebration;
      default:
        return Icons.event;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colorsOf;

    if (_loading) {
      return ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: 4,
        itemBuilder: (_, __) => const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: ShimmerBox(height: 70),
        ),
      );
    }

    return Column(
      children: [
        if (widget.canEdit) ...[
          // Add button
          Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _showForm = !_showForm),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: _showForm ? c.bg3 : c.accent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _showForm ? c.border : c.accent.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _showForm ? Icons.close : Icons.add,
                              size: 16,
                              color: _showForm ? c.muted : c.accent,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _showForm ? 'Cancel' : 'Add Event',
                              style: TextStyle(
                                color: _showForm ? c.muted : c.accent,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          // Add form
          if (_showForm)
            Flexible(
              fit: FlexFit.loose,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: c.bg2,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: c.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Add Event',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.white)),
                      const SizedBox(height: 16),
                      // Event type
                      Text('EVENT TYPE',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: c.muted)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: _eventTypes.map((t) {
                          final sel = _eventType == t;
                          return GestureDetector(
                            onTap: () => setState(() => _eventType = t),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: sel ? c.accent.withValues(alpha: 0.15) : c.bg3,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: sel ? c.accent : c.border),
                              ),
                              child: Text(t,
                                  style: TextStyle(
                                      color: sel ? c.accent : c.muted,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600)),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 12),
                      // Date and time
                      Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: _pickDate,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('DATE',
                                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: c.muted)),
                                  const SizedBox(height: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                    decoration: BoxDecoration(
                                      color: c.bg3,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: c.border),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(Icons.calendar_today_outlined, size: 14, color: c.muted),
                                        const SizedBox(width: 6),
                                        Text(
                                          DateFormat('MMM d, yyyy').format(_eventDate),
                                          style: TextStyle(color: c.text, fontSize: 12),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                setState(() => _hasTime = !_hasTime);
                                if (!_hasTime) _eventTime = const TimeOfDay(hour: 10, minute: 0);
                              },
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text('TIME',
                                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: c.muted)),
                                      const SizedBox(width: 4),
                                      Container(
                                        width: 14, height: 14,
                                        decoration: BoxDecoration(
                                          color: _hasTime ? c.accent : c.bg3,
                                          borderRadius: BorderRadius.circular(3),
                                          border: Border.all(color: _hasTime ? c.accent : c.border),
                                        ),
                                        child: _hasTime
                                            ? Icon(Icons.check, size: 10, color: Colors.white)
                                            : null,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                    decoration: BoxDecoration(
                                      color: c.bg3,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: _hasTime ? c.accent : c.border),
                                    ),
                                    child: GestureDetector(
                                      onTap: _hasTime ? _pickTime : null,
                                      child: Row(
                                        children: [
                                          Icon(Icons.access_time,
                                              size: 14, color: _hasTime ? c.accent : c.muted.withValues(alpha: 0.4)),
                                          const SizedBox(width: 6),
                                          Text(
                                            _hasTime ? _eventTime.format(context) : 'Optional',
                                            style: TextStyle(
                                              color: _hasTime ? c.text : c.muted.withValues(alpha: 0.5),
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      // Title
                      Container(
                        decoration: BoxDecoration(
                          color: c.bg3,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: c.border),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: TextField(
                          controller: _titleCtrl,
                          style: TextStyle(color: c.text, fontSize: 13),
                          decoration: const InputDecoration(
                            hintText: 'Event title',
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      // Description
                      Container(
                        decoration: BoxDecoration(
                          color: c.bg3,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: c.border),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: TextField(
                          controller: _descCtrl,
                          style: TextStyle(color: c.text, fontSize: 13),
                          maxLines: 3,
                          decoration: const InputDecoration(
                            hintText: 'Description (optional)',
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      // Location
                      Container(
                        decoration: BoxDecoration(
                          color: c.bg3,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: c.border),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: TextField(
                          controller: _locationCtrl,
                          style: TextStyle(color: c.text, fontSize: 13),
                          decoration: const InputDecoration(
                            hintText: 'Location (optional)',
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      GestureDetector(
                        onTap: _saving ? null : _add,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: c.accent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Center(
                            child: _saving
                                ? SizedBox(
                                    width: 18, height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : Text('Save Event',
                                    style: TextStyle(
                                        color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
        const SizedBox(height: 8),
        // Events list
        Expanded(
          child: _events.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.event, size: 40, color: c.muted.withValues(alpha: 0.4)),
                      const SizedBox(height: 12),
                      Text('No upcoming events',
                          style: TextStyle(color: c.muted, fontSize: 14)),
                      Text('Add seminars, workshops, and more',
                          style: TextStyle(color: c.muted.withValues(alpha: 0.6), fontSize: 12)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _events.length,
                  itemBuilder: (_, i) {
                    final ev = _events[i];
                    final type = ev['event_type']?.toString() ?? 'General';
                    final typeColor = _typeColor(type, c);
                    final icon = _typeIcon(type);
                    final dateStr = _formatDate(ev['event_date']?.toString() ?? '');
                    final timeStr = ev['event_time'] != null && ev['event_time'].toString().isNotEmpty
                        ? _formatTime(ev['event_time'].toString())
                        : null;
                    final location = ev['location']?.toString();
                    final desc = ev['description']?.toString();

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Stack(
                        children: [
                          // Gradient hero background
                          Container(
                            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  typeColor.withValues(alpha: 0.35),
                                  typeColor.withValues(alpha: 0.08),
                                  c.bg2,
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              border: Border.all(
                                color: typeColor.withValues(alpha: 0.2),
                              ),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Top row: type badge + delete
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: typeColor.withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                          color: typeColor.withValues(alpha: 0.4),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(icon, size: 12, color: typeColor),
                                          const SizedBox(width: 4),
                                          Text(
                                            type.toUpperCase(),
                                            style: TextStyle(
                                              color: typeColor,
                                              fontSize: 10,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: 1,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Spacer(),
                                    if (widget.canEdit)
                                      GestureDetector(
                                        onTap: () => _delete(ev['id']?.toString() ?? ''),
                                        child: Container(
                                          padding: const EdgeInsets.all(6),
                                          decoration: BoxDecoration(
                                            color: c.danger.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Icon(Icons.delete_outline, size: 16, color: c.danger),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                // Title (big, prominent)
                                Text(
                                  ev['title'] ?? '',
                                  style: TextStyle(
                                    color: c.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                    height: 1.2,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                // Description (if present)
                                if (desc != null && desc.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    desc,
                                    style: TextStyle(
                                      color: c.text.withValues(alpha: 0.8),
                                      fontSize: 13,
                                      height: 1.4,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                                const SizedBox(height: 14),
                                // Info row: date, time, location
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: c.bg3.withValues(alpha: 0.5),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.calendar_today, size: 12, color: typeColor),
                                      const SizedBox(width: 4),
                                      Text(
                                        dateStr,
                                        style: TextStyle(color: c.muted, fontSize: 11, fontWeight: FontWeight.w500),
                                      ),
                                      if (timeStr != null) ...[
                                        const SizedBox(width: 8),
                                        Icon(Icons.access_time, size: 12, color: typeColor),
                                        const SizedBox(width: 4),
                                        Text(
                                          timeStr,
                                          style: TextStyle(color: c.muted, fontSize: 11, fontWeight: FontWeight.w500),
                                        ),
                                      ],
                                      if (location != null && location.isNotEmpty) ...[
                                        const Spacer(),
                                        Icon(Icons.location_on, size: 12, color: typeColor.withValues(alpha: 0.6)),
                                        const SizedBox(width: 4),
                                        Flexible(
                                          child: Text(
                                            location,
                                            style: TextStyle(color: c.muted, fontSize: 11, fontWeight: FontWeight.w500),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Decorative glowing orb
                          Positioned(
                            top: -30,
                            right: -30,
                            child: Container(
                              width: 100,
                              height: 100,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: typeColor.withValues(alpha: 0.08),
                                boxShadow: [
                                  BoxShadow(
                                    color: typeColor.withValues(alpha: 0.12),
                                    blurRadius: 40,
                                    spreadRadius: 10,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ).animate().fadeIn(
                      duration: 400.ms,
                      delay: Duration(milliseconds: (i * 60).clamp(0, 600)),
                    ).scaleXY(
                      begin: 0.96,
                      end: 1.0,
                      duration: 400.ms,
                      delay: Duration(milliseconds: (i * 60).clamp(0, 600)),
                      curve: Curves.easeOutBack,
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ─── Off Days Tab ────────────────────────────────────────────────────────────
class _OffDaysTab extends StatefulWidget {
  final bool isAdmin;
  final bool canEdit;
  const _OffDaysTab({required this.isAdmin, this.canEdit = true});

  @override
  State<_OffDaysTab> createState() => _OffDaysTabState();
}

class _OffDaysTabState extends State<_OffDaysTab> {
  List<Map<String, dynamic>> _offDays = [];
  bool _loading = true;
  StreamSubscription<List<Map<String, dynamic>>>? _offDaysSub;

  // Add form state
  bool _showForm = false;
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now();
  final _reasonCtrl = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void dispose() {
    _offDaysSub?.cancel();
    _reasonCtrl.dispose();
    super.dispose();
  }

  void _subscribe() {
    _offDaysSub?.cancel();
    _offDaysSub = SupabaseService.getOffDaysStream().listen((data) {
      if (!mounted) return;
      // Filter for future off days only
      final today = DateTime.now().toIso8601String().substring(0, 10);
      final filtered = data.where((d) {
        final end = d['end_date']?.toString() ?? '';
        return end.compareTo(today) >= 0;
      }).toList()
        ..sort((a, b) => (a['start_date'] ?? '').toString().compareTo(b['start_date']?.toString() ?? ''));
      setState(() { _offDays = filtered; _loading = false; });
    }, onError: (_) {
      if (mounted) setState(() => _loading = false);
    });
  }

  Future<void> _add() async {
    setState(() => _saving = true);
    try {
      await SupabaseService.insertOffDay({
        'start_date': _startDate.toIso8601String().substring(0, 10),
        'end_date': _endDate.toIso8601String().substring(0, 10),
        'reason': _reasonCtrl.text.trim(),
        'created_by': SupabaseService.currentUser?.id,
      });
      _reasonCtrl.clear();
      _startDate = DateTime.now();
      _endDate = DateTime.now();
      setState(() => _showForm = false);
      if (mounted) showAppSnackbar(context, 'Off day added');
    } catch (e) {
      if (mounted) showAppSnackbar(context, friendlyError(e), isError: true);
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _delete(String id) async {
    try {
      await SupabaseService.deleteOffDay(id);
      if (mounted) showAppSnackbar(context, 'Removed');
    } catch (e) {
      if (mounted) showAppSnackbar(context, friendlyError(e), isError: true);
    }
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
      builder: _datePickerTheme,
    );
    if (picked != null) {
      setState(() {
        _startDate = picked;
        if (_endDate.isBefore(picked)) _endDate = picked;
      });
    }
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate,
      firstDate: _startDate,
      lastDate: DateTime(2030),
      builder: _datePickerTheme,
    );
    if (picked != null) setState(() => _endDate = picked);
  }

  Widget _datePickerTheme(BuildContext context, Widget? child) {
    return Theme(
      data: buildDatePickerTheme(context, Theme.of(context)),
      child: child!,
    );
  }

  String _formatDate(String dateStr) {
    try {
      return DateFormat('MMM d, yyyy').format(DateTime.parse(dateStr));
    } catch (_) {
      return dateStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colorsOf;

    if (_loading) {
      return ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: 4,
        itemBuilder: (_, __) => const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: ShimmerBox(height: 70),
        ),
      );
    }

    return Column(
      children: [
        // Info banner
        Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: c.warn.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: c.warn.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Icon(Icons.notifications_off_outlined, size: 14, color: c.warn),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Class reminders are paused on off days',
                  style: TextStyle(
                    color: c.warn.withValues(alpha: 0.85),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
        // Add button
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _showForm = !_showForm),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: _showForm ? c.bg3 : c.accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _showForm
                            ? c.border
                            : c.accent.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _showForm ? Icons.close : Icons.add,
                          size: 16,
                          color: _showForm ? c.muted : c.accent,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _showForm ? 'Cancel' : 'Add Off Day',
                          style: TextStyle(
                            color: _showForm ? c.muted : c.accent,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Add form
        if (_showForm)
          Flexible(
            fit: FlexFit.loose,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: c.bg2,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: c.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: _pickStartDate,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                          decoration: BoxDecoration(
                            color: c.bg3,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: c.border),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('FROM',
                                  style: TextStyle(
                                      color: c.muted,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700)),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(Icons.calendar_today,
                                      size: 14, color: c.accent),
                                  const SizedBox(width: 6),
                                  Text(
                                    _formatDate(_startDate
                                        .toIso8601String()
                                        .substring(0, 10)),
                                    style: TextStyle(
                                        color: c.white, fontSize: 13),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(Icons.arrow_forward,
                          color: c.muted, size: 16),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: _pickEndDate,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                          decoration: BoxDecoration(
                            color: c.bg3,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: c.border),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('TO',
                                  style: TextStyle(
                                      color: c.muted,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700)),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(Icons.calendar_today,
                                      size: 14, color: c.accent),
                                  const SizedBox(width: 6),
                                  Text(
                                    _formatDate(_endDate
                                        .toIso8601String()
                                        .substring(0, 10)),
                                    style: TextStyle(
                                        color: c.white, fontSize: 13),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: c.bg3,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: c.border),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: TextField(
                    controller: _reasonCtrl,
                    style: TextStyle(color: c.text, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Reason (e.g. Holiday, Exam Week...)',
                      hintStyle: TextStyle(
                          color: c.muted.withValues(alpha: 0.5), fontSize: 13),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _showForm = false),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: c.border),
                          ),
                          child: Center(
                            child: Text('Cancel',
                                style: TextStyle(
                                    color: c.muted, fontSize: 13)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GestureDetector(
                        onTap: _saving ? null : _add,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: c.accent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Center(
                            child: _saving
                                ? SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white),
                                  )
                                : Text('Save',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
            ),
          ),
        const SizedBox(height: 8),
        // Off days list
        Expanded(
          child: _offDays.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.event_busy,
                          size: 40, color: c.muted.withValues(alpha: 0.4)),
                      const SizedBox(height: 12),
                      Text('No off days scheduled',
                          style:
                              TextStyle(color: c.muted, fontSize: 14)),
                      Text('Add upcoming holidays or breaks',
                          style: TextStyle(
                              color: c.muted.withValues(alpha: 0.6),
                              fontSize: 12)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _offDays.length,
                  itemBuilder: (_, i) {
                    final d = _offDays[i];
                    final start = d['start_date']?.toString() ?? '';
                    final end = d['end_date']?.toString() ?? '';
                    final reason = d['reason']?.toString() ?? '';
                    final today = DateTime.now()
                        .toIso8601String()
                        .substring(0, 10);
                    final isActive = start.compareTo(today) <= 0 &&
                        today.compareTo(end) <= 0;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isActive
                            ? c.warn.withValues(alpha: 0.08)
                            : c.bg2,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isActive
                              ? c.warn.withValues(alpha: 0.3)
                              : c.border,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: isActive
                                  ? c.warn.withValues(alpha: 0.15)
                                  : c.bg3,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              isActive
                                  ? Icons.warning_amber
                                  : Icons.event,
                              color: isActive ? c.warn : c.muted,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      '${_formatDate(start)} – ${_formatDate(end)}',
                                      style: TextStyle(
                                        color: c.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    if (isActive) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: c.warn
                                              .withValues(alpha: 0.2),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: Text('NOW',
                                            style: TextStyle(
                                                color: c.warn,
                                                fontSize: 9,
                                                fontWeight: FontWeight.w700)),
                                      ),
                                    ],
                                  ],
                                ),
                                if (reason.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(reason,
                                      style: TextStyle(
                                          color: c.muted, fontSize: 12)),
                                ],
                              ],
                            ),
                          ),
                          if (widget.canEdit)
                            GestureDetector(
                              onTap: () =>
                                  _delete(d['id']?.toString() ?? ''),
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: c.danger.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Icon(Icons.delete_outline,
                                    size: 16, color: c.danger),
                              ),
                            ),
                        ],
                      ),
                    ).animate().fadeIn(
                      duration: 300.ms,
                      delay: Duration(milliseconds: (i * 40).clamp(0, 400)),
                    ).slideX(
                      begin: 0.04,
                      end: 0,
                      duration: 300.ms,
                      delay: Duration(milliseconds: (i * 40).clamp(0, 400)),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ─── Exams Tab ──────────────────────────────────────────────────────────────
class _ExamsTab extends StatefulWidget {
  final bool isAdmin;
  final bool canEdit;
  const _ExamsTab({required this.isAdmin, this.canEdit = true});

  @override
  State<_ExamsTab> createState() => _ExamsTabState();
}

class _ExamsTabState extends State<_ExamsTab> {
  List<Map<String, dynamic>> _exams = [];
  bool _loading = true;
  StreamSubscription<List<Map<String, dynamic>>>? _examsSub;

  // Add form state
  bool _showForm = false;
  Map<String, dynamic>? _editingExam;

  // Form controllers
  final _subjectCtrl = TextEditingController();
  final _subjectCodeCtrl = TextEditingController();
  final _roomCtrl = TextEditingController();
  final _teacherCtrl = TextEditingController();
  String _examType = 'Mid';
  DateTime _examDate = DateTime.now();
  TimeOfDay _startTime = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 11, minute: 0);
  int _semester = 1;
  bool _saving = false;

  static const _examTypes = ['Mid', 'Final', 'Class Test'];
  // Semester picker removed (defaults to 3rd)

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void dispose() {
    _examsSub?.cancel();
    _subjectCtrl.dispose();
    _subjectCodeCtrl.dispose();
    _roomCtrl.dispose();
    _teacherCtrl.dispose();
    super.dispose();
  }

  void _subscribe() {
    _examsSub?.cancel();
    _examsSub = SupabaseService.getExamsStream().listen((data) {
      if (!mounted) return;
      setState(() { _exams = data; _loading = false; });
    }, onError: (_) {
      if (mounted) setState(() => _loading = false);
    });
  }

  void _openForm([Map<String, dynamic>? exam]) {
    if (exam != null) {
      _editingExam = exam;
      _examType = exam['exam_type']?.toString() ?? 'Mid';
      _subjectCtrl.text = exam['subject']?.toString() ?? '';
      _subjectCodeCtrl.text = exam['subject_code']?.toString() ?? '';
      _roomCtrl.text = exam['room']?.toString() ?? '';
      _teacherCtrl.text = exam['teacher']?.toString() ?? '';
      _semester = int.tryParse(exam['semester']?.toString() ?? '3') ?? 3;
      if (exam['exam_date'] != null) {
        _examDate =
            DateTime.tryParse(exam['exam_date'].toString()) ?? DateTime.now();
      }
      if (exam['start_time'] != null) {
        _startTime = _parseTime(exam['start_time'].toString());
      }
      if (exam['end_time'] != null) {
        _endTime = _parseTime(exam['end_time'].toString());
      }
    } else {
      _editingExam = null;
      _examType = 'Mid';
      _subjectCtrl.clear();
      _subjectCodeCtrl.clear();
      _roomCtrl.clear();
      _teacherCtrl.clear();
      _semester = 3;
      _examDate = DateTime.now();
      _startTime = const TimeOfDay(hour: 9, minute: 0);
      _endTime = const TimeOfDay(hour: 11, minute: 0);
    }
    setState(() => _showForm = true);
  }

  void _cancelForm() {
    setState(() {
      _showForm = false;
      _editingExam = null;
    });
  }

  TimeOfDay _parseTime(String time) {
    try {
      final parts = time.split(':');
      return TimeOfDay(
          hour: int.parse(parts[0]),
          minute: int.parse(parts[1].substring(0, 2)));
    } catch (_) {
      return const TimeOfDay(hour: 9, minute: 0);
    }
  }

  String _formatTimeOfDay(TimeOfDay t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m:00';
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

  Future<void> _save() async {
    if (_subjectCtrl.text.trim().isEmpty) {
      showAppSnackbar(context, 'Subject is required', isError: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final data = {
        if (_editingExam != null) 'id': _editingExam!['id'],
        'exam_type': _examType,
        'subject': _subjectCtrl.text.trim(),
        'subject_code': _subjectCodeCtrl.text.trim(),
        'exam_date': _examDate.toIso8601String().substring(0, 10),
        'start_time': _formatTimeOfDay(_startTime),
        'end_time': _formatTimeOfDay(_endTime),
        'room': _roomCtrl.text.trim().isEmpty ? null : _roomCtrl.text.trim(),
        'teacher':
            _teacherCtrl.text.trim().isEmpty ? null : _teacherCtrl.text.trim(),
        'semester': _semester,
      };
      final wasEditing = _editingExam != null;
      await SupabaseService.upsertExam(data);
      _cancelForm();
      if (mounted) {
        showAppSnackbar(
            context, wasEditing ? 'Exam updated' : 'Exam added');
      }
    } catch (e) {
      if (mounted) showAppSnackbar(context, friendlyError(e), isError: true);
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _delete(String id) async {
    final c = context.colorsOf;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: c.bg2,
        title: Text('Delete Exam', style: TextStyle(color: c.white)),
        content: Text('This cannot be undone.',
            style: TextStyle(color: c.muted)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('Delete', style: TextStyle(color: c.danger))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await SupabaseService.deleteExam(id);
      if (mounted) showAppSnackbar(context, 'Exam deleted');
    } catch (e) {
      if (mounted) showAppSnackbar(context, friendlyError(e), isError: true);
    }
  }

  Future<void> _pickDate() async {
    final c = context.colors;
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
    final c = context.colors;
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _startTime : _endTime,
      builder: (ctx, child) => Theme(
        data: buildDatePickerTheme(ctx, Theme.of(ctx)),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startTime = picked;
        } else {
          _endTime = picked;
        }
      });
    }
  }

  Color _typeColor(String type, ThemeColors c) {
    switch (type) {
      case 'Mid':
        return c.warn;
      case 'Final':
        return c.accent;
      case 'Class Test':
        return c.accent3;
      default:
        return c.muted;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colorsOf;

    if (_loading) {
      return ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: 4,
        itemBuilder: (_, __) => const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: ShimmerBox(height: 70),
        ),
      );
    }

    return Column(
      children: [
        // Add button
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => _showForm ? _cancelForm() : _openForm(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: _showForm
                          ? c.bg3
                          : c.accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _showForm
                            ? c.border
                            : c.accent.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _showForm ? Icons.close : Icons.add,
                          size: 16,
                          color: _showForm ? c.muted : c.accent,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _showForm ? 'Cancel' : 'Add Exam',
                          style: TextStyle(
                            color: _showForm ? c.muted : c.accent,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Exam form
        if (_showForm)
          Flexible(
            fit: FlexFit.loose,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: c.bg2,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: c.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _editingExam != null ? 'Edit Exam' : 'Add Exam',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: c.white),
                    ),
                    const SizedBox(height: 16),
                    // Exam type
                    Text('EXAM TYPE',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: c.muted)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _examTypes.map((t) {
                        final sel = _examType == t;
                        return GestureDetector(
                          onTap: () => setState(() => _examType = t),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 7),
                            decoration: BoxDecoration(
                              color: sel
                                  ? c.accent.withValues(alpha: 0.15)
                                  : c.bg3,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color:
                                    sel ? c.accent : c.border,
                              ),
                            ),
                            child: Text(t,
                                style: TextStyle(
                                    color: sel ? c.accent : c.muted,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600)),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                    // Semester picker removed (defaults to 3rd semester)
                    const SizedBox(height: 12),
                    // Date and time
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: _pickDate,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('DATE',
                                    style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: c.muted)),
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: c.bg3,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: c.border),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.calendar_today_outlined,
                                          size: 14, color: c.muted),
                                      const SizedBox(width: 6),
                                      Text(
                                        DateFormat('MMM d, yyyy')
                                            .format(_examDate),
                                        style: TextStyle(
                                            color: c.text, fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => _pickTime(true),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('START',
                                    style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: c.muted)),
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: c.bg3,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: c.border),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.access_time,
                                          size: 14, color: c.muted),
                                      const SizedBox(width: 6),
                                      Text(
                                        _startTime.format(context),
                                        style: TextStyle(
                                            color: c.text, fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => _pickTime(false),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('END',
                                    style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: c.muted)),
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: c.bg3,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: c.border),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.access_time,
                                          size: 14, color: c.muted),
                                      const SizedBox(width: 6),
                                      Text(
                                        _endTime.format(context),
                                        style: TextStyle(
                                            color: c.text, fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Subject fields
                    Container(
                      decoration: BoxDecoration(
                        color: c.bg3,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: c.border),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: TextField(
                        controller: _subjectCtrl,
                        style: TextStyle(color: c.text, fontSize: 13),
                        decoration: const InputDecoration(
                          hintText: 'Subject',
                          border: InputBorder.none,
                          contentPadding:
                              EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: c.bg3,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: c.border),
                            ),
                            padding:
                                const EdgeInsets.symmetric(horizontal: 12),
                            child: TextField(
                              controller: _subjectCodeCtrl,
                              style:
                                  TextStyle(color: c.text, fontSize: 13),
                              decoration: const InputDecoration(
                                hintText: 'Subject Code',
                                border: InputBorder.none,
                                contentPadding:
                                    EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: c.bg3,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: c.border),
                            ),
                            padding:
                                const EdgeInsets.symmetric(horizontal: 12),
                            child: TextField(
                              controller: _roomCtrl,
                              style:
                                  TextStyle(color: c.text, fontSize: 13),
                              decoration: const InputDecoration(
                                hintText: 'Room',
                                border: InputBorder.none,
                                contentPadding:
                                    EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      decoration: BoxDecoration(
                        color: c.bg3,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: c.border),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: TextField(
                        controller: _teacherCtrl,
                        style: TextStyle(color: c.text, fontSize: 13),
                        decoration: const InputDecoration(
                          hintText: 'Teacher',
                          border: InputBorder.none,
                          contentPadding:
                              EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    GestureDetector(
                      onTap: _saving ? null : _save,
                      child: Container(
                        width: double.infinity,
                        padding:
                            const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: c.accent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: _saving
                              ? SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white),
                                )
                              : Text(
                                  _editingExam != null
                                      ? 'Update Exam'
                                      : 'Save Exam',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600),
                              ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(height: 8),
        // Exams list
        Expanded(
          child: _exams.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.edit_note,
                          size: 40, color: c.muted.withValues(alpha: 0.4)),
                      const SizedBox(height: 12),
                      Text('No exams scheduled',
                          style:
                              TextStyle(color: c.muted, fontSize: 14)),
                      Text('Add upcoming exams for each semester',
                          style: TextStyle(
                              color: c.muted.withValues(alpha: 0.6),
                              fontSize: 12)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _exams.length,
                  itemBuilder: (_, i) {
                    final exam = _exams[i];
                    final typeColor =
                        _typeColor(exam['exam_type']?.toString() ?? '', c);
                    final dateStr = exam['exam_date'] != null
                        ? DateFormat('MMM d, yyyy').format(
                            DateTime.tryParse(
                                    exam['exam_date'].toString()) ??
                                DateTime.now())
                        : 'TBD';
                    final semLabel = SupabaseService.semesterFromInt(
                        int.tryParse(exam['semester']?.toString() ?? ''));
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: c.bg2,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: typeColor.withValues(alpha: 0.15),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 3,
                            height: 48,
                            decoration: BoxDecoration(
                              color: typeColor,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                  exam['subject'] ?? '',
                                  style: TextStyle(
                                    color: c.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '$dateStr · ${_formatTime(exam['start_time']?.toString())} – ${_formatTime(exam['end_time']?.toString())}',
                                  style: TextStyle(
                                      color: c.muted, fontSize: 11),
                                ),
                                const SizedBox(height: 2),
                                Wrap(
                                  spacing: 6,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: typeColor
                                            .withValues(alpha: 0.15),
                                        borderRadius:
                                            BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        exam['exam_type']?.toString() ??
                                            '',
                                        style: TextStyle(
                                          color: typeColor,
                                          fontSize: 9,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: c.accent3
                                            .withValues(alpha: 0.12),
                                        borderRadius:
                                            BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        '$semLabel Sem',
                                        style: TextStyle(
                                          color: c.accent3,
                                          fontSize: 9,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    if (exam['subject_code']?.toString() !=
                                        null &&
                                        exam['subject_code']
                                            .toString()
                                            .isNotEmpty)
                                      Text(
                                        exam['subject_code'].toString(),
                                        style: TextStyle(
                                            color: c.muted,
                                            fontSize: 11),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          if (widget.canEdit) ...[
                            GestureDetector(
                              onTap: () => _openForm(exam),
                              child: Padding(
                                padding:
                                    const EdgeInsets.only(right: 8),
                                child: Icon(Icons.edit_outlined,
                                    size: 16, color: c.muted),
                              ),
                            ),
                            GestureDetector(
                              onTap: () =>
                                  _delete(exam['id'].toString()),
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: c.danger
                                      .withValues(alpha: 0.1),
                                  borderRadius:
                                      BorderRadius.circular(6),
                                ),
                                child: Icon(Icons.delete_outline,
                                    size: 16, color: c.danger),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ).animate().fadeIn(
                      duration: 300.ms,
                      delay: Duration(
                          milliseconds: (i * 40).clamp(0, 400)),
                    ).slideX(
                      begin: 0.04,
                      end: 0,
                      duration: 300.ms,
                      delay: Duration(
                          milliseconds: (i * 40).clamp(0, 400)),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

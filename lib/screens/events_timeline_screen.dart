import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import '../services/supabase_service.dart';
import '../services/cache_service.dart';
import '../utils/theme_provider.dart';
import '../widgets/common.dart';

// ─── Data Model for Timeline Items ───────────────────────────────────────────
class _TimelineItem {
  final String type; // 'event', 'exam', 'off_day'
  final String title;
  final String? description;
  final DateTime date;
  final DateTime? endDate;
  final String? time;
  final String? location;
  final String? subtitle;

  _TimelineItem({
    required this.type,
    required this.title,
    this.description,
    required this.date,
    this.endDate,
    this.time,
    this.location,
    this.subtitle,
  });
}

// ─── Timeline Screen ─────────────────────────────────────────────────────────
class EventsTimelineScreen extends StatefulWidget {
  const EventsTimelineScreen({super.key});

  @override
  State<EventsTimelineScreen> createState() => _EventsTimelineScreenState();
}

class _EventsTimelineScreenState extends State<EventsTimelineScreen> {
  List<_TimelineItem> _items = [];
  bool _loading = true;
  bool _isOffline = false;
  StreamSubscription<List<Map<String, dynamic>>>? _eventsSub;
  StreamSubscription<List<Map<String, dynamic>>>? _offDaysSub;
  StreamSubscription<List<Map<String, dynamic>>>? _examsSub;

  @override
  void initState() {
    super.initState();
    _loadCache();
    _subscribeAll();
  }

  void _loadCache() {
    // Try loading cached events
    if (!CacheService.isStale(CacheService.eventsKey)) {
      final cachedEvents = CacheService.loadList(CacheService.eventsKey);
      final cachedOffDays = CacheService.loadList(CacheService.offDaysKey);
      final cachedExams = CacheService.loadList(CacheService.examsKey);
      if ((cachedEvents != null && cachedEvents.isNotEmpty) ||
          (cachedOffDays != null && cachedOffDays.isNotEmpty) ||
          (cachedExams != null && cachedExams.isNotEmpty)) {
        _rebuildItems(cachedEvents, cachedOffDays, cachedExams);
        _loading = false;
      }
    }
  }

  @override
  void dispose() {
    _eventsSub?.cancel();
    _offDaysSub?.cancel();
    _examsSub?.cancel();
    super.dispose();
  }

  void _subscribeAll() {
    final today = DateTime.now().toIso8601String().substring(0, 10);

    // Events stream
    _eventsSub?.cancel();
    _eventsSub = SupabaseService.getEventsStream().listen((data) {
      final filtered = data.where((e) {
        final date = e['event_date']?.toString() ?? '';
        return date.compareTo(today) >= 0;
      }).toList();
      CacheService.saveList(CacheService.eventsKey, data);
      _isOffline = false;
      _rebuildItems(filtered, null, null);
    }, onError: (_) {
      if (mounted && _items.isEmpty) _loading = false;
      if (mounted && _items.isNotEmpty) _isOffline = true;
      _rebuildItems(null, null, null);
    });

    // Off days stream
    _offDaysSub?.cancel();
    _offDaysSub = SupabaseService.getOffDaysStream().listen((data) {
      final filtered = data.where((d) {
        final end = d['end_date']?.toString() ?? '';
        return end.compareTo(today) >= 0;
      }).toList();
      CacheService.saveList(CacheService.offDaysKey, data);
      _isOffline = false;
      _rebuildItems(null, filtered, null);
    }, onError: (_) {
      if (mounted && _items.isNotEmpty) _isOffline = true;
      _rebuildItems(null, null, null);
    });

    // Exams stream
    _examsSub?.cancel();
    _examsSub = SupabaseService.getExamsStream().listen((data) {
      CacheService.saveList(CacheService.examsKey, data);
      _isOffline = false;
      _rebuildItems(null, null, data);
    }, onError: (_) {
      if (mounted && _items.isNotEmpty) _isOffline = true;
      _rebuildItems(null, null, null);
    });
  }

  void _rebuildItems(List<Map<String, dynamic>>? events,
      List<Map<String, dynamic>>? offDays, List<Map<String, dynamic>>? exams) {
    if (!mounted) return;

    final items = <_TimelineItem>[];

    if (events != null) {
      for (final ev in events) {
        final dateStr = ev['event_date']?.toString() ?? '';
        final date = DateTime.tryParse(dateStr);
        if (date == null) continue;
        items.add(_TimelineItem(
          type: 'event',
          title: ev['title']?.toString() ?? 'Event',
          description: ev['description']?.toString(),
          date: date,
          time: ev['event_time']?.toString(),
          location: ev['location']?.toString(),
          subtitle: ev['event_type']?.toString(),
        ));
      }
    } else {
      items.addAll(_items.where((i) => i.type == 'event'));
    }

    if (offDays != null) {
      for (final off in offDays) {
        final startStr = off['start_date']?.toString() ?? '';
        final endStr = off['end_date']?.toString() ?? '';
        final start = DateTime.tryParse(startStr);
        final end = DateTime.tryParse(endStr);
        if (start == null) continue;
        items.add(_TimelineItem(
          type: 'off_day',
          title: off['reason']?.toString() ?? 'College Off',
          date: start,
          endDate: end,
          subtitle: 'Holiday',
        ));
      }
    } else {
      items.addAll(_items.where((i) => i.type == 'off_day'));
    }

    if (exams != null) {
      for (final exam in exams) {
        final dateStr = exam['exam_date']?.toString() ?? '';
        final date = DateTime.tryParse(dateStr);
        if (date == null) continue;
        final semester = exam['semester'];
        final semLabel = semester != null
            ? SupabaseService.semesterFromInt(int.tryParse(semester.toString()))
            : '';
        items.add(_TimelineItem(
          type: 'exam',
          title: exam['subject']?.toString() ?? 'Exam',
          date: date,
          time:
              '${_fmtTime(exam['start_time']?.toString())} - ${_fmtTime(exam['end_time']?.toString())}',
          subtitle: '${exam['exam_type'] ?? 'Exam'}${semLabel.isNotEmpty ? ' - $semLabel Sem' : ''}',
        ));
      }
    } else {
      items.addAll(_items.where((i) => i.type == 'exam'));
    }

    items.sort((a, b) => a.date.compareTo(b.date));
    setState(() { _items = items; _loading = false; });
  }

  String _fmtTime(String? t) {
    if (t == null || t.isEmpty) return '';
    try {
      final parts = t.split(':');
      final h = int.parse(parts[0]);
      final m = parts.length > 1 ? parts[1].substring(0, 2) : '00';
      final period = h >= 12 ? 'PM' : 'AM';
      final h12 = h > 12 ? h - 12 : (h == 0 ? 12 : h);
      return '$h12:$m $period';
    } catch (_) {
      return t;
    }
  }

  // Helpers
  Color _typeColor(String type, ThemeColors c) {
    switch (type) {
      case 'event':
        return c.accentOrange;
      case 'exam':
        return c.accent;
      case 'off_day':
        return c.warn;
      default:
        return c.muted;
    }
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'event':
        return Icons.event;
      case 'exam':
        return Icons.edit_note;
      case 'off_day':
        return Icons.event_busy;
      default:
        return Icons.circle;
    }
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'event':
        return 'EVENT';
      case 'exam':
        return 'EXAM';
      case 'off_day':
        return 'HOLIDAY';
      default:
        return type.toUpperCase();
    }
  }

  String _formatDate(DateTime d) {
    return DateFormat('MMM d').format(d);
  }

  String _formatMonth(DateTime d) {
    return DateFormat('MMMM yyyy').format(d).toUpperCase();
  }

  bool _isSameMonth(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month;
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
        title: Text('Upcoming Events',
            style: TextStyle(fontWeight: FontWeight.w700, color: c.white)),
      ),
      body: Column(
        children: [
          ConnectivityBanners(
            isOffline: _isOffline,
            onRefresh: () async => _subscribeAll(),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => _subscribeAll(),
              color: c.accent,
              backgroundColor: c.bg2,
              child: _loading
          ? ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: 5,
              itemBuilder: (_, __) => const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: ShimmerBox(height: 80),
              ),
            )
          : _items.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: const [
                    SizedBox(height: 200),
                    Center(
                      child: EmptyState(
                        icon: Icons.event,
                        title: 'No upcoming events',
                        subtitle: 'Nothing scheduled at this time.',
                      ),
                    ),
                  ],
                )
              : ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  itemCount: _items.length,
                  itemBuilder: (_, i) {
                    final item = _items[i];
                    final color = _typeColor(item.type, c);
                    final icon = _typeIcon(item.type);
                    final label = _typeLabel(item.type);

                    // Determine if this is the start of a new month
                    final showMonth =
                        i == 0 || !_isSameMonth(item.date, _items[i - 1].date);

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (showMonth) ...[
                          const SizedBox(height: 16),
                          // Month header
                          Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                              decoration: BoxDecoration(
                                color: c.bg3,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: c.border),
                              ),
                              child: Text(
                                _formatMonth(item.date),
                                style: TextStyle(
                                  color: c.muted,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.5,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        // Timeline item row
                        IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Timeline bar + dot
                              SizedBox(
                                width: 32,
                                child: Column(
                                  children: [
                                    // Dot
                                    Container(
                                      width: 14,
                                      height: 14,
                                      margin: const EdgeInsets.only(top: 6),
                                      decoration: BoxDecoration(
                                        color: color,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: c.bg2,
                                          width: 2.5,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: color.withValues(alpha: 0.3),
                                            blurRadius: 6,
                                            spreadRadius: 1,
                                          ),
                                        ],
                                      ),
                                    ),
                                    // Line connecting to next item
                                    Expanded(
                                      child: Container(
                                        width: 2,
                                        margin: const EdgeInsets.symmetric(vertical: 2),
                                        decoration: BoxDecoration(
                                          color: c.border.withValues(alpha: 0.3),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Card
                              Expanded(
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: c.bg2,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: color.withValues(alpha: 0.15),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Top row: type badge + date
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: color.withValues(alpha: 0.12),
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(
                                                color: color.withValues(alpha: 0.2),
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(icon, size: 10, color: color),
                                                const SizedBox(width: 4),
                                                Text(
                                                  label,
                                                  style: TextStyle(
                                                    color: color,
                                                    fontSize: 9,
                                                    fontWeight: FontWeight.w800,
                                                    letterSpacing: 0.8,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const Spacer(),
                                          Text(
                                            _formatDate(item.date),
                                            style: TextStyle(
                                              color: color,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      // Title
                                      Text(
                                        item.title,
                                        style: TextStyle(
                                          color: c.white,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          height: 1.2,
                                        ),
                                      ),
                                      // Subtitle (type-specific info)
                                      if (item.subtitle != null && item.subtitle!.isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          item.subtitle!,
                                          style: TextStyle(
                                            color: c.muted.withValues(alpha: 0.8),
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                      const SizedBox(height: 6),
                                      // Info row
                                      Row(
                                        children: [
                                          if (item.time != null && item.time!.isNotEmpty && item.time != ' - ') ...[
                                            Icon(Icons.access_time, size: 11, color: color.withValues(alpha: 0.6)),
                                            const SizedBox(width: 3),
                                            Flexible(
                                              child: Text(
                                                item.time!,
                                                style: TextStyle(
                                                  color: c.muted,
                                                  fontSize: 10,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                          ],
                                          if (item.endDate != null && item.endDate != item.date)
                                            Text(
                                              '-> ${_formatDate(item.endDate!)}',
                                              style: TextStyle(
                                                color: c.muted,
                                                fontSize: 10,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          if (item.location != null && item.location!.isNotEmpty) ...[
                                            const Spacer(),
                                            Icon(Icons.location_on, size: 11, color: color.withValues(alpha: 0.5)),
                                            const SizedBox(width: 2),
                                            Flexible(
                                              child: Text(
                                                item.location!,
                                                style: TextStyle(
                                                  color: c.muted,
                                                  fontSize: 10,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      // Description
                                      if (item.description != null && item.description!.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 6),
                                          child: Text(
                                            item.description!,
                                            style: TextStyle(
                                              color: c.text.withValues(alpha: 0.7),
                                              fontSize: 11,
                                              height: 1.4,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                    ],
                                  ),
                                ).animate().fadeIn(
                                  duration: 350.ms,
                                  delay: Duration(milliseconds: (i * 50).clamp(0, 500)),
                                ).slideX(
                                  begin: 0.04,
                                  end: 0,
                                  duration: 350.ms,
                                  delay: Duration(milliseconds: (i * 50).clamp(0, 500)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
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

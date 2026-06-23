import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/routine_service.dart';
import '../services/supabase_service.dart';
import '../services/cache_service.dart';
import '../utils/theme_provider.dart';
import '../utils/responsive.dart';
import '../widgets/common.dart';
import 'notices_screen.dart';
import 'notes_screen.dart';
import 'routine_screen.dart';
import 'students_screen.dart';
import 'teachers_screen.dart';
import 'profile_screen.dart';
import 'events_timeline_screen.dart';
import 'student_attendance_screen.dart';
import 'exam_routine_screen.dart';
import '../utils/page_transitions.dart';

class StudentHomeScreen extends StatefulWidget {
  final Map<String, dynamic> profile;
  const StudentHomeScreen({super.key, required this.profile});

  @override
  State<StudentHomeScreen> createState() => _StudentHomeScreenState();
}

class _StudentHomeScreenState extends State<StudentHomeScreen> {
  int _tab = 0;
  DateTime? _lastBackPress;
  bool _navVisible = true;
  Timer? _hideTimer;
  final ValueNotifier<int> _unreadNotifier = ValueNotifier<int>(0);

  late final List<Widget> _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = [
      _HomeTab(profile: widget.profile, unreadNotifier: _unreadNotifier),
      const NoticesScreen(isAdmin: false),
      NotesScreen(
          isAdmin: false,
          defaultSemester: int.tryParse(widget.profile['semester']?.toString() ?? ''),
        ),
      RoutineScreen(
        isAdmin: false,
        initialSemester: RoutineService.profileSemester(widget.profile),
      ),
      ProfileScreen(profile: widget.profile),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_tab != 0) {
          setState(() => _tab = 0);
        } else {
          final now = DateTime.now();
          if (_lastBackPress == null || now.difference(_lastBackPress!) > const Duration(seconds: 2)) {
            _lastBackPress = now;
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(const SnackBar(
                content: Text('Press back again to exit'),
                duration: Duration(seconds: 2),
              ));
          } else {
            SystemNavigator.pop();
          }
        }
      },
      child: Scaffold(
      extendBody: true,
      backgroundColor: c.bg,
      body: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification is ScrollUpdateNotification) {
            final delta = notification.scrollDelta ?? 0;
            if (delta > 2) {
              _hideTimer ??= Timer(const Duration(milliseconds: 500), () {
                _hideTimer = null;
                if (mounted) setState(() => _navVisible = false);
              });
            } else if (delta < -2) {
              _hideTimer?.cancel();
              _hideTimer = null;
              if (!_navVisible) setState(() => _navVisible = true);
            }
          }
          if (notification is ScrollEndNotification) {
            _hideTimer?.cancel();
            _hideTimer = null;
          }
          return false;
        },
        child: AnimatedTabSwitcher(currentIndex: _tab, children: _tabs),
      ),
      bottomNavigationBar: FloatingBottomNav(
        isVisible: _navVisible,
        currentIndex: _tab,
        onTap: (i) => setState(() {
          _tab = i;
          _navVisible = true;
          _hideTimer?.cancel();
          _hideTimer = null;
          if (i == 1) CacheService.markViewed(CacheService.unreadNoticesKey);
          if (i == 2) CacheService.markViewed(CacheService.unreadNotesKey);
          _unreadNotifier.value++;
        }),
        items: [
          const BottomNavigationBarItem(icon: Icon(Icons.home_outlined), activeIcon: Icon(Icons.home), label: ''),
          BottomNavigationBarItem(icon: Icon(Icons.campaign_outlined), activeIcon: Icon(Icons.campaign), label: ''),
          BottomNavigationBarItem(icon: Icon(Icons.menu_book_outlined), activeIcon: Icon(Icons.menu_book), label: ''),
          const BottomNavigationBarItem(icon: Icon(Icons.schedule_outlined), activeIcon: Icon(Icons.schedule), label: ''),
          const BottomNavigationBarItem(icon: Icon(Icons.person_outline), activeIcon: Icon(Icons.person), label: ''),
        ],
      ),
    ),
    );
  }
  @override
  void dispose() {
    _hideTimer?.cancel();
    _unreadNotifier.dispose();
    super.dispose();
  }
}

// ── Home Tab ─────────────────────────────────────────────────────────────────
class _HomeTab extends StatefulWidget {
  final Map<String, dynamic> profile;
  final ValueNotifier<int> unreadNotifier;
  const _HomeTab({required this.profile, required this.unreadNotifier});

  @override
  State<_HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<_HomeTab> {
  List<Map<String, dynamic>> _recentNotices = [];
  List<Map<String, dynamic>> _allNotices = [];
  List<Map<String, dynamic>> _allNotes = [];
  List<Map<String, dynamic>> _allEvents = [];
  bool _initialLoading = true;
  bool _isOffline = false;
  StreamSubscription<List<Map<String, dynamic>>>? _noticesSub;
  StreamSubscription<List<Map<String, dynamic>>>? _notesSub;
  StreamSubscription<List<Map<String, dynamic>>>? _eventsSub;

  DateTime? _lastViewedNotices;
  DateTime? _lastViewedNotes;
  DateTime? _lastViewedEvents;

  bool _hasUnreadNotices = false;
  bool _hasUnreadNotes = false;
  bool _hasUnreadEvents = false;

  @override
  void initState() {
    super.initState();
    final sem = int.tryParse(widget.profile['semester']?.toString() ?? '');

    if (!CacheService.isStale(CacheService.noticesKey)) {
      final cached = CacheService.loadList(CacheService.noticesKey);
      if (cached != null && cached.isNotEmpty) {
        _allNotices = cached;
        _recentNotices = cached.take(3).toList();
        _initialLoading = false;
      }
    }
    final cachedNotes = CacheService.loadList(CacheService.notesKey(sem));
    if (cachedNotes != null) _allNotes = cachedNotes;
    final cachedEvents = CacheService.loadList(CacheService.eventsKey);
    if (cachedEvents != null) _allEvents = cachedEvents;

    _restoreLastViewed();
    _recomputeUnread();

    _noticesSub = SupabaseService.getNoticesStream().listen((data) {
      if (mounted) {
        _allNotices = data;
        _recentNotices = data.take(3).toList();
        _initialLoading = false;
        _recomputeUnread();
      if (mounted) setState(() { _isOffline = false; });
        CacheService.saveList(CacheService.noticesKey, data);
      }
    }, onError: (_) {
      if (mounted) setState(() { _initialLoading = false; _isOffline = true; });
    });

    _notesSub = SupabaseService.getNotesStream(semester: sem).listen((data) {
      if (mounted) {
        _allNotes = data;
        _recomputeUnread();
        if (mounted) setState(() { _isOffline = false; });
        CacheService.saveList(CacheService.notesKey(sem), data);
      }
    }, onError: (_) {
      if (mounted) setState(() => _isOffline = true);
    });

    _eventsSub = SupabaseService.getEventsStream().listen((data) {
      if (mounted) {
        _allEvents = data;
        _recomputeUnread();
        if (mounted) setState(() { _isOffline = false; });
        CacheService.saveList(CacheService.eventsKey, data);
      }
    }, onError: (_) {
      if (mounted) setState(() => _isOffline = true);
    });
  }

  @override
  void dispose() {
    _noticesSub?.cancel();
    _notesSub?.cancel();
    _eventsSub?.cancel();
    super.dispose();
  }

  void _restoreLastViewed() {
    _lastViewedNotices = _ts(CacheService.unreadNoticesKey) ?? DateTime.now();
    _lastViewedNotes = _ts(CacheService.unreadNotesKey) ?? DateTime.now();
    _lastViewedEvents = _ts(CacheService.unreadEventsKey) ?? DateTime.now();
  }

  DateTime? _ts(String key) {
    final raw = CacheService.getRaw(key);
    return raw != null ? DateTime.tryParse(raw) : null;
  }

  bool _anyNewer(
    List<Map<String, dynamic>> list,
    DateTime? lastViewed, {
    String field = 'created_at',
  }) {
    if (list.isEmpty) return false;
    if (lastViewed == null) return true;
    for (final item in list) {
      final ts = DateTime.tryParse(item[field]?.toString() ?? '');
      if (ts != null && ts.isAfter(lastViewed)) return true;
    }
    return false;
  }

  void _recomputeUnread() {
    _hasUnreadNotices = _anyNewer(_allNotices, _lastViewedNotices);
    _hasUnreadNotes = _anyNewer(_allNotes, _lastViewedNotes);
    _hasUnreadEvents = _anyNewer(_allEvents, _lastViewedEvents);
  }

  void _markNoticesViewed() {
    _lastViewedNotices = DateTime.now();
    _hasUnreadNotices = false;
    CacheService.markViewed(CacheService.unreadNoticesKey);
  }

  void _markNotesViewed() {
    _lastViewedNotes = DateTime.now();
    _hasUnreadNotes = false;
    CacheService.markViewed(CacheService.unreadNotesKey);
  }

  void _markEventsViewed() {
    _lastViewedEvents = DateTime.now();
    _hasUnreadEvents = false;
    CacheService.markViewed(CacheService.unreadEventsKey);
  }

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final name = widget.profile['name'] ?? 'Student';
    final semester = SupabaseService.semesterFromInt(int.tryParse(widget.profile['semester']?.toString() ?? ''));

    final hasUnreadNotices = _hasUnreadNotices;
    final hasUnreadNotes = _hasUnreadNotes;
    final hasUnreadEvents = _hasUnreadEvents;

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [c.accent.withValues(alpha: 0.12), c.accent.withValues(alpha: 0.01)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
        title: Row(
          children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [c.accent, c.accentDim]),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Center(child: Icon(Icons.school, color: Colors.white, size: 16)),
            ),
            const SizedBox(width: 10),
            Text('CST Portal', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.white)),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.logout, color: c.danger),
            tooltip: 'Sign out',
            onPressed: () async {
              await SupabaseService.signOut();
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          Responsive.screenPadding(context),
          Responsive.screenPadding(context),
          Responsive.screenPadding(context),
          Responsive.screenPadding(context) + 88,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Greeting Card
            GestureDetector(
              onTap: () => _navigateToStudents(context, 4),
              child: AppCard(
                borderColor: c.accentOrange.withValues(alpha: c.isLight ? 0.2 : 0.3),
                color: c.isLight ? c.bg2 : null,
                gradient: c.isLight
                    ? null
                    : LinearGradient(
                        colors: [c.accentOrange.withValues(alpha: 0.06), c.accentOrange.withValues(alpha: 0.01)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                child: Row(
                  children: [
                    Container(
                      width: 60, height: 60,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [c.accentOrange, Color.lerp(c.accentOrange, Colors.black, 0.35)!]),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Center(
                        child: Text(
                          (name.isNotEmpty ? name[0] : '?').toUpperCase(),
                          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_greeting, style: TextStyle(color: c.accentOrange.withValues(alpha: 0.75), fontSize: 11, fontWeight: FontWeight.w700)),
                          Text(name, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: c.white)),
                          Text('$semester Semester · CST', style: TextStyle(color: c.muted, fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Quick Actions
            const SectionTitle(title: 'Quick Access', icon: Icons.flash_on, centered: true),
            const SizedBox(height: 16),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: Responsive.gridColumns(context, small: 2, medium: 3, large: 4),
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 1.3,
              children: [
                _QuickCard(icon: Icons.campaign, label: 'Notices', color: c.accentOrange.withValues(alpha: 0.75), index: 0,
                  hasUnread: hasUnreadNotices,
                  onTap: () {
                    setState(() {
                      _markNoticesViewed();
                    });
                    _navigateToStudents(context, 1);
                  }),
                _QuickCard(icon: Icons.menu_book, label: 'Notes', color: c.accentOrange.withValues(alpha: 0.75), index: 1,
                  hasUnread: hasUnreadNotes,
                  onTap: () {
                    setState(() {
                      _markNotesViewed();
                    });
                    _navigateToStudents(context, 2);
                  }),
                _QuickCard(icon: Icons.calendar_month, label: 'Routine', color: c.accentOrange.withValues(alpha: 0.75), index: 2,
                  onTap: () => _navigateToStudents(context, 3)),
                _QuickCard(icon: Icons.people, label: 'Students', color: c.accentOrange.withValues(alpha: 0.75), index: 3,
                  onTap: () => Navigator.push(context, buildCupertinoRoute(const StudentsScreen(isAdmin: false)))),
                _QuickCard(icon: Icons.group, label: 'Teachers', color: c.accentOrange.withValues(alpha: 0.75), index: 4,
                  onTap: () => Navigator.push(context, buildCupertinoRoute(const TeachersScreen(isAdmin: false)))),
                _QuickCard(icon: Icons.checklist, label: 'Attendance', color: c.accentOrange.withValues(alpha: 0.75), index: 5,
                  onTap: () => Navigator.push(context, buildCupertinoRoute(StudentAttendanceScreen(profile: widget.profile)))),
                _QuickCard(icon: Icons.person, label: 'My Profile', color: c.accentOrange.withValues(alpha: 0.75), index: 6,
                  onTap: () => _navigateToStudents(context, 4)),
                _QuickCard(icon: Icons.event, label: 'Events', color: c.accentOrange.withValues(alpha: 0.75), index: 7,
                  hasUnread: hasUnreadEvents,
                  onTap: () {
                    setState(() {
                      _markEventsViewed();
                    });
                    Navigator.push(context, buildCupertinoRoute(
                      const EventsTimelineScreen(),
                    ));
                  }),
                _QuickCard(icon: Icons.quiz_outlined, label: 'Exams', color: c.accentOrange.withValues(alpha: 0.75), index: 8,
                  onTap: () => Navigator.push(context, buildCupertinoRoute(
                    ExamRoutineScreen(
                      isAdmin: false,
                      semester: int.tryParse(widget.profile['semester']?.toString() ?? '') ?? 1,
                    ),
                  ))),
              ],
            ),
            const SizedBox(height: 24),

            // Recent Notices
            SectionTitle(
              title: 'Recent Notices',
              trailing: TextButton(
                onPressed: () {
                  setState(() {
                    _markNoticesViewed();
                  });
                  _navigateToStudents(context, 1);
                },
                child: Text('See all', style: TextStyle(color: c.accent, fontSize: 12)),
              ),
            ),
            const SizedBox(height: 12),
            if (_initialLoading)
              ...List.generate(3, (_) => const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: ShimmerBox(height: 80),
              ))
            else if (_recentNotices.isEmpty)
              const EmptyState(icon: Icons.mail_outline, title: 'No notices yet', subtitle: 'Check back later')
            else
              ..._recentNotices.map((n) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _NoticePreview(notice: n),
              )),
          ],
        ),
      ),
    );
  }

  void _navigateToStudents(BuildContext context, int tab) {
    final state = context.findAncestorStateOfType<_StudentHomeScreenState>();
    state?.setState(() => state._tab = tab);
  }
}

// ── Quick Action Card ────────────────────────────────────────────────────────
class _QuickCard extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;
  final int index;
  final VoidCallback onTap;
  final bool hasUnread;

  const _QuickCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.index,
    required this.onTap,
    this.hasUnread = false,
  });

  @override
  State<_QuickCard> createState() => _QuickCardState();
}

class _QuickCardState extends State<_QuickCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: 250.ms,
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          decoration: BoxDecoration(
            color: c.bg2,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: _isHovered ? widget.color : widget.color.withValues(alpha: 0.25),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: _isHovered ? 0.15 : 0.02),
                blurRadius: _isHovered ? 16 : 4,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(widget.icon, size: 24, color: widget.color),
                  if (widget.hasUnread)
                    Positioned(
                      right: -4,
                      top: -4,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          color: Color(0xFFC62828),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                widget.label,
                style: TextStyle(
                  color: widget.color,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    ).animate(
      delay: Duration(milliseconds: (widget.index * 70).clamp(0, 600)),
    ).fadeIn(
      duration: 350.ms,
    ).scale(
      begin: const Offset(0.9, 0.9),
      end: const Offset(1, 1),
      duration: 350.ms,
      curve: Curves.easeOutBack,
    );
  }
}

// ── Notice Preview ───────────────────────────────────────────────────────────
class _NoticePreview extends StatelessWidget {
  final Map<String, dynamic> notice;
  const _NoticePreview({required this.notice});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      color: c.bg3,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: c.warn.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.campaign, color: c.warn, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(notice['title'] ?? '',
                    style: GoogleFonts.dmSans(
                      textStyle: TextStyle(
                          color: c.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          letterSpacing: 0),
                    )),
                const SizedBox(height: 4),
                Text(notice['description'] ?? '',
                    style: GoogleFonts.dmSans(
                      textStyle:
                          TextStyle(color: c.muted, fontSize: 12, letterSpacing: 0),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

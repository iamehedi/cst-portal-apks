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
import '../widgets/theme_picker.dart';
import 'notices_screen.dart';
import 'notes_screen.dart';
import 'students_screen.dart';
import 'teachers_screen.dart';
import 'routine_screen.dart';
import 'events_editor_screen.dart';
import '../widgets/attendance_launcher.dart';
import '../utils/page_transitions.dart';
import 'attendance_report_screen.dart';
import 'admin_teacher_profile_screen.dart';

class TeacherDashboardScreen extends StatefulWidget {
  final Map<String, dynamic> profile;
  const TeacherDashboardScreen({super.key, required this.profile});

  @override
  State<TeacherDashboardScreen> createState() => _TeacherDashboardScreenState();
}

class _TeacherDashboardScreenState extends State<TeacherDashboardScreen> {
  int _tab = 0;
  DateTime? _lastBackPress;
  bool _navVisible = true;
  Timer? _hideTimer;

  late final List<Widget> _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = [
      _TeacherOverview(profile: widget.profile),
      const NotesScreen(isAdmin: true),
      const NoticesScreen(isAdmin: true),
      const StudentsScreen(isAdmin: false, isTeacher: true),
      AttendanceLauncher(profile: widget.profile),
      AdminTeacherProfileScreen(profile: widget.profile, isAdmin: false),
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
              // Scrolling down — schedule hide with delay
              _hideTimer ??= Timer(const Duration(milliseconds: 500), () {
                _hideTimer = null;
                if (mounted) setState(() => _navVisible = false);
              });
            } else if (delta < -2) {
              // Scrolling up — show immediately, cancel pending hide
              _hideTimer?.cancel();
              _hideTimer = null;
              if (!_navVisible) setState(() => _navVisible = true);
            }
          }
          if (notification is ScrollEndNotification) {
            // Cancel pending hide timer so stopping doesn't trigger hide
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
        }),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined), activeIcon: Icon(Icons.home), label: ''),
          BottomNavigationBarItem(icon: Icon(Icons.menu_book_outlined), activeIcon: Icon(Icons.menu_book), label: ''),
          BottomNavigationBarItem(icon: Icon(Icons.campaign_outlined), activeIcon: Icon(Icons.campaign), label: ''),
          BottomNavigationBarItem(icon: Icon(Icons.people_outline), activeIcon: Icon(Icons.people), label: ''),
          BottomNavigationBarItem(icon: Icon(Icons.checklist_outlined), activeIcon: Icon(Icons.checklist), label: ''),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline), activeIcon: Icon(Icons.person), label: ''),
        ],
      ),
    ),
    );
  }
}

class _TeacherOverview extends StatefulWidget {
  final Map<String, dynamic> profile;
  const _TeacherOverview({required this.profile});

  @override
  State<_TeacherOverview> createState() => _TeacherOverviewState();
}

class _TeacherOverviewState extends State<_TeacherOverview> {
  List<Map<String, dynamic>> _recentNotices = [];
  bool _initialLoading = true;
  StreamSubscription<List<Map<String, dynamic>>>? _noticesSub;

  @override
  void initState() {
    super.initState();
    if (!CacheService.isStale(CacheService.noticesKey)) {
      final cached = CacheService.loadList(CacheService.noticesKey);
      if (cached != null && cached.isNotEmpty) {
        _recentNotices = cached.take(3).toList();
        _initialLoading = false;
      }
    }
    _noticesSub = SupabaseService.getNoticesStream().listen((data) {
      if (mounted) {
        setState(() {
          _recentNotices = data.take(3).toList();
          _initialLoading = false;
        });
        CacheService.saveList(CacheService.noticesKey, data);
      }
    }, onError: (_) {
      if (mounted) setState(() => _initialLoading = false);
    });
  }

  @override
  void dispose() {
    _noticesSub?.cancel();
    super.dispose();
  }

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  void _navigateToTab(BuildContext context, int tab) {
    final state = context.findAncestorStateOfType<_TeacherDashboardScreenState>();
    state?.setState(() => state._tab = tab);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final name = widget.profile['name'] ?? 'Teacher';
    final subject = widget.profile['subject'] ?? '';

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [c.accent3.withValues(alpha: 0.12), c.accent3.withValues(alpha: 0.01)],
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
                gradient: LinearGradient(colors: [c.accent3, c.accent3]),
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
            icon: Icon(Icons.palette_outlined, color: c.accent),
            tooltip: 'Theme',
            onPressed: () => showThemePicker(context),
          ),
          IconButton(
            icon: Icon(Icons.logout, color: c.danger),
            tooltip: 'Sign out',
            onPressed: () async { await SupabaseService.signOut(); },
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
            AppCard(
              borderColor: c.accentOrange.withValues(alpha: c.isLight ? 0.2 : 0.4),
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
                        Text('Faculty · ${subject.isNotEmpty ? subject : 'CST Department'}', style: TextStyle(color: c.muted, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn(duration: 400.ms, curve: Curves.easeOut).scale(begin: const Offset(0.96, 0.96), duration: 400.ms, curve: Curves.easeOutBack),
            const SizedBox(height: 24),

            // Quick Actions
            const SectionTitle(title: 'Quick Access', icon: Icons.flash_on, centered: true),
            const SizedBox(height: 16),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: Responsive.gridColumns(context, small: 2, medium: 3, large: 4),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.8,
              children: [
                _TeacherQuickCard(icon: Icons.menu_book, label: 'Notes', color: c.accentOrange.withValues(alpha: 0.75), index: 0,
                  onTap: () => _navigateToTab(context, 1)),
                _TeacherQuickCard(icon: Icons.campaign, label: 'Notices', color: c.accentOrange.withValues(alpha: 0.75), index: 1,
                  onTap: () => _navigateToTab(context, 2)),
                _TeacherQuickCard(icon: Icons.people, label: 'Students', color: c.accentOrange.withValues(alpha: 0.75), index: 2,
                  onTap: () => _navigateToTab(context, 3)),
                _TeacherQuickCard(icon: Icons.person, label: 'Teachers', color: c.accentOrange.withValues(alpha: 0.75), index: 3,
                  onTap: () => Navigator.push(context, buildCupertinoRoute(const TeachersScreen(isAdmin: false)))),
                _TeacherQuickCard(icon: Icons.calendar_month, label: 'Routine', color: c.accentOrange.withValues(alpha: 0.75), index: 4,
                  onTap: () => Navigator.push(context, buildCupertinoRoute(
                    RoutineScreen(
                      isAdmin: false,
                      initialSemester: RoutineService.profileSemester(widget.profile),
                    ),
                  ))),
                _TeacherQuickCard(icon: Icons.checklist, label: 'Attendance', color: c.accentOrange.withValues(alpha: 0.75), index: 5,
                  onTap: () => _navigateToTab(context, 4)),
                _TeacherQuickCard(icon: Icons.event, label: 'Events', color: c.accentOrange.withValues(alpha: 0.75), index: 6,
                  onTap: () => Navigator.push(context, buildCupertinoRoute(
                    const EventsEditorScreen(isAdmin: false),
                  ))),
                _TeacherQuickCard(icon: Icons.bar_chart, label: 'Attendance Reports', color: c.accentOrange.withValues(alpha: 0.75), index: 7,
                  onTap: () => Navigator.push(context,
                    buildCupertinoRoute(const AttendanceReportScreen()))),
                _TeacherQuickCard(icon: Icons.person, label: 'My Profile', color: c.accentOrange.withValues(alpha: 0.75), index: 8,
                  onTap: () => _navigateToTab(context, 5)),
              ],
            ),
            const SizedBox(height: 24),

            // Recent Notices
            SectionTitle(
              title: 'Recent Notices',
              trailing: TextButton(
                onPressed: () => _navigateToTab(context, 2),
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
                child: _TeacherNoticePreview(notice: n),
              )),
          ],
        ),
      ),
    );
  }
}

class _TeacherQuickCard extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;
  final int index;
  final VoidCallback onTap;

  const _TeacherQuickCard({required this.icon, required this.label, required this.color, required this.index, required this.onTap});

  @override
  State<_TeacherQuickCard> createState() => _TeacherQuickCardState();
}

class _TeacherQuickCardState extends State<_TeacherQuickCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: RepaintBoundary(
        child: AnimatedContainer(
          duration: 250.ms,
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SizedBox(height: 4),
              // Prominent Action Icon
              Icon(
                widget.icon,
                size: 32,
                color: widget.color,
              ),
              const SizedBox(height: 4),

              // Custom Typography matching mockup accent colors
              Text(
                widget.label,
                style: TextStyle(
                  color: widget.color,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),

              // Glowing round navigation button at bottom center
              AnimatedContainer(
                duration: 200.ms,
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isHovered ? widget.color : widget.color.withValues(alpha: 0.1),
                  border: Border.all(
                    color: widget.color.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Center(
                  child: Icon(
                    Icons.chevron_right_rounded,
                    color: _isHovered ? c.bg : widget.color,
                    size: 18,
                  ),
                ),
              ),
            ],
          ),
        ),
      )
      )
      .animate(delay: Duration(milliseconds: (widget.index * 70).clamp(0, 600)))
      .fadeIn(duration: 350.ms)
      .scale(
          begin: const Offset(0.9, 0.9),
          end: const Offset(1, 1),
          duration: 350.ms,
          curve: Curves.easeOutBack),
    );
  }
}

class _TeacherNoticePreview extends StatelessWidget {
  final Map<String, dynamic> notice;
  const _TeacherNoticePreview({required this.notice});

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


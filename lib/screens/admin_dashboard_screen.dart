import 'dart:async'; // 👈 স্ট্রিম সাবস্ক্রিপশনের জন্য এটি প্রয়োজন
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/routine_service.dart';
import '../services/supabase_service.dart';
import '../utils/theme_provider.dart';
import '../utils/responsive.dart';
import '../widgets/common.dart';
import '../widgets/theme_picker.dart';
import 'notices_screen.dart';
import 'notes_screen.dart';
import 'students_screen.dart';
import 'routine_screen.dart';
import 'teachers_screen.dart';
import 'events_editor_screen.dart';
import '../widgets/attendance_launcher.dart';
import '../widgets/approval_menu.dart';
import '../utils/page_transitions.dart';
import 'attendance_report_screen.dart';
import 'admin_teacher_profile_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  final Map<String, dynamic> profile;
  const AdminDashboardScreen({super.key, required this.profile});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  int _tab = 0;
  DateTime? _lastBackPress;
  bool _navVisible = true;
  Timer? _hideTimer;
  late final List<Widget> _tabs;
  /// Notifier that increments when a user is approved/rejected, triggering
  /// refresh on subscribed screens (students list, teachers list, etc.).
  final ValueNotifier<int> _approvalNotifier = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    _tabs = [
      _AdminOverview(
        profile: widget.profile,
        approvalNotifier: _approvalNotifier,
        onApprovalChanged: _onApprovalChanged,
      ),
      StudentsScreen(isAdmin: true, refreshNotifier: _approvalNotifier),
      const RoutineScreen(
          isAdmin: true, initialSemester: RoutineService.allSemesters),
      const NotesScreen(isAdmin: true),
      const NoticesScreen(isAdmin: true),
      AttendanceLauncher(profile: widget.profile),
      AdminTeacherProfileScreen(profile: widget.profile, isAdmin: true),
    ];
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _approvalNotifier.dispose();
    super.dispose();
  }

  void _onApprovalChanged() {
    _approvalNotifier.value++;
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
          BottomNavigationBarItem(icon: Icon(Icons.dashboard_outlined), activeIcon: Icon(Icons.dashboard), label: ''),
          BottomNavigationBarItem(icon: Icon(Icons.people_outline), activeIcon: Icon(Icons.people), label: ''),
          BottomNavigationBarItem(icon: Icon(Icons.schedule_outlined), activeIcon: Icon(Icons.schedule), label: ''),
          BottomNavigationBarItem(icon: Icon(Icons.menu_book_outlined), activeIcon: Icon(Icons.menu_book), label: ''),
          BottomNavigationBarItem(icon: Icon(Icons.campaign_outlined), activeIcon: Icon(Icons.campaign), label: ''),
          BottomNavigationBarItem(icon: Icon(Icons.qr_code_outlined), activeIcon: Icon(Icons.qr_code), label: ''),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline), activeIcon: Icon(Icons.person), label: ''),
        ],
      ),
    ),
    );
  }
}

// ── Overview Tab ──────────────────────────────────────────────────────────────
class _AdminOverview extends StatefulWidget {
  final Map<String, dynamic> profile;
  final ValueNotifier<int> approvalNotifier;
  final VoidCallback? onApprovalChanged;
  const _AdminOverview({
    required this.profile,
    required this.approvalNotifier,
    this.onApprovalChanged,
  });

  @override
  State<_AdminOverview> createState() => _AdminOverviewState();
}

class _AdminOverviewState extends State<_AdminOverview> {
  int _studentCount = 0;
  int _noticeCount = 0;
  int _noteCount = 0;
  int _pendingCount = 0;
  bool _initialLoading = true;
  bool _initialDataLoaded = false;
  int _prevPendingCount = 0;
  DateTime? _lastPendingToast;
  final _subs = <StreamSubscription>[];
  StreamSubscription<List<Map<String, dynamic>>>? _pendingSub;

  @override
  void initState() {
    super.initState();
    widget.approvalNotifier.addListener(_refreshPendingCount);
    _subscribe();
  }

  @override
  void dispose() {
    widget.approvalNotifier.removeListener(_refreshPendingCount);
    _pendingSub?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  Future<void> _refreshPendingCount() async {
    try {
      final data = await SupabaseService.getPendingProfiles();
      if (!mounted) return;
      setState(() {
        _prevPendingCount = _pendingCount;
        _pendingCount = data.length;
        _initialLoading = false;
        _initialDataLoaded = true;
      });
    } catch (_) {
      // The realtime stream remains the fallback if this immediate refresh fails.
    }
  }

  void _subscribe() {
    _subs.add(SupabaseService.getStudentsStream().listen((data) {
      if (mounted)
        setState(() {
          _studentCount = data.length;
          _initialLoading = false;
        });
    }, onError: (_) {
      if (mounted) setState(() => _initialLoading = false);
    }));
    _subs.add(SupabaseService.getNoticesStream().listen((data) {
      if (mounted)
        setState(() {
          _noticeCount = data.length;
        });
    }));
    _subs.add(SupabaseService.getNotesStream().listen((data) {
      if (mounted)
        setState(() {
          _noteCount = data.length;
        });
    }));

    // Real-time stream for pending approval count — replaces old poll-based approach
    _pendingSub?.cancel();
    _pendingSub = SupabaseService.getPendingProfilesStream().listen((data) {
      if (!mounted) return;
      final newCount = data.length;

      // Show toast when a NEW pending request arrives (skip on initial load)
      if (_initialDataLoaded && newCount > _prevPendingCount) {
        final diff = newCount - _prevPendingCount;
        final now = DateTime.now();
        // Debounce: only show toast once every 3 seconds to avoid spam
        if (_lastPendingToast == null ||
            now.difference(_lastPendingToast!) > const Duration(seconds: 3)) {
          _lastPendingToast = now;
          final msg = diff == 1
              ? 'New approval request received!'
              : '$diff new approval requests received!';
          showAppSnackbar(context, msg);
        }
      }

      setState(() {
        _prevPendingCount = _pendingCount;
        _pendingCount = newCount;
        _initialLoading = false;
        _initialDataLoaded = true;
      });
    }, onError: (_) {
      if (mounted && _pendingCount == 0)
        setState(() => _initialLoading = false);
    });
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
    final name = widget.profile['name'] ?? 'Admin';
    return Container(
      color: c.bg,
      child: SafeArea(
        // outer Scaffold handles bottom nav safe area
        bottom: false,
        child: Column(
          children: [
            // ── App Bar replacement (avoids nested Scaffold) ────────────────
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    c.accent.withValues(alpha: 0.12),
                    c.accent.withValues(alpha: 0.01),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Padding(
                padding:
                    const EdgeInsets.only(left: 8, right: 4, top: 4, bottom: 4),
                child: Row(
                  children: [
                    const SizedBox(width: 8),
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        gradient:
                            LinearGradient(colors: [c.accent, c.accentDim]),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: const Center(
                          child: Icon(Icons.school,
                              color: Colors.white, size: 16)),
                    ),
                    const SizedBox(width: 10),
                    Text('Admin Panel',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: c.white)),
                    const Spacer(),
                    // Approvals badge
                    IconButton(
                      icon: Badge(
                        isLabelVisible: _pendingCount > 0,
                        label: Text('$_pendingCount',
                            style: const TextStyle(fontSize: 10)),
                        backgroundColor: c.accent,
                        child: Icon(Icons.how_to_reg_outlined, color: c.accent),
                      ),
                      tooltip: 'Approvals',
                      onPressed: () => showResponsiveApprovalMenu(context,
                          onChanged: widget.onApprovalChanged),
                    ),
                    // Theme picker
                    IconButton(
                      icon: Icon(Icons.palette_outlined, color: c.accent),
                      tooltip: 'Change Theme',
                      onPressed: () => showThemePicker(context),
                    ),
                    // Sign out
                    IconButton(
                      icon: Icon(Icons.logout, color: c.danger),
                      tooltip: 'Sign Out',
                      onPressed: () async {
                        await SupabaseService.signOut();
                      },
                    ),
                  ],
                ),
              ),
            ),

            // ── Scrollable body ────────────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  Responsive.screenPadding(context),
                  Responsive.screenPadding(context),
                  Responsive.screenPadding(context),
                  Responsive.screenPadding(context) + 88, // extra bottom padding for nav bar overlay
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Greeting
                    AppCard(
                      borderColor: c.accentOrange
                          .withValues(alpha: c.isLight ? 0.2 : 0.3),
                      color: c.isLight ? c.bg2 : null,
                      gradient: c.isLight
                          ? null
                          : LinearGradient(
                              colors: [
                                c.accentOrange.withValues(alpha: 0.06),
                                c.accentOrange.withValues(alpha: 0.01),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                      child: Row(
                        children: [
                          Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(colors: [
                                c.accentOrange,
                                Color.lerp(c.accentOrange, Colors.black, 0.35)!
                              ]),
                              borderRadius: BorderRadius.circular(16),
                            ),
                      child: const Center(
                          child: Icon(Icons.bolt,
                              color: Colors.white, size: 24)),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_greeting,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: c.accentOrange
                                            .withValues(alpha: 0.75),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0)),
                                const SizedBox(height: 2),
                                Text(name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w800,
                                        color: c.white)),
                                Text('System Administrator \u00B7 CST',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: c.muted, fontSize: 12)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Stats
                    const SectionTitle(
                        title: 'Overview',
                        icon: Icons.dashboard_outlined,
                        centered: true),
                    const SizedBox(height: 14),
                    GridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: Responsive.gridColumns(context,
                          small: 2, medium: 2, large: 4),
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 1.15,
                      children: [
                        _StatCard(
                            label: 'Total Students',
                            value: _initialLoading ? '\u2014' : '$_studentCount',
                            icon: Icons.people,
                            color: c.accent,
                            index: 0),
                        _StatCard(
                            label: 'Notices',
                            value: _initialLoading ? '\u2014' : '$_noticeCount',
                            icon: Icons.campaign,
                            color: c.warn,
                            index: 1),
                        _StatCard(
                            label: 'Notes',
                            value: _initialLoading ? '\u2014' : '$_noteCount',
                            icon: Icons.menu_book,
                            color: c.accent3,
                            index: 2),
                        _StatCard(
                            label: 'Pending Approval',
                            value:
                                _initialLoading ? '\u2014' : '$_pendingCount',
                            icon: Icons.hourglass_empty,
                            color: c.accentIndigo,
                            index: 3),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Quick Actions
                    const SectionTitle(
                        title: 'Quick Actions',
                        icon: Icons.flash_on,
                        centered: true),
                    const SizedBox(height: 14),
                    GridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: Responsive.gridColumns(context,
                          small: 2, medium: 3, large: 4),
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      childAspectRatio: 0.85,
                      children: [
                        _QuickAction(
                            icon: Icons.people,
                            label: 'Students',
                            color: c.accentOrange.withValues(alpha: 0.75),
                            index: 0,
                            onTap: () => Navigator.push(
                                context,
                                buildCupertinoRoute(const StudentsScreen(
                                    isAdmin: true)))),
                        _QuickAction(
                            icon: Icons.person,
                            label: 'Faculty',
                            color: c.accentOrange.withValues(alpha: 0.75),
                            index: 1,
                            onTap: () => Navigator.push(
                                context,
                                buildCupertinoRoute(const TeachersScreen(
                                    isAdmin: true)))),
                        _QuickAction(
                            icon: Icons.calendar_month,
                            label: 'Routine',
                            color: c.accentOrange.withValues(alpha: 0.75),
                            index: 2,
                            onTap: () {
                              final state = context.findAncestorStateOfType<
                                  _AdminDashboardScreenState>();
                              state?.setState(() => state._tab = 2);
                            }),
                        _QuickAction(
                            icon: Icons.menu_book,
                            label: 'Notes',
                            color: c.accentOrange.withValues(alpha: 0.75),
                            index: 3,
                            onTap: () {
                              final state = context.findAncestorStateOfType<
                                  _AdminDashboardScreenState>();
                              state?.setState(() => state._tab = 3);
                            }),
                        _QuickAction(
                            icon: Icons.campaign,
                            label: 'Notices',
                            color: c.accentOrange.withValues(alpha: 0.75),
                            index: 4,
                            onTap: () {
                              final state = context.findAncestorStateOfType<
                                  _AdminDashboardScreenState>();
                              state?.setState(() => state._tab = 4);
                            }),
                        _QuickAction(
                            icon: Icons.check_circle,
                            label: 'Approvals',
                            color: c.accentOrange.withValues(alpha: 0.75),
                            index: 5,
                            onTap: () => showResponsiveApprovalMenu(context,
                                onChanged: widget.onApprovalChanged)),
                        _QuickAction(
                            icon: Icons.event,
                            label: 'Events',
                            color: c.accentOrange.withValues(alpha: 0.75),
                            index: 6,
                            onTap: () => Navigator.push(
                                context,
                                buildCupertinoRoute(const EventsEditorScreen(
                                    isAdmin: true)))),
                        _QuickAction(
                            icon: Icons.event_busy,
                            label: 'Off Days',
                            color: c.accentOrange.withValues(alpha: 0.75),
                            index: 7,
                            onTap: () => showOffDaysManager(context)),
                        _QuickAction(
                            icon: Icons.bar_chart,
                            label: 'Attendance Reports',
                            color: c.accentOrange.withValues(alpha: 0.75),
                            index: 8,
                            onTap: () => Navigator.push(
                                context,
                                buildCupertinoRoute(
                                    const AttendanceReportScreen()))),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatefulWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final int index;

  const _StatCard(
      {required this.label,
      required this.value,
      required this.icon,
      required this.color,
      required this.index});

  @override
  State<_StatCard> createState() => _StatCardState();
}

class _StatCardState extends State<_StatCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: RepaintBoundary(
      child: AnimatedContainer(
        duration: 250.ms,
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: c.bg2,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: _isHovered ? widget.color.withValues(alpha: 0.5) : widget.color.withValues(alpha: 0.15),
            width: _isHovered ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: widget.color.withValues(alpha: _isHovered ? 0.12 : 0.04),
              blurRadius: _isHovered ? 16 : 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            children: [
              // Premium Sparkline Wave at the bottom (RepaintBoundary caches it)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                height: 44,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: _WavePainter(color: widget.color),
                    ),
                  ),
                ),
              ),
              
              // Card Details
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        // Circular glowing container for emoji
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: widget.color.withValues(alpha: 0.1),
                            border: Border.all(
                              color: widget.color.withValues(alpha: 0.25),
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: widget.color.withValues(alpha: 0.12),
                                blurRadius: 8,
                              )
                            ]
                          ),
                          child: Center(
                            child: Icon(
                              widget.icon,
                              color: widget.color,
                              size: 20,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        
                        // Giant Value text in matching accent color
                        Expanded(
                          child: Text(
                            widget.value,
                            style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w900,
                              color: widget.color,
                              height: 1,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    
                    // Card Label in bold high-contrast text
                    Text(
                      widget.label,
                      style: TextStyle(
                        color: c.white.withValues(alpha: 0.85),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    )
    .animate(delay: Duration(milliseconds: (widget.index * 80).clamp(0, 600)))
    .fadeIn(duration: 350.ms)
    .scale(
        begin: const Offset(0.92, 0.92),
        end: const Offset(1, 1),
        duration: 350.ms,
        curve: Curves.easeOutBack),
  );
  }
}

class _QuickAction extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;
  final int index;
  final VoidCallback onTap;

  const _QuickAction(
      {required this.icon,
      required this.label,
      required this.color,
      required this.index,
      required this.onTap});

  @override
  State<_QuickAction> createState() => _QuickActionState();
}

class _QuickActionState extends State<_QuickAction> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: RepaintBoundary(
        child: AnimatedContainer(
          duration: 250.ms,
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          decoration: BoxDecoration(
            color: context.colors.bg2,
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
              // Prominent Action Icon
              Icon(
                widget.icon,
                size: 24,
                color: widget.color,
              ),
              const SizedBox(height: 8),
              
              // Custom Typography matching mockup accent colors
              Text(
                widget.label,
                style: TextStyle(
                  color: widget.color,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              
              // Subtle navigation indicator
              Icon(
                Icons.chevron_right_rounded,
                color: _isHovered ? widget.color : widget.color.withValues(alpha: 0.4),
                size: 16,
              ),
            ],
          ),
        ),
      )
      )
    );
  }
}

// ── Premium Sparkline Wave Painter ──────────────────────────────────────────
class _WavePainter extends CustomPainter {
  final Color color;
  _WavePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withValues(alpha: 0.15),
          color.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;

    final path = Path();
    path.moveTo(0, size.height * 0.7);
    
    // Perfectly calculated wave matching the reference screenshot exactly
    path.cubicTo(
      size.width * 0.25, size.height * 0.2,
      size.width * 0.5, size.height * 0.95,
      size.width * 0.75, size.height * 0.35,
    );
    path.quadraticBezierTo(
      size.width * 0.88, size.height * 0.1,
      size.width, size.height * 0.3,
    );

    // Close the path for gradient background fill
    final fillPath = Path.from(path);
    fillPath.lineTo(size.width, size.height);
    fillPath.lineTo(0, size.height);
    fillPath.close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, paint);

    // Translucent glowing dot on the wave terminal
    final outerDotPaint = Paint()
      ..color = color.withValues(alpha: 0.35)
      ..style = PaintingStyle.fill;
    final innerDotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final dotCenter = Offset(size.width, size.height * 0.3);
    canvas.drawCircle(dotCenter, 6.5, outerDotPaint);
    canvas.drawCircle(dotCenter, 3.5, innerDotPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

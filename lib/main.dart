import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kReleaseMode, kDebugMode;
import 'package:flutter_animate/flutter_animate.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'services/supabase_service.dart';
import 'services/update_service.dart';
import 'services/cache_service.dart';
import 'services/notification_service.dart';
import 'services/reminder_service.dart';
import 'services/error_service.dart';
import 'services/analytics_service.dart';
import 'services/connectivity_service.dart';
import 'firebase_options.dart';
import 'utils/theme_provider.dart';
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/student_home_screen.dart';
import 'screens/admin_dashboard_screen.dart';
import 'screens/teacher_dashboard_screen.dart';
import 'screens/notices_screen.dart';
import 'screens/notes_screen.dart';
import 'screens/exam_routine_screen.dart';

// নোটিফিকেশন ক্লিক রুট হ্যান্ডেল করার জন্য গ্লোবাল নেভিগেটর কি
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Simple error fallback shown when the Flutter framework catches a build error.
/// This uses NO theme, NO MaterialApp, and NO providers — safe to show even
/// when the theme system itself is broken.
class _ErrorFallback extends StatelessWidget {
  final String message;
  const _ErrorFallback({this.message = 'Something went wrong.'});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0E1420),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
              const SizedBox(height: 16),
              const Text(
                'Something went wrong',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Entry Point ─────────────────────────────────────────────────────────────
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // স্ক্রিন ওরিয়েন্টেশন পোর্ট্রেট মোডে লক করা
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // ── STEP 1: Firebase ব্যাকগ্রাউন্ড হ্যান্ডেলার রেজিস্টার করা ──────────────────
  if (!kIsWeb) {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }

  // ── STEP 2: Cache + Supabase ইনিশিয়ালাইজেশন (parallel) ─────────────────────
  await Future.wait([
    CacheService.init(),
    SupabaseService.initialize(),
    ConnectivityService().init(),
  ]);

  // Firebase + FCM init deferred to after the first frame
  // so the splash screen shows immediately. See _CSTPortalAppState._deferredInit().

  // ── Error Boundary: catch unhandled Flutter framework errors ──
  // NOTE: Do NOT return a MaterialApp here — if the error is theme/build related,
  // a second MaterialApp would also fail, causing infinite recursion → Stack Overflow.
  ErrorWidget.builder = (FlutterErrorDetails details) {
    ErrorService.log('Flutter ErrorWidget', error: details.exception, stack: details.stack);
    return const _ErrorFallback(
      message: 'Something went wrong. Please restart the app.',
    );
  };

  // Catch async errors that don't hit the Flutter framework
  FlutterError.onError = (FlutterErrorDetails details) {
    ErrorService.recordError(details.exception, details.stack ?? StackTrace.current,
        reason: details.context?.toString());
    FlutterError.presentError(details);
  };

  runApp(const CSTPortalApp());
}

// ─── App Root ─────────────────────────────────────────────────────────────────
class CSTPortalApp extends StatefulWidget {
  const CSTPortalApp({super.key});

  @override
  State<CSTPortalApp> createState() => _CSTPortalAppState();
}

class _CSTPortalAppState extends State<CSTPortalApp>
    with WidgetsBindingObserver {
  final _themeProvider = ThemeProvider();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _themeProvider.addListener(_updateSystemUI);
    // Show the first frame ASAP, then initialize Firebase + FCM
    WidgetsBinding.instance.addPostFrameCallback((_) => _deferredInit());
  }

  /// Deferred Firebase + FCM init — runs after the splash screen is visible.
  /// Also starts the profile fetch early so it can overlap with the splash animation.
  Future<void> _deferredInit() async {
    // Start profile preload during splash (in parallel with Firebase init)
    _ProfileRouterState.startPreload();

    if (kIsWeb) {
      debugPrint('[main] Firebase skipped — running on Web.');
      return;
    }
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      // Initialize error reporting & analytics after Firebase
      await Future.wait([
        ErrorService.init(),
        AnalyticsService.init(),
        FirebaseMessaging.instance.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        ),
      ]);
    } catch (e) {
      debugPrint('[main] Firebase init skipped/failed: $e');
    }
  }

  @override
  void didChangePlatformBrightness() {
    _themeProvider.updatePlatformBrightness(
      WidgetsBinding.instance.platformDispatcher.platformBrightness,
    );
  }

  void _updateSystemUI() {
    final c = _themeProvider.colors;
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: c.isLight ? Brightness.dark : Brightness.light,
      statusBarBrightness: c.isLight ? Brightness.light : Brightness.dark,
      systemNavigationBarColor: c.bg2,
      systemNavigationBarIconBrightness:
          c.isLight ? Brightness.dark : Brightness.light,
      systemNavigationBarDividerColor: Colors.transparent,
    ));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _themeProvider.removeListener(_updateSystemUI);
    _themeProvider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _themeProvider,
      child: Consumer<ThemeProvider>(
        builder: (context, themeProv, _) {
          // Sync system chrome immediately on each theme change
          _updateSystemUI();
          return MaterialApp(
            navigatorKey: navigatorKey, // নোটিফিকেশন ক্লিকের পর পেজ পরিবর্তনের জন্য জরুরি
            title: 'CST Department Portal',
            debugShowCheckedModeBanner: false,
            theme: themeProv.themeData,
            navigatorObservers: [
              LazyAnalyticsObserver(),
            ],
            // ── নোটিফিকেশনে ট্যাপ করলে সঠিক পেজে যাওয়ার জন্য Named Routes ──────────
            routes: {
              '/notices': (ctx) => NoticesScreen(
                    isAdmin: _resolveIsAdmin(ctx),
                  ),
              '/notes': (ctx) => NotesScreen(
                    isAdmin: _resolveIsAdmin(ctx),
                  ),
              '/exams': (ctx) => ExamRoutineScreen(
                    isAdmin: _resolveIsAdmin(ctx),
                    semester: SupabaseService.semesterToInt(_ProfileRouterState.currentProfile?['semester']?.toString()) ?? 1,
                  ),
            },
            builder: (context, child) {
              final c = context.colors;
              final scaler = MediaQuery.of(context).textScaler;
              final clamped = scaler.scale(1.0).clamp(0.8, 1.5);
              return MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(clamped),
                ),
                child: Stack(
                  children: [
                    // Subtle blue-red ambient gradient across the full app
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: c.backgroundGradient,
                          ),
                        ),
                      ),
                    ),
                    child!,
                  ],
                ),
              );
            },
            home: const SplashScreen(nextScreen: AuthGate()),
          );
        },
      ),
    );
  }

  bool _resolveIsAdmin(BuildContext ctx) {
    final role = (_ProfileRouterState.currentProfile?['role'] ?? '').toString().toLowerCase();
    return role == 'admin';
  }
}

// ─── AuthGate ─────────────────────────────────────────────────────────────────
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: SupabaseService.authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.data?.event == AuthChangeEvent.signedOut) {
          return const LoginScreen();
        }
        final user = SupabaseService.currentUser;
        if (user == null) return const LoginScreen();
        return _ProfileRouter(userId: user.id);
      },
    );
  }
}

// ─── ProfileRouter ────────────────────────────────────────────────────────────
class _ProfileRouter extends StatefulWidget {
  final String userId;
  const _ProfileRouter({required this.userId});

  @override
  State<_ProfileRouter> createState() => _ProfileRouterState();
}

class _ProfileRouterState extends State<_ProfileRouter> {
  /// Static accessor so named routes can resolve admin role and semester
  /// without needing to pass profile data through the widget tree.
  static Map<String, dynamic>? currentProfile;

  /// Preload future — started during splash screen so profile data
  /// may already be ready by the time we navigate here.
  static Future<Map<String, dynamic>?>? _preloadFuture;

  /// Kick off the profile fetch during the splash screen.
  /// Called from [_CSTPortalAppState._deferredInit] after the first frame.
  static void startPreload() {
    if (_preloadFuture != null) return; // Already started
    final user = SupabaseService.currentUser;
    if (user == null) return;
    _preloadFuture = SupabaseService.getProfile(user.id);
  }

  Map<String, dynamic>? _profile;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    // ── Cache-first: show cached profile immediately (if fresh) ──
    final cacheKey = CacheService.profileKey(widget.userId);
    Map<String, dynamic>? cached;
    if (!CacheService.isStale(cacheKey)) {
      cached = CacheService.loadMap(cacheKey);
    }
    if (cached != null && mounted) {
      currentProfile = cached;
      setState(() { _profile = cached; _loading = false; });
    }

    try {
      // Use the preloaded profile if available (started during splash screen)
      var profile = _preloadFuture != null
          ? await _preloadFuture!
          : await SupabaseService.getProfile(widget.userId);
      _preloadFuture = null; // Prevent reuse across user switches

      // Profile is null — try to auto-create from auth metadata
      // This handles the case where the DB trigger was missing when the user registered.
      if (profile == null) {
        final created = await SupabaseService.createProfileFromAuth();
        if (created != null) {
          profile = created;
          debugPrint('[ProfileRouter] Auto-created profile for ${created['email']}');
        }
      }

      // Still null after auto-create attempt — admin likely rejected/deleted this user
      if (mounted && profile == null) {
        LoginScreen.showRejectedMessage = true;
        await SupabaseService.signOut();
        return;
      }

      // প্রোফাইল সফলভাবে লোড হওয়ার পর নোটিফিকেশন সার্ভিস চালু করা
      if (mounted && !kIsWeb) {
        await NotificationService().initialize(context);
        if (kDebugMode) await NotificationService().printToken();
        ReminderService.rescheduleOnAppLaunch().catchError((e) {
          debugPrint('[main] Reminder reschedule on launch failed: $e');
        });
      }

      if (profile != null) {
        // Write-through: update cache with fresh data
        await CacheService.saveMap(cacheKey, profile);
        currentProfile = profile;
        if (mounted) setState(() { _profile = profile; _loading = false; });
      }

      // Check for app updates via Firebase Remote Config (non-blocking, fails silently)
      if (mounted) UpdateService.checkForUpdate(context);
    } catch (e) {
      // If we already showed cached profile, don't show error — just log it
      if (cached != null) {
        debugPrint('[ProfileRouter] Network error, using cached profile: $e');
        // Initialize notifications with cached profile
        if (mounted && !kIsWeb) {
          await NotificationService().initialize(context);
          if (kDebugMode) await NotificationService().printToken();
          ReminderService.rescheduleOnAppLaunch().catchError((e) {
            debugPrint('[main] Reminder reschedule on launch failed: $e');
          });
        }
      } else {
        // No cache — show error screen
        if (mounted) setState(() { _error = e.toString(); _loading = false; });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    if (_loading) {
      return Scaffold(
        backgroundColor: c.bg,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 40, height: 40,
                child: CircularProgressIndicator(color: c.accent, strokeWidth: 3),
              )
                  .animate()
                  .fadeIn(duration: 600.ms, curve: Curves.easeOut)
                  .scale(begin: const Offset(0.8, 0.8), duration: 600.ms, curve: Curves.easeOutBack),
              const SizedBox(height: 24),
              Text('Loading your profile…', style: TextStyle(color: c.muted, fontSize: 14))
                  .animate()
                  .fadeIn(duration: 400.ms, delay: 100.ms)
                  .slideY(begin: 0.08, end: 0, duration: 400.ms, delay: 100.ms),
            ],
          ),
        ),
      );
    }

    if (_error != null) {
      return _ErrorScreen(
        error: _error!,
        onRetry: () { setState(() { _loading = true; _error = null; }); _loadProfile(); },
      );
    }

    if (_profile == null) return _AwaitingApprovalScreen(onRefresh: _loadProfile);

    final status = (_profile!['status'] ?? 'pending').toString().toLowerCase();

    if (status == 'rejected') {
      return _RejectedScreen(profile: _profile!, onRefresh: _loadProfile);
    }

    if (status != 'approved') {
      return _PendingScreen(profile: _profile!, onRefresh: _loadProfile);
    }

    // Role এর ওপর ভিত্তি করে সঠিক ড্যাশবোর্ডে পাঠানো
    final role = (_profile!['role'] ?? 'student').toString().toLowerCase();
    if (role == 'admin')   return AdminDashboardScreen(profile: _profile!);
    if (role == 'teacher') return TeacherDashboardScreen(profile: _profile!);
    return StudentHomeScreen(profile: _profile!);
  }
}

// ─── Simple Status Screens ────────────────────────────────────────────────────
class _ErrorScreen extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorScreen({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.bg,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.warning_amber, size: 56, color: Colors.amber),
                const SizedBox(height: 16),
                Text('Could not load profile',
                    style: TextStyle(color: c.white, fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(error,
                    style: TextStyle(color: c.muted, fontSize: 13),
                    textAlign: TextAlign.center),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () async => SupabaseService.signOut(),
                  child: Text('Sign Out', style: TextStyle(color: c.danger)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AwaitingApprovalScreen extends StatelessWidget {
  final VoidCallback onRefresh;
  const _AwaitingApprovalScreen({required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.bg,
      body: Center(
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.hourglass_empty, size: 56, color: Colors.amber),
              const SizedBox(height: 16),
              Text('Awaiting Approval',
                  style: TextStyle(color: c.white, fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              Text(
                'Your account is pending admin approval.',
                style: TextStyle(color: c.muted, fontSize: 14, height: 1.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              OutlinedButton.icon(
                onPressed: onRefresh,
                icon: Icon(Icons.refresh, color: c.accent),
                label: Text('Check again', style: TextStyle(color: c.accent)),
                style: OutlinedButton.styleFrom(side: BorderSide(color: c.accent)),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () async => SupabaseService.signOut(),
                child: Text('Sign Out', style: TextStyle(color: c.muted)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PendingScreen extends StatelessWidget {
  final Map<String, dynamic> profile;
  final VoidCallback onRefresh;
  const _PendingScreen({required this.profile, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.bg,
      body: Center(
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.hourglass_empty, size: 56, color: Colors.amber),
              const SizedBox(height: 16),
              Text('Pending Approval',
                  style: TextStyle(color: c.white, fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              Text(
                'Hello ${profile['name'] ?? ''}! Your account is under review.',
                style: TextStyle(color: c.muted, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              OutlinedButton.icon(
                onPressed: onRefresh,
                icon: Icon(Icons.refresh, color: c.accent),
                label: Text('Refresh', style: TextStyle(color: c.accent)),
                style: OutlinedButton.styleFrom(side: BorderSide(color: c.accent)),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () async => SupabaseService.signOut(),
                child: Text('Sign Out', style: TextStyle(color: c.muted)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RejectedScreen extends StatelessWidget {
  final Map<String, dynamic> profile;
  final VoidCallback onRefresh;
  const _RejectedScreen({required this.profile, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.bg,
      body: Center(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cancel, size: 64, color: Colors.redAccent),
                const SizedBox(height: 16),
                Text('Registration Rejected',
                    style: TextStyle(color: c.white, fontSize: 22, fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                Text(
                  'Hello ${profile['name'] ?? ''}. Your application was rejected by the administrator.',
                  style: TextStyle(color: c.muted, fontSize: 14, height: 1.5),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 28),
                TextButton(
                  onPressed: () async => SupabaseService.signOut(),
                  child: Text('Sign Out', style: TextStyle(color: c.muted)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

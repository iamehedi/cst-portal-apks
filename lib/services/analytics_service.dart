import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;

/// Centralized analytics service.
/// Tracks screen views and user events via Firebase Analytics.
class AnalyticsService {
  static FirebaseAnalytics? _analytics;

  /// Must be called after Firebase.initializeApp().
  static Future<void> init() async {
    if (kIsWeb) return;
    _analytics = FirebaseAnalytics.instance;
    // Enable analytics in release mode
    await _analytics!.setAnalyticsCollectionEnabled(!kDebugMode);
  }

  /// Log a screen view event.
  static Future<void> logScreen(String screenName) async {
    if (kIsWeb || kDebugMode || _analytics == null) return;
    await _analytics!.logScreenView(
      screenName: screenName,
      screenClass: screenName,
    );
  }

  /// Log a custom event with optional parameters.
  static Future<void> logEvent(String name, {Map<String, Object>? parameters}) async {
    if (kIsWeb || kDebugMode || _analytics == null) return;
    await _analytics!.logEvent(name: name, parameters: parameters);
  }

  /// Log a user login event.
  static Future<void> logLogin() async {
    if (kIsWeb || kDebugMode || _analytics == null) return;
    await _analytics!.logLogin();
  }

  /// Log a user signup event.
  static Future<void> logSignUp({String? signUpMethod}) async {
    if (kIsWeb || kDebugMode || _analytics == null) return;
    await _analytics!.logSignUp(signUpMethod: signUpMethod ?? '');
  }

  /// Get the FirebaseAnalytics instance for use with NavigatorObserver.
  static FirebaseAnalytics? get instance => _analytics;
}

/// NavigatorObserver that lazily delegates to FirebaseAnalyticsObserver
/// once AnalyticsService is initialized. Safe to add to MaterialApp
/// even before Firebase init completes — it silently no-ops until ready.
class LazyAnalyticsObserver extends NavigatorObserver {
  FirebaseAnalyticsObserver? _realObserver;

  @override
  void didPush(Route route, Route? previousRoute) {
    _ensureReady();
    _realObserver?.didPush(route, previousRoute);
  }

  @override
  void didPop(Route route, Route? previousRoute) {
    _ensureReady();
    _realObserver?.didPop(route, previousRoute);
  }

  @override
  void didReplace({Route? newRoute, Route? oldRoute}) {
    _ensureReady();
    _realObserver?.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }

  void _ensureReady() {
    if (_realObserver != null) return;
    final analytics = AnalyticsService.instance;
    if (analytics != null) {
      _realObserver = FirebaseAnalyticsObserver(analytics: analytics);
    }
  }
}

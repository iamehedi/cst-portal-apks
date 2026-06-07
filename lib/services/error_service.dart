import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Centralized error reporting service.
/// Uses Firebase Crashlytics in release mode on Android/iOS.
/// Falls back to debugPrint in debug mode / on web.
class ErrorService {
  static FirebaseCrashlytics? _crashlytics;

  /// Must be called after Firebase.initializeApp().
  static Future<void> init() async {
    if (kIsWeb) return;
    _crashlytics = FirebaseCrashlytics.instance;
    // Enable crash collection in release mode only (avoids noisy debug crashes)
    await _crashlytics!.setCrashlyticsCollectionEnabled(!kDebugMode);
  }

  /// Log a non-fatal error (e.g. caught exception).
  static void log(String message, {Object? error, StackTrace? stack}) {
    if (kIsWeb || kDebugMode) {
      // ignore: avoid_print
      print('[ErrorService] $message');
      if (error != null) // ignore: avoid_print
        print('  → $error');
      return;
    }
    _crashlytics?.log(message);
    if (error != null && stack != null) {
      _crashlytics?.recordError(error, stack);
    }
  }

  /// Record a caught exception with its stack trace.
  static void recordError(Object error, StackTrace stack, {String? reason}) {
    if (kIsWeb || kDebugMode) {
      // ignore: avoid_print
      print('[ErrorService] ${reason ?? "Error"}: $error');
      return;
    }
    if (reason != null) _crashlytics?.log(reason);
    _crashlytics?.recordError(error, stack);
  }

  /// Set a key-value pair for crash reports (e.g. user role, screen).
  static void setCustomKey(String key, String value) {
    if (kIsWeb || kDebugMode) return;
    _crashlytics?.setCustomKey(key, value);
  }

  /// Set the current user identifier for crash reports.
  static void setUserId(String userId) {
    if (kIsWeb || kDebugMode) return;
    _crashlytics?.setUserIdentifier(userId);
  }
}

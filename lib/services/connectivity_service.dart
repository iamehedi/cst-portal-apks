import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Singleton service that monitors device network connectivity using
/// the [connectivity_plus] package.
///
/// Exposes [isOnline] as a [ValueNotifier<bool>] so widgets can listen
/// reactively. Initialize once at app startup via [init()].
class ConnectivityService {
  // ── Singleton ─────────────────────────────────────────────────
  ConnectivityService._();
  static final ConnectivityService _instance = ConnectivityService._();
  factory ConnectivityService() => _instance;

  final Connectivity _connectivity = Connectivity();

  /// Tracks whether the device currently has network connectivity.
  final ValueNotifier<bool> isOnline = ValueNotifier<bool>(true);

  StreamSubscription<List<ConnectivityResult>>? _subscription;

  /// Start monitoring connectivity. Call once early in app startup.
  Future<void> init() async {
    // Check the initial state immediately
    try {
      final results = await _connectivity.checkConnectivity();
      _updateStatus(results);
    } catch (_) {
      // checkConnectivity may throw on some platforms (e.g. web)
    }

    // Listen for ongoing changes
    try {
      _subscription = _connectivity.onConnectivityChanged
          .listen(_updateStatus);
    } catch (_) {
      // onConnectivityChanged may not be available on all platforms
    }
  }

  void _updateStatus(List<ConnectivityResult> results) {
    final online = results.any((r) => r != ConnectivityResult.none);
    isOnline.value = online;
  }

  /// Clean up the subscription when no longer needed.
  void dispose() {
    _subscription?.cancel();
  }
}

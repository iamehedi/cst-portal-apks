import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';
import '../../services/attendance_service.dart';
import '../../services/cache_service.dart';
import '../../services/connectivity_service.dart';
import '../../services/supabase_service.dart';
import '../db/local_database.dart';
import 'sync_engine.dart';

const String _syncTaskName = 'com.cstportal.attendance_sync';
const String _syncTaskTag = 'attendanceSync';

class SyncManager {
  static SyncManager? _instance;
  factory SyncManager() => _instance ??= SyncManager._();
  SyncManager._();

  Timer? _periodicTimer;
  bool _initialized = false;
  bool _isSyncing = false;
  /// Tracks whether we were offline on the previous connectivity check,
  /// so we can detect offline→online transitions.
  bool _wasOffline = false;

  /// Value notifier for total pending sync count (attendance records + sessions).
  final ValueNotifier<int> pendingCount = ValueNotifier<int>(0);
  /// Value notifier for pending QR session count specifically.
  final ValueNotifier<int> sessionPendingCount = ValueNotifier<int>(0);
  /// Last sync timestamp.
  final ValueNotifier<DateTime?> lastSyncTime = ValueNotifier<DateTime?>(null);

  static Future<void> initialize() async {
    final manager = SyncManager();
    await manager._init();
  }

  Future<void> _init() async {
    if (_initialized) return;
    _initialized = true;

    await _refreshPendingCount();

    ConnectivityService().isOnline.addListener(_onConnectivityChanged);

    _periodicTimer = Timer.periodic(const Duration(minutes: 15), (_) async {
      await _trySync();
    });

    await _registerWorkmanagerTask();

    if (ConnectivityService().isOnline.value) {
      await _trySync();
    }
  }

  void _onConnectivityChanged() {
    final online = ConnectivityService().isOnline.value;
    if (online) {
      // Transition: was offline → now online
      if (_wasOffline) {
        _wasOffline = false;
        // Invalidate all cached data so screens re-fetch fresh data
        CacheService.invalidateAllCaches();
      }
      _trySync();
    } else {
      _wasOffline = true;
    }
  }

  Future<void> _trySync() async {
    if (_isSyncing) return;
    _isSyncing = true;
    try {
      await SyncEngine.syncPendingRecords();
      // Sync any unsynced BLE records to Supabase
      await AttendanceService.syncAllBleRecords();
      // Sync any unsynced QR sessions to Supabase
      await AttendanceService.syncAllQrSessions();
      lastSyncTime.value = DateTime.now();
      await _refreshPendingCount();
    } catch (e) {
      debugPrint('[SyncManager] Sync failed: $e');
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _refreshPendingCount() async {
    try {
      final attendanceCount = await LocalDatabase.getPendingCount();
      final sessionCount = await LocalDatabase.getQrPendingCount();
      pendingCount.value = attendanceCount + sessionCount;
      sessionPendingCount.value = sessionCount;
    } catch (_) {}
  }

  static Future<void> _registerWorkmanagerTask() async {
    try {
      await Workmanager().registerPeriodicTask(
        _syncTaskName,
        _syncTaskTag,
        frequency: const Duration(minutes: 15),
        constraints: Constraints(
          networkType: NetworkType.connected,
        ),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
        backoffPolicy: BackoffPolicy.exponential,
        initialDelay: const Duration(minutes: 1),
      );
    } catch (e) {
      debugPrint('[SyncManager] WorkManager registration failed: $e');
    }
  }

  @pragma('vm:entry-point')
  static Future<bool> syncBackgroundTask() async {
    try {
      await SyncEngine.syncPendingRecords();
      return true;
    } catch (e) {
      debugPrint('[SyncManager] Background sync failed: $e');
      return false;
    }
  }

  /// Refresh the student cache from Supabase.
  static Future<void> refreshStudentCache() async {
    try {
      final students = await SupabaseService.getStudents();
      await LocalDatabase.cacheStudents(students);
      debugPrint('[SyncManager] Student cache refreshed: ${students.length} students');
    } catch (e) {
      debugPrint('[SyncManager] Student cache refresh failed: $e');
    }
  }

  /// Manual sync trigger (called from UI).
  Future<int> manualSync() async {
    int count = await SyncEngine.retryFailedRecords();
    await AttendanceService.syncAllBleRecords();
    await AttendanceService.syncAllQrSessions();
    lastSyncTime.value = DateTime.now();
    await _refreshPendingCount();
    return count;
  }

  void dispose() {
    _periodicTimer?.cancel();
    ConnectivityService().isOnline.removeListener(_onConnectivityChanged);
    _initialized = false;
  }
}

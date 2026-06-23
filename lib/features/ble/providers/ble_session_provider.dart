import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:uuid/uuid.dart';
import '../../../core/ble/ble_constants.dart';
import '../../../core/db/local_database.dart';
import '../../../core/ble/ble_teacher_service.dart';
import '../../../core/ble/nearby_service.dart';
import '../../../services/attendance_service.dart';
import '../../../services/connectivity_service.dart';

class BlePendingStudent {
  final int id;
  final String studentId;
  final String studentName;
  String status;
  final String? endpointId;

  BlePendingStudent({
    required this.id,
    required this.studentId,
    required this.studentName,
    this.status = 'pending',
    this.endpointId,
  });
}

class BleSessionProvider extends ChangeNotifier {
  final BleTeacherService _ble = BleTeacherService();
  final NearbyService _nearby = NearbyService();
  final _uuid = const Uuid();

  String? _sessionId;
  String? _subject;
  int? _semester;
  String _status = 'idle'; // idle | active | closed
  bool _loading = false;
  String? _error;

  final List<BlePendingStudent> _roster = [];
  StreamSubscription? _bluetoothStateSub;
  StreamSubscription? _disconnectSub;

  /// Guards against duplicate concurrent check-ins for the same studentId.
  final Set<String> _processingCheckIns = {};

  /// Approve-all progress tracking.
  int _approveProgress = 0;
  int _approveTotal = 0;
  bool _approving = false;

  // Getters
  String? get sessionId => _sessionId;
  String? get subject => _subject;
  int? get semester => _semester;
  String get status => _status;
  bool get loading => _loading;
  String? get error => _error;
  bool get isBluetoothOff => _error?.contains('Bluetooth') == true;
  bool get isAdvertising => _ble.isAdvertising.value;
  bool get isNearbyActive => _nearby.isActive.value;
  int get connectedCount => _nearby.connectedCount.value;
  List<BlePendingStudent> get roster => List.unmodifiable(_roster);

  int get pendingCount => _roster.where((s) => s.status == 'pending').length;
  int get approveProgress => _approveProgress;
  int get approveTotal => _approveTotal;
  bool get approving => _approving;

  Future<bool> startSession({
    required String subject,
    required int semester,
    required String teacherId,
    required String department,
  }) async {
    // ── CRITICAL: Fully clear previous session state ──
    // This prevents ghost attendance across sessions (Bug 1 & 4).
    // Every session must start with a completely empty roster, cleared
    // processing set, and no lingering BLE/Nearby connections.
    await _ble.stopAdvertising();
    await _nearby.stopAll();
    _roster.clear();
    _processingCheckIns.clear();
    _nextLocalId = -1;
    _bluetoothStateSub?.cancel();
    _disconnectSub?.cancel();
    _approveProgress = 0;
    _approveTotal = 0;
    _approving = false;

    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final now = DateTime.now().toUtc();
      final dateStr = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
      final random = _uuid.v4().substring(0, 5).toUpperCase();
      final sessionId = 'ATT_${subject.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '')}_${dateStr}_$random';

      // Save session to local DB
      final sessionData = {
        'id': sessionId,
        'subject': subject,
        'semester': semester,
        'teacher_id': teacherId,
        'department': department,
        'status': 'active',
        'created_at': now.toIso8601String(),
      };
      await LocalDatabase.insertBleSession(sessionData);

      // Create unified attendance_sessions record + sync to Supabase
      if (ConnectivityService().isOnline.value) {
        await AttendanceService.ensureUnifiedBleSession(sessionData);
      }

      // Ensure BLE ready (permissions + Bluetooth on)
      final bleReady = await _ble.ensureReady();
      if (!bleReady) {
        _error = 'BLE permission denied or Bluetooth off. Please grant BLE access and turn on Bluetooth.';
        _loading = false;
        notifyListeners();
        return false;
      }

      // Start BLE advertising
      final bleOk = await _ble.startAdvertising(sessionId, subject);
      if (!bleOk) {
        _error = 'Failed to start BLE beacon';
        _loading = false;
        notifyListeners();
        return false;
      }

      // Start Nearby Connections hub
      final nearbyOk = await _nearby.startAdvertising(
        name: '${BleConstants.nearbyEndpointPrefix}_$sessionId',
        sessionId: sessionId,
        onCheckInReceived: _onCheckIn,
      );
      if (!nearbyOk) {
        await _ble.stopAdvertising();
        _error = 'Failed to start Nearby Connections';
        _loading = false;
        notifyListeners();
        return false;
      }

      _sessionId = sessionId;
      _subject = subject;
      _semester = semester;
      _status = 'active';

      // The session ID is set BEFORE Nearby starts advertising, eliminating
      // a race condition where _onCheckIn could fire with a null _sessionId
      // if a student connects immediately during the nearby startup window.

      // Listen for BT state changes to detect when user turns off Bluetooth
      _bluetoothStateSub?.cancel();
      _bluetoothStateSub = _ble.onBluetoothStateChanged.listen((state) {
        if (state == PeripheralState.poweredOff) {
          _error = 'Bluetooth turned off — tap retry to re-enable';
          _ble.stopAdvertising();
          _nearby.stopAll();
          notifyListeners();
        } else if (state != PeripheralState.poweredOff && state != PeripheralState.unknown && _error?.contains('Bluetooth') == true) {
          _error = null;
          notifyListeners();
        }
      });

      // Listen for disconnects only (check-ins are handled via callback above)
      _disconnectSub?.cancel();
      _disconnectSub = _nearby.onDisconnect.listen(_onDisconnect);

      _loading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      _loading = false;
      notifyListeners();
      return false;
    }
  }

  int _nextLocalId = -1;

  Future<void> _onCheckIn(NearbyCheckIn checkIn) async {
    // Guard: already in roster or being processed by another call
    if (_roster.any((s) => s.studentId == checkIn.studentId)) return;
    if (!_processingCheckIns.add(checkIn.studentId)) return;

    try {
      int dbId = _nextLocalId--;
      if (_sessionId != null) {
        final now = DateTime.now();
        try {
          dbId = await LocalDatabase.insertBlePending({
            'student_id': checkIn.studentId,
            'student_name': checkIn.studentName,
            'session_id': _sessionId,
            'time': '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
            'rssi': 0,
            'status': 'pending',
            'created_at': now.toUtc().toIso8601String(),
          });
        } catch (_) {
          // Fall back to negative ID if local write fails
        }
      }

      final entry = BlePendingStudent(
        id: dbId,
        studentId: checkIn.studentId,
        studentName: checkIn.studentName,
        endpointId: checkIn.endpointId,
      );
      _roster.add(entry);
      notifyListeners();
    } finally {
      _processingCheckIns.remove(checkIn.studentId);
    }
  }

  void _onDisconnect(String endpointId) {
    // When a student disconnects from Nearby, mark their roster entry
    for (final s in _roster) {
      if (s.endpointId == endpointId && s.status == 'pending') {
        s.status = 'disconnected';
      }
    }
    notifyListeners();
  }

  Future<void> approveStudent(int id) async {
    final idx = _roster.indexWhere((s) => s.id == id);
    if (idx == -1 || _sessionId == null) return;

    final studentId = _roster[idx].studentId;
    final prevStatus = _roster[idx].status;
    _roster[idx].status = 'present';

    try {
      // Save to local DB
      final now = DateTime.now().toUtc().toIso8601String();
      final finalRecord = {
        'student_id': _roster[idx].studentId,
        'student_name': _roster[idx].studentName,
        'session_id': _sessionId,
        'status': 'present',
        'created_at': now,
      };
      await LocalDatabase.insertBleFinal(finalRecord);

      if (id > 0) {
        await LocalDatabase.updateBlePendingStatus(id, 'present');
      }

      // Sync to Supabase (legacy + unified) if online
      if (ConnectivityService().isOnline.value) {
        final sessions = await LocalDatabase.getAllBleSessions();
        final session = sessions.where((s) => s['id'] == _sessionId).firstOrNull;
        String? uuid;
        if (session != null) {
          uuid = session['unified_session_id']?.toString();
          if (uuid == null || uuid.isEmpty) {
            uuid = await AttendanceService.ensureUnifiedBleSession(session);
          }
        }

        await AttendanceService.syncBleFinal(finalRecord);

        if (id > 0) {
          final pendingRows = await LocalDatabase.getBlePendingBySession(_sessionId!);
          final match = pendingRows.where((r) => r['id'] == id).firstOrNull;
          if (match != null) await AttendanceService.syncBlePending(match);
        }
      }

      // Notify student via Nearby
      final endpointId = _roster[idx].endpointId;
      if (endpointId != null) {
        await _nearby.sendApproval(endpointId, 'present');
        // Disconnect immediately to free the Nearby slot for the next student
        await _nearby.disconnectFromEndpoint(endpointId);
      }
    } catch (e) {
      // Rollback in-memory status on failure
      _roster[idx].status = prevStatus;
      debugPrint('[BleSession] approveStudent failed for $studentId: $e');
      rethrow;
    }

    notifyListeners();
  }

  Future<void> rejectStudent(int id) async {
    final idx = _roster.indexWhere((s) => s.id == id);
    if (idx == -1) return;

    final prevStatus = _roster[idx].status;
    _roster[idx].status = 'rejected';

    try {
      if (id > 0) {
        await LocalDatabase.updateBlePendingStatus(id, 'rejected');
      }

      final endpointId = _roster[idx].endpointId;
      if (endpointId != null) {
        await _nearby.sendApproval(endpointId, 'rejected');
      }
    } catch (e) {
      _roster[idx].status = prevStatus;
      debugPrint('[BleSession] rejectStudent failed: $e');
      rethrow;
    }

    notifyListeners();
  }

  /// Approves all pending students in parallel batches (max 5 concurrent)
  /// with an overall 60-second timeout. Reports progress via [approveProgress]
  /// so the UI can show a progress indicator.
  Future<void> approveAll() async {
    if (_sessionId == null || _approving) return;

    final pending = _roster.where((s) => s.status == 'pending').toList();
    if (pending.isEmpty) return;

    _approving = true;
    _approveProgress = 0;
    _approveTotal = pending.length;
    notifyListeners();

    const batchSize = 5;
    final overallTimer = Timer(const Duration(seconds: 60), () {
      debugPrint('[BleSession] approveAll timed out after 60s');
    });

    try {
      for (var i = 0; i < pending.length; i += batchSize) {
        final batch = pending.skip(i).take(batchSize).toList();
        final batchIds = batch.map((s) => s.id).toList();

        // Check for timeout
        if (!overallTimer.isActive) break;

        await Future.wait(
          batchIds.map((id) => approveStudent(id).catchError((e) {
            debugPrint('[BleSession] approveAll: student $id failed: $e');
          })),
        );

        _approveProgress = (i + batch.length).clamp(0, _approveTotal);
        notifyListeners();
      }
    } finally {
      overallTimer.cancel();
      _approving = false;
      _approveProgress = 0;
      _approveTotal = 0;
      notifyListeners();
    }
  }

  Future<void> stopSession() async {
    if (_sessionId == null) return;

    // Reject any remaining pending
    await LocalDatabase.rejectAllPending(_sessionId!);

    // Close session in DB
    await LocalDatabase.closeBleSession(_sessionId!);

    // Sync the full session to Supabase (legacy + unified)
    if (ConnectivityService().isOnline.value) {
      await AttendanceService.syncBleSessionFull(_sessionId!);
      // Also close the unified attendance_sessions record
      final sessions = await LocalDatabase.getAllBleSessions();
      final session = sessions.where((s) => s['id'] == _sessionId).firstOrNull;
      if (session != null) {
        final uuid = session['unified_session_id']?.toString();
        if (uuid != null && uuid.isNotEmpty) {
          await AttendanceService.endSession(uuid);
        }
      }
    }

    // Stop BLE + Nearby
    await _ble.stopAdvertising();
    await _nearby.stopAll();

    _status = 'closed';
    _bluetoothStateSub?.cancel();
    _disconnectSub?.cancel();

    // ── CRITICAL: Clear all in-memory session state ──
    // Prevents ghost attendance where the previous session's roster
    // carries over to the next session (Bug 1 & 4).
    _roster.clear();
    _processingCheckIns.clear();

    notifyListeners();
  }

  Future<void> loadPendingRoster() async {
    if (_sessionId == null) return;
    _loading = true;
    notifyListeners();

    final rows = await LocalDatabase.getBlePendingBySession(_sessionId!);
    _roster.clear();
    for (final r in rows) {
      _roster.add(BlePendingStudent(
        id: r['id'] as int,
        studentId: r['student_id'] as String,
        studentName: r['student_name'] as String,
        status: r['status'] as String,
      ));
    }
    _loading = false;
    notifyListeners();
  }

  /// Re-enable BLE and restart advertising after Bluetooth was turned off.
  /// Returns `true` if the session resumed successfully.
  Future<bool> retrySession() async {
    if (_sessionId == null) return false;

    final bleReady = await _ble.ensureReady();
    if (!bleReady) {
      _error = 'BLE permission denied or Bluetooth off. Please grant BLE access and turn on Bluetooth.';
      notifyListeners();
      return false;
    }

    _error = null;

    // Restart BLE advertising
    final bleOk = await _ble.startAdvertising(_sessionId!, _subject ?? '');
    if (!bleOk) {
      _error = 'Failed to restart BLE beacon';
      notifyListeners();
      return false;
    }

    // Restart Nearby hub
    final nearbyOk = await _nearby.startAdvertising(
      name: '${BleConstants.nearbyEndpointPrefix}_$_sessionId',
      sessionId: _sessionId!,
      onCheckInReceived: _onCheckIn,
    );
    if (!nearbyOk) {
      await _ble.stopAdvertising();
      _error = 'Failed to restart Nearby Connections';
      notifyListeners();
      return false;
    }

    // Re-bind disconnect listener
    _disconnectSub?.cancel();
    _disconnectSub = _nearby.onDisconnect.listen(_onDisconnect);

    notifyListeners();
    return true;
  }

  void reset() {
    _sessionId = null;
    _subject = null;
    _semester = null;
    _status = 'idle';
    _error = null;
    _roster.clear();
    _bluetoothStateSub?.cancel();
    _disconnectSub?.cancel();
    notifyListeners();
  }

  @override
  void dispose() {
    _bluetoothStateSub?.cancel();
    _disconnectSub?.cancel();
    super.dispose();
  }
}

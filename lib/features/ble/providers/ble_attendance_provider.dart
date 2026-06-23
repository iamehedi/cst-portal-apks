import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../../../core/db/local_database.dart';
import '../../../core/ble/ble_student_service.dart';
import '../../../core/ble/nearby_service.dart';
import '../../../services/attendance_service.dart';
import '../../../services/connectivity_service.dart';

class BleAttendanceProvider extends ChangeNotifier {
  final BleStudentService _ble = BleStudentService();
  final NearbyService _nearby = NearbyService();

  String _scanState = 'idle'; // idle | scanning | found | connected | approved | rejected | error
  String? _detectedSessionId;
  String? _detectedSubject;
  int? _detectedRssi;
  String? _statusMessage;
  final bool _loading = false;

  StreamSubscription? _beaconSub;
  StreamSubscription? _approvalSub;
  StreamSubscription<BluetoothAdapterState>? _bluetoothStateSub;
  Timer? _connectTimer;
  Timer? _autoResetTimer;
  Timer? _scanRetryTimer;
  VoidCallback? _isScanningListener;

  /// Duration to wait before auto-resetting after a successful scan.
  static const Duration autoResetDelay = Duration(seconds: 5);

  /// Auto-retry scan when beacon not found within timeout.
  int _scanRetries = 0;
  static const int maxScanRetries = 3;

  /// Guards against double-save of pending for the same session.
  final Set<String> _pendingSavedForSession = {};

  /// ─── State Machine ──────────────────────────────────────────────────────
  /// Correct state flow (no state may be skipped):
  ///   idle → scanning → found (DETECTED) → connecting (CONNECTED)
  ///       → pending (PENDING/check-in submitted) → approved (PRESENT)
  ///       → rejected (ABSENT)
  ///       → error
  ///
  /// The 'found' state means a BLE beacon was detected (DETECTED).
  /// The 'pending' state means the student submitted check-in (PENDING).
  /// These are separate and must not be conflated (Bug 3 fix).

  // Getters
  String get scanState => _scanState;
  String? get detectedSessionId => _detectedSessionId;
  String? get detectedSubject => _detectedSubject;
  int? get detectedRssi => _detectedRssi;
  String? get statusMessage => _statusMessage;
  bool get loading => _loading;
  bool get isScanning => _ble.isScanning.value;

  Future<bool> requestBlePermission() async {
    return _ble.ensureReady();
  }

  Future<void> startScanning() async {
    if (_scanState == 'scanning' || _scanState == 'connected') return;

    final ready = await _ble.ensureReady();
    if (!ready) {
      _scanState = 'error';
      _statusMessage = 'BLE permission denied or Bluetooth off. Please grant access and turn on Bluetooth.';
      notifyListeners();
      return;
    }

    // Reset all per-scan state to ensure clean isolation between sessions
    _pendingSavedForSession.clear();
    _scanState = 'scanning';
    _detectedSessionId = null;
    _detectedSubject = null;
    _detectedRssi = null;
    _statusMessage = 'Searching for class...';
    notifyListeners();

    // Listen for BT turning off mid-scan
    _bluetoothStateSub?.cancel();
    _bluetoothStateSub = _ble.onAdapterStateChanged.listen((state) {
      if (state == BluetoothAdapterState.off && _scanState == 'scanning') {
        _ble.stopScan();
        _scanState = 'error';
        _statusMessage = 'Bluetooth turned off. Tap retry to re-enable.';
        notifyListeners();
      } else if (state == BluetoothAdapterState.on &&
          _statusMessage?.contains('Bluetooth') == true) {
        _statusMessage = 'Bluetooth restored — tap scan to continue';
        notifyListeners();
      }
    });

    _scanRetries = 0;

    // Listen for scan timeout — auto-retry up to maxScanRetries times
    void onScanStopped(bool scanning) {
      if (scanning) return;
      if (_scanState != 'scanning') return;
      if (_detectedSessionId != null) return;
      if (_scanRetries >= maxScanRetries) {
        _scanRetries = 0;
        _scanState = 'error';
        _statusMessage = 'No class found after $_scanRetries attempts. Make sure you\'re near the teacher.';
        notifyListeners();
        return;
      }
      _scanRetries++;
      _statusMessage = 'Searching for class... (attempt $_scanRetries/$maxScanRetries)';
      notifyListeners();
      _scanRetryTimer?.cancel();
      _scanRetryTimer = Timer(const Duration(seconds: 2), () {
        if (_scanState == 'scanning' && _detectedSessionId == null) {
          _ble.startScan();
        }
      });
    }

    // Hook into isScanning changes for auto-retry
    _isScanningListener = () => onScanStopped(_ble.isScanning.value);
    _ble.isScanning.addListener(_isScanningListener!);

    _beaconSub = _ble.onBeaconFound.listen((result) {
      if (_detectedSessionId != null) return;

      _detectedSessionId = result.sessionId;
      _detectedSubject = result.subject;
      _detectedRssi = result.rssi;
      _scanState = 'found';
      _statusMessage = 'Class Found — $_detectedSubject';
      notifyListeners();

      _ble.stopScan();
      _autoConnect();
    });

    await _ble.startScan();
  }

  String _studentId = '';
  String _studentName = '';

  /// Set identity from the caller (student's profile).
  void setIdentity(String studentId, String studentName) {
    _studentId = studentId;
    _studentName = studentName;
  }

  Future<void> _autoConnect() async {
    if (_detectedSessionId == null || _studentId.isEmpty) return;

    _statusMessage = 'Connecting...';
    _scanState = 'connecting';
    notifyListeners();

    final isDuplicate = await LocalDatabase.hasBleDuplicate(_studentId, _detectedSessionId!);
    if (_scanState != 'connecting') return;
    if (isDuplicate) {
      _scanState = 'error';
      _statusMessage = 'Already checked in for this session';
      notifyListeners();
      return;
    }

    _connectTimer?.cancel();
    _connectTimer = Timer(const Duration(seconds: 8), () {
      if (_scanState != 'connecting') return;
      _nearby.stopAll();
      _savePending();
      _scanState = 'pending';
      _statusMessage = 'Check-in submitted! Waiting for teacher approval.';
      notifyListeners();
    });

    if (_scanState != 'connecting') return;

    final ok = await _nearby.startDiscovery(
      studentName: _studentName,
      studentId: _studentId,
      sessionId: _detectedSessionId!,
      onConnected: () {
        _connectTimer?.cancel();
        _statusMessage = 'Connected to session';
        notifyListeners();
      },
      onConnectionFailed: () {
        _connectTimer?.cancel();
        if (_scanState != 'connecting') return;
        _savePending();
        _scanState = 'pending';
        _statusMessage = 'Check-in submitted! Waiting for teacher approval.';
        notifyListeners();
      },
      onApproval: (status) async {
        _connectTimer?.cancel();
        if (status == 'present') {
          _scanState = 'approved';
          _statusMessage = 'Present ✅';
        } else {
          _scanState = 'rejected';
          _statusMessage = 'Rejected ❌';
        }
        await _saveRecord();
        _nearby.stopAll();
        notifyListeners();
        _scheduleAutoReset();
      },
    );

    if (_scanState != 'connecting') return;

    if (!ok) {
      _connectTimer?.cancel();
      await _savePending();
      _scanState = 'pending';
      _statusMessage = 'Check-in submitted! Waiting for teacher approval.';
      notifyListeners();
    }
  }

  Future<void> _savePending() async {
    if (_detectedSessionId == null) return;
    final sessionKey = '$_studentId:$_detectedSessionId';
    if (!_pendingSavedForSession.add(sessionKey)) return; // Already saved
    final now = DateTime.now();
    try {
      await LocalDatabase.insertBlePending({
        'student_id': _studentId,
        'student_name': _studentName,
        'session_id': _detectedSessionId,
        'time': '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
        'rssi': _detectedRssi ?? 0,
        'status': 'pending',
        'created_at': now.toUtc().toIso8601String(),
      });
    } catch (e) {
      _pendingSavedForSession.remove(sessionKey);
      debugPrint('[BleAttendance] _savePending error: $e');
    }
  }

  Future<void> _saveRecord() async {
    if (_detectedSessionId == null) return;
    try {
      final now = DateTime.now();
      final status = _scanState == 'approved' ? 'present' : 'rejected';

      final record = {
        'student_id': _studentId,
        'student_name': _studentName,
        'session_id': _detectedSessionId,
        'status': status,
        'created_at': now.toUtc().toIso8601String(),
      };
      await LocalDatabase.insertBleFinal(record);

      if (ConnectivityService().isOnline.value) {
        await AttendanceService.syncBleFinal(record);
      }
    } catch (e) {
      debugPrint('[BleAttendanceProvider] _saveRecord error: $e');
    }
  }

  /// Retry scanning after Bluetooth was turned off — re-prompts permissions
  /// and restarts the BLE scan from scratch.
  Future<void> retryScan() async {
    final ready = await _ble.ensureReady();
    if (!ready) {
      _scanState = 'error';
      _statusMessage = 'BLE permission denied or Bluetooth off. Please grant access and turn on Bluetooth.';
      notifyListeners();
      return;
    }
    // Reset state and start fresh
    _scanState = 'idle';
    _statusMessage = 'Ready to scan';
    notifyListeners();
    await startScanning();
  }

  Future<void> stopScanning() async {
    await _ble.stopScan();
    _beaconSub?.cancel();
    if (_scanState == 'scanning') {
      _scanState = 'idle';
    }
    notifyListeners();
  }

  /// Schedule an automatic reset back to idle after [autoResetDelay].
  /// Lets the student see the success message briefly, then returns to
  /// the start-scanning state so they can scan another subject.
  ///
  /// Uses [Timer] for both stages so [reset()] can properly cancel the
  /// entire sequence — avoids the race where a manual "Scan Another Session"
  /// click during the transition window could be overwritten by a stale
  /// [Future.delayed] callback.
  void _scheduleAutoReset() {
    _autoResetTimer?.cancel();
    // Stage 1: show success message for [autoResetDelay]
    _autoResetTimer = Timer(autoResetDelay, () {
      if (_scanState == 'approved' || _scanState == 'rejected') {
        // Stage 2: brief transition message before going idle
        _statusMessage = 'Ready to scan again';
        notifyListeners();
        _autoResetTimer = Timer(const Duration(milliseconds: 800), () {
          reset();
        });
      }
    });
  }

  /// Synchronously reset all state to idle — safe to call from initState.
  void reset() {
    _autoResetTimer?.cancel();
    _autoResetTimer = null;
    _connectTimer?.cancel();
    _scanRetryTimer?.cancel();
    _scanRetries = 0;
    _ble.stopScan(); // fire-and-forget: stop any lingering BLE hardware scan
    _nearby.stopAll(); // fire-and-forget: stop any nearby connections cleanup
    _beaconSub?.cancel();
    _beaconSub = null;
    _bluetoothStateSub?.cancel();
    _bluetoothStateSub = null;
    _approvalSub?.cancel();
    if (_isScanningListener != null) {
      _ble.isScanning.removeListener(_isScanningListener!);
      _isScanningListener = null;
    }
    _scanState = 'idle';
    _detectedSessionId = null;
    _detectedSubject = null;
    _detectedRssi = null;
    _statusMessage = null;
    _pendingSavedForSession.clear();
    notifyListeners();
  }

  Future<void> disconnect() async {
    reset();
    await _nearby.stopAll();
  }

  Future<String?> getFinalStatus(String sessionId, String studentId) async {
    return LocalDatabase.getBleFinalStatus(studentId, sessionId);
  }

  @override
  void dispose() {
    _autoResetTimer?.cancel();
    _connectTimer?.cancel();
    _scanRetryTimer?.cancel();
    _beaconSub?.cancel();
    _bluetoothStateSub?.cancel();
    _approvalSub?.cancel();
    if (_isScanningListener != null) {
      _ble.isScanning.removeListener(_isScanningListener!);
      _isScanningListener = null;
    }
    _ble.dispose();
    super.dispose();
  }
}

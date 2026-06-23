import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:meta/meta.dart';
import 'ble_constants.dart';

class NearbyCheckIn {
  final String endpointId;
  final String studentId;
  final String studentName;

  NearbyCheckIn({required this.endpointId, required this.studentId, required this.studentName});
}

class NearbyService {
  NearbyService._() : _nearby = Nearby();
  static final NearbyService _instance = NearbyService._();
  factory NearbyService() => _instance;

  final Nearby _nearby;

  /// Maximum simultaneous Nearby Connections in P2P_STAR mode.
  /// Tuned for 60-student classes — slots cycle quickly as approved students
  /// or QR checks get disconnected to free capacity.
  static const int maxConcurrentConnections = 12;

  /// Shorter capacity for the QR bridge (lighter usage).
  static const int maxConcurrentQrBridge = 20;

  final ValueNotifier<bool> isActive = ValueNotifier(false);
  final ValueNotifier<int> connectedCount = ValueNotifier(0);

  final StreamController<NearbyCheckIn> _checkInCtrl = StreamController<NearbyCheckIn>.broadcast();
  Stream<NearbyCheckIn> get onCheckIn => _checkInCtrl.stream;

  final StreamController<String> _disconnectCtrl = StreamController<String>.broadcast();
  Stream<String> get onDisconnect => _disconnectCtrl.stream;

  final Set<String> _connectedEndpoints = {};
  final Map<String, String> _endpointNames = {};

  /// Tracks endpointId by studentId to ensure one check-in per student.
  final Map<String, String> _studentToEndpoint = {};

  /// Timer for cleaning up stale endpoints that never sent a check-in.
  Timer? _staleCleanupTimer;

  /// QR + BLE offline bridge state.
  bool _qrBridgeActive = false;
  void Function(Map<String, dynamic>)? _onQrOfflineCheckIn;

  bool get hasCapacity => _connectedEndpoints.length < maxConcurrentConnections;

  List<({String endpointId, String name, bool connected})> get connectedPeers {
    return _connectedEndpoints.map((e) => (
      endpointId: e,
      name: _endpointNames[e] ?? 'Unknown',
      connected: true,
    )).toList();
  }

  void _startStaleCleanup(void Function(NearbyCheckIn) onCheckInReceived) {
    _staleCleanupTimer?.cancel();
    _staleCleanupTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _connectedEndpoints.removeWhere((ep) {
        final kept = _studentToEndpoint.containsValue(ep);
        if (!kept) {
          debugPrint('[Nearby] Cleaning stale endpoint: $ep');
          _endpointNames.remove(ep);
          _nearby.disconnectFromEndpoint(ep);
        }
        return !kept;
      });
      connectedCount.value = _connectedEndpoints.length;
    });
  }

  Future<bool> startAdvertising({
    required String name,
    required String sessionId,
    required void Function(NearbyCheckIn checkIn) onCheckInReceived,
  }) async {
    try {
      _startStaleCleanup(onCheckInReceived);
      final result = await _nearby.startAdvertising(
        name,
        Strategy.P2P_STAR,
        serviceId: BleConstants.nearbyServiceId,
        onConnectionInitiated: (endpointId, connectionInfo) async {
          debugPrint('[Nearby] Connection from: ${connectionInfo.endpointName} ($endpointId)');

          // Admission control: reject if at capacity
          if (!hasCapacity) {
            debugPrint('[Nearby] At capacity ($maxConcurrentConnections), rejecting $endpointId');
            await _nearby.rejectConnection(endpointId);
            return;
          }

          _endpointNames[endpointId] = connectionInfo.endpointName;

          // Create a preliminary roster entry from the connection info.
          // The student now encodes their name and ID as "name|id" in the
          // endpoint name, so even if sendBytesPayload fails, the teacher
          // still has the student's identity.
          final parts = connectionInfo.endpointName.split('|');
          final studentName = parts.isNotEmpty ? parts[0] : connectionInfo.endpointName;
          final studentId = parts.length > 1 ? parts[1] : '';
          if (studentId.isNotEmpty && studentName.isNotEmpty) {
            final preliminaryCheckIn = NearbyCheckIn(
              endpointId: endpointId,
              studentId: studentId,
              studentName: studentName,
            );
            onCheckInReceived(preliminaryCheckIn);
          }

          await _nearby.acceptConnection(
            endpointId,
            onPayLoadRecieved: (epId, payload) {
              _handlePayload(epId, payload, onCheckInReceived);
            },
          );
        },
        onConnectionResult: (endpointId, status) {
          if (status == Status.CONNECTED) {
            debugPrint('[Nearby] Connected: $endpointId');
            _connectedEndpoints.add(endpointId);
            connectedCount.value = _connectedEndpoints.length;
          } else {
            debugPrint('[Nearby] Connection failed: $endpointId ($status)');
            _endpointNames.remove(endpointId);
          }
        },
        onDisconnected: (endpointId) {
          debugPrint('[Nearby] Disconnected: $endpointId');
          _connectedEndpoints.remove(endpointId);
          _endpointNames.remove(endpointId);
          _studentToEndpoint.removeWhere((_, v) => v == endpointId);
          connectedCount.value = _connectedEndpoints.length;
          _disconnectCtrl.add(endpointId);
        },
      );
      if (result) {
        isActive.value = true;
      }
      return result;
    } catch (e) {
      debugPrint('[Nearby] startAdvertising error: $e');
      return false;
    }
  }

  void _handlePayload(String endpointId, Payload payload, void Function(NearbyCheckIn) onCheckInReceived) {
    try {
      if (payload.type == PayloadType.BYTES && payload.bytes != null) {
        final data = utf8.decode(payload.bytes!);
        final json = jsonDecode(data) as Map<String, dynamic>;
        if (json['type'] == BleConstants.payloadTypeCheckIn) {
          final studentId = json['studentId'] as String;

          // Deduplicate: prevent duplicate check-in from same student
          final existingEndpoint = _studentToEndpoint[studentId];
          if (existingEndpoint != null && existingEndpoint != endpointId) {
            debugPrint('[Nearby] Duplicate check-in from $studentId (already from $existingEndpoint)');
            return;
          }
          _studentToEndpoint[studentId] = endpointId;

          final checkIn = NearbyCheckIn(
            endpointId: endpointId,
            studentId: studentId,
            studentName: json['studentName'] as String,
          );
          _checkInCtrl.add(checkIn);
          onCheckInReceived(checkIn);
        }
      }
    } catch (e) {
      debugPrint('[Nearby] Payload decode error: $e');
    }
  }

  Future<bool> startDiscovery({
    required String studentName,
    required String studentId,
    required String sessionId,
    void Function()? onConnected,
    void Function()? onConnectionFailed,
    void Function(String status)? onApproval,
  }) async {
    String? matchedEndpointId;

    try {
      return await _nearby.startDiscovery(
        studentName,
        Strategy.P2P_STAR,
        serviceId: BleConstants.nearbyServiceId,
        onEndpointFound: (endpointId, deviceName, serviceId) async {
          if (deviceName.startsWith(BleConstants.nearbyEndpointPrefix)) {
            final discoveredSessionId = deviceName.replaceFirst('${BleConstants.nearbyEndpointPrefix}_', '');
            if (discoveredSessionId == sessionId && matchedEndpointId == null) {
              matchedEndpointId = endpointId;
              debugPrint('[Nearby] Found teacher: $deviceName');
              // Encode student ID in the endpoint name so the teacher can
              // extract it even if the follow-up payload send fails.
              final endpointName = '$studentName|$studentId';
              await _nearby.requestConnection(
                endpointName,
                endpointId,
                onConnectionInitiated: (epId, connectionInfo) async {
                  await _nearby.acceptConnection(
                    epId,
                    onPayLoadRecieved: (endpointId, payload) {
                      _handleApprovalPayload(payload, onApproval);
                    },
                  );
                },
                onConnectionResult: (epId, status) {
                  if (status == Status.CONNECTED) {
                    debugPrint('[Nearby] Connected to teacher');
                    isActive.value = true;
                    _connectedEndpoints.add(epId);
                    connectedCount.value = _connectedEndpoints.length;
                    onConnected?.call();
                    _sendCheckIn(epId, studentId, studentName);
                  } else {
                    debugPrint('[Nearby] Connection to teacher failed: $status');
                    onConnectionFailed?.call();
                  }
                },
                onDisconnected: (epId) {
                  _connectedEndpoints.remove(epId);
                  connectedCount.value = _connectedEndpoints.length;
                  _disconnectCtrl.add(epId);
                },
              );
            }
          }
        },
        onEndpointLost: (endpointId) {
          if (endpointId == matchedEndpointId) {
            matchedEndpointId = null;
          }
        },
      );
    } catch (e) {
      debugPrint('[Nearby] startDiscovery error: $e');
      return false;
    }
  }

  void _handleApprovalPayload(Payload payload, void Function(String)? onApproval) {
    try {
      if (payload.type == PayloadType.BYTES && payload.bytes != null) {
        final data = utf8.decode(payload.bytes!);
        final json = jsonDecode(data) as Map<String, dynamic>;
        if (json['type'] == BleConstants.payloadTypeApproval) {
          onApproval?.call(json['status'] as String);
        }
      }
    } catch (e) {
      debugPrint('[Nearby] Approval payload decode error: $e');
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  //  QR + BLE Offline Bridge — Teacher Side
  // ──────────────────────────────────────────────────────────────────────────

  /// Start a lightweight Nearby hub for receiving QR offline check-ins.
  ///
  /// The teacher's QR session screen calls this alongside displaying the QR
  /// code. Students who scanned the QR offline can then deliver their check-in
  /// via Nearby, which auto-accepts (no teacher approval needed).
  ///
  /// Returns `true` if advertising started successfully.
  Future<bool> startQrBridge({
    required String sessionId,
    required void Function(Map<String, dynamic> payload) onQrOfflineCheckIn,
  }) async {
    if (_qrBridgeActive) return true;
    _onQrOfflineCheckIn = onQrOfflineCheckIn;

    // ── CRITICAL: Safely clean up any lingering Nearby state ──
    // Each stop call must be individually try-caught because the Nearby
    // singleton may throw if there's nothing to stop (e.g. first-time use,
    // or when transitioning from a clean state). A single try-catch around
    // all of them would abort on the first failure and never reach start().
    try { await _nearby.stopAdvertising(); } catch (_) {}
    try { await _nearby.stopDiscovery(); } catch (_) {}
    try { await _nearby.stopAllEndpoints(); } catch (_) {}
    _connectedEndpoints.clear();
    _endpointNames.clear();
    _studentToEndpoint.clear();
    _qrBridgeActive = false;

    try {
      final result = await _nearby.startAdvertising(
        '${BleConstants.qrBridgePrefix}_$sessionId',
        Strategy.P2P_STAR,
        serviceId: BleConstants.nearbyServiceId,
        onConnectionInitiated: (endpointId, connectionInfo) async {
          debugPrint('[QrBridge] Connection from: ${connectionInfo.endpointName} ($endpointId)');

          if (_connectedEndpoints.length >= maxConcurrentQrBridge) {
            debugPrint('[QrBridge] At capacity, rejecting $endpointId');
            await _nearby.rejectConnection(endpointId);
            return;
          }

          await _nearby.acceptConnection(
            endpointId,
            onPayLoadRecieved: (epId, payload) {
              _handleQrBridgePayload(epId, payload);
            },
          );
        },
        onConnectionResult: (endpointId, status) {
          if (status == Status.CONNECTED) {
            debugPrint('[QrBridge] Connected: $endpointId');
            _connectedEndpoints.add(endpointId);
            connectedCount.value = _connectedEndpoints.length;
          }
        },
        onDisconnected: (endpointId) {
          _connectedEndpoints.remove(endpointId);
          connectedCount.value = _connectedEndpoints.length;
        },
      );

      if (result) {
        _qrBridgeActive = true;
        isActive.value = true;
      }
      return result;
    } catch (e) {
      debugPrint('[QrBridge] start error: $e');
      return false;
    }
  }

  void _handleQrBridgePayload(String endpointId, Payload payload) {
    try {
      if (payload.type == PayloadType.BYTES && payload.bytes != null) {
        final data = utf8.decode(payload.bytes!);
        final json = jsonDecode(data) as Map<String, dynamic>;
        if (json['type'] == BleConstants.payloadTypeQrOffline) {
          debugPrint('[QrBridge] Received QR offline check-in: ${json['student_name']}');
          _onQrOfflineCheckIn?.call(json);
        }
      }
    } catch (e) {
      debugPrint('[QrBridge] payload error: $e');
    }
  }

  Future<void> stopQrBridge() async {
    _qrBridgeActive = false;
    _onQrOfflineCheckIn = null;
    try {
      await _nearby.stopAdvertising();
      await _nearby.stopAllEndpoints();
    } catch (e) {
      debugPrint('[QrBridge] stop error: $e');
    }
    _connectedEndpoints.clear();
    isActive.value = false;
    connectedCount.value = 0;
  }

  // ──────────────────────────────────────────────────────────────────────────
  //  QR + BLE Offline Bridge — Student Side
  // ──────────────────────────────────────────────────────────────────────────

  /// Start discovery for the teacher's QR bridge hub.
  ///
  /// After the student scans the QR code offline, this tries to find the
  /// teacher's Nearby hub (advertised as `QR_BRIDGE_<sessionId>`), connect,
  /// and deliver the full check-in payload via BLE.
  ///
  /// Returns `true` if the payload was delivered successfully.
  Future<bool> startQrDiscovery({
    required String studentName,
    required String studentId,
    required String sessionId,
    required String sessionToken,
  }) async {
    String? matchedEndpointId;
    final completer = Completer<bool>();
    Timer? timeout;

    timeout = Timer(Duration(seconds: BleConstants.qrBridgeTimeoutSec), () {
      if (!completer.isCompleted) {
        debugPrint('[QrBridge] Discovery timeout for session $sessionId');
        completer.complete(false);
      }
    });

    try {
      await _nearby.startDiscovery(
        '$studentName|$studentId',
        Strategy.P2P_STAR,
        serviceId: BleConstants.nearbyServiceId,
        onEndpointFound: (endpointId, deviceName, serviceId) async {
          if (!deviceName.startsWith(BleConstants.qrBridgePrefix)) return;
          final discoveredSessionId =
              deviceName.replaceFirst('${BleConstants.qrBridgePrefix}_', '');
          if (discoveredSessionId != sessionId || matchedEndpointId != null) return;

          matchedEndpointId = endpointId;
          debugPrint('[QrBridge] Found teacher hub: $deviceName');

          await _nearby.requestConnection(
            '$studentName|$studentId',
            endpointId,
            onConnectionInitiated: (epId, connectionInfo) async {
              await _nearby.acceptConnection(
                epId,
                onPayLoadRecieved: (_, payload) {
                  _handleApprovalPayload(payload, (_) {
                    // QR bridge doesn't need approval — connection confirms delivery
                  });
                },
              );
            },
            onConnectionResult: (epId, status) async {
              if (status == Status.CONNECTED) {
                debugPrint('[QrBridge] Connected to teacher hub');
                _connectedEndpoints.add(epId);
                connectedCount.value = _connectedEndpoints.length;

                // Send QR offline check-in payload
                final payload = jsonEncode({
                  'type': BleConstants.payloadTypeQrOffline,
                  'student_id': studentId,
                  'student_name': studentName,
                  'session_token': sessionToken,
                  'timestamp': DateTime.now().toUtc().toIso8601String(),
                  'method': 'QR_OFFLINE',
                });
                final bytes = Uint8List.fromList(utf8.encode(payload));

                final sent = await NearbyService.sendWithRetry(
                  () => _nearby.sendBytesPayload(epId, bytes),
                );

                if (!completer.isCompleted) {
                  timeout?.cancel();
                  completer.complete(sent);
                }

                // Disconnect promptly to free the slot
                await _nearby.disconnectFromEndpoint(epId);
              } else {
                debugPrint('[QrBridge] Connection failed: $status');
              }
            },
            onDisconnected: (epId) {
              _connectedEndpoints.remove(epId);
              connectedCount.value = _connectedEndpoints.length;
              if (epId == matchedEndpointId && !completer.isCompleted) {
                timeout?.cancel();
                completer.complete(false);
              }
            },
          );
        },
        onEndpointLost: (endpointId) {
          if (endpointId == matchedEndpointId) {
            matchedEndpointId = null;
          }
        },
      );

      return await completer.future;
    } catch (e) {
      debugPrint('[QrBridge] startQrDiscovery error: $e');
      timeout?.cancel();
      return false;
    }
  }

  // ── Utility ──────────────────────────────────────────────────────────────

  /// Send a bytes payload with retry logic.
  ///
  /// Retries up to 3 times with a 2-second timeout per attempt and 500ms
  /// delay between retries. Exposed as package-visible for unit testing.
  @visibleForTesting
  static Future<bool> sendWithRetry(Future<void> Function() sendFn) async {
    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        await sendFn().timeout(const Duration(seconds: 2));
        return true; // Success
      } catch (_) {
        if (attempt < 2) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }
    }
    return false; // All retries exhausted
  }

  Future<void> _sendCheckIn(String endpointId, String studentId, String studentName) async {
    final payload = jsonEncode({
      'type': BleConstants.payloadTypeCheckIn,
      'studentId': studentId,
      'studentName': studentName,
    });
    final bytes = Uint8List.fromList(utf8.encode(payload));

    // Retry up to 3 times with a short delay; the student ID is already
    // transmitted via the endpoint name (see startDiscovery), so this is
    // a best-effort delivery — the teacher's roster already has the info.
    final success = await sendWithRetry(() => _nearby.sendBytesPayload(endpointId, bytes));
    if (success) {
      debugPrint('[Nearby] Sent check-in for $studentName');
    } else {
      debugPrint('[Nearby] All sendCheckIn attempts failed for $studentName (ID: $studentId)');
    }
  }

  /// Disconnect a specific endpoint to free a Nearby slot for another student.
  Future<void> disconnectFromEndpoint(String endpointId) async {
    try {
      await _nearby.disconnectFromEndpoint(endpointId);
    } catch (e) {
      debugPrint('[Nearby] disconnectFromEndpoint error: $e');
    }
    _connectedEndpoints.remove(endpointId);
    _endpointNames.remove(endpointId);
    _studentToEndpoint.removeWhere((_, v) => v == endpointId);
    connectedCount.value = _connectedEndpoints.length;
  }

  Future<void> sendApproval(String endpointId, String status) async {
    final payload = jsonEncode({
      'type': BleConstants.payloadTypeApproval,
      'status': status,
    });
    try {
      await _nearby.sendBytesPayload(endpointId, Uint8List.fromList(utf8.encode(payload)));
      debugPrint('[Nearby] Sent approval: $status to $endpointId');
    } catch (e) {
      debugPrint('[Nearby] sendApproval error: $e');
    }
  }

  Future<void> stopAll() async {
    _staleCleanupTimer?.cancel();
    _staleCleanupTimer = null;
    try {
      await _nearby.stopAdvertising();
    } catch (e) {
      debugPrint('[Nearby] stopAdvertising error: $e');
    }
    try {
      await _nearby.stopDiscovery();
    } catch (e) {
      debugPrint('[Nearby] stopDiscovery error: $e');
    }
    try {
      await _nearby.stopAllEndpoints();
    } catch (e) {
      debugPrint('[Nearby] stopAllEndpoints error: $e');
    }
    _connectedEndpoints.clear();
    _endpointNames.clear();
    _studentToEndpoint.clear();
    isActive.value = false;
    connectedCount.value = 0;
  }

  Future<void> dispose() async {
    await stopAll();
    await _checkInCtrl.close();
    await _disconnectCtrl.close();
  }
}

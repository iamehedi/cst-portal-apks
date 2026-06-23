import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BleConstants {
  BleConstants._();

  static const String serviceUuid = '0000cafe-0000-1000-8000-00805f9b34fb';
  static const int manufacturerId = 0xFFFF;
  static const int rssiThreshold = -75;

  static const int scanDurationSeconds = 10;
  static const int scanPauseSeconds = 5;

  static const Duration bleBeaconInterval = Duration(milliseconds: 500);

  static const String nearbyServiceId = 'cst_attendance';

  static final Guid bleServiceGuid = Guid(serviceUuid);

  static const String nearbyEndpointPrefix = 'CST_ATT';

  static const String payloadTypeCheckIn = 'check_in';
  static const String payloadTypeApproval = 'approval';

  // ── QR + BLE Offline Bridge ─────────────────────────────────────────────
  /// Payload type for QR-scanned attendance delivered via BLE.
  static const String payloadTypeQrOffline = 'qr_offline_checkin';

  /// Prefix used in the teacher's Nearby endpoint name for QR bridge.
  static const String qrBridgePrefix = 'QR_BRIDGE';

  /// Timeout (seconds) for the student to wait for BLE bridge confirmation
  /// before falling back to offline-only.
  static const int qrBridgeTimeoutSec = 15;
}

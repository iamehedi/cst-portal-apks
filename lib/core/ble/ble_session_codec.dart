import 'dart:convert';
import 'dart:typed_data';

class BleSessionCodec {
  BleSessionCodec._();

  /// Encode session data into bytes for BLE advertisement manufacturer data.
  /// Format: "ATT|{sessionId}|{subject}" as UTF-8.
  static Uint8List encode(String sessionId, String subject) {
    final payload = 'ATT|$sessionId|$subject';
    return Uint8List.fromList(utf8.encode(payload));
  }

  /// Decode manufacturer data bytes back to (sessionId, subject).
  /// Returns null if the data is not a valid attendance beacon.
  static ({String sessionId, String subject})? decode(Uint8List data) {
    try {
      final str = utf8.decode(data);
      if (!str.startsWith('ATT|')) return null;
      final parts = str.split('|');
      if (parts.length < 3) return null;
      return (sessionId: parts[1], subject: parts.sublist(2).join('|'));
    } catch (_) {
      return null;
    }
  }
}

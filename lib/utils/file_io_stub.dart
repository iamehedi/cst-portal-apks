import 'dart:typed_data';

/// Read file bytes from a filesystem path.
/// Returns null on platforms where dart:io is not available (web).
Future<Uint8List?> readFileBytes(String path) async {
  // Stub: dart:io is not available on web.
  return null;
}

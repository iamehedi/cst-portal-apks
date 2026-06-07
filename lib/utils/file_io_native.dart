import 'dart:io';
import 'dart:typed_data';

/// Read file bytes from a filesystem path (uses dart:io).
Future<Uint8List?> readFileBytes(String path) async {
  return await File(path).readAsBytes();
}

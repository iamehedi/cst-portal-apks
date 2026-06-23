import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'ble_constants.dart';
import 'ble_session_codec.dart';

class BleScanResult {
  final String sessionId;
  final String subject;
  final int rssi;

  BleScanResult({
    required this.sessionId,
    required this.subject,
    required this.rssi,
  });

  bool get isValid => rssi > BleConstants.rssiThreshold;
}

class BleStudentService {
  BleStudentService._();
  static final BleStudentService _instance = BleStudentService._();
  factory BleStudentService() => _instance;

  final ValueNotifier<bool> isScanning = ValueNotifier(false);
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<BluetoothAdapterState>? _adapterStateSub;
  StreamSubscription<bool>? _isScanningSub;

  final StreamController<BleScanResult> _resultCtrl = StreamController<BleScanResult>.broadcast();
  Stream<BleScanResult> get onBeaconFound => _resultCtrl.stream;

  final StreamController<BluetoothAdapterState> _adapterStateCtrl = StreamController<BluetoothAdapterState>.broadcast();
  Stream<BluetoothAdapterState> get onAdapterStateChanged => _adapterStateCtrl.stream;

  /// Request BLE scan permissions and prompt to turn on Bluetooth.
  /// Returns `true` if all requirements are met.
  Future<bool> ensureReady() async {
    // Start monitoring BT adapter state changes for re-prompt support
    _adapterStateSub?.cancel();
    _adapterStateSub = FlutterBluePlus.adapterState.listen((state) {
      _adapterStateCtrl.add(state);
    });

    // Android 12+ needs BLUETOOTH_SCAN + BLUETOOTH_CONNECT
    // Android <12 needs ACCESS_FINE_LOCATION
    final scanGranted = await Permission.bluetoothScan.request().isGranted;
    final connectGranted = await Permission.bluetoothConnect.request().isGranted;
    final locationGranted = await Permission.locationWhenInUse.request().isGranted;
    if (scanGranted && connectGranted) {
      await FlutterBluePlus.turnOn();
      final status = await FlutterBluePlus.adapterState.first;
      if (status == BluetoothAdapterState.on) return true;
      debugPrint('[BleStudent] Bluetooth is off after turnOn request');
      return false;
    } else if (locationGranted && connectGranted) {
      await FlutterBluePlus.turnOn();
      final status = await FlutterBluePlus.adapterState.first;
      if (status == BluetoothAdapterState.on) return true;
      debugPrint('[BleStudent] Bluetooth is off after turnOn request');
      return false;
    }
    if (await Permission.bluetoothScan.isPermanentlyDenied ||
        await Permission.bluetoothConnect.isPermanentlyDenied ||
        await Permission.locationWhenInUse.isPermanentlyDenied) {
      debugPrint('[BleStudent] BLE permission permanently denied');
      return false;
    }
    debugPrint('[BleStudent] BLE permission not granted');
    return false;
  }

  Future<void> startScan() async {
    if (isScanning.value) return;
    _scanSub?.cancel();
    _scanSub = null;

    _isScanningSub?.cancel();
    _isScanningSub = FlutterBluePlus.isScanning.listen((scanning) {
      isScanning.value = scanning;
    });

    try {
      _scanSub = FlutterBluePlus.onScanResults.listen((results) {
        for (final result in results) {
          final data = result.advertisementData.manufacturerData;
          final bytes = data[BleConstants.manufacturerId];
          if (bytes == null || bytes.isEmpty) continue;

          final decoded = BleSessionCodec.decode(Uint8List.fromList(bytes));
          if (decoded == null) continue;

          final scanResult = BleScanResult(
            sessionId: decoded.sessionId,
            subject: decoded.subject,
            rssi: result.rssi,
          );

          if (scanResult.isValid) {
            _resultCtrl.add(scanResult);
          }
        }
      });

      await FlutterBluePlus.startScan(
        withMsd: [MsdFilter(BleConstants.manufacturerId)],
        timeout: const Duration(seconds: 30),
      );
    } catch (e) {
      debugPrint('[BleStudent] startScan error: $e');
    }
  }

  Future<void> stopScan() async {
    try {
      _scanSub?.cancel();
      _scanSub = null;
      await FlutterBluePlus.stopScan();
    } catch (e) {
      debugPrint('[BleStudent] stopScan error: $e');
    }
    isScanning.value = false;
  }

  void dispose() {
    _scanSub?.cancel();
    _isScanningSub?.cancel();
    _adapterStateSub?.cancel();
    _resultCtrl.close();
    _adapterStateCtrl.close();
  }
}

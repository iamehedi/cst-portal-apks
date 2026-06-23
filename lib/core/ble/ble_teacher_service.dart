import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:permission_handler/permission_handler.dart';
import 'ble_constants.dart';
import 'ble_session_codec.dart';

class BleTeacherService {
  BleTeacherService._();
  static final BleTeacherService _instance = BleTeacherService._();
  factory BleTeacherService() => _instance;

  final FlutterBlePeripheral _peripheral = FlutterBlePeripheral();

  final ValueNotifier<bool> isAdvertising = ValueNotifier(false);
  StreamSubscription<PeripheralState>? _stateSub;

  final StreamController<PeripheralState> _bluetoothStateCtrl = StreamController<PeripheralState>.broadcast();
  Stream<PeripheralState> get onBluetoothStateChanged => _bluetoothStateCtrl.stream;

  Stream<PeripheralState>? get onStateChanged => _peripheral.onPeripheralStateChanged;

  /// Request BLE permissions and prompt to turn on Bluetooth.
  /// Returns `true` if all requirements are met.
  Future<bool> ensureReady() async {
    // Android 12+ needs BLUETOOTH_ADVERTISE + BLUETOOTH_CONNECT
    // Android <12 needs ACCESS_FINE_LOCATION
    final advertiseGranted = await Permission.bluetoothAdvertise.request().isGranted;
    final connectGranted = await Permission.bluetoothConnect.request().isGranted;
    final locationGranted = await Permission.locationWhenInUse.request().isGranted;
    if (advertiseGranted || locationGranted) {
      // Permission granted, now ensure Bluetooth is on
      if (await _peripheral.isBluetoothOn != true) {
        if (connectGranted) {
          final enabled = await _peripheral.enableBluetooth(askUser: true);
          if (!enabled) {
            debugPrint('[BleTeacher] Bluetooth not enabled by user');
            return false;
          }
        } else {
          debugPrint('[BleTeacher] BLUETOOTH_CONNECT not granted, cannot enable Bluetooth');
          return false;
        }
      }
      return true;
    }
    if (await Permission.bluetoothAdvertise.isPermanentlyDenied ||
        await Permission.bluetoothConnect.isPermanentlyDenied ||
        await Permission.locationWhenInUse.isPermanentlyDenied) {
      debugPrint('[BleTeacher] BLE permission permanently denied');
      return false;
    }
    debugPrint('[BleTeacher] BLE permission not granted');
    return false;
  }

  Future<bool> startAdvertising(String sessionId, String subject) async {
    if (isAdvertising.value) return true;
    _stateSub?.cancel();
    _stateSub = _peripheral.onPeripheralStateChanged?.listen((state) {
      debugPrint('[BleTeacher] Peripheral state changed: $state');
      _bluetoothStateCtrl.add(state);
      if (state == PeripheralState.poweredOff) {
        isAdvertising.value = false;
      }
    });
    try {
      final data = BleSessionCodec.encode(sessionId, subject);
      await _peripheral.start(
        advertiseData: AdvertiseData(
          manufacturerId: BleConstants.manufacturerId,
          manufacturerData: data,
          includeDeviceName: false,
        ),
        advertiseSettings: AdvertiseSettings(
          advertiseMode: AdvertiseMode.advertiseModeLowLatency,
          connectable: false,
        ),
      );
      isAdvertising.value = true;
      debugPrint('[BleTeacher] Advertising session: $sessionId');
      return true;
    } catch (e) {
      debugPrint('[BleTeacher] startAdvertising error: $e');
      return false;
    }
  }

  Future<void> stopAdvertising() async {
    try {
      await _peripheral.stop();
    } catch (e) {
      debugPrint('[BleTeacher] stop error: $e');
    }
    isAdvertising.value = false;
  }

  Future<void> dispose() async {
    _stateSub?.cancel();
    await _bluetoothStateCtrl.close();
    await stopAdvertising();
  }
}

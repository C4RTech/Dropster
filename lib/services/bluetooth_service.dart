import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'mqtt_hive.dart';

/// Servicio singleton para manejar la conexión global BLE con el ESP32.
/// Permite conectar, desconectar, reconectar automáticamente y recibir notificaciones de datos.
class AppBluetoothService {
  BluetoothDevice? _connectedDevice;
  StreamSubscription<List<int>>? _dataSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionStateSub;
  Function(String)? _debugLogCallback;

  bool _autoReconnect = false; // Indica si debe intentar reconectar automáticamente
  String? _targetMac;          // Dirección MAC del dispositivo objetivo

  AppBluetoothService._internal();
  static final AppBluetoothService _instance = AppBluetoothService._internal();
  factory AppBluetoothService() => _instance;

  /// Permite establecer un callback para debug/log
  void setDebugLogCallback(Function(String) cb) {
    _debugLogCallback = cb;
  }

  /// Llama a esto UNA SOLA VEZ para iniciar la conexión BLE global
  /// autoReconnect permite reconectar automáticamente si se pierde la conexión
  Future<void> connectAndPoll(BluetoothDevice device, {bool autoReconnect = true}) async {
    _autoReconnect = autoReconnect;
    _targetMac = device.remoteId.str.toUpperCase();
    await _connect(device);
  }

  /// Conecta al dispositivo BLE y escucha los cambios de estado de conexión
  Future<void> _connect(BluetoothDevice device) async {
    if (_connectedDevice?.remoteId.str == device.remoteId.str) return;
    try {
      await device.connect(autoConnect: false);
    } catch (_) {}
    _connectedDevice = device;

    _connectionStateSub?.cancel();
    _connectionStateSub = device.connectionState.listen((state) async {
      _debugLogCallback?.call("Estado de conexión BLE: $state");
      if (state == BluetoothConnectionState.connected) {
        await _subscribeToNotifications(device);
      }
      if (state == BluetoothConnectionState.disconnected) {
        _cleanup();
        if (_autoReconnect && _targetMac != null) {
          _debugLogCallback?.call("Intentando reconectar a $_targetMac ...");
          // Espera 1 segundo antes de intentar reconectar
          Future.delayed(const Duration(seconds: 1), () {
            _reconnect();
          });
        }
      }
    });
  }

  /// Se suscribe a la característica notifiable del dispositivo BLE para recibir datos
  Future<void> _subscribeToNotifications(BluetoothDevice device) async {
    final services = await device.discoverServices();
    bool found = false;
    for (final s in services) {
      for (final c in s.characteristics) {
        if (c.properties.notify) {
          await c.setNotifyValue(true);
          _debugLogCallback?.call("Suscrito a notificaciones BLE en ${c.uuid}");
          _dataSubscription?.cancel();
          _dataSubscription = c.onValueReceived.listen((value) {
            _debugLogCallback?.call("Dato BLE recibido: $value");
            MqttHiveService().onBluetoothDataReceived(value, source: "BLE");
          });
          found = true;
          break;
        }
      }
      if (found) break;
    }
    if (!found) {
      throw Exception("No se encontró característica BLE notifiable");
    }
  }

  /// Limpia las subscripciones y el dispositivo conectado
  void _cleanup() {
    _dataSubscription?.cancel();
    _dataSubscription = null;
    _connectedDevice = null;
  }

  /// Intenta reconectar automáticamente al dispositivo objetivo
  Future<void> _reconnect() async {
    try {
      final devices = await FlutterBluePlus.connectedDevices;
      BluetoothDevice? target;
      for (final d in devices) {
        if (d.remoteId.str.toUpperCase() == _targetMac) {
          target = d;
          break;
        }
      }
      if (target == null) {
        // Declarar scanSub ANTES de usarlo en el closure
        StreamSubscription? scanSub;
        scanSub = FlutterBluePlus.scanResults.listen((results) async {
          for (final r in results) {
            if (r.device.remoteId.str.toUpperCase() == _targetMac) {
              await connectAndPoll(r.device, autoReconnect: _autoReconnect);
              await FlutterBluePlus.stopScan();
              await scanSub?.cancel();
              break;
            }
          }
        });
        await FlutterBluePlus.startScan(timeout: const Duration(seconds: 8));
      } else {
        await connectAndPoll(target, autoReconnect: _autoReconnect);
      }
    } catch (e) {
      _debugLogCallback?.call("Error al reconectar: $e");
    }
  }

  /// Desconecta y limpia el estado, detiene reconexión automática
  Future<void> disconnect() async {
    _autoReconnect = false;
    _targetMac = null;
    _dataSubscription?.cancel();
    _connectionStateSub?.cancel();
    if (_connectedDevice != null) {
      try {
        await _connectedDevice?.disconnect();
      } catch (_) {}
      _connectedDevice = null;
    }
    _debugLogCallback?.call("Desconectado de BLE");
  }

  /// Devuelve el dispositivo actualmente conectado (si hay)
  BluetoothDevice? get connectedDevice => _connectedDevice;
}
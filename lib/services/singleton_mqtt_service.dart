import 'dart:async';
import 'package:flutter/material.dart';
import 'mqtt_hive.dart';
import 'mqtt_service.dart';

/// Singleton que orquesta el acceso y sincronización entre el servicio MQTT y la app.
/// Expone un ValueNotifier para que la UI escuche los cambios en tiempo real y
/// coordina la conexión/desconexión MQTT.
/// También permite actualizar el notifier desde BLE, fusionando los datos.
class SingletonMqttService {
  // Instancia única del singleton
  static final SingletonMqttService _instance =
      SingletonMqttService._internal();
  factory SingletonMqttService() => _instance;

  // Servicios: para Hive (almacenamiento) y para MQTT (broker)
  final MqttHiveService mqttService = MqttHiveService();
  final MqttService mqttClientService = MqttService();

  // Notificador global con los datos actuales (para usar en toda la UI)
  final ValueNotifier<Map<String, dynamic>> notifier = ValueNotifier({});
  // Notificador para el estado de conexión MQTT
  final ValueNotifier<bool> connectionNotifier = ValueNotifier(false);
  StreamSubscription<Map<String, dynamic>>? _dataSubscription;
  Timer? _connectionStatusTimer;

  // Inicialización interna: escucha el stream de datos históricos y fusiona con el estado actual.
  SingletonMqttService._internal() {
    _dataSubscription ??= mqttService.dataStream.listen((data) {
      // MERGE: Mantén los valores viejos si no llegan en el nuevo mensaje
      notifier.value = {...notifier.value, ...data, 'source': 'MQTT'};
    });
  }

  /// Indica si hay conexión al broker MQTT
  bool get mqttConnected => mqttClientService.isConnected;
  String get broker => mqttClientService.broker;
  int get port => mqttClientService.port;
  String get topic => mqttClientService.topic;

  /// Conecta al broker usando el servicio MQTT y el servicio Hive para guardar datos
  Future<void> connect() async {
    print('[MQTT DEBUG] Iniciando conexión MQTT desde Singleton');

    // Asegurar que Hive esté inicializado antes de conectar
    print('[MQTT DEBUG] Inicializando Hive...');
    await MqttHiveService.initHive();
    print('[MQTT DEBUG] Hive inicializado correctamente');

    await mqttClientService.connect(mqttService);
    print(
        '[MQTT DEBUG] Conexión MQTT completada, estado: ${mqttClientService.isConnected}');

    // Actualizar estado de conexión
    connectionNotifier.value = mqttClientService.isConnected;

    // Iniciar monitoreo de conexión para reconexión automática
    mqttClientService.startConnectionMonitoring();

    // Iniciar monitoreo del estado de conexión para UI
    _startConnectionStatusMonitoring();
  }

  /// Desconecta del broker MQTT
  Future<void> disconnect() async {
    mqttClientService.stopConnectionMonitoring();
    _stopConnectionStatusMonitoring();
    mqttClientService.disconnect();
    connectionNotifier.value = false;
  }

  /// Inicia el monitoreo del estado de conexión
  void _startConnectionStatusMonitoring() {
    _connectionStatusTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      final currentStatus = mqttClientService.isConnected;
      if (connectionNotifier.value != currentStatus) {
        connectionNotifier.value = currentStatus;
        print('[MQTT DEBUG] Estado de conexión cambió a: $currentStatus');
      }
    });
  }

  /// Detiene el monitoreo del estado de conexión
  void _stopConnectionStatusMonitoring() {
    _connectionStatusTimer?.cancel();
  }

  /// Procesa un payload recibido por MQTT y lo guarda/actualiza en Hive y la UI
  void onMqttPayload(String payload) {
    mqttService.onMqttDataReceived(payload);
  }

  /// Actualización segura desde BLE: fusiona los datos y marca su origen.
  void updateWithBleData(Map<String, dynamic> data) {
    notifier.value = {...notifier.value, ...data, 'source': 'BLE'};
  }
}

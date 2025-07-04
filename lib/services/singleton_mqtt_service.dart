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
  static final SingletonMqttService _instance = SingletonMqttService._internal();
  factory SingletonMqttService() => _instance;

  // Servicios: para Hive (almacenamiento) y para MQTT (broker)
  final MqttHiveService mqttService = MqttHiveService();
  final MqttService mqttClientService = MqttService();

  // Notificador global con los datos actuales (para usar en toda la UI)
  final ValueNotifier<Map<String, dynamic>> notifier = ValueNotifier({});
  StreamSubscription<Map<String, dynamic>>? _dataSubscription;

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
    await mqttClientService.connect(mqttService);
  }

  /// Desconecta del broker MQTT
  Future<void> disconnect() async {
    mqttClientService.disconnect();
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
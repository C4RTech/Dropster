import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
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
  // Notificador para el estado de conexión MQTT de la app
  final ValueNotifier<bool> connectionNotifier = ValueNotifier(false);
  // Notificador para el estado de conexión del ESP32
  final ValueNotifier<bool> esp32ConnectionNotifier = ValueNotifier(false);
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
    debugPrint('[MQTT DEBUG] Iniciando conexión MQTT desde Singleton');

    // Asegurar que Hive esté inicializado antes de conectar
    debugPrint('[MQTT DEBUG] Inicializando Hive...');
    await MqttHiveService.initHive();
    debugPrint('[MQTT DEBUG] Hive inicializado correctamente');

    await mqttClientService.connect(mqttService);
    debugPrint(
        '[MQTT DEBUG] Conexión MQTT completada, estado: ${mqttClientService.isConnected}');

    // Mostrar configuración de conexión
    debugPrint('[MQTT DEBUG] Configuración MQTT:');
    debugPrint('[MQTT DEBUG]   - Broker: ${mqttClientService.broker}');
    debugPrint('[MQTT DEBUG]   - Puerto: ${mqttClientService.port}');
    debugPrint('[MQTT DEBUG]   - Tópico: ${mqttClientService.topic}');

    // Actualizar estado de conexión
    connectionNotifier.value = mqttClientService.isConnected;

    // Iniciar monitoreo de conexión para reconexión automática
    mqttClientService.startConnectionMonitoring();

    // Iniciar monitoreo del estado de conexión para UI
    _startConnectionStatusMonitoring();

    // Agregar listener para debug de mensajes MQTT
    debugPrint('[MQTT DEBUG] Agregando listener para debug de mensajes MQTT');
    notifier.addListener(() {
      final data = notifier.value;
      if (data.containsKey('energia')) {
        debugPrint(
            '[MQTT LISTENER DEBUG] Energía actualizada en notifier: ${data['energia']}kWh');
      }
    });
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
    _connectionStatusTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      final currentStatus = mqttClientService.isConnected;
      if (connectionNotifier.value != currentStatus) {
        connectionNotifier.value = currentStatus;
        // Solo log cuando cambia el estado, no cada 3 segundos
        debugPrint('[MQTT] Estado de conexión cambió a: $currentStatus');
        if (!currentStatus) {
          debugPrint(
              '[MQTT] ⚠️ Conexión perdida detectada, intentando reconectar...');
        }
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

  /// Configura el modo background/foreground para optimizar la conexión
  void setBackgroundMode(bool isBackground) {
    mqttClientService.setBackgroundMode(isBackground);
  }

  /// Método de debug para simular recepción de datos MQTT (para testing)
  void simulateMqttData() {
    debugPrint('[MQTT SIMULATION] Simulando recepción de datos MQTT...');

    final simulatedData = {
      'temperaturaAmbiente': 25.5,
      'humedadRelativa': 65.0,
      'aguaAlmacenada': 450.0,
      'voltaje': 220.0,
      'corriente': 2.5,
      'potencia': 550.0,
      'energia': 1250.75, // Este es el campo que faltaba
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'source': 'MQTT_SIMULATION'
    };

    debugPrint('[MQTT SIMULATION] Datos simulados: $simulatedData');

    // Actualizar el notifier como si viniera de MQTT
    notifier.value = {...notifier.value, ...simulatedData};

    debugPrint('[MQTT SIMULATION] ✅ Datos simulados enviados al notifier');
  }
}

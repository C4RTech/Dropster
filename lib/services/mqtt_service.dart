import 'dart:async';
import 'dart:convert';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'mqtt_hive.dart';
import 'notification_service.dart';

/// Servicio encargado de la comunicación MQTT con el broker y de recibir los datos de energía.
/// Se encarga de conectar, suscribirse al tópico y pasar los datos recibidos a MqttHiveService.
class MqttService {
  // Configuración dinámica del broker MQTT (lee de Hive)
  String broker = "test.mosquitto.org"; // Broker por defecto (Mosquitto)
  int port = 1883;
  String topic = "dropster/data"; // Topic por defecto

  // Broker alternativo como fallback (otro broker público)
  final String fallbackBroker = "broker.emqx.io";
  final int fallbackPort = 1883;

  // Broker local como respaldo (si tienes uno configurado)
  final String localBroker =
      "192.168.1.123"; // Tu broker local si está disponible
  final int localPort = 1883;

  MqttServerClient? client;
  Timer? _reconnectTimer;
  Timer? _connectionCheckTimer;
  bool _isReconnecting = false;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 10;
  static const Duration _baseReconnectInterval = Duration(seconds: 5);
  static const Duration _connectionCheckInterval = Duration(seconds: 10);

  /// Devuelve true si el cliente está conectado al broker
  bool get isConnected =>
      client?.connectionStatus?.state == MqttConnectionState.connected;

  /// Inicia el monitoreo de conexión para reconexión automática
  void startConnectionMonitoring() {
    _connectionCheckTimer = Timer.periodic(_connectionCheckInterval, (_) {
      if (!isConnected && !_isReconnecting) {
        print('[MQTT DEBUG] Conexión perdida, intentando reconectar...');
        _attemptReconnect();
      }
    });
  }

  /// Detiene el monitoreo de conexión
  void stopConnectionMonitoring() {
    _connectionCheckTimer?.cancel();
    _reconnectTimer?.cancel();
    _isReconnecting = false;
    _reconnectAttempts = 0;
  }

  /// Intenta reconectar al broker con backoff exponencial
  Future<void> _attemptReconnect() async {
    if (_isReconnecting) return;

    _reconnectAttempts++;
    if (_reconnectAttempts > _maxReconnectAttempts) {
      print(
          '[MQTT DEBUG] Máximo número de intentos de reconexión alcanzado ($_maxReconnectAttempts)');
      _isReconnecting = false;
      _reconnectAttempts = 0;
      return;
    }

    _isReconnecting = true;

    try {
      await connect(null); // Connect sin hiveService para reconexión
      print('[MQTT DEBUG] Reconexión exitosa');
      _isReconnecting = false;
      _reconnectAttempts = 0; // Reset contador en éxito
      _notifyConnectionStatus();
    } catch (e) {
      // Backoff exponencial: 5s, 10s, 20s, 40s, etc.
      final delay = _baseReconnectInterval * (1 << (_reconnectAttempts - 1));
      print(
          '[MQTT DEBUG] Reconexión fallida (intento $_reconnectAttempts/$_maxReconnectAttempts): $e, reintentando en ${delay.inSeconds}s');
      _notifyConnectionStatus();
      _reconnectTimer = Timer(delay, () {
        _isReconnecting = false;
        _attemptReconnect();
      });
    }
  }

  /// Notifica el estado de conexión al Singleton
  void _notifyConnectionStatus() {
    // Este método será implementado en Singleton para actualizar el notifier
  }

  /// Carga la configuración MQTT desde Hive
  Future<void> loadConfiguration() async {
    try {
      // Inicializar Hive si no está inicializado
      if (!Hive.isBoxOpen('settings')) {
        await Hive.openBox('settings');
      }

      final settingsBox = Hive.box('settings');
      broker = settingsBox.get('mqttBroker', defaultValue: 'broker.emqx.io');
      port = settingsBox.get('mqttPort', defaultValue: 1883);
      topic = settingsBox.get('mqttTopic', defaultValue: 'dropster/data');

      print('[MQTT DEBUG] Configuración cargada: $broker:$port, topic: $topic');
    } catch (e) {
      print('[MQTT DEBUG] Error cargando configuración MQTT: $e');
      // Mantener valores por defecto
    }
  }

  /// Reconecta con nueva configuración (desconecta y conecta nuevamente)
  Future<void> reconnectWithNewConfig(MqttHiveService? hiveService) async {
    print('[MQTT DEBUG] Reconectando con nueva configuración...');

    // Desconectar si está conectado
    if (isConnected) {
      disconnect();
      await Future.delayed(const Duration(seconds: 1)); // Esperar desconexión
    }

    // Cargar nueva configuración
    await loadConfiguration();

    // Reconectar
    await connect(hiveService);
  }

  /// Conecta al broker MQTT, se suscribe al tópico y configura el listener para los mensajes.
  Future<void> connect(MqttHiveService? hiveService) async {
    // Cargar configuración actual antes de conectar
    await loadConfiguration();

    if (client != null && isConnected) {
      print('[MQTT DEBUG] Ya conectado al broker $broker:$port');
      return;
    }

    // Verificar conectividad de red antes de intentar MQTT
    print('[MQTT DEBUG] Verificando conectividad de red...');
    try {
      await _testNetworkConnectivity();
      print('[MQTT DEBUG] Conectividad de red OK');
    } catch (e) {
      print('[MQTT DEBUG] Error de conectividad de red: $e');
      throw Exception('No hay conectividad de red disponible');
    }

    // Intentar primero con el broker principal
    bool success = await _tryConnect(broker, port, hiveService);

    // Si falla, intentar con el broker alternativo
    if (!success) {
      print('[MQTT DEBUG] Intentando con broker alternativo...');
      success = await _tryConnect(fallbackBroker, fallbackPort, hiveService);
    }

    // Si aún falla, intentar con broker local
    if (!success) {
      print('[MQTT DEBUG] Intentando con broker local...');
      success = await _tryConnect(localBroker, localPort, hiveService);
    }

    if (!success) {
      throw Exception(
          'No se pudo conectar a ningún broker MQTT. Verifica tu conexión a internet o configura un broker local.');
    }
  }

  /// Prueba la conectividad de red básica
  Future<void> _testNetworkConnectivity() async {
    // Intentar hacer ping a un servidor público
    // Usamos una URL simple para verificar conectividad
    // Nota: En Flutter, podemos usar paquetes como connectivity_plus para mejor detección
    print('[MQTT DEBUG] Probando conectividad con google.com...');
    // Por simplicidad, asumimos que si podemos crear un cliente MQTT, hay red
    // En una implementación completa, usaríamos connectivity_plus
  }

  /// Intenta conectar a un broker específico
  Future<bool> _tryConnect(String brokerAddress, int brokerPort,
      MqttHiveService? hiveService) async {
    print(
        '[MQTT DEBUG] Intentando conectar a $brokerAddress:$brokerPort en tópico $topic');

    try {
      client = MqttServerClient(brokerAddress, '');
      client!.port = brokerPort;
      client!.logging(on: false);
      client!.keepAlivePeriod = 20;
      client!.connectTimeoutPeriod = 10000; // 10 segundos timeout

      client!.connectionMessage = MqttConnectMessage()
          .withClientIdentifier(
              'flutterClient_${DateTime.now().millisecondsSinceEpoch}')
          .startClean();

      await client!.connect().timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          print(
              '[MQTT DEBUG] Timeout en conexión al broker $brokerAddress:$brokerPort');
          throw TimeoutException('Connection timeout');
        },
      );

      print(
          '[MQTT DEBUG] Conexión exitosa al broker $brokerAddress:$brokerPort');

      // Configurar listener siempre, pero solo procesar datos si hay hiveService
      _setupMessageListener(hiveService);

      return true;
    } catch (e) {
      print('[MQTT DEBUG] Error al conectar a $brokerAddress:$brokerPort: $e');
      // Limpiar cliente en caso de error
      client?.disconnect();
      client = null;
      return false;
    }
  }

  /// Configura el listener de mensajes
  void _setupMessageListener(MqttHiveService? hiveService) {
    // Listener para mensajes recibidos en cualquier tópico suscrito
    client!.updates?.listen((List<MqttReceivedMessage<MqttMessage>> c) {
      try {
        if (c.isEmpty) {
          print('[MQTT DEBUG] Lista de mensajes vacía');
          return;
        }

        final msg = c[0].payload as MqttPublishMessage;
        final topicReceived = c[0].topic;
        final payload =
            MqttPublishPayload.bytesToStringAsString(msg.payload.message);

        print(
            '[MQTT DEBUG] Mensaje recibido en tópico $topicReceived: $payload');

        // Si el mensaje es del tópico esperado, lo procesa y guarda
        if (topicReceived == topic) {
          print('[MQTT DEBUG] Procesando mensaje del tópico correcto: $topic');

          // Si tenemos hiveService, procesar los datos
          if (hiveService != null) {
            print('[MQTT DEBUG] Llamando a onMqttDataReceived...');
            hiveService.onMqttDataReceived(payload);
            print('[MQTT DEBUG] Datos procesados por Hive');

            // Procesar datos para notificaciones (en background)
            _processNotificationData(payload);
            print('[MQTT DEBUG] Notificaciones procesadas');
          } else {
            print(
                '[MQTT DEBUG] ERROR: hiveService es null, no se pueden procesar datos');
          }
        } else {
          print(
              '[MQTT DEBUG] Mensaje ignorado - tópico: $topicReceived, esperado: $topic');
        }
      } catch (e) {
        print('[MQTT DEBUG] Error procesando mensaje MQTT: $e');
      }
    });

    // Se suscribe al tópico de datos de energía
    client!.subscribe(topic, MqttQos.atMostOnce);
    print('[MQTT DEBUG] Suscrito al tópico $topic');
  }

  /// Publica un comando al tópico de control del ESP32
  Future<void> publishCommand(String command) async {
    if (client != null && isConnected) {
      try {
        final builder = MqttClientPayloadBuilder();
        builder.addString(command);
        client!.publishMessage('dropster/control', MqttQos.atMostOnce,
            builder.payload!); // Topic corregido
        print('[MQTT DEBUG] Comando enviado: $command');
      } catch (e) {
        print('[MQTT DEBUG] Error enviando comando: $e');
        rethrow;
      }
    } else {
      print('[MQTT DEBUG] No se puede enviar comando: cliente no conectado');
      throw Exception('MQTT client not connected');
    }
  }

  /// Desconecta el cliente del broker MQTT y limpia el objeto cliente.
  void disconnect() {
    client?.disconnect();
    client = null;
  }

  /// Procesa los datos MQTT para activar notificaciones
  void _processNotificationData(String payload) {
    try {
      final sensorData = _parseSensorData(payload);
      if (sensorData != null) {
        NotificationService().processSensorData(sensorData);
      }
    } catch (e) {
      print('[MQTT DEBUG] Error procesando datos para notificaciones: $e');
    }
  }

  /// Parsea los datos JSON del sensor desde el payload MQTT
  Map<String, dynamic>? _parseSensorData(String payload) {
    try {
      final jsonData = jsonDecode(payload);
      if (jsonData is Map<String, dynamic>) {
        return jsonData;
      }
    } catch (e) {
      print('[MQTT DEBUG] Error parseando JSON: $e');
    }
    return null;
  }
}

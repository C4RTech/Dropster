import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'mqtt_hive.dart';
import 'notification_service.dart';
import 'singleton_mqtt_service.dart';

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
  Timer? _pingTimer;
  bool _isReconnecting = false;
  bool _isInBackground = false;
  int _reconnectAttempts = 0;
  DateTime? _lastMessageTime;
  DateTime? _lastPingTime;
  DateTime? _lastSuccessfulConnection;
  static const int _maxReconnectAttempts = 20;
  static const Duration _baseReconnectInterval = Duration(seconds: 2);
  static const Duration _maxReconnectInterval = Duration(minutes: 5);
  static const Duration _connectionCheckInterval = Duration(seconds: 10);
  static const Duration _pingInterval = Duration(seconds: 30);
  static const Duration _backgroundPingInterval = Duration(seconds: 60);
  static const Duration _connectionTimeout = Duration(seconds: 15);

  // Stream para publicar cambios de modo y suscribirse desde la UI
  final StreamController<String> _modeController =
      StreamController<String>.broadcast();
  Stream<String> get modeStream => _modeController.stream;

  /// Devuelve true si el cliente está conectado al broker
  bool get isConnected =>
      client?.connectionStatus?.state == MqttConnectionState.connected;

  /// Método público para verificar conexión (útil para background service)
  Future<bool> checkConnection() async {
    return isConnected;
  }

  /// Inicia el monitoreo de conexión para reconexión automática
  void startConnectionMonitoring() {
    _connectionCheckTimer = Timer.periodic(_connectionCheckInterval, (_) {
      print(
          '[MQTT STATUS] Estado de conexión: ${isConnected ? 'CONECTADO' : 'DESCONECTADO'}');
      print('[MQTT STATUS] Broker: $broker:$port');
      print('[MQTT STATUS] Topic: $topic');
      print('[MQTT STATUS] Último mensaje: ${_lastMessageTime ?? 'Nunca'}');

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
    _stopActivityMonitoring();
    _isReconnecting = false;
    _reconnectAttempts = 0;
  }

  /// Inicia el monitoreo de actividad para mantener la conexión viva
  void _startActivityMonitoring() {
    _pingTimer?.cancel();
    final activityInterval =
        _isInBackground ? _backgroundPingInterval : _pingInterval;
    _pingTimer = Timer.periodic(activityInterval, (_) {
      if (isConnected && client != null) {
        final now = DateTime.now();
        _lastPingTime = now;

        // Verificar si ha pasado mucho tiempo sin mensajes
        final timeSinceLastMessage = _lastMessageTime != null
            ? now.difference(_lastMessageTime!).inSeconds
            : 0;

        // Verificar tiempo desde última conexión exitosa
        final timeSinceLastConnection = _lastSuccessfulConnection != null
            ? now.difference(_lastSuccessfulConnection!).inMinutes
            : 0;

        if (timeSinceLastMessage > 120) {
          // 2 minutos sin mensajes
          print(
              '[MQTT DEBUG] Sin actividad por ${timeSinceLastMessage}s, verificando conexión...');
          // Forzar verificación de conexión
          _checkConnectionHealth();
        }

        // Log de estado de conexión cada 5 minutos
        if (timeSinceLastConnection > 0 && timeSinceLastConnection % 5 == 0) {
          print(
              '[MQTT DEBUG] 📊 Estado conexión: ${timeSinceLastConnection}min activa, último mensaje: ${timeSinceLastMessage}s');
        }
      }
    });
  }

  /// Detiene el monitoreo de actividad
  void _stopActivityMonitoring() {
    _pingTimer?.cancel();
    _pingTimer = null;
  }

  /// Verifica la salud de la conexión
  void _checkConnectionHealth() {
    if (!isConnected) {
      print(
          '[MQTT DEBUG] Conexión detectada como perdida, intentando reconectar...');
      _attemptReconnect();
    } else {
      final now = DateTime.now();
      final timeSinceLastPing =
          _lastPingTime != null ? now.difference(_lastPingTime!).inSeconds : 0;
      print(
          '[MQTT DEBUG] Conexión saludable (último ping: ${timeSinceLastPing}s)');
    }
  }

  /// Configura el modo background/foreground
  void setBackgroundMode(bool isBackground) {
    if (_isInBackground != isBackground) {
      _isInBackground = isBackground;
      if (isBackground) {
        print('[MQTT DEBUG] App en background - ajustando configuración');
        _stopActivityMonitoring();
        _startActivityMonitoring(); // Reinicia con intervalo de background
      } else {
        print('[MQTT DEBUG] App en foreground - optimizando configuración');
        _stopActivityMonitoring();
        _startActivityMonitoring(); // Reinicia con intervalo normal
      }
    }
  }

  /// Intenta reconectar al broker con backoff exponencial mejorado
  Future<void> _attemptReconnect() async {
    if (_isReconnecting) return;

    _reconnectAttempts++;
    if (_reconnectAttempts > _maxReconnectAttempts) {
      print(
          '[MQTT DEBUG] Máximo número de intentos de reconexión alcanzado ($_maxReconnectAttempts)');
      _isReconnecting = false;
      _reconnectAttempts = 0;
      _notifyConnectionStatus();
      return;
    }

    _isReconnecting = true;
    print(
        '[MQTT DEBUG] 🔄 Intentando reconexión (intento $_reconnectAttempts/$_maxReconnectAttempts)');

    try {
      // Intentar conectar con timeout
      await connect(null).timeout(_connectionTimeout);
      print('[MQTT DEBUG] ✅ Reconexión exitosa');
      _isReconnecting = false;
      _reconnectAttempts = 0; // Reset contador en éxito
      _lastSuccessfulConnection = DateTime.now();
      _notifyConnectionStatus();
    } catch (e) {
      // Backoff exponencial con jitter para evitar thundering herd
      final baseDelay =
          _baseReconnectInterval * (1 << (_reconnectAttempts - 1));
      final maxDelay = _maxReconnectInterval;
      final delay = Duration(
          milliseconds: (baseDelay.inMilliseconds * 0.5 +
                  (baseDelay.inMilliseconds *
                      0.5 *
                      (DateTime.now().millisecondsSinceEpoch % 1000) /
                      1000))
              .clamp(0, maxDelay.inMilliseconds)
              .round());

      print(
          '[MQTT DEBUG] ❌ Reconexión fallida (intento $_reconnectAttempts/$_maxReconnectAttempts): $e');
      print('[MQTT DEBUG] ⏰ Reintentando en ${delay.inSeconds}s (con jitter)');

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
    // Intentar resolver un host público para validar conectividad de red.
    // Evitar paquetes extra; usar lookup con timeout.
    print('[MQTT DEBUG] Probando conectividad (lookup google.com)...');
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 5));
      if (result.isEmpty || result[0].rawAddress.isEmpty) {
        throw Exception('Lookup regresó vacío');
      }
      print('[MQTT DEBUG] Conectividad de red OK: ${result[0].address}');
    } on TimeoutException catch (e) {
      print('[MQTT DEBUG] Timeout en verificación de red: $e');
      throw Exception('Timeout verificando conectividad');
    } catch (e) {
      print('[MQTT DEBUG] Error de conectividad de red: $e');
      throw Exception('No hay conectividad de red disponible');
    }
  }

  /// Intenta conectar a un broker específico
  Future<bool> _tryConnect(String brokerAddress, int brokerPort,
      MqttHiveService? hiveService) async {
    print(
        '[MQTT DEBUG] 🔗 Intentando conectar a $brokerAddress:$brokerPort en tópico $topic');

    try {
      // Limpiar cliente anterior si existe
      if (client != null) {
        client!.disconnect();
        client = null;
      }

      client = MqttServerClient(brokerAddress, '');
      client!.port = brokerPort;
      client!.logging(on: false);

      // Configuración optimizada para estabilidad
      client!.keepAlivePeriod = 60; // 60 segundos
      client!.connectTimeoutPeriod = 10000; // 10 segundos
      client!.autoReconnect =
          false; // Deshabilitar auto-reconnect del cliente (manejamos nosotros)
      client!.resubscribeOnAutoReconnect = true;

      // Configurar mensaje de conexión con identificador único
      final clientId = 'dropster_${DateTime.now().millisecondsSinceEpoch}';
      client!.connectionMessage = MqttConnectMessage()
          .withClientIdentifier(clientId)
          .withWillTopic('dropster/status')
          .withWillMessage('OFFLINE')
          .withWillQos(MqttQos.atLeastOnce)
          .startClean();

      print(
          '[MQTT DEBUG] ⏱️ Iniciando conexión con timeout de ${_connectionTimeout.inSeconds}s...');

      await client!.connect().timeout(
        _connectionTimeout,
        onTimeout: () {
          print(
              '[MQTT DEBUG] ⏰ Timeout en conexión al broker $brokerAddress:$brokerPort');
          throw TimeoutException(
              'Connection timeout after ${_connectionTimeout.inSeconds}s');
        },
      );

      // Verificar que la conexión sea exitosa
      if (client!.connectionStatus?.state != MqttConnectionState.connected) {
        throw Exception(
            'Connection failed: ${client!.connectionStatus?.state}');
      }

      print(
          '[MQTT DEBUG] ✅ Conexión exitosa al broker $brokerAddress:$brokerPort');
      print('[MQTT DEBUG] 📡 Client ID: $clientId');

      // Configurar listener siempre, pero solo procesar datos si hay hiveService
      _setupMessageListener(hiveService);

      // Iniciar monitoreo de actividad para mantener conexión viva
      _startActivityMonitoring();

      // Resetear contador de intentos en conexión exitosa
      _reconnectAttempts = 0;
      _lastSuccessfulConnection = DateTime.now();

      return true;
    } catch (e) {
      print(
          '[MQTT DEBUG] ❌ Error al conectar a $brokerAddress:$brokerPort: $e');
      // Limpiar cliente en caso de error
      try {
        client?.disconnect();
      } catch (_) {
        // Ignorar errores de desconexión
      }
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

        // Actualizar timestamp del último mensaje
        _lastMessageTime = DateTime.now();

        print(
            '[MQTT DEBUG] Mensaje recibido en tópico $topicReceived: $payload');

        // Si el mensaje es del tópico esperado (datos)
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
        }
        // Si el mensaje viene por el tópico de estado, procesar modo/estado
        else if (topicReceived == 'dropster/status') {
          print('[MQTT DEBUG] Mensaje de STATUS recibido: $payload');
          try {
            final Map<String, dynamic> json = jsonDecode(payload);
            if (json.containsKey('mode')) {
              final String mode = json['mode'].toString();
              print('[MQTT DEBUG] Modo recibido: $mode');
              _modeController.add(mode);
              // Actualizar notifier con el modo
              SingletonMqttService().notifier.value = {
                ...SingletonMqttService().notifier.value,
                'mode': mode,
              };
            }
            // Procesar estados individuales de relés si están en JSON
            if (json.containsKey('compressor')) {
              SingletonMqttService().notifier.value = {
                ...SingletonMqttService().notifier.value,
                'cs': json['compressor'],
              };
            }
            if (json.containsKey('ventilador')) {
              SingletonMqttService().notifier.value = {
                ...SingletonMqttService().notifier.value,
                'vs': json['ventilador'],
              };
            }
            if (json.containsKey('pump')) {
              SingletonMqttService().notifier.value = {
                ...SingletonMqttService().notifier.value,
                'ps': json['pump'],
              };
            }
          } catch (e) {
            // Si no es JSON, aceptar payloads simples como "MODE_AUTO" o "MODE_MANUAL"
            if (payload.contains('MODE_AUTO')) {
              _modeController.add('AUTO');
              SingletonMqttService().notifier.value = {
                ...SingletonMqttService().notifier.value,
                'mode': 'AUTO',
              };
            } else if (payload.contains('MODE_MANUAL')) {
              _modeController.add('MANUAL');
              SingletonMqttService().notifier.value = {
                ...SingletonMqttService().notifier.value,
                'mode': 'MANUAL',
              };
            }
            // Procesar estados individuales de relés
            else if (payload.contains('COMP_ON')) {
              SingletonMqttService().notifier.value = {
                ...SingletonMqttService().notifier.value,
                'cs': 1,
              };
            } else if (payload.contains('COMP_OFF')) {
              SingletonMqttService().notifier.value = {
                ...SingletonMqttService().notifier.value,
                'cs': 0,
              };
            } else if (payload.contains('VENT_ON')) {
              SingletonMqttService().notifier.value = {
                ...SingletonMqttService().notifier.value,
                'vs': 1,
              };
            } else if (payload.contains('VENT_OFF')) {
              SingletonMqttService().notifier.value = {
                ...SingletonMqttService().notifier.value,
                'vs': 0,
              };
            } else if (payload.contains('PUMP_ON')) {
              SingletonMqttService().notifier.value = {
                ...SingletonMqttService().notifier.value,
                'ps': 1,
              };
            } else if (payload.contains('PUMP_OFF')) {
              SingletonMqttService().notifier.value = {
                ...SingletonMqttService().notifier.value,
                'ps': 0,
              };
            }
          }
        }
        // Si el mensaje viene por el tópico de alertas, procesar alertas
        else if (topicReceived.contains('/alerts')) {
          print('[MQTT ALERT] Mensaje de ALERTA recibido: $payload');
          _processAlertData(payload);
        } else {
          print(
              '[MQTT DEBUG] Mensaje ignorado - tópico: $topicReceived, esperado: $topic, dropster/status o */alerts');
        }
      } catch (e) {
        print('[MQTT DEBUG] Error procesando mensaje MQTT: $e');
      }
    });

    // Se suscribe al tópico de datos de energía con QoS 1 (atLeastOnce) para mayor fiabilidad
    client!.subscribe(topic, MqttQos.atLeastOnce);
    print('[MQTT DEBUG] Suscrito al tópico $topic (QoS 1)');

    // También suscribirse al tópico de estado para recibir modo y otros estados
    client!.subscribe('dropster/status', MqttQos.atLeastOnce);
    print('[MQTT DEBUG] Suscrito al tópico dropster/status (QoS 1)');

    // Suscribirse al tópico de alertas para recibir alertas del ESP32
    client!.subscribe('dropster/alerts', MqttQos.atLeastOnce);
    print('[MQTT DEBUG] Suscrito al tópico dropster/alerts (QoS 1)');
  }

  /// Publica un comando al tópico de control del ESP32
  Future<void> publishCommand(String command) async {
    if (client != null && isConnected) {
      try {
        final builder = MqttClientPayloadBuilder();
        builder.addString(command);
        client!.publishMessage('dropster/control', MqttQos.atLeastOnce,
            builder.payload!); // Topic corregido, usar QoS 1 para fiabilidad
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

  /// Publicar cambio de modo (AUTO/MANUAL) por MQTT
  Future<void> publishMode(String mode) async {
    // mode = "AUTO" o "MANUAL"
    final cmd = (mode.toUpperCase() == 'AUTO') ? 'MODE AUTO' : 'MODE MANUAL';
    await publishCommand(cmd);
    print('[MQTT DEBUG] publishMode: $cmd');
  }

  /// Enviar configuración MQTT al ESP32
  Future<void> sendMqttConfigToESP32(
      String newBroker, int newPort, String newTopic) async {
    try {
      // Crear comando JSON con la nueva configuración (sin campo "command")
      final configJson = jsonEncode({
        'broker': newBroker,
        'port': newPort,
        'topic': newTopic,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      // Enviar como "UPDATE_MQTT_CONFIG" + JSON
      final command = 'UPDATE_MQTT_CONFIG$configJson';
      await publishCommand(command);
      print('[MQTT DEBUG] Configuración MQTT enviada al ESP32: $command');
    } catch (e) {
      print('[MQTT DEBUG] Error enviando configuración MQTT al ESP32: $e');
      rethrow;
    }
  }

  /// Enviar configuración completa (MQTT + alertas + calibración + control) al ESP32
  Future<void> sendFullConfigToESP32({
    required String broker,
    required int port,
    required String topic,
    required double tankFullThreshold,
    required double voltageLowThreshold,
    required double humidityLowThreshold,
    required bool tankFullEnabled,
    required bool voltageLowEnabled,
    required bool humidityLowEnabled,
    required double tankCapacity,
    required bool isCalibrated,
    required List<Map<String, double>> calibrationPoints,
    required double ultrasonicOffset,
    required double controlDeadband,
    required int controlMinOff,
    required int controlMaxOn,
    required int controlSampling,
    required double controlAlpha,
  }) async {
    try {
      // Crear comando JSON con toda la configuración
      final fullConfigJson = jsonEncode({
        'mqtt': {
          'broker': broker,
          'port': port,
          'topic': topic,
        },
        'alerts': {
          'tankFullThreshold': tankFullThreshold,
          'voltageLowThreshold': voltageLowThreshold,
          'humidityLowThreshold': humidityLowThreshold,
          'tankFullEnabled': tankFullEnabled,
          'voltageLowEnabled': voltageLowEnabled,
          'humidityLowEnabled': humidityLowEnabled,
        },
        'tank': {
          'capacity': tankCapacity,
          'isCalibrated': isCalibrated,
          'calibrationPoints': calibrationPoints,
          'ultrasonicOffset': ultrasonicOffset,
        },
        'control': {
          'deadband': controlDeadband,
          'minOff': controlMinOff,
          'maxOn': controlMaxOn,
          'sampling': controlSampling,
          'alpha': controlAlpha,
        },
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      // Enviar como "UPDATE_FULL_CONFIG" + JSON
      final command = 'UPDATE_FULL_CONFIG$fullConfigJson';
      await publishCommand(command);
      print('[MQTT DEBUG] Configuración completa enviada al ESP32: $command');
    } catch (e) {
      print('[MQTT DEBUG] Error enviando configuración completa al ESP32: $e');
      rethrow;
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

  /// Procesa mensajes de alertas del ESP32
  void _processAlertData(String payload) {
    try {
      NotificationService().processAlertData(payload);
    } catch (e) {
      print('[MQTT DEBUG] Error procesando datos de alerta: $e');
    }
  }

  /// Obtiene estadísticas de conexión para debugging
  Map<String, dynamic> getConnectionStats() {
    return {
      'isConnected': isConnected,
      'isReconnecting': _isReconnecting,
      'reconnectAttempts': _reconnectAttempts,
      'isInBackground': _isInBackground,
      'lastMessageTime': _lastMessageTime?.toIso8601String(),
      'timeSinceLastMessage': _lastMessageTime != null
          ? DateTime.now().difference(_lastMessageTime!).inSeconds
          : null,
      'broker': broker,
      'port': port,
      'topic': topic,
    };
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

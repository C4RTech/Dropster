import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'mqtt_hive.dart';
import 'notification_service.dart';
import 'singleton_mqtt_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Servicio encargado de la comunicación MQTT con el broker y de recibir los datos de energía.
/// Se encarga de conectar, suscribirse al tópico y pasar los datos recibidos a MqttHiveService.
class MqttService {
  // Configuración dinámica del broker MQTT (lee de Hive)
  String broker = "test.mosquitto.org"; // Broker por defecto (Mosquitto)
  int port = 1883;
  String topic = "dropster/data"; // Topic por defecto
  // Opciones de seguridad y autenticación
  bool useTls = false;
  String mqttUser = '';
  String mqttPass = '';

  // Solo usar test.mosquitto.org - sin brokers alternativos

  // Secure storage for sensitive credentials
  final FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  MqttServerClient? client;
  Timer? _reconnectTimer;
  Timer? _connectionCheckTimer;
  Timer? _pingTimer;
  Timer? _networkDiagnosticTimer;
  bool _isReconnecting = false;
  bool _isInBackground = false;
  int _reconnectAttempts = 0;
  DateTime? _lastMessageTime;
  DateTime? _lastPingTime;
  DateTime? _lastSuccessfulConnection;
  DateTime? _lastNetworkCheck;
  static const int _maxReconnectAttempts = 20;
  static const Duration _baseReconnectInterval = Duration(seconds: 2);
  static const Duration _maxReconnectInterval = Duration(minutes: 5);
  static const Duration _connectionCheckInterval = Duration(seconds: 5);
  static const Duration _pingInterval = Duration(seconds: 30);
  static const Duration _backgroundPingInterval = Duration(seconds: 60);
  static const Duration _connectionTimeout = Duration(seconds: 15);
  static const Duration _networkDiagnosticInterval = Duration(minutes: 5);

  // Stream para publicar cambios de modo y suscribirse desde la UI
  final StreamController<String> _modeController =
      StreamController<String>.broadcast();
  Stream<String> get modeStream => _modeController.stream;

  // Stream para notificar errores de bomba a la UI
  final StreamController<Map<String, dynamic>> _pumpErrorController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get pumpErrorStream =>
      _pumpErrorController.stream;

  /// Función helper para logs condicionales (solo en debug mode)
  void _log(String message) {
    if (kDebugMode) {
      debugPrint('[MQTT] $message');
    }
  }

  /// Devuelve true si el cliente está conectado al broker
  bool get isConnected =>
      client?.connectionStatus?.state == MqttConnectionState.connected;

  /// Método público para verificar conexión (útil para background service)
  Future<bool> checkConnection() async {
    return isConnected;
  }

  /// Método público para ejecutar diagnóstico de red manualmente
  Future<Map<String, dynamic>> performNetworkDiagnostic() async {
    debugPrint('[MQTT NETWORK] 🔍 Ejecutando diagnóstico de red manual...');
    final results = <String, dynamic>{};

    try {
      // Verificar conectividad básica
      await _testNetworkConnectivity();
      results['network_connectivity'] = 'OK';

      // Verificar conectividad MQTT
      await _testMqttConnectivity();
      results['mqtt_connectivity'] = 'OK';

      // Obtener estadísticas de conexión
      results['connection_stats'] = getConnectionStats();

      debugPrint('[MQTT NETWORK] ✅ Diagnóstico completado exitosamente');
      results['overall_status'] = 'SUCCESS';
    } catch (e) {
      debugPrint('[MQTT NETWORK] ❌ Diagnóstico fallido: $e');
      results['overall_status'] = 'FAILED';
      results['error'] = e.toString();
    }

    return results;
  }

  /// Inicia el monitoreo de conexión para reconexión automática
  void startConnectionMonitoring() {
    _connectionCheckTimer = Timer.periodic(_connectionCheckInterval, (_) {
      final now = DateTime.now();
      final timeSinceLastMessage = _lastMessageTime != null
          ? now.difference(_lastMessageTime!).inSeconds
          : null;

      _log(
          'Estado: ${isConnected ? 'CONECTADO' : 'DESCONECTADO'} | Broker: $broker:$port | Topic: $topic');
      _log(
          'Último mensaje: ${_lastMessageTime ?? 'Nunca'} | Segundos sin mensaje: $timeSinceLastMessage');

      if (!isConnected && !_isReconnecting) {
        _log(
            '⚠️ Conexión perdida detectada, iniciando reconexión automática...');
        _log(
            '📊 Estadísticas: Intentos=${_reconnectAttempts}, Última conexión=${_lastSuccessfulConnection ?? 'Nunca'}');
        _attemptReconnect();
      } else if (isConnected &&
          timeSinceLastMessage != null &&
          timeSinceLastMessage > 300) {
        debugPrint(
            '[MQTT HEALTH] ⚠️ Conexión activa pero sin mensajes por ${timeSinceLastMessage}s - verificando salud...');
        _checkConnectionHealth();
      }
    });

    // Iniciar diagnóstico de red periódico
    _startNetworkDiagnosticMonitoring();
  }

  /// Detiene el monitoreo de conexión
  void stopConnectionMonitoring() {
    _connectionCheckTimer?.cancel();
    _reconnectTimer?.cancel();
    _networkDiagnosticTimer?.cancel();
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
          debugPrint(
              '[MQTT DEBUG] Sin actividad por ${timeSinceLastMessage}s, verificando conexión...');
          // Forzar verificación de conexión
          _checkConnectionHealth();
        }

        // Log de estado de conexión cada 5 minutos
        if (timeSinceLastConnection > 0 && timeSinceLastConnection % 5 == 0) {
          debugPrint(
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

  /// Inicia el monitoreo de diagnóstico de red
  void _startNetworkDiagnosticMonitoring() {
    _networkDiagnosticTimer?.cancel();
    _networkDiagnosticTimer = Timer.periodic(_networkDiagnosticInterval, (_) {
      final now = DateTime.now();
      final timeSinceLastCheck = _lastNetworkCheck != null
          ? now.difference(_lastNetworkCheck!).inMinutes
          : null;

      // Solo ejecutar diagnóstico si han pasado suficientes minutos o si hay problemas de conexión
      if ((timeSinceLastCheck == null || timeSinceLastCheck >= 5) ||
          (!isConnected && _reconnectAttempts > 3)) {
        debugPrint(
            '[MQTT NETWORK] 🔍 Iniciando diagnóstico de red automático...');
        _performNetworkDiagnostic();
        _lastNetworkCheck = now;
      }
    });
  }

  /// Realiza diagnóstico completo de red
  Future<void> _performNetworkDiagnostic() async {
    try {
      debugPrint('[MQTT NETWORK] 🌐 Verificando conectividad básica...');

      // 1. Verificar conectividad básica
      await _testNetworkConnectivity();

      // 2. Verificar conectividad MQTT específica
      await _testMqttConnectivity();

      // 3. Verificar estado de conexión actual
      final stats = getConnectionStats();
      debugPrint(
          '[MQTT NETWORK] 📊 Estado actual: ${stats['isConnected'] ? 'CONECTADO' : 'DESCONECTADO'}');
      debugPrint(
          '[MQTT NETWORK] 📊 Intentos de reconexión: ${stats['reconnectAttempts']}');

      debugPrint('[MQTT NETWORK] ✅ Diagnóstico de red completado');
    } catch (e) {
      debugPrint('[MQTT NETWORK] ❌ Error en diagnóstico de red: $e');
      debugPrint('[MQTT NETWORK] 💡 Posibles causas:');
      debugPrint('[MQTT NETWORK]    • Problemas de conectividad a internet');
      debugPrint('[MQTT NETWORK]    • Broker MQTT inaccesible: $broker:$port');
      debugPrint(
          '[MQTT NETWORK]    • Firewall/antivirus bloqueando conexiones');
      debugPrint('[MQTT NETWORK]    • Problemas de DNS');
    }
  }

  /// Prueba conectividad específica MQTT
  Future<void> _testMqttConnectivity() async {
    try {
      debugPrint(
          '[MQTT NETWORK] 🔌 Probando conectividad MQTT al broker $broker:$port...');

      // Intentar una conexión TCP básica al puerto MQTT
      final socket = await Socket.connect(broker, port,
          timeout: const Duration(seconds: 5));
      socket.destroy();

      debugPrint('[MQTT NETWORK] ✅ Broker MQTT reachable: $broker:$port');
    } catch (e) {
      debugPrint(
          '[MQTT NETWORK] ❌ Broker MQTT NO reachable: $broker:$port - Error: $e');
      throw Exception('Broker MQTT no accesible');
    }
  }

  /// Verifica la salud de la conexión
  void _checkConnectionHealth() {
    if (!isConnected) {
      debugPrint(
          '[MQTT DEBUG] Conexión detectada como perdida, intentando reconectar...');
      _attemptReconnect();
    } else {
      final now = DateTime.now();
      final timeSinceLastPing =
          _lastPingTime != null ? now.difference(_lastPingTime!).inSeconds : 0;
      debugPrint(
          '[MQTT DEBUG] Conexión saludable (último ping: ${timeSinceLastPing}s)');
    }
  }

  /// Configura el modo background/foreground
  void setBackgroundMode(bool isBackground) {
    if (_isInBackground != isBackground) {
      _isInBackground = isBackground;
      if (isBackground) {
        debugPrint('[MQTT DEBUG] App en background - ajustando configuración');
        _stopActivityMonitoring();
        _startActivityMonitoring(); // Reinicia con intervalo de background
      } else {
        debugPrint(
            '[MQTT DEBUG] App en foreground - optimizando configuración');
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
      debugPrint(
          '[MQTT DEBUG] Máximo número de intentos de reconexión alcanzado ($_maxReconnectAttempts)');
      _isReconnecting = false;
      _reconnectAttempts = 0;
      _notifyConnectionStatus();
      return;
    }

    _isReconnecting = true;
    debugPrint(
        '[MQTT RECONNECT] 🔄 Intentando reconexión (intento $_reconnectAttempts/$_maxReconnectAttempts)');
    debugPrint('[MQTT RECONNECT] 📍 Broker: $broker:$port, Topic: $topic');

    try {
      // Intentar conectar con timeout
      await connect(null).timeout(_connectionTimeout);
      debugPrint(
          '[MQTT RECONNECT] ✅ Reconexión exitosa - Conexión establecida');
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

      debugPrint(
          '[MQTT RECONNECT] ❌ Reconexión fallida (intento $_reconnectAttempts/$_maxReconnectAttempts)');
      debugPrint('[MQTT RECONNECT] 📋 Error: $e');
      debugPrint(
          '[MQTT RECONNECT] ⏰ Próximo intento en ${delay.inSeconds}s (backoff exponencial con jitter)');

      // Agregar información adicional para debugging
      if (_reconnectAttempts >= 5) {
        debugPrint(
            '[MQTT RECONNECT] ⚠️ Múltiples fallos consecutivos - verificar:');
        debugPrint('[MQTT RECONNECT]   • Conectividad de red');
        debugPrint('[MQTT RECONNECT]   • Broker MQTT accesible: $broker:$port');
        debugPrint('[MQTT RECONNECT]   • Credenciales válidas');
        debugPrint(
            '[MQTT RECONNECT]   • Firewall/antivirus bloqueando puerto $port');
      }

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
      broker =
          settingsBox.get('mqttBroker', defaultValue: 'test.mosquitto.org');
      port = settingsBox.get('mqttPort', defaultValue: 1883);
      topic = settingsBox.get('mqttTopic', defaultValue: 'dropster/data');
      useTls = settingsBox.get('mqttUseTls', defaultValue: false);
      // Credentials must be stored in secure storage for safety
      mqttUser = await _secureStorage.read(key: 'mqttUser') ?? '';
      mqttPass = await _secureStorage.read(key: 'mqttPass') ?? '';

      debugPrint(
          '[MQTT DEBUG] Configuración cargada: $broker:$port, topic: $topic');
    } catch (e) {
      debugPrint('[MQTT DEBUG] Error cargando configuración MQTT: $e');
      // Mantener valores por defecto
    }
  }

  /// Guarda las credenciales MQTT en almacenamiento seguro
  Future<void> saveCredentials(
      {required String user, required String pass}) async {
    try {
      await _secureStorage.write(key: 'mqttUser', value: user);
      await _secureStorage.write(key: 'mqttPass', value: pass);
      mqttUser = user;
      mqttPass = pass;
      debugPrint(
          '[MQTT DEBUG] Credenciales guardadas en almacenamiento seguro');
    } catch (e) {
      debugPrint('[MQTT DEBUG] Error guardando credenciales seguras: $e');
    }
  }

  /// Reconecta con nueva configuración (desconecta y conecta nuevamente)
  Future<void> reconnectWithNewConfig(MqttHiveService? hiveService) async {
    debugPrint('[MQTT DEBUG] Reconectando con nueva configuración...');

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
      debugPrint('[MQTT DEBUG] Ya conectado al broker $broker:$port');
      return;
    }

    // Verificar conectividad de red antes de intentar MQTT
    debugPrint('[MQTT DEBUG] Verificando conectividad de red...');
    try {
      await _testNetworkConnectivity();
      debugPrint('[MQTT DEBUG] Conectividad de red OK');
    } catch (e) {
      debugPrint('[MQTT DEBUG] Error de conectividad de red: $e');
      throw Exception('No hay conectividad de red disponible');
    }

    // Solo intentar conectar al broker principal (test.mosquitto.org)
    bool success = await _tryConnect(broker, port, hiveService);

    if (!success) {
      throw Exception(
          'No se pudo conectar al broker MQTT test.mosquitto.org. Verifica tu conexión a internet.');
    }
  }

  /// Prueba la conectividad de red básica
  Future<void> _testNetworkConnectivity() async {
    // Intentar resolver un host público para validar conectividad de red.
    // Evitar paquetes extra; usar lookup con timeout.
    debugPrint('[MQTT DEBUG] Probando conectividad (lookup google.com)...');
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 5));
      if (result.isEmpty || result[0].rawAddress.isEmpty) {
        throw Exception('Lookup regresó vacío');
      }
      debugPrint('[MQTT DEBUG] Conectividad de red OK: ${result[0].address}');
    } on TimeoutException catch (e) {
      debugPrint('[MQTT DEBUG] Timeout en verificación de red: $e');
      throw Exception('Timeout verificando conectividad');
    } catch (e) {
      debugPrint('[MQTT DEBUG] Error de conectividad de red: $e');
      throw Exception('No hay conectividad de red disponible');
    }
  }

  /// Intenta conectar a un broker específico
  Future<bool> _tryConnect(String brokerAddress, int brokerPort,
      MqttHiveService? hiveService) async {
    debugPrint(
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

      // Configurar TLS si está habilitado en settings
      try {
        client!.secure = useTls;
      } catch (_) {
        // Algunas versiones no exponen secure; ignore si no está disponible
      }

      // Configuración optimizada para estabilidad mejorada
      client!.keepAlivePeriod =
          120; // Aumentado a 120 segundos para mayor estabilidad
      client!.connectTimeoutPeriod = 15000; // Aumentado a 15 segundos
      client!.autoReconnect =
          false; // Deshabilitar auto-reconnect del cliente (manejamos nosotros)
      client!.resubscribeOnAutoReconnect = true;

      // Configurar mensaje de conexión con identificador único
      final clientId = 'dropster_${DateTime.now().millisecondsSinceEpoch}';
      client!.connectionMessage = MqttConnectMessage()
          .withClientIdentifier(clientId)
          .withWillTopic('dropster/system')
          .withWillMessage('ESP32_AWG_OFFLINE')
          .withWillQos(MqttQos.atLeastOnce)
          .startClean();

      debugPrint(
          '[MQTT DEBUG] ⏱️ Iniciando conexión con timeout de ${_connectionTimeout.inSeconds}s...');

      // Si hay usuario definido, usar autenticación
      if (mqttUser.isNotEmpty) {
        await client!.connect(mqttUser, mqttPass).timeout(
          _connectionTimeout,
          onTimeout: () {
            debugPrint(
                '[MQTT DEBUG] ⏰ Timeout en conexión al broker $brokerAddress:$brokerPort');
            throw TimeoutException(
                'Connection timeout after ${_connectionTimeout.inSeconds}s');
          },
        );
      } else {
        await client!.connect().timeout(
          _connectionTimeout,
          onTimeout: () {
            debugPrint(
                '[MQTT DEBUG] ⏰ Timeout en conexión al broker $brokerAddress:$brokerPort');
            throw TimeoutException(
                'Connection timeout after ${_connectionTimeout.inSeconds}s');
          },
        );
      }

      // Verificar que la conexión sea exitosa
      if (client!.connectionStatus?.state != MqttConnectionState.connected) {
        throw Exception(
            'Connection failed: ${client!.connectionStatus?.state}');
      }

      debugPrint(
          '[MQTT DEBUG] ✅ Conexión exitosa al broker $brokerAddress:$brokerPort');
      debugPrint('[MQTT DEBUG] 📡 Client ID: $clientId');

      // Configurar listener siempre, pero solo procesar datos si hay hiveService
      _setupMessageListener(hiveService);

      // Iniciar monitoreo de actividad para mantener conexión viva
      _startActivityMonitoring();

      // Resetear contador de intentos en conexión exitosa
      _reconnectAttempts = 0;
      _lastSuccessfulConnection = DateTime.now();

      return true;
    } catch (e) {
      debugPrint(
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
      if (c.isEmpty) {
        debugPrint('[MQTT DEBUG] Lista de mensajes vacía');
        return;
      }

      final msg = c[0].payload as MqttPublishMessage;
      final topicReceived = c[0].topic;
      final payload =
          MqttPublishPayload.bytesToStringAsString(msg.payload.message);

      // Actualizar timestamp del último mensaje
      _lastMessageTime = DateTime.now();

      _log('Mensaje recibido en tópico $topicReceived');

      try {
        // Si el mensaje es del tópico esperado (datos)
        if (topicReceived == topic) {
          debugPrint(
              '[MQTT DEBUG] Procesando mensaje del tópico correcto: $topic');

          // Si tenemos hiveService, procesar los datos
          if (hiveService != null) {
            debugPrint('[MQTT DEBUG] Llamando a onMqttDataReceived...');
            hiveService.onMqttDataReceived(payload);
            debugPrint('[MQTT DEBUG] Datos procesados por Hive');

            // Procesar datos para notificaciones (en background)
            _processNotificationData(payload);
            debugPrint('[MQTT DEBUG] Notificaciones procesadas');
          } else {
            debugPrint(
                '[MQTT DEBUG] ERROR: hiveService es null, no se pueden procesar datos');
          }
        }
        // Si el mensaje viene por el tópico de estado, procesar modo/estado
        else if (topicReceived == 'dropster/status') {
          debugPrint('[MQTT DEBUG] Mensaje de STATUS recibido: $payload');

          // Procesar confirmación de configuración
          if (payload.contains('"type":"config_ack"')) {
            try {
              final jsonData = jsonDecode(payload);
              if (jsonData is Map<String, dynamic> &&
                  jsonData['type'] == 'config_ack') {
                debugPrint(
                    '[MQTT CONFIG] ✅ Confirmación de configuración recibida por STATUS: ${jsonData['changes']} cambios aplicados');
                debugPrint('[MQTT CONFIG] 📊 Estado: ${jsonData['status']}');
                debugPrint(
                    '[MQTT CONFIG] ⏱️  Timestamp: ${jsonData['timestamp']}');
                debugPrint(
                    '[MQTT CONFIG] 🔋 Uptime ESP32: ${jsonData['uptime']} segundos');
                // Siempre marcar como config_saved=true independientemente de si hay cambios o no
                SingletonMqttService().notifier.value = {
                  ...SingletonMqttService().notifier.value,
                  'config_saved': true,
                  'config_ack_data': jsonData,
                };
              }
            } catch (e) {
              debugPrint(
                  '[MQTT DEBUG] Error procesando confirmación de configuración: $e');
            }
          }
          // Procesar heartbeat del ESP32 (system_status)
          else if (payload.contains('"type":"system_status"')) {
            try {
              final jsonData = jsonDecode(payload);
              if (jsonData is Map<String, dynamic> &&
                  jsonData['type'] == 'system_status') {
                debugPrint(
                    '[MQTT HEARTBEAT] 💓 Heartbeat recibido del dispositivo - uptime: ${jsonData['uptime']}');
                // Marcar dispositivo como online
                SingletonMqttService().deviceConnectionNotifier.value = true;
              }
            } catch (e) {
              debugPrint('[MQTT DEBUG] Error procesando heartbeat: $e');
            }
          } else {
            try {
              final Map<String, dynamic> json = jsonDecode(payload);

              // Procesar errores de bomba
              if (json.containsKey('type') && json['type'] == 'pump_error') {
                debugPrint('[MQTT DEBUG] Error de bomba recibido: $json');
                _pumpErrorController.add(json);
                return; // No procesar otros campos para este mensaje
              }

              if (json.containsKey('mode')) {
                final String mode = json['mode'].toString();
                debugPrint('[MQTT DEBUG] Modo recibido: $mode');
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
              if (json.containsKey('compressor_fan')) {
                SingletonMqttService().notifier.value = {
                  ...SingletonMqttService().notifier.value,
                  'cfs': json['compressor_fan'] ?? 0,
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
              } else if (payload.contains('CFAN_ON')) {
                SingletonMqttService().notifier.value = {
                  ...SingletonMqttService().notifier.value,
                  'cfs': 1,
                };
              } else if (payload.contains('CFAN_OFF')) {
                SingletonMqttService().notifier.value = {
                  ...SingletonMqttService().notifier.value,
                  'cfs': 0,
                };
              } else if (payload.contains('AUTO_COMP_ON')) {
                SingletonMqttService().notifier.value = {
                  ...SingletonMqttService().notifier.value,
                  'cs': 1,
                };
              } else if (payload.contains('AUTO_COMP_OFF')) {
                SingletonMqttService().notifier.value = {
                  ...SingletonMqttService().notifier.value,
                  'cs': 0,
                };
              }
            }
          }
        }
        // Si el mensaje viene por el tópico de alertas, procesar alertas
        else if (topicReceived.contains('/alerts')) {
          debugPrint('[MQTT ALERT] Mensaje de ALERTA recibido: $payload');
          _processAlertData(payload);
        }
        // Si el mensaje viene por el tópico de errores, procesar errores
        else if (topicReceived.contains('/errors')) {
          debugPrint('[MQTT ERROR] Mensaje de ERROR recibido: $payload');
          _processErrorData(payload);
        }
        // Si el mensaje viene por el tópico de sistema, procesar estado del sistema
        else if (topicReceived == 'dropster/system') {
          debugPrint('[MQTT SYSTEM] Mensaje de SISTEMA recibido: $payload');

          // Procesar backup de configuración desde SYSTEM
          if (payload.startsWith('BACKUP:')) {
            try {
              final jsonStr = payload.substring(7); // Remover "BACKUP:"
              final configData = jsonDecode(jsonStr) as Map<String, dynamic>;
              debugPrint(
                  '[MQTT DEBUG] Backup de configuración recibido por SYSTEM: ${configData.keys}');
              // Actualizar el notifier con el JSON completo del backup (manteniendo la estructura original)
              SingletonMqttService().notifier.value = {
                ...SingletonMqttService().notifier.value,
                ...configData, // Expandir el JSON del backup directamente en el notifier
              };
            } catch (e) {
              debugPrint(
                  '[MQTT DEBUG] Error procesando backup de configuración desde SYSTEM: $e');
            }
          } else {
            _processSystemData(payload);
          }
        } else {
          debugPrint(
              '[MQTT DEBUG] Mensaje ignorado - tópico: $topicReceived, esperado: $topic, dropster/status, dropster/alerts, dropster/errors o dropster/system');
        }
      } catch (e) {
        debugPrint('[MQTT DEBUG] Error procesando mensaje MQTT: $e');
      }
    });

    // Se suscribe al tópico de datos de energía con QoS 1 (atLeastOnce) para mayor fiabilidad
    // Nota: Ya se suscribió arriba, aquí solo se registra el log
    debugPrint('[MQTT DEBUG] Suscrito al tópico $topic (QoS 1)');

    // Suscribirse al tópico de datos (principal)
    client!.subscribe(topic, MqttQos.atLeastOnce);
    debugPrint('[MQTT DEBUG] Suscrito al tópico $topic (QoS 1)');

    // Suscribirse al tópico de estado para recibir modo y otros estados
    client!.subscribe('dropster/status', MqttQos.atLeastOnce);
    debugPrint('[MQTT DEBUG] Suscrito al tópico dropster/status (QoS 1)');

    // Suscribirse al tópico de alertas para recibir alertas del ESP32
    client!.subscribe('dropster/alerts', MqttQos.atLeastOnce);
    debugPrint('[MQTT DEBUG] Suscrito al tópico dropster/alerts (QoS 1)');

    // Suscribirse al tópico de errores para recibir mensajes de error del ESP32
    client!.subscribe('dropster/errors', MqttQos.atLeastOnce);
    debugPrint('[MQTT DEBUG] Suscrito al tópico dropster/errors (QoS 1)');

    // Suscribirse al tópico de sistema para recibir estado general y backups del ESP32
    client!.subscribe('dropster/system', MqttQos.atLeastOnce);
    debugPrint('[MQTT DEBUG] Suscrito al tópico dropster/system (QoS 1)');
  }

  /// Publica un comando al tópico de control del ESP32
  Future<void> publishCommand(String command) async {
    if (client != null && isConnected) {
      try {
        final builder = MqttClientPayloadBuilder();
        builder.addString(command);
        client!.publishMessage('dropster/control', MqttQos.atLeastOnce,
            builder.payload!); // Topic corregido, usar QoS 1 para fiabilidad
        debugPrint('[MQTT DEBUG] Comando enviado: $command');
      } catch (e) {
        debugPrint('[MQTT DEBUG] Error enviando comando: $e');
        rethrow;
      }
    } else {
      debugPrint(
          '[MQTT DEBUG] No se puede enviar comando: cliente no conectado');
      throw Exception('MQTT client not connected');
    }
  }

  /// Publicar cambio de modo (AUTO/MANUAL) por MQTT
  Future<void> publishMode(String mode) async {
    // mode = "AUTO" o "MANUAL"
    final cmd = (mode.toUpperCase() == 'AUTO') ? 'MODE AUTO' : 'MODE MANUAL';
    await publishCommand(cmd);
    debugPrint('[MQTT DEBUG] publishMode: $cmd');
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
      });

      // Enviar como "UPDATE_MQTT_CONFIG" + JSON
      final command = 'UPDATE_MQTT_CONFIG$configJson';
      await publishCommand(command);
      debugPrint('[MQTT DEBUG] Configuración MQTT enviada al ESP32: $command');
    } catch (e) {
      debugPrint('[MQTT DEBUG] Error enviando configuración MQTT al ESP32: $e');
      rethrow;
    }
  }

  /// Enviar configuración completa (MQTT + alertas + control) al ESP32 con confirmación
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
    required double ultrasonicOffset,
    required double controlDeadband,
    required int controlMinOff,
    required int controlMaxOn,
    required int controlSampling,
    required double controlAlpha,
    required double maxCompressorTemp,
    required int displayTimeoutMinutes,
    required bool showNotifications,
    required bool dailyReportEnabled,
    required TimeOfDay dailyReportTime,
  }) async {
    const int maxRetries = 3;
    const Duration timeout = Duration(seconds: 30);

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        debugPrint(
            '[MQTT CONFIG] Intento $attempt/$maxRetries de enviar configuración al ESP32');

        // Función para formatear valores con máximo 2 decimales
        String formatValue(dynamic value) {
          if (value is double) {
            return value.toStringAsFixed(2);
          }
          return value.toString();
        }

        // Crear JSON abreviado para configuración (como en transmitMQTTData)
        final Map<String, dynamic> configJson = {
          'mqtt': {
            'b': broker, // broker
            'p': port, // port
          },
          'alerts': {
            'tf': tankFullEnabled, // tank full
            'tfv': formatValue(tankFullThreshold.toInt()),
            'vl': voltageLowEnabled, // voltage low
            'vlv': formatValue(voltageLowThreshold.toInt()),
            'hl': humidityLowEnabled, // humidity low
            'hlv': formatValue(humidityLowThreshold.toInt()),
          },
          'control': {
            'db': formatValue(controlDeadband), // deadband
            'mof': controlMinOff, // min off
            'mon': controlMaxOn, // max on
            'smp': controlSampling, // sampling
            'alp': formatValue(controlAlpha), // alpha
            'mt': formatValue(maxCompressorTemp.toInt()), // max temp
            'dt': displayTimeoutMinutes * 60, // display timeout in seconds
          },
          'tank': {
            'cap': formatValue(tankCapacity), // capacity
            'cal': isCalibrated, // calibrated
            'off': formatValue(ultrasonicOffset), // offset
          },
        };

        final fullConfigJson = jsonEncode(configJson);
        debugPrint(
            '[MQTT CONFIG] 📊 JSON abreviado creado - Longitud: ${fullConfigJson.length} caracteres');

        // Enviar como "update_config" + JSON (minúsculas como espera el ESP32)
        // DIVIDIR EL MENSAJE EN PARTES MÁS PEQUEÑAS PARA EVITAR TRUNCAMIENTO
        final command = 'update_config$fullConfigJson';
        debugPrint('[MQTT CONFIG] 📤 Comando completo a enviar: "$command"');
        debugPrint(
            '[MQTT CONFIG] 📏 Longitud del comando: ${command.length} caracteres');

        // Siempre dividir en partes para consistencia y robustez
        debugPrint(
            '[MQTT CONFIG] 📦 Enviando configuración en partes fragmentadas...');

        // Parte 1: MQTT
        final part1 = 'update_config_part1${jsonEncode(configJson['mqtt'])}';
        debugPrint(
            '[MQTT CONFIG] 📤 Parte 1 MQTT: "$part1" (${part1.length} chars)');

        final builder1 = MqttClientPayloadBuilder();
        builder1.addString(part1);
        client!.publishMessage(
            'dropster/control', MqttQos.atLeastOnce, builder1.payload!);

        await Future.delayed(const Duration(milliseconds: 300));

        // Parte 2: Alertas
        final part2 = 'update_config_part2${jsonEncode(configJson['alerts'])}';
        debugPrint(
            '[MQTT CONFIG] 📤 Parte 2 Alertas: "$part2" (${part2.length} chars)');

        final builder2 = MqttClientPayloadBuilder();
        builder2.addString(part2);
        client!.publishMessage(
            'dropster/control', MqttQos.atLeastOnce, builder2.payload!);

        await Future.delayed(const Duration(milliseconds: 300));

        // Parte 3: Control
        final part3 = 'update_config_part3${jsonEncode(configJson['control'])}';
        debugPrint(
            '[MQTT CONFIG] 📤 Parte 3 Control: "$part3" (${part3.length} chars)');

        final builder3 = MqttClientPayloadBuilder();
        builder3.addString(part3);
        client!.publishMessage(
            'dropster/control', MqttQos.atLeastOnce, builder3.payload!);

        await Future.delayed(const Duration(milliseconds: 300));

        // Parte 4: Tanque
        final part4 = 'update_config_part4${jsonEncode(configJson['tank'])}';
        debugPrint(
            '[MQTT CONFIG] 📤 Parte 4 Tanque: "$part4" (${part4.length} chars)');

        final builder4 = MqttClientPayloadBuilder();
        builder4.addString(part4);
        client!.publishMessage(
            'dropster/control', MqttQos.atLeastOnce, builder4.payload!);

        await Future.delayed(const Duration(milliseconds: 300));

        // Comando de ensamblaje
        final finalCmd = 'update_config_assemble';
        debugPrint('[MQTT CONFIG] 📤 Comando ensamblaje: "$finalCmd"');

        final builderFinal = MqttClientPayloadBuilder();
        builderFinal.addString(finalCmd);
        client!.publishMessage(
            'dropster/control', MqttQos.atLeastOnce, builderFinal.payload!);

        debugPrint(
            '[MQTT CONFIG] ✅ Configuración enviada al ESP32 (intento $attempt). Esperando confirmación...');

        // Esperar confirmación del ESP32 con timeout
        final ackReceived = await _waitForConfigAck(timeout);
        if (ackReceived) {
          debugPrint(
              '[MQTT CONFIG] ✅ Configuración aplicada exitosamente en ESP32');
          return; // Éxito, salir del método
        } else {
          debugPrint(
              '[MQTT CONFIG] ❌ No se recibió confirmación del ESP32 en ${timeout.inSeconds}s');
          if (attempt == maxRetries) {
            throw Exception(
                'ESP32 no confirmó recepción de configuración después de $maxRetries intentos');
          }
        }

        // Esperar antes del siguiente intento
        if (attempt < maxRetries) {
          await Future.delayed(Duration(seconds: 2));
        }
      } catch (e) {
        debugPrint('[MQTT CONFIG] ❌ Error en intento $attempt: $e');
        if (attempt == maxRetries) {
          rethrow;
        }
        await Future.delayed(Duration(seconds: 1));
      }
    }
  }

  /// Espera confirmación de configuración del ESP32
  Future<bool> _waitForConfigAck(Duration timeout) async {
    final completer = Completer<bool>();
    Timer? timer;

    // Listener temporal para mensajes de confirmación
    late StreamSubscription subscription;

    subscription = client!.updates!
        .listen((List<MqttReceivedMessage<MqttMessage>> messages) {
      for (final message in messages) {
        final topic = message.topic;
        if (topic == 'dropster/status') {
          // Esperar confirmación en STATUS (donde el ESP32 envía confirmaciones)
          final payload = MqttPublishPayload.bytesToStringAsString(
              (message.payload as MqttPublishMessage).payload.message);

          try {
            final jsonData = jsonDecode(payload);
            if (jsonData is Map<String, dynamic> &&
                jsonData['type'] == 'config_ack' &&
                jsonData['status'] == 'success') {
              debugPrint(
                  '[MQTT CONFIG] 📨 Confirmación recibida del ESP32: $payload');
              completer.complete(true);
              subscription.cancel();
              timer?.cancel();
              return;
            }
          } catch (e) {
            // No es JSON válido, continuar
          }
        }
      }
    });

    // Timeout
    timer = Timer(timeout, () {
      debugPrint('[MQTT CONFIG] ⏰ Timeout esperando confirmación del ESP32');
      completer.complete(false);
      subscription.cancel();
    });

    return completer.future;
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
      debugPrint('[MQTT DEBUG] Error procesando datos para notificaciones: $e');
    }
  }

  /// Procesa mensajes de alertas del ESP32
  void _processAlertData(String payload) {
    try {
      NotificationService().processAlertData(payload);
    } catch (e) {
      debugPrint('[MQTT DEBUG] Error procesando datos de alerta: $e');
    }
  }

  /// Procesa mensajes de error del ESP32
  void _processErrorData(String payload) {
    try {
      final jsonData = jsonDecode(payload);
      if (jsonData is Map<String, dynamic> && jsonData.containsKey('type')) {
        if (jsonData['type'] == 'pump_error') {
          debugPrint('[MQTT ERROR] Error de bomba recibido: $jsonData');
          _pumpErrorController.add(jsonData);
        }
      }
    } catch (e) {
      debugPrint('[MQTT DEBUG] Error procesando datos de error: $e');
    }
  }

  /// Procesa mensajes de sistema del ESP32
  void _processSystemData(String payload) {
    try {
      // Procesar mensajes de estado del sistema (online/offline)
      if (payload.contains('ONLINE')) {
        debugPrint('[MQTT SYSTEM] Dispositivo reporta estado ONLINE');
        // Actualizar notifier con estado de conexión del dispositivo
        SingletonMqttService().deviceConnectionNotifier.value = true;
      } else if (payload.contains('OFFLINE')) {
        debugPrint('[MQTT SYSTEM] Dispositivo reporta estado OFFLINE');
        SingletonMqttService().deviceConnectionNotifier.value = false;
      }
    } catch (e) {
      debugPrint('[MQTT DEBUG] Error procesando datos de sistema: $e');
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
      debugPrint('[MQTT DEBUG] Error parseando JSON: $e');
    }
    return null;
  }
}

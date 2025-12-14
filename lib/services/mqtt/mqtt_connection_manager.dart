import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

/// Gestiona la conexión MQTT, reconexión automática y monitoreo de salud
class MqttConnectionManager {
  MqttServerClient? client;
  Timer? _reconnectTimer;
  Timer? _connectionCheckTimer;
  bool _isReconnecting = false;
  int _reconnectAttempts = 0;
  DateTime? _lastSuccessfulConnection;

  static const int _maxReconnectAttempts = 20;
  static const Duration _baseReconnectInterval = Duration(seconds: 2);
  static const Duration _maxReconnectInterval = Duration(minutes: 5);
  static const Duration _connectionCheckInterval = Duration(seconds: 5);
  static const Duration _connectionTimeout = Duration(seconds: 15);

  /// Función helper para logs condicionales
  void _log(String message) {
    if (kDebugMode) {
      debugPrint('[MQTT-CONN] $message');
    }
  }

  /// Devuelve true si el cliente está conectado al broker
  bool get isConnected =>
      client?.connectionStatus?.state == MqttConnectionState.connected;

  /// Inicia el monitoreo de conexión para reconexión automática
  void startConnectionMonitoring(Function() onReconnectAttempt) {
    _connectionCheckTimer = Timer.periodic(_connectionCheckInterval, (_) {
      _log('Estado: ${isConnected ? 'CONECTADO' : 'DESCONECTADO'}');

      if (!isConnected && !_isReconnecting) {
        _log(
            '⚠️ Conexión perdida detectada, iniciando reconexión automática...');
        onReconnectAttempt();
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

  /// Intenta conectar a un broker específico
  Future<bool> tryConnect(
    String brokerAddress,
    int brokerPort,
    bool useTls,
    String? username,
    String? password,
  ) async {
    _log('🔗 Intentando conectar a $brokerAddress:$brokerPort');

    try {
      // Limpiar cliente anterior si existe
      if (client != null) {
        client!.disconnect();
        client = null;
      }

      client = MqttServerClient(brokerAddress, '');
      client!.port = brokerPort;
      client!.logging(on: false);

      // Configurar TLS si está habilitado
      try {
        client!.secure = useTls;
      } catch (_) {
        // Algunas versiones no exponen secure; ignore si no está disponible
      }

      // Configuración optimizada para estabilidad
      client!.keepAlivePeriod = 120;
      client!.connectTimeoutPeriod = 15000;
      client!.autoReconnect = false;
      client!.resubscribeOnAutoReconnect = true;

      // Configurar mensaje de conexión con identificador único
      final clientId = 'dropster_${DateTime.now().millisecondsSinceEpoch}';
      client!.connectionMessage = MqttConnectMessage()
          .withClientIdentifier(clientId)
          .withWillTopic('dropster/system')
          .withWillMessage('ESP32_AWG_OFFLINE')
          .withWillQos(MqttQos.atLeastOnce)
          .startClean();

      _log(
          '⏱️ Iniciando conexión con timeout de ${_connectionTimeout.inSeconds}s...');

      // Si hay usuario definido, usar autenticación
      if (username?.isNotEmpty ?? false) {
        await client!.connect(username, password).timeout(_connectionTimeout);
      } else {
        await client!.connect().timeout(_connectionTimeout);
      }

      // Verificar que la conexión sea exitosa
      if (client!.connectionStatus?.state != MqttConnectionState.connected) {
        throw Exception(
            'Connection failed: ${client!.connectionStatus?.state}');
      }

      _log('✅ Conexión exitosa al broker $brokerAddress:$brokerPort');
      _log('📡 Client ID: $clientId');

      // Resetear contador de intentos en conexión exitosa
      _reconnectAttempts = 0;
      _lastSuccessfulConnection = DateTime.now();

      return true;
    } catch (e) {
      _log('❌ Error al conectar a $brokerAddress:$brokerPort: $e');
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

  /// Intenta reconectar al broker con backoff exponencial
  Future<void> attemptReconnect(
    String broker,
    int port,
    bool useTls,
    String? username,
    String? password,
  ) async {
    if (_isReconnecting) return;

    _reconnectAttempts++;
    if (_reconnectAttempts > _maxReconnectAttempts) {
      _log(
          'Máximo número de intentos de reconexión alcanzado ($_maxReconnectAttempts)');
      _isReconnecting = false;
      return;
    }

    _isReconnecting = true;
    _log(
        '🔄 Intentando reconexión (intento $_reconnectAttempts/$_maxReconnectAttempts)');

    try {
      final success =
          await tryConnect(broker, port, useTls, username, password);
      if (success) {
        _log('✅ Reconexión exitosa - Conexión establecida');
        _isReconnecting = false;
        return;
      }
    } catch (e) {
      // Backoff exponencial con jitter
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
            .round(),
      );

      _log(
          '❌ Reconexión fallida (intento $_reconnectAttempts/$_maxReconnectAttempts)');
      _log('⏰ Próximo intento en ${delay.inSeconds}s');

      _reconnectTimer = Timer(delay, () {
        _isReconnecting = false;
        attemptReconnect(broker, port, useTls, username, password);
      });
    }
  }

  /// Desconecta el cliente del broker MQTT
  void disconnect() {
    client?.disconnect();
    client = null;
  }

  /// Prueba conectividad básica de red
  Future<void> testNetworkConnectivity() async {
    _log('Probando conectividad (lookup google.com)...');
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 5));
      if (result.isEmpty || result[0].rawAddress.isEmpty) {
        throw Exception('Lookup regresó vacío');
      }
      _log('Conectividad de red OK: ${result[0].address}');
    } on TimeoutException catch (e) {
      _log('Timeout en verificación de red: $e');
      throw Exception('Timeout verificando conectividad');
    } catch (e) {
      _log('Error de conectividad de red: $e');
      throw Exception('No hay conectividad de red disponible');
    }
  }

  /// Obtiene estadísticas de conexión
  Map<String, dynamic> getConnectionStats() {
    return {
      'isConnected': isConnected,
      'isReconnecting': _isReconnecting,
      'reconnectAttempts': _reconnectAttempts,
      'lastSuccessfulConnection': _lastSuccessfulConnection?.toIso8601String(),
    };
  }
}

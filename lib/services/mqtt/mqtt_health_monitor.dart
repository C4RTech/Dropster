import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

/// Monitorea la salud de la conexión MQTT y realiza diagnósticos de red
class MqttHealthMonitor {
  Timer? _pingTimer;
  Timer? _networkDiagnosticTimer;
  bool _isInBackground = false;
  DateTime? _lastMessageTime;
  DateTime? _lastPingTime;
  DateTime? _lastNetworkCheck;

  static const Duration _pingInterval = Duration(seconds: 30);
  static const Duration _backgroundPingInterval = Duration(seconds: 60);
  static const Duration _networkDiagnosticInterval = Duration(minutes: 5);

  /// Función helper para logs condicionales
  void _log(String message) {
    if (kDebugMode) {
      debugPrint('[MQTT-HEALTH] $message');
    }
  }

  /// Inicia el monitoreo de actividad para mantener la conexión viva
  void startActivityMonitoring(MqttServerClient? client, bool isConnected) {
    _pingTimer?.cancel();
    final activityInterval =
        _isInBackground ? _backgroundPingInterval : _pingInterval;

    _pingTimer = Timer.periodic(activityInterval, (_) {
      if (isConnected && client != null) {
        final now = DateTime.now();
        _lastPingTime = now;

        final timeSinceLastMessage = _lastMessageTime != null
            ? now.difference(_lastMessageTime!).inSeconds
            : 0;

        if (timeSinceLastMessage > 120) {
          _log(
              'Sin actividad por ${timeSinceLastMessage}s, verificando conexión...');
          _checkConnectionHealth(client);
        }

        if (timeSinceLastMessage > 0 && timeSinceLastMessage % 300 == 0) {
          _log('Estado conexión: último mensaje hace ${timeSinceLastMessage}s');
        }
      }
    });
  }

  /// Detiene el monitoreo de actividad
  void stopActivityMonitoring() {
    _pingTimer?.cancel();
    _pingTimer = null;
  }

  /// Inicia el monitoreo de diagnóstico de red
  void startNetworkDiagnosticMonitoring(Function() performDiagnostic) {
    _networkDiagnosticTimer?.cancel();
    _networkDiagnosticTimer = Timer.periodic(_networkDiagnosticInterval, (_) {
      final now = DateTime.now();
      final timeSinceLastCheck = _lastNetworkCheck != null
          ? now.difference(_lastNetworkCheck!).inMinutes
          : null;

      if ((timeSinceLastCheck == null || timeSinceLastCheck >= 5)) {
        _log('Iniciando diagnóstico de red automático...');
        performDiagnostic();
        _lastNetworkCheck = now;
      }
    });
  }

  /// Detiene el monitoreo de diagnóstico de red
  void stopNetworkDiagnosticMonitoring() {
    _networkDiagnosticTimer?.cancel();
  }

  /// Verifica la salud de la conexión
  void _checkConnectionHealth(MqttServerClient client) {
    final isConnected =
        client.connectionStatus?.state == MqttConnectionState.connected;
    if (!isConnected) {
      _log('Conexión detectada como perdida, intentando reconectar...');
    } else {
      final now = DateTime.now();
      final timeSinceLastPing =
          _lastPingTime != null ? now.difference(_lastPingTime!).inSeconds : 0;
      _log('Conexión saludable (último ping: ${timeSinceLastPing}s)');
    }
  }

  /// Configura el modo background/foreground
  void setBackgroundMode(bool isBackground) {
    if (_isInBackground != isBackground) {
      _isInBackground = isBackground;
      if (isBackground) {
        _log('App en background - ajustando configuración');
      } else {
        _log('App en foreground - optimizando configuración');
      }
    }
  }

  /// Actualiza el timestamp del último mensaje recibido
  void updateLastMessageTime() {
    _lastMessageTime = DateTime.now();
  }

  /// Ejecuta diagnóstico completo de red
  Future<Map<String, dynamic>> performNetworkDiagnostic(
    Future<void> Function() testNetworkConnectivity,
    Future<void> Function() testMqttConnectivity,
    Map<String, dynamic> Function() getConnectionStats,
  ) async {
    _log('🔍 Ejecutando diagnóstico de red...');
    final results = <String, dynamic>{};

    try {
      // Verificar conectividad básica
      await testNetworkConnectivity();
      results['network_connectivity'] = 'OK';

      // Verificar conectividad MQTT
      await testMqttConnectivity();
      results['mqtt_connectivity'] = 'OK';

      // Obtener estadísticas de conexión
      results['connection_stats'] = getConnectionStats();

      _log('✅ Diagnóstico completado exitosamente');
      results['overall_status'] = 'SUCCESS';
    } catch (e) {
      _log('❌ Diagnóstico fallido: $e');
      results['overall_status'] = 'FAILED';
      results['error'] = e.toString();
    }

    return results;
  }

  /// Prueba conectividad MQTT específica
  Future<void> testMqttConnectivity(String broker, int port) async {
    try {
      _log('🔌 Probando conectividad MQTT al broker $broker:$port...');

      final socket = await Socket.connect(broker, port,
          timeout: const Duration(seconds: 5));
      socket.destroy();

      _log('✅ Broker MQTT reachable: $broker:$port');
    } catch (e) {
      _log('❌ Broker MQTT NO reachable: $broker:$port - Error: $e');
      throw Exception('Broker MQTT no accesible');
    }
  }

  /// Obtiene el timestamp del último mensaje
  DateTime? get lastMessageTime => _lastMessageTime;

  /// Libera recursos
  void dispose() {
    stopActivityMonitoring();
    stopNetworkDiagnosticMonitoring();
  }
}

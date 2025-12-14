import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import '../singleton_mqtt_service.dart';
import '../notification_service.dart';

/// Procesa mensajes MQTT entrantes de diferentes tópicos
class MqttMessageProcessor {
  // Stream para publicar cambios de modo
  final StreamController<String> _modeController =
      StreamController<String>.broadcast();
  Stream<String> get modeStream => _modeController.stream;

  // Stream para notificar errores de bomba a la UI
  final StreamController<Map<String, dynamic>> _pumpErrorController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get pumpErrorStream =>
      _pumpErrorController.stream;

  /// Función helper para logs condicionales
  void _log(String message) {
    if (kDebugMode) {
      debugPrint('[MQTT-MSG] $message');
    }
  }

  /// Configura el listener de mensajes MQTT
  void setupMessageListener(MqttServerClient client, String dataTopic) {
    client.updates?.listen((List<MqttReceivedMessage<MqttMessage>> c) {
      if (c.isEmpty) {
        _log('Lista de mensajes vacía');
        return;
      }

      final msg = c[0].payload as MqttPublishMessage;
      final topicReceived = c[0].topic;
      final payload =
          MqttPublishPayload.bytesToStringAsString(msg.payload.message);

      _log('Mensaje recibido en tópico $topicReceived');

      try {
        // Procesar según el tópico
        if (topicReceived == dataTopic) {
          _processDataMessage(payload);
        } else if (topicReceived == 'dropster/status') {
          _processStatusMessage(payload);
        } else if (topicReceived.contains('/alerts')) {
          _processAlertMessage(payload);
        } else if (topicReceived.contains('/errors')) {
          _processErrorMessage(payload);
        } else if (topicReceived == 'dropster/system') {
          _processSystemMessage(payload);
        } else {
          _log('Mensaje ignorado - tópico: $topicReceived');
        }
      } catch (e) {
        _log('Error procesando mensaje MQTT: $e');
      }
    });

    // Suscribirse a los tópicos necesarios
    _subscribeToTopics(client, dataTopic);
  }

  /// Suscribe el cliente a todos los tópicos necesarios
  void _subscribeToTopics(MqttServerClient client, String dataTopic) {
    client.subscribe(dataTopic, MqttQos.atLeastOnce);
    _log('Suscrito al tópico $dataTopic (QoS 1)');

    client.subscribe('dropster/status', MqttQos.atLeastOnce);
    _log('Suscrito al tópico dropster/status (QoS 1)');

    client.subscribe('dropster/alerts', MqttQos.atLeastOnce);
    _log('Suscrito al tópico dropster/alerts (QoS 1)');

    client.subscribe('dropster/errors', MqttQos.atLeastOnce);
    _log('Suscrito al tópico dropster/errors (QoS 1)');

    client.subscribe('dropster/system', MqttQos.atLeastOnce);
    _log('Suscrito al tópico dropster/system (QoS 1)');
  }

  /// Procesa mensajes de datos del sensor
  void _processDataMessage(String payload) {
    _log('Procesando mensaje del tópico correcto');
    // Aquí se llamaría a hiveService.onMqttDataReceived(payload)
    // pero eso se maneja en el servicio principal
  }

  /// Procesa mensajes de estado del ESP32
  void _processStatusMessage(String payload) {
    _log('Mensaje de STATUS recibido: $payload');

    // Procesar confirmación de configuración
    if (payload.contains('"type":"config_ack"')) {
      try {
        final jsonData = jsonDecode(payload);
        if (jsonData is Map<String, dynamic> &&
            jsonData['type'] == 'config_ack') {
          _log(
              'Confirmación de configuración recibida por STATUS: ${jsonData['changes']} cambios aplicados');
          SingletonMqttService().notifier.value = {
            ...SingletonMqttService().notifier.value,
            'config_saved': true,
            'config_ack_data': jsonData,
          };
        }
      } catch (e) {
        _log('Error procesando confirmación de configuración: $e');
      }
    } else {
      try {
        final Map<String, dynamic> json = jsonDecode(payload);

        // Procesar errores de bomba
        if (json.containsKey('type') && json['type'] == 'pump_error') {
          _log('Error de bomba recibido: $json');
          _pumpErrorController.add(json);
          return; // No procesar otros campos para este mensaje
        }

        // Procesar modo de operación
        if (json.containsKey('mode')) {
          final String mode = json['mode'].toString();
          _log('Modo recibido: $mode');
          _modeController.add(mode);
          SingletonMqttService().notifier.value = {
            ...SingletonMqttService().notifier.value,
            'mode': mode,
          };
        }

        // Procesar estados individuales de relés
        _processRelayStates(json);
      } catch (e) {
        // Si no es JSON, procesar como mensajes simples
        _processSimpleModeMessage(payload);
      }
    }
  }

  /// Procesa estados de relés desde JSON
  void _processRelayStates(Map<String, dynamic> json) {
    final updates = <String, dynamic>{};

    if (json.containsKey('compressor')) {
      updates['cs'] = json['compressor'];
    }
    if (json.containsKey('ventilador')) {
      updates['vs'] = json['ventilador'];
    }
    if (json.containsKey('pump')) {
      updates['ps'] = json['pump'];
    }
    if (json.containsKey('compressor_fan')) {
      updates['cfs'] = json['compressor_fan'] ?? 0;
    }

    if (updates.isNotEmpty) {
      SingletonMqttService().notifier.value = {
        ...SingletonMqttService().notifier.value,
        ...updates,
      };
    }
  }

  /// Procesa mensajes simples de modo (no JSON)
  void _processSimpleModeMessage(String payload) {
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
    } else {
      // Procesar estados individuales de relés
      _processSimpleRelayStates(payload);
    }
  }

  /// Procesa estados simples de relés (no JSON)
  void _processSimpleRelayStates(String payload) {
    if (payload.contains('COMP_ON')) {
      SingletonMqttService().notifier.value = {
        ...SingletonMqttService().notifier.value,
        'cs': 1,
      };
    } else if (payload.contains('COMP_OFF')) {
      SingletonMqttService().notifier.value = {
        ...SingletonMqttService().notifier.value,
        'cs': 0,
      };
    }
    // ... otros estados similares
  }

  /// Procesa mensajes de alertas
  void _processAlertMessage(String payload) {
    _log('Mensaje de ALERTA recibido: $payload');
    try {
      NotificationService().processAlertData(payload);
    } catch (e) {
      _log('Error procesando datos de alerta: $e');
    }
  }

  /// Procesa mensajes de error
  void _processErrorMessage(String payload) {
    _log('Mensaje de ERROR recibido: $payload');
    try {
      final jsonData = jsonDecode(payload);
      if (jsonData is Map<String, dynamic> && jsonData.containsKey('type')) {
        if (jsonData['type'] == 'pump_error') {
          _log('Error de bomba recibido: $jsonData');
          _pumpErrorController.add(jsonData);
        }
      }
    } catch (e) {
      _log('Error procesando datos de error: $e');
    }
  }

  /// Procesa mensajes de sistema
  void _processSystemMessage(String payload) {
    _log('Mensaje de SISTEMA recibido: $payload');

    // Procesar backup de configuración desde SYSTEM
    if (payload.startsWith('BACKUP:')) {
      try {
        final jsonStr = payload.substring(7);
        final configData = jsonDecode(jsonStr) as Map<String, dynamic>;
        _log('Backup de configuración recibido por SYSTEM: ${configData.keys}');
        SingletonMqttService().notifier.value = {
          ...SingletonMqttService().notifier.value,
          ...configData,
        };
      } catch (e) {
        _log('Error procesando backup de configuración desde SYSTEM: $e');
      }
    } else {
      // Procesar mensajes de estado del sistema
      if (payload.contains('ONLINE')) {
        _log('ESP32 reporta estado ONLINE');
        SingletonMqttService().connectionNotifier.value = true;
      } else if (payload.contains('OFFLINE')) {
        _log('ESP32 reporta estado OFFLINE');
        SingletonMqttService().connectionNotifier.value = false;
      }
    }
  }

  /// Procesa datos MQTT para activar notificaciones
  void processNotificationData(String payload) {
    try {
      final sensorData = _parseSensorData(payload);
      if (sensorData != null) {
        NotificationService().processSensorData(sensorData);
      }
    } catch (e) {
      _log('Error procesando datos para notificaciones: $e');
    }
  }

  /// Parsea los datos JSON del sensor
  Map<String, dynamic>? _parseSensorData(String payload) {
    try {
      final jsonData = jsonDecode(payload);
      if (jsonData is Map<String, dynamic>) {
        return jsonData;
      }
    } catch (e) {
      _log('Error parseando JSON: $e');
    }
    return null;
  }

  /// Libera recursos
  void dispose() {
    _modeController.close();
    _pumpErrorController.close();
  }
}

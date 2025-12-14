import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:flutter/material.dart';

/// Gestiona la publicación de comandos MQTT al ESP32
class MqttCommandPublisher {
  final MqttServerClient? client;

  MqttCommandPublisher(this.client);

  /// Función helper para logs condicionales
  void _log(String message) {
    if (kDebugMode) {
      debugPrint('[MQTT-CMD] $message');
    }
  }

  /// Publica un comando simple al tópico de control
  Future<void> publishCommand(String command) async {
    if (client == null || !isConnected) {
      _log('No se puede enviar comando: cliente no conectado');
      throw Exception('MQTT client not connected');
    }

    try {
      final builder = MqttClientPayloadBuilder();
      builder.addString(command);
      client!.publishMessage(
          'dropster/control', MqttQos.atLeastOnce, builder.payload!);
      _log('Comando enviado: $command');
    } catch (e) {
      _log('Error enviando comando: $e');
      rethrow;
    }
  }

  /// Publica cambio de modo (AUTO/MANUAL)
  Future<void> publishMode(String mode) async {
    final cmd = (mode.toUpperCase() == 'AUTO') ? 'MODE AUTO' : 'MODE MANUAL';
    await publishCommand(cmd);
    _log('publishMode: $cmd');
  }

  /// Envía configuración MQTT al ESP32
  Future<void> sendMqttConfigToESP32(
      String newBroker, int newPort, String newTopic) async {
    try {
      final configJson = jsonEncode({
        'broker': newBroker,
        'port': newPort,
        'topic': newTopic,
      });

      final command = 'UPDATE_MQTT_CONFIG$configJson';
      await publishCommand(command);
      _log('Configuración MQTT enviada al ESP32: $command');
    } catch (e) {
      _log('Error enviando configuración MQTT al ESP32: $e');
      rethrow;
    }
  }

  /// Envía configuración completa al ESP32 con confirmación
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
        _log('Intento $attempt/$maxRetries de enviar configuración al ESP32');

        // Crear JSON abreviado para configuración
        final configJson = _createConfigJson(
          broker: broker,
          port: port,
          tankFullThreshold: tankFullThreshold,
          voltageLowThreshold: voltageLowThreshold,
          humidityLowThreshold: humidityLowThreshold,
          tankFullEnabled: tankFullEnabled,
          voltageLowEnabled: voltageLowEnabled,
          humidityLowEnabled: humidityLowEnabled,
          tankCapacity: tankCapacity,
          isCalibrated: isCalibrated,
          ultrasonicOffset: ultrasonicOffset,
          controlDeadband: controlDeadband,
          controlMinOff: controlMinOff,
          controlMaxOn: controlMaxOn,
          controlSampling: controlSampling,
          controlAlpha: controlAlpha,
          maxCompressorTemp: maxCompressorTemp,
          displayTimeoutMinutes: displayTimeoutMinutes,
        );

        final fullConfigJson = jsonEncode(configJson);
        _log(
            'JSON abreviado creado - Longitud: ${fullConfigJson.length} caracteres');

        // Enviar configuración en partes para evitar truncamiento
        await _sendConfigInParts(configJson);

        _log(
            'Configuración enviada al ESP32 (intento $attempt). Esperando confirmación...');

        // Esperar confirmación del ESP32
        final ackReceived = await _waitForConfigAck(timeout);
        if (ackReceived) {
          _log('Configuración aplicada exitosamente en ESP32');
          return;
        } else {
          _log('No se recibió confirmación del ESP32 en ${timeout.inSeconds}s');
          if (attempt == maxRetries) {
            throw Exception(
                'ESP32 no confirmó recepción de configuración después de $maxRetries intentos');
          }
        }

        if (attempt < maxRetries) {
          await Future.delayed(Duration(seconds: 2));
        }
      } catch (e) {
        _log('Error en intento $attempt: $e');
        if (attempt == maxRetries) {
          rethrow;
        }
        await Future.delayed(Duration(seconds: 1));
      }
    }
  }

  /// Crea el JSON de configuración abreviado
  Map<String, dynamic> _createConfigJson({
    required String broker,
    required int port,
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
  }) {
    String formatValue(dynamic value) {
      if (value is double) {
        return value.toStringAsFixed(2);
      }
      return value.toString();
    }

    return {
      'mqtt': {
        'b': broker,
        'p': port,
      },
      'alerts': {
        'tf': tankFullEnabled,
        'tfv': formatValue(tankFullThreshold.toInt()),
        'vl': voltageLowEnabled,
        'vlv': formatValue(voltageLowThreshold.toInt()),
        'hl': humidityLowEnabled,
        'hlv': formatValue(humidityLowThreshold.toInt()),
      },
      'control': {
        'db': formatValue(controlDeadband),
        'mof': controlMinOff,
        'mon': controlMaxOn,
        'smp': controlSampling,
        'alp': formatValue(controlAlpha),
        'mt': formatValue(maxCompressorTemp.toInt()),
        'dt': displayTimeoutMinutes * 60, // en segundos
      },
      'tank': {
        'cap': formatValue(tankCapacity),
        'cal': isCalibrated,
        'off': formatValue(ultrasonicOffset),
      },
    };
  }

  /// Envía la configuración en partes fragmentadas
  Future<void> _sendConfigInParts(Map<String, dynamic> configJson) async {
    _log('Enviando configuración en partes fragmentadas...');

    // Parte 1: MQTT
    final part1 = 'update_config_part1${jsonEncode(configJson['mqtt'])}';
    await _publishPart(part1, 'Parte 1 MQTT');

    // Parte 2: Alertas
    final part2 = 'update_config_part2${jsonEncode(configJson['alerts'])}';
    await _publishPart(part2, 'Parte 2 Alertas');

    // Parte 3: Control
    final part3 = 'update_config_part3${jsonEncode(configJson['control'])}';
    await _publishPart(part3, 'Parte 3 Control');

    // Parte 4: Tanque
    final part4 = 'update_config_part4${jsonEncode(configJson['tank'])}';
    await _publishPart(part4, 'Parte 4 Tanque');

    // Comando de ensamblaje
    final finalCmd = 'update_config_assemble';
    await _publishPart(finalCmd, 'Comando ensamblaje');
  }

  /// Publica una parte de la configuración
  Future<void> _publishPart(String command, String description) async {
    _log('$description: "$command" (${command.length} chars)');

    final builder = MqttClientPayloadBuilder();
    builder.addString(command);
    client!.publishMessage(
        'dropster/control', MqttQos.atLeastOnce, builder.payload!);

    await Future.delayed(const Duration(milliseconds: 300));
  }

  /// Espera confirmación de configuración del ESP32
  Future<bool> _waitForConfigAck(Duration timeout) async {
    final completer = Completer<bool>();
    Timer? timer;

    late StreamSubscription subscription;

    subscription = client!.updates!
        .listen((List<MqttReceivedMessage<MqttMessage>> messages) {
      for (final message in messages) {
        final topic = message.topic;
        if (topic == 'dropster/status') {
          final payload = MqttPublishPayload.bytesToStringAsString(
              (message.payload as MqttPublishMessage).payload.message);

          try {
            final jsonData = jsonDecode(payload);
            if (jsonData is Map<String, dynamic> &&
                jsonData['type'] == 'config_ack' &&
                jsonData['status'] == 'success') {
              _log('Confirmación recibida del ESP32: $payload');
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

    timer = Timer(timeout, () {
      _log('Timeout esperando confirmación del ESP32');
      completer.complete(false);
      subscription.cancel();
    });

    return completer.future;
  }

  /// Verifica si el cliente está conectado
  bool get isConnected =>
      client?.connectionStatus?.state == MqttConnectionState.connected;
}

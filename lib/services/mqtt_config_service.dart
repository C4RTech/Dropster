import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'singleton_mqtt_service.dart';

/// Servicio para gestión avanzada de configuración MQTT
class MqttConfigService {
  static const String _configBoxName = 'mqtt_config';
  static const String _lastUpdatedKey = 'lastUpdated';

  /// Configuración por defecto
  static const Map<String, dynamic> _defaultConfig = {
    'broker': 'test.mosquitto.org',
    'port': 1883,
    'topic': 'dropster/data',
    'username': '',
    'password': '',
    'keepAlive': 60,
    'cleanSession': true,
  };

  /// Cargar configuración MQTT desde Hive
  static Future<Map<String, dynamic>> loadConfig() async {
    try {
      if (!Hive.isBoxOpen(_configBoxName)) {
        await Hive.openBox(_configBoxName);
      }

      final box = Hive.box(_configBoxName);
      final config = Map<String, dynamic>.from(_defaultConfig);

      // Cargar valores guardados
      for (final key in config.keys) {
        final value = box.get(key);
        if (value != null) {
          config[key] = value;
        }
      }

      // Cargar timestamp de última actualización
      config[_lastUpdatedKey] = box.get(_lastUpdatedKey, defaultValue: 0);

      return config;
    } catch (e) {
      debugPrint('[MQTT_CONFIG] Error cargando configuración: $e');
      return Map<String, dynamic>.from(_defaultConfig);
    }
  }

  /// Guardar configuración MQTT en Hive
  static Future<bool> saveConfig(Map<String, dynamic> config) async {
    try {
      if (!Hive.isBoxOpen(_configBoxName)) {
        await Hive.openBox(_configBoxName);
      }

      final box = Hive.box(_configBoxName);

      // Validar configuración
      if (!_validateConfig(config)) {
        debugPrint('[MQTT_CONFIG] Configuración inválida');
        return false;
      }

      // Guardar cada campo
      for (final entry in config.entries) {
        if (entry.key != _lastUpdatedKey) {
          await box.put(entry.key, entry.value);
        }
      }

      // Guardar timestamp
      await box.put(_lastUpdatedKey, DateTime.now().millisecondsSinceEpoch);

      debugPrint('[MQTT_CONFIG] ✅ Configuración guardada exitosamente');
      return true;
    } catch (e) {
      debugPrint('[MQTT_CONFIG] Error guardando configuración: $e');
      return false;
    }
  }

  /// Validar configuración MQTT
  static bool _validateConfig(Map<String, dynamic> config) {
    // Validar broker
    final broker = config['broker']?.toString();
    if (broker == null || broker.isEmpty) {
      debugPrint('[MQTT_CONFIG] Broker inválido');
      return false;
    }

    // Validar puerto
    final port = config['port'];
    if (port is! int || port < 1 || port > 65535) {
      debugPrint('[MQTT_CONFIG] Puerto inválido: $port');
      return false;
    }

    // Validar tópico
    final topic = config['topic']?.toString();
    if (topic == null || topic.isEmpty) {
      debugPrint('[MQTT_CONFIG] Tópico inválido');
      return false;
    }

    // Validar keep alive
    final keepAlive = config['keepAlive'];
    if (keepAlive is! int || keepAlive < 10 || keepAlive > 300) {
      debugPrint('[MQTT_CONFIG] Keep alive inválido: $keepAlive');
      return false;
    }

    return true;
  }

  /// Actualizar configuración MQTT y reconectar
  static Future<bool> updateConfigAndReconnect(
      Map<String, dynamic> newConfig) async {
    try {
      // Guardar nueva configuración
      final saved = await saveConfig(newConfig);
      if (!saved) return false;

      // Reconectar con nueva configuración
      await SingletonMqttService()
          .mqttClientService
          .reconnectWithNewConfig(SingletonMqttService().mqttService);

      debugPrint('[MQTT_CONFIG] ✅ Configuración actualizada y reconectado');
      return true;
    } catch (e) {
      debugPrint('[MQTT_CONFIG] Error actualizando configuración: $e');
      return false;
    }
  }

  /// Obtener configuración actual
  static Future<Map<String, dynamic>> getCurrentConfig() async {
    return await loadConfig();
  }

  /// Resetear a configuración por defecto
  static Future<bool> resetToDefault() async {
    return await updateConfigAndReconnect(_defaultConfig);
  }

  /// Verificar si la configuración ha cambiado
  static Future<bool> hasConfigChanged(Map<String, dynamic> newConfig) async {
    final currentConfig = await loadConfig();

    for (final key in _defaultConfig.keys) {
      if (currentConfig[key] != newConfig[key]) {
        return true;
      }
    }

    return false;
  }

  /// Exportar configuración como JSON
  static Future<String> exportConfig() async {
    final config = await loadConfig();
    return jsonEncode(config);
  }

  /// Importar configuración desde JSON
  static Future<bool> importConfig(String jsonConfig) async {
    try {
      final config = Map<String, dynamic>.from(jsonDecode(jsonConfig));
      return await updateConfigAndReconnect(config);
    } catch (e) {
      debugPrint('[MQTT_CONFIG] Error importando configuración: $e');
      return false;
    }
  }

  /// Obtener información de conexión
  static Future<Map<String, dynamic>> getConnectionInfo() async {
    final config = await loadConfig();
    final mqttService = SingletonMqttService().mqttClientService;

    return {
      'broker': config['broker'],
      'port': config['port'],
      'topic': config['topic'],
      'isConnected': mqttService.isConnected,
      'lastUpdated': config[_lastUpdatedKey],
      'connectionStatus':
          mqttService.isConnected ? 'Conectado' : 'Desconectado',
    };
  }

  /// Probar conexión con configuración actual
  static Future<bool> testConnection() async {
    try {
      final mqttService = SingletonMqttService().mqttClientService;

      if (mqttService.isConnected) {
        // Si ya está conectado, publicar un mensaje de prueba
        await mqttService.publishCommand('TEST_CONNECTION');
        return true;
      } else {
        // Intentar conectar
        await mqttService.connect(SingletonMqttService().mqttService);
        return mqttService.isConnected;
      }
    } catch (e) {
      debugPrint('[MQTT_CONFIG] Error probando conexión: $e');
      return false;
    }
  }

  /// Obtener brokers recomendados
  static List<Map<String, dynamic>> getRecommendedBrokers() {
    return [
      {
        'name': 'Mosquitto (Público)',
        'broker': 'test.mosquitto.org',
        'port': 1883,
        'description': 'Broker público para pruebas',
        'secure': false,
      },
      {
        'name': 'EMQX (Público)',
        'broker': 'broker.emqx.io',
        'port': 1883,
        'description': 'Broker público confiable',
        'secure': false,
      },
      {
        'name': 'HiveMQ (Público)',
        'broker': 'broker.hivemq.com',
        'port': 1883,
        'description': 'Broker público para desarrollo',
        'secure': false,
      },
      {
        'name': 'Local (192.168.1.100)',
        'broker': '192.168.1.100',
        'port': 1883,
        'description': 'Broker local en red',
        'secure': false,
      },
    ];
  }
}

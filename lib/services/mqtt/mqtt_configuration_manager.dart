import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Gestiona la configuración MQTT: broker, puerto, tópicos, credenciales
class MqttConfigurationManager {
  // Configuración dinámica del broker MQTT
  String broker = "test.mosquitto.org";
  int port = 1883;
  String topic = "dropster/data";
  bool useTls = false;
  String mqttUser = '';
  String mqttPass = '';

  final FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  /// Función helper para logs condicionales
  void _log(String message) {
    if (kDebugMode) {
      debugPrint('[MQTT-CONFIG] $message');
    }
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

      _log('Configuración cargada: $broker:$port, topic: $topic');
    } catch (e) {
      _log('Error cargando configuración MQTT: $e');
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
      _log('Credenciales guardadas en almacenamiento seguro');
    } catch (e) {
      _log('Error guardando credenciales seguras: $e');
    }
  }

  /// Actualiza la configuración del broker
  Future<void> updateBrokerConfig(
      String newBroker, int newPort, String newTopic, bool newUseTls) async {
    broker = newBroker;
    port = newPort;
    topic = newTopic;
    useTls = newUseTls;

    try {
      if (!Hive.isBoxOpen('settings')) {
        await Hive.openBox('settings');
      }

      final settingsBox = Hive.box('settings');
      await settingsBox.put('mqttBroker', newBroker);
      await settingsBox.put('mqttPort', newPort);
      await settingsBox.put('mqttTopic', newTopic);
      await settingsBox.put('mqttUseTls', newUseTls);

      _log('Configuración del broker actualizada: $newBroker:$newPort');
    } catch (e) {
      _log('Error guardando configuración del broker: $e');
    }
  }

  /// Obtiene la configuración actual como mapa
  Map<String, dynamic> getCurrentConfig() {
    return {
      'broker': broker,
      'port': port,
      'topic': topic,
      'useTls': useTls,
      'hasCredentials': mqttUser.isNotEmpty,
    };
  }

  /// Valida que la configuración sea correcta
  bool validateConfig() {
    if (broker.isEmpty) return false;
    if (port <= 0 || port > 65535) return false;
    if (topic.isEmpty) return false;
    return true;
  }
}

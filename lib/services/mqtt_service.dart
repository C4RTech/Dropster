import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'mqtt_hive.dart';

/// Servicio encargado de la comunicación MQTT con el broker y de recibir los datos de energía.
/// Se encarga de conectar, suscribirse al tópico y pasar los datos recibidos a MqttHiveService.
class MqttService {
  // Configuración del broker y tópico MQTT
  final String broker = "test.mosquitto.org";
  final int port = 1883;
  final String topic = "esp3209/energy_data/data";

  MqttServerClient? client;

  /// Devuelve true si el cliente está conectado al broker
  bool get isConnected => client?.connectionStatus?.state == MqttConnectionState.connected;

  /// Conecta al broker MQTT, se suscribe al tópico y configura el listener para los mensajes.
  Future<void> connect(MqttHiveService hiveService) async {
    if (client != null && isConnected) return;

    client = MqttServerClient(broker, '');
    client!.port = port;
    client!.logging(on: false);
    client!.keepAlivePeriod = 20;

    client!.connectionMessage = MqttConnectMessage()
        .withClientIdentifier('flutterClient_${DateTime.now().millisecondsSinceEpoch}')
        .startClean();

    await client!.connect();

    // Listener para mensajes recibidos en cualquier tópico suscrito
    client!.updates?.listen((List<MqttReceivedMessage<MqttMessage>> c) {
      final msg = c[0].payload as MqttPublishMessage;
      final topicReceived = c[0].topic;
      final payload = MqttPublishPayload.bytesToStringAsString(msg.payload.message);

      // Si el mensaje es del tópico esperado, lo procesa y guarda
      if (topicReceived == topic) {
        hiveService.onMqttDataReceived(payload);
      }
    });

    // Se suscribe al tópico de datos de energía
    client!.subscribe(topic, MqttQos.atMostOnce);
  }

  /// Desconecta el cliente del broker MQTT y limpia el objeto cliente.
  void disconnect() {
    client?.disconnect();
    client = null;
  }
}
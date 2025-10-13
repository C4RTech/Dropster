import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../services/mqtt_hive.dart';
import '../services/singleton_mqtt_service.dart';

/// Pantalla de conectividad: permite conectar por MQTT, muestra estado de conexión.
class ConnectivityScreen extends StatefulWidget {
  @override
  _ConnectivityScreenState createState() => _ConnectivityScreenState();
}

class _ConnectivityScreenState extends State<ConnectivityScreen> {
  bool isConnecting = false;
  late final ValueNotifier<bool> connectionNotifier;

  // Configuración MQTT guardada
  String savedMqttBroker = 'test.mosquitto.org';
  int savedMqttPort = 1883;
  String savedMqttTopic = 'dropster/data';

  @override
  void initState() {
    super.initState();
    connectionNotifier = SingletonMqttService().connectionNotifier;
    _loadSavedMqttConfig();
  }

  Future<void> _loadSavedMqttConfig() async {
    try {
      if (!Hive.isBoxOpen('settings')) {
        await Hive.openBox('settings');
      }
      final settingsBox = Hive.box('settings');
      setState(() {
        savedMqttBroker =
            settingsBox.get('mqttBroker', defaultValue: 'test.mosquitto.org');
        savedMqttPort = settingsBox.get('mqttPort', defaultValue: 1883);
        savedMqttTopic =
            settingsBox.get('mqttTopic', defaultValue: 'dropster/data');
      });
    } catch (e) {
      print('[CONNECTIVITY] Error cargando configuración MQTT: $e');
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _connectMQTT() async {
    setState(() {
      isConnecting = true;
    });
    try {
      await SingletonMqttService().connect();
      print('[UI DEBUG] Conexión MQTT exitosa desde pantalla de conectividad');
    } catch (e) {
      print(
          '[UI DEBUG] Error al conectar MQTT desde pantalla de conectividad: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error de conexión: $e')),
      );
    }
    setState(() {
      isConnecting = false;
    });
  }

  Future<void> _disconnectMQTT() async {
    await SingletonMqttService().disconnect();
    setState(() {});
  }

  Future<void> _sendCommand(String command) async {
    try {
      await SingletonMqttService().mqttClientService.publishCommand(command);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Comando "$command" enviado correctamente'),
          backgroundColor: Colors.green,
        ),
      );
      print('[UI DEBUG] Comando enviado: $command');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error enviando comando: $e'),
          backgroundColor: Colors.red,
        ),
      );
      print('[UI DEBUG] Error enviando comando $command: $e');
    }
  }

  /// Verifica si tanto la app como el ESP32 están conectados al broker
  bool _isFullyConnected() {
    // La app debe estar conectada al broker
    if (!SingletonMqttService().mqttConnected) {
      return false;
    }

    // El ESP32 debe haber enviado datos recientemente (últimos 30 segundos)
    final stats = SingletonMqttService().mqttClientService.getConnectionStats();
    final lastMessageTime = stats['lastMessageTime'];
    if (lastMessageTime == null) {
      return false;
    }

    final lastMessage = DateTime.parse(lastMessageTime);
    final now = DateTime.now();
    final timeSinceLastMessage = now.difference(lastMessage).inSeconds;

    // Consideramos que el ESP32 está conectado si envió datos en los últimos 30 segundos
    return timeSinceLastMessage <= 30;
  }

  Widget _buildNetworkInfo(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: Colors.white70,
              fontWeight: FontWeight.w500,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorPrimary = Theme.of(context).colorScheme.primary;
    final colorAccent = Theme.of(context).colorScheme.secondary;
    return Scaffold(
      appBar: AppBar(
        title: Text('Conectividad'),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: () async {
              await _loadSavedMqttConfig(); // Recarga configuración MQTT
              setState(() {}); // Refresca la pantalla
            },
            tooltip: 'Refrescar configuración',
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Franja horizontal de estado de conexión
          ValueListenableBuilder<bool>(
            valueListenable: connectionNotifier,
            builder: (context, isConnected, child) {
              final fullyConnected = _isFullyConnected();
              return Container(
                width: double.infinity,
                color: fullyConnected
                    ? Color(0xFF2E7D32)
                    : (isConnected ? Color(0xFFFFA000) : Color(0xFF0C434A)),
                padding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                child: Row(
                  children: [
                    Icon(
                        fullyConnected
                            ? Icons.wifi
                            : (isConnected ? Icons.wifi_off : Icons.wifi_off),
                        color: colorAccent),
                    SizedBox(width: 8),
                    Text(
                      fullyConnected
                          ? 'Conectado (App + ESP32)'
                          : (isConnected
                              ? 'Conectado (Solo App)'
                              : 'Sin conexión'),
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 2,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 10, horizontal: 12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.wifi, color: colorAccent),
                              SizedBox(width: 8),
                              Text(
                                'Conexión MQTT',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 18),
                              ),
                            ],
                          ),
                          SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Expanded(
                                child: ValueListenableBuilder<bool>(
                                  valueListenable: connectionNotifier,
                                  builder: (context, isConnected, child) {
                                    return ElevatedButton(
                                      onPressed: isConnected || isConnecting
                                          ? null
                                          : _connectMQTT,
                                      child: isConnecting
                                          ? CircularProgressIndicator(
                                              color: Colors.white)
                                          : Text('Conectar MQTT'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: colorAccent,
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(20)),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              SizedBox(width: 8),
                              Expanded(
                                child: ValueListenableBuilder<bool>(
                                  valueListenable: connectionNotifier,
                                  builder: (context, isConnected, child) {
                                    return ElevatedButton(
                                      onPressed:
                                          isConnected ? _disconnectMQTT : null,
                                      child: Text('Desconectar'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.grey,
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(20)),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: 24),
                  Card(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.router, color: colorAccent, size: 28),
                              SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Información de Red y Conexión',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                    SizedBox(height: 12),
                                    _buildNetworkInfo(
                                        'Broker MQTT', savedMqttBroker),
                                    _buildNetworkInfo('Puerto MQTT',
                                        savedMqttPort.toString()),
                                    _buildNetworkInfo(
                                        'Tópico MQTT', savedMqttTopic),
                                    _buildNetworkInfo(
                                        'Estado',
                                        _isFullyConnected()
                                            ? 'Conectado (App + ESP32)'
                                            : SingletonMqttService()
                                                    .mqttConnected
                                                ? 'Conectado (Solo App)'
                                                : 'Desconectado'),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Colores de la app (centralizados)
class AppColors {
  static const primary = Color(0xFF1D347A);
  static const green = Colors.green;
  static const red = Colors.red;
}

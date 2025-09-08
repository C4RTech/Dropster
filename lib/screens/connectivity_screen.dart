import 'dart:async';
import 'package:flutter/material.dart';
import '../services/mqtt_hive.dart';
import '../services/singleton_mqtt_service.dart';

/// Pantalla de conectividad: permite conectar por MQTT o Bluetooth, muestra estado, y permite borrar datos.
class ConnectivityScreen extends StatefulWidget {
  @override
  _ConnectivityScreenState createState() => _ConnectivityScreenState();
}

class _ConnectivityScreenState extends State<ConnectivityScreen> {
  bool isSavingEnabled = MqttHiveService.isSavingEnabled();
  bool isConnecting = false;
  late final ValueNotifier<bool> connectionNotifier;

  @override
  void initState() {
    super.initState();
    connectionNotifier = SingletonMqttService().connectionNotifier;
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _toggleSaving(bool value) {
    setState(() {
      isSavingEnabled = value;
      MqttHiveService.toggleSaving(value);
    });
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

  Future<void> _clearAllData() async {
    await MqttHiveService.clearAllData();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Todos los datos han sido eliminados.')),
    );
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
            onPressed: () {
              setState(() {}); // Refresca la pantalla
            },
            tooltip: 'Refrescar',
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
              return Container(
                width: double.infinity,
                color: isConnected ? Color(0xFF2E7D32) : Color(0xFF0C434A),
                padding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                child: Row(
                  children: [
                    Icon(isConnected ? Icons.wifi : Icons.wifi_off,
                        color: colorAccent),
                    SizedBox(width: 8),
                    Text(
                      isConnected ? 'Conectado a MQTT' : 'Sin conexión',
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
                  const SizedBox(height: 24),

                  // Nueva sección de control del ESP32
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
                              Icon(Icons.control_camera,
                                  color: colorAccent, size: 28),
                              SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Control del ESP32',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                    SizedBox(height: 8),
                                    Text(
                                      'Envía comandos al dispositivo ESP32',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.white70,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 24),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () => _sendCommand('ON'),
                                  icon: Icon(Icons.power),
                                  label: Text('ENCENDER'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green,
                                    foregroundColor: Colors.white,
                                    padding: EdgeInsets.symmetric(vertical: 12),
                                  ),
                                ),
                              ),
                              SizedBox(width: 8),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () => _sendCommand('OFF'),
                                  icon: Icon(Icons.power_off),
                                  label: Text('APAGAR'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red,
                                    foregroundColor: Colors.white,
                                    padding: EdgeInsets.symmetric(vertical: 12),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () => _sendCommand('GET_STATUS'),
                                  icon: Icon(Icons.info),
                                  label: Text('ESTADO'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: colorAccent,
                                    foregroundColor: Colors.white,
                                    padding: EdgeInsets.symmetric(vertical: 12),
                                  ),
                                ),
                              ),
                              SizedBox(width: 8),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () => _sendCommand('GET_DATA'),
                                  icon: Icon(Icons.data_usage),
                                  label: Text('DATOS'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: colorPrimary,
                                    foregroundColor: Colors.white,
                                    padding: EdgeInsets.symmetric(vertical: 12),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
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
                              Icon(Icons.settings,
                                  color: colorAccent, size: 28),
                              SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Configuración de Datos',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                    SizedBox(height: 12),
                                    Text(
                                      'Guardar datos automáticamente',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.white,
                                      ),
                                    ),
                                    Text(
                                      'Almacena los datos recibidos en el dispositivo',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.white70,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Switch(
                                value: isSavingEnabled,
                                onChanged: _toggleSaving,
                                activeColor: colorAccent,
                              ),
                            ],
                          ),
                          const Divider(height: 28),
                          ListTile(
                            leading:
                                Icon(Icons.delete_sweep, color: colorAccent),
                            title: const Text('Borrar todos los datos'),
                            subtitle: const Text(
                                'Elimina todos los datos históricos almacenados'),
                            onTap: _clearAllData,
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

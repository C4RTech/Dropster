import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import '../services/singleton_mqtt_service.dart';
import '../services/mqtt_hive.dart';
import '../services/mqtt_service.dart';
import '../widgets/professional_water_drop.dart';
import 'dart:async';

/// Pantalla principal que muestra datos eléctricos en tiempo real,
/// permite configurar valores nominales y detecta anomalías.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  // Valores nominales por defecto
  double nominalVoltage = 110.0;
  double nominalCurrent = 10.0;
  final voltageController = TextEditingController();
  final currentController = TextEditingController();

  // Acceso rápido al "notifier" global con los datos en tiempo real
  ValueNotifier<Map<String, dynamic>> get globalNotifier =>
      SingletonMqttService().notifier;

  // Acceso al notifier de estado de conexión MQTT
  ValueNotifier<bool> get connectionNotifier =>
      SingletonMqttService().connectionNotifier;

  // Control de anomalías detectadas para evitar registros duplicados
  Map<String, bool> _anomalyActive = {};
  bool _firstLoadDone = false;

  late AnimationController _controller;
  late Animation<double> _animation;

  // Nivel del tanque real desde ESP32
  double tankLevel = 0.0;

  // Control del sistema AWG
  bool isSystemOn = false;
  final MqttService _mqttService = MqttService();

  /// Obtiene el valor de la batería desde el notifier global
  double? get batteryValue {
    final bat = globalNotifier.value['battery'];
    if (bat is double) return bat;
    if (bat is int) return bat.toDouble();
    if (bat is String) return double.tryParse(bat);
    return null;
  }

  /// Interpreta el estado textual de la batería según su valor
  String get batteryStatus {
    final value = batteryValue;
    if (value == null) return "No disponible";
    if (value >= 2.9) return "Cargada/Conectado";
    if (value > 2.5) return "En buen estado";
    return "Nivel bajo";
  }

  /// Devuelve el tipo de fuente de datos ("BLE", "MQTT", o vacío)
  String get sourceType {
    final source =
        (globalNotifier.value['source'] ?? '').toString().toUpperCase();
    if (source == "BLE") return "BLE";
    if (source == "MQTT") return "MQTT";
    return "";
  }

  @override
  void initState() {
    super.initState();
    _loadSettings(); // Carga los valores nominales almacenados
    _initLatestData(); // Carga los últimos datos guardados
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);

    // Escuchar datos MQTT para actualizar nivel de tanque real
    globalNotifier.addListener(() {
      final data = globalNotifier.value;
      print('[UI DEBUG] Notifier actualizado: ${data.keys}');

      // Obtener capacidad del tanque desde configuración
      final settingsBox = Hive.box('settings');
      final tankCapacity =
          settingsBox.get('tankCapacity', defaultValue: 1000.0);

      // Intentar diferentes nombres de clave para el agua almacenada
      double? aguaReal;
      if (data['aguaAlmacenada'] != null) {
        aguaReal = (data['aguaAlmacenada'] as num).toDouble();
      } else if (data['agua'] != null) {
        aguaReal = (data['agua'] as num).toDouble();
      } else if (data['waterStored'] != null) {
        aguaReal = (data['waterStored'] as num).toDouble();
      }

      if (aguaReal != null && aguaReal >= 0 && tankCapacity > 0) {
        // Calcular porcentaje basado en capacidad configurada
        final porcentaje = (aguaReal / tankCapacity).clamp(0.0, 1.0);
        setState(() {
          tankLevel = porcentaje;
          print(
              '[UI DEBUG] Nivel de tanque actualizado a ${(porcentaje * 100).toStringAsFixed(1)}% (agua: $aguaReal L de $tankCapacity L)');
        });
      } else {
        print(
            '[UI DEBUG] No se encontró dato de agua almacenada o capacidad inválida');
      }

      // Forzar actualización de la UI cuando llegan datos nuevos
      if (data.isNotEmpty && mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Carga los valores nominales de voltaje y corriente desde Hive.
  Future<void> _loadSettings() async {
    if (!Hive.isBoxOpen('settings')) {
      await Hive.openBox('settings');
    }
    final settingsBox = Hive.box('settings');
    nominalVoltage = settingsBox.get('nominalVoltage', defaultValue: 110.0);
    nominalCurrent = settingsBox.get('nominalCurrent', defaultValue: 10.0);
    voltageController.text = nominalVoltage.toStringAsFixed(1);
    currentController.text = nominalCurrent.toStringAsFixed(1);
    setState(() {});
  }

  /// Inicializa Hive y carga los últimos datos registrados, si existen.
  Future<void> _initLatestData() async {
    try {
      // Timeout de 5 segundos para evitar que se quede cargando indefinidamente
      await MqttHiveService.initHive().timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          print(
              '[INIT] Timeout inicializando Hive, continuando sin datos previos');
          return;
        },
      );

      final latest = await MqttHiveService.getLatestData().timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          print('[INIT] Timeout cargando datos previos, continuando sin datos');
          return null;
        },
      );

      if (latest != null && globalNotifier.value.isEmpty) {
        globalNotifier.value = {...latest};
        print('[INIT] Datos previos cargados exitosamente');
      } else {
        print('[INIT] No hay datos previos o ya hay datos en el notifier');
      }
    } catch (e) {
      print('[INIT] Error inicializando datos: $e');
    } finally {
      // Asegurar que siempre se complete la carga inicial
      if (mounted) {
        setState(() {
          _firstLoadDone = true;
        });
        print('[INIT] Carga inicial completada');
      }
    }
  }

  /// Detecta y guarda anomalías de voltaje, corriente y frecuencia en Hive.
  Future<void> _checkAndSaveAnomalies(Map<String, dynamic> data) async {
    final anomaliesBox = await Hive.openBox('anomalies');
    final now = DateTime.now().millisecondsSinceEpoch;

    // Verifica voltaje por fase
    for (var phase in ['a', 'b', 'c']) {
      final key = 'voltage_$phase';
      final voltage = double.tryParse(data[key]?.toString() ?? "");
      if (voltage == null) continue;
      final min = nominalVoltage * 0.98;
      final max = nominalVoltage * 1.02;
      final anomalyKey = 'voltage_$phase';
      if (voltage < min || voltage > max) {
        if (_anomalyActive[anomalyKey] != true) {
          await anomaliesBox.add({
            'description':
                'Voltaje ${phase.toUpperCase()} fuera de rango: ${voltage.toStringAsFixed(2)} V (límite ${min.toStringAsFixed(1)}-${max.toStringAsFixed(1)})',
            'timestamp': now,
            'type': 'voltage',
            'phase': phase,
            'value': voltage,
            'limitMin': min,
            'limitMax': max,
          });
          _anomalyActive[anomalyKey] = true;
        }
      } else {
        _anomalyActive[anomalyKey] = false;
      }
    }

    // Verifica corriente por fase
    for (var phase in ['a', 'b', 'c']) {
      final key = 'current_$phase';
      final current = double.tryParse(data[key]?.toString() ?? "");
      if (current == null) continue;
      final min = nominalCurrent * 0.7;
      final max = nominalCurrent * 1.3;
      final anomalyKey = 'current_$phase';
      if (current < min || current > max) {
        if (_anomalyActive[anomalyKey] != true) {
          await anomaliesBox.add({
            'description':
                'Corriente ${phase.toUpperCase()} fuera de rango: ${current.toStringAsFixed(2)} A (límite ${min.toStringAsFixed(1)}-${max.toStringAsFixed(1)})',
            'timestamp': now,
            'type': 'current',
            'phase': phase,
            'value': current,
            'limitMin': min,
            'limitMax': max,
          });
          _anomalyActive[anomalyKey] = true;
        }
      } else {
        _anomalyActive[anomalyKey] = false;
      }
    }

    // Verifica frecuencia
    final freq = double.tryParse(data['frequency']?.toString() ?? "");
    if (freq != null) {
      final anomalyKey = 'frequency';
      bool outOfRange =
          !((freq >= 59.9 && freq <= 60.1) || (freq >= 49.9 && freq <= 50.1));
      if (outOfRange) {
        if (_anomalyActive[anomalyKey] != true) {
          await anomaliesBox.add({
            'description':
                'Frecuencia fuera de rango: ${freq.toStringAsFixed(2)} Hz',
            'timestamp': now,
            'type': 'frequency',
            'value': freq,
            'limit': '49.9-50.1 Hz o 59.9-60.1 Hz',
          });
          _anomalyActive[anomalyKey] = true;
        }
      } else {
        _anomalyActive[anomalyKey] = false;
      }
    }

    // Verifica nivel del tanque
    double tankLevel = 0.0;
    final nivelStr = getField(data, 'nivel_tanque');
    if (nivelStr != '--') {
      tankLevel = double.tryParse(nivelStr) ?? 0.0;
      if (tankLevel > 1.0) tankLevel = tankLevel / 100.0;
      if (tankLevel > 1.0) tankLevel = 1.0;
      if (tankLevel < 0.0) tankLevel = 0.0;
    }
    // Si no existe la variable, intentar con 'nivelTanque'
    if (tankLevel == 0.0 && data['nivelTanque'] != null) {
      tankLevel = (data['nivelTanque'] as num).toDouble();
      if (tankLevel > 1.0) tankLevel = tankLevel / 100.0;
      if (tankLevel > 1.0) tankLevel = 1.0;
      if (tankLevel < 0.0) tankLevel = 0.0;
    }

    if (tankLevel > 0.0) {
      final anomalyKey = 'tank_level_low';
      const lowThreshold = 0.15; // 15% del tanque

      if (tankLevel <= lowThreshold) {
        if (_anomalyActive[anomalyKey] != true) {
          await anomaliesBox.add({
            'description':
                'Nivel del tanque bajo: ${(tankLevel * 100).toStringAsFixed(1)}% - Se recomienda no activar la bomba',
            'timestamp': now,
            'type': 'tank_level',
            'value': tankLevel,
            'limit': 'Mínimo 15%',
          });
          _anomalyActive[anomalyKey] = true;
        }
      } else {
        _anomalyActive[anomalyKey] = false;
      }
    }
  }

  /// Guarda los valores nominales actuales en Hive.
  Future<void> _saveSettings() async {
    final settingsBox = Hive.box('settings');
    await settingsBox.put('nominalVoltage', nominalVoltage);
    await settingsBox.put('nominalCurrent', nominalCurrent);
  }

  /// Devuelve el valor de un campo como string formateado
  String getField(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value == null) return '--';
    if (value is double) {
      // Formatear según el tipo de dato
      if (key.contains('energia')) {
        return value.toStringAsFixed(1); // Energía con 1 decimal
      } else if (key.contains('voltaje') || key.contains('corriente')) {
        return value.toStringAsFixed(2); // Voltaje/corriente con 2 decimales
      } else if (key.contains('temperatura') || key.contains('humedad')) {
        return value.toStringAsFixed(1); // Temperatura/humedad con 1 decimal
      }
      return value.toStringAsFixed(2); // Por defecto 2 decimales
    }
    return value.toString();
  }

  /// Color del borde del círculo según si el voltaje está en rango
  Color _getVoltageBorderColor(Map<String, dynamic> data, String voltageStr) {
    final v = double.tryParse(voltageStr);
    if (v == null) return Colors.grey;
    final min = nominalVoltage * 0.98;
    final max = nominalVoltage * 1.02;
    return (v >= min && v <= max) ? Colors.green : Colors.red;
  }

  /// Color del borde del círculo según si la corriente está en rango
  Color _getCurrentBorderColor(Map<String, dynamic> data, String key) {
    final val = double.tryParse(getField(data, key));
    if (val == null) return Colors.grey;
    final min = nominalCurrent * 0.7;
    final max = nominalCurrent * 1.3;
    return (val >= min && val <= max) ? Colors.green : Colors.red;
  }

  /// Color del borde del círculo según si la frecuencia está en rango
  Color _getFrequencyBorderColor(Map<String, dynamic> data, String freqStr) {
    final f = double.tryParse(freqStr);
    if (f == null) return Colors.grey;
    bool inRange = (f >= 59.9 && f <= 60.1) || (f >= 49.9 && f <= 50.1);
    return inRange ? Colors.green : Colors.red;
  }

  /// Tarjeta circular que muestra el estado de la batería
  Widget buildBatteryCircleCard() {
    // Solo muestra el estado textual
    Color borderColor;
    String status = batteryStatus;
    if (status == "Cargada/Conectado")
      borderColor = Colors.green;
    else if (status == "En buen estado")
      borderColor = Colors.amber;
    else if (status == "Nivel bajo")
      borderColor = Colors.red;
    else
      borderColor = Colors.grey;

    return Container(
      width: 100,
      height: 100,
      margin: const EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [Colors.white, Color(0xFFE0E0E0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: borderColor, width: 4),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade400,
            offset: const Offset(4, 4),
            blurRadius: 6,
            spreadRadius: 1,
          ),
          const BoxShadow(
            color: Colors.white,
            offset: Offset(-4, -4),
            blurRadius: 6,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.battery_full, color: borderColor, size: 36),
            const SizedBox(height: 4),
            Text(
              status,
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: borderColor),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  /// Tarjeta circular genérica para cualquier medición
  Widget buildCircleCard(String label, String value,
      {String unit = '', Color borderColor = const Color(0xFF1D347A)}) {
    return Container(
      width: 100,
      height: 100,
      margin: const EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [Colors.white, Color(0xFFE0E0E0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: borderColor, width: 4),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade400,
            offset: const Offset(4, 4),
            blurRadius: 6,
            spreadRadius: 1,
          ),
          const BoxShadow(
            color: Colors.white,
            offset: Offset(-4, -4),
            blurRadius: 6,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text('$value $unit',
                style: const TextStyle(fontSize: 14),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  /// Caja estilizada para mostrar la fecha y hora actual
  Widget _styledDateTimeBox(String dateStr, String timeStr) {
    return Container(
      height: 44,
      margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 0),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      constraints: const BoxConstraints(
        maxWidth: 360,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.10),
            blurRadius: 14,
            offset: const Offset(2, 2),
          ),
        ],
        border: Border.all(color: const Color(0xFF1D347A), width: 2),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.calendar_today_rounded,
              color: const Color(0xFF1D347A), size: 24),
          const SizedBox(width: 8),
          Text(
            dateStr,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 17,
              letterSpacing: 1,
              color: Color(0xFF1D347A),
            ),
          ),
          const SizedBox(width: 16),
          Icon(Icons.access_time_rounded, color: Color(0xFF1D347A), size: 24),
          const SizedBox(width: 8),
          Text(
            timeStr,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
              color: Color(0xFF1D347A),
            ),
          ),
        ],
      ),
    );
  }

  /// Caja estilizada para configurar valores nominales de voltaje y corriente
  Widget _styledNominalBox() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 18, horizontal: 24),
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.10),
            blurRadius: 14,
            offset: const Offset(2, 2),
          ),
        ],
        border: Border.all(color: const Color(0xFF1D347A), width: 2),
      ),
      child: Column(
        children: [
          const Text(
            'Configuración de Valores Nominales',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 17,
              color: Color(0xFF1D347A),
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Campo para voltaje nominal
              Column(
                children: [
                  SizedBox(
                    width: 120,
                    child: TextField(
                      controller: voltageController,
                      keyboardType:
                          TextInputType.numberWithOptions(decimal: true),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: Color(0xFF1D347A),
                      ),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFFEDF0F6),
                        focusedBorder: OutlineInputBorder(
                          borderSide: const BorderSide(
                              color: Color(0xFF1D347A), width: 2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderSide: const BorderSide(
                              color: Color(0xFFB5B5B5), width: 1.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 10),
                        isDense: true,
                      ),
                      onChanged: (val) {
                        final parsed = double.tryParse(val);
                        if (parsed != null) {
                          setState(() => nominalVoltage = parsed);
                          _saveSettings();
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Voltaje nominal (V)',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Color(0xFF1D347A)),
                  ),
                ],
              ),
              const SizedBox(width: 30),
              // Campo para corriente nominal
              Column(
                children: [
                  SizedBox(
                    width: 120,
                    child: TextField(
                      controller: currentController,
                      keyboardType:
                          TextInputType.numberWithOptions(decimal: true),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: Color(0xFF1D347A),
                      ),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFFEDF0F6),
                        focusedBorder: OutlineInputBorder(
                          borderSide: const BorderSide(
                              color: Color(0xFF1D347A), width: 2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderSide: const BorderSide(
                              color: Color(0xFFB5B5B5), width: 1.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 10),
                        isDense: true,
                      ),
                      onChanged: (val) {
                        final parsed = double.tryParse(val);
                        if (parsed != null) {
                          setState(() => nominalCurrent = parsed);
                          _saveSettings();
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Corriente nominal (A)',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Color(0xFF1D347A)),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDataCard(String title, String value, String unit, IconData icon,
      Color borderColor, Color textColor) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor, width: 2),
      ),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: borderColor, size: 32),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: textColor,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              '$value $unit',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: borderColor,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  void _toggleSystem() async {
    final command = isSystemOn ? "OFF" : "ON";
    await _mqttService.publishCommand(command);
    setState(() {
      isSystemOn = !isSystemOn;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorPrimary = Theme.of(context).colorScheme.primary;
    final colorAccent = Theme.of(context).colorScheme.secondary;
    final colorText = Theme.of(context).colorScheme.onBackground;

    // Obtener el nivel del tanque usando capacidad configurada
    double tankLevel = 0.0;
    final settingsBox = Hive.box('settings');
    final tankCapacity = settingsBox.get('tankCapacity', defaultValue: 1000.0);

    // Intentar obtener agua almacenada del ESP32
    final aguaAlmacenada = globalNotifier.value['aguaAlmacenada'];
    if (aguaAlmacenada != null && tankCapacity > 0) {
      final aguaLitros = (aguaAlmacenada as num).toDouble();
      tankLevel = (aguaLitros / tankCapacity).clamp(0.0, 1.0);
    }

    // Actualizar animación de la gota
    _controller.value = tankLevel;

    // Mostrar pantalla de carga solo por un tiempo limitado
    if (!_firstLoadDone) {
      // Forzar carga completada después de 10 segundos como respaldo
      Future.delayed(const Duration(seconds: 10), () {
        if (mounted && !_firstLoadDone) {
          setState(() {
            _firstLoadDone = true;
          });
          print('[INIT] Carga forzada completada después de timeout');
        }
      });

      return Scaffold(
        appBar: AppBar(
          title: const Text('Dropster'),
          backgroundColor: colorPrimary,
          foregroundColor: Colors.white,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: colorAccent),
              const SizedBox(height: 16),
              Text(
                'Cargando datos...',
                style: TextStyle(color: colorText),
              ),
              const SizedBox(height: 8),
              Text(
                'Si tarda demasiado, la app se cargará automáticamente',
                style:
                    TextStyle(color: colorText.withOpacity(0.7), fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset('lib/assets/images/Dropster_simbolo.png', height: 32),
            const SizedBox(width: 8),
            const Text('Dropster'),
          ],
        ),
        backgroundColor: colorPrimary,
        foregroundColor: Colors.white,
        actions: [
          // Indicador de estado de conexión MQTT
          ValueListenableBuilder<bool>(
            valueListenable: connectionNotifier,
            builder: (context, isConnected, child) {
              return Container(
                margin: const EdgeInsets.only(right: 16),
                child: Row(
                  children: [
                    Icon(
                      isConnected ? Icons.wifi : Icons.wifi_off,
                      color: isConnected ? Colors.green : Colors.red,
                      size: 20,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isConnected ? 'MQTT' : 'Sin conexión',
                      style: TextStyle(
                        color: isConnected ? Colors.green : Colors.red,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Indicador de estado de conexión
            if (globalNotifier.value.isEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.info_outline, color: Colors.orange, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Esperando conexión con ESP32...',
                      style: TextStyle(
                        color: Colors.orange,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

            // Gota animada en el centro sin fondo
            Center(
              child: Column(
                children: [
                  // Gota sin contenedor de fondo
                  ProfessionalWaterDrop(
                    value: tankLevel,
                    size: 140,
                    primaryColor: colorAccent,
                    secondaryColor: colorPrimary,
                    animationDuration: const Duration(milliseconds: 800),
                  ),
                  const SizedBox(height: 16),
                  // Nombre de la variable con estilo profesional
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          colorPrimary.withOpacity(0.1),
                          colorAccent.withOpacity(0.1),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: colorAccent.withOpacity(0.3),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.water_drop,
                              color: colorAccent,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Nivel del Tanque',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: colorText,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Porcentaje debajo del nombre
                        Text(
                          '${(tankLevel * 100).toStringAsFixed(1)}%',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: colorAccent,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // Botón de control ON/OFF
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              child: Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side:
                      BorderSide(color: colorAccent.withOpacity(0.3), width: 2),
                ),
                elevation: 8,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Icon(
                        isSystemOn ? Icons.power : Icons.power_off,
                        color: isSystemOn ? colorAccent : Colors.red,
                        size: 40,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          isSystemOn ? 'Sistema Encendido' : 'Sistema Apagado',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: colorText,
                          ),
                        ),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              isSystemOn ? Colors.red : colorAccent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 12),
                          elevation: 4,
                        ),
                        onPressed: _toggleSystem,
                        child: Text(
                          isSystemOn ? 'Apagar' : 'Encender',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Variables principales del sistema AWG (simplificadas)
            Wrap(
              spacing: 16,
              runSpacing: 16,
              alignment: WrapAlignment.center,
              children: [
                // === DATOS PRINCIPALES ===
                _miniDataCard(
                    'Temperatura ambiente',
                    getField(globalNotifier.value, 'temperaturaAmbiente'),
                    '°C',
                    Icons.thermostat,
                    colorAccent,
                    colorText),
                _miniDataCard(
                    'Humedad relativa',
                    getField(globalNotifier.value, 'humedadRelativa'),
                    '%',
                    Icons.water,
                    colorAccent,
                    colorText),
                _miniDataCard(
                    'Humedad absoluta',
                    getField(globalNotifier.value, 'humedadAbsoluta'),
                    'g/m³',
                    Icons.grain,
                    colorAccent,
                    colorText),
                _miniDataCard(
                    'Energía',
                    getField(globalNotifier.value, 'energia'),
                    'kWh',
                    Icons.flash_on,
                    colorAccent,
                    colorText),
              ],
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _miniDataCard(String title, String value, String unit, IconData icon,
      Color borderColor, Color textColor) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: borderColor.withOpacity(0.6), width: 2),
      ),
      elevation: 6,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: borderColor, size: 36),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                  fontSize: 15,
                  color: textColor.withOpacity(0.9),
                  fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              '$value$unit',
              style: TextStyle(
                  fontSize: 22,
                  color: borderColor,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

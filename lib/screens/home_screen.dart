import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../services/singleton_mqtt_service.dart';
import '../services/mqtt_hive.dart';
import '../services/mqtt_service.dart';
import '../widgets/dropster_animated_symbol.dart';
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
  Timer? _debounceTimer;

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
  // Map<String, bool> _anomalyActive = {}; // Removido: no se utiliza
  bool _firstLoadDone = false;

  late AnimationController _controller;

  // Nivel del tanque real desde ESP32
  double tankLevel = 0.0;

  // Control del sistema AWG - ahora basado en estado real del ESP32
  int compressorState = 0; // 0 = OFF, 1 = ON - Estado real del ESP32
  int ventilatorState = 0; // 0 = OFF, 1 = ON
  int compressorFanState = 0; // 0 = OFF, 1 = ON - Ventilador del compresor
  int pumpState = 0; // 0 = OFF, 1 = ON
  String operationMode =
      'MANUAL'; // 'MANUAL' o 'AUTO' - Iniciar en MANUAL para que los controles funcionen
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

    // Función para procesar datos del notifier
    void _processNotifierData() {
      final data = globalNotifier.value;
      print('[UI DEBUG] Procesando datos del notifier: ${data.keys}');

      // Log específico para energia
      if (data.containsKey('energia')) {
        print(
            '[UI ENERGIA DEBUG] ✅ Energía en notifier: ${data['energia']} (tipo: ${data['energia'].runtimeType})');
      } else {
        print('[UI ENERGIA DEBUG] ⚠️ Energía NO presente en notifier');
        print('[UI ENERGIA DEBUG] Datos actuales: $data');
      }

      // Actualizar estado del compresor desde MQTT
      final newCompressorState = data['cs'] ?? 0;
      if (newCompressorState != compressorState && mounted) {
        compressorState = newCompressorState;
        _debouncedSetState();
      }

      // Actualizar estado del ventilador desde MQTT
      final newVentilatorState = data['vs'] ?? 0;
      if (newVentilatorState != ventilatorState && mounted) {
        ventilatorState = newVentilatorState;
        print(
            '[UI DEBUG] Estado del ventilador actualizado a: $ventilatorState');
        _debouncedSetState();
      }

      // Actualizar estado de la bomba desde MQTT
      final newPumpState = data['ps'] ?? 0;
      if (newPumpState != pumpState && mounted) {
        pumpState = newPumpState;
        print('[UI DEBUG] Estado de la bomba actualizado a: $pumpState');
        _debouncedSetState();
      }

      // Actualizar estado del ventilador del compresor desde MQTT
      final newCompressorFanState = data['cfs'] ?? 0;
      if (newCompressorFanState != compressorFanState && mounted) {
        compressorFanState = newCompressorFanState;
        print(
            '[UI DEBUG] Estado del ventilador del compresor actualizado a: $compressorFanState');
        _debouncedSetState();
      }

      // Actualizar modo de operación desde MQTT
      final newMode = data['mode'] ?? operationMode;
      if (newMode != operationMode && mounted) {
        operationMode = newMode;
        print('[UI DEBUG] Modo de operación actualizado a: $operationMode');
        _debouncedSetState();
      }

      // Mostrar diálogo de error de bomba si se recibe el mensaje
      if (data.containsKey('pump_error') &&
          data['pump_error'] == true &&
          mounted) {
        _showPumpErrorDialog();
      }

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
        if (mounted && tankLevel != porcentaje) {
          tankLevel = porcentaje;
          print(
              '[UI DEBUG] Nivel de tanque actualizado a ${(porcentaje * 100).toStringAsFixed(1)}% (agua: $aguaReal L de $tankCapacity L)');
          _debouncedSetState();
        }
      } else {
        print(
            '[UI DEBUG] No se encontró dato de agua almacenada o capacidad inválida');
      }
    }

    // Escuchar datos MQTT para actualizar nivel de tanque real
    globalNotifier.addListener(_processNotifierData);

    // Procesar datos iniciales inmediatamente
    _processNotifierData();
  }

  @override
  void dispose() {
    _controller.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _debouncedSetState() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 200), () {
      if (mounted) {
        setState(() {});
      }
    });
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

      if (latest != null) {
        // Solo cargar si el notifier está vacío o si no tiene datos de energía
        if (globalNotifier.value.isEmpty ||
            !globalNotifier.value.containsKey('energia')) {
          globalNotifier.value = {...latest};
          print('[INIT] Datos previos cargados exitosamente');
          print('[INIT] Datos cargados: ${latest.keys}');
        } else {
          print('[INIT] Notifier ya tiene datos, no se sobrescriben');
        }
      } else {
        print('[INIT] No hay datos previos en Hive');
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

  /// Devuelve el valor de un campo como string formateado
  String getField(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value == null) {
      if (key.contains('energia')) {
        print('[HOME ENERGIA DEBUG] ⚠️ Campo "energia" es null en datos');
        print('[HOME ENERGIA DEBUG] Claves disponibles: ${data.keys}');
        print(
            '[HOME ENERGIA DEBUG] Fuente de datos: ${data['source'] ?? 'desconocida'}');
        print('[HOME ENERGIA DEBUG] Todos los datos: $data');
        return '--';
      }
      return '--';
    }
    if (value is double) {
      if (key.contains('energia')) {
        // Energía ya viene en Wh desde ESP32, no necesita conversión
        print(
            '[HOME ENERGIA DEBUG] ✅ Energía recibida en UI: ${value}Wh (tipo: ${value.runtimeType})');

        // Para energía, usar más decimales si el valor es muy pequeño
        if (value < 1.0 && value > 0) {
          print(
              '[HOME ENERGIA DEBUG] Valor pequeño detectado: ${value}Wh, usando 3 decimales');
          return value.toStringAsFixed(3); // 3 decimales para valores pequeños
        } else {
          return value.toStringAsFixed(2); // 2 decimales para valores normales
        }
      }
      return value
          .toStringAsFixed(2); // Todos los demás valores con 2 decimales
    }
    return value.toString();
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

  void _toggleSystem() async {
    // Actualizar estado local optimistamente
    final newState = compressorState == 1 ? 0 : 1;
    setState(() {
      compressorState = newState;
    });

    // Enviar comando opuesto al estado actual
    final command = newState == 1 ? "ON" : "OFF";
    try {
      await SingletonMqttService().mqttClientService.publishCommand(command);
    } catch (e) {
      // Revertir estado si falla
      setState(() {
        compressorState = 1 - newState;
      });
      // Error ya se maneja en el servicio MQTT, no mostrar SnackBar
    }
  }

  void _toggleVentilator() async {
    // Actualizar estado local optimistamente
    final newState = ventilatorState == 1 ? 0 : 1;
    setState(() {
      ventilatorState = newState;
    });

    final command = newState == 1 ? "ONV" : "OFFV";
    try {
      await SingletonMqttService().mqttClientService.publishCommand(command);
    } catch (e) {
      // Revertir estado si falla
      setState(() {
        ventilatorState = 1 - newState;
      });
      // Error ya se maneja en el servicio MQTT, no mostrar SnackBar
    }
  }

  void _togglePump() async {
    // Actualizar estado local optimistamente
    final newState = pumpState == 1 ? 0 : 1;
    setState(() {
      pumpState = newState;
    });

    final command = newState == 1 ? "ONB" : "OFFB";
    try {
      await SingletonMqttService().mqttClientService.publishCommand(command);
    } catch (e) {
      // Revertir estado si falla
      setState(() {
        pumpState = 1 - newState;
      });
      // Error ya se maneja en el servicio MQTT, no mostrar SnackBar
    }
  }

  void _toggleCompressorFan() async {
    // Actualizar estado local optimistamente
    final newState = compressorFanState == 1 ? 0 : 1;
    setState(() {
      compressorFanState = newState;
    });

    final command = newState == 1 ? "ONCF" : "OFFCF";
    try {
      await SingletonMqttService().mqttClientService.publishCommand(command);
    } catch (e) {
      // No revertir estado, mantener el cambio local
      // Error ya se maneja en el servicio MQTT, no mostrar SnackBar
    }
  }

  void _toggleMode() async {
    final newMode = operationMode == 'AUTO' ? 'MANUAL' : 'AUTO';
    final command = 'MODE $newMode';
    try {
      await SingletonMqttService().mqttClientService.publishCommand(command);
      print('[UI DEBUG] Comando modo enviado exitosamente: $command');
    } catch (e) {
      print('[UI DEBUG] Error enviando comando modo $command: $e');
      // Error ya se maneja en el servicio MQTT, no mostrar SnackBar
    }
  }

  Widget _buildDeviceControl(String label, bool isOn, VoidCallback onPressed,
      String buttonText, IconData icon) {
    final colorPrimary = Theme.of(context).colorScheme.primary;
    final colorAccent = Theme.of(context).colorScheme.secondary;
    final colorText = Theme.of(context).colorScheme.onBackground;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color:
            isOn ? colorAccent.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isOn ? colorAccent : Colors.grey,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: isOn ? colorAccent : Colors.grey,
            size: 32,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: colorText,
                  ),
                ),
                Text(
                  isOn ? 'Encendido' : 'Apagado',
                  style: TextStyle(
                    fontSize: 14,
                    color: isOn ? colorAccent : Colors.grey,
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isOn ? Colors.red : colorAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              elevation: 2,
            ),
            onPressed: operationMode == 'AUTO'
                ? null
                : onPressed, // Deshabilitar en modo AUTO
            child: Text(
              buttonText,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
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
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                colorPrimary.withOpacity(0.1),
                colorAccent.withOpacity(0.05),
              ],
            ),
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Indicador de carga con colores de la paleta
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: colorPrimary.withOpacity(0.2),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      CircularProgressIndicator(
                        color: colorAccent,
                        strokeWidth: 3,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Cargando datos...',
                        style: TextStyle(
                          color: colorPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Si tarda demasiado, la app se cargará automáticamente',
                        style: TextStyle(
                          color: colorPrimary.withOpacity(0.7),
                          fontSize: 12,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ],
            ),
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
            // Gota animada en el centro sin fondo
            Center(
              child: Column(
                children: [
                  // Símbolo de Dropster animado
                  DropsterAnimatedSymbol(
                    value: tankLevel,
                    size: 140,
                    primaryColor: colorAccent,
                    secondaryColor: colorPrimary,
                    animationDuration: const Duration(milliseconds: 800),
                  ),
                  const SizedBox(height: 16),
                  // Título con porcentaje debajo
                  Column(
                    children: [
                      Text(
                        'Nivel del Tanque',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: colorText,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${(tankLevel * 100).toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: colorAccent,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // Control de Modo de Operación
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
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(
                            operationMode == 'AUTO'
                                ? Icons.autorenew
                                : Icons.touch_app,
                            color: operationMode == 'AUTO'
                                ? Colors.blue
                                : colorAccent,
                            size: 40,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              'Modo de Operación',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: colorText,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: operationMode == 'AUTO'
                                  ? Colors.blue.withOpacity(0.1)
                                  : colorAccent.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: operationMode == 'AUTO'
                                    ? Colors.blue
                                    : colorAccent,
                                width: 2,
                              ),
                            ),
                            child: Text(
                              operationMode,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: operationMode == 'AUTO'
                                    ? Colors.blue
                                    : colorAccent,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: operationMode == 'AUTO'
                                ? colorAccent
                                : Colors.blue,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            elevation: 4,
                          ),
                          onPressed: _toggleMode,
                          child: Text(
                            'Cambiar a ${operationMode == 'AUTO' ? 'Manual' : 'Automático'}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Controles de Relés
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Control de Actuadores',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: colorText,
                        ),
                      ),
                      const SizedBox(height: 16),
                      // AWG (Compresor)
                      _buildDeviceControl(
                        'AWG (Compresor)',
                        compressorState == 1,
                        _toggleSystem,
                        compressorState == 1 ? 'Apagar' : 'Encender',
                        Icons.ac_unit,
                      ),
                      const SizedBox(height: 16),
                      // Ventilador del Evaporador
                      _buildDeviceControl(
                        'Ventilador del Evaporador',
                        ventilatorState == 1,
                        _toggleVentilator,
                        ventilatorState == 1 ? 'Apagar' : 'Encender',
                        Icons.air,
                      ),
                      const SizedBox(height: 16),
                      // Ventilador del Compresor
                      _buildDeviceControl(
                        'Ventilador del Compresor',
                        compressorFanState == 1,
                        _toggleCompressorFan,
                        compressorFanState == 1 ? 'Apagar' : 'Encender',
                        Icons.air,
                      ),
                      const SizedBox(height: 16),
                      // Bomba de Agua
                      _buildDeviceControl(
                        'Bomba de Agua',
                        pumpState == 1,
                        _togglePump,
                        pumpState == 1 ? 'Apagar' : 'Encender',
                        Icons.water_drop,
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
                    'Wh',
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

  void _showPumpErrorDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Error'),
        content: const Text(
            'No se pudo activar la bomba de agua por seguridad nivel del tanque muy bajo para poder activarla.'),
        actions: [
          Builder(
            builder: (dialogContext) {
              final colorPrimary = Theme.of(dialogContext).colorScheme.primary;
              return ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: colorPrimary,
                  foregroundColor: Colors.white,
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                child: const Text('Aceptar'),
              );
            },
          ),
        ],
      ),
    );
  }
}

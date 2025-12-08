import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import '../services/mqtt_hive.dart';
import '../services/enhanced_daily_report_service.dart';
import '../services/singleton_mqtt_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Valores nominales
  double nominalVoltage = 110.0;
  double nominalCurrent = 10.0;
  final voltageController = TextEditingController();
  final currentController = TextEditingController();
  final mqttBrokerController = TextEditingController();
  final mqttPortController = TextEditingController();

  // Configuraciones de la app
  bool isSavingEnabled = true;
  bool autoConnect = true;
  bool showNotifications = true;
  bool dailyReportEnabled = false;
  TimeOfDay dailyReportTime = const TimeOfDay(hour: 20, minute: 0);
  String mqttBroker = 'test.mosquitto.org';
  int mqttPort = 1883;
  String mqttTopic = 'dropster/data';

  // Configuración del tanque
  double tankCapacity = 20.0; // litros
  final tankCapacityController = TextEditingController();

  // Calibración del tanque
  bool isCalibrated = false;
  List<Map<String, double>> calibrationPoints =
      []; // [{'distance': cm, 'liters': L}]
  double ultrasonicOffset = 0.0; // cm
  final ultrasonicOffsetController = TextEditingController();

  // Configuración de umbrales para alertas
  double tankFullThreshold = 90.0; // %
  double voltageLowThreshold = 100.0; // V
  double humidityLowThreshold = 30.0; // %
  bool tankFullEnabled = true;
  bool voltageLowEnabled = true;
  bool humidityLowEnabled = true;

  // Parámetros de control del ESP32
  double controlDeadband = 3.0; // °C
  int controlMinOff = 60; // segundos
  int controlMaxOn = 1800; // segundos
  int controlSampling = 8; // segundos
  double controlAlpha = 0.2; // factor de suavizado
  double maxCompressorTemp = 95.0; // °C
  int displayTimeoutMinutes =
      0; // Timeout del display en minutos (0 = desactivado)

  // Variables para almacenar configuración previa (para detectar cambios)
  String oldMqttBroker = 'test.mosquitto.org';
  int oldMqttPort = 1883;
  String oldMqttTopic = 'dropster/data';
  double oldTankFullThreshold = 90.0;
  double oldVoltageLowThreshold = 100.0;
  double oldHumidityLowThreshold = 30.0;
  bool oldTankFullEnabled = true;
  bool oldVoltageLowEnabled = true;
  bool oldHumidityLowEnabled = true;
  double oldControlDeadband = 3.0;
  int oldControlMinOff = 60;
  int oldControlMaxOn = 1800;
  int oldControlSampling = 8;
  double oldControlAlpha = 0.2;
  double oldMaxCompressorTemp = 95.0;
  int oldDisplayTimeoutMinutes = 0;
  bool oldShowNotifications = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    voltageController.dispose();
    currentController.dispose();
    mqttBrokerController.dispose();
    mqttPortController.dispose();
    tankCapacityController.dispose();
    ultrasonicOffsetController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    await MqttHiveService.initHive();

    if (!Hive.isBoxOpen('settings')) {
      await Hive.openBox('settings');
    }
    final settingsBox = Hive.box('settings');

    setState(() {
      // Valores nominales
      nominalVoltage = settingsBox.get('nominalVoltage', defaultValue: 110.0);
      nominalCurrent = settingsBox.get('nominalCurrent', defaultValue: 10.0);
      voltageController.text = nominalVoltage.toStringAsFixed(1);
      currentController.text = nominalCurrent.toStringAsFixed(1);

      // Configuraciones de la app
      isSavingEnabled = settingsBox.get('isSavingEnabled', defaultValue: true);
      autoConnect = settingsBox.get('autoConnect', defaultValue: true);
      showNotifications =
          settingsBox.get('showNotifications', defaultValue: true);
      mqttBroker =
          settingsBox.get('mqttBroker', defaultValue: 'test.mosquitto.org');
      mqttPort = settingsBox.get('mqttPort', defaultValue: 1883);
      mqttTopic = settingsBox.get('mqttTopic', defaultValue: 'dropster/data');

      // Configuración del tanque
      tankCapacity = settingsBox.get('tankCapacity', defaultValue: 20.0);
      tankCapacityController.text =
          tankCapacity.toStringAsFixed(tankCapacity < 1 ? 2 : 0);

      // Configuración de calibración
      isCalibrated = settingsBox.get('isCalibrated', defaultValue: false);
      calibrationPoints =
          (settingsBox.get('calibrationPoints', defaultValue: []) as List)
              .map((point) => Map<String, double>.from(point as Map))
              .toList();
      ultrasonicOffset = settingsBox.get('ultrasonicOffset', defaultValue: 0.0);
      ultrasonicOffsetController.text = ultrasonicOffset.toStringAsFixed(1);

      // Configuración de umbrales para alertas
      tankFullThreshold =
          settingsBox.get('tankFullThreshold', defaultValue: 90.0);
      voltageLowThreshold =
          settingsBox.get('voltageLowThreshold', defaultValue: 100.0);
      humidityLowThreshold =
          settingsBox.get('humidityLowThreshold', defaultValue: 30.0);
      tankFullEnabled = settingsBox.get('tankFullEnabled', defaultValue: true);
      voltageLowEnabled =
          settingsBox.get('voltageLowEnabled', defaultValue: true);
      humidityLowEnabled =
          settingsBox.get('humidityLowEnabled', defaultValue: true);

      // Configuración de reportes diarios
      dailyReportEnabled =
          settingsBox.get('dailyReportEnabled', defaultValue: false);
      final savedHour = settingsBox.get('dailyReportHour', defaultValue: 20);
      final savedMinute = settingsBox.get('dailyReportMinute', defaultValue: 0);
      dailyReportTime = TimeOfDay(hour: savedHour, minute: savedMinute);

      // Configuración de parámetros de control
      controlDeadband = settingsBox.get('controlDeadband', defaultValue: 3.0);
      controlMinOff = settingsBox.get('controlMinOff', defaultValue: 60);
      controlMaxOn = settingsBox.get('controlMaxOn', defaultValue: 1800);
      controlSampling = settingsBox.get('controlSampling', defaultValue: 8);
      controlAlpha = settingsBox.get('controlAlpha', defaultValue: 0.2);
      maxCompressorTemp =
          settingsBox.get('maxCompressorTemp', defaultValue: 95.0);
      displayTimeoutMinutes =
          settingsBox.get('displayTimeoutMinutes', defaultValue: 0);
    });

    // Asignar configuración previa para detectar cambios
    oldMqttBroker = mqttBroker;
    oldMqttPort = mqttPort;
    oldMqttTopic = mqttTopic;
    oldTankFullThreshold = tankFullThreshold;
    oldVoltageLowThreshold = voltageLowThreshold;
    oldHumidityLowThreshold = humidityLowThreshold;
    oldTankFullEnabled = tankFullEnabled;
    oldVoltageLowEnabled = voltageLowEnabled;
    oldHumidityLowEnabled = humidityLowEnabled;
    oldControlDeadband = controlDeadband;
    oldControlMinOff = controlMinOff;
    oldControlMaxOn = controlMaxOn;
    oldControlSampling = controlSampling;
    oldControlAlpha = controlAlpha;
    oldMaxCompressorTemp = maxCompressorTemp;
    oldDisplayTimeoutMinutes = displayTimeoutMinutes;
    oldShowNotifications = showNotifications;

    // Inicializar controladores de MQTT
    mqttBrokerController.text = mqttBroker;
    mqttPortController.text = mqttPort.toString();
  }

  Future<void> _saveSettings() async {
    final settingsBox = Hive.box('settings');

    // Mostrar diálogo de progreso
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return const AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text(
                'Enviando configuración...',
                style: TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      },
    );

    // Crear un Completer para esperar la confirmación del ESP32
    final completer = Completer<bool>();

    // Listener temporal para detectar confirmación de configuración
    void onConfigConfirmation(Map<String, dynamic> data) {
      if (data.containsKey('config_saved') && data['config_saved'] == true) {
        debugPrint(
            '[SETTINGS] ✅ Confirmación de configuración recibida del ESP32');
        completer.complete(true);
        // Limpiar el mensaje del notifier
        SingletonMqttService().notifier.value = {...data}
          ..remove('config_saved');
      }
    }

    // Agregar listener temporal (guardar la referencia para removerla luego)
    void listener() =>
        onConfigConfirmation(SingletonMqttService().notifier.value);
    SingletonMqttService().notifier.addListener(listener);

    try {
      debugPrint('[SETTINGS] 🚀 Iniciando guardado de configuración...');

      // Guardar valores nominales
      debugPrint('[SETTINGS] 💾 Guardando valores nominales...');
      await settingsBox.put('nominalVoltage', nominalVoltage);
      await settingsBox.put('nominalCurrent', nominalCurrent);

      // Guardar configuraciones de la app
      debugPrint('[SETTINGS] 💾 Guardando configuraciones de la app...');
      await settingsBox.put('isSavingEnabled', isSavingEnabled);
      await settingsBox.put('autoConnect', autoConnect);
      await settingsBox.put('showNotifications', showNotifications);
      await settingsBox.put('mqttBroker', mqttBroker);
      await settingsBox.put('mqttPort', mqttPort);
      await settingsBox.put('mqttTopic', mqttTopic);

      // Guardar configuración del tanque
      debugPrint('[SETTINGS] 💾 Guardando configuración del tanque...');
      await settingsBox.put('tankCapacity', tankCapacity);

      // Guardar configuración de calibración
      await settingsBox.put('isCalibrated', isCalibrated);
      await settingsBox.put('calibrationPoints', calibrationPoints);
      await settingsBox.put('ultrasonicOffset', ultrasonicOffset);

      // Guardar configuración de umbrales para alertas
      debugPrint('[SETTINGS] 💾 Guardando umbrales de alertas...');
      await settingsBox.put('tankFullThreshold', tankFullThreshold);
      await settingsBox.put('voltageLowThreshold', voltageLowThreshold);
      await settingsBox.put('humidityLowThreshold', humidityLowThreshold);
      await settingsBox.put('tankFullEnabled', tankFullEnabled);
      await settingsBox.put('voltageLowEnabled', voltageLowEnabled);
      await settingsBox.put('humidityLowEnabled', humidityLowEnabled);

      // Guardar configuración de reportes diarios
      debugPrint(
          '[SETTINGS] 💾 Guardando configuración de reportes diarios...');
      await settingsBox.put('dailyReportEnabled', dailyReportEnabled);
      await settingsBox.put('dailyReportHour', dailyReportTime.hour);
      await settingsBox.put('dailyReportMinute', dailyReportTime.minute);

      // Guardar configuración de parámetros de control
      debugPrint('[SETTINGS] 💾 Guardando parámetros de control...');
      await settingsBox.put('controlDeadband', controlDeadband);
      await settingsBox.put('controlMinOff', controlMinOff);
      await settingsBox.put('controlMaxOn', controlMaxOn);
      await settingsBox.put('controlSampling', controlSampling);
      await settingsBox.put('controlAlpha', controlAlpha);
      await settingsBox.put('maxCompressorTemp', maxCompressorTemp);
      await settingsBox.put('displayTimeoutMinutes', displayTimeoutMinutes);

      debugPrint('[SETTINGS] ✅ Configuración guardada localmente en Hive');

      // Actualizar el servicio MQTT Hive inmediatamente
      MqttHiveService.toggleSaving(isSavingEnabled);

      // Programar o cancelar reporte diario mejorado
      try {
        debugPrint('[SETTINGS] 📅 Programando reporte diario...');
        await EnhancedDailyReportService()
            .scheduleDailyReport(dailyReportTime, dailyReportEnabled);
        debugPrint('[SETTINGS] ✅ Reporte diario programado correctamente');
      } catch (e) {
        debugPrint('[SETTINGS] ❌ Error programando reporte diario: $e');
      }

      // 📡 ENVIAR CONFIGURACIÓN AL ESP32 EN 2 MENSAJES SEPARADOS
      debugPrint(
          '[SETTINGS] 🔍 Verificando estado de conexión MQTT antes de enviar...');
      bool isMqttConnected = SingletonMqttService().mqttConnected;
      debugPrint('[SETTINGS] Estado MQTT conectado: $isMqttConnected');

      if (!isMqttConnected) {
        debugPrint(
            '[SETTINGS] ❌ MQTT no conectado, abortando envío de configuración');

        // Cerrar diálogo de progreso
        if (mounted && Navigator.canPop(context)) {
          Navigator.of(context).pop();
        }

        if (mounted) {
          showDialog(
            context: context,
            builder: (BuildContext errorContext) {
              return AlertDialog(
                title: const Text('❌ Error'),
                content: const Text(
                    'MQTT no conectado. Verifica la conexión antes de guardar.'),
                actions: [
                  Builder(
                    builder: (dialogContext) {
                      final colorPrimary =
                          Theme.of(dialogContext).colorScheme.primary;
                      return ElevatedButton(
                        onPressed: () => Navigator.of(errorContext).pop(),
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
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 12),
                        ),
                        child: const Text('Aceptar'),
                      );
                    },
                  ),
                ],
              );
            },
          );
        }
        return;
      }

      debugPrint(
          '[SETTINGS] ✅ MQTT conectado, enviando configuración unificada...');

      // 1️⃣ DETECTAR CAMBIOS EN CONFIGURACIÓN MQTT
      bool mqttConfigChanged = (mqttBroker != oldMqttBroker ||
          mqttPort != oldMqttPort ||
          mqttTopic != oldMqttTopic);
      debugPrint('[SETTINGS] ¿Configuración MQTT cambió?: $mqttConfigChanged');

      // 2️⃣ RECONECTAR SOLO SI CAMBIÓ LA CONFIGURACIÓN MQTT
      if (mqttConfigChanged) {
        debugPrint(
            '[SETTINGS] 📡 Configuración MQTT cambió, reconectando cliente MQTT de la app...');

        try {
          // Reconectar el cliente MQTT de la app con nueva configuración
          await SingletonMqttService()
              .mqttClientService
              .reconnectWithNewConfig(SingletonMqttService().mqttService);

          debugPrint(
              '[SETTINGS] ✅ Cliente MQTT reconectado con nueva configuración');
        } catch (e) {
          debugPrint('[SETTINGS] ❌ Error reconectando MQTT: $e');
          // Continuar con el envío aunque falle la reconexión
        }
      } else {
        debugPrint(
            '[SETTINGS] ℹ️ Configuración MQTT sin cambios, manteniendo conexión actual');
      }

      // 3️⃣ ENVIAR CONFIGURACIÓN UNIFICADA (MQTT + PARÁMETROS)
      debugPrint('[SETTINGS] 📤 Enviando configuración unificada completa...');
      debugPrint('[SETTINGS] 📊 Parámetros a enviar:');
      debugPrint('  - MQTT: $mqttBroker:$mqttPort, topic: $mqttTopic');
      debugPrint(
          '  - Tanque: capacidad=$tankCapacity, calibrado=$isCalibrated');
      debugPrint(
          '  - Umbrales: tanque=$tankFullThreshold, voltaje=$voltageLowThreshold, humedad=$humidityLowThreshold');
      debugPrint(
          '  - Control: deadband=$controlDeadband, minOff=$controlMinOff, maxOn=$controlMaxOn');
      debugPrint(
          '  - Reportes: enabled=$dailyReportEnabled, time=${dailyReportTime.hour}:${dailyReportTime.minute}');

      try {
        debugPrint(
            '[SETTINGS] 🔍 Verificando estado MQTT antes de enviar configuración...');
        debugPrint(
            '[SETTINGS] Estado MQTT: ${SingletonMqttService().mqttConnected}');
        debugPrint('[SETTINGS] Broker configurado: $mqttBroker:$mqttPort');
        debugPrint('[SETTINGS] Topic configurado: $mqttTopic');

        final configResult = await SingletonMqttService()
            .mqttClientService
            .sendFullConfigToESP32(
              broker: mqttBroker,
              port: mqttPort,
              topic: mqttTopic,
              tankFullThreshold: tankFullThreshold,
              voltageLowThreshold: voltageLowThreshold,
              humidityLowThreshold: humidityLowThreshold,
              tankFullEnabled: tankFullEnabled,
              voltageLowEnabled: voltageLowEnabled,
              humidityLowEnabled: humidityLowEnabled,
              tankCapacity: tankCapacity,
              isCalibrated: isCalibrated,
              calibrationPoints: calibrationPoints,
              ultrasonicOffset: ultrasonicOffset,
              controlDeadband: controlDeadband,
              controlMinOff: controlMinOff,
              controlMaxOn: controlMaxOn,
              controlSampling: controlSampling,
              controlAlpha: controlAlpha,
              maxCompressorTemp: maxCompressorTemp,
              displayTimeoutMinutes: displayTimeoutMinutes * 60,
              showNotifications: showNotifications,
              dailyReportEnabled: dailyReportEnabled,
              dailyReportTime: dailyReportTime,
            );
        debugPrint('[SETTINGS] ✅ Configuración unificada enviada al ESP32');
        debugPrint('[SETTINGS] 📡 Mensaje enviado al topic: dropster/control');
        debugPrint(
            '[SETTINGS] ⏳ Esperando confirmación del ESP32 en topic: dropster/status');

        // Esperar confirmación del ESP32 con timeout de 15 segundos
        debugPrint('[SETTINGS] ⏳ Esperando confirmación del ESP32...');
        final confirmed = await completer.future.timeout(
          const Duration(seconds: 15),
          onTimeout: () {
            debugPrint('[SETTINGS] ⏰ Timeout esperando confirmación del ESP32');
            return false;
          },
        );

        // Cerrar diálogo de progreso
        if (mounted && Navigator.canPop(context)) {
          Navigator.of(context).pop();
        }

        if (confirmed) {
          // Actualizar configuración previa para futuras comparaciones
          oldMqttBroker = mqttBroker;
          oldMqttPort = mqttPort;
          oldMqttTopic = mqttTopic;
          oldTankFullThreshold = tankFullThreshold;
          oldVoltageLowThreshold = voltageLowThreshold;
          oldHumidityLowThreshold = humidityLowThreshold;
          oldTankFullEnabled = tankFullEnabled;
          oldVoltageLowEnabled = voltageLowEnabled;
          oldHumidityLowEnabled = humidityLowEnabled;
          oldControlDeadband = controlDeadband;
          oldControlMinOff = controlMinOff;
          oldControlMaxOn = controlMaxOn;
          oldControlSampling = controlSampling;
          oldControlAlpha = controlAlpha;
          oldMaxCompressorTemp = maxCompressorTemp;
          oldDisplayTimeoutMinutes = displayTimeoutMinutes;
          oldShowNotifications = showNotifications;

          // Mostrar mensaje de éxito
          if (mounted) {
            showDialog(
              context: context,
              builder: (BuildContext successContext) {
                return AlertDialog(
                  title: const Text('✅ Éxito'),
                  content: const Text(
                      'Configuración cargada exitosamente en el dispositivo Dropster AWG'),
                  actions: [
                    Builder(
                      builder: (dialogContext) {
                        final colorPrimary =
                            Theme.of(dialogContext).colorScheme.primary;
                        return ElevatedButton(
                          onPressed: () => Navigator.of(successContext).pop(),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: colorPrimary),
                          child: const Text('Aceptar',
                              style: TextStyle(color: Colors.white)),
                        );
                      },
                    ),
                  ],
                );
              },
            );
          }
        } else {
          // No se recibió confirmación
          if (mounted) {
            showDialog(
              context: context,
              builder: (BuildContext errorContext) {
                return AlertDialog(
                  title: const Text('❌ Error'),
                  content: const Text(
                      'Error en el envio de configuracion a Dropster AWG:\nNo se recibio confirmacion del dispositivo en 15 segundos\n\nVerifica que el dispositivo Dropster AWG este conectado y\nfuncionando correctamente.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(errorContext).pop(),
                      style: TextButton.styleFrom(
                        backgroundColor: const Color(0xFF206877),
                        foregroundColor: Colors.white,
                        textStyle: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                      ),
                      child: const Text('Aceptar'),
                    ),
                  ],
                );
              },
            );
          }
        }
      } catch (e) {
        debugPrint(
            '[SETTINGS] ❌ Error enviando configuración de parámetros: $e');

        // Cerrar diálogo de progreso
        if (mounted && Navigator.canPop(context)) {
          Navigator.of(context).pop();
        }

        // Mostrar error al usuario
        if (mounted) {
          showDialog(
            context: context,
            builder: (BuildContext errorContext) {
              return AlertDialog(
                title: const Text('❌ Error'),
                content: Text('Error enviando configuración: $e'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(errorContext).pop(),
                    child: const Text('Aceptar'),
                  ),
                ],
              );
            },
          );
        }
      } finally {
        // Limpiar listener temporal
        SingletonMqttService().notifier.removeListener(listener);
      }
    } catch (e) {
      debugPrint('[SETTINGS] ❌ Error guardando configuración: $e');

      // Cerrar diálogo de progreso si está abierto
      if (mounted && Navigator.canPop(context)) {
        Navigator.of(context).pop();
      }

      // Mostrar error
      if (mounted) {
        showDialog(
          context: context,
          builder: (BuildContext errorContext) {
            return AlertDialog(
              title: const Text('❌ Error'),
              content: Text('Error guardando configuración: $e'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(errorContext).pop(),
                  style: TextButton.styleFrom(
                    backgroundColor: const Color(0xFF206877),
                    foregroundColor: Colors.white,
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                  ),
                  child: const Text('Aceptar'),
                ),
              ],
            );
          },
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorPrimary = Theme.of(context).colorScheme.primary;
    final colorAccent = Theme.of(context).colorScheme.secondary;
    final colorText = Theme.of(context).colorScheme.onBackground;
    final labelColor = Colors.white;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuración'),
        backgroundColor: colorPrimary,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Sección de configuración de datos
            _buildSectionHeader(
                'Configuración de Datos', Icons.data_usage, labelColor),
            const SizedBox(height: 16),
            _buildDataSettingsCard(colorPrimary, colorAccent, colorText),
            const SizedBox(height: 24),
            // Sección de conectividad
            _buildSectionHeader('Conectividad', Icons.wifi, labelColor),
            const SizedBox(height: 16),
            _buildConnectivityCard(colorPrimary, colorAccent, colorText),
            const SizedBox(height: 24),
            // Sección de notificaciones
            _buildSectionHeader(
                'Notificaciones', Icons.notifications, labelColor),
            const SizedBox(height: 16),
            _buildNotificationsCard(colorPrimary, colorAccent, colorText),
            const SizedBox(height: 24),
            // Sección de configuración del tanque
            _buildSectionHeader(
                'Configuración del Tanque', Icons.water_drop, labelColor),
            const SizedBox(height: 16),
            _buildTankSettingsCard(colorPrimary, colorAccent, colorText),
            const SizedBox(height: 24),
            // Sección de umbrales de alertas
            _buildSectionHeader(
                'Umbrales de Alertas', Icons.warning, labelColor),
            const SizedBox(height: 16),
            _buildAlertThresholdsCard(colorPrimary, colorAccent, colorText),
            const SizedBox(height: 24),
            // Sección de parámetros de control
            _buildSectionHeader(
                'Parámetros de Control', Icons.tune, labelColor),
            const SizedBox(height: 16),
            _buildControlParametersCard(colorPrimary, colorAccent, colorText),
            const SizedBox(height: 32),
            // Botón de guardar
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saveSettings,
                style: ElevatedButton.styleFrom(
                  backgroundColor: colorAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text(
                  'Guardar Configuración',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildDataSettingsCard(
      Color colorPrimary, Color colorAccent, Color colorText) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ListTile(
              leading: Icon(Icons.delete_sweep, color: colorAccent),
              title: const Text('Borrar todos los datos'),
              subtitle:
                  const Text('Elimina todos los datos históricos almacenados'),
              onTap: () => _showClearDataDialog(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectivityCard(
      Color colorPrimary, Color colorAccent, Color colorText) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            SwitchListTile(
              title: const Text('Conexión automática'),
              subtitle: const Text('Conecta automáticamente al iniciar la app'),
              value: autoConnect,
              onChanged: (value) {
                setState(() {
                  autoConnect = value;
                });
              },
              activeColor: colorAccent,
            ),
            const Divider(),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Broker MQTT',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.wifi),
              ),
              onChanged: (value) {
                mqttBroker = value;
              },
              controller: mqttBrokerController,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: 'Puerto',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.numbers),
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (value) {
                      mqttPort = int.tryParse(value) ?? 1883;
                    },
                    controller: mqttPortController,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationsCard(
      Color colorPrimary, Color colorAccent, Color colorText) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            SwitchListTile(
              title: const Text('Mostrar notificaciones'),
              subtitle: const Text('Recibe alertas de anomalías y eventos'),
              value: showNotifications,
              onChanged: (value) {
                setState(() {
                  showNotifications = value;
                });
              },
              activeColor: colorAccent,
            ),
            const Divider(),
            SwitchListTile(
              title: const Text('Reporte diario automático'),
              subtitle: Text(
                  'Recibe resumen diario a las ${dailyReportTime.format(context)}'),
              value: dailyReportEnabled,
              onChanged: (value) {
                setState(() {
                  dailyReportEnabled = value;
                });
              },
              activeColor: colorAccent,
            ),
            const Divider(),
            ListTile(
              leading: Icon(Icons.schedule, color: colorAccent),
              title: const Text('Hora del reporte diario'),
              subtitle: Text('${dailyReportTime.format(context)}'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: _showDailyReportTimeDialog,
            ),
            const Divider(),
            ListTile(
              leading: Icon(Icons.history, color: colorAccent),
              title: const Text('Historial de reportes'),
              subtitle: const Text('Ver reportes diarios anteriores'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: _showReportHistoryDialog,
            ),
            const Divider(),
            ListTile(
              leading: Icon(Icons.today, color: colorAccent),
              title: const Text('Reporte del día actual'),
              subtitle: const Text('Generar reporte con datos actuales'),
              trailing: const Icon(Icons.assessment, size: 16),
              onTap: () => _generateCurrentDayReport(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTankSettingsCard(
      Color colorPrimary, Color colorAccent, Color colorText) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Capacidad del tanque
            ListTile(
              leading: Icon(Icons.straighten, color: colorAccent),
              title: const Text('Capacidad del tanque'),
              subtitle: Text(
                  '${tankCapacity.toStringAsFixed(tankCapacity < 1 ? 2 : 0)} litros'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: _showTankCapacityDialog,
            ),
            const Divider(),

            // Offset del sensor de nivel
            ListTile(
              leading: Icon(Icons.tune, color: colorAccent),
              title: const Text('Offset del sensor de nivel'),
              subtitle: Text('${ultrasonicOffset.toStringAsFixed(1)} cm'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: _showUltrasonicOffsetDialog,
            ),
            const Divider(),
          ],
        ),
      ),
    );
  }

  Widget _buildAlertThresholdsCard(
      Color colorPrimary, Color colorAccent, Color colorText) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Alerta de tanque lleno
            SwitchListTile(
              title: const Text('Alerta de tanque lleno'),
              subtitle: Text(
                  'Notificar cuando el tanque supere el ${tankFullThreshold.toStringAsFixed(0)}%'),
              value: tankFullEnabled,
              onChanged: (value) {
                setState(() {
                  tankFullEnabled = value;
                });
              },
              activeColor: colorAccent,
            ),
            if (tankFullEnabled)
              Padding(
                padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
                child: Row(
                  children: [
                    const Text('Umbral: '),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: colorAccent,
                          inactiveTrackColor: colorAccent.withOpacity(0.3),
                          thumbColor: colorAccent,
                          overlayColor: colorAccent.withOpacity(0.2),
                          valueIndicatorColor: colorAccent,
                          valueIndicatorTextStyle: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        child: Slider(
                          value: tankFullThreshold,
                          min: 70,
                          max: 100,
                          label: '${tankFullThreshold.toStringAsFixed(0)}%',
                          onChanged: (value) {
                            setState(() {
                              tankFullThreshold = value;
                            });
                          },
                          activeColor: colorAccent,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const Divider(),

            // Alerta de voltaje bajo
            SwitchListTile(
              title: const Text('Alerta de voltaje bajo'),
              subtitle: Text(
                  'Notificar cuando el voltaje baje de ${voltageLowThreshold.toInt()}V'),
              value: voltageLowEnabled,
              onChanged: (value) {
                setState(() {
                  voltageLowEnabled = value;
                });
              },
              activeColor: colorAccent,
            ),
            if (voltageLowEnabled)
              Padding(
                padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
                child: Row(
                  children: [
                    const Text('Umbral: '),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: colorAccent,
                          inactiveTrackColor: colorAccent.withOpacity(0.3),
                          thumbColor: colorAccent,
                          overlayColor: colorAccent.withOpacity(0.2),
                          valueIndicatorColor: colorAccent,
                          valueIndicatorTextStyle: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        child: Slider(
                          value: voltageLowThreshold,
                          min: 90,
                          max: 125,
                          divisions: 35,
                          label: '${voltageLowThreshold.toInt()}V',
                          onChanged: (value) {
                            setState(() {
                              voltageLowThreshold = value;
                            });
                          },
                          activeColor: colorAccent,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const Divider(),

            // Alerta de humedad baja
            SwitchListTile(
              title: const Text('Alerta de humedad baja'),
              subtitle: Text(
                  'Notificar cuando la humedad baje de ${humidityLowThreshold.toStringAsFixed(0)}%'),
              value: humidityLowEnabled,
              onChanged: (value) {
                setState(() {
                  humidityLowEnabled = value;
                });
              },
              activeColor: colorAccent,
            ),
            if (humidityLowEnabled)
              Padding(
                padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
                child: Row(
                  children: [
                    const Text('Umbral: '),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: colorAccent,
                          inactiveTrackColor: colorAccent.withOpacity(0.3),
                          thumbColor: colorAccent,
                          overlayColor: colorAccent.withOpacity(0.2),
                          valueIndicatorColor: colorAccent,
                          valueIndicatorTextStyle: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        child: Slider(
                          value: humidityLowThreshold,
                          min: 10,
                          max: 70,
                          divisions: 60,
                          label: '${humidityLowThreshold.toStringAsFixed(0)}%',
                          onChanged: (value) {
                            setState(() {
                              humidityLowThreshold = value;
                            });
                          },
                          activeColor: colorAccent,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const Divider(),

            // Alerta de sobrecalentamiento del compresor
            ListTile(
              title: Text(
                'Alerta de sobrecalentamiento del compresor',
                style: const TextStyle(color: Colors.white),
              ),
              subtitle: Text(
                'Notificar cuando la temperatura supere los ${maxCompressorTemp.toStringAsFixed(0)}°C',
                style: const TextStyle(color: Colors.white),
              ),
            ),
            // Slider para el umbral
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
              child: Row(
                children: [
                  const Text('Umbral: '),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: colorAccent,
                        inactiveTrackColor: colorAccent.withOpacity(0.3),
                        thumbColor: colorAccent,
                        overlayColor: colorAccent.withOpacity(0.2),
                        valueIndicatorColor: colorAccent,
                        valueIndicatorTextStyle: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      child: Slider(
                        value: maxCompressorTemp,
                        min: 50.0,
                        max: 150.0,
                        divisions: 100,
                        label: '${maxCompressorTemp.toStringAsFixed(0)}°C',
                        onChanged: (value) {
                          setState(() {
                            maxCompressorTemp = value;
                          });
                        },
                        activeColor: colorAccent,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(),

            // Timeout del display
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.timer_off, color: colorAccent, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Timeout del display: ${displayTimeoutMinutes == 0 ? "Desactivado" : "$displayTimeoutMinutes min"}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: colorAccent,
                      inactiveTrackColor: colorAccent.withOpacity(0.3),
                      thumbColor: colorAccent,
                      overlayColor: colorAccent.withOpacity(0.2),
                      valueIndicatorColor: colorAccent,
                      valueIndicatorTextStyle: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    child: Slider(
                      value: displayTimeoutMinutes.toDouble(),
                      min: 0,
                      max: 10,
                      divisions: 10,
                      label: displayTimeoutMinutes == 0
                          ? "Desactivado"
                          : "$displayTimeoutMinutes min",
                      onChanged: (value) {
                        setState(() {
                          displayTimeoutMinutes = value.toInt();
                        });
                      },
                      activeColor: colorAccent,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlParametersCard(
      Color colorPrimary, Color colorAccent, Color colorText) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Banda muerta (Deadband)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.thermostat, color: colorAccent, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Banda muerta: ${controlDeadband.toStringAsFixed(1)} °C',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: colorAccent,
                      inactiveTrackColor: colorAccent.withOpacity(0.3),
                      thumbColor: colorAccent,
                      overlayColor: colorAccent.withOpacity(0.2),
                      valueIndicatorColor: colorAccent,
                      valueIndicatorTextStyle: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    child: Slider(
                      value: controlDeadband,
                      min: 0.5,
                      max: 10.0,
                      divisions: 95,
                      label: '${controlDeadband.toStringAsFixed(1)}°C',
                      onChanged: (value) {
                        setState(() {
                          controlDeadband = value;
                        });
                      },
                      activeColor: colorAccent,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(),

            // Tiempo mínimo apagado
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.timer_off, color: colorAccent, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Tiempo min apagado: ${controlMinOff} segundos',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: colorAccent,
                      inactiveTrackColor: colorAccent.withOpacity(0.3),
                      thumbColor: colorAccent,
                      overlayColor: colorAccent.withOpacity(0.2),
                      valueIndicatorColor: colorAccent,
                      valueIndicatorTextStyle: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    child: Slider(
                      value: controlMinOff.toDouble(),
                      min: 10,
                      max: 300,
                      divisions: 58,
                      label: '${controlMinOff}s',
                      onChanged: (value) {
                        setState(() {
                          controlMinOff = value.toInt();
                        });
                      },
                      activeColor: colorAccent,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(),

            // Tiempo máximo encendido
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.timer, color: colorAccent, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Tiempo max encendido: ${controlMaxOn} segundos (${(controlMaxOn / 60).toStringAsFixed(0)} min)',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: colorAccent,
                      inactiveTrackColor: colorAccent.withOpacity(0.3),
                      thumbColor: colorAccent,
                      overlayColor: colorAccent.withOpacity(0.2),
                      valueIndicatorColor: colorAccent,
                      valueIndicatorTextStyle: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    child: Slider(
                      value: controlMaxOn.toDouble(),
                      min: 300,
                      max: 7200,
                      divisions: 69,
                      label:
                          '${controlMaxOn}s (${(controlMaxOn / 60).toStringAsFixed(0)}min)',
                      onChanged: (value) {
                        setState(() {
                          controlMaxOn = value.toInt();
                        });
                      },
                      activeColor: colorAccent,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(),

            // Intervalo de muestreo
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.schedule, color: colorAccent, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Intervalo de muestreo: ${controlSampling} segundos',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: colorAccent,
                      inactiveTrackColor: colorAccent.withOpacity(0.3),
                      thumbColor: colorAccent,
                      overlayColor: colorAccent.withOpacity(0.2),
                      valueIndicatorColor: colorAccent,
                      valueIndicatorTextStyle: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    child: Slider(
                      value: controlSampling.toDouble(),
                      min: 2,
                      max: 60,
                      divisions: 58,
                      label: '${controlSampling}s',
                      onChanged: (value) {
                        setState(() {
                          controlSampling = value.toInt();
                        });
                      },
                      activeColor: colorAccent,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(),

            // Factor de suavizado
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.blur_on, color: colorAccent, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Factor de suavizado: ${controlAlpha.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: colorAccent,
                      inactiveTrackColor: colorAccent.withOpacity(0.3),
                      thumbColor: colorAccent,
                      overlayColor: colorAccent.withOpacity(0.2),
                      valueIndicatorColor: colorAccent,
                      valueIndicatorTextStyle: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    child: Slider(
                      value: controlAlpha,
                      min: 0.0,
                      max: 1.0,
                      divisions: 100,
                      label: '${controlAlpha.toStringAsFixed(2)}',
                      onChanged: (value) {
                        setState(() {
                          controlAlpha = value;
                        });
                      },
                      activeColor: colorAccent,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showClearDataDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Borrar datos'),
        content: const Text(
            '¿Estás seguro de que quieres borrar todos los datos históricos? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
            ),
            child:
                const Text('Cancelar', style: TextStyle(color: Colors.white)),
          ),
          Builder(
            builder: (dialogContext) {
              final colorPrimary = Theme.of(dialogContext).colorScheme.primary;
              return ElevatedButton(
                onPressed: () async {
                  Navigator.pop(context);
                  await _clearAllDataAndNotify(dialogContext);
                },
                style: ElevatedButton.styleFrom(backgroundColor: colorPrimary),
                child:
                    const Text('Borrar', style: TextStyle(color: Colors.white)),
              );
            },
          ),
        ],
      ),
    );
  }

  void _showTankCapacityDialog() {
    final colorPrimary = Theme.of(context).colorScheme.primary;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Capacidad del tanque'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: tankCapacityController,
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Capacidad (litros)',
                border: OutlineInputBorder(),
                suffixText: 'L',
                hintText: 'Ej: 0.5, 1.25, 1000',
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Ingresa la capacidad total del tanque en litros. Valores decimales permitidos (ej: 0.5 L para tanques pequeños).',
              style: TextStyle(fontSize: 12, color: Colors.white),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
            ),
            child:
                const Text('Cancelar', style: TextStyle(color: Colors.white)),
          ),
          Builder(
            builder: (dialogContext) {
              final colorPrimary = Theme.of(dialogContext).colorScheme.primary;
              return ElevatedButton(
                onPressed: () {
                  final capacity = double.tryParse(tankCapacityController.text);
                  if (capacity != null && capacity > 0 && capacity != 0) {
                    setState(() {
                      tankCapacity = capacity;
                    });
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('Capacidad del tanque actualizada',
                            style: TextStyle(color: Color(0xFF155263))),
                        backgroundColor: Colors.white,
                      ),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text(
                            'Por favor ingresa un valor válido mayor a 0 (ej: 0.5, 1.25, 1000)',
                            style: TextStyle(color: Colors.white)),
                        backgroundColor: colorPrimary,
                      ),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: colorPrimary),
                child: const Text('Aceptar',
                    style: TextStyle(color: Colors.white)),
              );
            },
          ),
        ],
      ),
    );
  }

  void _showDailyReportTimeDialog() async {
    final currentContext = context;
    final TimeOfDay? picked = await showTimePicker(
      context: currentContext,
      initialTime: dailyReportTime,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
                  primary: Theme.of(context).colorScheme.primary,
                  onPrimary: Colors.white,
                  surface: Theme.of(context).dialogBackgroundColor,
                  onSurface: Colors.white,
                ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                backgroundColor: const Color(0xFF206877),
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
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && picked != dailyReportTime) {
      setState(() {
        dailyReportTime = picked;
      });
      if (mounted) {
        ScaffoldMessenger.of(currentContext).showSnackBar(
          SnackBar(
            content: Text(
                'Hora del reporte diario actualizada a ${picked.format(currentContext)}',
                style: TextStyle(color: Color(0xFF155263))),
            backgroundColor: Colors.white,
          ),
        );
      }
    }
  }

  void _showReportHistoryDialog() async {
    final currentContext = context;
    final reports = await EnhancedDailyReportService().getReportHistory();

    if (!mounted) return;
    showDialog(
      context: currentContext,
      builder: (context) => AlertDialog(
        title: const Text('Historial de Reportes Diarios'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: reports.isEmpty
              ? const Center(
                  child: Text('No hay reportes disponibles'),
                )
              : ListView.builder(
                  itemCount: reports.length,
                  itemBuilder: (context, index) {
                    final report = reports[index];
                    final date =
                        DateTime.fromMillisecondsSinceEpoch(report['date']);
                    final energy = report['energy'] ?? 0.0;
                    final water = report['water'] ?? 0.0;
                    final efficiency = report['efficiency'] ?? 0.0;

                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        title: Text(
                          '${DateFormat('dd/MM/yyyy').format(date)}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('⚡ Energía: ${energy.toStringAsFixed(2)} Wh'),
                            Text('💧 Agua: ${water.toStringAsFixed(2)} L'),
                            Text(
                                '⚡ Eficiencia: ${efficiency.toStringAsFixed(3)} Wh/L'),
                          ],
                        ),
                        trailing: Icon(
                          efficiency > 0 ? Icons.check_circle : Icons.warning,
                          color: efficiency > 0 ? Colors.green : Colors.orange,
                        ),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(currentContext),
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
            ),
            child: const Text('Cerrar', style: TextStyle(color: Colors.white)),
          ),
          if (reports.isNotEmpty)
            TextButton(
              onPressed: () {
                Navigator.pop(currentContext);
                _clearReportHistoryAndNotify();
              },
              child: const Text('Borrar Historial',
                  style: TextStyle(color: Colors.red)),
            ),
        ],
      ),
    );
  }

  void _generateCurrentDayReport(BuildContext context) async {
    try {
      debugPrint('📊 Generando reporte del día actual...');
      await EnhancedDailyReportService().generateCurrentDayReport();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Reporte del día actual enviado',
              style: TextStyle(color: Color(0xFF155263))),
          backgroundColor: Colors.white,
        ),
      );
    } catch (e) {
      debugPrint('Error generando reporte del día actual: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error generando reporte: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

// Métodos para configuración del tanque

  void _showUltrasonicOffsetDialog() {
    final colorPrimary = Theme.of(context).colorScheme.primary;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Offset del sensor ultrasónico'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ultrasonicOffsetController,
              keyboardType:
                  TextInputType.numberWithOptions(decimal: true, signed: true),
              decoration: const InputDecoration(
                labelText: 'Offset (cm)',
                border: OutlineInputBorder(),
                suffixText: 'cm',
                helperText:
                    'Ajuste positivo/negativo para compensar mediciones',
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'El offset se suma a las mediciones del sensor. Use valores positivos si mide más de lo real, negativos si mide menos.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            child:
                const Text('Cancelar', style: TextStyle(color: Colors.white)),
          ),
          Builder(
            builder: (dialogContext) {
              final colorPrimary = Theme.of(dialogContext).colorScheme.primary;
              return ElevatedButton(
                onPressed: () {
                  final offset =
                      double.tryParse(ultrasonicOffsetController.text);
                  if (offset != null) {
                    setState(() {
                      ultrasonicOffset = offset;
                    });
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Offset del sensor actualizado',
                            style: TextStyle(color: Color(0xFF155263))),
                        backgroundColor: Colors.white,
                      ),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('Por favor ingresa un valor válido',
                            style: TextStyle(color: Colors.white)),
                        backgroundColor: colorPrimary,
                      ),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: colorPrimary),
                child: const Text('Aceptar',
                    style: TextStyle(color: Colors.white)),
              );
            },
          ),
        ],
      ),
    );
  }

  void _addCalibrationPoint() {
    _showCalibrationPointDialog(-1, {'distance': 0.0, 'liters': 0.0});
  }

  void _editCalibrationPoint(int index) {
    if (index >= 0 && index < calibrationPoints.length) {
      _showCalibrationPointDialog(index, Map.from(calibrationPoints[index]));
    }
  }

  void _removeCalibrationPoint(int index) {
    setState(() {
      calibrationPoints.removeAt(index);
    });
  }

  void _showCalibrationPointDialog(int index, Map<String, double> point) {
    final colorPrimary = Theme.of(context).colorScheme.primary;
    final distanceController = TextEditingController(
        text: point['distance']?.toStringAsFixed(1) ?? '0.0');
    final litersController = TextEditingController(
        text: point['liters']?.toStringAsFixed(1) ?? '0.0');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(index == -1
            ? 'Agregar punto de calibración'
            : 'Editar punto de calibración'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: distanceController,
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Distancia del sensor',
                border: OutlineInputBorder(),
                suffixText: 'cm',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: litersController,
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Volumen de agua',
                border: OutlineInputBorder(),
                suffixText: 'L',
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Mide la distancia desde el sensor al agua y registra el volumen correspondiente.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            child:
                const Text('Cancelar', style: TextStyle(color: Colors.white)),
          ),
          Builder(
            builder: (dialogContext) {
              final colorPrimary = Theme.of(dialogContext).colorScheme.primary;
              return ElevatedButton(
                onPressed: () {
                  final distance = double.tryParse(distanceController.text);
                  final liters = double.tryParse(litersController.text);

                  if (distance != null &&
                      liters != null &&
                      distance >= 0 &&
                      liters >= 0) {
                    setState(() {
                      if (index == -1) {
                        calibrationPoints
                            .add({'distance': distance, 'liters': liters});
                      } else {
                        calibrationPoints[index] = {
                          'distance': distance,
                          'liters': liters
                        };
                      }
                      // Ordenar por distancia
                      calibrationPoints.sort(
                          (a, b) => a['distance']!.compareTo(b['distance']!));
                    });
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Punto de calibración guardado',
                            style: TextStyle(color: Color(0xFF155263))),
                        backgroundColor: Colors.white,
                      ),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('Por favor ingresa valores válidos',
                            style: TextStyle(color: Colors.white)),
                        backgroundColor: colorPrimary,
                      ),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: colorPrimary),
                child: const Text('Guardar',
                    style: TextStyle(color: Colors.white)),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _clearAllDataAndNotify(BuildContext context) async {
    try {
      await MqttHiveService.clearAllData();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Datos borrados correctamente',
              style: TextStyle(color: Color(0xFF155263))),
          backgroundColor: Colors.white,
        ),
      );
    } catch (e) {
      debugPrint('[SETTINGS] ❌ Error borrando datos: $e');
    }
  }

  Future<void> _clearReportHistoryAndNotify() async {
    try {
      await EnhancedDailyReportService().clearReportHistory();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Historial de reportes borrado'),
          backgroundColor: Colors.red,
        ),
      );
    } catch (e) {
      debugPrint('[SETTINGS] ❌ Error borrando historial de reportes: $e');
    }
  }
}

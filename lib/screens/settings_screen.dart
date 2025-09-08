import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import '../services/mqtt_hive.dart';
import '../services/daily_report_service.dart';
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
  double tankCapacity = 1000.0; // litros
  final tankCapacityController = TextEditingController();

  // Configuración de umbrales para alertas
  double tankFullThreshold = 90.0; // %
  double voltageLowThreshold = 100.0; // V
  double humidityLowThreshold = 30.0; // %
  bool tankFullEnabled = true;
  bool voltageLowEnabled = true;
  bool humidityLowEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    voltageController.dispose();
    currentController.dispose();
    tankCapacityController.dispose();
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
      tankCapacity = settingsBox.get('tankCapacity', defaultValue: 1000.0);
      tankCapacityController.text = tankCapacity.toStringAsFixed(0);

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
    });
  }

  Future<void> _saveSettings() async {
    final currentContext = context;
    final settingsBox = Hive.box('settings');

    try {
      // Guardar valores nominales
      await settingsBox.put('nominalVoltage', nominalVoltage);
      await settingsBox.put('nominalCurrent', nominalCurrent);

      // Guardar configuraciones de la app
      await settingsBox.put('isSavingEnabled', isSavingEnabled);
      await settingsBox.put('autoConnect', autoConnect);
      await settingsBox.put('showNotifications', showNotifications);
      await settingsBox.put('mqttBroker', mqttBroker);
      await settingsBox.put('mqttPort', mqttPort);
      await settingsBox.put('mqttTopic', mqttTopic);

      // Guardar configuración del tanque
      await settingsBox.put('tankCapacity', tankCapacity);

      // Guardar configuración de umbrales para alertas
      await settingsBox.put('tankFullThreshold', tankFullThreshold);
      await settingsBox.put('voltageLowThreshold', voltageLowThreshold);
      await settingsBox.put('humidityLowThreshold', humidityLowThreshold);
      await settingsBox.put('tankFullEnabled', tankFullEnabled);
      await settingsBox.put('voltageLowEnabled', voltageLowEnabled);
      await settingsBox.put('humidityLowEnabled', humidityLowEnabled);

      // Guardar configuración de reportes diarios
      await settingsBox.put('dailyReportEnabled', dailyReportEnabled);
      await settingsBox.put('dailyReportHour', dailyReportTime.hour);
      await settingsBox.put('dailyReportMinute', dailyReportTime.minute);

      // Actualizar el servicio MQTT Hive inmediatamente
      MqttHiveService.toggleSaving(isSavingEnabled);

      // Programar o cancelar reporte diario
      await DailyReportService()
          .scheduleDailyReport(dailyReportTime, dailyReportEnabled);

      // 🔄 RECONECTAR MQTT CON NUEVA CONFIGURACIÓN INMEDIATAMENTE
      debugPrint('[SETTINGS] Aplicando nueva configuración MQTT...');
      await SingletonMqttService()
          .mqttClientService
          .reconnectWithNewConfig(SingletonMqttService().mqttService);
      debugPrint('[SETTINGS] ✅ Configuración MQTT aplicada exitosamente');

      // Mostrar SnackBar de éxito
      if (mounted) {
        ScaffoldMessenger.of(currentContext).showSnackBar(
          SnackBar(
            content: const Text('Configuración guardada y aplicada',
                style: TextStyle(color: Color(0xFF155263))),
            backgroundColor: Colors.white,
          ),
        );
      }
    } catch (e) {
      debugPrint('[SETTINGS] ❌ Error aplicando configuración MQTT: $e');
      // Mostrar error pero no bloquear el guardado
      if (mounted) {
        ScaffoldMessenger.of(currentContext).showSnackBar(
          SnackBar(
            content: Text('Configuración guardada, pero error en MQTT: $e',
                style: const TextStyle(color: Colors.white)),
            backgroundColor: Colors.orange,
          ),
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
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveSettings,
            tooltip: 'Guardar configuración',
          ),
        ],
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
            SwitchListTile(
              title: const Text('Guardar datos automáticamente'),
              subtitle:
                  const Text('Almacena los datos recibidos en el dispositivo'),
              value: isSavingEnabled,
              onChanged: (value) {
                setState(() {
                  isSavingEnabled = value;
                });
              },
              activeColor: colorAccent,
            ),
            const Divider(),
            ListTile(
              leading: Icon(Icons.delete_sweep, color: colorAccent),
              title: const Text('Borrar todos los datos'),
              subtitle:
                  const Text('Elimina todos los datos históricos almacenados'),
              onTap: _showClearDataDialog,
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
              controller: TextEditingController(text: mqttBroker),
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
                    controller:
                        TextEditingController(text: mqttPort.toString()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Tópico MQTT (Base)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.topic),
                helperText:
                    'Base: dropster/ → Crea: dropster/data y dropster/control',
              ),
              onChanged: (value) {
                mqttTopic = value;
              },
              controller: TextEditingController(text: mqttTopic),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorAccent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colorAccent.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tópicos utilizados:',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: colorText,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '📥 Datos: ${mqttTopic.replaceAll('/data', '')}/data',
                    style: TextStyle(
                        fontSize: 11, color: colorText.withOpacity(0.8)),
                  ),
                  Text(
                    '📤 Control: ${mqttTopic.replaceAll('/data', '')}/control',
                    style: TextStyle(
                        fontSize: 11, color: colorText.withOpacity(0.8)),
                  ),
                  Text(
                    '💓 Status: ${mqttTopic.replaceAll('/data', '')}/status',
                    style: TextStyle(
                        fontSize: 11, color: colorText.withOpacity(0.8)),
                  ),
                  Text(
                    '❤️ Heartbeat: ${mqttTopic.replaceAll('/data', '')}/heartbeat',
                    style: TextStyle(
                        fontSize: 11, color: colorText.withOpacity(0.8)),
                  ),
                ],
              ),
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
              leading: Icon(Icons.notification_important, color: colorAccent),
              title: const Text('Probar reporte diario'),
              subtitle: const Text('Generar notificación de reporte simulado'),
              trailing: const Icon(Icons.send, size: 16),
              onTap: _testDailyReport,
            ),
            const Divider(),
            ListTile(
              leading: Icon(Icons.today, color: colorAccent),
              title: const Text('Reporte del día actual'),
              subtitle: const Text('Generar reporte con datos actuales'),
              trailing: const Icon(Icons.assessment, size: 16),
              onTap: _generateCurrentDayReport,
            ),
            const Divider(),
            ListTile(
              leading: Icon(Icons.notifications_off, color: colorAccent),
              title: const Text('Borrar todas las notificaciones'),
              subtitle:
                  const Text('Elimina todas las notificaciones almacenadas'),
              onTap: _showClearNotificationsDialog,
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
              subtitle: Text('${tankCapacity.toStringAsFixed(0)} litros'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: _showTankCapacityDialog,
            ),
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
                          divisions: 30,
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
                  'Notificar cuando el voltaje baje de ${voltageLowThreshold.toStringAsFixed(0)}V'),
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
                          min: 50,
                          max: 150,
                          divisions: 100,
                          label: '${voltageLowThreshold.toStringAsFixed(0)}V',
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
                  'Notificar cuando la humedad baje de ${humidityLowThreshold.toStringAsFixed(1)}%'),
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
                          max: 50,
                          divisions: 40,
                          label: '${humidityLowThreshold.toStringAsFixed(1)}%',
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
          ],
        ),
      ),
    );
  }

  void _showClearDataDialog() {
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
                  await MqttHiveService.clearAllData();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Datos borrados correctamente',
                          style: TextStyle(color: Color(0xFF155263))),
                      backgroundColor: Colors.white,
                    ),
                  );
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

  void _showClearNotificationsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Borrar notificaciones'),
        content: const Text(
            '¿Estás seguro de que quieres borrar todas las notificaciones? Esta acción no se puede deshacer.'),
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
                  final box = await Hive.openBox('anomalies');
                  await box.clear();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text(
                          'Notificaciones borradas correctamente',
                          style: TextStyle(color: Color(0xFF155263))),
                      backgroundColor: Colors.white,
                    ),
                  );
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
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Ingresa la capacidad total del tanque en litros.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
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
                  if (capacity != null && capacity > 0) {
                    setState(() {
                      tankCapacity = capacity;
                    });
                    Navigator.pop(context);
                    _saveSettings();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('Capacidad del tanque actualizada',
                            style: TextStyle(color: Color(0xFF155263))),
                        backgroundColor: Colors.white,
                      ),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content:
                            Text('Por favor ingresa un valor válido mayor a 0'),
                        backgroundColor: Colors.red,
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
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
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
      _saveSettings();
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
    final reports = await DailyReportService().getReportHistory();

    if (mounted) {
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
                              Text(
                                  '⚡ Energía: ${energy.toStringAsFixed(2)} Wh'),
                              Text('💧 Agua: ${water.toStringAsFixed(2)} L'),
                              Text(
                                  '⚡ Eficiencia: ${efficiency.toStringAsFixed(3)} Wh/L'),
                            ],
                          ),
                          trailing: Icon(
                            efficiency > 0 ? Icons.check_circle : Icons.warning,
                            color:
                                efficiency > 0 ? Colors.green : Colors.orange,
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
              child:
                  const Text('Cerrar', style: TextStyle(color: Colors.white)),
            ),
            if (reports.isNotEmpty)
              TextButton(
                onPressed: () async {
                  await DailyReportService().clearReportHistory();
                  Navigator.pop(currentContext);
                  if (mounted) {
                    ScaffoldMessenger.of(currentContext).showSnackBar(
                      const SnackBar(
                        content: Text('Historial de reportes borrado'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                },
                child: const Text('Borrar Historial',
                    style: TextStyle(color: Colors.red)),
              ),
          ],
        ),
      );
    }
  }



  void _testDailyReport() async {
    try {
      debugPrint('🧪 Iniciando prueba de reporte diario...');
      await DailyReportService().generateTestReport();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Reporte de prueba enviado',
                style: TextStyle(color: Color(0xFF155263))),
            backgroundColor: Colors.white,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error en prueba de reporte: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error en prueba: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _generateCurrentDayReport() async {
    try {
      debugPrint('📊 Generando reporte del día actual...');
      await DailyReportService().generateCurrentDayReport();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Reporte del día actual enviado',
                style: TextStyle(color: Color(0xFF155263))),
            backgroundColor: Colors.white,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error generando reporte del día actual: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error generando reporte: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

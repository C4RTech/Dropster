import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../services/mqtt_hive.dart';

/// Gestiona la carga y guardado de configuraciones en Hive
class SettingsDataManager {
  // Valores nominales
  double nominalVoltage = 110.0;
  double nominalCurrent = 10.0;

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
  double tankCapacity = 20.0;
  bool isCalibrated = false;
  List<Map<String, double>> calibrationPoints = [];
  double ultrasonicOffset = 0.0;

  // Configuración de umbrales para alertas
  double tankFullThreshold = 90.0;
  double voltageLowThreshold = 100.0;
  double humidityLowThreshold = 30.0;
  bool tankFullEnabled = true;
  bool voltageLowEnabled = true;
  bool humidityLowEnabled = true;

  // Parámetros de control del ESP32
  double controlDeadband = 3.0;
  int controlMinOff = 60;
  int controlMaxOn = 1800;
  int controlSampling = 8;
  double controlAlpha = 0.2;
  double maxCompressorTemp = 95.0;
  int displayTimeoutMinutes = 0;

  /// Carga todas las configuraciones desde Hive
  Future<void> loadSettings() async {
    await MqttHiveService.initHive();

    if (!Hive.isBoxOpen('settings')) {
      await Hive.openBox('settings');
    }
    final settingsBox = Hive.box('settings');

    // Valores nominales
    nominalVoltage = settingsBox.get('nominalVoltage', defaultValue: 110.0);
    nominalCurrent = settingsBox.get('nominalCurrent', defaultValue: 10.0);

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
    isCalibrated = settingsBox.get('isCalibrated', defaultValue: false);
    calibrationPoints =
        (settingsBox.get('calibrationPoints', defaultValue: []) as List)
            .map((point) => Map<String, double>.from(point as Map))
            .toList();
    ultrasonicOffset = settingsBox.get('ultrasonicOffset', defaultValue: 0.0);

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
  }

  /// Guarda todas las configuraciones en Hive
  Future<void> saveSettings() async {
    final settingsBox = Hive.box('settings');

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
    await settingsBox.put('isCalibrated', isCalibrated);
    await settingsBox.put('calibrationPoints', calibrationPoints);
    await settingsBox.put('ultrasonicOffset', ultrasonicOffset);

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

    // Guardar configuración de parámetros de control
    await settingsBox.put('controlDeadband', controlDeadband);
    await settingsBox.put('controlMinOff', controlMinOff);
    await settingsBox.put('controlMaxOn', controlMaxOn);
    await settingsBox.put('controlSampling', controlSampling);
    await settingsBox.put('controlAlpha', controlAlpha);
    await settingsBox.put('maxCompressorTemp', maxCompressorTemp);
    await settingsBox.put('displayTimeoutMinutes', displayTimeoutMinutes);

    // Actualizar el servicio MQTT Hive inmediatamente
    MqttHiveService.toggleSaving(isSavingEnabled);
  }

  /// Obtiene un mapa con todas las configuraciones actuales
  Map<String, dynamic> getCurrentSettings() {
    return {
      'nominalVoltage': nominalVoltage,
      'nominalCurrent': nominalCurrent,
      'isSavingEnabled': isSavingEnabled,
      'autoConnect': autoConnect,
      'showNotifications': showNotifications,
      'dailyReportEnabled': dailyReportEnabled,
      'dailyReportTime': dailyReportTime,
      'mqttBroker': mqttBroker,
      'mqttPort': mqttPort,
      'mqttTopic': mqttTopic,
      'tankCapacity': tankCapacity,
      'isCalibrated': isCalibrated,
      'calibrationPoints': calibrationPoints,
      'ultrasonicOffset': ultrasonicOffset,
      'tankFullThreshold': tankFullThreshold,
      'voltageLowThreshold': voltageLowThreshold,
      'humidityLowThreshold': humidityLowThreshold,
      'tankFullEnabled': tankFullEnabled,
      'voltageLowEnabled': voltageLowEnabled,
      'humidityLowEnabled': humidityLowEnabled,
      'controlDeadband': controlDeadband,
      'controlMinOff': controlMinOff,
      'controlMaxOn': controlMaxOn,
      'controlSampling': controlSampling,
      'controlAlpha': controlAlpha,
      'maxCompressorTemp': maxCompressorTemp,
      'displayTimeoutMinutes': displayTimeoutMinutes,
    };
  }

  /// Actualiza una configuración específica
  void updateSetting(String key, dynamic value) {
    switch (key) {
      case 'nominalVoltage':
        nominalVoltage = value as double;
        break;
      case 'nominalCurrent':
        nominalCurrent = value as double;
        break;
      case 'isSavingEnabled':
        isSavingEnabled = value as bool;
        break;
      case 'autoConnect':
        autoConnect = value as bool;
        break;
      case 'showNotifications':
        showNotifications = value as bool;
        break;
      case 'dailyReportEnabled':
        dailyReportEnabled = value as bool;
        break;
      case 'dailyReportTime':
        dailyReportTime = value as TimeOfDay;
        break;
      case 'mqttBroker':
        mqttBroker = value as String;
        break;
      case 'mqttPort':
        mqttPort = value as int;
        break;
      case 'mqttTopic':
        mqttTopic = value as String;
        break;
      case 'tankCapacity':
        tankCapacity = value as double;
        break;
      case 'isCalibrated':
        isCalibrated = value as bool;
        break;
      case 'calibrationPoints':
        calibrationPoints = value as List<Map<String, double>>;
        break;
      case 'ultrasonicOffset':
        ultrasonicOffset = value as double;
        break;
      case 'tankFullThreshold':
        tankFullThreshold = value as double;
        break;
      case 'voltageLowThreshold':
        voltageLowThreshold = value as double;
        break;
      case 'humidityLowThreshold':
        humidityLowThreshold = value as double;
        break;
      case 'tankFullEnabled':
        tankFullEnabled = value as bool;
        break;
      case 'voltageLowEnabled':
        voltageLowEnabled = value as bool;
        break;
      case 'humidityLowEnabled':
        humidityLowEnabled = value as bool;
        break;
      case 'controlDeadband':
        controlDeadband = value as double;
        break;
      case 'controlMinOff':
        controlMinOff = value as int;
        break;
      case 'controlMaxOn':
        controlMaxOn = value as int;
        break;
      case 'controlSampling':
        controlSampling = value as int;
        break;
      case 'controlAlpha':
        controlAlpha = value as double;
        break;
      case 'maxCompressorTemp':
        maxCompressorTemp = value as double;
        break;
      case 'displayTimeoutMinutes':
        displayTimeoutMinutes = value as int;
        break;
    }
  }
}

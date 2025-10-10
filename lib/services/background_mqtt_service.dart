import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'mqtt_service.dart';
import 'mqtt_hive.dart';

/// Servicio simplificado de background para mantener la conexión MQTT activa
/// Funciona tanto en foreground como en background usando timers eficientes
class BackgroundMqttService {
  static final BackgroundMqttService _instance =
      BackgroundMqttService._internal();
  factory BackgroundMqttService() => _instance;

  BackgroundMqttService._internal();

  MqttService? _mqttService;
  Timer? _healthCheckTimer;
  Timer? _dailyReportTimer;
  bool _isInitialized = false;
  bool _isInBackground = false;

  /// Inicializa el servicio de background
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Inicializar Hive si no está abierto
      if (!Hive.isBoxOpen('settings')) {
        final appDir = await getApplicationDocumentsDirectory();
        Hive.init(appDir.path);
        await MqttHiveService.initHive();
      }

      // Inicializar servicio MQTT
      await _initializeMqttService();

      // Iniciar timers para tareas periódicas
      _startPeriodicTasks();

      _isInitialized = true;
      print('[BACKGROUND] Servicio de background MQTT inicializado');
    } catch (e) {
      print('[BACKGROUND] Error inicializando servicio de background: $e');
    }
  }

  /// Inicializa el servicio MQTT
  Future<void> _initializeMqttService() async {
    try {
      _mqttService = MqttService();
      await _mqttService!.loadConfiguration();

      // Conectar inicialmente
      await _mqttService!.connect(null);

      print('[BACKGROUND] Servicio MQTT inicializado');
    } catch (e) {
      print('[BACKGROUND] Error inicializando MQTT: $e');
    }
  }

  /// Inicia las tareas periódicas
  void _startPeriodicTasks() {
    // Verificación de salud cada 2 minutos
    _healthCheckTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      _performHealthCheck();
    });

    // Reporte diario a las 8 AM
    _scheduleDailyReport();
  }

  /// Programa el reporte diario
  void _scheduleDailyReport() {
    final now = DateTime.now();
    final targetTime = DateTime(now.year, now.month, now.day, 8, 0, 0);

    Duration delay;
    if (now.isAfter(targetTime)) {
      // Si ya pasó la hora objetivo hoy, programar para mañana
      delay = targetTime.add(const Duration(days: 1)).difference(now);
    } else {
      // Programar para hoy
      delay = targetTime.difference(now);
    }

    _dailyReportTimer = Timer(delay, () {
      _generateDailyReport();
      // Reprogramar para el próximo día
      _scheduleDailyReport();
    });
  }

  /// Asegura que la conexión MQTT esté activa
  Future<void> _ensureMqttConnection() async {
    try {
      if (_mqttService == null) {
        await _initializeMqttService();
        return;
      }

      if (!(_mqttService?.isConnected ?? false)) {
        print('[BACKGROUND] Reconectando MQTT...');
        await _mqttService?.connect(null);
      }
    } catch (e) {
      print('[BACKGROUND] Error asegurando conexión MQTT: $e');
    }
  }

  /// Realiza verificación de salud
  Future<void> _performHealthCheck() async {
    try {
      // Verificar conexión MQTT
      if (!(_mqttService?.isConnected ?? false)) {
        print('[HEALTH CHECK] MQTT desconectado, intentando reconectar...');
        await _ensureMqttConnection();
      }

      // Verificar que Hive esté funcionando
      if (!Hive.isBoxOpen('energyData')) {
        print('[HEALTH CHECK] Reinicializando Hive...');
        await MqttHiveService.initHive();
      }

      print('[HEALTH CHECK] Verificación completada exitosamente');
    } catch (e) {
      print('[HEALTH CHECK] Error en verificación de salud: $e');
    }
  }

  /// Genera reporte diario
  Future<void> _generateDailyReport() async {
    try {
      if (!Hive.isBoxOpen('energyData')) return;

      final dataBox = Hive.box<Map>('energyData');
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      final dayData = dataBox.values.whereType<Map>().where((data) {
        final timestamp = data['timestamp'];
        if (timestamp == null) return false;
        final dataTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
        return dataTime.isAfter(startOfDay) && dataTime.isBefore(endOfDay);
      }).toList();

      if (dayData.isEmpty) {
        print('[DAILY REPORT] No hay datos para generar reporte');
        return;
      }

      // Calcular estadísticas
      double totalEnergy = 0.0;
      double totalWater = 0.0;

      for (final data in dayData) {
        final energy = _parseDouble(data['energia']) ?? 0.0;
        final water = _parseDouble(data['aguaAlmacenada']) ?? 0.0;

        totalEnergy += energy;
        totalWater += water;
      }

      final averageEfficiency = totalWater > 0 ? totalEnergy / totalWater : 0.0;

      // Guardar reporte
      final reportBox = await Hive.openBox('dailyReports');
      final report = {
        'date': today.millisecondsSinceEpoch,
        'totalEnergy': totalEnergy,
        'totalWater': totalWater,
        'averageEfficiency': averageEfficiency,
        'dataPoints': dayData.length,
        'generatedAt': DateTime.now().millisecondsSinceEpoch,
      };

      await reportBox.put(today.millisecondsSinceEpoch.toString(), report);

      print(
          '[DAILY REPORT] Reporte generado: ${totalEnergy.toStringAsFixed(2)} kWh, ${totalWater.toStringAsFixed(2)} L');
    } catch (e) {
      print('[DAILY REPORT] Error generando reporte: $e');
    }
  }

  /// Parsea double de forma segura
  double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  /// Configura el modo background/foreground
  void setBackgroundMode(bool isBackground) {
    _isInBackground = isBackground;
    print('[BACKGROUND] Modo background: $isBackground');

    // Ajustar frecuencia de verificaciones según el modo
    if (isBackground) {
      // En background, reducir frecuencia para ahorrar batería
      _healthCheckTimer?.cancel();
      _healthCheckTimer = Timer.periodic(const Duration(minutes: 5), (_) {
        _performHealthCheck();
      });
    } else {
      // En foreground, aumentar frecuencia para mejor responsiveness
      _healthCheckTimer?.cancel();
      _healthCheckTimer = Timer.periodic(const Duration(minutes: 2), (_) {
        _performHealthCheck();
      });
    }
  }

  /// Obtiene estadísticas del servicio
  Map<String, dynamic> getStats() {
    return {
      'isInitialized': _isInitialized,
      'isInBackground': _isInBackground,
      'mqttConnected': _mqttService?.isConnected ?? false,
      'lastHealthCheck': DateTime.now().millisecondsSinceEpoch,
    };
  }

  /// Libera recursos
  void dispose() {
    _healthCheckTimer?.cancel();
    _dailyReportTimer?.cancel();
    _mqttService?.disconnect();
    _isInitialized = false;
  }
}

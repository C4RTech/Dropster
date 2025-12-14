import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'mqtt_hive.dart';
import 'singleton_mqtt_service.dart';
import 'notification_service.dart';
import 'enhanced_daily_report_service_refactored.dart';
import 'error_handler_service.dart';

/// Servicio unificado para inicializar todos los componentes de la aplicación
class AppInitializationService {
  static final AppInitializationService _instance =
      AppInitializationService._internal();
  factory AppInitializationService() => _instance;
  AppInitializationService._internal();

  bool _isInitialized = false;
  bool _hiveInitialized = false;
  bool _mqttInitialized = false;
  bool _notificationsInitialized = false;
  bool _reportsInitialized = false;

  /// Estado de inicialización general
  bool get isInitialized => _isInitialized;

  /// Inicializar todos los servicios de la aplicación
  Future<void> initializeAll({
    required Function(String) onProgressUpdate,
  }) async {
    if (_isInitialized) return;

    try {
      // Paso 1: Inicializar Flutter binding
      onProgressUpdate("Preparando aplicación...");
      WidgetsFlutterBinding.ensureInitialized();
      await Future.delayed(const Duration(milliseconds: 300));

      // Paso 2: Inicializar Hive
      await _initializeHive(onProgressUpdate);

      // Paso 3: Inicializar notificaciones
      await _initializeNotifications(onProgressUpdate);

      // Paso 4: Inicializar reportes diarios
      await _initializeReports(onProgressUpdate);

      // Paso 5: Inicializar MQTT (opcional - puede fallar)
      await _initializeMqtt(onProgressUpdate);

      _isInitialized = true;
      onProgressUpdate("¡Listo para comenzar!");
    } catch (e) {
      ErrorHandlerService().logError('App Initialization General', e);
      // No fallar completamente, permitir que la app funcione sin algunos servicios
      _isInitialized = true;
      onProgressUpdate("Inicialización completada con advertencias");
    }
  }

  /// Inicializar solo Hive y servicios básicos (para uso en MainScreen)
  Future<void> initializeBasic() async {
    if (_hiveInitialized) return;

    try {
      WidgetsFlutterBinding.ensureInitialized();
      final dir = await getApplicationDocumentsDirectory();
      await Hive.initFlutter(dir.path);
      await MqttHiveService.initHive();
      _hiveInitialized = true;
      debugPrint('[APP INIT] Hive inicializado correctamente');
    } catch (e) {
      ErrorHandlerService().logError('Hive Initialization', e);
      rethrow;
    }
  }

  /// Inicializar MQTT (puede ser llamado desde MainScreen)
  Future<void> initializeMqtt() async {
    if (_mqttInitialized) return;

    try {
      await SingletonMqttService().connect();
      _mqttInitialized = true;
      debugPrint('[APP INIT] ✅ Conexión MQTT inicializada');
    } catch (e) {
      ErrorHandlerService().logError('MQTT Initialization', e);
      // No rethrow - permitir que la app funcione sin MQTT
    }
  }

  Future<void> _initializeHive(Function(String) onProgressUpdate) async {
    onProgressUpdate("Configurando base de datos...");
    final dir = await getApplicationDocumentsDirectory();
    await Hive.initFlutter(dir.path);
    await MqttHiveService.initHive();
    _hiveInitialized = true;
    await Future.delayed(const Duration(milliseconds: 300));
  }

  Future<void> _initializeNotifications(
      Function(String) onProgressUpdate) async {
    onProgressUpdate("Configurando notificaciones...");
    try {
      await NotificationService().initialize();
      final hasPermission = await NotificationService().checkPermissions();
      if (!hasPermission) {
        await NotificationService().requestPermissions();
      }
      _notificationsInitialized = true;
      debugPrint('[APP INIT] Servicio de notificaciones inicializado');
    } catch (e) {
      ErrorHandlerService().logError('Notifications Initialization', e);
    }
    await Future.delayed(const Duration(milliseconds: 300));
  }

  Future<void> _initializeReports(Function(String) onProgressUpdate) async {
    onProgressUpdate("Configurando reportes diarios...");
    try {
      await EnhancedDailyReportServiceRefactored().initialize();

      // Cargar configuración de reportes diarios
      final settingsBox = await Hive.openBox('settings');
      final dailyReportEnabled =
          settingsBox.get('dailyReportEnabled', defaultValue: false);
      if (dailyReportEnabled) {
        final hour = settingsBox.get('dailyReportHour', defaultValue: 20);
        final minute = settingsBox.get('dailyReportMinute', defaultValue: 0);
        final reportTime = TimeOfDay(hour: hour, minute: minute);
        await EnhancedDailyReportServiceRefactored()
            .scheduleDailyReport(reportTime, true);
        debugPrint(
            '[APP INIT] Reporte diario programado para ${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}');
      }
      _reportsInitialized = true;
      debugPrint('[APP INIT] Servicio de reportes diarios inicializado');
    } catch (e) {
      ErrorHandlerService().logError('Daily Reports Initialization', e);
    }
    await Future.delayed(const Duration(milliseconds: 300));
  }

  Future<void> _initializeMqtt(Function(String) onProgressUpdate) async {
    onProgressUpdate("Conectando servicios...");
    try {
      await SingletonMqttService().connect();
      _mqttInitialized = true;
      debugPrint('[APP INIT] ✅ Conexión MQTT inicializada');
    } catch (e) {
      ErrorHandlerService().logError('MQTT Initialization', e);
      debugPrint(
          '[APP INIT] ⚠️ MQTT no disponible, app funcionará sin conexión');
    }
  }

  /// Obtener estado de inicialización
  Map<String, bool> getInitializationStatus() {
    return {
      'hive': _hiveInitialized,
      'mqtt': _mqttInitialized,
      'notifications': _notificationsInitialized,
      'reports': _reportsInitialized,
      'overall': _isInitialized,
    };
  }

  /// Resetear estado (útil para testing)
  void reset() {
    _isInitialized = false;
    _hiveInitialized = false;
    _mqttInitialized = false;
    _notificationsInitialized = false;
    _reportsInitialized = false;
  }
}

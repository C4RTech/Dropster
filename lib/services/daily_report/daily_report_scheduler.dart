import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import '../notification_service.dart';
import '../enhanced_daily_report_service_refactored.dart';

/// Gestiona la programación de reportes diarios automáticos
class DailyReportScheduler {
  static const int _alarmId = 1001;
  static const int _backupAlarmId = 1002;

  /// Programar reporte diario automático
  Future<void> scheduleDailyReport(TimeOfDay time, bool enabled) async {
    try {
      // Cancelar alarmas existentes
      await AndroidAlarmManager.cancel(_alarmId);
      await AndroidAlarmManager.cancel(_backupAlarmId);

      if (!enabled) {
        debugPrint('📅 Reporte diario automático deshabilitado');
        return;
      }

      // Calcular próxima ejecución
      final nextRun = _calculateNextRun(time);

      // Programar alarma principal
      final success = await AndroidAlarmManager.oneShotAt(
        nextRun,
        _alarmId,
        _dailyReportCallback,
        exact: true,
        allowWhileIdle: true,
        rescheduleOnReboot: true,
      );

      // Programar alarma de respaldo (5 minutos después)
      final backupTime = nextRun.add(const Duration(minutes: 5));
      await AndroidAlarmManager.oneShotAt(
        backupTime,
        _backupAlarmId,
        _backupReportCallback,
        exact: true,
        allowWhileIdle: true,
        rescheduleOnReboot: true,
      );

      if (success) {
        debugPrint('📅 ✅ Reporte diario programado exitosamente');
        debugPrint(
            '📅 ⏰ Próximo reporte: ${DateFormat('dd/MM/yyyy HH:mm').format(nextRun)}');
      } else {
        debugPrint('📅 ❌ Error al programar reporte diario');
        throw Exception('No se pudo programar la alarma del reporte diario');
      }
    } catch (e) {
      debugPrint('📅 ❌ Error en scheduleDailyReport: $e');
      rethrow;
    }
  }

  /// Calcular próxima ejecución del reporte
  DateTime _calculateNextRun(TimeOfDay time) {
    final now = DateTime.now();
    var nextRun =
        DateTime(now.year, now.month, now.day, time.hour, time.minute);

    // Si ya pasó la hora de hoy, programar para mañana
    if (nextRun.isBefore(now)) {
      nextRun = nextRun.add(const Duration(days: 1));
      debugPrint(
          '📅 Hora ya pasó hoy, programando para mañana: ${DateFormat('dd/MM/yyyy HH:mm').format(nextRun)}');
    } else {
      debugPrint(
          '📅 Programando para hoy: ${DateFormat('dd/MM/yyyy HH:mm').format(nextRun)}');
    }

    return nextRun;
  }

  /// Cancelar todas las alarmas de reportes
  Future<void> cancelAllAlarms() async {
    await AndroidAlarmManager.cancel(_alarmId);
    await AndroidAlarmManager.cancel(_backupAlarmId);
    debugPrint('📅 Alarmas de reporte diario canceladas');
  }

  /// Obtener estado de las alarmas
  Future<Map<String, dynamic>> getAlarmStatus() async {
    // Esta información no está disponible directamente en Android Alarm Manager
    // Podríamos mantener un estado interno si es necesario
    return {
      'primaryAlarmId': _alarmId,
      'backupAlarmId': _backupAlarmId,
      'alarmsActive': true, // Asumimos que están activas si no se cancelaron
    };
  }
}

// Callbacks que necesitan estar en el scope global
@pragma('vm:entry-point')
Future<void> _dailyReportCallback() async {
  debugPrint('📅 ⏰ ¡Es hora del reporte diario! (ejecutándose en background)');

  try {
    // Inicializar servicios necesarios para el background
    WidgetsFlutterBinding.ensureInitialized();

    // Inicializar datos de localización para español
    await initializeDateFormatting('es');

    // Inicializar Hive
    final dir = await getApplicationDocumentsDirectory();
    await Hive.initFlutter(dir.path);

    // Inicializar servicios
    final notificationService = NotificationService();
    await notificationService.initialize();

    // Verificar permisos de notificación
    final hasPermissions = await notificationService.checkPermissions();
    if (!hasPermissions) {
      debugPrint('📅 ⚠️ No hay permisos de notificación, cancelando reporte');
      return;
    }

    // Generar reporte
    final service = EnhancedDailyReportServiceRefactored();
    await service.generateDailyReport();

    // Programar siguiente reporte
    Box settingsBox;
    if (Hive.isBoxOpen('settings')) {
      settingsBox = Hive.box('settings');
    } else {
      settingsBox = await Hive.openBox('settings');
    }
    final enabled = settingsBox.get('dailyReportEnabled', defaultValue: false);
    final hour = settingsBox.get('dailyReportHour', defaultValue: 20);
    final minute = settingsBox.get('dailyReportMinute', defaultValue: 0);
    final reportTime = TimeOfDay(hour: hour, minute: minute);

    if (enabled) {
      await service.scheduleDailyReport(reportTime, true);
    }

    debugPrint('📅 ✅ Callback de reporte diario ejecutado');
  } catch (e) {
    debugPrint('📅 ❌ Error en callback de reporte diario: $e');
  }
}

@pragma('vm:entry-point')
Future<void> _backupReportCallback() async {
  debugPrint('📅 🔄 Ejecutando callback de respaldo...');

  try {
    // Inicializar servicios necesarios para el background
    WidgetsFlutterBinding.ensureInitialized();

    // Inicializar datos de localización para español
    await initializeDateFormatting('es');

    // Inicializar Hive
    final dir = await getApplicationDocumentsDirectory();
    await Hive.initFlutter(dir.path);

    // Inicializar servicios
    final notificationService = NotificationService();
    await notificationService.initialize();

    // Verificar permisos de notificación
    final hasPermissions = await notificationService.checkPermissions();
    if (!hasPermissions) {
      debugPrint(
          '📅 🔄 ⚠️ No hay permisos de notificación en respaldo, cancelando');
      return;
    }

    // Generar reporte
    final service = EnhancedDailyReportServiceRefactored();
    await service.generateDailyReport();

    // Programar siguiente reporte
    Box settingsBox;
    if (Hive.isBoxOpen('settings')) {
      settingsBox = Hive.box('settings');
    } else {
      settingsBox = await Hive.openBox('settings');
    }
    final enabled = settingsBox.get('dailyReportEnabled', defaultValue: false);
    final hour = settingsBox.get('dailyReportHour', defaultValue: 20);
    final minute = settingsBox.get('dailyReportMinute', defaultValue: 0);
    final reportTime = TimeOfDay(hour: hour, minute: minute);

    if (enabled) {
      await service.scheduleDailyReport(reportTime, true);
    }

    debugPrint('📅 ✅ Callback de respaldo ejecutado');
  } catch (e) {
    debugPrint('📅 ❌ Error en callback de respaldo: $e');
  }
}

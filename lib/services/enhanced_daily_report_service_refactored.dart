import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:path_provider/path_provider.dart';
import 'daily_report/daily_report_scheduler.dart';
import 'daily_report/daily_report_data_analyzer.dart';
import 'daily_report/daily_report_generator.dart';
import 'daily_report/daily_report_notifier.dart';
import 'daily_report/daily_report_storage.dart';
import 'notification_service.dart';

/// Servicio refactorizado de reportes diarios que utiliza módulos especializados
/// para mantener la separación de responsabilidades y facilitar el mantenimiento
class EnhancedDailyReportServiceRefactored {
  static final EnhancedDailyReportServiceRefactored _instance =
      EnhancedDailyReportServiceRefactored._internal();
  factory EnhancedDailyReportServiceRefactored() => _instance;
  EnhancedDailyReportServiceRefactored._internal();

  // Módulos especializados
  final DailyReportScheduler _scheduler = DailyReportScheduler();
  final DailyReportDataAnalyzer _dataAnalyzer = DailyReportDataAnalyzer();
  final DailyReportGenerator _reportGenerator = DailyReportGenerator();
  final DailyReportNotifier _notifier = DailyReportNotifier();
  final DailyReportStorage _storage = DailyReportStorage();

  bool _isInitialized = false;
  DateTime? _lastReportDate;
  Timer? _periodicCheckTimer;

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Inicializar servicios necesarios
      await NotificationService().initialize();
      _isInitialized = true;

      // Iniciar verificación periódica como respaldo
      _startPeriodicCheck();

      debugPrint(
          '📊 ✅ Enhanced Daily Report Service refactorizado inicializado');
    } catch (e) {
      debugPrint('📊 ❌ Error inicializando Enhanced Daily Report Service: $e');
    }
  }

  /// Programar reporte diario automático
  Future<void> scheduleDailyReport(TimeOfDay time, bool enabled) async {
    await _scheduler.scheduleDailyReport(time, enabled);
  }

  /// Generar reporte diario profesional
  Future<void> generateDailyReport() async {
    try {
      debugPrint('📊 🚀 Iniciando generación de reporte diario profesional...');

      // Verificar si las notificaciones están habilitadas
      Box settingsBox;
      if (Hive.isBoxOpen('settings')) {
        settingsBox = Hive.box('settings');
      } else {
        settingsBox = await Hive.openBox('settings');
      }
      final showNotifications =
          settingsBox.get('showNotifications', defaultValue: true);

      if (!showNotifications) {
        debugPrint('📊 ⚠️ Notificaciones deshabilitadas, cancelando reporte');
        return;
      }

      // Obtener datos del día anterior
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final reportData = await _dataAnalyzer.analyzeDayData(yesterday);

      // Generar reporte profesional
      final report = await _reportGenerator.generateProfessionalReport(
          yesterday, reportData);

      // Enviar notificación profesional
      await _notifier.sendProfessionalNotification(report);

      // Guardar en historial
      await _storage.saveReportToHistory(yesterday, report);

      // Actualizar fecha del último reporte
      _lastReportDate = yesterday;

      debugPrint('📊 ✅ Reporte diario profesional generado exitosamente');
    } catch (e) {
      debugPrint('📊 ❌ Error generando reporte diario: $e');
      await _notifier
          .sendErrorNotification('Error generando reporte diario: $e');
    }
  }

  /// Generar reporte del día actual
  Future<void> generateCurrentDayReport() async {
    try {
      debugPrint('📊 Generando reporte del día actual...');

      // Inicializar datos de localización para español
      await initializeDateFormatting('es');

      final today = DateTime.now();
      debugPrint(
          '📊 Fecha actual: ${DateFormat('dd/MM/yyyy HH:mm:ss').format(today)}');

      final reportData = await _dataAnalyzer.analyzeDayData(today);
      debugPrint('📊 Datos analizados: $reportData');

      final report =
          await _reportGenerator.generateProfessionalReport(today, reportData);
      debugPrint('📊 Reporte generado: $report');

      await _notifier.sendProfessionalNotification(report);
      debugPrint('📊 Notificación enviada');

      await _storage.saveReportToHistory(today, report);
      debugPrint('📊 Reporte guardado en historial');

      debugPrint('📊 ✅ Reporte del día actual generado');
    } catch (e, stackTrace) {
      debugPrint('📊 ❌ Error generando reporte del día actual: $e');
      debugPrint('📊 StackTrace: $stackTrace');
      await _notifier
          .sendErrorNotification('Error generando reporte del día actual: $e');
    }
  }

  /// Iniciar verificación periódica como respaldo
  void _startPeriodicCheck() {
    _periodicCheckTimer?.cancel();
    _periodicCheckTimer = Timer.periodic(const Duration(hours: 1), (timer) {
      _checkPendingReports();
    });
  }

  /// Verificar reportes pendientes
  Future<void> _checkPendingReports() async {
    try {
      Box settingsBox;
      if (Hive.isBoxOpen('settings')) {
        settingsBox = Hive.box('settings');
      } else {
        settingsBox = await Hive.openBox('settings');
      }
      final enabled =
          settingsBox.get('dailyReportEnabled', defaultValue: false);

      if (!enabled) return;

      final hour = settingsBox.get('dailyReportHour', defaultValue: 20);
      final minute = settingsBox.get('dailyReportMinute', defaultValue: 0);
      final reportTime = TimeOfDay(hour: hour, minute: minute);

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final reportDateTime = DateTime(today.year, today.month, today.day,
          reportTime.hour, reportTime.minute);

      // Si ya pasó la hora del reporte y no se ha generado hoy
      if (now.isAfter(reportDateTime) &&
          (_lastReportDate == null || !_isSameDay(_lastReportDate!, today))) {
        debugPrint('📅 🔄 Generando reporte pendiente...');
        await generateDailyReport();
      }
    } catch (e) {
      debugPrint('📅 ❌ Error en verificación periódica: $e');
    }
  }

  /// Verificar si es el mismo día
  bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }

  /// Obtener historial de reportes
  Future<List<Map>> getReportHistory() async {
    return await _storage.getReportHistory();
  }

  /// Limpiar historial de reportes
  Future<void> clearReportHistory() async {
    await _storage.clearReportHistory();
  }

  /// Obtener estado del servicio
  Future<Map<String, dynamic>> getServiceStatus() async {
    final now = DateTime.now();
    Box settingsBox;
    if (Hive.isBoxOpen('settings')) {
      settingsBox = Hive.box('settings');
    } else {
      settingsBox = await Hive.openBox('settings');
    }
    final enabled = settingsBox.get('dailyReportEnabled', defaultValue: false);

    if (!enabled) {
      return {
        'enabled': false,
        'nextReport': null,
        'lastReport': null,
        'status': 'disabled'
      };
    }

    final hour = settingsBox.get('dailyReportHour', defaultValue: 20);
    final minute = settingsBox.get('dailyReportMinute', defaultValue: 0);
    final reportTime = TimeOfDay(hour: hour, minute: minute);

    var nextRun = DateTime(
        now.year, now.month, now.day, reportTime.hour, reportTime.minute);
    if (nextRun.isBefore(now)) {
      nextRun = nextRun.add(const Duration(days: 1));
    }

    // Obtener último reporte
    final reports = await getReportHistory();
    final lastReport = reports.isNotEmpty ? reports.first : null;

    return {
      'enabled': true,
      'nextReport': nextRun.millisecondsSinceEpoch,
      'lastReport': lastReport,
      'status': 'active',
      'reportTime':
          '${reportTime.hour.toString().padLeft(2, '0')}:${reportTime.minute.toString().padLeft(2, '0')}'
    };
  }

  /// Dispose del servicio
  void dispose() {
    _periodicCheckTimer?.cancel();
    _scheduler.cancelAllAlarms();
  }
}

// Callbacks que necesitan estar en el scope global
@pragma('vm:entry-point')
Future<void> enhancedDailyReportCallback() async {
  debugPrint(
      '📅 ⏰ ¡Es hora del reporte diario refactorizado! (ejecutándose en background)');

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
          '📅 ⚠️ No hay permisos de notificación en callback refactorizado, cancelando');
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

    debugPrint('📅 ✅ Reporte diario refactorizado completado');
  } catch (e) {
    debugPrint('📅 ❌ Error en callback de reporte diario: $e');
  }
}

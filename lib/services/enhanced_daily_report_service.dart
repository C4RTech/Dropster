import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../services/notification_service.dart';

/// Servicio mejorado para reportes diarios automáticos con notificaciones profesionales
class EnhancedDailyReportService {
  static final EnhancedDailyReportService _instance =
      EnhancedDailyReportService._internal();
  factory EnhancedDailyReportService() => _instance;
  EnhancedDailyReportService._internal();

  static const int _alarmId =
      1001; // ID único para la alarma del reporte diario
  static const int _backupAlarmId = 1002; // ID de respaldo
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

      debugPrint('📊 ✅ Enhanced Daily Report Service inicializado');
    } catch (e) {
      debugPrint('📊 ❌ Error inicializando Enhanced Daily Report Service: $e');
    }
  }

  /// Programar reporte diario automático
  Future<void> scheduleDailyReport(TimeOfDay time, bool enabled) async {
    try {
      await initialize();

      // Cancelar alarmas existentes
      await AndroidAlarmManager.cancel(_alarmId);
      await AndroidAlarmManager.cancel(_backupAlarmId);

      if (!enabled) {
        debugPrint('📅 Reporte diario automático deshabilitado');
        return;
      }

      // Calcular próxima ejecución
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

      // Programar alarma principal
      final success = await AndroidAlarmManager.oneShotAt(
        nextRun,
        _alarmId,
        _enhancedDailyReportCallback,
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
      final reportData = await _analyzeDayData(yesterday);

      // Generar reporte profesional
      final report = await _generateProfessionalReport(yesterday, reportData);

      // Enviar notificación profesional
      await _sendProfessionalNotification(report);

      // Guardar en historial
      await _saveReportToHistory(yesterday, report);

      // Actualizar fecha del último reporte
      _lastReportDate = yesterday;

      debugPrint('📊 ✅ Reporte diario profesional generado exitosamente');
    } catch (e) {
      debugPrint('📊 ❌ Error generando reporte diario: $e');
      await _sendErrorNotification('Error generando reporte diario: $e');
    }
  }

  /// Analizar datos del día
  Future<Map<String, dynamic>> _analyzeDayData(DateTime date) async {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    debugPrint(
        '📊 Analizando datos del día: ${DateFormat('dd/MM/yyyy').format(date)}');

    // Obtener datos desde Hive
    Box<Map> dataBox;
    if (Hive.isBoxOpen('energyData')) {
      dataBox = Hive.box<Map>('energyData');
    } else {
      dataBox = await Hive.openBox<Map>('energyData');
    }
    final allData = dataBox.values.whereType<Map>().toList();

    // Filtrar datos del día
    final dayData = allData.where((data) {
      final timestamp = data['timestamp'];
      if (timestamp == null) return false;

      final dataTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
      return dataTime.isAfter(startOfDay) && dataTime.isBefore(endOfDay);
    }).toList();

    debugPrint('📊 Registros encontrados: ${dayData.length}');

    if (dayData.isEmpty) {
      return _generateSimulatedData();
    }

    // Analizar datos reales
    return _analyzeRealData(dayData);
  }

  /// Analizar datos reales del ESP32
  Map<String, dynamic> _analyzeRealData(List<Map> dayData) {
    double maxEnergy = 0.0;
    double maxWater = 0.0;
    double maxVoltage = 0.0;
    double maxCurrent = 0.0;
    double maxPower = 0.0;
    double avgTemperature = 0.0;
    double avgHumidity = 0.0;
    int validReadings = 0;
    int compressorOnCount = 0;
    int totalReadings = dayData.length;

    for (final data in dayData) {
      // Energía acumulada
      final energia = _parseDouble(data['energia'] ?? data['e']);
      if (energia != null && energia > maxEnergy) {
        maxEnergy = energia;
      }

      // Agua almacenada
      final agua = _parseDouble(data['aguaAlmacenada'] ?? data['w']);
      if (agua != null && agua > maxWater) {
        maxWater = agua;
      }

      // Parámetros eléctricos
      final voltaje = _parseDouble(data['voltaje'] ?? data['v']);
      if (voltaje != null && voltaje > maxVoltage) {
        maxVoltage = voltaje;
      }

      final corriente = _parseDouble(data['corriente'] ?? data['c']);
      if (corriente != null && corriente > maxCurrent) {
        maxCurrent = corriente;
      }

      final potencia = _parseDouble(data['potencia'] ?? data['po']);
      if (potencia != null && potencia > maxPower) {
        maxPower = potencia;
      }

      // Parámetros ambientales
      final temp = _parseDouble(data['temperaturaAmbiente'] ?? data['t']);
      if (temp != null) {
        avgTemperature += temp;
        validReadings++;
      }

      final hum = _parseDouble(data['humedadRelativa'] ?? data['h']);
      if (hum != null) {
        avgHumidity += hum;
      }

      // Estado del compresor
      final compState = data['estadoCompresor'] ?? data['cs'];
      if (compState == 1) {
        compressorOnCount++;
      }
    }

    if (validReadings > 0) {
      avgTemperature /= validReadings;
      avgHumidity /= validReadings;
    }

    // Calcular eficiencia
    double efficiency = 0.0;
    if (maxWater > 0 && maxEnergy > 0) {
      efficiency = maxEnergy / maxWater;
    }

    // Calcular tiempo de funcionamiento del compresor
    final compressorRuntime = (compressorOnCount / totalReadings) * 100;

    return {
      'maxEnergy': maxEnergy,
      'maxWater': maxWater,
      'maxVoltage': maxVoltage,
      'maxCurrent': maxCurrent,
      'maxPower': maxPower,
      'avgTemperature': avgTemperature,
      'avgHumidity': avgHumidity,
      'efficiency': efficiency,
      'compressorRuntime': compressorRuntime,
      'totalReadings': totalReadings,
      'validReadings': validReadings,
      'isRealData': true,
    };
  }

  /// Generar datos simulados si no hay datos reales
  Map<String, dynamic> _generateSimulatedData() {
    debugPrint('📊 Generando datos simulados para reporte');

    final random = DateTime.now().millisecondsSinceEpoch % 100;
    final baseEnergy = 2500.0 + (random * 15.0);
    final baseWater = 150.0 + (random * 0.8);

    return {
      'maxEnergy': baseEnergy,
      'maxWater': baseWater,
      'maxVoltage': 110.0 + (random * 0.5),
      'maxCurrent': 8.5 + (random * 0.3),
      'maxPower': 950.0 + (random * 20.0),
      'avgTemperature': 25.0 + (random * 0.2),
      'avgHumidity': 65.0 + (random * 0.5),
      'efficiency': baseEnergy / baseWater,
      'compressorRuntime': 45.0 + (random * 0.3),
      'totalReadings': 0,
      'validReadings': 0,
      'isRealData': false,
    };
  }

  /// Generar reporte profesional
  Future<Map<String, dynamic>> _generateProfessionalReport(
      DateTime date, Map<String, dynamic> data) async {
    final dateStr = DateFormat('dd/MM/yyyy').format(date);
    final dayName = DateFormat('EEEE', 'es').format(date);

    // Calcular estadísticas adicionales
    final efficiency = data['efficiency'] ?? 0.0;
    final efficiencyRating = _getEfficiencyRating(efficiency);
    final systemStatus = _getSystemStatus(data);

    return {
      'date': dateStr,
      'dayName': dayName,
      'energy': data['maxEnergy'] ?? 0.0,
      'water': data['maxWater'] ?? 0.0,
      'voltage': data['maxVoltage'] ?? 0.0,
      'current': data['maxCurrent'] ?? 0.0,
      'power': data['maxPower'] ?? 0.0,
      'temperature': data['avgTemperature'] ?? 0.0,
      'humidity': data['avgHumidity'] ?? 0.0,
      'efficiency': efficiency,
      'efficiencyRating': efficiencyRating,
      'compressorRuntime': data['compressorRuntime'] ?? 0.0,
      'systemStatus': systemStatus,
      'isRealData': data['isRealData'] ?? false,
      'totalReadings': data['totalReadings'] ?? 0,
    };
  }

  /// Obtener calificación de eficiencia
  String _getEfficiencyRating(double efficiency) {
    if (efficiency <= 0) return 'Sin datos';
    if (efficiency < 10) return 'Excelente';
    if (efficiency < 15) return 'Muy buena';
    if (efficiency < 20) return 'Buena';
    if (efficiency < 25) return 'Regular';
    return 'Necesita revisión';
  }

  /// Obtener estado del sistema
  String _getSystemStatus(Map<String, dynamic> data) {
    final efficiency = data['efficiency'] ?? 0.0;
    final compressorRuntime = data['compressorRuntime'] ?? 0.0;
    final isRealData = data['isRealData'] ?? false;

    if (!isRealData) return 'Sin datos del día';
    if (efficiency <= 0) return 'Sistema inactivo';
    if (efficiency < 15 && compressorRuntime > 30) {
      return 'Funcionamiento óptimo';
    }
    if (efficiency < 20) return 'Funcionamiento normal';
    if (compressorRuntime < 20) return 'Bajo uso';
    return 'Funcionamiento regular';
  }

  /// Enviar notificación profesional
  Future<void> _sendProfessionalNotification(
      Map<String, dynamic> report) async {
    try {
      // Asegurar que el servicio de notificaciones esté inicializado
      await NotificationService().initialize();

      final title = '📊 Reporte Diario - ${report['date']}';
      final body = _generateNotificationBody(report);

      debugPrint('📊 Enviando notificación con título: $title');

      // Enviar notificación profesional de reporte diario
      await NotificationService().showDailyReportNotification(
        title: title,
        body: body,
      );

      debugPrint('📊 Notificación showDailyReportNotification enviada');

      // Guardar en historial de notificaciones
      await NotificationService.saveNotification(
        title,
        body,
        'daily_report_professional',
      );

      debugPrint('📊 Notificación guardada en historial');
      debugPrint('📊 📱 Notificación profesional enviada');
    } catch (e, stackTrace) {
      debugPrint('📊 ❌ Error enviando notificación profesional: $e');
      debugPrint('📊 StackTrace: $stackTrace');
      rethrow;
    }
  }

  /// Generar cuerpo de notificación
  String _generateNotificationBody(Map<String, dynamic> report) {
    final energy = report['energy'] ?? 0.0;
    final water = report['water'] ?? 0.0;
    final efficiency = report['efficiency'] ?? 0.0;
    final efficiencyRating = report['efficiencyRating'] ?? 'Sin datos';
    final systemStatus = report['systemStatus'] ?? 'Desconocido';
    final isRealData = report['isRealData'] ?? false;

    if (!isRealData) {
      return '''📊 ${report['dayName'] ?? 'Día'} - ${report['date'] ?? 'Fecha'}

⚠️ Sin datos disponibles para el día

El sistema no registró actividad durante este período. Verifica la conexión y el funcionamiento del equipo.''';
    }

    return '''📊 ${report['dayName'] ?? 'Día'} - ${report['date'] ?? 'Fecha'}

⚡ Energía: ${energy.toStringAsFixed(1)} Wh
💧 Agua: ${water.toStringAsFixed(1)} L
📈 Eficiencia: ${efficiency.toStringAsFixed(1)} Wh/L ($efficiencyRating)''';
  }

  /// Obtener emoji de estado
  String _getStatusEmoji(String status) {
    switch (status) {
      case 'Funcionamiento óptimo':
        return '✅';
      case 'Funcionamiento normal':
        return '👍';
      case 'Funcionamiento regular':
        return '⚠️';
      case 'Bajo uso':
        return '📉';
      case 'Sistema inactivo':
        return '🔴';
      default:
        return '❓';
    }
  }

  /// Obtener mensaje de estado
  String _getStatusMessage(String status) {
    switch (status) {
      case 'Funcionamiento óptimo':
        return 'Sistema funcionando perfectamente';
      case 'Funcionamiento normal':
        return 'Rendimiento dentro de parámetros normales';
      case 'Funcionamiento regular':
        return 'Considera revisar el sistema';
      case 'Bajo uso':
        return 'Sistema con poca actividad';
      case 'Sistema inactivo':
        return 'Sistema no operativo';
      default:
        return 'Estado desconocido';
    }
  }

  /// Enviar notificación de error
  Future<void> _sendErrorNotification(String error) async {
    try {
      await NotificationService().initialize();
      await NotificationService().showPushNotification(
        title: '❌ Error en Reporte Diario',
        body: 'No se pudo generar el reporte: $error',
      );
    } catch (e) {
      debugPrint('📊 ❌ Error enviando notificación de error: $e');
    }
  }

  /// Guardar reporte en historial
  Future<void> _saveReportToHistory(
      DateTime date, Map<String, dynamic> report) async {
    try {
      debugPrint('📊 Guardando reporte en historial...');
      Box reportsBox;
      if (Hive.isBoxOpen('enhanced_daily_reports')) {
        reportsBox = Hive.box('enhanced_daily_reports');
      } else {
        reportsBox = await Hive.openBox('enhanced_daily_reports');
      }

      await reportsBox.add({
        'date': date.millisecondsSinceEpoch,
        'report': report,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      debugPrint('📊 💾 Reporte guardado en historial exitosamente');
    } catch (e, stackTrace) {
      debugPrint('📊 ❌ Error guardando reporte en historial: $e');
      debugPrint('📊 StackTrace: $stackTrace');
      rethrow;
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

  /// Parsear double de manera segura
  double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  /// Obtener historial de reportes
  Future<List<Map>> getReportHistory() async {
    Box reportsBox;
    if (Hive.isBoxOpen('enhanced_daily_reports')) {
      reportsBox = Hive.box('enhanced_daily_reports');
    } else {
      reportsBox = await Hive.openBox('enhanced_daily_reports');
    }
    final allReports = reportsBox.values.whereType<Map>().toList();

    // Ordenar por fecha (más reciente primero)
    allReports.sort((a, b) => (b['date'] ?? 0).compareTo(a['date'] ?? 0));

    return allReports;
  }

  /// Limpiar historial de reportes
  Future<void> clearReportHistory() async {
    Box reportsBox;
    if (Hive.isBoxOpen('enhanced_daily_reports')) {
      reportsBox = Hive.box('enhanced_daily_reports');
    } else {
      reportsBox = await Hive.openBox('enhanced_daily_reports');
    }
    await reportsBox.clear();
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

  /// Generar reporte del día actual
  Future<void> generateCurrentDayReport() async {
    try {
      debugPrint('📊 Generando reporte del día actual...');

      final today = DateTime.now();
      debugPrint(
          '📊 Fecha actual: ${DateFormat('dd/MM/yyyy HH:mm:ss').format(today)}');

      final reportData = await _analyzeDayData(today);
      debugPrint('📊 Datos analizados: $reportData');

      final report = await _generateProfessionalReport(today, reportData);
      debugPrint('📊 Reporte generado: $report');

      await _sendProfessionalNotification(report);
      debugPrint('📊 Notificación enviada');

      await _saveReportToHistory(today, report);
      debugPrint('📊 Reporte guardado en historial');

      debugPrint('📊 ✅ Reporte del día actual generado');
    } catch (e, stackTrace) {
      debugPrint('📊 ❌ Error generando reporte del día actual: $e');
      debugPrint('📊 StackTrace: $stackTrace');
      await _sendErrorNotification(
          'Error generando reporte del día actual: $e');
    }
  }

  /// Dispose del servicio
  void dispose() {
    _periodicCheckTimer?.cancel();
    AndroidAlarmManager.cancel(_alarmId);
    AndroidAlarmManager.cancel(_backupAlarmId);
  }
}

// Callback principal para reportes diarios
@pragma('vm:entry-point')
Future<void> _enhancedDailyReportCallback() async {
  debugPrint(
      '📅 ⏰ ¡Es hora del reporte diario profesional! (ejecutándose en background)');

  try {
    // Inicializar servicios necesarios para el background
    WidgetsFlutterBinding.ensureInitialized();

    // Inicializar Hive
    final dir = await getApplicationDocumentsDirectory();
    await Hive.initFlutter(dir.path);

    // Inicializar servicios
    await NotificationService().initialize();

    // Generar reporte
    final service = EnhancedDailyReportService();
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

    debugPrint('📅 ✅ Reporte diario profesional completado');
  } catch (e) {
    debugPrint('📅 ❌ Error en callback de reporte diario: $e');
  }
}

// Callback de respaldo
@pragma('vm:entry-point')
Future<void> _backupReportCallback() async {
  debugPrint('📅 🔄 Ejecutando callback de respaldo...');

  try {
    // Verificar si ya se ejecutó el reporte principal
    Box reportsBox;
    if (Hive.isBoxOpen('enhanced_daily_reports')) {
      reportsBox = Hive.box('enhanced_daily_reports');
    } else {
      reportsBox = await Hive.openBox('enhanced_daily_reports');
    }
    final today = DateTime.now().subtract(const Duration(days: 1));

    final todayReports = reportsBox.values.where((report) {
      final reportDate = DateTime.fromMillisecondsSinceEpoch(report['date']);
      return _isSameDay(reportDate, today);
    }).toList();

    if (todayReports.isEmpty) {
      debugPrint(
          '📅 🔄 Reporte principal no ejecutado, ejecutando respaldo...');
      await _enhancedDailyReportCallback();
    } else {
      debugPrint('📅 ✅ Reporte principal ya ejecutado, cancelando respaldo');
    }
  } catch (e) {
    debugPrint('📅 ❌ Error en callback de respaldo: $e');
  }
}

// Función auxiliar para comparar fechas
bool _isSameDay(DateTime date1, DateTime date2) {
  return date1.year == date2.year &&
      date1.month == date2.month &&
      date1.day == date2.day;
}

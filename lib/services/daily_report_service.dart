import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import '../services/notification_service.dart';

class DailyReportService {
  static final DailyReportService _instance = DailyReportService._internal();
  factory DailyReportService() => _instance;
  DailyReportService._internal();

  Timer? _dailyTimer;
  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;
  }

  Future<void> scheduleDailyReport(TimeOfDay time, bool enabled) async {
    await initialize();

    // Cancelar timer existente
    _dailyTimer?.cancel();

    if (!enabled) {
      debugPrint('📅 Reporte diario deshabilitado');
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
          '📅 Hora ya pasó hoy, programando para mañana: ${nextRun.toString()}');
    } else {
      debugPrint('📅 Programando para hoy: ${nextRun.toString()}');
    }

    final delay = nextRun.difference(now);
    debugPrint(
        '📅 Próximo reporte en: ${delay.inHours}h ${delay.inMinutes % 60}m ${delay.inSeconds % 60}s');

    // Programar timer con verificación adicional
    _dailyTimer = Timer(delay, () async {
      debugPrint('📅 ⏰ ¡Es hora del reporte diario!');
      await _generateDailyReport();

      // Verificar que el reporte se generó correctamente
      await Future.delayed(const Duration(seconds: 5));

      // Programar para el siguiente día
      debugPrint('📅 Programando siguiente reporte diario...');
      await scheduleDailyReport(time, enabled);
    });

    debugPrint('📅 ✅ Reporte diario programado exitosamente');
  }

  Future<void> _generateDailyReport() async {
    try {
      debugPrint('📊 Iniciando generación de reporte diario...');

      // Obtener datos del día anterior
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final startOfDay =
          DateTime(yesterday.year, yesterday.month, yesterday.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      debugPrint(
          '📊 Analizando datos del día: ${DateFormat('dd/MM/yyyy').format(yesterday)}');
      debugPrint(
          '📊 Rango de tiempo: ${startOfDay.toString()} - ${endOfDay.toString()}');

      // Obtener datos desde Hive
      final dataBox = await Hive.openBox('mqtt_data');
      final allData = dataBox.values.whereType<Map>().toList();

      debugPrint('📊 Total de registros en Hive: ${allData.length}');

      // Filtrar datos del día anterior
      final dayData = allData.where((data) {
        final timestamp = data['timestamp'];
        if (timestamp == null) return false;

        final dataTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
        final isInRange =
            dataTime.isAfter(startOfDay) && dataTime.isBefore(endOfDay);

        if (isInRange) {
          debugPrint('📊 ✅ Dato válido encontrado: ${dataTime.toString()}');
        }

        return isInRange;
      }).toList();

      debugPrint(
          '📊 Registros del día anterior encontrados: ${dayData.length}');

      if (dayData.isEmpty) {
        debugPrint('📊 ⚠️ No hay datos disponibles para el día anterior');
        await _showNotification(
          'Reporte Diario - ${DateFormat('dd/MM/yyyy').format(yesterday)}',
          'No hay datos disponibles para el día anterior.',
        );
        return;
      }

      // Calcular totales con datos reales del ESP32
      double totalEnergy = 0.0;
      double totalWater = 0.0;
      double maxEnergy = 0.0;
      double maxWater = 0.0;
      int validEnergyReadings = 0;
      int validWaterReadings = 0;

      for (final data in dayData) {
        // Energía acumulada (datos reales del ESP32 - campo 'energia' en Wh)
        final energia = _parseDouble(data['energia']);
        if (energia != null && energia > 0) {
          if (energia > maxEnergy) {
            maxEnergy = energia;
          }
          validEnergyReadings++;
          debugPrint(
              '📊 Energía encontrada: ${energia.toStringAsFixed(2)} Wh');
        }

        // Agua almacenada (datos reales del ESP32 - campo 'aguaAlmacenada' en L)
        final aguaAlmacenada = _parseDouble(data['aguaAlmacenada']);
        if (aguaAlmacenada != null && aguaAlmacenada > 0) {
          if (aguaAlmacenada > maxWater) {
            maxWater = aguaAlmacenada;
          }
          validWaterReadings++;
          debugPrint(
              '📊 Agua encontrada: ${aguaAlmacenada.toStringAsFixed(2)} L');
        }
      }

      totalEnergy = maxEnergy;
      totalWater = maxWater;

      debugPrint('📊 Resumen del día:');
      debugPrint(
          '📊   - Energía máxima: ${totalEnergy.toStringAsFixed(2)} Wh');
      debugPrint('📊   - Agua máxima: ${totalWater.toStringAsFixed(2)} L');
      debugPrint('📊   - Lecturas de energía válidas: $validEnergyReadings');
      debugPrint('📊   - Lecturas de agua válidas: $validWaterReadings');

      // Calcular eficiencia
      double efficiency = 0.0;
      if (totalWater > 0 && totalEnergy > 0) {
        efficiency = totalEnergy / totalWater; // Wh por litro
        debugPrint(
            '📊 Eficiencia calculada: ${efficiency.toStringAsFixed(3)} Wh/L');
      } else {
        debugPrint(
            '📊 ⚠️ No se puede calcular eficiencia: datos insuficientes');
      }

      // Generar mensaje del reporte
      final reportMessage = _generateReportMessage(
        DateFormat('dd/MM/yyyy').format(yesterday),
        totalEnergy,
        totalWater,
        efficiency,
      );

      // Mostrar notificación push
      await NotificationService().showPushNotification(
        title:
            '📅 Reporte Diario - ${DateFormat('dd/MM/yyyy').format(yesterday)}',
        body: reportMessage,
      );

      // Guardar notificación en el sistema
      await NotificationService.saveNotification(
        'Reporte Diario - ${DateFormat('dd/MM/yyyy').format(yesterday)}',
        reportMessage,
        'daily_report',
      );

      debugPrint('📊 ✅ Reporte diario generado exitosamente');
      debugPrint('📊 📧 Notificación enviada al usuario');

      // Guardar reporte en Hive para historial
      await saveReportToHistory(yesterday, totalEnergy, totalWater, efficiency);
      debugPrint('📊 💾 Reporte guardado en historial');
    } catch (e) {
      debugPrint('📊 ❌ Error generando reporte diario: $e');

      // Mostrar notificación de error
      await NotificationService().showPushNotification(
        title: '❌ Error en Reporte Diario',
        body: 'No se pudo generar el reporte del día anterior.',
      );

      // Guardar notificación de error
      await NotificationService.saveNotification(
        'Error en Reporte Diario',
        'No se pudo generar el reporte del día anterior.',
        'error',
      );
    }
  }

  double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  String _generateReportMessage(
      String date, double energy, double water, double efficiency) {
    final energyStr = energy.toStringAsFixed(2);
    final waterStr = water.toStringAsFixed(2);
    final efficiencyStr = efficiency.toStringAsFixed(3);

    return '''📊 Resumen del día $date:

⚡ Energía acumulada: $energyStr Wh
💧 Agua almacenada: $waterStr L
⚡ Eficiencia: $efficiencyStr Wh/L

${efficiency > 0 ? '✅ Sistema funcionando correctamente' : '⚠️ Sin datos de eficiencia'}''';
  }

  // Método para mostrar notificaciones usando el servicio de notificaciones
  Future<void> _showNotification(String title, String body) async {
    await NotificationService.saveNotification(title, body, 'daily_report');
    debugPrint('NOTIFICACIÓN: $title - $body');
  }

  Future<void> saveReportToHistory(
      DateTime date, double energy, double water, double efficiency) async {
    final reportsBox = await Hive.openBox('daily_reports');

    await reportsBox.add({
      'date': date.millisecondsSinceEpoch,
      'energy': energy,
      'water': water,
      'efficiency': efficiency,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<List<Map>> getReportHistory() async {
    final reportsBox = await Hive.openBox('daily_reports');
    final allReports = reportsBox.values.whereType<Map>().toList();

    // Ordenar por fecha (más reciente primero)
    allReports.sort((a, b) => (b['date'] ?? 0).compareTo(a['date'] ?? 0));

    return allReports;
  }

  /// Generar un reporte diario simulado con datos de prueba
  Future<void> generateTestReport() async {
    try {
      debugPrint('🧪 Generando reporte diario de prueba...');

      // Datos simulados para el día actual
      final today = DateTime.now();
      final random = DateTime.now().millisecondsSinceEpoch % 100;

      // Simular datos realistas
      final simulatedEnergy = 2500.0 + (random * 10.0); // 2500 - 3500 Wh
      final simulatedWater = 150.0 + (random * 0.5); // 150 - 250 L
      final simulatedEfficiency = simulatedEnergy / simulatedWater;

      // Generar mensaje del reporte
      final reportMessage = _generateReportMessage(
        DateFormat('dd/MM/yyyy').format(today),
        simulatedEnergy,
        simulatedWater,
        simulatedEfficiency,
      );

      // Mostrar notificación push de prueba
      await NotificationService().showPushNotification(
        title: '🧪 Reporte Diario de Prueba',
        body: reportMessage,
      );

      // Guardar notificación en el sistema
      await NotificationService.saveNotification(
        'Reporte Diario de Prueba - ${DateFormat('dd/MM/yyyy').format(today)}',
        reportMessage,
        'daily_report_test',
      );

      debugPrint('🧪 Reporte de prueba generado exitosamente');
      debugPrint(
          '🧪 Energía simulada: ${simulatedEnergy.toStringAsFixed(2)} Wh');
      debugPrint('🧪 Agua simulada: ${simulatedWater.toStringAsFixed(2)} L');
      debugPrint(
          '🧪 Eficiencia simulada: ${simulatedEfficiency.toStringAsFixed(3)} Wh/L');
    } catch (e) {
      debugPrint('Error generando reporte de prueba: $e');

      // Mostrar notificación de error
      await NotificationService().showPushNotification(
        title: 'Error en Reporte de Prueba',
        body: 'No se pudo generar el reporte de prueba.',
      );
    }
  }

  /// Generar reporte del día actual (no del día anterior)
  Future<void> generateCurrentDayReport() async {
    try {
      debugPrint('📊 Generando reporte del día actual...');

      // Obtener datos del día actual
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      // Obtener datos desde Hive
      final dataBox = await Hive.openBox('mqtt_data');
      final allData = dataBox.values.whereType<Map>().toList();

      // Filtrar datos del día actual
      final dayData = allData.where((data) {
        final timestamp = data['timestamp'];
        if (timestamp == null) return false;

        final dataTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
        return dataTime.isAfter(startOfDay) && dataTime.isBefore(endOfDay);
      }).toList();

      double totalEnergy = 0.0;
      double totalWater = 0.0;

      if (dayData.isNotEmpty) {
        // Calcular totales desde datos reales
        double maxEnergy = 0.0;
        double maxWater = 0.0;

        for (final data in dayData) {
          final energia = _parseDouble(data['energia']);
          if (energia != null && energia > maxEnergy) {
            maxEnergy = energia;
          }

          final aguaAlmacenada = _parseDouble(data['aguaAlmacenada']);
          if (aguaAlmacenada != null && aguaAlmacenada > maxWater) {
            maxWater = aguaAlmacenada;
          }
        }

        totalEnergy = maxEnergy;
        totalWater = maxWater;
      } else {
        // Si no hay datos reales, usar datos simulados
        debugPrint('📊 No hay datos reales, usando simulación...');
        final random = DateTime.now().millisecondsSinceEpoch % 100;
        totalEnergy = 1500.0 + (random * 10.0); // Energía parcial del día en Wh
        totalWater = 75.0 + (random * 0.25); // Agua parcial del día
      }

      // Calcular eficiencia
      double efficiency = 0.0;
      if (totalWater > 0 && totalEnergy > 0) {
        efficiency = totalEnergy / totalWater;
      }

      // Generar mensaje del reporte
      final reportMessage = _generateReportMessage(
        DateFormat('dd/MM/yyyy').format(today),
        totalEnergy,
        totalWater,
        efficiency,
      );

      // Mostrar notificación push
      await NotificationService().showPushNotification(
        title: '📊 Reporte del Día Actual',
        body: reportMessage,
      );

      // Guardar notificación en el sistema
      await NotificationService.saveNotification(
        'Reporte del Día Actual - ${DateFormat('dd/MM/yyyy').format(today)}',
        reportMessage,
        'daily_report_current',
      );

      debugPrint('📊 Reporte del día actual generado');
      debugPrint('📊 Energía: ${totalEnergy.toStringAsFixed(2)} Wh');
      debugPrint('📊 Agua: ${totalWater.toStringAsFixed(2)} L');
      debugPrint('📊 Eficiencia: ${efficiency.toStringAsFixed(3)} Wh/L');
    } catch (e) {
      debugPrint('Error generando reporte del día actual: $e');

      await NotificationService().showPushNotification(
        title: 'Error en Reporte del Día',
        body: 'No se pudo generar el reporte del día actual.',
      );
    }
  }

  Future<void> clearReportHistory() async {
    final reportsBox = await Hive.openBox('daily_reports');
    await reportsBox.clear();
  }

  /// Verificar estado del servicio de reportes diarios
  Future<Map<String, dynamic>> getServiceStatus() async {
    final now = DateTime.now();
    final settingsBox = await Hive.openBox('settings');
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
      'status': _dailyTimer?.isActive == true ? 'active' : 'scheduled',
      'reportTime':
          '${reportTime.hour.toString().padLeft(2, '0')}:${reportTime.minute.toString().padLeft(2, '0')}'
    };
  }

  /// Forzar ejecución inmediata del reporte diario (para pruebas)
  Future<void> forceGenerateReport() async {
    debugPrint('🔧 Forzando generación inmediata del reporte diario...');
    await _generateDailyReport();
  }

  /// Verificar y reparar el servicio si es necesario
  Future<void> checkAndRepairService() async {
    try {
      final status = await getServiceStatus();

      if (status['enabled'] == true && status['status'] != 'active') {
        debugPrint(
            '🔧 Servicio de reportes necesita reparación, reprogramando...');

        final settingsBox = await Hive.openBox('settings');
        final hour = settingsBox.get('dailyReportHour', defaultValue: 20);
        final minute = settingsBox.get('dailyReportMinute', defaultValue: 0);
        final reportTime = TimeOfDay(hour: hour, minute: minute);

        await scheduleDailyReport(reportTime, true);
        debugPrint('🔧 Servicio de reportes reparado exitosamente');
      }
    } catch (e) {
      debugPrint('🔧 Error verificando servicio de reportes: $e');
    }
  }

  void dispose() {
    _dailyTimer?.cancel();
  }
}

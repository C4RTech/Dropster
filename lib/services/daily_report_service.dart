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
    
    if (!enabled) return;

    // Calcular próxima ejecución
    final now = DateTime.now();
    var nextRun = DateTime(now.year, now.month, now.day, time.hour, time.minute);
    
    // Si ya pasó la hora de hoy, programar para mañana
    if (nextRun.isBefore(now)) {
      nextRun = nextRun.add(const Duration(days: 1));
    }

    final delay = nextRun.difference(now);
    
    // Programar timer
    _dailyTimer = Timer(delay, () {
      _generateDailyReport();
      // Programar para el siguiente día
      scheduleDailyReport(time, enabled);
    });
  }

  Future<void> _generateDailyReport() async {
    try {
      // Obtener datos del día anterior
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final startOfDay = DateTime(yesterday.year, yesterday.month, yesterday.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      // Obtener datos desde Hive
      final dataBox = await Hive.openBox('mqtt_data');
      final allData = dataBox.values.whereType<Map>().toList();

      // Filtrar datos del día anterior
      final dayData = allData.where((data) {
        final timestamp = data['timestamp'];
        if (timestamp == null) return false;
        
        final dataTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
        return dataTime.isAfter(startOfDay) && dataTime.isBefore(endOfDay);
      }).toList();

      if (dayData.isEmpty) {
        await _showNotification(
          'Reporte Diario - ${DateFormat('dd/MM/yyyy').format(yesterday)}',
          'No hay datos disponibles para el día anterior.',
        );
        return;
      }

      // Calcular totales
      double totalEnergy = 0.0;
      double totalWater = 0.0;
      double maxEnergy = 0.0;
      double maxWater = 0.0;

      for (final data in dayData) {
        // Energía del día
        final energyToday = _parseDouble(data['energyToday']);
        if (energyToday != null && energyToday > maxEnergy) {
          maxEnergy = energyToday;
        }

        // Agua generada (simulada o real)
        final waterGenerated = _parseDouble(data['waterGenerated']) ?? 
                              _parseDouble(data['aguaGenerada']) ?? 
                              0.0;
        if (waterGenerated > maxWater) {
          maxWater = waterGenerated;
        }
      }

      totalEnergy = maxEnergy;
      totalWater = maxWater;

      // Calcular eficiencia
      double efficiency = 0.0;
      if (totalWater > 0 && totalEnergy > 0) {
        efficiency = totalEnergy / totalWater; // kWh por litro
      }

      // Generar mensaje del reporte
      final reportMessage = _generateReportMessage(
        DateFormat('dd/MM/yyyy').format(yesterday),
        totalEnergy,
        totalWater,
        efficiency,
      );

      // Guardar notificación en el sistema
      await NotificationService.saveNotification(
        'Reporte Diario - ${DateFormat('dd/MM/yyyy').format(yesterday)}',
        reportMessage,
        'daily_report',
      );
      
      debugPrint('Reporte Diario - ${DateFormat('dd/MM/yyyy').format(yesterday)}');
      debugPrint(reportMessage);

      // Guardar reporte en Hive para historial
      await saveReportToHistory(yesterday, totalEnergy, totalWater, efficiency);

    } catch (e) {
      debugPrint('Error generando reporte diario: $e');
      
      // Guardar notificación de error
      await NotificationService.saveNotification(
        'Error en Reporte Diario',
        'No se pudo generar el reporte del día anterior.',
        'error',
      );
      
      debugPrint('Error en Reporte Diario: No se pudo generar el reporte del día anterior.');
    }
  }

  double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  String _generateReportMessage(String date, double energy, double water, double efficiency) {
    final energyStr = energy.toStringAsFixed(2);
    final waterStr = water.toStringAsFixed(2);
    final efficiencyStr = efficiency.toStringAsFixed(3);

    return '''📊 Resumen del día $date:

⚡ Energía consumida: $energyStr kWh
💧 Agua generada: $waterStr L
⚡ Eficiencia: $efficiencyStr kWh/L

${efficiency > 0 ? '✅ Sistema funcionando correctamente' : '⚠️ Sin datos de eficiencia'}''';
  }

  // Método para mostrar notificaciones usando el servicio de notificaciones
  Future<void> _showNotification(String title, String body) async {
    await NotificationService.saveNotification(title, body, 'daily_report');
    debugPrint('NOTIFICACIÓN: $title - $body');
  }

  Future<void> saveReportToHistory(DateTime date, double energy, double water, double efficiency) async {
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

  Future<void> clearReportHistory() async {
    final reportsBox = await Hive.openBox('daily_reports');
    await reportsBox.clear();
  }

  void dispose() {
    _dailyTimer?.cancel();
  }
} 
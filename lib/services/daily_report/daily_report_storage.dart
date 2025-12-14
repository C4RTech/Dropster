import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Gestiona el almacenamiento de reportes diarios en Hive
class DailyReportStorage {
  static const String _boxName = 'enhanced_daily_reports';

  /// Función helper para logs condicionales
  void _log(String message) {
    if (kDebugMode) {
      debugPrint('[REPORT-STORAGE] $message');
    }
  }

  /// Guardar reporte en historial
  Future<void> saveReportToHistory(
      DateTime date, Map<String, dynamic> report) async {
    try {
      _log('Guardando reporte en historial...');
      Box reportsBox;
      if (Hive.isBoxOpen(_boxName)) {
        reportsBox = Hive.box(_boxName);
      } else {
        reportsBox = await Hive.openBox(_boxName);
      }

      await reportsBox.add({
        'date': date.millisecondsSinceEpoch,
        'report': report,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      _log('💾 Reporte guardado en historial exitosamente');
    } catch (e, stackTrace) {
      _log('❌ Error guardando reporte en historial: $e');
      _log('StackTrace: $stackTrace');
      rethrow;
    }
  }

  /// Obtener historial de reportes
  Future<List<Map>> getReportHistory() async {
    Box reportsBox;
    if (Hive.isBoxOpen(_boxName)) {
      reportsBox = Hive.box(_boxName);
    } else {
      reportsBox = await Hive.openBox(_boxName);
    }

    final allReports = reportsBox.values.whereType<Map>().toList();

    // Ordenar por fecha (más reciente primero)
    allReports.sort((a, b) => (b['date'] ?? 0).compareTo(a['date'] ?? 0));

    return allReports;
  }

  /// Limpiar historial de reportes
  Future<void> clearReportHistory() async {
    Box reportsBox;
    if (Hive.isBoxOpen(_boxName)) {
      reportsBox = Hive.box(_boxName);
    } else {
      reportsBox = await Hive.openBox(_boxName);
    }

    await reportsBox.clear();
    _log('Historial de reportes limpiado');
  }

  /// Obtener reporte por fecha específica
  Future<Map?> getReportByDate(DateTime date) async {
    final reports = await getReportHistory();

    for (final reportEntry in reports) {
      final reportDate =
          DateTime.fromMillisecondsSinceEpoch(reportEntry['date']);
      if (_isSameDay(reportDate, date)) {
        return reportEntry;
      }
    }

    return null;
  }

  /// Obtener reportes en un rango de fechas
  Future<List<Map>> getReportsInDateRange(
      DateTime startDate, DateTime endDate) async {
    final allReports = await getReportHistory();

    return allReports.where((reportEntry) {
      final reportDate =
          DateTime.fromMillisecondsSinceEpoch(reportEntry['date']);
      return reportDate.isAfter(startDate.subtract(const Duration(days: 1))) &&
          reportDate.isBefore(endDate.add(const Duration(days: 1)));
    }).toList();
  }

  /// Obtener estadísticas del historial
  Future<Map<String, dynamic>> getHistoryStats() async {
    final reports = await getReportHistory();

    if (reports.isEmpty) {
      return {
        'totalReports': 0,
        'dateRange': null,
        'avgEfficiency': 0.0,
        'avgEnergy': 0.0,
        'avgWater': 0.0,
      };
    }

    double totalEfficiency = 0.0;
    double totalEnergy = 0.0;
    double totalWater = 0.0;
    int validReports = 0;

    DateTime? earliestDate;
    DateTime? latestDate;

    for (final reportEntry in reports) {
      final report = reportEntry['report'] as Map<String, dynamic>;
      final isRealData = report['isRealData'] ?? false;

      if (isRealData) {
        final efficiency = report['efficiency'] ?? 0.0;
        final energy = report['energy'] ?? 0.0;
        final water = report['water'] ?? 0.0;

        totalEfficiency += efficiency;
        totalEnergy += energy;
        totalWater += water;
        validReports++;
      }

      final reportDate =
          DateTime.fromMillisecondsSinceEpoch(reportEntry['date']);
      if (earliestDate == null || reportDate.isBefore(earliestDate)) {
        earliestDate = reportDate;
      }
      if (latestDate == null || reportDate.isAfter(latestDate)) {
        latestDate = reportDate;
      }
    }

    return {
      'totalReports': reports.length,
      'validReports': validReports,
      'dateRange': earliestDate != null && latestDate != null
          ? {'start': earliestDate, 'end': latestDate}
          : null,
      'avgEfficiency': validReports > 0 ? totalEfficiency / validReports : 0.0,
      'avgEnergy': validReports > 0 ? totalEnergy / validReports : 0.0,
      'avgWater': validReports > 0 ? totalWater / validReports : 0.0,
    };
  }

  /// Verificar si ya existe un reporte para una fecha específica
  Future<bool> hasReportForDate(DateTime date) async {
    final report = await getReportByDate(date);
    return report != null;
  }

  /// Eliminar reporte específico
  Future<void> deleteReport(DateTime date) async {
    final reports = await getReportHistory();
    Box reportsBox;

    if (Hive.isBoxOpen(_boxName)) {
      reportsBox = Hive.box(_boxName);
    } else {
      reportsBox = await Hive.openBox(_boxName);
    }

    for (int i = 0; i < reports.length; i++) {
      final reportEntry = reports[i];
      final reportDate =
          DateTime.fromMillisecondsSinceEpoch(reportEntry['date']);
      if (_isSameDay(reportDate, date)) {
        await reportsBox.deleteAt(i);
        _log('Reporte eliminado para fecha: ${date.toString().split(' ')[0]}');
        return;
      }
    }
  }

  /// Verificar si es el mismo día
  bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }
}

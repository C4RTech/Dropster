import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';

/// Genera reportes diarios profesionales con estadísticas detalladas
class DailyReportGenerator {
  /// Función helper para logs condicionales
  void _log(String message) {
    if (kDebugMode) {
      debugPrint('[REPORT-GENERATOR] $message');
    }
  }

  /// Generar reporte profesional
  Future<Map<String, dynamic>> generateProfessionalReport(
      DateTime date, Map<String, dynamic> data) async {
    // Inicializar datos de localización para español
    await initializeDateFormatting('es');

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

  /// Generar cuerpo de notificación
  String generateNotificationBody(Map<String, dynamic> report) {
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

  /// Generar resumen ejecutivo del reporte
  String generateExecutiveSummary(Map<String, dynamic> report) {
    final isRealData = report['isRealData'] ?? false;
    if (!isRealData) {
      return 'No hay datos disponibles para generar un resumen ejecutivo.';
    }

    final energy = report['energy'] ?? 0.0;
    final water = report['water'] ?? 0.0;
    final efficiency = report['efficiency'] ?? 0.0;
    final status = report['systemStatus'] ?? 'Desconocido';

    return '''
RESUMEN EJECUTIVO - ${report['date']}

📊 PRODUCCIÓN:
• Energía generada: ${energy.toStringAsFixed(1)} Wh
• Agua producida: ${water.toStringAsFixed(1)} L
• Eficiencia: ${efficiency.toStringAsFixed(1)} Wh/L

💡 RECOMENDACIONES:
${_generateRecommendations(report)}
''';
  }

  /// Generar recomendaciones basadas en el reporte
  String _generateRecommendations(Map<String, dynamic> report) {
    final efficiency = report['efficiency'] ?? 0.0;
    final compressorRuntime = report['compressorRuntime'] ?? 0.0;
    final status = report['systemStatus'] ?? '';

    final recommendations = <String>[];

    if (efficiency < 10) {
      recommendations
          .add('• Excelente eficiencia - mantener condiciones actuales');
    } else if (efficiency < 15) {
      recommendations
          .add('• Eficiencia muy buena - monitorear temperatura ambiente');
    } else if (efficiency < 20) {
      recommendations
          .add('• Eficiencia aceptable - considerar limpieza de filtros');
    } else {
      recommendations
          .add('• Eficiencia baja - revisar componentes del sistema');
    }

    if (compressorRuntime > 80) {
      recommendations
          .add('• Alto uso del compresor - verificar carga de trabajo');
    } else if (compressorRuntime < 20) {
      recommendations
          .add('• Bajo uso del sistema - considerar aumento de carga');
    }

    if (recommendations.isEmpty) {
      recommendations
          .add('• Sistema funcionando dentro de parámetros normales');
    }

    return recommendations.join('\n');
  }
}

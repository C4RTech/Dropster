import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Analiza datos del día para generar reportes diarios
class DailyReportDataAnalyzer {
  /// Función helper para logs condicionales
  void _log(String message) {
    if (kDebugMode) {
      debugPrint('[DAILY-ANALYZER] $message');
    }
  }

  /// Analizar datos del día
  Future<Map<String, dynamic>> analyzeDayData(DateTime date) async {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    _log('Analizando datos del día: ${date.toString().split(' ')[0]}');

    // Obtener datos desde Hive
    final dayData = await _getDayDataFromHive(startOfDay, endOfDay);

    _log('Registros encontrados: ${dayData.length}');

    if (dayData.isEmpty) {
      return _generateSimulatedData();
    }

    // Analizar datos reales
    return _analyzeRealData(dayData);
  }

  /// Obtener datos del día desde Hive
  Future<List<Map>> _getDayDataFromHive(
      DateTime startOfDay, DateTime endOfDay) async {
    Box<Map> dataBox;
    if (Hive.isBoxOpen('energyData')) {
      dataBox = Hive.box<Map>('energyData');
    } else {
      dataBox = await Hive.openBox<Map>('energyData');
    }

    final allData = dataBox.values.whereType<Map>().toList();

    // Filtrar datos del día
    return allData.where((data) {
      final timestamp = data['timestamp'];
      if (timestamp == null) return false;

      final dataTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
      return dataTime.isAfter(startOfDay) && dataTime.isBefore(endOfDay);
    }).toList();
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
    _log('Generando datos simulados para reporte');

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
      'efficiency': baseWater / baseEnergy,
      'compressorRuntime': 45.0 + (random * 0.3),
      'totalReadings': 0,
      'validReadings': 0,
      'isRealData': false,
    };
  }

  /// Parsear double de manera segura
  double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}

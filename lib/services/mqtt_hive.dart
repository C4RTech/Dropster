import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'singleton_mqtt_service.dart';

/// Servicio para integrar MQTT y Hive.
/// Permite guardar, recuperar y notificar datos energéticos en la app.
/// Incluye utilidades para parsear datos, habilitar/deshabilitar guardado y manejar streams históricos.
class MqttHiveService {
  static Box<Map>? dataBox; // Box de Hive para datos energéticos históricos
  static Box?
      settingsBox; // Box de Hive para configuraciones (nominales, flags)
  static bool isInitialized = false; // Indica si ya se inicializó

  /// Inicializa los boxes de Hive necesarios para el almacenamiento local.
  static Future<void> initHive() async {
    if (!Hive.isBoxOpen('energyData')) {
      dataBox = await Hive.openBox<Map>('energyData');
    } else {
      dataBox = Hive.box<Map>('energyData');
    }
    if (!Hive.isBoxOpen('settings')) {
      settingsBox = await Hive.openBox('settings');
    } else {
      settingsBox = Hive.box('settings');
    }
    isInitialized = true;
  }

  /// Devuelve si el guardado de datos está habilitado (por defecto sí).
  static bool isSavingEnabled() {
    if (!isInitialized || settingsBox == null) return true;
    return settingsBox!.get('isSavingEnabled', defaultValue: true);
  }

  /// Activa/desactiva el guardado de datos
  static void toggleSaving(bool enabled) {
    if (settingsBox != null) {
      settingsBox!.put('isSavingEnabled', enabled);
    }
  }

  /// Borra todos los datos históricos almacenados
  static Future<void> clearAllData() async {
    if (dataBox != null) {
      await dataBox!.clear();
    }
  }

  /// Devuelve el registro más reciente guardado, o null si no hay datos
  static Future<Map<String, dynamic>?> getLatestData() async {
    if (dataBox == null || dataBox!.isEmpty) return null;
    final last = dataBox!.getAt(dataBox!.length - 1);
    return last?.cast<String, dynamic>();
  }

  /// Parsea datos JSON del AWG ESP32 a un mapa con claves semánticas.
  /// El parámetro "source" indica el origen ("MQTT" o "BLE").
  static Map<String, dynamic> parseAwgJson(String jsonString,
      {String source = "MQTT"}) {
    debugPrint('[MQTT DEBUG] Intentando parsear JSON: $jsonString');
    try {
      final Map<String, dynamic> jsonData =
          Map<String, dynamic>.from(json.decode(jsonString));

      debugPrint(
          '[MQTT DEBUG] JSON parseado exitosamente, claves: ${jsonData.keys}');

      // Log específico para campo 'e' (energia)
      if (jsonData.containsKey('e')) {
        debugPrint(
            '[ENERGIA DEBUG] Campo "e" encontrado en JSON: ${jsonData['e']} (tipo: ${jsonData['e'].runtimeType})');
      } else {
        debugPrint(
            '[ENERGIA DEBUG] ⚠️ Campo "e" NO encontrado en JSON recibido');
      }

      // Mapear datos del AWG ESP32 (nombres abreviados) al formato esperado por la app
      final parsedData = {
        // === DATOS PRINCIPALES ===
        'temperaturaAmbiente': jsonData['t'] ?? 0.0, // t = temperatura ambiente
        'presionAtmosferica': jsonData['p'] ?? 0.0, // p = presión atmosférica
        'humedadRelativa':
            jsonData['h'] ?? 0.0, // h = humedad relativa ambiente
        'aguaAlmacenada': jsonData['w'] ?? 0.0, // w = agua almacenada

        // === SENSORES ADICIONALES ===
        'sht1Temp': jsonData['te'] ?? 0.0, // te = temperatura evaporador
        'sht1Hum': jsonData['he'] ?? 0.0, // he = humedad evaporador
        'compressorTemp': jsonData['tc'] ?? 0.0, // tc = temperatura compresor

        // === CÁLCULOS DERIVADOS ===
        'puntoRocio': jsonData['dp'] ?? 0.0, // dp = punto de rocío
        'humedadAbsoluta': jsonData['ha'] ?? 0.0, // ha = humedad absoluta

        // === DATOS ELÉCTRICOS ===
        'voltaje': jsonData['v'] ?? 0.0, // v = voltaje
        'corriente': jsonData['c'] ?? 0.0, // c = corriente
        'potencia': jsonData['po'] ?? 0.0, // po = potencia
        'energia': jsonData['e'] ?? 0.0, // e = energia en Wh

        // === ESTADO DEL COMPRESOR ===
        'estadoCompresor':
            jsonData['cs'] ?? 0, // cs = estado compresor (0=OFF, 1=ON)

        // === TIMESTAMP ===
        'datetime': jsonData['ts']?.toString() ?? '', // ts = timestamp unix
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'source': source,
      };

      // Verificar que energia se mapeó correctamente
      final energiaValue = parsedData['energia'];
      debugPrint(
          '[ENERGIA DEBUG] Valor mapeado para "energia": $energiaValue (tipo: ${energiaValue.runtimeType})');

      // Debug exhaustivo de valores eléctricos
      debugPrint('[ESP32 RAW DEBUG] === VALORES CRUDOS DEL ESP32 ===');
      debugPrint('[ESP32 RAW DEBUG] - Voltaje raw: ${jsonData['v']}');
      debugPrint('[ESP32 RAW DEBUG] - Corriente raw: ${jsonData['c']}');
      debugPrint('[ESP32 RAW DEBUG] - Potencia raw: ${jsonData['po']}');
      debugPrint('[ESP32 RAW DEBUG] - Energía raw: ${jsonData['e']}');

      debugPrint('[FLUTTER PARSED DEBUG] === VALORES MAPEADOS EN FLUTTER ===');
      debugPrint('[FLUTTER PARSED DEBUG] - Voltaje: ${parsedData['voltaje']}V');
      debugPrint(
          '[FLUTTER PARSED DEBUG] - Corriente: ${parsedData['corriente']}A');
      debugPrint(
          '[FLUTTER PARSED DEBUG] - Potencia: ${parsedData['potencia']}W');
      debugPrint(
          '[FLUTTER PARSED DEBUG] - Energía: ${parsedData['energia']}Wh');

      return parsedData;
    } catch (e) {
      debugPrint('[MQTT DEBUG] Error parsing AWG JSON: $e');
      debugPrint(
          '[ENERGIA DEBUG] Error durante parsing - campo "e" no pudo procesarse');
      return {};
    }
  }

  /// Parsea una línea CSV (formato del script Python) a un mapa con claves semánticas.
  /// El parámetro "source" indica el origen ("MQTT" o "BLE").
  static Map<String, dynamic> parseCsvLine(String line,
      {String source = "MQTT"}) {
    final parts = line.split(',');
    if (parts.length < 29) return {};

    final dateParts = parts[0].split('-');
    final timeParts = parts[1].split(':');

    int getInt(List<String> arr, int idx) =>
        int.tryParse(arr.length > idx ? arr[idx] : '0') ?? 0;

    double getDouble(int idx) =>
        double.tryParse(parts.length > idx ? parts[idx] : '0') ?? 0.0;

    return {
      'date_year': getInt(dateParts, 0),
      'date_month': getInt(dateParts, 1),
      'date_day': getInt(dateParts, 2),
      'time_hour': getInt(timeParts, 0),
      'time_minute': getInt(timeParts, 1),
      'time_second': getInt(timeParts, 2),
      'voltage_a': getDouble(2),
      'voltage_b': getDouble(3),
      'voltage_c': getDouble(4),
      'current_a': getDouble(5),
      'current_b': getDouble(6),
      'current_c': getDouble(7),
      'realPower_a': getDouble(8),
      'realPower_b': getDouble(9),
      'realPower_c': getDouble(10),
      'reactivePower_a': getDouble(11),
      'reactivePower_b': getDouble(12),
      'reactivePower_c': getDouble(13),
      'apparentPower_a': getDouble(14),
      'apparentPower_b': getDouble(15),
      'apparentPower_c': getDouble(16),
      'totalRealPower': getDouble(17),
      'totalReactivePower': getDouble(18),
      'totalApparentPower': getDouble(19),
      'powerFactor': getDouble(20),
      'frequency': getDouble(21),
      'temperature': getDouble(22),
      'phase_a': getDouble(23),
      'phase_b': getDouble(24),
      'phase_c': getDouble(25),
      'totalActiveFundPower': getDouble(26),
      'totalActiveHarPower': getDouble(27),
      'source': source,
      'timestamp': DateTime.tryParse(
            '${dateParts[0].padLeft(4, '0')}-${dateParts[1].padLeft(2, '0')}-${dateParts[2].padLeft(2, '0')} '
            '${timeParts[0].padLeft(2, '0')}:${timeParts[1].padLeft(2, '0')}:${timeParts[2].padLeft(2, '0')}',
          )?.millisecondsSinceEpoch ??
          DateTime.now().millisecondsSinceEpoch,
    };
  }

  /// Maneja datos recibidos por MQTT, los guarda y actualiza el notifier en tiempo real.
  void onMqttDataReceived(String value) {
    debugPrint('[MQTT DEBUG] ===== NUEVOS DATOS MQTT RECIBIDOS =====');
    debugPrint('[MQTT DEBUG] Payload crudo: $value');

    Map<String, dynamic> data;

    // Intentar parsear como JSON (AWG ESP32) primero
    if (value.trim().startsWith('{')) {
      debugPrint('[MQTT DEBUG] Detectado formato JSON, parseando...');
      data = parseAwgJson(value, source: "MQTT");
    } else {
      // Fallback a CSV (formato legacy)
      debugPrint('[MQTT DEBUG] Detectado formato CSV, parseando...');
      data = parseCsvLine(value, source: "MQTT");
    }

    debugPrint('[MQTT DEBUG] Datos parseados exitosamente:');
    debugPrint('[MQTT DEBUG] - Número de campos: ${data.length}');
    debugPrint('[MQTT DEBUG] - Campos disponibles: ${data.keys.toList()}');

    // Mostrar TODOS los valores para debugging exhaustivo
    debugPrint('[MQTT DEBUG] === VALORES ELÉCTRICOS PROCESADOS ===');
    debugPrint('[MQTT DEBUG] - Voltaje: ${data['voltaje']}V');
    debugPrint('[MQTT DEBUG] - Corriente: ${data['corriente']}A');
    debugPrint('[MQTT DEBUG] - Potencia: ${data['potencia']}W');
    debugPrint('[MQTT DEBUG] - Energía: ${data['energia']}Wh');

    // Verificar si los valores son exactamente 0.0
    if (data['voltaje'] == 0.0) debugPrint('[MQTT DEBUG] ⚠️ VOLTAJE ES 0.0');
    if (data['corriente'] == 0.0)
      debugPrint('[MQTT DEBUG] ⚠️ CORRIENTE ES 0.0');
    if (data['potencia'] == 0.0) debugPrint('[MQTT DEBUG] ⚠️ POTENCIA ES 0.0');
    if (data['energia'] == 0.0) debugPrint('[MQTT DEBUG] ⚠️ ENERGÍA ES 0.0');

    // Mostrar otros valores clave
    if (data.containsKey('temperaturaAmbiente')) {
      debugPrint(
          '[MQTT DEBUG] - Temperatura ambiente: ${data['temperaturaAmbiente']}°C');
    }
    if (data.containsKey('humedadRelativa')) {
      debugPrint(
          '[MQTT DEBUG] - Humedad relativa: ${data['humedadRelativa']}%');
    }
    if (data.containsKey('aguaAlmacenada')) {
      debugPrint('[MQTT DEBUG] - Agua almacenada: ${data['aguaAlmacenada']}L');
    }
    if (data.containsKey('energia')) {
      final energiaValue = data['energia'];
      debugPrint(
          '[MQTT DEBUG] - Energía: ${energiaValue}Wh (tipo: ${energiaValue.runtimeType})');
      if (energiaValue != null && energiaValue != 0.0) {
        debugPrint('[MQTT DEBUG] - Energía valor válido: ${energiaValue}Wh');
      } else {
        debugPrint('[MQTT DEBUG] - Energía es null o cero: ${energiaValue}Wh');
      }
    } else {
      debugPrint('[MQTT DEBUG] - Campo "energia" NO encontrado en datos');
    }

    if (data.isNotEmpty && isSavingEnabled() && dataBox != null) {
      dataBox!.add(data);
      debugPrint('[MQTT DEBUG] ✅ Datos guardados en Hive correctamente');
    } else {
      debugPrint('[MQTT DEBUG] ❌ No se guardaron datos:');
      debugPrint('[MQTT DEBUG]   - Datos vacíos: ${data.isEmpty}');
      debugPrint('[MQTT DEBUG]   - Guardado habilitado: ${isSavingEnabled()}');
      debugPrint('[MQTT DEBUG]   - DataBox disponible: ${dataBox != null}');
    }

    // Notifica a la app en TIEMPO REAL con actualización inmediata de valores eléctricos
    debugPrint('[MQTT DEBUG] Actualizando notifier global...');
    final oldNotifierValue = SingletonMqttService().notifier.value;
    debugPrint('[MQTT DEBUG] - Campos anteriores: ${oldNotifierValue.length}');

    // === ACTUALIZACIÓN INMEDIATA PARA VALORES ELÉCTRICOS ===
    // Asegurar que voltaje, corriente, potencia y energía se actualicen inmediatamente
    final currentNotifier = SingletonMqttService().notifier.value;

    // Crear nuevo mapa con valores eléctricos forzados
    final updatedData = {
      ...currentNotifier,
      ...data,
      // Forzar actualización inmediata de valores eléctricos
      'voltaje': data['voltaje'] ?? currentNotifier['voltaje'] ?? 0.0,
      'corriente': data['corriente'] ?? currentNotifier['corriente'] ?? 0.0,
      'potencia': data['potencia'] ?? currentNotifier['potencia'] ?? 0.0,
      'energia': data['energia'] ?? currentNotifier['energia'] ?? 0.0,
    };

    SingletonMqttService().notifier.value = updatedData;

    final newNotifierValue = SingletonMqttService().notifier.value;
    debugPrint('[MQTT DEBUG] - Campos después: ${newNotifierValue.length}');

    // Debug específico de valores eléctricos
    debugPrint('[MQTT DEBUG] ⚡ VALORES ELÉCTRICOS ACTUALIZADOS:');
    debugPrint('[MQTT DEBUG]   - Voltaje: ${newNotifierValue['voltaje']}V');
    debugPrint('[MQTT DEBUG]   - Corriente: ${newNotifierValue['corriente']}A');
    debugPrint('[MQTT DEBUG]   - Potencia: ${newNotifierValue['potencia']}W');
    debugPrint('[MQTT DEBUG]   - Energía: ${newNotifierValue['energia']}Wh');

    debugPrint('[MQTT DEBUG] ✅ Notifier actualizado correctamente');
    debugPrint('[MQTT DEBUG] ===== FIN PROCESAMIENTO DATOS =====');
  }

  /// Obtener estado del compresor (0=OFF, 1=ON)
  int getCompressorState() {
    return SingletonMqttService().notifier.value['estadoCompresor'] ?? 0;
  }

  /// Stream para que otras partes de la app puedan escuchar nuevos datos históricos.
  Stream<Map<String, dynamic>> get dataStream async* {
    if (dataBox == null) return;

    for (int i = 0; i < dataBox!.length; i++) {
      yield dataBox!.getAt(i)!.cast<String, dynamic>();
    }
    await for (final _ in dataBox!.watch()) {
      if (dataBox!.isNotEmpty) {
        yield dataBox!.getAt(dataBox!.length - 1)!.cast<String, dynamic>();
      }
    }
  }
}

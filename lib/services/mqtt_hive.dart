import 'package:hive_flutter/hive_flutter.dart';
import 'singleton_mqtt_service.dart';

/// Servicio para integrar MQTT y Hive.
/// Permite guardar, recuperar y notificar datos energéticos en la app.
/// Incluye utilidades para parsear datos, habilitar/deshabilitar guardado y manejar streams históricos.
class MqttHiveService {
  static Box<Map>? dataBox;      // Box de Hive para datos energéticos históricos
  static Box? settingsBox;       // Box de Hive para configuraciones (nominales, flags)
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

  /// Parsea una línea CSV (formato del script Python) a un mapa con claves semánticas.
  /// El parámetro "source" indica el origen ("MQTT" o "BLE").
  static Map<String, dynamic> parseCsvLine(String line, {String source = "MQTT"}) {
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
      'battery': getDouble(28),
      'source': source,
      'timestamp': DateTime.tryParse(
        '${dateParts[0].padLeft(4, '0')}-${dateParts[1].padLeft(2, '0')}-${dateParts[2].padLeft(2, '0')} '
        '${timeParts[0].padLeft(2, '0')}:${timeParts[1].padLeft(2, '0')}:${timeParts[2].padLeft(2, '0')}',
      )?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch,
    };
  }

  /// Maneja datos recibidos por BLE, los guarda y actualiza el notifier en tiempo real.
  /// Convierte los bytes a string, los parsea, guarda en Hive y actualiza la UI.
  void onBluetoothDataReceived(List<int> value, {String source = "BLE"}) {
    final str = String.fromCharCodes(value);
    final data = parseCsvLine(str, source: source);
    if (data.isNotEmpty && isSavingEnabled() && dataBox != null) {
      dataBox!.add(data);
    }
    // Notifica a la app en TIEMPO REAL (MERGE en vez de REEMPLAZAR)
    SingletonMqttService().notifier.value = {
      ...SingletonMqttService().notifier.value,
      ...data
    };
  }

  /// Maneja datos recibidos por MQTT, los guarda y actualiza el notifier en tiempo real.
  void onMqttDataReceived(String value) {
    final data = parseCsvLine(value, source: "MQTT");
    if (data.isNotEmpty && isSavingEnabled() && dataBox != null) {
      dataBox!.add(data);
    }
    // Notifica a la app en TIEMPO REAL (MERGE en vez de REEMPLAZAR)
    SingletonMqttService().notifier.value = {
      ...SingletonMqttService().notifier.value,
      ...data
    };
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

  /// Desconecta Bluetooth (implementación vacía para compatibilidad)
  void disconnectBluetooth() {}
}
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io' show Platform;

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // Configuración de notificaciones
  bool _initialized = false;
  static const String _channelId = 'dropster_alerts';
  static const String _channelName = 'Alertas Dropster';
  static const String _channelDescription =
      'Notificaciones de alertas y anomalías del sistema';

  // Umbrales para alertas
  static const double TEMP_HIGH_THRESHOLD = 35.0; // °C
  static const double TANK_FULL_THRESHOLD = 95.0; // %
  static const double BATTERY_LOW_THRESHOLD = 2.5; // V

  // Método para mostrar notificaciones usando SnackBar
  static void showNotification(
      BuildContext context, String title, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 4),
            Text(message),
          ],
        ),
        backgroundColor: Colors.blue,
        duration: const Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  // Método para guardar notificaciones en Hive
  static Future<void> saveNotification(
      String title, String message, String type) async {
    final notificationsBox = await Hive.openBox('notifications');

    await notificationsBox.add({
      'title': title,
      'message': message,
      'type': type,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'read': false,
    });
  }

  // Método para obtener todas las notificaciones
  static Future<List<Map>> getAllNotifications() async {
    final notificationsBox = await Hive.openBox('notifications');
    final allNotifications = notificationsBox.values.whereType<Map>().toList();

    // Ordenar por timestamp (más reciente primero)
    allNotifications
        .sort((a, b) => (b['timestamp'] ?? 0).compareTo(a['timestamp'] ?? 0));

    return allNotifications;
  }

  // Método para marcar notificación como leída
  static Future<void> markAsRead(int index) async {
    final notificationsBox = await Hive.openBox('notifications');
    final notifications = notificationsBox.values.whereType<Map>().toList();

    if (index < notifications.length) {
      final notification = Map<String, dynamic>.from(notifications[index]);
      notification['read'] = true;
      await notificationsBox.putAt(index, notification);
    }
  }

  // Método para borrar todas las notificaciones
  static Future<void> clearAllNotifications() async {
    final notificationsBox = await Hive.openBox('notifications');
    await notificationsBox.clear();
  }

  // Método para obtener notificaciones no leídas
  static Future<List<Map>> getUnreadNotifications() async {
    final allNotifications = await getAllNotifications();
    return allNotifications
        .where((notification) => notification['read'] == false)
        .toList();
  }

  // Método para obtener el número de notificaciones no leídas
  static Future<int> getUnreadCount() async {
    final unreadNotifications = await getUnreadNotifications();
    return unreadNotifications.length;
  }

  // ===== MÉTODOS PARA NOTIFICACIONES PUSH REALES =====

  /// Inicializar el servicio de notificaciones push
  Future<void> initialize() async {
    if (_initialized) return;

    // Configuración para Android
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    // Configuración para iOS
    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    // Configuración general
    const InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    // Crear canal de notificaciones para Android
    await _createNotificationChannel();

    // Inicializar plugin
    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    _initialized = true;
    debugPrint('✅ Servicio de notificaciones inicializado');
  }

  /// Crear canal de notificaciones para Android
  Future<void> _createNotificationChannel() async {
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDescription,
      importance: Importance.high,
      showBadge: true,
      enableVibration: true,
      playSound: true,
    );

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  /// Solicitar permisos de notificaciones
  Future<bool> requestPermissions() async {
    if (Platform.isAndroid) {
      // Para Android 13+ (API 33+)
      final androidStatus = await Permission.notification.request();
      return androidStatus.isGranted;
    } else if (Platform.isIOS) {
      // Para iOS
      final iosStatus = await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );
      return iosStatus ?? false;
    }
    return false;
  }

  /// Mostrar notificación push
  Future<void> showPushNotification({
    required String title,
    required String body,
    String? payload,
    int? id,
  }) async {
    if (!_initialized) {
      await initialize();
    }

    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.high,
      showWhen: true,
      enableVibration: true,
      playSound: true,
      icon: '@mipmap/ic_launcher',
    );

    const DarwinNotificationDetails iosPlatformChannelSpecifics =
        DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
      iOS: iosPlatformChannelSpecifics,
    );

    await flutterLocalNotificationsPlugin.show(
      id ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      platformChannelSpecifics,
      payload: payload,
    );

    debugPrint('🔔 Notificación push mostrada: $title');
  }

  /// Manejar cuando se toca una notificación
  void _onNotificationTapped(NotificationResponse response) {
    debugPrint('📱 Notificación tocada: ${response.payload}');
    // Aquí puedes navegar a una pantalla específica
  }

  // ===== MÉTODOS PARA DETECTAR ANOMALÍAS Y MOSTRAR ALERTAS =====

  /// Procesar datos MQTT y detectar anomalías
  Future<void> processSensorData(Map<String, dynamic> sensorData) async {
    debugPrint('[NOTIFICATION DEBUG] 🔍 Procesando datos de sensores para notificaciones...');
    
    final settingsBox = await Hive.openBox('settings');
    final showNotifications =
        settingsBox.get('showNotifications', defaultValue: true);

    if (!showNotifications) {
      debugPrint('[NOTIFICATION DEBUG] ⚠️ Notificaciones deshabilitadas en configuración');
      return;
    }
    
    debugPrint('[NOTIFICATION DEBUG] ✅ Notificaciones habilitadas, verificando umbrales...');

    // Obtener umbrales configurables
    final tankFullEnabled =
        settingsBox.get('tankFullEnabled', defaultValue: true);
    final voltageLowEnabled =
        settingsBox.get('voltageLowEnabled', defaultValue: true);
    final humidityLowEnabled =
        settingsBox.get('humidityLowEnabled', defaultValue: true);

    final tankFullThreshold =
        settingsBox.get('tankFullThreshold', defaultValue: 90.0);
    final voltageLowThreshold =
        settingsBox.get('voltageLowThreshold', defaultValue: 100.0);
    final humidityLowThreshold =
        settingsBox.get('humidityLowThreshold', defaultValue: 30.0);

    // Verificar temperatura alta
    final tempAmbiente = sensorData['temperaturaAmbiente'];
    if (tempAmbiente != null &&
        tempAmbiente is num &&
        tempAmbiente > TEMP_HIGH_THRESHOLD) {
      await _showTemperatureAlert(tempAmbiente.toDouble());
    }

    // Verificar tanque lleno usando umbral configurable
    if (tankFullEnabled) {
      final aguaAlmacenada = sensorData['aguaAlmacenada'];
      final tankCapacity =
          settingsBox.get('tankCapacity', defaultValue: 1000.0);

      if (aguaAlmacenada != null && aguaAlmacenada is num && tankCapacity > 0) {
        final aguaLitros = aguaAlmacenada.toDouble();
        final capacidadLitros = tankCapacity.toDouble();

        // Calcular porcentaje de llenado
        final porcentajeLlenado = (aguaLitros / capacidadLitros) * 100.0;
        
        debugPrint('[NOTIFICATION DEBUG] 💧 Verificando tanque: ${aguaLitros}L/${capacidadLitros}L (${porcentajeLlenado.toStringAsFixed(1)}%) - umbral: ${tankFullThreshold}%');

        // Mostrar alerta si supera el umbral configurado
        if (porcentajeLlenado >= tankFullThreshold) {
          debugPrint('[NOTIFICATION DEBUG] 🚨 ALERTA: Tanque lleno detectado!');
          await _showTankFullAlert(
              aguaLitros, capacidadLitros, porcentajeLlenado);
        }
      }
    }

    // Verificar voltaje bajo usando umbral configurable
    if (voltageLowEnabled) {
      final voltaje = sensorData['voltaje'];
      debugPrint('[NOTIFICATION DEBUG] ⚡ Verificando voltaje: ${voltaje}V (umbral: ${voltageLowThreshold}V)');
      if (voltaje != null && voltaje is num && voltaje < voltageLowThreshold) {
        debugPrint('[NOTIFICATION DEBUG] 🚨 ALERTA: Voltaje bajo detectado!');
        await _showVoltageLowAlert(voltaje.toDouble(), voltageLowThreshold);
      }
    }

    // Verificar humedad baja usando umbral configurable
    if (humidityLowEnabled) {
      final humedad = sensorData['humedadRelativa'];
      debugPrint('[NOTIFICATION DEBUG] 💨 Verificando humedad: ${humedad}% (umbral: ${humidityLowThreshold}%)');
      if (humedad != null && humedad is num && humedad < humidityLowThreshold) {
        debugPrint('[NOTIFICATION DEBUG] 🚨 ALERTA: Humedad baja detectada!');
        await _showHumidityLowAlert(humedad.toDouble(), humidityLowThreshold);
      }
    }

    // Verificar batería baja (mantiene umbral fijo)
    final bateria = sensorData['bateria'];
    if (bateria != null && bateria is num && bateria < BATTERY_LOW_THRESHOLD) {
      await _showBatteryLowAlert(bateria.toDouble());
    }
  }

  /// Mostrar alerta de temperatura alta
  Future<void> _showTemperatureAlert(double temperature) async {
    const title = '🌡️ ¡TEMPERATURA ALTA!';
    final body =
        'Temperatura ambiente: ${temperature.toStringAsFixed(1)}°C\nVerifique el sistema de enfriamiento.';

    await showPushNotification(
      title: title,
      body: body,
      payload: 'temperature_high',
    );

    // Guardar en anomalías
    await saveNotification(
      'Temperatura Alta Detectada',
      'Temperatura ambiente: ${temperature.toStringAsFixed(1)}°C',
      'temperature_high',
    );
  }

  /// Mostrar alerta de tanque lleno
  Future<void> _showTankFullAlert(double aguaLitros, double capacidadLitros,
      double porcentajeLlenado) async {
    const title = '💧 ¡TANQUE LLENO!';
    final body =
        'Agua almacenada: ${aguaLitros.toStringAsFixed(1)}L de ${capacidadLitros.toStringAsFixed(0)}L\n'
        'Porcentaje: ${porcentajeLlenado.toStringAsFixed(1)}%\n'
        'Considere drenar o usar el agua almacenada.';

    await showPushNotification(
      title: title,
      body: body,
      payload: 'tank_full',
    );

    // Guardar en anomalías
    await saveNotification(
      'Tanque Lleno',
      'Agua almacenada: ${aguaLitros.toStringAsFixed(1)}L (${porcentajeLlenado.toStringAsFixed(1)}%)',
      'tank_full',
    );
  }

  /// Mostrar alerta de batería baja
  Future<void> _showBatteryLowAlert(double batteryVoltage) async {
    const title = '🔋 ¡BATERÍA BAJA!';
    final body =
        'Voltaje de batería: ${batteryVoltage.toStringAsFixed(2)}V\nConsidere cambiar la batería pronto.';

    await showPushNotification(
      title: title,
      body: body,
      payload: 'battery_low',
    );

    // Guardar en anomalías
    await saveNotification(
      'Batería Baja',
      'Voltaje de batería: ${batteryVoltage.toStringAsFixed(2)}V',
      'battery_low',
    );
  }

  /// Mostrar alerta de voltaje bajo
  Future<void> _showVoltageLowAlert(double voltage, double threshold) async {
    const title = '⚡ ¡VOLTAJE BAJO!';
    final body = 'Voltaje detectado: ${voltage.toStringAsFixed(0)}V\n'
        'Umbral configurado: ${threshold.toStringAsFixed(0)}V\n'
        'Verifique la alimentación eléctrica o el AWG.';

    await showPushNotification(
      title: title,
      body: body,
      payload: 'voltage_low',
    );

    // Guardar en anomalías
    await saveNotification(
      'Voltaje Bajo Detectado',
      'Voltaje: ${voltage.toStringAsFixed(0)}V (Umbral: ${threshold.toStringAsFixed(0)}V)',
      'voltage_low',
    );
  }

  /// Mostrar alerta de humedad baja
  Future<void> _showHumidityLowAlert(double humidity, double threshold) async {
    const title = '💨 ¡HUMEDAD BAJA!';
    final body = 'Humedad relativa: ${humidity.toStringAsFixed(1)}%\n'
        'Umbral configurado: ${threshold.toStringAsFixed(1)}%\n'
        'La eficiencia del sistema puede verse afectada.';

    await showPushNotification(
      title: title,
      body: body,
      payload: 'humidity_low',
    );

    // Guardar en anomalías
    await saveNotification(
      'Humedad Baja Detectada',
      'Humedad: ${humidity.toStringAsFixed(1)}% (Umbral: ${threshold.toStringAsFixed(1)}%)',
      'humidity_low',
    );
  }

  /// Verificar estado de permisos
  Future<bool> checkPermissions() async {
    final status = await Permission.notification.status;
    return status.isGranted;
  }
}

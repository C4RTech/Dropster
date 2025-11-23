import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'background_mqtt_service.dart';

class BackgroundServiceManager {
  static final BackgroundServiceManager _instance =
      BackgroundServiceManager._internal();
  factory BackgroundServiceManager() => _instance;
  BackgroundServiceManager._internal();

  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // Servicio foreground simple
  Future<void> initializeSimpleForegroundService() async {
    try {
      debugPrint(
          '[BACKGROUND_SERVICE] Iniciando servicio foreground simple...');
      final service = FlutterBackgroundService();

      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'dropster_simple',
        'Dropster Simple Monitor',
        description: 'Simple monitoring service',
        importance: Importance.low,
        playSound: false,
        enableVibration: false,
        showBadge: false,
      );

      await service.configure(
        androidConfiguration: AndroidConfiguration(
          onStart: _onSimpleForegroundStart,
          autoStart: false,
          isForegroundMode: true,
          notificationChannelId: 'dropster_simple',
          initialNotificationTitle: 'Dropster',
          initialNotificationContent: 'Monitoring active',
          foregroundServiceNotificationId: 999,
        ),
        iosConfiguration: IosConfiguration(
          autoStart: false,
          onForeground: _onSimpleForegroundStart,
        ),
      );

      await service.startService();
      debugPrint(
          '[BACKGROUND_SERVICE] ✅ Servicio foreground simple iniciado exitosamente');
    } catch (e, stackTrace) {
      debugPrint(
          '[BACKGROUND_SERVICE] ❌ Error iniciando servicio foreground: $e');
      debugPrint('[BACKGROUND_SERVICE] StackTrace: $stackTrace');
      rethrow;
    }
  }

  Future<void> stopSimpleService() async {
    try {
      debugPrint(
          '[BACKGROUND_SERVICE] Deteniendo servicio foreground simple...');
      final service = FlutterBackgroundService();
      service.invoke('stop');
      debugPrint(
          '[BACKGROUND_SERVICE] ✅ Servicio foreground simple detenido exitosamente');
    } catch (e, stackTrace) {
      debugPrint(
          '[BACKGROUND_SERVICE] ❌ Error deteniendo servicio foreground: $e');
      debugPrint('[BACKGROUND_SERVICE] StackTrace: $stackTrace');
      rethrow;
    }
  }

  // Método de compatibilidad
  Future<void> initializeMinimalForegroundService() async {
    await initializeSimpleForegroundService();
  }
}

@pragma('vm:entry-point')
Future<void> _onSimpleForegroundStart(ServiceInstance service) async {
  try {
    debugPrint(
        '[BACKGROUND_SERVICE] Servicio foreground iniciado, configurando listeners...');
    service.on('stop').listen((event) {
      debugPrint(
          '[BACKGROUND_SERVICE] Recibida señal de stop, deteniendo servicio...');
      service.stopSelf();
    });

    // Inicializar el servicio MQTT de background dentro del entrypoint
    try {
      // Cargar e inicializar el servicio que gestionará MQTT en background
      debugPrint('[BACKGROUND_SERVICE] Inicializando BackgroundMqttService...');
      await BackgroundMqttService().initialize();
      debugPrint('[BACKGROUND_SERVICE] BackgroundMqttService inicializado');
    } catch (e, st) {
      debugPrint(
          '[BACKGROUND_SERVICE] Error inicializando BackgroundMqttService: $e');
      debugPrint('[BACKGROUND_SERVICE] Stack: $st');
    }

    // Mantener servicio vivo
    Timer.periodic(const Duration(seconds: 30), (timer) {
      debugPrint('[BACKGROUND_SERVICE] Timer ejecutándose cada 30 segundos...');
      // Servicio simple sin lógica compleja
    });
    debugPrint(
        '[BACKGROUND_SERVICE] ✅ Servicio foreground configurado y ejecutándose');
  } catch (e, stackTrace) {
    debugPrint('[BACKGROUND_SERVICE] ❌ Error en _onSimpleForegroundStart: $e');
    debugPrint('[BACKGROUND_SERVICE] StackTrace: $stackTrace');
  }
}

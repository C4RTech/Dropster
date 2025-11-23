import 'dart:async';
import 'package:flutter/material.dart';
import 'singleton_mqtt_service.dart';

/// Servicio para manejar el ciclo de vida de la aplicación y optimizar MQTT
class AppLifecycleService {
  static final AppLifecycleService _instance = AppLifecycleService._internal();
  factory AppLifecycleService() => _instance;

  AppLifecycleService._internal();

  AppLifecycleState _currentState = AppLifecycleState.resumed;
  Timer? _backgroundTimer;
  Timer? _fastUpdateTimer;

  // Configuración de intervalos
  static const Duration _backgroundCheckInterval = Duration(minutes: 5);
  static const Duration _fastUpdateInterval = Duration(seconds: 5);
  static const Duration _normalUpdateInterval = Duration(seconds: 15);

  /// Estado actual de la aplicación
  AppLifecycleState get currentState => _currentState;

  /// Inicializa el servicio con el contexto de la aplicación
  void initialize(BuildContext context) {
    // Escuchar cambios en el ciclo de vida
    WidgetsBinding.instance.addObserver(_AppLifecycleObserver(this));
  }

  /// Maneja cambios en el estado de la aplicación
  void _handleLifecycleChange(AppLifecycleState state) {
    if (_currentState == state) return;

    _currentState = state;
    debugPrint('[LIFECYCLE] Estado cambió a: $state');

    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        _enterBackgroundMode();
        break;
      case AppLifecycleState.resumed:
        _enterForegroundMode();
        break;
    }
  }

  /// Configura el modo background para ahorrar batería
  void _enterBackgroundMode() {
    debugPrint('[LIFECYCLE] Entrando en modo background');

    // Configurar MQTT para background
    SingletonMqttService().setBackgroundMode(true);

    // Iniciar timer para verificaciones periódicas en background
    _backgroundTimer?.cancel();
    _backgroundTimer = Timer.periodic(_backgroundCheckInterval, (_) {
      debugPrint('[LIFECYCLE] Verificación periódica en background');
      // Aquí se puede agregar lógica adicional para background
    });

    // Detener actualizaciones rápidas
    _stopFastUpdates();
  }

  /// Configura el modo foreground para máxima responsiveness
  void _enterForegroundMode() {
    debugPrint('[LIFECYCLE] Entrando en modo foreground');

    // Configurar MQTT para foreground
    SingletonMqttService().setBackgroundMode(false);

    // Cancelar timer de background
    _backgroundTimer?.cancel();

    // Iniciar actualizaciones rápidas por un tiempo limitado
    _startFastUpdates();
  }

  /// Inicia actualizaciones rápidas temporalmente
  void _startFastUpdates() {
    debugPrint('[LIFECYCLE] Iniciando actualizaciones rápidas');
    _fastUpdateTimer?.cancel();

    // Actualizaciones rápidas por 2 minutos
    _fastUpdateTimer = Timer.periodic(_fastUpdateInterval, (_) {
      // Lógica para actualizaciones rápidas si es necesario
      debugPrint('[LIFECYCLE] Actualización rápida ejecutada');
    });

    // Después de 2 minutos, volver a velocidad normal
    Future.delayed(const Duration(minutes: 2), () {
      _stopFastUpdates();
    });
  }

  /// Detiene las actualizaciones rápidas
  void _stopFastUpdates() {
    debugPrint('[LIFECYCLE] Deteniendo actualizaciones rápidas');
    _fastUpdateTimer?.cancel();
    _fastUpdateTimer = null;
  }

  /// Libera recursos
  void dispose() {
    _backgroundTimer?.cancel();
    _fastUpdateTimer?.cancel();
  }
}

/// Observer para el ciclo de vida de Flutter
class _AppLifecycleObserver extends WidgetsBindingObserver {
  final AppLifecycleService _service;

  _AppLifecycleObserver(this._service);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _service._handleLifecycleChange(state);
  }
}

import 'package:flutter/material.dart';

/// Servicio centralizado para manejo de errores en la aplicación
class ErrorHandlerService {
  static final ErrorHandlerService _instance = ErrorHandlerService._internal();
  factory ErrorHandlerService() => _instance;
  ErrorHandlerService._internal();

  /// Muestra un diálogo de error al usuario
  void showErrorDialog(BuildContext context, String title, String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Aceptar'),
            ),
          ],
        );
      },
    );
  }

  /// Muestra un snackbar con mensaje de error
  void showErrorSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'Cerrar',
          textColor: Colors.white,
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
      ),
    );
  }

  /// Maneja errores de conexión MQTT
  void handleMqttError(BuildContext context, dynamic error) {
    String message = _getMqttErrorMessage(error);
    showErrorSnackBar(context, message);
  }

  /// Maneja errores de inicialización
  void handleInitializationError(BuildContext context, dynamic error) {
    String message = _getInitializationErrorMessage(error);
    showErrorDialog(context, 'Error de Inicialización', message);
  }

  /// Maneja errores generales
  void handleGenericError(BuildContext context, dynamic error) {
    String message = _getGenericErrorMessage(error);
    showErrorSnackBar(context, message);
  }

  /// Convierte errores técnicos en mensajes amigables para el usuario
  String _getMqttErrorMessage(dynamic error) {
    String errorStr = error.toString().toLowerCase();

    if (errorStr.contains('connection refused')) {
      return 'No se pudo conectar al servidor MQTT. Verifica tu conexión a internet.';
    } else if (errorStr.contains('timeout')) {
      return 'Tiempo de espera agotado. El servidor MQTT no responde.';
    } else if (errorStr.contains('authentication')) {
      return 'Error de autenticación MQTT. Verifica las credenciales.';
    } else if (errorStr.contains('network')) {
      return 'Error de red. Verifica tu conexión a internet.';
    } else {
      return 'Error de conexión MQTT: ${error.toString()}';
    }
  }

  String _getInitializationErrorMessage(dynamic error) {
    String errorStr = error.toString().toLowerCase();

    if (errorStr.contains('hive')) {
      return 'Error al inicializar el almacenamiento local. La aplicación puede no funcionar correctamente.';
    } else if (errorStr.contains('permission')) {
      return 'Error de permisos. La aplicación necesita permisos para funcionar correctamente.';
    } else if (errorStr.contains('storage')) {
      return 'Error de almacenamiento. Verifica que haya espacio disponible en el dispositivo.';
    } else {
      return 'Error durante la inicialización: ${error.toString()}';
    }
  }

  String _getGenericErrorMessage(dynamic error) {
    String errorStr = error.toString().toLowerCase();

    if (errorStr.contains('network')) {
      return 'Error de conexión. Verifica tu conexión a internet.';
    } else if (errorStr.contains('timeout')) {
      return 'Operación cancelada por tiempo de espera.';
    } else if (errorStr.contains('permission')) {
      return 'Error de permisos. Verifica que la aplicación tenga los permisos necesarios.';
    } else {
      return 'Ha ocurrido un error inesperado.';
    }
  }

  /// Registra errores en el log (solo en modo debug)
  void logError(String context, dynamic error, [StackTrace? stackTrace]) {
    debugPrint('[ERROR HANDLER] $context: $error');
    if (stackTrace != null) {
      debugPrint('[ERROR HANDLER] Stack trace: $stackTrace');
    }
  }
}

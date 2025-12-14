import 'package:flutter/foundation.dart';
import '../notification_service.dart';

/// Gestiona notificaciones para reportes diarios
class DailyReportNotifier {
  /// Función helper para logs condicionales
  void _log(String message) {
    if (kDebugMode) {
      debugPrint('[REPORT-NOTIFIER] $message');
    }
  }

  /// Enviar notificación profesional de reporte diario
  Future<void> sendProfessionalNotification(Map<String, dynamic> report) async {
    try {
      // Asegurar que el servicio de notificaciones esté inicializado
      await NotificationService().initialize();

      final title = '📊 Reporte Diario - ${report['date']}';
      final body = _generateNotificationBody(report);

      _log('Enviando notificación con título: $title');

      // Enviar notificación profesional de reporte diario
      await NotificationService().showDailyReportNotification(
        title: title,
        body: body,
      );

      _log('Notificación showDailyReportNotification enviada');

      // Guardar en historial de notificaciones
      await NotificationService.saveNotification(
        title,
        body,
        'daily_report_professional',
      );

      _log('Notificación guardada en historial');
      _log('📱 Notificación profesional enviada');
    } catch (e, stackTrace) {
      _log('❌ Error enviando notificación profesional: $e');
      _log('StackTrace: $stackTrace');
      rethrow;
    }
  }

  /// Enviar notificación de error
  Future<void> sendErrorNotification(String error) async {
    try {
      await NotificationService().initialize();
      await NotificationService().showPushNotification(
        title: '❌ Error en Reporte Diario',
        body: 'No se pudo generar el reporte: $error',
      );
    } catch (e) {
      _log('❌ Error enviando notificación de error: $e');
    }
  }

  /// Generar cuerpo de notificación
  String _generateNotificationBody(Map<String, dynamic> report) {
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

  /// Enviar notificación de prueba
  Future<void> sendTestNotification() async {
    try {
      await NotificationService().initialize();
      await NotificationService().showPushNotification(
        title: '🧪 Notificación de Prueba',
        body:
            'Esta es una notificación de prueba del sistema de reportes diarios.',
      );
      _log('Notificación de prueba enviada');
    } catch (e) {
      _log('Error enviando notificación de prueba: $e');
    }
  }

  /// Verificar permisos de notificación
  Future<bool> checkNotificationPermissions() async {
    try {
      return await NotificationService().checkPermissions();
    } catch (e) {
      _log('Error verificando permisos de notificación: $e');
      return false;
    }
  }

  /// Solicitar permisos de notificación
  Future<bool> requestNotificationPermissions() async {
    try {
      await NotificationService().requestPermissions();
      return await checkNotificationPermissions();
    } catch (e) {
      _log('Error solicitando permisos de notificación: $e');
      return false;
    }
  }
}

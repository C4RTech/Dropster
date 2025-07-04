import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  // Método para mostrar notificaciones usando SnackBar
  static void showNotification(BuildContext context, String title, String message) {
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
  static Future<void> saveNotification(String title, String message, String type) async {
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
    allNotifications.sort((a, b) => (b['timestamp'] ?? 0).compareTo(a['timestamp'] ?? 0));
    
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
    return allNotifications.where((notification) => notification['read'] == false).toList();
  }

  // Método para obtener el número de notificaciones no leídas
  static Future<int> getUnreadCount() async {
    final unreadNotifications = await getUnreadNotifications();
    return unreadNotifications.length;
  }
} 
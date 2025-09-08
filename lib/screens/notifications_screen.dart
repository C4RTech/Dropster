import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import '../services/singleton_mqtt_service.dart';

class NotificationsScreen extends StatefulWidget {
  @override
  _NotificationsScreenState createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<Map> _allAnomalies = [];
  List<Map> _visibleAnomalies = [];
  int _itemsToShow = 20;

  String _selectedPhase = "Todas";
  String _selectedType = "Todos";
  DateTimeRange? _selectedRange;

  static const Color appBarColor = Color(0xFF1D347A);

  static const Map<String, Color> phaseColors = {
    "A": Colors.blue,
    "B": Colors.green,
    "C": Colors.red,
    "Todas": Colors.grey,
  };

  static const Map<String, String> typeLabels = {
    "Todos": "Todos",
    "current": "Corriente",
    "voltage": "Voltaje",
    "frequency": "Frecuencia",
    "tank_level": "Nivel Tanque",
  };

  static const Map<String, IconData> typeIcons = {
    "Todos": Icons.notifications,
    "current": Icons.flash_on,
    "voltage": Icons.bolt,
    "frequency": Icons.waves,
    "tank_level": Icons.water_drop, // Notificación de nivel del tanque
  };

  ValueNotifier<Map<String, dynamic>> get globalNotifier =>
      SingletonMqttService().notifier;

  double? nominalVoltage;
  double? nominalCurrent;

  @override
  void initState() {
    super.initState();
    _loadNominals();
    _loadAndShowAnomalies();
    globalNotifier.addListener(_onNotifierChanged);
  }

  @override
  void dispose() {
    globalNotifier.removeListener(_onNotifierChanged);
    super.dispose();
  }

  Future<void> _loadNominals() async {
    await Hive.openBox('settings');
    final settingsBox = Hive.box('settings');
    nominalVoltage = settingsBox.get('nominalVoltage', defaultValue: 110.0);
    nominalCurrent = settingsBox.get('nominalCurrent', defaultValue: 10.0);
    setState(() {});
  }

  void _onNotifierChanged() {
    setState(() {}); // recarga el estado del ícono de batería
    _loadAndShowAnomalies();
  }

  Future<List<Map>> _fetchAllAnomalies() async {
    await Hive.openBox('anomalies');
    final box = Hive.box('anomalies');
    final all = box.values.whereType<Map>();
    final seen = <String>{};
    final unique = <Map>[];
    for (final anomaly in all) {
      final key =
          "${anomaly['timestamp']}_${anomaly['type']}_${anomaly['phase']}_${anomaly['description']}";
      if (!seen.contains(key)) {
        seen.add(key);
        unique.add(anomaly);
      }
    }
    return unique.reversed.toList();
  }

  List<Map> _filtered(List<Map> anomalies) {
    return anomalies.where((anomaly) {
      final phase = (anomaly['phase'] ?? '').toString().toUpperCase();
      if (_selectedPhase != "Todas" && phase != _selectedPhase) return false;
      final type = anomaly['type'] ?? '';
      if (_selectedType != "Todos" && type != _selectedType) return false;
      if (_selectedRange != null) {
        final int? timestamp = anomaly['timestamp'] is int
            ? anomaly['timestamp']
            : int.tryParse(anomaly['timestamp']?.toString() ?? '');
        if (timestamp == null || timestamp == 0) return false;
        final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
        if (date.isBefore(_selectedRange!.start) ||
            date.isAfter(_selectedRange!.end)) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  Future<void> _loadAndShowAnomalies() async {
    final all = await _fetchAllAnomalies();
    _allAnomalies = all;
    final filtered = _filtered(_allAnomalies);
    int toShow = _itemsToShow.clamp(0, filtered.length);
    if (filtered.length < _itemsToShow) toShow = filtered.length;
    setState(() {
      _visibleAnomalies = filtered.take(toShow).toList();
      _itemsToShow = toShow == 0 ? 20 : toShow;
    });
  }

  Future<void> _show20More() async {
    final filtered = _filtered(_allAnomalies);
    final prev = _visibleAnomalies.length;
    final next = (prev + 20).clamp(0, filtered.length);
    setState(() {
      _itemsToShow = next;
      _visibleAnomalies = filtered.take(_itemsToShow).toList();
    });
  }

  Future<void> _clearData() async {
    await Hive.openBox('anomalies');
    final box = Hive.box('anomalies');
    await box.clear();
    setState(() {
      _allAnomalies.clear();
      _visibleAnomalies.clear();
      _itemsToShow = 20;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Notificaciones borradas'),
        backgroundColor: appBarColor,
      ),
    );
  }

  Widget _buildNotificationCard(Map anomaly) {
    final int? timestamp = anomaly['timestamp'] is int
        ? anomaly['timestamp']
        : int.tryParse(anomaly['timestamp']?.toString() ?? '');
    String dateStr = '--/--/----', timeStr = '--:--:--';
    if (timestamp != null && timestamp > 0) {
      final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
      dateStr = DateFormat('dd/MM/yyyy').format(dt);
      timeStr = DateFormat('HH:mm:ss').format(dt);
    }
    final phase = (anomaly['phase'] ?? '').toString().toUpperCase();
    final type = anomaly['type'] ?? '';
    final phaseColor = phaseColors[phase] ?? Colors.grey;

    String valueInfo = "";
    if (nominalVoltage != null && nominalCurrent != null) {
      if (type == "voltage" && anomaly["value"] != null) {
        final v = double.tryParse(anomaly["value"].toString());
        final min = nominalVoltage! * 0.98;
        final max = nominalVoltage! * 1.02;
        if (v != null) {
          valueInfo =
              " | Valor: ${v.toStringAsFixed(2)} V, Rango: ${min.toStringAsFixed(1)} - ${max.toStringAsFixed(1)}";
        }
      }
      if (type == "current" && anomaly["value"] != null) {
        final c = double.tryParse(anomaly["value"].toString());
        final min = nominalCurrent! * 0.7;
        final max = nominalCurrent! * 1.3;
        if (c != null) {
          valueInfo =
              " | Valor: ${c.toStringAsFixed(2)} A, Rango: ${min.toStringAsFixed(1)} - ${max.toStringAsFixed(1)}";
        }
      }
      if (type == "tank_level" && anomaly["value"] != null) {
        final t = double.tryParse(anomaly["value"].toString());
        if (t != null) {
          valueInfo = " | Nivel: ${(t * 100).toStringAsFixed(1)}%";
        }
      }
    }

    final title = anomaly['description'] ?? 'Anomalía';

    return Card(
      margin: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: phaseColor, width: 2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: phaseColor,
          child: Icon(
            typeIcons[type] ?? Icons.warning,
            color: Colors.white,
          ),
        ),
        title: Text(title),
        subtitle: Text(
          "$dateStr $timeStr"
          "${phase.isNotEmpty && phase != "TODAS" ? "  •  Fase $phase" : ""}"
          "$valueInfo",
        ),
        trailing: typeLabels[type] != null
            ? Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: appBarColor.withOpacity(0.07),
                  border: Border.all(color: appBarColor, width: 1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      typeIcons[type] ?? Icons.warning,
                      color: appBarColor,
                      size: 18,
                    ),
                    SizedBox(width: 4),
                    Text(
                      typeLabels[type]!,
                      style: TextStyle(
                        color: appBarColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              )
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorPrimary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notificaciones'),
        backgroundColor: colorPrimary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.clear_all),
            onPressed: _showClearDialog,
            tooltip: 'Borrar todas las notificaciones',
          ),
        ],
      ),
      body: Column(
        children: [
          // Lista de notificaciones
          Expanded(
            child: _visibleAnomalies.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.notifications_none,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No hay notificaciones',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Las alertas aparecerán aquí cuando se detecten anomalías',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[500],
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _visibleAnomalies.length +
                        (_visibleAnomalies.length < _allAnomalies.length
                            ? 1
                            : 0),
                    itemBuilder: (context, index) {
                      if (index == _visibleAnomalies.length) {
                        // Botón "Mostrar más"
                        return Padding(
                          padding: const EdgeInsets.all(16),
                          child: ElevatedButton(
                            onPressed: _show20More,
                            child: const Text('Mostrar más notificaciones'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: appBarColor,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        );
                      }
                      return _buildNotificationCard(_visibleAnomalies[index]);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _showClearDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Borrar notificaciones'),
        content: const Text(
            '¿Estás seguro de que quieres borrar todas las notificaciones? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child:
                const Text('Cancelar', style: TextStyle(color: Colors.white)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _clearData();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Borrar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Color _getAnomalyColor(String type) {
    switch (type) {
      case 'voltage':
        return Colors.red;
      case 'current':
        return Colors.orange;
      case 'frequency':
        return Colors.purple;
      case 'tank_level':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  void _showAnomalyDetails(Map anomaly) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Detalles de la notificación'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Descripción: ${anomaly['description']}'),
              const SizedBox(height: 8),
              if (anomaly['timestamp'] != null)
                Text(
                    'Fecha: ${DateFormat('dd/MM/yyyy HH:mm:ss').format(DateTime.fromMillisecondsSinceEpoch(anomaly['timestamp']))}'),
              const SizedBox(height: 8),
              if (anomaly['type'] != null)
                Text('Tipo: ${typeLabels[anomaly['type']] ?? anomaly['type']}'),
              const SizedBox(height: 8),
              if (anomaly['phase'] != null)
                Text('Fase: ${anomaly['phase'].toString().toUpperCase()}'),
              const SizedBox(height: 8),
              if (anomaly['value'] != null) Text('Valor: ${anomaly['value']}'),
              const SizedBox(height: 8),
              if (anomaly['limitMin'] != null && anomaly['limitMax'] != null)
                Text(
                    'Límites: ${anomaly['limitMin']} - ${anomaly['limitMax']}'),
              const SizedBox(height: 8),
              if (anomaly['limit'] != null) Text('Límite: ${anomaly['limit']}'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }
}

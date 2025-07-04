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
    "battery": Icons.battery_full, // Notificación de batería
    "tank_level": Icons.water_drop, // Notificación de nivel del tanque
  };

  ValueNotifier<Map<String, dynamic>> get globalNotifier =>
      SingletonMqttService().notifier;

  double? nominalVoltage;
  double? nominalCurrent;

  double? get batteryValue {
    final bat = globalNotifier.value['battery'];
    if (bat is double) return bat;
    if (bat is int) return bat.toDouble();
    if (bat is String) return double.tryParse(bat);
    return null;
  }

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

  Widget buildBatteryIconButton() {
    final battery = batteryValue;
    IconData icon = Icons.battery_full;
    Color color = Colors.grey;
    String message = "Estado de la batería: --";

    if (battery == null) {
      icon = Icons.battery_unknown;
      color = Colors.grey;
      message = "Estado de la batería: No disponible";
    } else if (battery >= 3.0) {
      icon = Icons.battery_full;
      color = Colors.green;
      message = "Estado de la batería: Cargada/Conectado";
    } else if (battery > 2.5) {
      icon = Icons.battery_5_bar;
      color = Colors.amber;
      message = "Estado de la batería: Buena";
    } else {
      icon = Icons.battery_alert;
      color = Colors.red;
      message =
          "Estado de la batería: Nivel bajo, se recomienda cambiar pronto";
    }

    return IconButton(
      tooltip: "Estado batería",
      icon: Icon(icon, color: color),
      onPressed: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message, style: TextStyle(color: Colors.white)),
            backgroundColor: color,
            duration: Duration(seconds: 2),
          ),
        );
      },
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
      if (type == "battery" && anomaly["value"] != null) {
        final b = double.tryParse(anomaly["value"].toString());
        if (b != null) {
          valueInfo = " | Voltaje: ${b.toStringAsFixed(2)} V";
        }
      }
      if (type == "tank_level" && anomaly["value"] != null) {
        final t = double.tryParse(anomaly["value"].toString());
        if (t != null) {
          valueInfo = " | Nivel: ${(t * 100).toStringAsFixed(1)}%";
        }
      }
    }

    // Título especial si es notificación de batería
    final isBattery = type == "battery";
    final title = isBattery
        ? (anomaly['description'] ?? "Notificación de batería")
        : (anomaly['description'] ?? 'Anomalía');

    return Card(
      margin: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(
        side:
            BorderSide(color: isBattery ? Colors.amber : phaseColor, width: 2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isBattery ? Colors.amber : phaseColor,
          child: Icon(
            typeIcons[type] ?? Icons.warning,
            color: Colors.white,
          ),
        ),
        title: Text(title),
        subtitle: Text(
          "$dateStr $timeStr"
          "${phase.isNotEmpty && phase != "TODAS" && !isBattery ? "  •  Fase $phase" : ""}"
          "$valueInfo",
        ),
        trailing: typeLabels[type] != null || isBattery
            ? Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: appBarColor.withOpacity(0.07),
                  border: Border.all(
                      color: isBattery ? Colors.amber : appBarColor, width: 1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      typeIcons[type] ?? Icons.warning,
                      color: isBattery ? Colors.amber : appBarColor,
                      size: 18,
                    ),
                    SizedBox(width: 4),
                    Text(
                      isBattery ? "Batería" : typeLabels[type]!,
                      style: TextStyle(
                        color: isBattery ? Colors.amber[800] : appBarColor,
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

  Widget _buildPhaseFilters() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: ["Todas", "A", "B", "C"].map((phase) {
            final color = phaseColors[phase]!;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ChoiceChip(
                label: Text(
                  phase == "Todas" ? "Todas las fases" : "Fase $phase",
                  style: TextStyle(
                    color: _selectedPhase == phase ? Colors.white : color,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                selected: _selectedPhase == phase,
                selectedColor: color,
                backgroundColor: Colors.grey[200],
                showCheckmark: false,
                onSelected: (_) {
                  setState(() {
                    _selectedPhase = phase;
                  });
                  _loadAndShowAnomalies();
                },
              ),
            );
          }).toList(),
        ),
      );

  Widget _buildTypeFilters() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ...typeLabels.entries.map((entry) {
              final type = entry.key;
              final label = entry.value;
              final icon = typeIcons[type] ?? Icons.notifications;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(
                  avatar: Icon(
                    icon,
                    color: _selectedType == type ? Colors.white : appBarColor,
                    size: 20,
                  ),
                  label: Text(
                    label,
                    style: TextStyle(
                      color: _selectedType == type ? Colors.white : appBarColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  selected: _selectedType == type,
                  selectedColor: appBarColor,
                  backgroundColor: Colors.grey[200],
                  showCheckmark: false,
                  onSelected: (_) {
                    setState(() {
                      _selectedType = type;
                    });
                    _loadAndShowAnomalies();
                  },
                ),
              );
            }),
            // Filtro especial para batería
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ChoiceChip(
                avatar: Icon(
                  Icons.battery_full,
                  color:
                      _selectedType == "battery" ? Colors.white : appBarColor,
                  size: 20,
                ),
                label: Text(
                  "Batería",
                  style: TextStyle(
                    color:
                        _selectedType == "battery" ? Colors.white : appBarColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                selected: _selectedType == "battery",
                selectedColor: Colors.amber,
                backgroundColor: Colors.grey[200],
                showCheckmark: false,
                onSelected: (_) {
                  setState(() {
                    _selectedType = "battery";
                  });
                  _loadAndShowAnomalies();
                },
              ),
            ),
            // Filtro especial para nivel del tanque
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ChoiceChip(
                avatar: Icon(
                  Icons.water_drop,
                  color:
                      _selectedType == "tank_level" ? Colors.white : appBarColor,
                  size: 20,
                ),
                label: Text(
                  "Nivel Tanque",
                  style: TextStyle(
                    color:
                        _selectedType == "tank_level" ? Colors.white : appBarColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                selected: _selectedType == "tank_level",
                selectedColor: Colors.blue,
                backgroundColor: Colors.grey[200],
                showCheckmark: false,
                onSelected: (_) {
                  setState(() {
                    _selectedType = "tank_level";
                  });
                  _loadAndShowAnomalies();
                },
              ),
            ),
          ],
        ),
      );

  Widget _buildDateRangeFilterBox() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 14),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton.icon(
                  icon: Icon(Icons.date_range, color: appBarColor),
                  label: Text(
                    _selectedRange != null
                        ? 'Modificar rango de fecha y hora'
                        : 'Filtrar por fecha y hora',
                    style: TextStyle(
                        color: appBarColor, fontWeight: FontWeight.bold),
                  ),
                  onPressed: () async {
                    final DateTimeRange? pickedDate = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2035),
                      initialEntryMode: DatePickerEntryMode.calendarOnly,
                      builder: (BuildContext context, Widget? child) {
                        return Theme(
                          data: ThemeData.dark(),
                          child: child!,
                        );
                      },
                    );

                    if (pickedDate != null) {
                      final TimeOfDay? startTime = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay(hour: 0, minute: 0),
                        builder: (context, child) => Theme(
                          data: ThemeData.dark(),
                          child: child!,
                        ),
                      );
                      if (startTime == null) return;

                      final TimeOfDay? endTime = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay(hour: 23, minute: 59),
                        builder: (context, child) => Theme(
                          data: ThemeData.dark(),
                          child: child!,
                        ),
                      );
                      if (endTime == null) return;

                      final startDateTime = DateTime(
                        pickedDate.start.year,
                        pickedDate.start.month,
                        pickedDate.start.day,
                        startTime.hour,
                        startTime.minute,
                      );
                      final endDateTime = DateTime(
                        pickedDate.end.year,
                        pickedDate.end.month,
                        pickedDate.end.day,
                        endTime.hour,
                        endTime.minute,
                      );

                      setState(() {
                        _selectedRange = DateTimeRange(
                            start: startDateTime, end: endDateTime);
                      });
                      _loadAndShowAnomalies();
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: appBarColor),
                    backgroundColor: Colors.white,
                  ),
                ),
                if (_selectedRange != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 10),
                    child: OutlinedButton.icon(
                      icon: Icon(Icons.clear, color: Colors.red),
                      label: Text(
                        "Quitar filtro",
                        style: TextStyle(
                            color: Colors.red, fontWeight: FontWeight.bold),
                      ),
                      onPressed: () {
                        setState(() {
                          _selectedRange = null;
                        });
                        _loadAndShowAnomalies();
                      },
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.red),
                        backgroundColor: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
            if (_selectedRange != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  "Desde: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(_selectedRange!.start)}\n"
                  "Hasta: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(_selectedRange!.end)}",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: appBarColor, fontWeight: FontWeight.w500),
                ),
              ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final colorPrimary = Theme.of(context).colorScheme.primary;
    final colorAccent = Theme.of(context).colorScheme.secondary;
    final colorText = Theme.of(context).colorScheme.onBackground;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notificaciones'),
        backgroundColor: colorPrimary,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Notificaciones recientes', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: colorText)),
            const SizedBox(height: 16),
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 4,
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: colorAccent,
                  child: Icon(Icons.warning, color: Colors.white),
                ),
                title: Text('Tanque lleno', style: TextStyle(fontWeight: FontWeight.bold, color: colorAccent)),
                subtitle: Text('29/06/2025 22:05:43  •  Nivel del tanque al 100%', style: TextStyle(color: colorText)),
                trailing: Icon(Icons.chevron_right, color: colorAccent),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 2,
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.redAccent,
                  child: Icon(Icons.thermostat, color: Colors.white),
                ),
                title: Text('Temperatura alta', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent)),
                subtitle: Text('29/06/2025 21:50:12  •  Temp. ambiente 36°C', style: TextStyle(color: colorText)),
                trailing: Icon(Icons.chevron_right, color: colorAccent),
              ),
            ),
            const SizedBox(height: 24),
            Text('Simulación de notificaciones recientes.', style: TextStyle(color: colorText.withOpacity(0.7))),
          ],
        ),
      ),
    );
  }

  String _getActiveFiltersText() {
    List<String> filters = [];
    if (_selectedPhase != "Todas") filters.add('Fase: $_selectedPhase');
    if (_selectedType != "Todos") filters.add('Tipo: ${typeLabels[_selectedType]}');
    if (_selectedRange != null) {
      final formatter = DateFormat('dd/MM/yyyy');
      filters.add('Rango: ${formatter.format(_selectedRange!.start)} - ${formatter.format(_selectedRange!.end)}');
    }
    return filters.join(', ');
  }

  void _clearFilters() {
    setState(() {
      _selectedPhase = "Todas";
      _selectedType = "Todos";
      _selectedRange = null;
    });
    _loadAndShowAnomalies();
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Filtrar notificaciones'),
        content: StatefulBuilder(
          builder: (context, setState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Filtro por fase
              DropdownButtonFormField<String>(
                value: _selectedPhase,
                decoration: const InputDecoration(labelText: 'Fase'),
                items: phaseColors.keys.map((phase) => 
                  DropdownMenuItem(value: phase, child: Text(phase))
                ).toList(),
                onChanged: (value) {
                  setState(() => _selectedPhase = value!);
                },
              ),
              const SizedBox(height: 16),
              // Filtro por tipo
              DropdownButtonFormField<String>(
                value: _selectedType,
                decoration: const InputDecoration(labelText: 'Tipo'),
                items: typeLabels.entries.map((entry) => 
                  DropdownMenuItem(value: entry.key, child: Text(entry.value))
                ).toList(),
                onChanged: (value) {
                  setState(() => _selectedType = value!);
                },
              ),
              const SizedBox(height: 16),
              // Filtro por rango de fechas
              ElevatedButton(
                onPressed: () async {
                  final range = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                    initialDateRange: _selectedRange,
                  );
                  if (range != null) {
                    setState(() => _selectedRange = range);
                  }
                },
                child: Text(_selectedRange == null 
                  ? 'Seleccionar rango de fechas' 
                  : 'Rango: ${DateFormat('dd/MM/yyyy').format(_selectedRange!.start)} - ${DateFormat('dd/MM/yyyy').format(_selectedRange!.end)}'
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _loadAndShowAnomalies();
            },
            child: const Text('Aplicar'),
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
        content: const Text('¿Estás seguro de que quieres borrar todas las notificaciones? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
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

  Widget _buildAnomalyCard(Map anomaly, Color colorPrimary, Color colorAccent, Color colorText) {
    final timestamp = anomaly['timestamp'];
    final type = anomaly['type'] ?? '';
    final phase = anomaly['phase'] ?? '';
    final description = anomaly['description'] ?? '';
    final value = anomaly['value'];
    
    DateTime? date;
    if (timestamp != null) {
      if (timestamp is int) {
        date = DateTime.fromMillisecondsSinceEpoch(timestamp);
      } else if (timestamp is String) {
        date = DateTime.tryParse(timestamp);
      }
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _getAnomalyColor(type),
          child: Icon(
            typeIcons[type] ?? Icons.warning,
            color: Colors.white,
          ),
        ),
        title: Text(
          description,
          style: TextStyle(fontWeight: FontWeight.bold, color: colorText),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (date != null)
              Text(
                DateFormat('dd/MM/yyyy HH:mm:ss').format(date),
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            if (value != null)
              Text(
                'Valor: $value',
                style: TextStyle(fontSize: 12, color: colorAccent),
              ),
            if (phase.isNotEmpty)
              Text(
                'Fase: ${phase.toUpperCase()}',
                style: TextStyle(fontSize: 12, color: phaseColors[phase.toUpperCase()] ?? Colors.grey),
              ),
          ],
        ),
        trailing: Icon(
          Icons.chevron_right,
          color: Colors.grey[400],
        ),
        onTap: () => _showAnomalyDetails(anomaly),
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
      case 'battery':
        return Colors.amber;
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
                Text('Fecha: ${DateFormat('dd/MM/yyyy HH:mm:ss').format(DateTime.fromMillisecondsSinceEpoch(anomaly['timestamp']))}'),
              const SizedBox(height: 8),
              if (anomaly['type'] != null)
                Text('Tipo: ${typeLabels[anomaly['type']] ?? anomaly['type']}'),
              const SizedBox(height: 8),
              if (anomaly['phase'] != null)
                Text('Fase: ${anomaly['phase'].toString().toUpperCase()}'),
              const SizedBox(height: 8),
              if (anomaly['value'] != null)
                Text('Valor: ${anomaly['value']}'),
              const SizedBox(height: 8),
              if (anomaly['limitMin'] != null && anomaly['limitMax'] != null)
                Text('Límites: ${anomaly['limitMin']} - ${anomaly['limitMax']}'),
              const SizedBox(height: 8),
              if (anomaly['limit'] != null)
                Text('Límite: ${anomaly['limit']}'),
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

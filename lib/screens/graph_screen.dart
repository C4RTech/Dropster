import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:hive/hive.dart';
import 'dart:async';
import 'dart:math' as math;
import '../services/singleton_mqtt_service.dart';
import 'dart:collection';
import 'package:intl/intl.dart';

class GraphScreen extends StatefulWidget {
  @override
  _GraphScreenState createState() => _GraphScreenState();
}

class _GraphScreenState extends State<GraphScreen> {
  List<Map<String, dynamic>> _allData = [];
  bool isRealTime = true;
  bool isLoading = false;
  DateTimeRange? selectedRange;
  String _message = "";
  String _timePeriod = "tiempo_real"; // tiempo_real, dia, semana, mes

  final String dataBoxName = 'energyData';
  int realTimeSampleCount = 20;
  final String settingsBoxName = 'settings';
  final String sampleCountKey = 'graphSampleCount';

  late final ValueNotifier<Map<String, dynamic>> _globalNotifier;

  final List<_MultiGraphGroup> _multiGraphGroups = [
    // === ENERGÍA Y AGUA (PRIORIDAD ALTA) ===
    _MultiGraphGroup(
      title: "Energía Consumida",
      keys: ["energia"],
      seriesTitles: ["Energía Total"],
      colors: [Colors.amber],
      unit: "Wh",
      icon: Icons.bolt,
    ),
    _MultiGraphGroup(
      title: "Agua Generada",
      keys: ["aguaAlmacenada"],
      seriesTitles: ["Volumen de Agua"],
      colors: [Colors.blue],
      unit: "L",
      icon: Icons.water_drop,
    ),

    // === PARÁMETROS AMBIENTALES ===
    _MultiGraphGroup(
      title: "Temperaturas",
      keys: [
        "temperaturaAmbiente",
        "temperaturaEvaporador",
        "temperaturaCondensador"
      ],
      seriesTitles: ["Ambiente", "Evaporador", "Condensador"],
      colors: [
        Colors.orange.shade600,
        Colors.red.shade600,
        Colors.purple.shade600
      ],
      unit: "°C",
      icon: Icons.thermostat,
    ),
    _MultiGraphGroup(
      title: "Humedad",
      keys: ["humedadRelativa", "humedadEvaporador", "humedadCondensador"],
      seriesTitles: ["Ambiente", "Evaporador", "Condensador"],
      colors: [
        Colors.cyan.shade600,
        Colors.teal.shade600,
        Colors.indigo.shade600
      ],
      unit: "%",
      icon: Icons.water,
    ),
  ];

  late List<bool> _showTableForGroup;

  // Zoom vertical (1.0 = normal, >1 = más "plano", <1 = más "amplificado")
  double verticalZoomFactor = 1.0;

  @override
  void initState() {
    super.initState();
    _globalNotifier = SingletonMqttService().notifier;
    _initGroupSelection();
    _loadSampleCount();
    _loadInitialData();
    _initRealTimeListener();
    _initSettingsListener();
    _showTableForGroup = List.generate(_multiGraphGroups.length, (_) => false);
  }

  void _initGroupSelection() {
    for (final group in _multiGraphGroups) {
      group.selected ??= List.filled(group.keys.length, true);
    }
  }

  DateTimeRange? _calculateTimeRange() {
    final now = DateTime.now();

    switch (_timePeriod) {
      case "tiempo_real":
        // Últimas 2 horas para tiempo real
        return DateTimeRange(
          start: now.subtract(Duration(hours: 2)),
          end: now,
        );
      case "dia":
        // Día completo actual
        final startOfDay = DateTime(now.year, now.month, now.day);
        return DateTimeRange(
          start: startOfDay,
          end: startOfDay.add(Duration(days: 1)),
        );
      case "semana":
        // Semana completa (desde lunes hasta domingo)
        final monday = now.subtract(Duration(days: now.weekday - 1));
        final startOfWeek = DateTime(monday.year, monday.month, monday.day);
        return DateTimeRange(
          start: startOfWeek,
          end: startOfWeek.add(Duration(days: 7)),
        );
      case "mes":
        // Mes completo actual
        final startOfMonth = DateTime(now.year, now.month, 1);
        final nextMonth = now.month == 12
            ? DateTime(now.year + 1, 1, 1)
            : DateTime(now.year, now.month + 1, 1);
        return DateTimeRange(
          start: startOfMonth,
          end: nextMonth,
        );
      default:
        return null;
    }
  }

  Future<void> _loadSampleCount() async {
    if (!Hive.isBoxOpen(settingsBoxName)) {
      await Hive.openBox(settingsBoxName);
    }
    final settingsBox = Hive.box(settingsBoxName);
    setState(() {
      realTimeSampleCount = settingsBox.get(sampleCountKey, defaultValue: 20);
    });
    print('[GRAPH] Muestras cargadas: $realTimeSampleCount');
  }

  Future<void> _saveSampleCount(int value) async {
    if (!Hive.isBoxOpen(settingsBoxName)) {
      await Hive.openBox(settingsBoxName);
    }
    final settingsBox = Hive.box(settingsBoxName);
    await settingsBox.put(sampleCountKey, value);
  }

  Future<void> _loadInitialData() async {
    print('[GRAPH DEBUG] 🔄 Iniciando carga inicial de datos...');
    setState(() {
      isLoading = true;
    });

    try {
      // Calcular rango basado en el período seleccionado
      DateTimeRange? range = _calculateTimeRange();
      _allData = await _getDataFromHive(range: range);
      print('[GRAPH DEBUG] ✅ Datos cargados: ${_allData.length} registros');

      // Si no hay datos, crear datos de ejemplo para testing
      if (_allData.isEmpty && _timePeriod == "tiempo_real") {
        print(
            '[GRAPH DEBUG] ⚠️ No hay datos reales, creando datos de ejemplo...');
        _allData = _createSampleData();
        print(
            '[GRAPH DEBUG] ✅ Datos de ejemplo creados: ${_allData.length} registros');
      }

      // Log detallado de los primeros registros
      if (_allData.isNotEmpty) {
        print('[GRAPH DEBUG] 📊 Primer registro: ${_allData.first}');
        print('[GRAPH DEBUG] 📊 Último registro: ${_allData.last}');
      }

      setState(() {
        isLoading = false;
      });

      print('[GRAPH DEBUG] ✅ Carga inicial completada');
    } catch (e) {
      print('[GRAPH DEBUG] ❌ Error en carga inicial: $e');
      setState(() {
        isLoading = false;
        _message = 'Error cargando datos: $e';
      });
    }
  }

  Future<List<Map<String, dynamic>>> _getDataFromHive(
      {DateTimeRange? range}) async {
    print('[GRAPH DEBUG] 🔍 Obteniendo datos de Hive...');

    try {
      Box<Map> box;
      if (Hive.isBoxOpen(dataBoxName)) {
        box = Hive.box<Map>(dataBoxName);
        print('[GRAPH DEBUG] 📦 Usando caja abierta: $dataBoxName');
      } else {
        box = await Hive.openBox<Map>(dataBoxName);
        print('[GRAPH DEBUG] 📦 Abriendo caja: $dataBoxName');
      }

      final rawData = box.values.toList();
      print('[GRAPH DEBUG] 📊 Datos crudos en Hive: ${rawData.length}');

      final all = rawData
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();

      print(
          '[GRAPH DEBUG] 📊 Datos válidos después de filtrado: ${all.length}');

      if (all.isEmpty) {
        print('[GRAPH DEBUG] ⚠️ No hay datos en Hive');
        return [];
      }

      // Ordenar por timestamp
      all.sort((a, b) => _getTimestamp(a).compareTo(_getTimestamp(b)));
      print('[GRAPH DEBUG] 📊 Datos ordenados por timestamp');

      if (range == null) {
        if (isRealTime && all.length > realTimeSampleCount) {
          final result = all.sublist(all.length - realTimeSampleCount);
          print(
              '[GRAPH DEBUG] 📊 Modo tiempo real: ${result.length} muestras de ${all.length}');
          return result;
        }
        print(
            '[GRAPH DEBUG] 📊 Modo tiempo real completo: ${all.length} muestras');
        return all;
      }

      // Filtrar por rango de fechas
      final filtered = all.where((item) {
        final t = _parseTimestamp(item);
        if (t == null) {
          print('[GRAPH DEBUG] ⚠️ Timestamp inválido en item: $item');
          return false;
        }
        final inRange = !t.isBefore(range.start) && !t.isAfter(range.end);
        if (inRange) {
          print('[GRAPH DEBUG] ✅ Item en rango: ${t.toString()}');
        }
        return inRange;
      }).toList();

      print(
          '[GRAPH DEBUG] 📊 Datos filtrados por rango: ${filtered.length} de ${all.length}');
      return filtered;
    } catch (e) {
      print('[GRAPH DEBUG] ❌ Error obteniendo datos de Hive: $e');
      return [];
    }
  }

  int _getTimestamp(Map<String, dynamic> item) {
    if (item.containsKey('timestamp')) {
      final ts = item['timestamp'];
      if (ts is int) return ts;
      if (ts is String) return int.tryParse(ts) ?? 0;
      if (ts is DateTime) return ts.millisecondsSinceEpoch;
    }
    try {
      final year = int.tryParse(item['date_year']?.toString() ?? '') ?? 0;
      final month = int.tryParse(item['date_month']?.toString() ?? '') ?? 1;
      final day = int.tryParse(item['date_day']?.toString() ?? '') ?? 1;
      final hour = int.tryParse(item['time_hour']?.toString() ?? '') ?? 0;
      final min = int.tryParse(item['time_minute']?.toString() ?? '') ?? 0;
      final sec = int.tryParse(item['time_second']?.toString() ?? '') ?? 0;
      return DateTime(year, month, day, hour, min, sec).millisecondsSinceEpoch;
    } catch (_) {
      return 0;
    }
  }

  DateTime? _parseTimestamp(Map<String, dynamic> item) {
    try {
      final ms = _getTimestamp(item);
      if (ms > 0) return DateTime.fromMillisecondsSinceEpoch(ms);
      return null;
    } catch (_) {
      return null;
    }
  }

  bool _isValidDateRange(DateTime start, DateTime end) {
    return !start.isAfter(end);
  }

  Future<void> _pickDateTimeRange() async {
    final DateTimeRange? pickedDate = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
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

      if (!_isValidDateRange(startDateTime, endDateTime)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'La fecha/hora de inicio debe ser anterior o igual a la de fin.',
              style: TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      setState(() {
        selectedRange = DateTimeRange(start: startDateTime, end: endDateTime);
        isRealTime = false;
        isLoading = true;
        _message = "";
      });

      _allData = await _getDataFromHive(range: selectedRange);

      if (_allData.isEmpty) {
        setState(() {
          _message = "No hay datos en el rango de tiempo seleccionado.";
          isLoading = false;
        });
      } else {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Future<void> _confirmAndClearData() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('¿Borrar datos?'),
        content: Text(
            '¿Estás seguro de que deseas eliminar todos los datos almacenados?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child:
                const Text('Cancelar', style: TextStyle(color: Colors.white)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context, true);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Borrar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _clearData();
    }
  }

  Future<void> _clearData() async {
    Box<Map> box;
    if (Hive.isBoxOpen(dataBoxName)) {
      box = Hive.box<Map>(dataBoxName);
    } else {
      box = await Hive.openBox<Map>(dataBoxName);
    }
    await box.clear();
    setState(() {
      _allData.clear();
      _message = "Datos borrados";
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Datos borrados'),
        backgroundColor: Color(0xFF1D347A),
      ),
    );
  }

  /// Función para forzar recarga de datos
  Future<void> _forceRefreshData() async {
    print('[GRAPH DEBUG] 🔄 Forzando recarga de datos...');

    setState(() {
      isLoading = true;
      _message = "";
    });

    try {
      // Recargar datos de Hive
      _allData = await _getDataFromHive(range: selectedRange);

      // Si estamos en tiempo real, intentar obtener datos del notifier actual
      if (isRealTime && _globalNotifier.value.isNotEmpty) {
        print('[GRAPH DEBUG] 🔄 Actualizando con datos del notifier...');
        final currentData = _globalNotifier.value;
        if (currentData['timestamp'] != null) {
          _onNewRealTimeData(currentData);
        }
      }

      setState(() {
        isLoading = false;
      });

      print('[GRAPH DEBUG] ✅ Recarga forzada completada');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Datos recargados: ${_allData.length} registros'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      print('[GRAPH DEBUG] ❌ Error en recarga forzada: $e');
      setState(() {
        isLoading = false;
        _message = 'Error recargando datos: $e';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error recargando datos'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _onNewRealTimeData(Map<String, dynamic> newData) {
    if (!isRealTime || !mounted) return;

    // Validar que el nuevo dato tenga timestamp válido
    final newTimestamp = _getTimestamp(newData);
    if (newTimestamp <= 0) {
      print(
          '[GRAPH DEBUG] ⚠️ Nuevo dato rechazado: timestamp inválido ($newTimestamp)');
      return;
    }

    // Validar que tenga al menos un campo de datos válido
    final hasValidData = [
      'energia',
      'aguaAlmacenada',
      'temperaturaAmbiente',
      'humedadRelativa'
    ].any((key) => newData.containsKey(key) && newData[key] != null);
    if (!hasValidData) {
      print(
          '[GRAPH DEBUG] ⚠️ Nuevo dato rechazado: no tiene campos de datos válidos');
      return;
    }

    setState(() {
      final current = List<Map<String, dynamic>>.from(_allData);
      current.add(Map<String, dynamic>.from(newData));

      // Ordenar por timestamp para asegurar consistencia
      current.sort((a, b) => _getTimestamp(a).compareTo(_getTimestamp(b)));

      // Eliminar duplicados de timestamp, conservando el último valor
      final map = LinkedHashMap<int, Map<String, dynamic>>();
      for (final item in current) {
        final ts = _getTimestamp(item);
        if (ts > 0) {
          // Solo incluir timestamps válidos
          map[ts] = item;
        }
      }
      final deduped = map.values.toList();

      // Limitar a la cantidad máxima de muestras
      if (deduped.length > realTimeSampleCount) {
        _allData = deduped.sublist(deduped.length - realTimeSampleCount);
        print(
            '[GRAPH DEBUG] 📊 Datos limitados a $realTimeSampleCount muestras más recientes');
      } else {
        _allData = deduped;
      }

      print(
          '[GRAPH DEBUG] ✅ Nuevo dato agregado. Total datos: ${_allData.length}');
    });
  }

  /// Función para detectar anomalías en los datos que podrían causar comportamientos extraños
  void _detectDataAnomalies(List<FlSpot> spots, String seriesName) {
    if (spots.length < 2) return;

    print(
        '[GRAPH DEBUG] 🔍 Analizando anomalías en serie: $seriesName (${spots.length} puntos)');

    // 1. Detectar timestamps duplicados
    final timestampCounts = <double, int>{};
    for (final spot in spots) {
      timestampCounts[spot.x] = (timestampCounts[spot.x] ?? 0) + 1;
    }
    final duplicates =
        timestampCounts.entries.where((e) => e.value > 1).toList();
    if (duplicates.isNotEmpty) {
      print('[GRAPH DEBUG] ⚠️ Timestamps duplicados encontrados:');
      for (final dup in duplicates) {
        print('[GRAPH DEBUG]   - Timestamp ${dup.key}: ${dup.value} veces');
      }
    }

    // 2. Detectar valores extremos
    final values = spots.map((s) => s.y).toList();
    final min = values.reduce((a, b) => a < b ? a : b);
    final max = values.reduce((a, b) => a > b ? a : b);
    final avg = values.reduce((a, b) => a + b) / values.length;

    // Calcular desviación estándar
    final variance =
        values.map((v) => (v - avg) * (v - avg)).reduce((a, b) => a + b) /
            values.length;
    final stdDev = variance > 0 ? math.sqrt(variance) : 0.0;

    // Detectar outliers (valores fuera de 3 desviaciones estándar)
    final outliers = spots.where((spot) {
      final deviation = (spot.y - avg).abs();
      return deviation > (3 * stdDev);
    }).toList();

    if (outliers.isNotEmpty) {
      print('[GRAPH DEBUG] ⚠️ Valores atípicos detectados en $seriesName:');
      for (final outlier in outliers) {
        final dt = DateTime.fromMillisecondsSinceEpoch(outlier.x.toInt());
        print(
            '[GRAPH DEBUG]   - ${dt.toString()}: ${outlier.y} (desviación: ${(outlier.y - avg).abs() / stdDev}σ)');
      }
    }

    // 3. Detectar saltos temporales irregulares
    final timeGaps = <double>[];
    for (int i = 1; i < spots.length; i++) {
      final gap = spots[i].x - spots[i - 1].x;
      timeGaps.add(gap);
    }

    if (timeGaps.isNotEmpty) {
      final avgGap = timeGaps.reduce((a, b) => a + b) / timeGaps.length;
      final gapStdDev = timeGaps
              .map((g) => (g - avgGap) * (g - avgGap))
              .reduce((a, b) => a + b) /
          timeGaps.length;
      final gapStdDevSqrt = gapStdDev > 0 ? math.sqrt(gapStdDev) : 0.0;

      final irregularGaps = <int>[];
      for (int i = 0; i < timeGaps.length; i++) {
        if ((timeGaps[i] - avgGap).abs() > (3 * gapStdDevSqrt)) {
          irregularGaps.add(i);
        }
      }

      if (irregularGaps.isNotEmpty) {
        print('[GRAPH DEBUG] ⚠️ Saltos temporales irregulares en $seriesName:');
        for (final idx in irregularGaps) {
          final dt1 = DateTime.fromMillisecondsSinceEpoch(spots[idx].x.toInt());
          final dt2 =
              DateTime.fromMillisecondsSinceEpoch(spots[idx + 1].x.toInt());
          final gapMinutes = timeGaps[idx] / (1000 * 60);
          print(
              '[GRAPH DEBUG]   - Entre ${dt1.toString()} y ${dt2.toString()}: ${gapMinutes.toStringAsFixed(1)} min');
        }
      }
    }

    // 4. Resumen de análisis
    print('[GRAPH DEBUG] 📊 Resumen análisis $seriesName:');
    print('[GRAPH DEBUG]   - Rango de valores: $min - $max');
    print('[GRAPH DEBUG]   - Promedio: ${avg.toStringAsFixed(2)}');
    print(
        '[GRAPH DEBUG]   - Desviación estándar: ${stdDev.toStringAsFixed(2)}');
    print('[GRAPH DEBUG]   - Duplicados: ${duplicates.length}');
    print('[GRAPH DEBUG]   - Valores atípicos: ${outliers.length}');
  }

  void _initRealTimeListener() {
    _globalNotifier.addListener(_handleGlobalNotifierChange);
  }

  void _initSettingsListener() {
    if (!Hive.isBoxOpen(settingsBoxName)) {
      Hive.openBox(settingsBoxName).then((_) {
        final settingsBox = Hive.box(settingsBoxName);
        settingsBox.watch(key: sampleCountKey).listen((event) {
          if (mounted) {
            setState(() {
              realTimeSampleCount = event.value ?? 20;
            });
            print(
                '[GRAPH] Muestras actualizadas desde configuración: $realTimeSampleCount');
          }
        });
      });
    } else {
      final settingsBox = Hive.box(settingsBoxName);
      settingsBox.watch(key: sampleCountKey).listen((event) {
        if (mounted) {
          setState(() {
            realTimeSampleCount = event.value ?? 20;
          });
          print(
              '[GRAPH] Muestras actualizadas desde configuración: $realTimeSampleCount');
        }
      });
    }
  }

  void _handleGlobalNotifierChange() {
    if (!isRealTime || !mounted) return;

    final data = _globalNotifier.value;
    print('[GRAPH DEBUG] 📡 Notifier cambió: ${data.keys.length} keys');

    if (data.isNotEmpty && data['timestamp'] != null) {
      print(
          '[GRAPH DEBUG] 📡 Datos válidos recibidos, actualizando gráfica...');
      _onNewRealTimeData(data);
    } else {
      print('[GRAPH DEBUG] ⚠️ Datos inválidos o sin timestamp');
    }
  }

  void _removeRealTimeListener() {
    _globalNotifier.removeListener(_handleGlobalNotifierChange);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _removeRealTimeListener();
    _initRealTimeListener();
  }

  @override
  void dispose() {
    _removeRealTimeListener();
    super.dispose();
  }

  Widget _buildTabulatedTable(_MultiGraphGroup group) {
    if (_allData.isEmpty) {
      return Center(
          child: Text("Sin datos", style: TextStyle(color: Colors.white)));
    }

    final selectedIdxs = <int>[];
    for (int i = 0; i < group.selected!.length; i++) {
      if (group.selected![i]) selectedIdxs.add(i);
    }
    if (selectedIdxs.isEmpty) {
      return Center(
          child: Text("Selecciona al menos una serie",
              style: TextStyle(color: Colors.white)));
    }

    final List<DataRow> rows = [];
    for (var entry in _allData) {
      final time = _parseTimestamp(entry);
      if (time == null) continue;
      rows.add(
        DataRow(
          cells: [
            DataCell(Text(
              "${time.year.toString().padLeft(4, '0')}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')} "
              "${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}",
              style: TextStyle(color: Colors.black87, fontSize: 12),
            )),
            ...selectedIdxs.map((idx) {
              final key = group.keys[idx];
              final value = entry[key];
              return DataCell(Text(
                value != null
                    ? _formatValueWithUnit(
                        (value as num).toDouble(), group.unit)
                    : "-",
                style: TextStyle(color: Colors.black87, fontSize: 12),
              ));
            }).toList(),
          ],
        ),
      );
    }

    return Container(
      color: Colors.white,
      margin: EdgeInsets.only(top: 10, bottom: 15),
      padding: EdgeInsets.symmetric(vertical: 10, horizontal: 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor:
              MaterialStateProperty.resolveWith((_) => Colors.blue.shade50),
          columns: [
            DataColumn(
                label: Text("Timestamp",
                    style: TextStyle(fontWeight: FontWeight.bold))),
            ...selectedIdxs.map((idx) => DataColumn(
                  label: Text(
                    group.unit.isNotEmpty
                        ? "${group.seriesTitles[idx]} (${group.unit})"
                        : group.seriesTitles[idx],
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                )),
          ],
          rows: rows,
        ),
      ),
    );
  }

  Widget _buildEnhancedGraph(_MultiGraphGroup group) {
    print('[GRAPH DEBUG] 📈 Construyendo gráfica para: ${group.title}');

    final groupIndex = _multiGraphGroups.indexOf(group);
    group.selected ??= List.filled(group.keys.length, true);

    List<List<FlSpot>> seriesSpots = [];
    List<String> enabledTitles = [];
    List<Color> enabledColors = [];
    int minSpots = 0;

    print(
        '[GRAPH DEBUG] 📊 Procesando ${group.keys.length} series para ${group.title}');

    for (int i = 0; i < group.keys.length; i++) {
      if (!(group.selected![i])) {
        print('[GRAPH DEBUG] ⚠️ Serie ${group.seriesTitles[i]} deshabilitada');
        continue;
      }

      final key = group.keys[i];
      final color = group.colors[i];
      final title = group.seriesTitles[i];

      print('[GRAPH DEBUG] 🔍 Procesando serie: $title (key: $key)');

      final source = _allData.where((e) => e[key] != null).toList();
      print(
          '[GRAPH DEBUG] 📊 Datos con key "$key": ${source.length} de ${_allData.length}');

      List<FlSpot> spots = source
          .map((entry) {
            final time = _parseTimestamp(entry);
            final y = (entry[key] as num?)?.toDouble();

            // Validaciones exhaustivas
            if (time == null) {
              print(
                  '[GRAPH DEBUG] ⚠️ Timestamp null para $key en entry: $entry');
              return null;
            }
            if (y == null) {
              print('[GRAPH DEBUG] ⚠️ Valor null para $key en entry: $entry');
              return null;
            }
            if (y.isNaN || y.isInfinite) {
              print(
                  '[GRAPH DEBUG] ⚠️ Valor inválido (NaN/Infinite) para $key: $y');
              return null;
            }
            if (y < -1000000 || y > 1000000) {
              // Rango razonable
              print('[GRAPH DEBUG] ⚠️ Valor fuera de rango para $key: $y');
              return null;
            }

            final timestamp = time.millisecondsSinceEpoch.toDouble();
            if (timestamp <= 0) {
              print(
                  '[GRAPH DEBUG] ⚠️ Timestamp inválido (<=0) para $key: $timestamp');
              return null;
            }

            return FlSpot(timestamp, y);
          })
          .where((e) => e != null)
          .cast<FlSpot>()
          .toList();

      print('[GRAPH DEBUG] ✅ Spots generados para $title: ${spots.length}');

      // === DEDUPLICACIÓN MEJORADA ===
      // Eliminar duplicados de timestamp, conservando el último valor
      final originalCount = spots.length;
      final map = LinkedHashMap<double, FlSpot>();
      for (final spot in spots) {
        map[spot.x] =
            spot; // Sobrescribe con el último valor para timestamp duplicado
      }
      spots = map.values.toList();

      // Verificar si había duplicados
      if (spots.length != originalCount) {
        print(
            '[GRAPH DEBUG] ⚠️ Eliminados ${originalCount - spots.length} spots duplicados para $title');
      }

      // Limitar cantidad de spots en tiempo real
      if (isRealTime && spots.length > realTimeSampleCount) {
        spots = spots.sublist(spots.length - realTimeSampleCount);
        print(
            '[GRAPH DEBUG] 🔄 Tiempo real: ${spots.length} spots después de limitar muestras');
      }

      print('[GRAPH DEBUG] ✅ Spots finales para $title: ${spots.length}');

      if (minSpots == 0 || spots.length < minSpots) minSpots = spots.length;

      seriesSpots.add(spots);
      enabledTitles.add(title);
      enabledColors.add(color);

      print('[GRAPH DEBUG] 📈 Serie $title agregada: ${spots.length} puntos');

      // === DETECCIÓN DE ANOMALÍAS ===
      if (spots.isNotEmpty) {
        _detectDataAnomalies(spots, title);
      }
    }

    List<double> xTicks = [];
    if (seriesSpots.isNotEmpty && seriesSpots[0].isNotEmpty) {
      xTicks = seriesSpots[0].map((e) => e.x).toList();
      print('[GRAPH DEBUG] 📊 X ticks generados: ${xTicks.length}');
    }

    // Permitir mostrar gráfica con al menos 1 punto si hay datos, pero preferir 2+ para mejor visualización
    final hasAnyData = seriesSpots.any((lst) => lst.isNotEmpty);
    final hasEnoughData = seriesSpots.any((lst) => lst.length >= 2);
    final bool showChart = hasAnyData; // Cambiado para ser más flexible

    print('[GRAPH DEBUG] 📊 ¿Mostrar gráfica? $showChart');
    print('[GRAPH DEBUG] 📊   - Tiene datos: $hasAnyData');
    print('[GRAPH DEBUG] 📊   - Datos suficientes (>=2): $hasEnoughData');
    print(
        '[GRAPH DEBUG] 📊   - Series con datos: ${seriesSpots.where((lst) => lst.isNotEmpty).length}');
    print(
        '[GRAPH DEBUG] 📊   - Puntos por serie: ${seriesSpots.map((lst) => lst.length).toList()}');

    // === NUEVO: calcular minY/maxY expandido con zoom ===
    double? minY, maxY;
    final allYValues =
        seriesSpots.expand((lst) => lst.map((s) => s.y)).toList();
    if (allYValues.isNotEmpty) {
      final minVal = allYValues.reduce((a, b) => a < b ? a : b);
      final maxVal = allYValues.reduce((a, b) => a > b ? a : b);
      final range = (maxVal - minVal).abs();
      // Aplica el zoom vertical
      final expand = range == 0
          ? (minVal.abs() * 0.25 * verticalZoomFactor)
          : (range * 0.25 * verticalZoomFactor);
      minY = minVal - expand;
      maxY = maxVal + expand;
      // Si todos los valores son iguales, fuerza un rango mínimo visible
      if (range == 0) {
        minY = minVal - (minVal.abs() * 0.25 * verticalZoomFactor + 1);
        maxY = maxVal + (maxVal.abs() * 0.25 * verticalZoomFactor + 1);
      }
      print('[GRAPH DEBUG] 📊 Rango Y calculado: $minY - $maxY');
    } else {
      print('[GRAPH DEBUG] ⚠️ No hay valores Y para calcular rango');
    }

    return Card(
      color: Color(0xFF2C3E50),
      elevation: 4,
      margin: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 2, left: 6, right: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Título con icono mejorado
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      group.icon,
                      color:
                          Color(0xFF64B5F6), // Azul de la pantalla de monitoreo
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          group.title,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Color(
                                0xFF64B5F6), // Azul de la pantalla de monitoreo
                          ),
                        ),
                        if (group.unit.isNotEmpty)
                          Text(
                            'Unidad: ${group.unit}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 210,
              child: !showChart
                  ? Center(
                      child: Text(
                          "No hay suficientes datos para mostrar la gráfica",
                          style: TextStyle(color: Colors.white)))
                  : LineChart(
                      LineChartData(
                        gridData:
                            FlGridData(show: true, drawVerticalLine: true),
                        titlesData: FlTitlesData(
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize:
                                  45, // Más espacio para mejor legibilidad
                              getTitlesWidget: (value, meta) {
                                return Text(
                                  group.unit.isNotEmpty
                                      ? _formatValueWithUnit(value, group.unit)
                                      : value.toStringAsFixed(0),
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500),
                                );
                              },
                            ),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize:
                                  50, // Más espacio para mejor legibilidad
                              interval: _calculateTimeInterval(xTicks),
                              getTitlesWidget: (value, meta) {
                                final dt = DateTime.fromMillisecondsSinceEpoch(
                                    value.toInt());

                                // Para datos históricos, mostrar fecha y hora
                                if (!isRealTime && selectedRange != null) {
                                  return Text(
                                    "${dt.day}/${dt.month} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}",
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500),
                                  );
                                }

                                // Para tiempo real, mostrar solo hora y minutos
                                return Text(
                                  "${dt.hour}:${dt.minute.toString().padLeft(2, '0')}",
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500),
                                );
                              },
                            ),
                          ),
                          rightTitles: AxisTitles(
                              sideTitles: SideTitles(showTitles: false)),
                          topTitles: AxisTitles(
                              sideTitles: SideTitles(showTitles: false)),
                        ),
                        borderData: FlBorderData(
                            show: true,
                            border:
                                Border.all(color: Colors.black26, width: 0.5)),
                        lineBarsData: [
                          for (int i = 0; i < seriesSpots.length; i++)
                            if (seriesSpots[i]
                                .isNotEmpty) // Cambiado para permitir series con al menos 1 punto
                              LineChartBarData(
                                spots: seriesSpots[i],
                                isCurved: seriesSpots[i].length >=
                                    2, // Solo curvar si hay suficientes puntos
                                curveSmoothness: 0.4, // Más suavizado
                                color: enabledColors[i],
                                dotData: FlDotData(
                                    show: seriesSpots[i].length ==
                                        1), // Mostrar puntos si solo hay 1
                                belowBarData: BarAreaData(show: false),
                                barWidth: 2.5,
                              ),
                        ],
                        lineTouchData: LineTouchData(
                          touchTooltipData: LineTouchTooltipData(
                            tooltipBgColor: Colors.blueGrey.withOpacity(0.8),
                            getTooltipItems: (List<LineBarSpot> touchedSpots) {
                              return touchedSpots
                                  .map((LineBarSpot touchedSpot) {
                                final value = touchedSpot.y;
                                // Mostrar valor con 2 decimales y unidad
                                final displayValue = group.unit.isNotEmpty
                                    ? "${value.toStringAsFixed(2)} ${group.unit}"
                                    : value.toStringAsFixed(2);

                                return LineTooltipItem(
                                  displayValue,
                                  TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                );
                              }).toList();
                            },
                          ),
                          handleBuiltInTouches: true,
                          touchCallback: (FlTouchEvent event,
                              LineTouchResponse? touchResponse) {
                            if (event is FlTapUpEvent &&
                                touchResponse != null &&
                                touchResponse.lineBarSpots != null) {
                              // Mostrar información adicional si es necesario
                              for (final spot in touchResponse.lineBarSpots!) {
                                final dt = DateTime.fromMillisecondsSinceEpoch(
                                    spot.x.toInt());
                                final timeStr = isRealTime
                                    ? "${dt.hour}:${dt.minute.toString().padLeft(2, '0')}"
                                    : "${dt.day}/${dt.month} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}";

                                print(
                                    '[GRAPH] 📊 Tocado punto: $timeStr, Valor: ${spot.y.toStringAsFixed(2)}');
                              }
                            }
                          },
                        ),
                        minX: xTicks.isNotEmpty ? xTicks.first : 0,
                        maxX: xTicks.isNotEmpty ? xTicks.last : 0,
                        minY: minY,
                        maxY: maxY,
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                children: [
                  for (int i = 0; i < group.keys.length; i++)
                    FilterChip(
                      label: Row(
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            margin: EdgeInsets.only(right: 4),
                            decoration: BoxDecoration(
                              color: group.colors[i],
                              shape: BoxShape.circle,
                            ),
                          ),
                          Text(group.seriesTitles[i],
                              style: TextStyle(color: Colors.white)),
                        ],
                      ),
                      selected: group.selected![i],
                      selectedColor: group.colors[i].withOpacity(0.7),
                      backgroundColor: Colors.grey[700],
                      onSelected: (val) {
                        setState(() {
                          group.selected![i] = val;
                        });
                      },
                    ),
                ],
              ),
            ),
            if (!isRealTime && selectedRange != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(top: 2, bottom: 2),
                  child: OutlinedButton.icon(
                    icon: Icon(
                      _showTableForGroup[groupIndex]
                          ? Icons.table_chart
                          : Icons.list_alt,
                      color: Color(0xFF1D347A),
                    ),
                    label: Text(
                      _showTableForGroup[groupIndex]
                          ? "Ocultar valores tabulados"
                          : "Ver valores tabulados",
                      style: TextStyle(color: Color(0xFF1D347A)),
                    ),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Color(0xFF1D347A),
                      side: BorderSide(color: Color(0xFF1D347A)),
                    ),
                    onPressed: () {
                      setState(() {
                        _showTableForGroup[groupIndex] =
                            !_showTableForGroup[groupIndex];
                      });
                    },
                  ),
                ),
              ),
            if (!isRealTime &&
                selectedRange != null &&
                _showTableForGroup[groupIndex])
              Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: 640),
                  child: _buildTabulatedTable(group),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSliderSamples() {
    return isRealTime
        ? Column(
            children: [
              Text(
                "Cantidad de muestras a mostrar: $realTimeSampleCount",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              Slider(
                value: realTimeSampleCount.toDouble(),
                min: 5,
                max: 100,
                divisions: 19,
                label: realTimeSampleCount.toString(),
                activeColor: Color(0xFF1D347A),
                onChanged: (value) {
                  final newValue = value.round();
                  setState(() {
                    realTimeSampleCount = newValue;
                  });
                  _saveSampleCount(newValue);
                  print('[GRAPH] Muestras cambiadas a: $newValue');
                },
              ),
            ],
          )
        : SizedBox.shrink();
  }

  Widget _buildSliderVerticalZoom() {
    if (_allData.isEmpty) return SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 30, right: 30, bottom: 5, top: 5),
      child: Column(
        children: [
          Text(
            "Zoom vertical: ${(verticalZoomFactor * 100).toInt()}%",
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          Slider(
            value: verticalZoomFactor,
            min: 0.5, // Mínimo 50% (más zoom)
            max: 10.0, // Máximo 1000% (menos zoom)
            divisions: 95,
            label: "${(verticalZoomFactor * 100).toInt()}%",
            activeColor: Color(0xFF1D347A),
            onChanged: (value) {
              setState(() {
                verticalZoomFactor = value;
              });
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorPrimary = Theme.of(context).colorScheme.primary;
    final colorAccent = Theme.of(context).colorScheme.secondary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gráficas'),
        backgroundColor: colorPrimary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _forceRefreshData,
            tooltip: 'Recargar datos',
          ),
          IconButton(
            icon: Icon(isRealTime ? Icons.access_time : Icons.calendar_today),
            onPressed: () {
              setState(() {
                isRealTime = !isRealTime;
                if (isRealTime) {
                  selectedRange = null;
                  _loadInitialData();
                }
              });
            },
            tooltip: isRealTime
                ? 'Cambiar a modo histórico'
                : 'Cambiar a tiempo real',
          ),
          if (!isRealTime)
            IconButton(
              icon: const Icon(Icons.date_range),
              onPressed: _pickDateTimeRange,
              tooltip: 'Seleccionar rango de fechas',
            ),
          IconButton(
            icon: const Icon(Icons.delete_forever),
            onPressed: _confirmAndClearData,
            tooltip: 'Borrar todos los datos',
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              colorPrimary.withOpacity(0.1),
              Colors.white,
            ],
          ),
        ),
        child: Column(
          children: [
            // Controles superiores
            Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Selector de período de tiempo
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      _buildTimePeriodButton("Tiempo Real", "tiempo_real",
                          Icons.access_time, Colors.green),
                      _buildTimePeriodButton(
                          "Día", "dia", Icons.today, Colors.blue),
                      _buildTimePeriodButton("Semana", "semana",
                          Icons.calendar_view_week, Colors.purple),
                      _buildTimePeriodButton(
                          "Mes", "mes", Icons.calendar_month, Colors.orange),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (selectedRange != null && !isRealTime)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Rango: ${DateFormat('dd/MM/yyyy HH:mm').format(selectedRange!.start)} - ${DateFormat('dd/MM/yyyy HH:mm').format(selectedRange!.end)}',
                        style: TextStyle(
                          color: colorPrimary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Controles de zoom y muestras
            if (isRealTime) _buildSliderSamples(),
            _buildSliderVerticalZoom(),

            // Lista de gráficas
            Expanded(
              child: isLoading
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(color: colorPrimary),
                          const SizedBox(height: 16),
                          Text(
                            'Cargando datos...',
                            style: TextStyle(
                              color: colorPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    )
                  : _allData.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.show_chart,
                                size: 64,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _message.isNotEmpty
                                    ? _message
                                    : 'No hay datos disponibles',
                                style: TextStyle(
                                  fontSize: 18,
                                  color: Colors.grey[600],
                                  fontWeight: FontWeight.w500,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Los datos aparecerán aquí cuando el ESP32 esté conectado',
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
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          itemCount: _multiGraphGroups.length,
                          itemBuilder: (context, index) {
                            return _buildEnhancedGraph(
                                _multiGraphGroups[index]);
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  // Función para calcular el intervalo óptimo de tiempo para los títulos del eje X
  double _calculateTimeInterval(List<double> xTicks) {
    if (xTicks.length <= 1) return 1;

    final range = xTicks.last - xTicks.first;
    final timeRange = Duration(milliseconds: range.toInt());

    // Intervalos específicos según el período seleccionado
    switch (_timePeriod) {
      case "tiempo_real":
        // Para tiempo real, mostrar cada 5 minutos para mejor legibilidad
        return Duration(minutes: 5).inMilliseconds.toDouble();

      case "dia":
        // Para día completo, mostrar cada hora (24 muestras)
        return Duration(hours: 1).inMilliseconds.toDouble();

      case "semana":
        // Para semana completa, mostrar cada día (7 muestras)
        return Duration(hours: 24).inMilliseconds.toDouble();

      case "mes":
        // Para mes completo, mostrar cada 2 días para mejor legibilidad
        return Duration(hours: 48).inMilliseconds.toDouble();

      default:
        // Para otros casos, usar lógica anterior
        if (timeRange.inMinutes < 60) {
          return Duration(minutes: 5).inMilliseconds.toDouble();
        }
        if (timeRange.inHours < 24) {
          return Duration(minutes: 30).inMilliseconds.toDouble();
        }
        if (timeRange.inHours < 168) {
          return Duration(hours: 2).inMilliseconds.toDouble();
        }
        return Duration(hours: 24).inMilliseconds.toDouble();
    }
  }

  // Función para formatear valores con unidades apropiadas
  String _formatValueWithUnit(double value, String unit) {
    // Energía ya viene en Wh desde ESP32, no necesita conversión
    double displayValue = value;
    if (unit == "Wh") {
      if (value > 0) {
        print('[GRAPH DEBUG] Energía recibida: ${value}Wh (ya en Wh)');
      }
    }

    switch (unit) {
      case "Wh":
        // Para energía en Wh, usar más decimales si el valor es muy pequeño
        if (displayValue < 1.0 && displayValue > 0) {
          return "${displayValue.toStringAsFixed(3)} $unit"; // 3 decimales para valores pequeños
        } else {
          return "${displayValue.toStringAsFixed(2)} $unit"; // 2 decimales para valores normales
        }
      case "W":
        return "${displayValue.toStringAsFixed(2)} $unit"; // Potencia con 2 decimales
      case "A":
      case "V":
      case "Hz":
        return "${displayValue.toStringAsFixed(2)} $unit";
      case "°C":
        return "${displayValue.toStringAsFixed(2)}$unit"; // Temperatura con 2 decimales
      case "%":
        return "${displayValue.toStringAsFixed(2)}$unit"; // Humedad con 2 decimales
      case "L":
        return "${displayValue.toStringAsFixed(2)} $unit"; // Volumen con 2 decimales
      case "hPa":
        return "${displayValue.toStringAsFixed(2)} $unit"; // Presión con 2 decimales
      default:
        return displayValue.toStringAsFixed(2);
    }
  }

  /// Función para crear datos de ejemplo cuando no hay datos reales
  List<Map<String, dynamic>> _createSampleData() {
    print('[GRAPH DEBUG] 🏗️ Creando datos de ejemplo para testing...');

    final now = DateTime.now();
    final sampleData = <Map<String, dynamic>>[];

    // Crear datos para las últimas 2 horas con intervalos de 5 minutos
    for (int i = 0; i < 24; i++) {
      final timestamp =
          now.subtract(Duration(minutes: i * 5)).millisecondsSinceEpoch;

      sampleData.add({
        'timestamp': timestamp,
        'energia': 1500.0 + (i * 10), // Energía en Wh
        'aguaAlmacenada': 500.0 + (i * 2), // Agua en L
        'temperaturaAmbiente': 25.0 + (i * 0.1), // Temperatura en °C
        'humedadRelativa': 60.0 + (i * 0.5), // Humedad en %
      });
    }

    print(
        '[GRAPH DEBUG] ✅ Datos de ejemplo creados: ${sampleData.length} registros');
    return sampleData;
  }

  Widget _buildTimePeriodButton(
      String label, String period, IconData icon, Color color) {
    final isSelected = _timePeriod == period;
    return ElevatedButton.icon(
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: isSelected ? color : Colors.grey[700],
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        elevation: isSelected ? 4 : 0,
      ),
      onPressed: () {
        setState(() {
          _timePeriod = period;
          isRealTime = period == "tiempo_real";
          selectedRange = null;
        });
        _loadInitialData();
      },
    );
  }

  Color _getPeriodColor() {
    switch (_timePeriod) {
      case "tiempo_real":
        return Colors.green;
      case "dia":
        return Colors.blue;
      case "semana":
        return Colors.purple;
      case "mes":
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  IconData _getPeriodIcon() {
    switch (_timePeriod) {
      case "tiempo_real":
        return Icons.access_time;
      case "dia":
        return Icons.today;
      case "semana":
        return Icons.calendar_view_week;
      case "mes":
        return Icons.calendar_month;
      default:
        return Icons.schedule;
    }
  }

  String _getPeriodText() {
    switch (_timePeriod) {
      case "tiempo_real":
        return "TIEMPO REAL";
      case "dia":
        return "DÍA COMPLETO";
      case "semana":
        return "SEMANA COMPLETA";
      case "mes":
        return "MES COMPLETO";
      default:
        return "PERÍODO";
    }
  }
}

class _MultiGraphGroup {
  final String title;
  final List<String> keys;
  final List<String> seriesTitles;
  final List<Color> colors;
  final String unit;
  final IconData icon;
  List<bool>? selected;

  _MultiGraphGroup({
    required this.title,
    required this.keys,
    required this.seriesTitles,
    required this.colors,
    this.unit = "",
    this.icon = Icons.show_chart,
  }) {
    selected ??= List.filled(keys.length, true);
  }
}

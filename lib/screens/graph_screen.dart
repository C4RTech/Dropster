import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:hive/hive.dart';
import 'dart:async';
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
    setState(() {
      isLoading = true;
    });
    _allData = await _getDataFromHive(range: selectedRange);
    setState(() {
      isLoading = false;
    });
  }

  Future<List<Map<String, dynamic>>> _getDataFromHive(
      {DateTimeRange? range}) async {
    Box<Map> box;
    if (Hive.isBoxOpen(dataBoxName)) {
      box = Hive.box<Map>(dataBoxName);
    } else {
      box = await Hive.openBox<Map>(dataBoxName);
    }
    final all = box.values
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
    if (all.isEmpty) return [];
    all.sort((a, b) => _getTimestamp(a).compareTo(_getTimestamp(b)));
    if (range == null) {
      if (isRealTime && all.length > realTimeSampleCount) {
        return all.sublist(all.length - realTimeSampleCount);
      }
      return all;
    }
    return all.where((item) {
      final t = _parseTimestamp(item);
      return t != null && !t.isBefore(range.start) && !t.isAfter(range.end);
    }).toList();
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
              child: Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('Borrar')),
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

  void _onNewRealTimeData(Map<String, dynamic> newData) {
    if (!isRealTime || !mounted) return;
    setState(() {
      final current = List<Map<String, dynamic>>.from(_allData);
      current.add(Map<String, dynamic>.from(newData));
      current.sort((a, b) => _getTimestamp(a).compareTo(_getTimestamp(b)));
      // Eliminar duplicados de timestamp, conservando el último valor
      final map = LinkedHashMap<int, Map<String, dynamic>>();
      for (final item in current) {
        final ts = _getTimestamp(item);
        map[ts] = item;
      }
      final deduped = map.values.toList();
      if (deduped.length > realTimeSampleCount) {
        _allData = deduped.sublist(deduped.length - realTimeSampleCount);
      } else {
        _allData = deduped;
      }
    });
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
    if (data.isNotEmpty && data['timestamp'] != null) {
      _onNewRealTimeData(data);
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
    final groupIndex = _multiGraphGroups.indexOf(group);
    group.selected ??= List.filled(group.keys.length, true);

    List<List<FlSpot>> seriesSpots = [];
    List<String> enabledTitles = [];
    List<Color> enabledColors = [];
    int minSpots = 0;

    for (int i = 0; i < group.keys.length; i++) {
      if (!(group.selected![i])) continue;
      final key = group.keys[i];
      final color = group.colors[i];
      final title = group.seriesTitles[i];

      final source = _allData.where((e) => e[key] != null).toList();

      List<FlSpot> spots = source
          .map((entry) {
            final time = _parseTimestamp(entry);
            final y = (entry[key] as num?)?.toDouble();
            if (time == null || y == null) return null;
            return FlSpot(time.millisecondsSinceEpoch.toDouble(), y);
          })
          .where((e) => e != null)
          .cast<FlSpot>()
          .toList();

      // Elimina duplicados de timestamp en tiempo real, conservando el último valor
      if (isRealTime) {
        final map = LinkedHashMap<double, FlSpot>();
        for (final spot in spots) {
          map[spot.x] = spot;
        }
        spots = map.values.toList();
        if (spots.length > realTimeSampleCount) {
          spots = spots.sublist(spots.length - realTimeSampleCount);
        }
      }

      if (minSpots == 0 || spots.length < minSpots) minSpots = spots.length;

      seriesSpots.add(spots);
      enabledTitles.add(title);
      enabledColors.add(color);
    }

    List<double> xTicks = [];
    if (seriesSpots.isNotEmpty && seriesSpots[0].isNotEmpty) {
      xTicks = seriesSpots[0].map((e) => e.x).toList();
    }

    final bool showChart = seriesSpots.any((lst) => lst.length >= 2);

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
                      color: Theme.of(context).colorScheme.primary,
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
                            color: Theme.of(context).colorScheme.primary,
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
                              reservedSize: 30,
                              getTitlesWidget: (value, meta) {
                                return Text(
                                  group.unit.isNotEmpty
                                      ? _formatValueWithUnit(value, group.unit)
                                      : value.toStringAsFixed(0),
                                  style: TextStyle(
                                      color: Colors.white, fontSize: 10),
                                );
                              },
                            ),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 40,
                              interval: (xTicks.length > 1)
                                  ? ((xTicks.last - xTicks.first) / 4)
                                  : 1,
                              getTitlesWidget: (value, meta) {
                                final dt = DateTime.fromMillisecondsSinceEpoch(
                                    value.toInt());
                                return Text(
                                  "${dt.hour}:${dt.minute}:${dt.second}",
                                  style: TextStyle(
                                      color: Colors.white, fontSize: 10),
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
                            if (seriesSpots[i].length >= 2)
                              LineChartBarData(
                                spots: seriesSpots[i],
                                isCurved: true,
                                curveSmoothness: 0.4, // Más suavizado
                                color: enabledColors[i],
                                dotData: FlDotData(show: false), // No nudos
                                belowBarData: BarAreaData(show: false),
                                barWidth: 2.5,
                              ),
                        ],
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
                  color: Color(0xFF1D347A),
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
              color: Color(0xFF1D347A),
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          Slider(
            value: verticalZoomFactor,
            min: 0.2,
            max: 75.0, // Hasta 1500%
            divisions: 148,
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
    final colorText = Theme.of(context).colorScheme.onBackground;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gráficas en Tiempo Real'),
        backgroundColor: colorPrimary,
        foregroundColor: Colors.white,
        actions: [
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: isRealTime ? Colors.green : Colors.blue,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isRealTime
                                  ? Icons.access_time
                                  : Icons.calendar_today,
                              color: Colors.white,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              isRealTime ? 'TIEMPO REAL' : 'HISTÓRICO',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
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

  void _showFilterDialog() {
    // Implementation of _showFilterDialog method
  }

  void _showSampleCountDialog() {
    // Implementation of _showSampleCountDialog method
  }

  // Función para formatear valores con unidades apropiadas
  String _formatValueWithUnit(double value, String unit) {
    switch (unit) {
      case "Wh":
      case "W":
        return "${value.toStringAsFixed(1)} $unit";
      case "A":
      case "V":
      case "Hz":
        return "${value.toStringAsFixed(2)} $unit";
      case "°C":
        return "${value.toStringAsFixed(1)}$unit";
      case "%":
        return "${value.toStringAsFixed(1)}$unit";
      case "L":
        return "${value.toStringAsFixed(1)} $unit";
      case "hPa":
        return "${value.toStringAsFixed(0)} $unit";
      default:
        return value.toStringAsFixed(2);
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

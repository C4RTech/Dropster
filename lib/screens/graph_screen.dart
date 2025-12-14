import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:hive/hive.dart';
import 'dart:async';
import 'dart:math' as math;
import '../services/singleton_mqtt_service.dart';
// import 'package:intl/intl.dart';

class GraphScreen extends StatefulWidget {
  const GraphScreen({super.key});

  @override
  _GraphScreenState createState() => _GraphScreenState();
}

class _GraphScreenState extends State<GraphScreen> {
  List<Map<String, dynamic>> _allData = [];
  bool isRealTime = true;
  bool isLoading = false;
  DateTimeRange? selectedRange;
  String _message = "";
  String _timePeriod = "tiempo_real";

  final String dataBoxName = 'energyData';
  int realTimeSampleCount = 20;
  final String settingsBoxName = 'settings';
  final String sampleCountKey = 'graphSampleCount';

  late final ValueNotifier<Map<String, dynamic>> _globalNotifier;

  final List<_MultiGraphGroup> _multiGraphGroups = [
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
    _MultiGraphGroup(
      title: "Temperaturas",
      keys: ["temperaturaAmbiente", "sht1Temp", "compressorTemp"],
      seriesTitles: ["Ambiente", "Evaporador", "Compresor"],
      colors: [Colors.red, Colors.orange, Colors.yellow],
      unit: "°C",
      icon: Icons.thermostat,
    ),
    _MultiGraphGroup(
      title: "Humedad",
      keys: ["humedadRelativa", "sht1Hum"],
      seriesTitles: ["Ambiente", "Evaporador"],
      colors: [Colors.blue.shade300, Colors.cyan],
      unit: "%",
      icon: Icons.water,
    ),
  ];

  late List<bool> _showTableForGroup;
  double verticalZoomFactor = 1.0;

  @override
  void initState() {
    super.initState();
    print('[GRAPH DEBUG] initState iniciado');
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

  Future<void> _loadInitialData() async {
    print('[GRAPH DEBUG] 🔄 Iniciando carga inicial de datos...');
    setState(() {
      isLoading = true;
    });

    try {
      DateTimeRange? range = _calculateTimeRange();
      _allData = await _getDataFromHive(range: range);
      print('[GRAPH DEBUG] ✅ Datos cargados: ${_allData.length} registros');

      // Para tiempo real, no crear datos de ejemplo - mantener vacío si no hay datos
      if (_allData.isEmpty && _timePeriod == "tiempo_real") {
        print(
            '[GRAPH DEBUG] ⚠️ No hay datos reales disponibles para tiempo real - esperando datos en tiempo real');
        // No crear datos de ejemplo, mantener lista vacía para tiempo real
        // Los datos se actualizarán automáticamente cuando llegue el primer dato MQTT
      }

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

  Future<void> _refreshData() async {
    print('[GRAPH DEBUG] 🔄 Iniciando refresh manual de datos...');

    try {
      DateTimeRange? range = _calculateTimeRange();
      final newData = await _getDataFromHive(range: range);
      print('[GRAPH DEBUG] ✅ Datos refrescados: ${newData.length} registros');

      setState(() {
        _allData = newData;

        if (_allData.isEmpty && _timePeriod == "tiempo_real") {
          print(
              '[GRAPH DEBUG] ⚠️ No hay datos reales disponibles para tiempo real - esperando datos en tiempo real');
          // No crear datos de ejemplo, mantener lista vacía para tiempo real
          // Los datos se actualizarán automáticamente cuando llegue el primer dato MQTT
        }
      });

      // Mostrar snackbar con el número de muestras cargadas
      if (mounted) {
        final sampleCount = _allData.length;
        final dataType = "muestras";

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ Datos actualizados: $sampleCount $dataType cargadas',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
            ),
            backgroundColor: Colors.green.shade600,
            duration: Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }

      print('[GRAPH DEBUG] ✅ Refresh completado exitosamente');
    } catch (e) {
      print('[GRAPH DEBUG] ❌ Error en refresh: $e');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '❌ Error al refrescar datos: $e',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
            ),
            backgroundColor: Colors.red.shade600,
            duration: Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    }
  }

  DateTimeRange? _calculateTimeRange() {
    final now = DateTime.now();

    switch (_timePeriod) {
      case "tiempo_real":
        return DateTimeRange(
          start: now.subtract(Duration(hours: 2)),
          end: now,
        );
      case "dia":
        final startOfDay = DateTime(now.year, now.month, now.day);
        return DateTimeRange(
          start: startOfDay,
          end: startOfDay.add(Duration(days: 1)),
        );
      case "semana":
        final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
        final startOfWeekMidnight =
            DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day);
        return DateTimeRange(
          start: startOfWeekMidnight,
          end: startOfWeekMidnight.add(Duration(days: 7)),
        );
      case "mes":
        final startOfMonth = DateTime(now.year, now.month, 1);
        final endOfMonth = DateTime(now.year, now.month + 1, 1);
        return DateTimeRange(
          start: startOfMonth,
          end: endOfMonth,
        );
      case "personalizado":
        return selectedRange;
      default:
        return null;
    }
  }

  Future<List<Map<String, dynamic>>> _getDataFromHive(
      {DateTimeRange? range}) async {
    print('[GRAPH DEBUG] 🔍 Obteniendo datos de Hive...');

    try {
      Box<Map> box;
      if (Hive.isBoxOpen(dataBoxName)) {
        box = Hive.box<Map>(dataBoxName);
      } else {
        box = await Hive.openBox<Map>(dataBoxName);
      }

      final rawData = box.values.toList();
      print('[GRAPH DEBUG] 📊 Datos crudos en Hive: ${rawData.length}');

      final all = rawData
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
      print('[GRAPH DEBUG] 📊 Datos válidos: ${all.length}');

      if (all.isEmpty) {
        print('[GRAPH DEBUG] ⚠️ No hay datos en Hive');
        return [];
      }

      all.sort((a, b) => _getTimestamp(a).compareTo(_getTimestamp(b)));

      if (range == null) {
        if (isRealTime && all.length > realTimeSampleCount) {
          final result = all.sublist(all.length - realTimeSampleCount);
          print('[GRAPH DEBUG] 📊 Tiempo real: ${result.length} muestras');
          return result;
        }
        return all;
      }

      final filtered = all.where((item) {
        final t = _parseTimestamp(item);
        if (t == null) return false;
        final inRange = !t.isBefore(range.start) && !t.isAfter(range.end);
        return inRange;
      }).toList();

      // Deduplicar por timestamp para evitar múltiples valores en el mismo instante
      final map = <int, Map<String, dynamic>>{};
      for (final item in filtered) {
        final ts = _getTimestamp(item);
        if (ts > 0) map[ts] = item;
      }
      final deduped = map.values.toList();
      deduped.sort((a, b) => _getTimestamp(a).compareTo(_getTimestamp(b)));

      print(
          '[GRAPH DEBUG] 📊 Datos filtrados y deduplicados: ${deduped.length} de ${all.length}');
      return deduped;
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
    return 0;
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
          }
        });
      });
    }
  }

  void _handleGlobalNotifierChange() {
    if (!isRealTime || !mounted) return;

    final data = _globalNotifier.value;
    print('[GRAPH DEBUG] 📡 Notifier cambió: ${data.keys.length} keys');

    // Solo procesar si hay datos válidos y timestamp
    if (data.isNotEmpty && data['timestamp'] != null) {
      print(
          '[GRAPH DEBUG] 📡 Datos válidos recibidos, actualizando gráfica...');
      _onNewRealTimeData(data);
    } else {
      print('[GRAPH DEBUG] ⚠️ Datos inválidos o sin timestamp');
    }
  }

  void _onNewRealTimeData(Map<String, dynamic> newData) {
    if (!isRealTime || !mounted) return;

    final newTimestamp = _getTimestamp(newData);
    if (newTimestamp <= 0) return;

    final hasValidData = [
      'energia',
      'aguaAlmacenada',
      'temperaturaAmbiente',
      'humedadRelativa',
      'sht1Temp',
      'compressorTemp',
      'sht1Hum'
    ].any((key) => newData.containsKey(key) && newData[key] != null);
    if (!hasValidData) return;

    setState(() {
      final current = List<Map<String, dynamic>>.from(_allData);
      current.add(Map<String, dynamic>.from(newData));

      current.sort((a, b) => _getTimestamp(a).compareTo(_getTimestamp(b)));

      final map = <int, Map<String, dynamic>>{};
      for (final item in current) {
        final ts = _getTimestamp(item);
        if (ts > 0) map[ts] = item;
      }
      final deduped = map.values.toList();

      if (deduped.length > realTimeSampleCount) {
        _allData = deduped.sublist(deduped.length - realTimeSampleCount);
      } else {
        _allData = deduped;
      }

      print('[GRAPH DEBUG] ✅ Nuevo dato agregado. Total: ${_allData.length}');
    });
  }

  @override
  void dispose() {
    _globalNotifier.removeListener(_handleGlobalNotifierChange);
    super.dispose();
  }

  Widget _buildEnhancedGraph(_MultiGraphGroup group) {
    try {
      print('[GRAPH DEBUG] 📈 Construyendo gráfica para: ${group.title}');

      final groupIndex = _multiGraphGroups.indexOf(group);
      group.selected ??= List.filled(group.keys.length, true);

      List<List<FlSpot>> seriesSpots = [];
      List<String> enabledTitles = [];
      List<Color> enabledColors = [];

      print('[GRAPH DEBUG] 📊 Procesando ${group.keys.length} series');

      for (int i = 0; i < group.keys.length; i++) {
        if (!(group.selected![i])) continue;

        final key = group.keys[i];
        final color = group.colors[i];
        final title = group.seriesTitles[i];

        final source = _allData.where((e) => e[key] != null).toList();
        print('[GRAPH DEBUG] 📊 Datos con key "$key": ${source.length}');

        List<FlSpot> spots = source
            .map((entry) {
              final time = _parseTimestamp(entry);
              final rawValue = entry[key];
              double? y;

              // Safe parsing for both numeric and string values
              if (rawValue is num) {
                y = rawValue.toDouble();
              } else if (rawValue is String) {
                y = double.tryParse(rawValue);
              } else if (rawValue is num?) {
                y = rawValue?.toDouble();
              }

              if (time == null || y == null || y.isNaN || y.isInfinite) {
                return null;
              }

              final timestamp = time.millisecondsSinceEpoch.toDouble();
              if (timestamp <= 0) return null;

              return FlSpot(timestamp, y);
            })
            .where((e) => e != null)
            .cast<FlSpot>()
            .toList();

        if (isRealTime && spots.length > realTimeSampleCount) {
          spots = spots.sublist(spots.length - realTimeSampleCount.toInt());
        }

        seriesSpots.add(spots);
        enabledTitles.add(title);
        enabledColors.add(color);
      }

      // Calcular xTicks de todas las series para incluir rangos completos
      List<double> xTicks =
          seriesSpots.expand((lst) => lst.map((s) => s.x)).toList();

      // Calcular minX y maxX con padding para evitar que líneas se salgan
      double minX =
          xTicks.isNotEmpty ? xTicks.reduce((a, b) => a < b ? a : b) : 0;
      double maxX =
          xTicks.isNotEmpty ? xTicks.reduce((a, b) => a > b ? a : b) : 0;
      if (minX != maxX) {
        double range = maxX - minX;
        double padding = range * 0.01; // 1% padding
        minX -= padding;
        maxX += padding;
      }

      final hasAnyData = seriesSpots.any((lst) => lst.isNotEmpty);
      final showChart = hasAnyData;

      double? minY, maxY;
      final allYValues =
          seriesSpots.expand((lst) => lst.map((s) => s.y)).toList();
      if (allYValues.isNotEmpty) {
        final minVal = allYValues.reduce((a, b) => a < b ? a : b);
        final maxVal = allYValues.reduce((a, b) => a > b ? a : b);
        final range = (maxVal - minVal).abs();
        final expand = range == 0
            ? (minVal.abs() * 0.25 * verticalZoomFactor)
            : (range * 0.25 * verticalZoomFactor);
        minY = minVal - expand;
        maxY = maxVal + expand;
      }

      return Card(
        color: Color(0xFF2C3E50),
        elevation: 4,
        margin: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Padding(
          padding:
              const EdgeInsets.only(top: 12, bottom: 2, left: 6, right: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
                        color: Color(0xFF64B5F6),
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
                              color: Color(0xFF64B5F6),
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
                                reservedSize: 45,
                                getTitlesWidget: (value, meta) {
                                  return Text(
                                    group.unit.isNotEmpty
                                        ? _formatValueWithUnit(
                                            value, group.unit)
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
                                reservedSize: 50,
                                interval: _calculateTimeInterval(xTicks),
                                getTitlesWidget: (value, meta) {
                                  final dt =
                                      DateTime.fromMillisecondsSinceEpoch(
                                          value.toInt());

                                  String timeLabel;
                                  if (isRealTime) {
                                    // Para tiempo real: mostrar HH:MM
                                    timeLabel =
                                        "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
                                  } else {
                                    // Para otros periodos: mostrar DD/MM HH:MM
                                    timeLabel =
                                        "${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
                                  }

                                  return Text(
                                    timeLabel,
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
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
                              border: Border.all(
                                  color: Colors.black26, width: 0.5)),
                          lineBarsData: [
                            for (int i = 0; i < seriesSpots.length; i++)
                              if (seriesSpots[i].isNotEmpty)
                                LineChartBarData(
                                  spots: seriesSpots[i],
                                  isCurved: seriesSpots[i].length >= 2,
                                  curveSmoothness: 0.4,
                                  color: enabledColors[i],
                                  dotData: FlDotData(
                                      show: seriesSpots[i].length == 1),
                                  belowBarData: BarAreaData(show: false),
                                  barWidth: 2.5,
                                ),
                          ],
                          lineTouchData: LineTouchData(
                            touchTooltipData: LineTouchTooltipData(
                              tooltipBgColor: Colors.blueGrey.withOpacity(0.8),
                              getTooltipItems:
                                  (List<LineBarSpot> touchedSpots) {
                                return touchedSpots
                                    .map((LineBarSpot touchedSpot) {
                                  final value = touchedSpot.y;
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
                          ),
                          minX: minX,
                          maxX: maxX,
                          minY: minY,
                          maxY: maxY,
                        ),
                      ),
              ),
              // Controles de selección de variables (solo para gráficas con múltiples series)
              if (group.keys.length > 1) ...[
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Seleccionar variables:',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: List.generate(group.keys.length, (index) {
                          final isSelected = group.selected![index];
                          final color = group.colors[index];
                          final title = group.seriesTitles[index];

                          return FilterChip(
                            label: Text(
                              title,
                              style: TextStyle(
                                color: isSelected ? Colors.white : color,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            selected: isSelected,
                            onSelected: (bool selected) {
                              setState(() {
                                group.selected![index] = selected;
                              });
                            },
                            backgroundColor: Colors.white.withOpacity(0.1),
                            selectedColor: color.withOpacity(0.8),
                            showCheckmark: false,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                              side: BorderSide(
                                color: color.withOpacity(0.5),
                                width: 1,
                              ),
                            ),
                          );
                        }),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    } catch (e, stackTrace) {
      print(
          '[GRAPH DEBUG] ❌ Error en _buildEnhancedGraph para ${group.title}: $e');
      print('[GRAPH DEBUG] Stack trace: $stackTrace');
      return Card(
        color: Colors.red.shade50,
        elevation: 4,
        margin: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Icon(Icons.error, color: Colors.red, size: 48),
              const SizedBox(height: 10),
              Text(
                'Error en gráfica: ${group.title}',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 5),
              Text(
                'Error: $e',
                style: TextStyle(
                  color: Colors.red.shade700,
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
  }

  double _calculateTimeInterval(List<double> xTicks) {
    if (xTicks.length <= 1) return 1;

    final range = xTicks.last - xTicks.first;
    final timeRange = Duration(milliseconds: range.toInt());

    // Calcular número óptimo de etiquetas basado en el ancho disponible
    // Para evitar solapamiento, máximo 4 etiquetas
    const maxLabels = 4;
    final optimalInterval = range / maxLabels;

    // Ajustar el intervalo basado en el rango de tiempo para mantener legibilidad
    if (timeRange.inMinutes < 60) {
      // Para rangos cortos (< 1 hora): intervalos de 5-10 minutos
      final minutesInterval =
          math.max(5, (timeRange.inMinutes / maxLabels).round());
      return Duration(minutes: minutesInterval).inMilliseconds.toDouble();
    } else if (timeRange.inHours < 24) {
      // Para rangos de horas: intervalos de 1-3 horas
      final hoursInterval =
          math.max(1, (timeRange.inHours / maxLabels).round());
      return Duration(hours: hoursInterval).inMilliseconds.toDouble();
    } else {
      // Para rangos largos: intervalos de 6-12 horas
      final hoursInterval =
          math.max(6, (timeRange.inHours / maxLabels).round());
      return Duration(hours: hoursInterval).inMilliseconds.toDouble();
    }
  }

  String _formatValueWithUnit(double value, String unit) {
    double displayValue = value;
    if (unit == "Wh") {
      if (value > 0) {
        print('[GRAPH DEBUG] Energía recibida: ${value}Wh');
      }
    }
    switch (unit) {
      case "Wh":
        if (displayValue < 1.0 && displayValue > 0) {
          return "${displayValue.toStringAsFixed(3)} $unit";
        } else {
          return "${displayValue.toStringAsFixed(2)} $unit";
        }
      case "°C":
        return "${displayValue.toStringAsFixed(2)}$unit";
      case "%":
        return "${displayValue.toStringAsFixed(2)}$unit";
      case "L":
        return "${displayValue.toStringAsFixed(2)} $unit";
      default:
        return displayValue.toStringAsFixed(2);
    }
  }

  List<Map<String, dynamic>> _createSampleData() {
    print('[GRAPH DEBUG] 🏗️ Creando datos de ejemplo...');
    final now = DateTime.now();
    final sampleData = <Map<String, dynamic>>[];
    for (int i = 0; i < 24; i++) {
      final timestamp =
          now.subtract(Duration(minutes: i * 5)).millisecondsSinceEpoch;
      sampleData.add({
        'timestamp': timestamp,
        'energia': 1500.0 + (i * 10),
        'aguaAlmacenada': 500.0 + (i * 2),
        'temperaturaAmbiente': 25.0 + (i * 0.1),
        'humedadRelativa': 60.0 + (i * 0.5),
        'sht1Temp': 15.0 + (i * 0.05), // Temperatura del evaporador
        'compressorTemp': 35.0 + (i * 0.2), // Temperatura del compresor
        'sht1Hum': 85.0 + (i * 0.3), // Humedad del evaporador
      });
    }
    print('[GRAPH DEBUG] ✅ Datos de ejemplo creados: ${sampleData.length}');
    return sampleData;
  }

  Future<void> _selectDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(Duration(days: 365)),
      lastDate: DateTime.now(),
      initialDateRange: selectedRange,
    );

    if (picked != null && picked != selectedRange) {
      setState(() {
        selectedRange = picked;
        _timePeriod = "personalizado";
        isRealTime = false;
      });
      _loadInitialData();
    }
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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

  @override
  Widget build(BuildContext context) {
    try {
      print(
          '[GRAPH DEBUG] build llamado, isLoading = $isLoading, _allData.length = ${_allData.length}');
      final colorPrimary = Theme.of(context).colorScheme.primary;
      final colorAccent = Theme.of(context).colorScheme.secondary;
      print('[GRAPH DEBUG] Colores obtenidos del tema');

      return Scaffold(
        appBar: AppBar(
          title: const Text('Gráficas'),
          backgroundColor: colorPrimary,
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => _refreshData(),
              tooltip: 'Recargar datos',
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
              Container(
                padding: const EdgeInsets.all(16),
                child: Wrap(
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
                        "Mes", "mes", Icons.calendar_view_month, Colors.orange),
                    ElevatedButton.icon(
                      icon: Icon(Icons.date_range, size: 16),
                      label: Text("Personalizado"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _timePeriod == "personalizado"
                            ? Colors.teal
                            : Colors.grey[700],
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 8),
                        elevation: _timePeriod == "personalizado" ? 4 : 0,
                      ),
                      onPressed: _selectDateRange,
                    ),
                  ],
                ),
              ),
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
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        itemCount: _multiGraphGroups.length,
                        itemBuilder: (context, index) {
                          return _buildEnhancedGraph(_multiGraphGroups[index]);
                        },
                      ),
              ),
            ],
          ),
        ),
      );
    } catch (e, stackTrace) {
      print('[GRAPH DEBUG] ❌ Error en build: $e');
      print('[GRAPH DEBUG] Stack trace: $stackTrace');
      return Scaffold(
        appBar: AppBar(
          title: const Text('Gráficas - Error'),
          backgroundColor: Colors.red,
          foregroundColor: Colors.white,
        ),
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.red.withOpacity(0.1),
                Colors.white,
              ],
            ),
          ),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 64,
                    color: Colors.red,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Error al cargar las gráficas',
                    style: TextStyle(
                      color: Colors.red,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Error: $e',
                    style: TextStyle(
                      color: Colors.red.shade700,
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        isLoading = false;
                        _message = 'Error: $e';
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Reintentar'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
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

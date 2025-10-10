import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../services/singleton_mqtt_service.dart';
import '../services/mqtt_service.dart';
import '../services/mqtt_hive.dart';

class DropsterHomeScreen extends StatefulWidget {
  const DropsterHomeScreen({Key? key}) : super(key: key);

  @override
  State<DropsterHomeScreen> createState() => _DropsterHomeScreenState();
}

class _DropsterHomeScreenState extends State<DropsterHomeScreen> {
  // Datos reales del ESP32
  double tankLevel = 0.0;
  bool isSystemOn = false;
  double energyToday = 0.0;
  double tempAmb = 0.0;
  double humRel = 0.0;
  double humAbs = 0.0;
  List<FlSpot> chartData = List.generate(24, (i) => FlSpot(i.toDouble(), 0));
  List<FlSpot> chartData2 = List.generate(24, (i) => FlSpot(i.toDouble(), 0));
  double aguaGenerada = 0.0;

  Timer? timer;
  final MqttService _mqttService = MqttService();

  @override
  void initState() {
    super.initState();
    _listenToMqttData();
    _initializeMqttConnection();
  }

  void _initializeMqttConnection() async {
    try {
      await MqttHiveService.initHive();
      final hiveService = MqttHiveService();
      await _mqttService.connect(hiveService);
    } catch (e) {
      print('Error conectando MQTT: $e');
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  void _listenToMqttData() {
    SingletonMqttService().notifier.addListener(() {
      final data = SingletonMqttService().notifier.value;
      if (data.isNotEmpty) {
        setState(() {
          // Datos reales del ESP32
          tempAmb = (data['temperaturaAmbiente'] ?? 0.0).toDouble();
          humRel = (data['humedadRelativa'] ?? 0.0).toDouble();
          humAbs = (data['humedadAbsoluta'] ?? 0.0).toDouble();
          aguaGenerada = (data['aguaAlmacenada'] ?? 0.0).toDouble();
          tankLevel = (aguaGenerada / 10.0).clamp(0.0, 1.0);
          energyToday = (data['energia'] ?? 0.0).toDouble();

          // Actualizar gráfica con datos reales del ESP32
          int hour = DateTime.now().hour;
          if (energyToday > 0) {
            chartData[hour] = FlSpot(hour.toDouble(), energyToday);
          }
          if (aguaGenerada > 0) {
            chartData2[hour] = FlSpot(hour.toDouble(), aguaGenerada);
          }
        });
      }
    });
  }

  void _toggleSystem() async {
    if (!_mqttService.isConnected) {
      print('MQTT no conectado. Intentando reconectar...');
      _initializeMqttConnection();
      // Verificar conexión después de intentar reconectar
      await Future.delayed(Duration(milliseconds: 500));
      if (!_mqttService.isConnected) {
        print('No se pudo conectar a MQTT');
        return;
      }
    }

    final command = isSystemOn ? "OFF" : "ON";
    print('Enviando comando: $command');
    await _mqttService.publishCommand(command);

    setState(() {
      isSystemOn = !isSystemOn;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorPrimary = Theme.of(context).colorScheme.primary;
    final colorAccent = Theme.of(context).colorScheme.secondary;
    final colorText = Theme.of(context).colorScheme.onBackground;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset('lib/assets/images/Dropster_simbolo.png', height: 32),
            const SizedBox(width: 8),
            const Text('Dropster'),
          ],
        ),
        centerTitle: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Nivel del tanque
            _buildTankLevelCard(colorPrimary, colorAccent, colorText),
            const SizedBox(height: 16),
            // Estado del sistema y botón
            _buildSystemStatusCard(colorPrimary, colorAccent, colorText),
            const SizedBox(height: 16),
            // Energía consumida hoy
            _buildEnergyCard(colorPrimary, colorAccent, colorText),
            const SizedBox(height: 16),
            // Temperatura ambiente
            _buildTempCard(colorPrimary, colorAccent, colorText),
            const SizedBox(height: 16),
            // Humedad relativa
            _buildHumRelCard(colorPrimary, colorAccent, colorText),
            const SizedBox(height: 16),
            // Humedad absoluta
            _buildHumAbsCard(colorPrimary, colorAccent, colorText),
            const SizedBox(height: 24),
            // Gráfica de línea
            _buildLineChartCard(colorPrimary, colorAccent, colorText),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNavBar(colorPrimary, colorAccent),
    );
  }

  Widget _buildTankLevelCard(
      Color colorPrimary, Color colorAccent, Color colorText) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 500),
                  width: 32,
                  height: 32,
                  transform: Matrix4.identity()
                    ..scale(tankLevel > 0 ? 1.0 : 0.8),
                  child: Opacity(
                    opacity: tankLevel > 0 ? 1.0 : 0.4,
                    child: Image.asset(
                      'lib/assets/images/Dropster_simbolo.png',
                      fit: BoxFit.contain,
                      color: tankLevel > 0
                          ? (tankLevel > 0.8
                              ? colorAccent
                              : colorAccent.withOpacity(0.7))
                          : colorAccent.withOpacity(0.3),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text('Nivel del tanque',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: colorText)),
                const Spacer(),
                Text('${(tankLevel * 100).toStringAsFixed(0)}%',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF42A5F5))),
              ],
            ),
            const SizedBox(height: 12),
            // Barra de progreso sin porcentaje encima
            LinearProgressIndicator(
              value: tankLevel,
              minHeight: 12,
              backgroundColor: colorAccent.withOpacity(0.2),
              valueColor: AlwaysStoppedAnimation<Color>(colorAccent),
              borderRadius: BorderRadius.circular(8),
            ),
            if (tankLevel > 0.95)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text('¡Tanque lleno!',
                    style: TextStyle(
                        color: Colors.red, fontWeight: FontWeight.bold)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSystemStatusCard(
      Color colorPrimary, Color colorAccent, Color colorText) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(isSystemOn ? Icons.power : Icons.power_off,
                color: isSystemOn ? colorAccent : Colors.red, size: 40),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                isSystemOn ? 'Sistema Encendido' : 'Sistema Apagado',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: colorText),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: isSystemOn ? colorAccent : Colors.red,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              onPressed: _toggleSystem,
              child: Text(isSystemOn ? 'Apagar' : 'Encender'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEnergyCard(
      Color colorPrimary, Color colorAccent, Color colorText) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(Icons.flash_on, color: colorAccent, size: 32),
            const SizedBox(width: 12),
            Text('Energía hoy',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: colorText)),
            const Spacer(),
            Text('${energyToday.toStringAsFixed(2)} kWh',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: colorPrimary)),
          ],
        ),
      ),
    );
  }

  Widget _buildTempCard(
      Color colorPrimary, Color colorAccent, Color colorText) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(Icons.thermostat, color: colorAccent, size: 32),
            const SizedBox(width: 12),
            Text('Temp. ambiente',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: colorText)),
            const Spacer(),
            Text('${tempAmb.toStringAsFixed(1)} °C',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: colorPrimary)),
          ],
        ),
      ),
    );
  }

  Widget _buildHumRelCard(
      Color colorPrimary, Color colorAccent, Color colorText) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(Icons.water, color: colorAccent, size: 32),
            const SizedBox(width: 12),
            Text('Humedad relativa',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: colorText)),
            const Spacer(),
            Text('${humRel.toStringAsFixed(1)} %',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: colorPrimary)),
          ],
        ),
      ),
    );
  }

  Widget _buildHumAbsCard(
      Color colorPrimary, Color colorAccent, Color colorText) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(Icons.grain, color: colorAccent, size: 32),
            const SizedBox(width: 12),
            Text('Humedad absoluta',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: colorText)),
            const Spacer(),
            Text('${humAbs.toStringAsFixed(1)} g/m³',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: colorPrimary)),
          ],
        ),
      ),
    );
  }

  Widget _buildLineChartCard(
      Color colorPrimary, Color colorAccent, Color colorText) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Energía vs Agua generada (hoy)',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: colorText)),
            const SizedBox(height: 16),
            SizedBox(
              height: 180,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(show: true, drawVerticalLine: false),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles:
                          SideTitles(showTitles: true, reservedSize: 40),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        getTitlesWidget: (value, meta) {
                          int hour = value.toInt();
                          if (hour % 2 == 0 && hour >= 0 && hour <= 23) {
                            return Text('$hour',
                                style:
                                    TextStyle(fontSize: 12, color: colorText));
                          }
                          return const SizedBox.shrink();
                        },
                        interval: 1,
                      ),
                    ),
                    rightTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  minX: 0,
                  maxX: 23,
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: chartData,
                      isCurved: true,
                      color: colorAccent,
                      barWidth: 4,
                      dotData: FlDotData(show: false),
                    ),
                    LineChartBarData(
                      spots: chartData2,
                      isCurved: true,
                      color: colorPrimary,
                      barWidth: 4,
                      dotData: FlDotData(show: false),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.flash_on, color: colorAccent, size: 18),
                const SizedBox(width: 4),
                Text('Energía', style: TextStyle(color: colorAccent)),
                const SizedBox(width: 16),
                Icon(Icons.water_drop, color: colorPrimary, size: 18),
                const SizedBox(width: 4),
                Text('Agua', style: TextStyle(color: colorPrimary)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNavBar(Color colorPrimary, Color colorAccent) {
    return BottomNavigationBar(
      type: BottomNavigationBarType.fixed,
      backgroundColor: Colors.white,
      selectedItemColor: colorAccent,
      unselectedItemColor: colorPrimary.withOpacity(0.5),
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Inicio'),
        BottomNavigationBarItem(icon: Icon(Icons.monitor), label: 'Monitoreo'),
        BottomNavigationBarItem(
            icon: Icon(Icons.show_chart), label: 'Gráficas'),
        BottomNavigationBarItem(icon: Icon(Icons.history), label: 'Historial'),
        BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Ajustes'),
      ],
      currentIndex: 0,
      onTap: (i) {},
    );
  }
}

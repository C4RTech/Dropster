import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

class MonitorScreen extends StatefulWidget {
  const MonitorScreen({Key? key}) : super(key: key);

  @override
  State<MonitorScreen> createState() => _MonitorScreenState();
}

class _MonitorScreenState extends State<MonitorScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Timer? timer;
  final Random random = Random();

  // Variables simuladas
  // Ambiente
  double tempAmb = 27.5;
  double humRelAmb = 68.0;
  double humAbsAmb = 18.2;
  double presionAmb = 1013.0;
  // Eléctrico
  double voltaje = 220.0;
  double corriente = 4.2;
  double potencia = 900.0;
  double energia = 2.3;
  // Agua
  double nivelTanque = 0.65;
  double tempEvap = 12.0;
  double tempCond = 35.0;
  double humRelEvap = 80.0;
  double humRelCond = 60.0;
  double puntoRocioEvap = 8.0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    timer = Timer.periodic(const Duration(seconds: 2), (_) => _simulateData());
  }

  @override
  void dispose() {
    timer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  void _simulateData() {
    setState(() {
      tempAmb = (tempAmb + (random.nextDouble() - 0.5) * 0.3).clamp(15.0, 35.0);
      humRelAmb = (humRelAmb + (random.nextDouble() - 0.5) * 2).clamp(30.0, 100.0);
      humAbsAmb = (humAbsAmb + (random.nextDouble() - 0.5) * 0.5).clamp(5.0, 30.0);
      presionAmb = (presionAmb + (random.nextDouble() - 0.5) * 1.5).clamp(980.0, 1050.0);
      voltaje = (voltaje + (random.nextDouble() - 0.5) * 2).clamp(200.0, 240.0);
      corriente = (corriente + (random.nextDouble() - 0.5) * 0.2).clamp(0.0, 10.0);
      potencia = voltaje * corriente;
      energia = (energia + (random.nextDouble() - 0.5) * 0.1).clamp(0.0, 20.0);
      nivelTanque = (nivelTanque + (random.nextDouble() - 0.5) * 0.02).clamp(0.0, 1.0);
      tempEvap = (tempEvap + (random.nextDouble() - 0.5) * 0.5).clamp(5.0, 20.0);
      tempCond = (tempCond + (random.nextDouble() - 0.5) * 0.5).clamp(25.0, 45.0);
      humRelEvap = (humRelEvap + (random.nextDouble() - 0.5) * 2).clamp(40.0, 100.0);
      humRelCond = (humRelCond + (random.nextDouble() - 0.5) * 2).clamp(30.0, 90.0);
      puntoRocioEvap = (puntoRocioEvap + (random.nextDouble() - 0.5) * 0.3).clamp(0.0, 15.0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorPrimary = Theme.of(context).colorScheme.primary;
    final colorAccent = Theme.of(context).colorScheme.secondary;
    final colorText = Theme.of(context).colorScheme.onBackground;
    final labelColor = Color(0xFF64B5F6); // azul claro
    return Scaffold(
      appBar: AppBar(
        title: const Text('Monitoreo'),
        backgroundColor: colorPrimary,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Ambiente', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: labelColor)),
            const SizedBox(height: 8),
            _bigCard(icon: Icons.thermostat, label: 'Temperatura ambiente', value: '${tempAmb.toStringAsFixed(1)} °C', color: colorAccent, textColor: Colors.white),
            _bigCard(icon: Icons.water, label: 'Humedad relativa ambiente', value: '${humRelAmb.toStringAsFixed(1)} %', color: colorAccent, textColor: Colors.white),
            _bigCard(icon: Icons.grain, label: 'Humedad absoluta ambiente', value: '${humAbsAmb.toStringAsFixed(1)} g/m³', color: colorAccent, textColor: Colors.white),
            _bigCard(icon: Icons.blur_on, label: 'Presión atmosférica', value: '${presionAmb.toStringAsFixed(1)} hPa', color: colorAccent, textColor: Colors.white),
            const SizedBox(height: 16),
            Text('Agua', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: labelColor)),
            const SizedBox(height: 8),
            _bigCard(icon: Icons.water_drop, label: 'Nivel del tanque', value: '${(nivelTanque * 100).toStringAsFixed(0)} %', color: colorAccent, textColor: Colors.white),
            _bigCard(icon: Icons.thermostat, label: 'Temp. evaporador', value: '${tempEvap.toStringAsFixed(1)} °C', color: colorAccent, textColor: Colors.white),
            _bigCard(icon: Icons.thermostat, label: 'Temp. condensador', value: '${tempCond.toStringAsFixed(1)} °C', color: colorAccent, textColor: Colors.white),
            _bigCard(icon: Icons.water, label: 'Humedad relativa evaporador', value: '${humRelEvap.toStringAsFixed(1)} %', color: colorAccent, textColor: Colors.white),
            _bigCard(icon: Icons.water, label: 'Humedad relativa condensador', value: '${humRelCond.toStringAsFixed(1)} %', color: colorAccent, textColor: Colors.white),
            _bigCard(icon: Icons.thermostat, label: 'Punto de rocío evaporador', value: '${puntoRocioEvap.toStringAsFixed(1)} °C', color: colorAccent, textColor: Colors.white),
            const SizedBox(height: 16),
            Text('Eléctrico', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: labelColor)),
            const SizedBox(height: 8),
            _bigCard(icon: Icons.bolt, label: 'Voltaje', value: '${voltaje.toStringAsFixed(1)} V', color: colorAccent, textColor: Colors.white),
            _bigCard(icon: Icons.electric_bolt, label: 'Corriente', value: '${corriente.toStringAsFixed(2)} A', color: colorAccent, textColor: Colors.white),
            _bigCard(icon: Icons.flash_on, label: 'Potencia', value: '${potencia.toStringAsFixed(1)} W', color: colorAccent, textColor: Colors.white),
            _bigCard(icon: Icons.energy_savings_leaf, label: 'Energía consumida', value: '${energia.toStringAsFixed(2)} kWh', color: colorAccent, textColor: Colors.white),
          ],
        ),
      ),
    );
  }

  Widget _bigCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    required Color textColor,
  }) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(icon, color: color, size: 40),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
} 
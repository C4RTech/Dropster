import 'dart:async';
import 'package:flutter/material.dart';
import '../services/singleton_mqtt_service.dart';

class MonitorScreen extends StatefulWidget {
  const MonitorScreen({Key? key}) : super(key: key);

  @override
  State<MonitorScreen> createState() => _MonitorScreenState();
}

class _MonitorScreenState extends State<MonitorScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Acceso a datos MQTT reales
  ValueNotifier<Map<String, dynamic>> get globalNotifier =>
      SingletonMqttService().notifier;

  // Valores por defecto cuando no hay datos
  final Map<String, dynamic> _defaultValues = {
    'temperaturaAmbiente': 0.0,
    'presionAtmosferica': 0.0,
    'humedadRelativa': 0.0,
    'humedadAbsoluta': 0.0,
    'puntoRocio': 0.0,
    'aguaAlmacenada': 0.0,
    'temperaturaEvaporador': 0.0,
    'humedadEvaporador': 0.0,
    'temperaturaCondensador': 0.0,
    'humedadCondensador': 0.0,
    'voltaje': 0.0,
    'corriente': 0.0,
    'potencia': 0.0,
    'energia': 0.0,
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    // Escuchar cambios en los datos MQTT
    globalNotifier.addListener(_onDataChanged);
  }

  @override
  void dispose() {
    globalNotifier.removeListener(_onDataChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onDataChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  // Función helper para obtener valores seguros
  double _getValue(String key) {
    final data = globalNotifier.value;
    if (data.containsKey(key) && data[key] != null) {
      final value = data[key];
      if (value is num) {
        return value.toDouble();
      } else if (value is String) {
        return double.tryParse(value) ?? _defaultValues[key] ?? 0.0;
      }
    }
    return _defaultValues[key] ?? 0.0;
  }

  // Función helper para formatear valores
  String _formatValue(double value, String unit, {int decimals = 1}) {
    // Si el valor es 0 y no hay datos en el notifier, mostrar "--"
    if (value == 0.0 && globalNotifier.value.isEmpty) {
      return '--';
    }
    // Si el valor es 0 pero hay datos en el notifier, mostrar el valor
    if (value == 0.0 && globalNotifier.value.isNotEmpty) {
      return '${value.toStringAsFixed(decimals)} $unit';
    }
    return '${value.toStringAsFixed(decimals)} $unit';
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
            Text('Ambiente',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: labelColor)),
            const SizedBox(height: 8),
            _bigCard(
                icon: Icons.thermostat,
                label: 'Temperatura ambiente',
                value: _formatValue(_getValue('temperaturaAmbiente'), '°C'),
                color: colorAccent,
                textColor: Colors.white),
            _bigCard(
                icon: Icons.water,
                label: 'Humedad relativa ambiente',
                value: _formatValue(_getValue('humedadRelativa'), '%'),
                color: colorAccent,
                textColor: Colors.white),
            _bigCard(
                icon: Icons.grain,
                label: 'Humedad absoluta ambiente',
                value: _formatValue(_getValue('humedadAbsoluta'), 'g/m³'),
                color: colorAccent,
                textColor: Colors.white),
            _bigCard(
                icon: Icons.blur_on,
                label: 'Presión atmosférica',
                value: _formatValue(_getValue('presionAtmosferica'), 'hPa'),
                color: colorAccent,
                textColor: Colors.white),
            const SizedBox(height: 16),
            Text('Agua',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: labelColor)),
            const SizedBox(height: 8),
            _bigCard(
                icon: Icons.water_drop,
                label: 'Agua almacenada',
                value: _formatValue(_getValue('aguaAlmacenada'), 'L'),
                color: colorAccent,
                textColor: Colors.white),
            _bigCard(
                icon: Icons.thermostat,
                label: 'Temp. evaporador',
                value: _formatValue(_getValue('temperaturaEvaporador'), '°C'),
                color: colorAccent,
                textColor: Colors.white),
            _bigCard(
                icon: Icons.thermostat,
                label: 'Temp. condensador',
                value: _formatValue(_getValue('temperaturaCondensador'), '°C'),
                color: colorAccent,
                textColor: Colors.white),
            _bigCard(
                icon: Icons.water,
                label: 'Humedad relativa evaporador',
                value: _formatValue(_getValue('humedadEvaporador'), '%'),
                color: colorAccent,
                textColor: Colors.white),
            _bigCard(
                icon: Icons.water,
                label: 'Humedad relativa condensador',
                value: _formatValue(_getValue('humedadCondensador'), '%'),
                color: colorAccent,
                textColor: Colors.white),
            _bigCard(
                icon: Icons.thermostat,
                label: 'Punto de rocío',
                value: _formatValue(_getValue('puntoRocio'), '°C'),
                color: colorAccent,
                textColor: Colors.white),
            const SizedBox(height: 16),
            Text('Eléctrico',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: labelColor)),
            const SizedBox(height: 8),
            _bigCard(
                icon: Icons.bolt,
                label: 'Voltaje',
                value: _formatValue(_getValue('voltaje'), 'V'),
                color: colorAccent,
                textColor: Colors.white),
            _bigCard(
                icon: Icons.electric_bolt,
                label: 'Corriente',
                value: _formatValue(_getValue('corriente'), 'A', decimals: 2),
                color: colorAccent,
                textColor: Colors.white),
            _bigCard(
                icon: Icons.flash_on,
                label: 'Potencia',
                value: _formatValue(_getValue('potencia'), 'W'),
                color: colorAccent,
                textColor: Colors.white),
            _bigCard(
                icon: Icons.energy_savings_leaf,
                label: 'Energía',
                value: _formatValue(_getValue('energia'), 'kWh', decimals: 2),
                color: colorAccent,
                textColor: Colors.white),
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

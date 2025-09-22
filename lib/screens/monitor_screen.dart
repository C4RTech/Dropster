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

  // Valores por defecto eliminados - solo datos en tiempo real

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    // Escuchar cambios en los datos MQTT
    globalNotifier.addListener(_onDataChanged);

    // Procesar datos iniciales inmediatamente
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _onDataChanged();
    });
  }

  @override
  void dispose() {
    globalNotifier.removeListener(_onDataChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onDataChanged() {
    if (mounted) {
      final data = globalNotifier.value;
      print(
          '[MONITOR DEBUG] Datos actualizados en MonitorScreen: ${data.keys}');

      // Log específico para valores eléctricos con detalle
      if (data.containsKey('voltaje')) {
        print('[MONITOR ELECTRICO DEBUG] ⚡ Voltaje: ${data['voltaje']}V');
      }
      if (data.containsKey('corriente')) {
        print('[MONITOR ELECTRICO DEBUG] ⚡ Corriente: ${data['corriente']}A');
      }
      if (data.containsKey('potencia')) {
        print('[MONITOR ELECTRICO DEBUG] ⚡ Potencia: ${data['potencia']}W');
      }
      if (data.containsKey('energia')) {
        print('[MONITOR ELECTRICO DEBUG] ⚡ Energía: ${data['energia']}Wh');
      }

      // === ACTUALIZACIÓN INMEDIATA DE UI ===
      // Forzar rebuild inmediato para valores eléctricos
      print('[MONITOR DEBUG] 🔄 Forzando actualización inmediata de UI...');
      setState(() {});

      // Log de confirmación de actualización
      print(
          '[MONITOR DEBUG] ✅ UI actualizada - Valores eléctricos sincronizados');
    }
  }

  // Función helper para obtener valores seguros - SOLO DATOS REALES
  double _getValue(String key) {
    final data = globalNotifier.value;

    // === PRIORIDAD PARA VALORES ELÉCTRICOS ===
    // Los valores eléctricos necesitan actualización inmediata
    final electricalKeys = ['voltaje', 'corriente', 'potencia', 'energia'];
    final isElectrical = electricalKeys.contains(key);

    // Solo procesar si hay datos reales del MQTT
    if (data.isNotEmpty &&
        data.containsKey('source') &&
        data['source'] == 'MQTT') {
      if (data.containsKey(key) && data[key] != null) {
        final value = data[key];
        if (value is num) {
          final doubleValue = value.toDouble();
          // Log detallado para valores eléctricos
          if (isElectrical) {
            print(
                '[MONITOR ${key.toUpperCase()} DEBUG] ⚡ ${key}: ${doubleValue} (tipo: ${value.runtimeType}) - TIEMPO REAL');
          }
          return doubleValue;
        } else if (value is String) {
          final parsed = double.tryParse(value);
          if (parsed != null) {
            if (isElectrical) {
              print(
                  '[MONITOR ${key.toUpperCase()} DEBUG] ⚡ ${key} como string: $value -> $parsed - TIEMPO REAL');
            }
            return parsed;
          }
        }
      }
    }

    // Si no hay datos reales, mostrar 0.0 (no valores por defecto)
    if (isElectrical) {
      print(
          '[MONITOR ${key.toUpperCase()} DEBUG] ⚡ ${key} NO hay datos reales, mostrando 0.0');
    }
    return 0.0;
  }

  // Función helper para formatear valores - SOLO DATOS EN TIEMPO REAL
  String _formatValue(double value, String unit, {int decimals = 2}) {
    final data = globalNotifier.value;

    // Si no hay datos reales del MQTT, mostrar "--"
    if (data.isEmpty ||
        !data.containsKey('source') ||
        data['source'] != 'MQTT') {
      return '--';
    }

    // Para energía, usar más decimales si el valor es muy pequeño
    int actualDecimals = decimals;
    if (unit == 'Wh' && value < 1.0 && value > 0) {
      actualDecimals =
          3; // Mostrar 3 decimales para valores pequeños de energía
      print(
          '[MONITOR ENERGIA] Valor pequeño detectado: ${value}Wh, usando ${actualDecimals} decimales');
    }

    print('[MONITOR TIEMPO REAL] ${unit}: ${value}');
    return '${value.toStringAsFixed(actualDecimals)} $unit';
  }

  @override
  Widget build(BuildContext context) {
    final colorPrimary = Theme.of(context).colorScheme.primary;
    final colorAccent = Theme.of(context).colorScheme.secondary;
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
                label: 'Temp. Compresor',
                value: _formatValue(_getValue('temperaturaCompresor'), '°C'),
                color: colorAccent,
                textColor: Colors.white),
            _bigCard(
                icon: Icons.water,
                label: 'Humedad relativa evaporador',
                value: _formatValue(_getValue('humedadEvaporador'), '%'),
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
                value: _formatValue(_getValue('energia'), 'Wh', decimals: 2),
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

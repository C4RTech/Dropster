import 'package:flutter/material.dart';
import 'settings_data_manager.dart';

/// Widget para la configuración de conectividad MQTT
class SettingsConnectivityCard extends StatefulWidget {
  final SettingsDataManager dataManager;
  final Color colorPrimary;
  final Color colorAccent;
  final Color colorText;

  const SettingsConnectivityCard({
    Key? key,
    required this.dataManager,
    required this.colorPrimary,
    required this.colorAccent,
    required this.colorText,
  }) : super(key: key);

  @override
  State<SettingsConnectivityCard> createState() =>
      _SettingsConnectivityCardState();
}

class _SettingsConnectivityCardState extends State<SettingsConnectivityCard> {
  late TextEditingController mqttBrokerController;
  late TextEditingController mqttPortController;

  @override
  void initState() {
    super.initState();
    mqttBrokerController =
        TextEditingController(text: widget.dataManager.mqttBroker);
    mqttPortController =
        TextEditingController(text: widget.dataManager.mqttPort.toString());
  }

  @override
  void dispose() {
    mqttBrokerController.dispose();
    mqttPortController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            SwitchListTile(
              title: const Text('Conexión automática'),
              subtitle: const Text('Conecta automáticamente al iniciar la app'),
              value: widget.dataManager.autoConnect,
              onChanged: (value) {
                setState(() {
                  widget.dataManager.updateSetting('autoConnect', value);
                });
              },
              activeColor: widget.colorAccent,
            ),
            const Divider(),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Broker MQTT',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.wifi),
              ),
              onChanged: (value) {
                widget.dataManager.updateSetting('mqttBroker', value);
              },
              controller: mqttBrokerController,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: 'Puerto',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.numbers),
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (value) {
                      final port = int.tryParse(value) ?? 1883;
                      widget.dataManager.updateSetting('mqttPort', port);
                    },
                    controller: mqttPortController,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

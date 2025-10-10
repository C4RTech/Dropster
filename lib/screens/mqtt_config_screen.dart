import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/mqtt_config_service.dart';

class MqttConfigScreen extends StatefulWidget {
  const MqttConfigScreen({Key? key}) : super(key: key);

  @override
  State<MqttConfigScreen> createState() => _MqttConfigScreenState();
}

class _MqttConfigScreenState extends State<MqttConfigScreen> {
  final _formKey = GlobalKey<FormState>();
  final _brokerController = TextEditingController();
  final _portController = TextEditingController();
  final _topicController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _keepAliveController = TextEditingController();

  bool _isLoading = false;
  bool _isConnected = false;
  bool _cleanSession = true;
  bool _showPassword = false;
  Map<String, dynamic> _currentConfig = {};
  String _connectionStatus = 'Desconectado';

  @override
  void initState() {
    super.initState();
    _loadCurrentConfig();
  }

  @override
  void dispose() {
    _brokerController.dispose();
    _portController.dispose();
    _topicController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _keepAliveController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentConfig() async {
    setState(() => _isLoading = true);
    
    try {
      _currentConfig = await MqttConfigService.getCurrentConfig();
      final connectionInfo = await MqttConfigService.getConnectionInfo();
      
      _brokerController.text = _currentConfig['broker'] ?? '';
      _portController.text = _currentConfig['port']?.toString() ?? '1883';
      _topicController.text = _currentConfig['topic'] ?? '';
      _usernameController.text = _currentConfig['username'] ?? '';
      _passwordController.text = _currentConfig['password'] ?? '';
      _keepAliveController.text = _currentConfig['keepAlive']?.toString() ?? '60';
      _cleanSession = _currentConfig['cleanSession'] ?? true;
      _isConnected = connectionInfo['isConnected'] ?? false;
      _connectionStatus = connectionInfo['connectionStatus'] ?? 'Desconectado';
    } catch (e) {
      _showErrorSnackBar('Error cargando configuración: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveConfig() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final newConfig = {
        'broker': _brokerController.text.trim(),
        'port': int.parse(_portController.text),
        'topic': _topicController.text.trim(),
        'username': _usernameController.text.trim(),
        'password': _passwordController.text.trim(),
        'keepAlive': int.parse(_keepAliveController.text),
        'cleanSession': _cleanSession,
      };

      final hasChanged = await MqttConfigService.hasConfigChanged(newConfig);
      
      if (hasChanged) {
        final success = await MqttConfigService.updateConfigAndReconnect(newConfig);
        if (success) {
          _showSuccessSnackBar('Configuración MQTT actualizada exitosamente');
          await _loadCurrentConfig(); // Recargar para actualizar estado
        } else {
          _showErrorSnackBar('Error actualizando configuración MQTT');
        }
      } else {
        _showInfoSnackBar('No hay cambios en la configuración');
      }
    } catch (e) {
      _showErrorSnackBar('Error guardando configuración: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _testConnection() async {
    setState(() => _isLoading = true);

    try {
      final success = await MqttConfigService.testConnection();
      if (success) {
        _showSuccessSnackBar('Conexión MQTT exitosa');
        await _loadCurrentConfig(); // Actualizar estado
      } else {
        _showErrorSnackBar('Error conectando al broker MQTT');
      }
    } catch (e) {
      _showErrorSnackBar('Error probando conexión: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }


  void _selectRecommendedBroker(Map<String, dynamic> broker) {
    _brokerController.text = broker['broker'];
    _portController.text = broker['port'].toString();
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showInfoSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.blue,
        duration: const Duration(seconds: 2),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuración MQTT'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadCurrentConfig,
            tooltip: 'Recargar configuración',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Estado de conexión
                    _buildConnectionStatusCard(),
                    const SizedBox(height: 16),

                    // Brokers recomendados
                    _buildRecommendedBrokersCard(),
                    const SizedBox(height: 16),

                    // Configuración básica
                    _buildBasicConfigCard(),
                    const SizedBox(height: 16),

                    // Configuración avanzada
                    _buildAdvancedConfigCard(),
                    const SizedBox(height: 16),

                    // Botones de acción
                    _buildActionButtons(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildConnectionStatusCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _isConnected ? Icons.wifi : Icons.wifi_off,
                  color: _isConnected ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 8),
                Text(
                  'Estado de Conexión',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _connectionStatus,
              style: TextStyle(
                color: _isConnected ? Colors.green : Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (_currentConfig.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Broker: ${_currentConfig['broker']}:${_currentConfig['port']}'),
              Text('Tópico: ${_currentConfig['topic']}'),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRecommendedBrokersCard() {
    final brokers = MqttConfigService.getRecommendedBrokers();
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Brokers Recomendados',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            ...brokers.map((broker) => ListTile(
              title: Text(broker['name']),
              subtitle: Text('${broker['broker']}:${broker['port']} - ${broker['description']}'),
              trailing: const Icon(Icons.arrow_forward_ios),
              onTap: () => _selectRecommendedBroker(broker),
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildBasicConfigCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Configuración Básica',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _brokerController,
              decoration: const InputDecoration(
                labelText: 'Broker MQTT',
                hintText: 'test.mosquitto.org',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'El broker es requerido';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _portController,
              decoration: const InputDecoration(
                labelText: 'Puerto',
                hintText: '1883',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'El puerto es requerido';
                }
                final port = int.tryParse(value);
                if (port == null || port < 1 || port > 65535) {
                  return 'Puerto inválido (1-65535)';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _topicController,
              decoration: const InputDecoration(
                labelText: 'Tópico',
                hintText: 'dropster/data',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'El tópico es requerido';
                }
                return null;
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdvancedConfigCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Configuración Avanzada',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _usernameController,
              decoration: const InputDecoration(
                labelText: 'Usuario (opcional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _passwordController,
              decoration: InputDecoration(
                labelText: 'Contraseña (opcional)',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_showPassword ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _showPassword = !_showPassword),
                ),
              ),
              obscureText: !_showPassword,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _keepAliveController,
              decoration: const InputDecoration(
                labelText: 'Keep Alive (segundos)',
                hintText: '60',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Keep alive es requerido';
                }
                final keepAlive = int.tryParse(value);
                if (keepAlive == null || keepAlive < 10 || keepAlive > 300) {
                  return 'Keep alive inválido (10-300)';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Sesión Limpia'),
              subtitle: const Text('Iniciar con sesión limpia'),
              value: _cleanSession,
              onChanged: (value) => setState(() => _cleanSession = value),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _isLoading ? null : _testConnection,
            icon: const Icon(Icons.wifi_find),
            label: const Text('Probar Conexión'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _isLoading ? null : _saveConfig,
            icon: const Icon(Icons.save),
            label: const Text('Guardar'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}

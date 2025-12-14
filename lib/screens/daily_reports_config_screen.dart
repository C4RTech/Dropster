import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import '../services/enhanced_daily_report_service_refactored.dart';

class DailyReportsConfigScreen extends StatefulWidget {
  const DailyReportsConfigScreen({super.key});

  @override
  State<DailyReportsConfigScreen> createState() =>
      _DailyReportsConfigScreenState();
}

class _DailyReportsConfigScreenState extends State<DailyReportsConfigScreen> {
  bool _isLoading = false;
  bool _dailyReportEnabled = false;
  TimeOfDay _reportTime = const TimeOfDay(hour: 20, minute: 0);
  Map<String, dynamic> _serviceStatus = {};
  List<Map> _reportHistory = [];

  @override
  void initState() {
    super.initState();
    _loadConfiguration();
  }

  Future<void> _loadConfiguration() async {
    setState(() => _isLoading = true);

    try {
      final settingsBox = await Hive.openBox('settings');
      _dailyReportEnabled =
          settingsBox.get('dailyReportEnabled', defaultValue: false);
      final hour = settingsBox.get('dailyReportHour', defaultValue: 20);
      final minute = settingsBox.get('dailyReportMinute', defaultValue: 0);
      _reportTime = TimeOfDay(hour: hour, minute: minute);

      _serviceStatus =
          await EnhancedDailyReportServiceRefactored().getServiceStatus();
      _reportHistory =
          await EnhancedDailyReportServiceRefactored().getReportHistory();
    } catch (e) {
      _showErrorSnackBar('Error cargando configuración: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveConfiguration() async {
    setState(() => _isLoading = true);

    try {
      final settingsBox = await Hive.openBox('settings');
      await settingsBox.put('dailyReportEnabled', _dailyReportEnabled);
      await settingsBox.put('dailyReportHour', _reportTime.hour);
      await settingsBox.put('dailyReportMinute', _reportTime.minute);

      // Programar reporte diario
      await EnhancedDailyReportServiceRefactored()
          .scheduleDailyReport(_reportTime, _dailyReportEnabled);

      // Recargar estado
      await _loadConfiguration();

      _showSuccessSnackBar(_dailyReportEnabled
          ? 'Reporte diario programado para las ${_reportTime.format(context)}'
          : 'Reporte diario deshabilitado');
    } catch (e) {
      _showErrorSnackBar('Error guardando configuración: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _selectTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _reportTime,
    );

    if (picked != null && picked != _reportTime) {
      setState(() => _reportTime = picked);
    }
  }

  Future<void> _testReport() async {
    setState(() => _isLoading = true);

    try {
      await EnhancedDailyReportServiceRefactored().generateCurrentDayReport();
      _showSuccessSnackBar('Reporte de prueba enviado');
    } catch (e) {
      _showErrorSnackBar('Error enviando reporte de prueba: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _clearHistory() async {
    final confirmed = await _showConfirmDialog(
      'Limpiar historial',
      '¿Estás seguro de que quieres borrar todo el historial de reportes? Esta acción no se puede deshacer.',
    );

    if (confirmed) {
      setState(() => _isLoading = true);

      try {
        await EnhancedDailyReportServiceRefactored().clearReportHistory();
        await _loadConfiguration();
        _showSuccessSnackBar('Historial de reportes borrado');
      } catch (e) {
        _showErrorSnackBar('Error borrando historial: $e');
      } finally {
        setState(() => _isLoading = false);
      }
    }
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

  Future<bool> _showConfirmDialog(String title, String content) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reportes Diarios'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadConfiguration,
            tooltip: 'Recargar configuración',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Estado del servicio
                  _buildServiceStatusCard(),
                  const SizedBox(height: 16),

                  // Configuración
                  _buildConfigurationCard(),
                  const SizedBox(height: 16),

                  // Acciones
                  _buildActionsCard(),
                  const SizedBox(height: 16),

                  // Historial
                  _buildHistoryCard(),
                ],
              ),
            ),
    );
  }

  Widget _buildServiceStatusCard() {
    final isEnabled = _serviceStatus['enabled'] ?? false;
    final nextReport = _serviceStatus['nextReport'];
    final reportTime = _serviceStatus['reportTime'] ?? '--:--';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isEnabled ? Icons.schedule : Icons.schedule_outlined,
                  color: isEnabled ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 8),
                Text(
                  'Estado del Servicio',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              isEnabled ? 'Habilitado' : 'Deshabilitado',
              style: TextStyle(
                color: isEnabled ? Colors.green : Colors.grey,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (isEnabled) ...[
              const SizedBox(height: 4),
              Text('Hora programada: $reportTime'),
              if (nextReport != null) ...[
                const SizedBox(height: 4),
                Text(
                    'Próximo reporte: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.fromMillisecondsSinceEpoch(nextReport))}'),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildConfigurationCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Configuración',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Reporte diario automático'),
              subtitle: const Text('Recibe un resumen diario del sistema'),
              value: _dailyReportEnabled,
              onChanged: (value) {
                setState(() => _dailyReportEnabled = value);
              },
            ),
            if (_dailyReportEnabled) ...[
              const SizedBox(height: 8),
              ListTile(
                title: const Text('Hora del reporte'),
                subtitle: Text(_reportTime.format(context)),
                trailing: const Icon(Icons.access_time),
                onTap: _selectTime,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActionsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Acciones',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _testReport,
                    icon: const Icon(Icons.send),
                    label: const Text('Probar Reporte'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _saveConfiguration,
                    icon: const Icon(Icons.save),
                    label: const Text('Guardar'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Historial de Reportes',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (_reportHistory.isNotEmpty)
                  TextButton(
                    onPressed: _clearHistory,
                    child: const Text('Limpiar'),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (_reportHistory.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32.0),
                  child: Text(
                    'No hay reportes en el historial',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _reportHistory.length,
                itemBuilder: (context, index) {
                  final report = _reportHistory[index];
                  final reportData = report['report'] as Map<String, dynamic>?;
                  final date =
                      DateTime.fromMillisecondsSinceEpoch(report['date']);

                  return ListTile(
                    leading: const Icon(Icons.assessment),
                    title: Text(
                        'Reporte - ${DateFormat('dd/MM/yyyy').format(date)}'),
                    subtitle: reportData != null
                        ? Text(
                            'Energía: ${reportData['energy']?.toStringAsFixed(1)} Wh | Agua: ${reportData['water']?.toStringAsFixed(1)} L')
                        : const Text('Datos no disponibles'),
                    trailing: const Icon(Icons.arrow_forward_ios),
                    onTap: () => _showReportDetails(report),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showReportDetails(Map report) {
    final reportData = report['report'] as Map<String, dynamic>?;
    final date = DateTime.fromMillisecondsSinceEpoch(report['date']);

    if (reportData == null) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Reporte - ${DateFormat('dd/MM/yyyy').format(date)}'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildReportDetailRow(
                  'Energía', '${reportData['energy']?.toStringAsFixed(1)} Wh'),
              _buildReportDetailRow(
                  'Agua', '${reportData['water']?.toStringAsFixed(1)} L'),
              _buildReportDetailRow('Eficiencia',
                  '${reportData['efficiency']?.toStringAsFixed(1)} Wh/L'),
              _buildReportDetailRow(
                  'Calificación', reportData['efficiencyRating'] ?? 'N/A'),
              _buildReportDetailRow(
                  'Estado', reportData['systemStatus'] ?? 'N/A'),
              if (reportData['voltage'] != null)
                _buildReportDetailRow('Voltaje',
                    '${reportData['voltage']?.toStringAsFixed(1)} V'),
              if (reportData['current'] != null)
                _buildReportDetailRow('Corriente',
                    '${reportData['current']?.toStringAsFixed(1)} A'),
              if (reportData['temperature'] != null)
                _buildReportDetailRow('Temperatura',
                    '${reportData['temperature']?.toStringAsFixed(1)} °C'),
              if (reportData['humidity'] != null)
                _buildReportDetailRow('Humedad',
                    '${reportData['humidity']?.toStringAsFixed(1)} %'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Widget _buildReportDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          Text(value),
        ],
      ),
    );
  }
}

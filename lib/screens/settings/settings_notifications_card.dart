import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/enhanced_daily_report_service_refactored.dart';
import 'settings_data_manager.dart';

/// Widget para la configuración de notificaciones y reportes diarios
class SettingsNotificationsCard extends StatefulWidget {
  final SettingsDataManager dataManager;
  final Color colorPrimary;
  final Color colorAccent;
  final Color colorText;

  const SettingsNotificationsCard({
    Key? key,
    required this.dataManager,
    required this.colorPrimary,
    required this.colorAccent,
    required this.colorText,
  }) : super(key: key);

  @override
  State<SettingsNotificationsCard> createState() =>
      _SettingsNotificationsCardState();
}

class _SettingsNotificationsCardState extends State<SettingsNotificationsCard> {
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
              title: const Text('Mostrar notificaciones'),
              subtitle: const Text('Recibe alertas de anomalías y eventos'),
              value: widget.dataManager.showNotifications,
              onChanged: (value) {
                setState(() {
                  widget.dataManager.updateSetting('showNotifications', value);
                });
              },
              activeColor: widget.colorAccent,
            ),
            const Divider(),
            SwitchListTile(
              title: const Text('Reporte diario automático'),
              subtitle: Text(
                  'Recibe resumen diario a las ${widget.dataManager.dailyReportTime.format(context)}'),
              value: widget.dataManager.dailyReportEnabled,
              onChanged: (value) {
                setState(() {
                  widget.dataManager.updateSetting('dailyReportEnabled', value);
                });
              },
              activeColor: widget.colorAccent,
            ),
            const Divider(),
            ListTile(
              leading: Icon(Icons.schedule, color: widget.colorAccent),
              title: const Text('Hora del reporte diario'),
              subtitle:
                  Text('${widget.dataManager.dailyReportTime.format(context)}'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: _showDailyReportTimeDialog,
            ),
            const Divider(),
            ListTile(
              leading: Icon(Icons.history, color: widget.colorAccent),
              title: const Text('Historial de reportes'),
              subtitle: const Text('Ver reportes diarios anteriores'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: _showReportHistoryDialog,
            ),
            const Divider(),
            ListTile(
              leading: Icon(Icons.today, color: widget.colorAccent),
              title: const Text('Reporte del día actual'),
              subtitle: const Text('Generar reporte con datos actuales'),
              trailing: const Icon(Icons.assessment, size: 16),
              onTap: () => _generateCurrentDayReport(context),
            ),
          ],
        ),
      ),
    );
  }

  void _showDailyReportTimeDialog() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: widget.dataManager.dailyReportTime,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
                  primary: Theme.of(context).colorScheme.primary,
                  onPrimary: Colors.white,
                  surface: Theme.of(context).dialogBackgroundColor,
                  onSurface: Colors.white,
                ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                backgroundColor: const Color(0xFF206877),
                foregroundColor: Colors.white,
                textStyle: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && picked != widget.dataManager.dailyReportTime) {
      setState(() {
        widget.dataManager.updateSetting('dailyReportTime', picked);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Hora del reporte diario actualizada a ${picked.format(context)}',
                style: TextStyle(color: Color(0xFF155263))),
            backgroundColor: Colors.white,
          ),
        );
      }
    }
  }

  void _showReportHistoryDialog() async {
    final reports =
        await EnhancedDailyReportServiceRefactored().getReportHistory();

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Historial de Reportes Diarios'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: reports.isEmpty
              ? const Center(
                  child: Text('No hay reportes disponibles'),
                )
              : ListView.builder(
                  itemCount: reports.length,
                  itemBuilder: (context, index) {
                    final report = reports[index];
                    final date =
                        DateTime.fromMillisecondsSinceEpoch(report['date']);
                    final energy = report['energy'] ?? 0.0;
                    final water = report['water'] ?? 0.0;
                    final efficiency = report['efficiency'] ?? 0.0;

                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      color: const Color(0xFF206877),
                      child: ListTile(
                        title: Text(
                          '${DateFormat('dd/MM/yyyy').format(date)}',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('⚡ Energía: ${energy.toStringAsFixed(2)} Wh',
                                style: const TextStyle(color: Colors.white)),
                            Text('💧 Agua: ${water.toStringAsFixed(2)} L',
                                style: const TextStyle(color: Colors.white)),
                            Text(
                                '⚡ Eficiencia: ${efficiency.toStringAsFixed(3)} Wh/L',
                                style: const TextStyle(color: Colors.white)),
                          ],
                        ),
                        trailing: Icon(
                          efficiency > 0 ? Icons.check_circle : Icons.warning,
                          color: efficiency > 0 ? Colors.green : Colors.orange,
                        ),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
            ),
            child: const Text('Cerrar', style: TextStyle(color: Colors.white)),
          ),
          if (reports.isNotEmpty)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _clearReportHistoryAndNotify();
              },
              style: TextButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Borrar Historial',
                  style: TextStyle(color: Colors.white)),
            ),
        ],
      ),
    );
  }

  void _generateCurrentDayReport(BuildContext context) async {
    try {
      await EnhancedDailyReportServiceRefactored().generateCurrentDayReport();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Reporte del día actual enviado',
              style: TextStyle(color: Color(0xFF155263))),
          backgroundColor: Colors.white,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error generando reporte: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _clearReportHistoryAndNotify() async {
    try {
      await EnhancedDailyReportServiceRefactored().clearReportHistory();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Historial de reportes borrado',
              style: TextStyle(color: Color(0xFF155263))),
          backgroundColor: Colors.white,
        ),
      );
    } catch (e) {
      debugPrint('Error borrando historial de reportes: $e');
    }
  }
}

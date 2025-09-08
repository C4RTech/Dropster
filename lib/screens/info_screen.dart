import 'package:flutter/material.dart';

class InfoScreen extends StatelessWidget {
  void _showHelpDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text("Acerca de Dropster App"),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "¿Qué es Dropster App?",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "Dropster es una aplicación móvil que permite el monitoreo y control en tiempo real del sistema AWG (Atmospheric Water Generator) Dropster. Esta tecnología genera agua para sistemas de riego en ambientes controlados a partir de la humedad del aire utilizando refrigeración y condensación.\n",
                  style: TextStyle(fontSize: 14),
                ),
                
                const SizedBox(height: 16),
                Text(
                  "Funcionalidades Principales:",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "🏠 Inicio: Monitoreo visual del nivel del tanque, temperatura, humedad y energía consumida\n"
                  "📊 Monitoreo: Datos detallados del sistema en tiempo real\n"
                  "🔗 Conectividad: Gestión de conexiones MQTT\n"
                  "📈 Gráficas: Visualización histórica y en tiempo real de variables de interés\n"
                  "🔔 Notificaciones: Alertas de anomalías y reportes diarios automáticos\n"
                  "⚙️ Configuración: Ajustes del sistema, notificaciones, configuracion de datos, configuracion de reportes diarios, conectividad y configuración del tanque\n"
                  "ℹ️ Información: Datos de la aplicación y ayuda\n",
                  style: TextStyle(fontSize: 14),
                ),
                
                const SizedBox(height: 16),
                Text(
                  "Características Técnicas:",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "• Monitoreo en tiempo real de variables de interés\n"
                  "• Reportes diarios automáticos con cálculo de agua generada y eficiencia del sistema\n"
                  "• Almacenamiento local de datos históricos\n"
                  "• Interfaz responsiva y adaptativa\n"
                  "• Notificaciones inteligentes para alerta de anomalías y reportes diarios\n",
                  style: TextStyle(fontSize: 14),
                ),
              ],
            ),
          ),
          actions: [
            Center(
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF206877),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 10),
                  elevation: 0,
                ),
                child: const Text(
                  "Cerrar",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorPrimary = Theme.of(context).colorScheme.primary;
    final colorAccent = Theme.of(context).colorScheme.secondary;
    final colorText = Theme.of(context).colorScheme.onBackground;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Información'),
        backgroundColor: colorPrimary,
        foregroundColor: Colors.white,
        centerTitle: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 32),
            // Imagen de logo Dropster con texto al inicio
            Image.asset(
              'lib/assets/images/Dropster_Lg.png',
              width: 520,
            ),
            const SizedBox(height: 32),
            // Información de la app
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Text(
                      "Dropster App",
                      style: TextStyle(
                        fontSize: 28, 
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      "Versión: 1.1.0",
                      style: TextStyle(fontSize: 18, color: colorText),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Creador: Carlos Guedez",
                      style: TextStyle(fontSize: 18, color: colorText),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      "Trabajo de grado para optar por el título de Ingeniería Electrónica",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16, color: colorText.withOpacity(0.8)),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Tutor: Dr. Gabriel Noriega",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16, color: colorText.withOpacity(0.8)),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Logos pequeños
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(
                  'lib/assets/images/logounexpo.png',
                  width: 80,
                  height: 80,
                ),
                const SizedBox(width: 16),
                Image.asset(
                  'lib/assets/images/logoie.png',
                  width: 80,
                  height: 80,
                ),
              ],
            ),
            const SizedBox(height: 32),
            // Botón de información de la app
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _showHelpDialog(context),
                icon: const Icon(Icons.info_outline),
                label: const Text("Información de la Aplicación"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: colorAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
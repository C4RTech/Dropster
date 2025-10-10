import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:dropster/screens/home_screen.dart';
import 'package:dropster/screens/connectivity_screen.dart';
import 'package:dropster/screens/graph_screen.dart';
import 'package:dropster/screens/notifications_screen.dart';
import 'package:dropster/screens/monitor_screen.dart';
import 'package:dropster/screens/settings_screen.dart';
import 'package:dropster/screens/info_screen.dart';
import 'package:path_provider/path_provider.dart';
import 'services/mqtt_hive.dart';
import 'services/singleton_mqtt_service.dart';
import 'services/notification_service.dart';
import 'services/app_lifecycle_service.dart';
import 'services/daily_report_service.dart';

void main() {
  runApp(const DropsterApp());
}

class DropsterApp extends StatelessWidget {
  const DropsterApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dropster',
      theme: ThemeData(
        colorScheme: ColorScheme.light(
          primary: Color(0xFF155263),
          secondary: Color(0xFF00CFC8),
          background: Color(0xFFE8F5E8),
          surface: Colors.white,
          onPrimary: Colors.white,
          onSecondary: Color(0xFF155263),
          onBackground: Color(0xFF155263),
          onSurface: Color(0xFF155263),
        ),
        scaffoldBackgroundColor: Color(0xFFE8F5E8),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF155263),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.dark(
          primary: Color(0xFF155263),
          secondary: Color(0xFF00CFC8),
          background: Color(0xFF0c2f39),
          surface: Color(0xFF1e758d),
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          onBackground: Colors.white,
          onSurface: Colors.white,
        ),
        scaffoldBackgroundColor: Color(0xFF0c2f39),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF155263),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      themeMode: ThemeMode.system,
      home: const LoaderScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class LoaderScreen extends StatefulWidget {
  const LoaderScreen({Key? key}) : super(key: key);

  @override
  State<LoaderScreen> createState() => _LoaderScreenState();
}

class _LoaderScreenState extends State<LoaderScreen>
    with SingleTickerProviderStateMixin {
  bool _initialized = false;
  String _loadingMessage = "Inicializando Dropster...";
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _initApp();
  }

  void _setupAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.elasticOut,
    ));

    _opacityAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeIn,
    ));

    _animationController.forward();
  }

  Future<void> _initApp() async {
    try {
      // Paso 1: Inicializar Flutter binding
      setState(() {
        _loadingMessage = "Preparando aplicación...";
      });
      WidgetsFlutterBinding.ensureInitialized();
      await Future.delayed(const Duration(milliseconds: 500));

      // Paso 2: Inicializar Hive
      setState(() {
        _loadingMessage = "Configurando base de datos...";
      });
      final dir = await getApplicationDocumentsDirectory();
      await Hive.initFlutter(dir.path);
      await MqttHiveService.initHive();
      await Future.delayed(const Duration(milliseconds: 500));

      // Paso 3: Inicializar servicio de notificaciones
      setState(() {
        _loadingMessage = "Configurando notificaciones...";
      });
      print('[APP INIT] Inicializando servicio de notificaciones...');
      try {
        await NotificationService().initialize();
        final hasPermission = await NotificationService().checkPermissions();
        if (!hasPermission) {
          await NotificationService().requestPermissions();
        }
        print('[APP INIT] Servicio de notificaciones inicializado');
      } catch (e) {
        print('[APP INIT] Error inicializando notificaciones: $e');
      }
      await Future.delayed(const Duration(milliseconds: 500));

      // Inicializar servicio de reportes diarios
      setState(() {
        _loadingMessage = "Configurando reportes diarios...";
      });
      print('[APP INIT] Inicializando servicio de reportes diarios...');
      try {
        await DailyReportService().initialize();
        // Cargar configuración de reportes diarios
        final settingsBox = await Hive.openBox('settings');
        final dailyReportEnabled = settingsBox.get('dailyReportEnabled', defaultValue: false);
        if (dailyReportEnabled) {
          final hour = settingsBox.get('dailyReportHour', defaultValue: 20);
          final minute = settingsBox.get('dailyReportMinute', defaultValue: 0);
          final reportTime = TimeOfDay(hour: hour, minute: minute);
          await DailyReportService().scheduleDailyReport(reportTime, true);
          print('[APP INIT] Reporte diario programado para ${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}');
        }
        print('[APP INIT] Servicio de reportes diarios inicializado');
      } catch (e) {
        print('[APP INIT] Error inicializando reportes diarios: $e');
      }
      await Future.delayed(const Duration(milliseconds: 500));

      // Paso 4: Finalización
      setState(() {
        _loadingMessage = "¡Listo para comenzar!";
      });
      await Future.delayed(const Duration(milliseconds: 800));

      print('[APP INIT] Inicialización básica completada');

      setState(() {
        _initialized = true;
      });
    } catch (e) {
      print('[APP INIT] Error durante inicialización: $e');
      setState(() {
        _loadingMessage = "Error de inicialización";
      });
      // En caso de error, esperar un poco y continuar
      await Future.delayed(const Duration(seconds: 2));
      setState(() {
        _initialized = true;
      });
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF155263), // Primary color
                Color(0xFF0c2f39), // Dark background
                Color(0xFF1e758d), // Surface color
              ],
              stops: [0.0, 0.6, 1.0],
            ),
          ),
          child: Center(
            child: AnimatedBuilder(
              animation: _animationController,
              builder: (context, child) {
                return Transform.scale(
                  scale: _scaleAnimation.value,
                  child: Opacity(
                    opacity: _opacityAnimation.value,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Logo/Icono de la app
                        Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Color(0xFF00CFC8), // Secondary color
                                Color(0xFF155263), // Primary color
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF00CFC8).withOpacity(0.3),
                                blurRadius: 20,
                                spreadRadius: 5,
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Image.asset(
                              'lib/assets/images/Dropster_simbolo.png',
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),

                        const SizedBox(height: 40),

                        // Título de la app
                        const Text(
                          "DROPSTER",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2,
                            shadows: [
                              Shadow(
                                color: Color(0xFF00CFC8),
                                blurRadius: 10,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 8),

                        // Subtítulo
                        Text(
                          "Sistema de Monitoreo Inteligente",
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: 16,
                            fontWeight: FontWeight.w300,
                          ),
                        ),

                        const SizedBox(height: 60),

                        // Indicador de carga personalizado
                        Container(
                          width: 200,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              backgroundColor: Colors.transparent,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                const Color(0xFF00CFC8).withOpacity(0.8),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 30),

                        // Mensaje de carga
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          child: Text(
                            _loadingMessage,
                            key: ValueKey<String>(_loadingMessage),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w400,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),

                        const SizedBox(height: 20),

                        // Indicador de progreso circular
                        SizedBox(
                          width: 40,
                          height: 40,
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(
                              const Color(0xFF00CFC8).withOpacity(0.8),
                            ),
                            strokeWidth: 3,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
    }

    // Cuando termina la carga, muestra la app real con transición suave
    return const MainScreen();
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({Key? key}) : super(key: key);

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  bool _mqttInitialized = false;

  final List<Widget> _pages = [
    HomeScreen(),
    MonitorScreen(),
    ConnectivityScreen(),
    GraphScreen(),
    NotificationsScreen(),
    SettingsScreen(),
    InfoScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _initializeApp();
    // Inicializar servicio de ciclo de vida
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppLifecycleService().initialize(context);
    });
  }

  Future<void> _initializeApp() async {
    if (!_mqttInitialized) {
      try {
        // Inicializar Hive primero
        WidgetsFlutterBinding.ensureInitialized();
        final dir = await getApplicationDocumentsDirectory();
        await Hive.initFlutter(dir.path);
        await MqttHiveService.initHive();
        print('[APP INIT] Hive inicializado correctamente');

        // Inicializar MQTT con configuración desde Hive
        print(
            '[APP INIT] Conectando a broker MQTT con configuración guardada...');
        await SingletonMqttService().connect();
        print('[APP INIT] ✅ Conexión MQTT inicializada');

        // El monitoreo de conexión ya se inicia automáticamente en connect()
        print('[APP INIT] 🔄 Monitoreo de conexión MQTT activado');
      } catch (e) {
        print('[APP INIT] ❌ Error conectando a broker local: $e');
        print('[APP INIT] ⚠️ MQTT no disponible, app funcionará sin conexión');
      } finally {
        // Marcar como inicializado para que la app funcione
        setState(() {
          _mqttInitialized = true;
        });
      }
    }
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: _pages,
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF00897B),
          boxShadow: [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 2,
              offset: Offset(0, -2),
            ),
          ],
        ),
        child: BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          backgroundColor: const Color(0xFF00897B),
          currentIndex: _selectedIndex,
          onTap: _onItemTapped,
          selectedItemColor: Colors.white,
          unselectedItemColor: Color(0xFFC7B7B3),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.monitor),
              label: 'Monitoreo',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.wifi),
              label: 'Conectividad',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.show_chart),
              label: 'Gráficas',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.notifications),
              label: 'Notificaciones',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.settings),
              label: 'Configuración',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.info),
              label: 'Info',
            ),
          ],
        ),
      ),
    );
  }
}

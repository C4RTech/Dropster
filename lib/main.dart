import 'dart:async';
import 'package:flutter/material.dart';
import 'package:dropster/screens/home_screen.dart';
import 'package:dropster/screens/connectivity_screen.dart';
import 'package:dropster/screens/monitor_screen.dart';
import 'package:dropster/screens/graph_screen.dart';
import 'package:dropster/screens/settings_screen.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'services/singleton_mqtt_service.dart';
import 'services/notification_service.dart';
import 'services/app_lifecycle_service.dart';
import 'services/app_initialization_service.dart';
import 'services/error_handler_service.dart';

void main() async {
  // Configurar manejo global de errores
  FlutterError.onError = (FlutterErrorDetails details) {
    ErrorHandlerService()
        .logError('Flutter Error', details.exception, details.stack);
  };

  runZonedGuarded(() async {
    // Inicializar Flutter binding
    WidgetsFlutterBinding.ensureInitialized();

    // Inicializar Android Alarm Manager para reportes diarios
    await AndroidAlarmManager.initialize();

    runApp(const DropsterApp());
  }, (error, stack) {
    ErrorHandlerService().logError('Uncaught Error', error, stack);
  });
}

class DropsterApp extends StatelessWidget {
  const DropsterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dropster',
      theme: ThemeData(
        colorScheme: ColorScheme.light(
          primary: Color(0xFF155263),
          secondary: Color(0xFF00CFC8),
          surface: Colors.white,
          onPrimary: Colors.white,
          onSecondary: Color(0xFF155263),
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
          surface: Color(0xFF1e758d),
          onPrimary: Colors.white,
          onSecondary: Colors.white,
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
  const LoaderScreen({super.key});

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
      await AppInitializationService().initializeAll(
        onProgressUpdate: (message) {
          setState(() {
            _loadingMessage = message;
          });
        },
      );

      await Future.delayed(const Duration(milliseconds: 800));

      setState(() {
        _initialized = true;
      });
    } catch (e) {
      ErrorHandlerService().logError('App Initialization', e);
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
  const MainScreen({super.key});

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
    SettingsScreen(),
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
        // Usar el servicio de inicialización unificado
        await AppInitializationService().initializeBasic();
        await AppInitializationService().initializeMqtt();

        debugPrint('[APP INIT] 🔄 Monitoreo de conexión MQTT activado');
      } catch (e) {
        ErrorHandlerService().logError('MQTT Initialization', e);
        ErrorHandlerService().handleMqttError(context, e);
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
              label: 'Inicio',
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
              icon: Icon(Icons.settings),
              label: 'Ajustes',
            ),
          ],
        ),
      ),
    );
  }
}

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
import 'package:dropster/screens/dropster_home_screen.dart';

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
      home: const MainScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class LoaderScreen extends StatefulWidget {
  const LoaderScreen({Key? key}) : super(key: key);

  @override
  State<LoaderScreen> createState() => _LoaderScreenState();
}

class _LoaderScreenState extends State<LoaderScreen> {
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  Future<void> _initApp() async {
    WidgetsFlutterBinding.ensureInitialized();
    final dir = await getApplicationDocumentsDirectory();
    await Hive.initFlutter(dir.path);
    await MqttHiveService.initHive();
    // Simula un pequeño delay si quieres que se note el splash
    // await Future.delayed(Duration(seconds: 2));
    setState(() {
      _initialized = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return Scaffold(
        backgroundColor: const Color(0xFF1D347A),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 16),
              Text(
                "Cargando...",
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      );
    }
    // Cuando termina la carga, muestra la app real
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

  final List<Widget> _pages = [
    HomeScreen(),
    MonitorScreen(),
    ConnectivityScreen(),
    GraphScreen(),
    NotificationsScreen(),
    SettingsScreen(),
    InfoScreen(),
  ];

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
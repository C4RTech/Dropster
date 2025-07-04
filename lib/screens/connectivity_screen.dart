import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/mqtt_hive.dart';
import '../services/singleton_mqtt_service.dart';
import '../services/bluetooth_service.dart';

/// Estado global de Bluetooth y dispositivo conectado (persisten incluso si la pantalla cambia)
BluetoothDevice? globalConnectedDevice;
BluetoothConnectionState globalDeviceState =
    BluetoothConnectionState.disconnected;
final AppBluetoothService appBluetoothSingleton = AppBluetoothService();

const String ESP32_BLE_MAC =
    "08:D1:F9:E9:D9:D2"; // MAC address esperado del ESP32

enum ConnectivityMode {
  none,
  mqtt,
  bluetooth,
}

/// Pantalla de conectividad: permite conectar por MQTT o Bluetooth, muestra estado, y permite borrar datos.
class ConnectivityScreen extends StatefulWidget {
  const ConnectivityScreen({Key? key}) : super(key: key);

  @override
  State<ConnectivityScreen> createState() => _ConnectivityScreenState();
}

class _ConnectivityScreenState extends State<ConnectivityScreen>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  late final MqttHiveService mqttHiveService;

  bool isSavingEnabled = true;
  bool hiveReady = false;

  List<ScanResult> scanResults = [];
  bool isScanning = false;
  BluetoothDevice? connectedDevice;

  // Subscripciones a streams para manejar eventos de BLE y datos
  StreamSubscription<Map<String, dynamic>>? _debugSub;
  StreamSubscription<List<ScanResult>>? _scanResultsSub;
  StreamSubscription<BluetoothAdapterState>? _bluetoothStateSub;
  StreamSubscription<bool>? _isScanningSub;
  StreamSubscription<BluetoothConnectionState>? _deviceStateSub;
  Timer? _hiveCheckTimer;
  int _hiveDataCount = 0;

  /// Devuelve el modo de conectividad actual
  ConnectivityMode get _currentMode {
    if (SingletonMqttService().mqttConnected) return ConnectivityMode.mqtt;
    if (globalConnectedDevice != null) return ConnectivityMode.bluetooth;
    return ConnectivityMode.none;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    mqttHiveService = SingletonMqttService().mqttService;
    _openHiveAndInit();
    _startHiveMonitor();
    _setupBluetoothStateListener();
    _setupScanResultsListener();

    if (globalConnectedDevice != null) {
      connectedDevice = globalConnectedDevice;
      _listenDeviceState(connectedDevice!);
    }
  }

  /// Escucha cambios de ciclo de vida para reconectar BLE si la app vuelve a primer plano
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && globalConnectedDevice != null) {
      connectedDevice = globalConnectedDevice;
      _listenDeviceState(connectedDevice!);
      setState(() {});
    }
  }

  /// Monitorea la cantidad de datos guardados en Hive para actualizar la UI
  void _startHiveMonitor() {
    _hiveCheckTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (MqttHiveService.dataBox != null && MqttHiveService.dataBox!.isOpen) {
        final count = MqttHiveService.dataBox!.length;
        if (count != _hiveDataCount) {
          _hiveDataCount = count;
          setState(() {});
        }
      }
    });
  }

  /// Escucha el estado del Bluetooth del dispositivo
  void _setupBluetoothStateListener() {
    _bluetoothStateSub = FlutterBluePlus.adapterState.listen((state) {
      if (state != BluetoothAdapterState.on) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Activa Bluetooth para buscar dispositivos.')),
        );
      }
    });
  }

  /// Escucha resultados de escaneo y conecta automáticamente si encuentra el ESP32
  void _setupScanResultsListener() {
    _scanResultsSub = FlutterBluePlus.scanResults.listen((results) async {
      setState(() {
        scanResults = results;
      });

      ScanResult? espResult;
      try {
        espResult = results.firstWhere(
          (r) => r.device.remoteId.str.toUpperCase() == ESP32_BLE_MAC,
        );
      } catch (_) {
        espResult = null;
      }
      if (espResult != null && globalConnectedDevice == null) {
        await _connectToDevice(espResult.device);
      }
    });
    _isScanningSub = FlutterBluePlus.isScanning.listen((scanning) {
      setState(() => isScanning = scanning);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _debugSub?.cancel();
    _scanResultsSub?.cancel();
    _bluetoothStateSub?.cancel();
    _isScanningSub?.cancel();
    _deviceStateSub?.cancel();
    _hiveCheckTimer?.cancel();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  /// Inicializa Hive y obtiene configuración de guardado
  Future<void> _openHiveAndInit() async {
    await MqttHiveService.initHive();
    isSavingEnabled = MqttHiveService.isSavingEnabled();
    hiveReady = true;
    setState(() {});
  }

  /// Intenta conectar al broker MQTT
  Future<void> connectToBroker() async {
    if (SingletonMqttService().mqttConnected ||
        globalConnectedDevice != null ||
        isScanning) return;
    try {
      await SingletonMqttService().connect();
      setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al conectar: $e')),
        );
      }
    }
  }

  /// Desconecta del broker MQTT
  Future<void> disconnectFromBroker() async {
    await SingletonMqttService().disconnect();
    setState(() {});
  }

  /// Escucha el estado de conexión de un dispositivo BLE y actualiza estado global
  void _listenDeviceState(BluetoothDevice device) {
    _deviceStateSub?.cancel();
    _deviceStateSub = device.connectionState.listen((state) {
      setState(() {
        globalDeviceState = state;
        if (state == BluetoothConnectionState.connected) {
          connectedDevice = device;
          globalConnectedDevice = device;
        }
        if (state == BluetoothConnectionState.disconnected) {
          connectedDevice = null;
          globalConnectedDevice = null;
          mqttHiveService.disconnectBluetooth();
        }
      });
    });
  }

  /// Pide permisos de Bluetooth y ubicación antes de escanear
  Future<void> _startScanWithPermissions() async {
    final granted = await _requestBluetoothPermissions();
    if (!granted) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Permisos de Bluetooth/Ubicación denegados')),
      );
      return;
    }
    final state = await FlutterBluePlus.adapterState.first;
    if (state != BluetoothAdapterState.on) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Activa Bluetooth para buscar dispositivos.')),
      );
      return;
    }
    await _startScan();
  }

  /// Solicita permisos necesarios para BLE
  Future<bool> _requestBluetoothPermissions() async {
    final statuses = await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetoothAdvertise,
      Permission.locationWhenInUse,
    ].request();

    bool allGranted = statuses.values.every((status) => status.isGranted);
    return allGranted;
  }

  /// Inicia escaneo de dispositivos BLE
  Future<void> _startScan() async {
    if (isScanning) return;
    setState(() {
      isScanning = true;
      scanResults.clear();
    });
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 8));
  }

  /// Intenta conectar al dispositivo BLE (solo ESP32 esperado)
  Future<void> _connectToDevice(BluetoothDevice device) async {
    if (globalConnectedDevice != null || SingletonMqttService().mqttConnected)
      return;
    if (device.remoteId.str.toUpperCase() != ESP32_BLE_MAC) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Este no es el ESP32 esperado.")),
      );
      return;
    }
    try {
      await FlutterBluePlus.stopScan();
      await appBluetoothSingleton.connectAndPoll(device);
      setState(() {
        connectedDevice = device;
        globalConnectedDevice = device;
        globalDeviceState = BluetoothConnectionState.connected;
        isScanning = false;
      });
      _listenDeviceState(device);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Conectado a ${device.remoteId.str}")),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error al conectar: $e")),
      );
    }
  }

  /// Desconecta el dispositivo BLE y limpia estado global/local
  Future<void> _disconnectDevice() async {
    await appBluetoothSingleton.disconnect();
    setState(() {
      connectedDevice = null;
      globalConnectedDevice = null;
      globalDeviceState = BluetoothConnectionState.disconnected;
      scanResults.clear();
      isScanning = false;
    });
  }

  /// Activa o desactiva el guardado de datos en Hive
  void toggleSaving(bool value) {
    MqttHiveService.toggleSaving(value);
    setState(() => isSavingEnabled = value);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          value
              ? 'Los datos se están guardando.'
              : 'Guardado de datos deshabilitado.',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: value ? AppColors.green : AppColors.red,
        duration: Duration(seconds: 2),
      ),
    );
  }

  /// Borra todos los datos con confirmación del usuario
  void _showClearDataDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Borrar datos'),
        content: const Text('¿Estás seguro de que quieres borrar todos los datos históricos? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          Builder(
            builder: (dialogContext) {
              final colorPrimary = Theme.of(dialogContext).colorScheme.primary;
              return ElevatedButton(
                onPressed: () async {
                  Navigator.pop(context);
                  await MqttHiveService.clearAllData();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Datos borrados correctamente', style: TextStyle(color: Color(0xFF155263))),
                      backgroundColor: Colors.white,
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(backgroundColor: colorPrimary),
                child: const Text('Borrar', style: TextStyle(color: Colors.white)),
              );
            },
          ),
        ],
      ),
    );
  }

  /// Card con UI para manejar conexión y escaneo Bluetooth
  Widget buildBluetoothCard() {
    final device = globalConnectedDevice;
    final isEsp32 =
        device != null && (device.remoteId.str.toUpperCase() == ESP32_BLE_MAC);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 10),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (device == null) ...[
              Center(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.bluetooth,
                      color: Colors.white, size: 28),
                  label: const Text(
                    "Buscar dispositivos Bluetooth",
                    textAlign: TextAlign.center,
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    alignment: Alignment.center,
                    minimumSize: Size(double.infinity, 50),
                    textStyle: const TextStyle(fontSize: 16),
                  ),
                  onPressed: isScanning ? null : _startScanWithPermissions,
                ),
              ),
              if (isScanning)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12.0),
                  child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator()),
                ),
              if (scanResults.isNotEmpty)
                Column(
                  children: [
                    const SizedBox(height: 20),
                    const Text("Dispositivos encontrados:",
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: scanResults.length,
                      itemBuilder: (context, i) {
                        final r = scanResults[i];
                        final dev = r.device;
                        final isTarget =
                            dev.remoteId.str.toUpperCase() == ESP32_BLE_MAC;
                        final displayName = isTarget
                            ? "ESP32"
                            : (dev.platformName.isNotEmpty
                                ? dev.platformName
                                : "(sin nombre)");
                        return Card(
                          color: isTarget ? Colors.blue[50] : null,
                          child: ListTile(
                            leading: Icon(Icons.bluetooth,
                                color: isTarget ? Colors.blue : Colors.black54),
                            title: Text(displayName),
                            subtitle: Text(dev.remoteId.str),
                            trailing: isTarget
                                ? const Text(
                                    "Conexión automática...",
                                    style: TextStyle(
                                        color: Colors.blue,
                                        fontWeight: FontWeight.bold),
                                  )
                                : null,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              if (scanResults.isEmpty && isScanning)
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text("Buscando dispositivos...",
                      style: TextStyle(color: Colors.grey)),
                ),
            ],
            if (device != null) ...[
              ListTile(
                leading: Icon(Icons.bluetooth_connected, color: Colors.green),
                title: Row(
                  children: [
                    Icon(Icons.memory, color: Colors.blueGrey[800], size: 26),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        isEsp32
                            ? "ESP32"
                            : (device.platformName.isNotEmpty
                                ? device.platformName
                                : "(sin nombre)"),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 17,
                          color: isEsp32 ? Colors.indigo : Colors.black87,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                subtitle: Text(
                  "Dirección: ${device.remoteId.str}\n"
                  "Estado: ${globalDeviceState.name}",
                  style: TextStyle(
                    color: Colors.grey[700],
                  ),
                ),
                trailing: isEsp32
                    ? Container(
                        padding:
                            EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue, width: 1.2),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.verified, color: Colors.blue, size: 18),
                            SizedBox(width: 4),
                            Text("ESP32",
                                style: TextStyle(
                                  color: Colors.blue[900],
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                )),
                          ],
                        ),
                      )
                    : null,
              ),
              buildBackButton(),
            ],
          ],
        ),
      ),
    );
  }

  /// Card para mostrar estado de conexión MQTT y botón para desconectar
  Widget buildMQTTCard() {
    final mqttClientService = SingletonMqttService().mqttClientService;
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            ListTile(
              leading: Icon(Icons.cloud_done, color: AppColors.green),
              title: Text('Conectado al broker MQTT'),
              subtitle:
                  Text('${mqttClientService.broker}:${mqttClientService.port}'),
            ),
            SizedBox(height: 10),
            buildBackButton(),
          ],
        ),
      ),
    );
  }

  /// Selector principal para elegir entre conexión MQTT y Bluetooth
  Widget buildMainSelector() {
    return Column(
      children: [
        ElevatedButton.icon(
          icon: const Icon(Icons.wifi, color: Colors.white),
          label: const Text('Conectar al broker MQTT'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            minimumSize: Size(double.infinity, 50),
          ),
          onPressed: connectToBroker,
        ),
        const SizedBox(height: 20),
        ElevatedButton.icon(
          icon: const Icon(Icons.bluetooth, color: Colors.white, size: 28),
          label: const Text("Buscar dispositivos Bluetooth"),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
            alignment: Alignment.center,
            minimumSize: Size(double.infinity, 50),
            textStyle: const TextStyle(fontSize: 16),
          ),
          onPressed: isScanning ? null : _startScanWithPermissions,
        ),
      ],
    );
  }

  /// Botón para desconectar (de MQTT o BLE) y volver al selector principal
  Widget buildBackButton() {
    final isBluetooth = _currentMode == ConnectivityMode.bluetooth;
    final isMqtt = _currentMode == ConnectivityMode.mqtt;
    return ElevatedButton.icon(
      icon: Icon(Icons.arrow_back, color: Colors.white),
      label: Text("Desconectar y volver"),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.grey[700],
        foregroundColor: Colors.white,
        minimumSize: Size(double.infinity, 50),
      ),
      onPressed: () async {
        if (isMqtt) await disconnectFromBroker();
        if (isBluetooth) await _disconnectDevice();
        setState(() {});
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
        title: const Text('Conectividad'),
        backgroundColor: colorPrimary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() {}),
            tooltip: "Refrescar",
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Estado de conectividad
            Container(
              padding: const EdgeInsets.all(16),
              color: colorAccent.withOpacity(0.1),
              child: Row(
                children: [
                  Icon(
                    SingletonMqttService().mqttConnected ? Icons.wifi : Icons.wifi_off,
                    color: colorAccent,
                    size: 24,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      SingletonMqttService().mqttConnected ? 'Conectado por MQTT' : 'Sin conexión',
                      style: TextStyle(
                        color: colorText,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Botones de conexión MQTT
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.wifi, color: colorAccent, size: 24),
                        const SizedBox(width: 8),
                        Text(
                          'Conexión MQTT',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: colorText,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: SingletonMqttService().mqttConnected 
                              ? null 
                              : connectToBroker,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: colorAccent,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: Colors.grey,
                            ),
                            child: const Text('Conectar MQTT'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: SingletonMqttService().mqttConnected 
                              ? disconnectFromBroker 
                              : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: Colors.grey,
                            ),
                            child: const Text('Desconectar'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Configuración de datos
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.data_usage, color: colorAccent, size: 24),
                        const SizedBox(width: 8),
                        Text(
                          'Configuración de Datos',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: colorText,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      title: Text(
                        'Guardar datos automáticamente',
                        style: TextStyle(color: colorText),
                      ),
                      subtitle: Text(
                        'Almacena los datos recibidos en el dispositivo',
                        style: TextStyle(color: colorText.withOpacity(0.7)),
                      ),
                      value: isSavingEnabled,
                      onChanged: (value) {
                        setState(() {
                          isSavingEnabled = value;
                        });
                        MqttHiveService.toggleSaving(value);
                      },
                      activeColor: colorAccent,
                    ),
                    const Divider(),
                    ListTile(
                      leading: Icon(Icons.delete_sweep, color: colorAccent),
                      title: Text(
                        'Borrar todos los datos',
                        style: TextStyle(color: colorText),
                      ),
                      subtitle: Text(
                        'Elimina todos los datos históricos almacenados',
                        style: TextStyle(color: colorText.withOpacity(0.7)),
                      ),
                      onTap: _showClearDataDialog,
                    ),
                    if (hiveReady) ...[
                      const Divider(),
                      ListTile(
                        leading: Icon(Icons.storage, color: colorAccent),
                        title: Text(
                          'Datos almacenados',
                          style: TextStyle(color: colorText),
                        ),
                        subtitle: Text(
                          '$_hiveDataCount registros',
                          style: TextStyle(color: colorAccent, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Colores de la app (centralizados)
class AppColors {
  static const primary = Color(0xFF1D347A);
  static const green = Colors.green;
  static const red = Colors.red;
}

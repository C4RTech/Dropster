# Dropster AWG - Sistema de Control y Monitoreo

## Descripción

Dropster es una aplicación móvil desarrollada en Flutter para el control y monitoreo de un sistema AWG (Atmospheric Water Generator). La aplicación permite recibir datos en tiempo real tanto por Bluetooth (BLE) como por MQTT, visualizar gráficas históricas, detectar anomalías y gestionar notificaciones.

## Características Principales

### 🔌 **Conectividad Dual**
- **Bluetooth (BLE)**: Conexión directa con ESP32 para datos en tiempo real
- **MQTT**: Comunicación por WiFi/internet con broker MQTT
- Reconexión automática y gestión de estado de conexión

### 📊 **Visualización de Datos**
- **Pantalla Principal**: Resumen rápido de datos eléctricos y estado del sistema
- **Gráficas Avanzadas**: Visualización histórica y tiempo real con múltiples variables
- **Monitoreo Detallado**: Datos organizados por categorías (Ambiente, Eléctrico, Agua)

### 🔔 **Sistema de Notificaciones**
- Detección automática de anomalías en voltaje, corriente y frecuencia
- Filtros avanzados por tipo, fase y rango de fechas
- Historial completo de eventos y alertas

### ⚙️ **Configuración Completa**
- Valores nominales personalizables
- Configuración de conectividad MQTT
- Gestión de almacenamiento de datos
- Ajustes de visualización de gráficas

## Pantallas Implementadas

### 1. **Pantalla Principal (HomeScreen)**
- **Ubicación**: `lib/screens/home_screen.dart`
- **Funcionalidad**: 
  - Visualización de datos eléctricos en tiempo real
  - Configuración de valores nominales
  - Detección automática de anomalías
  - Indicadores de estado de batería y fuente de datos

### 2. **Pantalla de Conectividad (ConnectivityScreen)**
- **Ubicación**: `lib/screens/connectivity_screen.dart`
- **Funcionalidad**:
  - Gestión de conexiones MQTT y Bluetooth
  - Escaneo automático de dispositivos BLE
  - Estado de conexión en tiempo real
  - Configuración de almacenamiento de datos

### 3. **Pantalla de Gráficas (GraphScreen)**
- **Ubicación**: `lib/screens/graph_screen.dart`
- **Funcionalidad**:
  - Gráficas de múltiples variables eléctricas
  - Modo tiempo real e histórico
  - Filtros por rango de fechas
  - Visualización en tabla y gráfica
  - Zoom y controles de visualización

### 4. **Pantalla de Notificaciones (NotificationsScreen)**
- **Ubicación**: `lib/screens/notifications_screen.dart`
- **Funcionalidad**:
  - Lista de anomalías detectadas
  - Filtros por tipo, fase y fecha
  - Detalles completos de cada evento
  - Gestión de notificaciones almacenadas

### 5. **Pantalla de Monitoreo (MonitorScreen)**
- **Ubicación**: `lib/screens/monitor_screen.dart`
- **Funcionalidad**:
  - Datos organizados por categorías (Ambiente, Eléctrico, Agua)
  - Visualización de variables específicas del sistema AWG
  - Interfaz con pestañas para mejor organización

### 6. **Pantalla de Configuración (SettingsScreen)**
- **Ubicación**: `lib/screens/settings_screen.dart`
- **Funcionalidad**:
  - Configuración de valores nominales
  - Ajustes de conectividad MQTT
  - Gestión de almacenamiento y notificaciones
  - Configuración de gráficas

### 7. **Pantalla de Información (InfoScreen)**
- **Ubicación**: `lib/screens/info_screen.dart`
- **Funcionalidad**:
  - Información sobre la aplicación
  - Guía de uso detallada
  - Créditos y versión

### 8. **Pantalla Principal Alternativa (DropsterHomeScreen)**
- **Ubicación**: `lib/screens/dropster_home_screen.dart`
- **Funcionalidad**:
  - Interfaz alternativa con enfoque en el sistema AWG
  - Simulación de datos del generador de agua
  - Control de encendido/apagado del sistema

## Servicios Implementados

### 🔧 **Servicios Principales**

1. **BluetoothService** (`lib/services/bluetooth_service.dart`)
   - Gestión de conexiones BLE con ESP32
   - Reconexión automática
   - Manejo de permisos y estados

2. **MqttHiveService** (`lib/services/mqtt_hive.dart`)
   - Integración MQTT con almacenamiento local
   - Parsing de datos CSV
   - Gestión de streams de datos

3. **SingletonMqttService** (`lib/services/singleton_mqtt_service.dart`)
   - Servicio global para datos en tiempo real
   - Notificaciones de cambios de estado

4. **MqttService** (`lib/services/mqtt_service.dart`)
   - Cliente MQTT básico
   - Conexión y suscripción a tópicos

### 🎨 **Widgets Personalizados**

1. **CircularCard** (`lib/widgets/circular_card.dart`)
   - Tarjetas circulares para visualización de datos
   - Versiones animadas y con estado
   - Personalización completa de colores y tamaños

## Configuración del Proyecto

### 📋 **Dependencias Principales**

```yaml
dependencies:
  flutter_blue_plus: ^1.4.0      # Bluetooth BLE
  mqtt_client: ^10.0.0           # Cliente MQTT
  hive_flutter: ^1.1.0           # Almacenamiento local
  fl_chart: ^0.63.0              # Gráficas
  provider: ^6.0.5               # Gestión de estado
  flutter_riverpod: ^2.0.0       # Estado avanzado
  permission_handler: ^10.4.0    # Permisos
  intl: ^0.18.1                  # Formateo de fechas
```

### 🔧 **Configuración Inicial**

1. **Instalar dependencias**:
   ```bash
   flutter pub get
   ```

2. **Configurar permisos** (Android):
   - Bluetooth
   - Ubicación (requerido para BLE)
   - Internet (para MQTT)

3. **Configurar MQTT**:
   - Broker: `broker.emqx.io` (por defecto)
   - Puerto: `1883`
   - Tópico: `dropster/data`

## Uso de la Aplicación

### 🚀 **Inicio Rápido**

1. **Conectar dispositivo**:
   - Ir a "Conectividad"
   - Seleccionar MQTT o Bluetooth
   - Configurar parámetros de conexión

2. **Configurar valores nominales**:
   - Ir a "Configuración"
   - Establecer voltaje y corriente nominales
   - Guardar configuración

3. **Monitorear datos**:
   - Ver datos en tiempo real en "Home"
   - Analizar tendencias en "Gráficas"
   - Revisar anomalías en "Notificaciones"

### 📱 **Navegación**

La aplicación utiliza navegación inferior con 6 secciones principales:
- **Home**: Datos principales y configuración rápida
- **Conectividad**: Gestión de conexiones
- **Gráficas**: Visualización histórica y tiempo real
- **Notificaciones**: Alertas y anomalías
- **Configuración**: Ajustes completos del sistema
- **Info**: Información y ayuda

## Características Técnicas

### 💾 **Almacenamiento Local**
- **Hive**: Base de datos NoSQL local
- **Boxes**: 
  - `energyData`: Datos históricos
  - `settings`: Configuraciones
  - `anomalies`: Notificaciones

### 🔄 **Gestión de Estado**
- **Provider/Riverpod**: Estado global
- **ValueNotifier**: Datos en tiempo real
- **Streams**: Actualizaciones automáticas

### 🎨 **UI/UX**
- **Material Design 3**: Interfaz moderna
- **Temas**: Claro y oscuro
- **Responsive**: Adaptable a diferentes tamaños
- **Animaciones**: Transiciones suaves

## Desarrollo y Contribución

### 🛠️ **Estructura del Proyecto**

```
lib/
├── main.dart                 # Punto de entrada
├── screens/                  # Pantallas de la aplicación
│   ├── home_screen.dart
│   ├── connectivity_screen.dart
│   ├── graph_screen.dart
│   ├── notifications_screen.dart
│   ├── monitor_screen.dart
│   ├── settings_screen.dart
│   ├── info_screen.dart
│   └── dropster_home_screen.dart
├── services/                 # Servicios y lógica de negocio
│   ├── bluetooth_service.dart
│   ├── mqtt_service.dart
│   ├── mqtt_hive.dart
│   └── singleton_mqtt_service.dart
├── widgets/                  # Widgets personalizados
│   └── circular_card.dart
└── assets/                   # Recursos estáticos
    └── images/
```

### 📝 **Próximas Mejoras**

- [ ] Notificaciones push
- [ ] Exportación de datos
- [ ] Dashboard personalizable
- [ ] Integración con APIs externas
- [ ] Modo offline mejorado
- [ ] Tests unitarios y de integración

## Autor

**Carlos Guedez** - Estudiante de Ingeniería Electrónica
- Email: carlosguedez7323@gmail.com
- Tutor: Dr. Gabriel Noriega

## Licencia

Este proyecto es parte de un trabajo de grado para optar por el título de Ingeniería Electrónica.

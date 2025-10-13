# Dropster AWG - Sistema de Control y Monitoreo

[![Flutter](https://img.shields.io/badge/Flutter-3.6+-02569B?logo=flutter)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.6+-0175C2?logo=dart)](https://dart.dev)
[![Arduino IDE](https://img.shields.io/badge/Arduino%20IDE-2.0+-008080)](https://www.arduino.cc/en/software)
[![License](https://img.shields.io/badge/License-Academic-yellow)](LICENSE)
[![GitHub Release](https://img.shields.io/github/v/release/C4RTech/Dropster)](https://github.com/C4RTech/Dropster/releases)

## Descripción

Dropster es una aplicación móvil desarrollada en Flutter para el control y monitoreo de un sistema AWG (Atmospheric Water Generator). La aplicación permite recibir datos en tiempo real por MQTT, visualizar gráficas históricas, detectar anomalías y gestionar notificaciones. Incluye funcionalidades avanzadas como notificaciones push locales, conectividad automática, y una arquitectura modular basada en features.

## Características Principales

### 🔌 **Conectividad Avanzada**
- **MQTT**: Comunicación por WiFi/internet con broker MQTT
- **Reconexión automática** y gestión inteligente de estado de conexión
- **Detección de conectividad** de red (WiFi/Móvil)
- **Servicio en segundo plano** para mantener conexiones activas

### 📊 **Visualización de Datos Completa**
- **Pantalla Principal**: Resumen rápido de variables y estado del sistema
- **Gráficas Avanzadas**: Visualización histórica y tiempo real con múltiples variables
- **Monitoreo Detallado**: Datos organizados por categorías (Ambiente, Eléctrico, Agua)
- **Reportes Diarios**: Generación automática de reportes de rendimiento

### 🔔 **Sistema de Notificaciones Inteligente**
- Detección automática de anomalías de bajo Voltaje, baja Humedad, alta Temperatura y Tanque de Agua lleno
- **Notificaciones Push Locales** con sonidos y vibración
- Filtros avanzados por tipo y rango de fechas
- Historial completo de eventos y alertas
- **Servicio de Notificaciones** dedicado para gestión eficiente

### ⚙️ **Configuración Completa**
- Valores nominales personalizables
- Configuración de conectividad MQTT
- Gestión de almacenamiento de datos con Hive
- Ajustes de visualización de gráficas
- **Gestión del Ciclo de Vida** de la aplicación

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
  - Gestión de conexiones MQTT
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

### 4. **Pantalla de Monitoreo (MonitorScreen)**
- **Ubicación**: `lib/screens/monitor_screen.dart`
- **Funcionalidad**:
  - Datos organizados por categorías (Ambiente, Eléctrico, Agua)
  - Visualización de variables específicas del sistema AWG
  - Interfaz con pestañas para mejor organización

### 5. **Pantalla de Configuración (SettingsScreen)**
- **Ubicación**: `lib/screens/settings_screen.dart`
- **Funcionalidad**:
  - Configuración de valores nominales
  - Ajustes de conectividad MQTT
  - Gestión de almacenamiento y notificaciones
  - Configuración de gráficas

### 6. **Pantalla de Información (InfoScreen)**
- **Ubicación**: `lib/screens/info_screen.dart`
- **Funcionalidad**:
  - Información sobre la aplicación
  - Guía de uso detallada
  - Créditos y versión

### 7. **Pantalla Principal Alternativa (DropsterHomeScreen)**
- **Ubicación**: `lib/screens/dropster_home_screen.dart`
- **Funcionalidad**:
  - Interfaz alternativa con enfoque en el sistema AWG
  - Simulación de datos del generador de agua
  - Control de encendido/apagado del sistema

## Servicios Implementados

### 🔧 **Servicios Principales**

1. **MqttHiveService** (`lib/services/mqtt_hive.dart`)
   - Integración MQTT con almacenamiento local
   - Parsing de datos CSV
   - Gestión de streams de datos

2. **SingletonMqttService** (`lib/services/singleton_mqtt_service.dart`)
   - Servicio global para datos en tiempo real
   - Notificaciones de cambios de estado

3. **MqttService** (`lib/services/mqtt_service.dart`)
   - Cliente MQTT básico
   - Conexión y suscripción a tópicos

4. **BackgroundMqttService** (`lib/services/background_mqtt_service.dart`)
   - Servicio MQTT en segundo plano
   - Mantiene conexiones activas cuando la app está en background
   - Gestión automática de reconexión

5. **NotificationService** (`lib/services/notification_service.dart`)
   - Gestión de notificaciones push locales
   - Configuración de canales de notificación
   - Manejo de permisos de notificación

6. **DailyReportService** (`lib/services/daily_report_service.dart`)
   - Generación automática de reportes diarios
   - Análisis de rendimiento del sistema
   - Exportación de datos históricos

7. **AppLifecycleService** (`lib/services/app_lifecycle_service.dart`)
   - Gestión del ciclo de vida de la aplicación
   - Control de estados (foreground/background)
   - Optimización de recursos según estado

### 🎨 **Widgets Personalizados**

1. **CircularCard** (`lib/widgets/circular_card.dart`)
   - Tarjetas circulares para visualización de datos
   - Versiones animadas y con estado
   - Personalización completa de colores y tamaños

2. **DropsterAnimatedSymbol** (`lib/widgets/dropster_animated_symbol.dart`)
   - Símbolo animado de gota de agua
   - Animaciones fluidas y personalizables
   - Integración con tema ecológico

3. **ProfessionalWaterDrop** (`lib/widgets/professional_water_drop.dart`)
   - Representación profesional de gota de agua
   - Efectos visuales avanzados
   - Diseño optimizado para interfaces modernas

## Configuración del Proyecto

### 🔧 **Desarrollo con Arduino IDE**

Dropster utiliza Arduino IDE para el desarrollo del firmware ESP32, manteniendo un enfoque simple y accesible para el desarrollo embebido.

#### **Estructura del Firmware**
```
hardware/
├── awg/                           # Firmware del controlador AWG
│   ├── mainAWG.ino                # Firmware principal AWG (Arduino IDE)
│   └── config.h                   # Configuración del sistema AWG
└── display/                       # Firmware de la pantalla táctil
    └── mainDisplay.ino            # Firmware de la pantalla (Arduino IDE)
```

#### **Instalación de Arduino IDE**
```bash
# Descargar e instalar Arduino IDE desde:
# https://www.arduino.cc/en/software

# Instalar las siguientes librerías vía Library Manager:
# - PubSubClient (MQTT)
# - ArduinoJson
# - WiFiManager
# - BME280
# - SHT31
# - PZEM004T
# - TFT_eSPI
# - LVGL
```

#### **Compilación del Firmware**

**Usando Arduino IDE:**
1. Abrir el archivo `.ino` correspondiente
2. Seleccionar la placa "ESP32 Dev Module"
3. Configurar el puerto COM correcto
4. Compilar y subir el firmware

**Configuración de librerías específicas:**
- Para TFT_eSPI: Configurar `User_Setup.h` según la pantalla ILI9341
- Para LVGL: Ajustar `lv_conf.h` para optimización de memoria

### 📋 **Dependencias Principales**

```yaml
dependencies:
  flutter:
    sdk: flutter

  # Comunicación y Conectividad
  mqtt_client: ^10.0.0                    # Cliente MQTT
  connectivity_plus: ^6.0.3               # Detección de conectividad

  # Almacenamiento y Persistencia
  hive: ^2.2.3                            # Base de datos NoSQL
  hive_flutter: ^1.1.0                    # Flutter integration
  shared_preferences: ^2.2.2              # Almacenamiento simple
  path_provider: ^2.1.0                   # Gestión de rutas

  # UI y Visualización
  fl_chart: ^0.63.0                       # Gráficas avanzadas
  flutter_svg: ^2.0.9                     # Soporte SVG
  cupertino_icons: ^1.0.8                 # Iconos iOS

  # Gestión de Estado
  provider: ^6.0.5                        # Provider pattern
  flutter_riverpod: ^2.0.0                # Riverpod state management
  get: ^4.7.2                             # GetX framework

  # Utilidades
  permission_handler: ^12.0.0             # Gestión de permisos
  intl: ^0.18.1                           # Formateo de fechas
  flutter_local_notifications: ^17.2.0    # Notificaciones locales

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^5.0.0                    # Linting
  flutter_launcher_icons: ^0.13.1         # Generación de iconos
```

### 🔧 **Configuración Inicial**

1. **Instalar dependencias**:
   ```bash
   flutter pub get
   ```

2. **Configurar permisos** (Android):
   - Internet (para MQTT)

3. **Configurar MQTT**:
   - Broker: `test.mosquitto.org` (por defecto)
   - Puerto: `1883`
   - Tópico: `dropster/data`

## Uso de la Aplicación

### 🚀 **Inicio Rápido**

1. **Conectar dispositivo**:
   - Ir a "Conectividad"
   - Seleccionar Conectar MQTT 
   - Configurar parámetros de conexión

2. **Monitorear datos**:
    - Ver datos en tiempo real en "Home"
    - Analizar tendencias en "Gráficas"
    - Revisar datos organizados en "Monitoreo"

### 📱 **Navegación**

La aplicación utiliza navegación inferior con 6 secciones principales:
- **Home**: Datos principales y configuración rápida
- **Monitoreo**: Datos organizados por categorías
- **Conectividad**: Gestión de conexiones
- **Gráficas**: Visualización histórica y tiempo real
- **Configuración**: Ajustes completos del sistema
- **Info**: Información y ayuda

## Características Técnicas

### 💾 **Almacenamiento Local**
- **Hive**: Base de datos NoSQL local
- **Boxes**: 
  - `Data`: Datos históricos
  - `settings`: Configuraciones
  - `anomalies`: Notificaciones

### 🔄 **Gestión de Estado**
- **Provider/Riverpod**: Estado global
- **ValueNotifier**: Datos en tiempo real
- **Streams**: Actualizaciones automáticas

### 🎨 **UI/UX**
- **Material Design 3**: Interfaz moderna
- **Temas**: Verde Agua Ecologico
- **Responsive**: Adaptable a diferentes tamaños
- **Animaciones**: Transiciones suaves

## Arquitectura del Proyecto

### 🏗️ **Arquitectura Basada en Features**

El proyecto utiliza una arquitectura modular organizada por features, siguiendo las mejores prácticas de desarrollo Flutter:

```
dropster/
├── lib/                               # Código fuente Flutter
│   ├── main.dart                      # Punto de entrada
│   ├── screens/                       # Pantallas principales
│   ├── services/                      # Servicios globales
│   ├── widgets/                       # Widgets reutilizables
│   └── assets/                        # Recursos estáticos
├── hardware/                          # Firmware ESP32 con Arduino IDE
│   ├── awg/                           # ESP32 para control AWG
│   │   ├── codigo_ESP32_AWG.ino       # Firmware principal
│   │   └── esp32_mqtt_config.h        # Configuración MQTT
│   └── display/                       # ESP32 para pantalla táctil
│       └── codigo_ESP32_PANTALLA.ino  # Firmware pantalla
├── docs/                              # Documentación adicional
│   └── mqtt_test_guide.md             # Guía de pruebas MQTT
├── android/, ios/, linux/, macos/, web/, windows/  # Builds Flutter
├── test/                              # Tests Flutter
├── CHANGELOG.md                       # Historial de cambios
├── README.md                          # Documentación principal
├── pubspec.yaml                       # Configuración Flutter
├── LICENSE                            # Licencia
└── .gitignore                         # Archivos ignorados
```

### 📁 **Separación por Capas**

Cada feature sigue el patrón de Clean Architecture:
- **Data**: Repositorios, APIs, almacenamiento local
- **Domain**: Casos de uso, entidades, lógica de negocio
- **Presentation**: Widgets, controladores, estado de UI

### 📝 **Estado Actual - V1.0.0**

**✅ Implementado:**
- Sistema completo de monitoreo AWG
- Conectividad MQTT con reconexión automática
- Notificaciones push locales
- Arquitectura modular por features
- Almacenamiento local con Hive
- Gráficas avanzadas en tiempo real
- Detección automática de anomalías
- Reportes diarios automáticos
- Servicio en segundo plano
- Gestión del ciclo de vida de la app

### 🚀 **Próximas Mejoras Planificadas**

Para ver el roadmap completo de desarrollo futuro, incluyendo fases detalladas, cronograma y objetivos específicos, consulta [`ROADMAP.md`](ROADMAP.md).

#### 📋 **Próximas Características (v1.1.x - Beta Avanzada)**
- [ ] Seguridad mejorada con MQTT TLS/SSL
- [ ] Autenticación de dispositivos
- [ ] Sistema de backup y recuperación
- [ ] Interfaz rediseñada con Material Design 3
- [ ] Soporte multi-idioma

#### 🎯 **Visión a Largo Plazo (v2.0+ - Comercial)**
- [ ] Sistema de usuarios y autenticación
- [ ] Dashboard completamente personalizable
- [ ] Exportación avanzada de datos
- [ ] Soporte multi-dispositivo
- [ ] Inteligencia artificial para predicción de fallos

## 📊 Información del Proyecto

### **Versión Actual**
- **Versión**: 1.0.0
- **Última Actualización**: Octubre 2025
- **Estado**: Beta Avanzada
- **Repositorio**: [GitHub - Dropster](https://github.com/C4RTech/Dropster)
- **Etiqueta**: dropster-beta-1.0

### **Compatibilidad**
- **Flutter**: ^3.6.0
- **Dart**: ^3.6.0
- **Android**: API 21+ (Android 5.0+)
- **iOS**: 12.0+
- **Windows**: 10+
- **Linux**: Ubuntu 18.04+
- **macOS**: 10.14+

## 👨‍💻 Autor y Desarrollo

**Carlos Guedez** - Desarrollador Principal
- 🎓 Estudiante de Ingeniería Electrónica
- 📧 Email: carlosguedez7323@gmail.com
- 👨‍🏫 Tutor: Dr. Gabriel Noriega
- 🏛️ Universidad: Universidad Nacional Experimental Politécnica "Antonio José de Sucre" (UNEXPO)

### **Contexto Académico**
Este proyecto es parte de un trabajo de grado para optar por el título de Ingeniería Electrónica, desarrollado como parte del programa de formación en la UNEXPO.

## 📄 Licencia

Este proyecto es de carácter académico y educativo. Todos los derechos reservados © 2025 Carlos Guedez.

**Nota**: Este software está diseñado exclusivamente para fines educativos y de investigación. No se permite su uso comercial sin autorización expresa del autor.

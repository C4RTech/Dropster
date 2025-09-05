# 🔗 Guía Paso a Paso: Verificar Comunicación ESP32 ↔ App Flutter

## 📋 **Checklist de Verificación Completa**

### ✅ **Paso 1: Preparar ESP32**
1. **Subir código al ESP32**:
   - Abrir Arduino IDE
   - Cargar `codigo_ESP32_AWG.ino`
   - Verificar librerías instaladas:
     ```
     - Adafruit BME280
     - Adafruit SHT31
     - PZEM004Tv30
     - PubSubClient
     - RTClib
     - ArduinoJson
     ```
   - Compilar y subir al ESP32

2. **Verificar conexión en Monitor Serial** (115200 baud):
   ```
   ✅ Esperado:
   Sensores OK
   Conectando a WiFi....
   WiFi conectado! IP: 192.168.x.x
   Conectando a MQTT...conectado
   ESP32_AWG_ONLINE
   ```

### ✅ **Paso 2: Ejecutar App Flutter**
1. **Compilar para web**:
   ```bash
   cd c:\Users\Usuario\Desktop\dropster
   flutter pub get
   flutter run -d chrome --web-port=3000
   ```

2. **Verificar app cargada**:
   - App abre en Chrome
   - Dashboard visible
   - Sin errores en consola

### ✅ **Paso 3: Configurar MQTT en App**
1. **Ir a Configuración** en la app
2. **Configurar MQTT**:
   ```
   Server: test.mosquitto.org
   Port: 1883
   Topic: awg/data
   ```
3. **Activar conexión MQTT**

### ✅ **Paso 4: Verificar Comunicación**

#### **4.1 ESP32 → App (Datos)**
- **En Monitor Serial**: Ver `Conectando a MQTT...conectado`
- **En App**: Dashboard debe mostrar datos actualizándose
- **Frecuencia**: Datos nuevos cada 10 segundos

#### **4.2 App → ESP32 (Comandos)**
- **En App**: Usar controles (ON/OFF, solicitar datos)
- **En Monitor Serial**: Ver `Mensaje recibido [awg/control]: GET_STATUS`

### ✅ **Paso 5: Usar Herramientas de Verificación**

#### **Visualizador Web MQTT**:
1. Abrir `mqtt_visualizer.html`
2. Conectar a broker
3. Ver datos JSON en tiempo real

#### **MQTT Explorer** (Recomendado):
1. Descargar: http://mqtt-explorer.com/
2. Conectar a `test.mosquitto.org:1883`
3. Suscribirse a `awg/#`

## 🧪 **Datos que Debes Ver**

### **JSON del ESP32 (cada 10s)**:
```json
{
  "timestamp": "2024-08-30 14:16:33",
  "temperaturaAmbiente": 25.5,
  "humedadRelativa": 65.2,
  "aguaAlmacenada": 15.8,
  "voltaje": 220.5,
  "corriente": 2.1,
  "potencia": 462.1,
  "energia": 1250.5
}
```

### **En App Flutter**:
- Dashboard con tarjetas actualizándose
- Gráficas con datos históricos
- Timestamps reales del RTC

## 🚨 **Solución de Problemas**

### **ESP32 no conecta a WiFi**:
- Verificar SSID: `"Tus nalgas_plus"`
- Verificar password: `"Mc2321332"`
- WiFi debe ser 2.4GHz

### **ESP32 no conecta a MQTT**:
- Verificar internet en ESP32
- Probar ping a `test.mosquitto.org`
- Revisar firewall

### **App no recibe datos**:
- Verificar configuración MQTT en app
- Comprobar que ESP32 envía datos (monitor serial)
- Verificar topics: `awg/data`

### **Datos no se muestran en Dashboard**:
- Verificar formato JSON del ESP32
- Comprobar parsing en `mqtt_hive.dart`
- Revisar consola de Chrome para errores

## 🎯 **Indicadores de Éxito**

### ✅ **Comunicación Exitosa**:
1. **Monitor Serial ESP32**: `ESP32_AWG_ONLINE` cada 10s
2. **App Flutter**: Datos actualizándose en tiempo real
3. **MQTT Explorer**: JSON visible en `awg/data`
4. **Comandos**: App puede enviar comandos al ESP32

### ✅ **Datos Sincronizados**:
- Timestamp del RTC en ESP32 = Timestamp en app
- Valores de sensores coherentes
- Gráficas históricas funcionando

## 🔄 **Flujo Completo de Verificación**

1. **ESP32** lee sensores → genera JSON → envía a `awg/data`
2. **Broker MQTT** recibe y distribuye datos
3. **App Flutter** recibe JSON → parsea → actualiza UI
4. **App** puede enviar comandos a `awg/control`
5. **ESP32** recibe comandos → ejecuta → responde

¡Sigue estos pasos y tendrás comunicación completa ESP32 ↔ App!

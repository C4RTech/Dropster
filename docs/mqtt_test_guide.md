# 🧪 Guía Completa para Probar Comunicación MQTT

## 📋 **Checklist de Pruebas**

### ✅ **1. ESP32 → Broker MQTT**
1. **Compilar y subir código** al ESP32
2. **Abrir monitor serial** (115200 baud)
3. **Verificar mensajes**:
   ```
   Conectando a WiFi...
   WiFi conectado! IP: 192.168.x.x
   Conectando a MQTT...conectado
   ESP32_AWG_ONLINE
   ```

### ✅ **2. Broker → PC (Cliente de Prueba)**
1. **Instalar Python MQTT** (si no tienes Python):
   ```bash
   # Opción 1: Usar MQTT Explorer (GUI)
   # Descargar: http://mqtt-explorer.com/
   
   # Opción 2: Usar cliente web
   # Ir a: http://www.hivemq.com/demos/websocket-client/
   ```

2. **Usar el script Python** (`test_mqtt_client.py`):
   ```bash
   python test_mqtt_client.py
   ```

### ✅ **3. App Flutter → Broker**
La app ya tiene configurado el `UnifiedAWGService` que se conecta automáticamente.

## 🔧 **Configuración Actual del ESP32**

```cpp
// WiFi configurado
ssid: "Tus nalgas_plus"
password: "Mc2321332"

// MQTT configurado  
broker: "test.mosquitto.org" (público)
port: 1883

// Topics:
awg/data      - Datos de sensores (JSON)
awg/status    - Estado del sistema
awg/control   - Comandos remotos
awg/heartbeat - Latido del sistema
```

## 📊 **Datos que Envía el ESP32**

Cada 10 segundos envía JSON con:
```json
{
  "timestamp": "2024-01-15 14:30:25",
  "temperaturaAmbiente": 25.5,
  "humedadRelativa": 65.2,
  "aguaAlmacenada": 15.8,
  "voltaje": 220.5,
  "corriente": 2.1,
  "potencia": 462.1,
  // ... todos los sensores
}
```

## 🧪 **Pruebas Paso a Paso**

### **Paso 1: Probar ESP32**
1. Subir código al ESP32
2. Verificar en monitor serial:
   - ✅ WiFi conectado
   - ✅ MQTT conectado  
   - ✅ Datos enviándose cada 10s

### **Paso 2: Probar Recepción**
Usar MQTT Explorer o cliente web:
1. Conectar a `test.mosquitto.org:1883`
2. Suscribirse a `awg/#` (todos los topics)
3. Verificar datos llegando cada 10s

### **Paso 3: Probar App Flutter**
1. Abrir app Dropster
2. Ir a Configuración → MQTT
3. Configurar:
   - Server: `test.mosquitto.org`
   - Port: `1883`
   - Topics: `awg/data`
4. Verificar datos en Dashboard

### **Paso 4: Prueba Bidireccional**
1. Desde MQTT Explorer enviar a `awg/control`:
   - `GET_STATUS` → Debe responder en `awg/status`
   - `GET_DATA` → Debe enviar datos inmediatos
2. Desde la app usar controles
3. Verificar comandos llegando al ESP32

## 🚨 **Solución de Problemas**

### **ESP32 no conecta a WiFi**
- Verificar SSID y password
- Verificar que WiFi es 2.4GHz (no 5GHz)
- Revisar monitor serial para errores

### **ESP32 no conecta a MQTT**
- Verificar conexión a internet
- Probar con broker local si falla público
- Revisar firewall/antivirus

### **App no recibe datos**
- Verificar configuración MQTT en app
- Verificar que ESP32 está enviando (monitor serial)
- Probar con cliente MQTT externo primero

## 📱 **Configurar App Flutter**

En la app, ir a **Configuración** y establecer:
```
MQTT Server: test.mosquitto.org
MQTT Port: 1883
Data Topic: awg/data
Status Topic: awg/status
```

¡Ahora puedes probar toda la comunicación MQTT completa!

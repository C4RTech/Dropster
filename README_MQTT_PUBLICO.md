# 🧪 PRUEBA DE COMUNICACIÓN MQTT CON BROKER PÚBLICO

## 🎯 OBJETIVO
Probar la comunicación bidireccional entre ESP32 y App Flutter usando broker MQTT público.

## 📋 CONFIGURACIÓN ACTUAL

### ESP32 → Broker Público
- **Broker:** `test.mosquitto.org`
- **Puerto:** `1883`
- **Topics:**
  - `dropster_test/data` → Envía datos de sensores
  - `dropster_test/status` → Envía estado del sistema
  - `dropster_test/control` → Recibe comandos de la app
  - `dropster_test/heartbeat` → Envía heartbeat cada 30s

### App Flutter → Broker Público
- **Broker:** `test.mosquitto.org`
- **Puerto:** `1883`
- **Topics:**
  - `dropster_test/data` → Recibe datos del ESP32
  - `dropster_test/control` → Envía comandos al ESP32

## 🚀 PASOS PARA PROBAR

### 1. Preparar ESP32
```cpp
// Código ya configurado para broker público
const char* mqtt_server = "test.mosquitto.org";
const char* topic_data = "dropster_test/data";
const char* topic_control = "dropster_test/control";
```

**Subir código al ESP32:**
- Abrir `codigo_ESP32_AWG.ino` en Arduino IDE
- Verificar configuración WiFi
- Compilar y subir al ESP32

### 2. Preparar App Flutter
```dart
// Código ya configurado para broker público
final String broker = "test.mosquitto.org";
final String topic = "dropster_test/data";
```

**Construir e instalar APK:**
```bash
flutter build apk
# Instalar el APK generado en tu teléfono
```

### 3. Verificar Comunicación

#### ✅ Señales de Éxito en ESP32 (Serial Monitor):
```
WiFi conectado! IP: 192.168.X.X
Conectando a MQTT (intento 1/5)...
✅ conectado exitosamente
✅ Suscrito a topic_control
✅ Mensaje de conexión enviado
📡 Enviando datos MQTT...
✅ Datos MQTT enviados exitosamente
💓 Heartbeat enviado
```

#### ✅ Señales de Éxito en App Flutter:
```
[MQTT DEBUG] Conexión exitosa al broker test.mosquitto.org:1883
[MQTT DEBUG] Suscrito al tópico dropster_test/data
[MQTT DEBUG] Mensaje recibido en tópico dropster_test/data: {...}
```

## 🔍 DIAGNÓSTICO DE PROBLEMAS

### Problema: ESP32 no conecta
**Síntomas:**
- ❌ "Conectando a MQTT..." pero nunca conecta
- ❌ "❌ falló, rc=X"

**Soluciones:**
1. Verificar conexión WiFi del ESP32
2. Cambiar broker alternativo en ESP32:
   ```cpp
   const char* mqtt_server = "broker.hivemq.com";
   ```

### Problema: App no recibe datos
**Síntomas:**
- ✅ ESP32 conectado y enviando datos
- ❌ App no muestra datos

**Soluciones:**
1. Verificar que ambos usen el mismo topic
2. Revisar logs de la app en modo debug
3. Verificar conexión a internet del teléfono

### Problema: Controles no funcionan
**Síntomas:**
- ✅ Datos fluyen ESP32 → App
- ❌ Comandos App → ESP32 no llegan

**Soluciones:**
1. Verificar topic de control: `dropster_test/control`
2. Revisar logs del ESP32 para comandos recibidos

## 🛠️ HERRAMIENTAS DE DIAGNÓSTICO

### Verificar conectividad MQTT:
```bash
# Ejecutar script de diagnóstico
probar_comunicacion_mqtt.bat
```

### Monitorear topics en tiempo real:
1. Instalar "MQTT Explorer" en PC
2. Conectar a `test.mosquitto.org:1883`
3. Suscribirse a `dropster_test/#` (todos los topics de prueba)

### Logs detallados:
- **ESP32:** Serial Monitor (115200 baud)
- **App:** Consola de desarrollo Flutter
- **Broker:** MQTT Explorer para ver todos los mensajes

## 📊 TOPICS DE COMUNICACIÓN

```
ESP32 → Broker → App Flutter:
├── dropster_test/data      → Datos de sensores (JSON)
├── dropster_test/status    → Estado del ESP32
└── dropster_test/heartbeat → Señal de vida

App Flutter → Broker → ESP32:
└── dropster_test/control   → Comandos de control
```

## 🎉 RESULTADO ESPERADO

Cuando todo funcione correctamente:

1. **ESP32** envía datos cada 10 segundos
2. **App Flutter** recibe y muestra los datos en tiempo real
3. **Controles de la app** encienden/apagan el LED del ESP32
4. **Heartbeat** confirma que ambos están conectados
5. **Reconexión automática** si se pierde la conexión

## 🔄 FALLBACK PLAN

Si `test.mosquitto.org` no funciona:
1. Cambiar a `broker.hivemq.com` en ambos códigos
2. Usar topics únicos: `dropster_hivemq/data`, etc.

## 📞 SOPORTE

Si encuentras problemas:
1. Ejecuta `probar_comunicacion_mqtt.bat`
2. Revisa logs de ESP32 y app
3. Verifica conectividad a internet
4. Comparte los logs de error para diagnóstico
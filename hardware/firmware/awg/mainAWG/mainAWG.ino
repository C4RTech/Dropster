/* ========================================================================================
 *          Sistema Dropster AWG (Atmospheric Water Generator) - Firmware v1.0
 * ========================================================================================
 * Sistema de control completo para generador de agua atmosférico con monitoreo de sensores,
 * control automático, comunicación MQTT y display LCD TFT.
 * ========================================================================================*/

// ========================================================================================
// 1. INCLUDES Y LIBRERÍAS
// ========================================================================================
#include <Wire.h>             // Comunicación I2C para sensores
#include <math.h>             // Funciones matemáticas
#include <WiFi.h>             // Conectividad WiFi
#include <WiFiManager.h>      // Gestión automática de WiFi
#include <PubSubClient.h>     // Cliente MQTT
#include <ArduinoJson.h>      // Parseo JSON
#include <Preferences.h>      // Almacenamiento persistente
#include <NewPing.h>          // Sensor ultrasónico
#include <Adafruit_BME280.h>  // Sensor BME280 (temperatura, humedad, presión)
#include <Adafruit_SHT31.h>   // Sensor SHT31 (temperatura, humedad de alta precisión)
#include <PZEM004Tv30.h>      // Medidor de energía PZEM-004T
#include <RTClib.h>           // Reloj de tiempo real DS3231
#include <esp32-hal-ledc.h>   // Control PWM LEDC para ESP32
#include <driver/ledc.h>
#include "config.h"           // Archivo de configuración con pines y constantes
// ========================================================================================
// 2. INSTANCIAS GLOBALES Y CONFIGURACIÓN INICIAL
// ========================================================================================

// Gestión de conectividad
WiFiManager wifiManager;             // Gestor automático de conexiones WiFi
WiFiClient espClient;                // Cliente WiFi para MQTT
PubSubClient mqttClient(espClient);  // Cliente MQTT

// Hardware del sistema
RTC_DS3231 rtc;                          // Reloj de tiempo real
bool rtcAvailable = false;               // Estado del RTC (evita llamadas repetidas)
Preferences preferences;                 // Almacenamiento persistente en flash
NewPing sonar(TRIG_PIN, ECHO_PIN, 400);  // Sensor ultrasónico (400cm máximo)

// ========================================================================================
// 3. VARIABLES GLOBALES DEL SISTEMA
// ========================================================================================

// Configuración de logging
int logLevel = LOG_INFO;  // Nivel de detalle de logs

// Estado del sistema
unsigned long configPortalTimeout = 0;  // Timeout para portal de configuración
bool systemReady = false;               // Flag para saber si el sistema está listo
bool buttonPressedLast = HIGH;          // Estado anterior del botón para detectar flanco

// (Estados LED eliminados)
float smoothedDistance = 0.0;           // Distancia suavizada del sensor ultrasónico
bool firstDistanceReading = true;       // Flag para inicialización del suavizado
bool offlineMode = false;               // Flag para modo offline
bool portalActive = false;              // Indica portal de configuración activo
bool sensorFailure = false;             // Flag global de falla de sensores

// Sistema de manejo de concurrencia (evita comandos simultáneos)
bool isProcessingCommand = false;   // Flag de procesamiento de comando activo
unsigned long lastCommandTime = 0;  // Timestamp del último comando
String lastProcessedCommand = "";   // Último comando procesado (evita duplicados)

// Sistema de ensamblaje de configuración fragmentada
String configFragments[CONFIG_FRAGMENT_COUNT];                                // Almacena las 4 partes del JSON fragmentado
bool fragmentsReceived[CONFIG_FRAGMENT_COUNT] = {false, false, false, false}; // Flags para saber qué partes llegaron
unsigned long configAssembleTimeout = 0;                                      // Timeout para el ensamblaje

// Estadísticas del sistema (métricas de funcionamiento)
unsigned long systemStartTime = 0;    // Timestamp de inicio del sistema
unsigned int rebootCount = 0;         // Número de reinicios
unsigned long totalUptime = 0;        // Tiempo total de funcionamiento
unsigned int mqttReconnectCount = 0;  // Conteo de reconexiones MQTT
unsigned int wifiReconnectCount = 0;  // Conteo de reconexiones WiFi

// Sistema de recuperación automática de sensores
unsigned long lastSensorRecoveryCheck = 0;  // Última verificación de recuperación

// Configuración MQTT (broker y puerto configurables desde la app)
String mqttBroker = "test.mosquitto.org";  // Broker MQTT
int mqttPort = 1883;                       // Puerto MQTT

// Modos de operación del sistema
enum OperationMode { MODE_MANUAL = 0,
                     MODE_AUTO = 1 };
OperationMode operationMode = MODE_MANUAL;  // Modo actual (MANUAL por defecto)

// Flags de comportamiento del control automático
bool forceStartOnModeSwitch = false;  // Permite arranque inmediato al cambiar a AUTO

// Parámetros del algoritmo de control automático
// El control automático mantiene la temperatura del evaporador cerca del punto de rocío, usando una banda muerta (deadband) para evitar oscilaciones
float control_deadband = CONTROL_DEADBAND_DEFAULT;  // Banda muerta alrededor del punto de rocío (°C)
int control_min_off = CONTROL_MIN_OFF_DEFAULT;      // Tiempo mínimo de apagado antes de rearranque (s)
int control_max_on = CONTROL_MAX_ON_DEFAULT;        // Tiempo máximo de funcionamiento continuo (s)
int control_sampling = CONTROL_SAMPLING_DEFAULT;    // Intervalo de muestreo del control (s)
float control_alpha = CONTROL_ALPHA_DEFAULT;        // Factor de suavizado exponencial (0-1, menor = más suavizado)

// Offsets para control automático del ventilador del compresor
float compressorFanTempOnOffset = COMPRESSOR_FAN_TEMP_ON_OFFSET_DEFAULT;    // Offset para encender ventilador (°C)
float compressorFanTempOffOffset = COMPRESSOR_FAN_TEMP_OFF_OFFSET_DEFAULT;  // Offset para apagar ventilador (°C)

// Estructura para configuración de alertas
struct AlertConfig {
  bool enabled;     // Si la alerta está habilitada
  float threshold;  // Umbral para activar la alerta
};

// Estados de alertas activas (evitan spam de notificaciones)
bool alertTankFullActive = false;        // Alerta de tanque lleno activa
bool alertVoltageLowActive = false;      // Alerta de voltaje bajo activa
bool alertHumidityLowActive = false;     // Alerta de humedad baja activa
bool alertVoltageZeroActive = false;     // Alerta de voltaje cero activa
bool alertCompressorTempActive = false;  // Alerta de temperatura compresor alta activa

// Configuración de cada tipo de alerta
AlertConfig alertTankFull = { true, ALERT_TANK_FULL_DEFAULT };        // Tanque lleno (>90% por defecto)
AlertConfig alertVoltageLow = { true, ALERT_VOLTAGE_LOW_DEFAULT };    // Voltaje bajo (<100V por defecto)
AlertConfig alertHumidityLow = { true, ALERT_HUMIDITY_LOW_DEFAULT };  // Humedad baja (<40% por defecto)
AlertConfig alertVoltageZero = { true, ALERT_VOLTAGE_ZERO_DEFAULT };  // Voltaje cero (siempre activo)
float maxCompressorTemp = MAX_COMPRESSOR_TEMP;                        // Temperatura máxima del compresor
AlertConfig alertCompressorTemp = { true, maxCompressorTemp };        // Temperatura compresor alta (>100°C por defecto)

// Control de timing del compresor
unsigned long compressorOnStart = 0;   // Timestamp cuando se encendió el compresor
unsigned long compressorOffStart = 0;  // Timestamp cuando se apagó el compresor
unsigned long lastControlSample = 0;   // Último muestreo del algoritmo de control

// Buffer circular para logs (evita fragmentación de memoria)
char logBuffer[LOG_BUFFER_SIZE][LOG_MSG_LEN];
int logBufferIndex = 0;

// Calibración del sensor de nivel
float sensorOffset = 0.0;       // Offset de calibración del sensor ultrasónico
bool isCalibrated = false;      // Estado de calibración del tanque
float emptyTankDistance = 0.0;  // Distancia cuando el tanque está vacío
float tankHeight = 0.0;         // Altura calibrada del tanque
float lastValidDistance = NAN;  // Última distancia válida medida

// Configuración del tanque
float tankCapacityLiters = TANK_CAPACITY_DEFAULT;  // Capacidad total del tanque en litros
unsigned int screenTimeoutSec = 0; // Timeout de reposo de la pantalla (segundos). 0 = deshabilitado
unsigned long lastScreenActivity = 0;
bool backlightOn = true;

// Variables para control de tiempo del loop principal
unsigned long lastRead = 0;                                 // Última lectura de sensores
unsigned long lastTransmit = 0;                             // Última transmisión UART
unsigned long lastMQTTTransmit = 0;                         // Última transmisión MQTT
unsigned long lastHeartbeat = 0;                            // Último heartbeat MQTT
unsigned long lastWiFiCheck = 0;                            // Última verificación WiFi
unsigned long lastMqttAttempt = 0;                          // Último intento de reconexión MQTT
unsigned long mqttReconnectBackoff = MQTT_RECONNECT_DELAY;  // Backoff para reconexión MQTT

// Variables para monitoreo automático de sensores
unsigned long lastSensorStatusCheck = 0;  // Última verificación de estado de sensores

// ========================================================================================
// 4. DECLARACIONES ANTICIPADAS DE FUNCIONES
// ========================================================================================

// Configuración del sistema
void setupWiFi();        // Configuración de conectividad WiFi
void setupMQTT();        // Configuración del cliente MQTT
void connectMQTT();      // Conexión al broker MQTT
void loadMqttConfig();   // Carga configuración MQTT desde memoria
void loadAlertConfig();  // Carga configuración de alertas
void loadSystemStats();  // Carga estadísticas del sistema
void saveSystemStats();  // Guarda estadísticas del sistema
void saveAlertConfig();  // Guarda configuración de alertas

// Comunicación y logging
void onMqttMessage(char* topic, byte* payload, unsigned int length);  // Callback MQTT
void awgLog(int level, const String& message);                        // Función de logging
String getSystemStateJSON();                                          // Estado del sistema en formato JSON

// Control de actuadores
void setVentiladorState(bool newState);     // Control del ventilador
void setCompressorFanState(bool newState);  // Control del ventilador del compresor
void setPumpState(bool newState);           // Control de la bomba con validaciones
void publishActuatorStatus();               // Publica estados actuadores + modo por MQTT

// Sistema de alertas
void sendAlert(String type, String message, float value);  // Envía alerta por MQTT
void checkAlerts();                                        // Verifica condiciones de alerta

// Comunicación con display
void sendStatesToDisplay();  // Envía estados al display LCD

// Declaraciones anticipadas para el control del LED RGB
// Definimos el enum de estados y prototipos para evitar errores de compilación
enum RGBLedState { LED_OFF = 0, LED_GREEN, LED_BLUE, LED_YELLOW, LED_RED, LED_RED_BLINK, LED_ORANGE, LED_WHITE };
RGBLedState currentLedState = LED_OFF; // estado global del LED (definido aquí)
void ledInit();
void setLedColor(uint8_t r, uint8_t g, uint8_t b);
void updateLedState();

// ========================================================================================
// 5. FUNCIONES DE COMUNICACIÓN Y UTILIDADES
// ========================================================================================


// Publica el estado de actuadores y modo de operación al topic status (JSON, QoS 1, retained)
void publishActuatorStatus() {
  if (!mqttClient.connected()) return;

  // Leer estados actuales de los relés
  bool compOn = (digitalRead(COMPRESSOR_RELAY_PIN) == LOW);
  bool ventOn = (digitalRead(VENTILADOR_RELAY_PIN) == LOW);
  bool compFanOn = (digitalRead(COMPRESSOR_FAN_RELAY_PIN) == LOW);
  bool pumpOn = (digitalRead(PUMP_RELAY_PIN) == LOW);

  // Crear JSON con estados de actuadores y modo
  StaticJsonDocument<STATUS_JSON_SIZE> statusDoc;
  statusDoc["compressor"] = compOn ? 1 : 0;
  statusDoc["ventilador"] = ventOn ? 1 : 0;
  statusDoc["compressor_fan"] = compFanOn ? 1 : 0;
  statusDoc["pump"] = pumpOn ? 1 : 0;
  statusDoc["mode"] = operationMode == MODE_AUTO ? "AUTO" : "MANUAL";

  char statusBuffer[200];
  size_t statusLen = serializeJson(statusDoc, statusBuffer, sizeof(statusBuffer));
  if (statusLen > 0 && statusLen < sizeof(statusBuffer)) {
    mqttClient.publish(MQTT_TOPIC_STATUS, statusBuffer, true);  // QoS 1, retained
    awgLog(LOG_DEBUG, "📊 Estado actuadores publicado: " + String(statusBuffer));
  }
}

/* Envía una alerta del sistema por MQTT hacia la aplicación móvil. Incluye información detallada del evento para notificaciones push
 * Tipo de alerta ("tank_full", "voltage_low", "humidity_low", "hightemp_comp") - mensaje descriptivo y valor detectado*/
void sendAlert(String type, String message, float value) {
  if (!mqttClient.connected()) {
    awgLog(LOG_WARNING, "MQTT no conectado, no se puede enviar alerta: " + type);
    return;
  }
  awgLog(LOG_DEBUG, "📤 Preparando envío de alerta: " + type + " - Valor: " + String(value, 2));

  // Función para convertir floats a strings con exactamente 2 decimales
  auto floatToString2Decimals = [](float value) -> String {
    char buffer[20];
    dtostrf(value, 1, 2, buffer);
    return String(buffer);
  };

  // Crear documento JSON con información de la alerta
  StaticJsonDocument<STATUS_JSON_SIZE> doc;
  doc["type"] = type;
  doc["message"] = message;
  doc["value"] = floatToString2Decimals(value);

  // Timestamp usando RTC si está disponible
  if (rtcAvailable) {
    DateTime now = rtc.now();
    doc["timestamp"] = now.unixtime();
  } else {
    doc["timestamp"] = millis() / 1000;
  }

  // Serializar y enviar
  char buffer[200];
  size_t len = serializeJson(doc, buffer, sizeof(buffer));
  if (len > 0) {
    awgLog(LOG_DEBUG, "📡 Enviando alerta MQTT al topic " + String(MQTT_TOPIC_ALERTS) + ": " + String(buffer));
    mqttClient.publish(MQTT_TOPIC_ALERTS, buffer, true);  // QoS 1 para asegurar entrega
    awgLog(LOG_DEBUG, "✅ Alerta enviada exitosamente: " + type + " - " + String(value, 2));

    // Log específico para debug de humedad baja
    if (type == "humidity_low") {
      awgLog(LOG_DEBUG, "💨 ALERTA HUMEDAD BAJA enviada - Valor: " + String(value, 2) + "%, Mensaje: " + message);
    }
    mqttClient.loop();  // Procesar MQTT para asegurar envío inmediato
  } else {
    awgLog(LOG_ERROR, "Error al serializar JSON de alerta: " + type);
  }
}

// Envía los estados actuales de los actuadores al display LCD por UART. Formato: "COMP:ON", "VENT:OFF", "PUMP:ON", "MODE:AUTO"
void sendStatesToDisplay() {
  bool compOn = (digitalRead(COMPRESSOR_RELAY_PIN) == LOW);
  bool ventOn = (digitalRead(VENTILADOR_RELAY_PIN) == LOW);
  bool compFanOn = (digitalRead(COMPRESSOR_FAN_RELAY_PIN) == LOW);
  bool pumpOn = (digitalRead(PUMP_RELAY_PIN) == LOW);
  Serial1.println(String("COMP:") + (compOn ? "ON" : "OFF"));
  Serial1.println(String("VENT:") + (ventOn ? "ON" : "OFF"));
  Serial1.println(String("CFAN:") + (compFanOn ? "ON" : "OFF"));
  Serial1.println(String("PUMP:") + (pumpOn ? "ON" : "OFF"));
  Serial1.println(String("MODE:") + (operationMode == MODE_AUTO ? "AUTO" : "MANUAL"));
}



// ========================================================================================
// 6. GESTIÓN DE SENSORES - CLASE AWGSensorManager
// ========================================================================================

/* Clase principal para gestión de todos los sensores del sistema Dropster AWG.
 * Maneja la lectura, validación, calibración, procesamiento de datos de sensores, algoritmos de control automático de temperatura y sistema de alertas.*/
class AWGSensorManager {
private:
  // SENSORES
  Adafruit_BME280 bme;     // Sensor BME280 (temperatura, humedad, presión ambiente)
  Adafruit_SHT31 sht31_1;  // Sensor SHT31 (temperatura y humedad del evaporador)
  PZEM004Tv30 pzem;        // Medidor de energía eléctrica PZEM-004T

  // VARIABLES DE CONTROL AUTOMÁTICO
  float evapSmoothed = 0.0f;             // Temperatura del evaporador suavizada
  bool evapSmoothedInitialized = false;  // Flag de inicialización del suavizado
  struct SensorData {
    float bmeTemp = 0, bmeHum = 0, bmePres = 0;
    float sht1Temp = 0, sht1Hum = 0;
    float distance = 0;
    float voltage = 0, current = 0, power = 0, energy = 0;
    float dewPoint = 0, absHumidity = 0, waterVolume = 0;
    float compressorTemp = 0;
    int compressorState = 0;
    int ventiladorState = 0;
    int compressorFanState = 0;
    int pumpState = 0;
    String timestamp = "";
  } data;
  char txBuffer[TX_BUFFER_SIZE];
  char mqttBuffer[MQTT_BUFFER_SIZE];
  unsigned long lastPZEMRead = 0;

  // Estados de sensores
  bool bmeOnline = false;
  bool sht1Online = false;
  bool pzemOnline = false;
  bool pzemJustOnline = false;  // Flag para evitar alerta falsa en primera lectura después de marcar online
  unsigned long lastPZEMDetection = 0;  // Para reintentar detección periódicamente
  bool rtcOnline = false;

  // Variables para calibración
  typedef struct {
    float distance;  // distancia en cm
    float volume;    // volumen en litros
  } CalibrationPoint;

  CalibrationPoint calibrationPoints[MAX_CALIBRATION_POINTS];
  int numCalibrationPoints = 0;
  bool calibrationMode = false;
  unsigned long calibrationStartTime = 0;
  float calibrationCurrentDistance = 0.0;

  // Funciones privadas para calibración
  void resetCalibration() {
    numCalibrationPoints = 0;
    for (int i = 0; i < MAX_CALIBRATION_POINTS; i++) {
      calibrationPoints[i].distance = 0.0;
      calibrationPoints[i].volume = 0.0;
    }
  }

  void sortCalibrationPoints() {
    // Ordenar por distancia (de mayor a menor)
    for (int i = 0; i < numCalibrationPoints - 1; i++) {
      for (int j = i + 1; j < numCalibrationPoints; j++) {
        if (calibrationPoints[i].distance < calibrationPoints[j].distance) {
          CalibrationPoint temp = calibrationPoints[i];
          calibrationPoints[i] = calibrationPoints[j];
          calibrationPoints[j] = temp;
        }
      }
    }
  }

  /* Calcula el volumen de agua usando interpolación basada en la tabla de calibración.
   * Utiliza búsqueda binaria para localizar el intervalo y interpolación lineal/cuadrática
   * para mayor precisión. Maneja casos extremos y validaciones de rango.*/
  float interpolateVolume(float distance) {
    if (numCalibrationPoints < 2) {         // Verificar que hay suficientes puntos de calibración
      if (!calibrationMode) {
        awgLog(LOG_WARNING, "No hay suficientes puntos de calibración para calcular volumen");
      }
      return 0.0;
    }

    // Validar rango general
    if (distance > calibrationPoints[0].distance + CALIBRATION_DISTANCE_TOLERANCE) {
      return WATER_VOLUME_MIN;  // Demasiado lejos - probablemente error de medición
    }
    if (distance < calibrationPoints[numCalibrationPoints - 1].distance - CALIBRATION_DISTANCE_TOLERANCE) {
      return calibrationPoints[numCalibrationPoints - 1].volume;  // Demasiado cerca - devolver volumen máximo conocido
    }

    // Búsqueda binaria para localizar el intervalo donde distance se encuentra
    int low = 0;
    int high = numCalibrationPoints - 1;
    while (low <= high) {
      int mid = (low + high) / 2;
      if (mid < numCalibrationPoints - 1) {
        if (distance <= calibrationPoints[mid].distance && distance >= calibrationPoints[mid + 1].distance) {
          low = mid;
          break;
        }
      }
      // Como los puntos están ordenados de mayor a menor distancia
      if (distance > calibrationPoints[mid].distance) {
        high = mid - 1;
      } else {
        low = mid + 1;
      }
    }
    int idx = constrain(low, 0, numCalibrationPoints - 2);
    float x0 = calibrationPoints[idx].distance;
    float y0 = calibrationPoints[idx].volume;
    float x1 = calibrationPoints[idx + 1].distance;
    float y1 = calibrationPoints[idx + 1].volume;

    if (fabs(x1 - x0) < 1e-6) {  // Protección contra división por cero
      return y0;
    }
    float v = y0 + (y1 - y0) * ((x0 - distance) / (x0 - x1));  // Interpolación lineal por defecto (robusta y rápida)

    // Si hay al menos 3 puntos, intentar refinamiento cuadrático local para mayor suavidad
    if (numCalibrationPoints >= 3) {
      int thirdIdx = -1;
      // Preferir un punto cercano fuera del segmento para una cuadrática local
      if (idx > 0) thirdIdx = idx - 1;
      else if (idx + 2 < numCalibrationPoints) thirdIdx = idx + 2;

      if (thirdIdx >= 0 && thirdIdx < numCalibrationPoints) {
        float x2 = calibrationPoints[thirdIdx].distance;
        float y2 = calibrationPoints[thirdIdx].volume;

        // Lagrange cuadrático local (estable si los puntos no son colineales extremos)
        float denom = (x0 - x1) * (x0 - x2) * (x1 - x2);
        if (fabs(denom) > 1e-6) {
          float L0 = ((distance - x1) * (distance - x2)) / ((x0 - x1) * (x0 - x2));
          float L1 = ((distance - x0) * (distance - x2)) / ((x1 - x0) * (x1 - x2));
          float L2 = ((distance - x0) * (distance - x1)) / ((x2 - x0) * (x2 - x1));
          float vquad = (y0 * L0) + (y1 * L1) + (y2 * L2);
          v = (v * 0.6f) + (vquad * 0.4f);  // Mezclar suavemente resultado lineal y cuadrático (evitar oscilaciones)
        }
      }
    }
    if (v < WATER_VOLUME_MIN) v = WATER_VOLUME_MIN;  // Asegurar rango válido
    return v;
  }

  void calculateTankHeight() {
    if (numCalibrationPoints >= 2) {
      tankHeight = calibrationPoints[0].distance - calibrationPoints[numCalibrationPoints - 1].distance;
        awgLog(LOG_DEBUG, "Altura calibrada del tanque: " + String(tankHeight, 2) + " cm");
    }
  }

  void loadCalibration() {
    preferences.begin("awg-config", true);
    sensorOffset = preferences.getFloat("offset", 0.0);
    isCalibrated = preferences.getBool("calibrated", false);
    emptyTankDistance = preferences.getFloat("emptyDist", 0.0);
    tankHeight = preferences.getFloat("tankHeight", 0.0);
    tankCapacityLiters = preferences.getFloat("tankCapacity", 1000.0);
    logLevel = preferences.getInt("logLevel", LOG_INFO);
    // Cargar timeout de pantalla (segundos)
    screenTimeoutSec = (unsigned int)preferences.getInt("screenTimeout", (int)screenTimeoutSec);
    int calibVer = preferences.getInt("calibVer", 0);
    String calibType = preferences.getString("calibType", "table");

    // Cargar parámetros de control si existen (si no, mantener valores por defecto)
    control_deadband = preferences.getFloat("ctrl_deadband", control_deadband);
    control_min_off = preferences.getInt("ctrl_min_off", control_min_off);
    control_max_on = preferences.getInt("ctrl_max_on", control_max_on);
    control_sampling = preferences.getInt("ctrl_sampling", control_sampling);
    control_alpha = preferences.getFloat("ctrl_alpha", control_alpha);

    // Cargar offsets del ventilador del compresor
    compressorFanTempOnOffset = preferences.getFloat("fanOnOffset", compressorFanTempOnOffset);
    compressorFanTempOffOffset = preferences.getFloat("fanOffOffset", compressorFanTempOffOffset);

    // Cargar temperatura máxima del compresor
    preferences.end();
    preferences.begin("awg-max-temp", true);
    maxCompressorTemp = preferences.getFloat("value", MAX_COMPRESSOR_TEMP);
    preferences.end();
    preferences.begin("awg-config", true);
    alertCompressorTemp.threshold = maxCompressorTemp;

    // Cargar modo guardado (0=MANUAL,1=AUTO)
    int storedMode = preferences.getInt("mode", (int)operationMode);
    operationMode = (storedMode == MODE_AUTO) ? MODE_AUTO : MODE_MANUAL;
    preferences.end();
    preferences.begin("awg-calib", true);
    numCalibrationPoints = preferences.getInt("calibPoints", 0);

    for (int i = 0; i < numCalibrationPoints; i++) {
      char keyDist[24];
      char keyVol[24];
      snprintf(keyDist, sizeof(keyDist), "calibDist%d", i);
      snprintf(keyVol, sizeof(keyVol), "calibVol%d", i);
      calibrationPoints[i].distance = preferences.getFloat(keyDist, 0.0);
      calibrationPoints[i].volume = preferences.getFloat(keyVol, 0.0);
    }
    preferences.end();

    if (isCalibrated && numCalibrationPoints >= 2) {
      awgLog(LOG_DEBUG, "Calibración cargada: " + String(numCalibrationPoints) + " puntos (ver " + String(calibVer) + ")");
      sortCalibrationPoints();
      calculateTankHeight();
    } else {
      isCalibrated = false;
    }
  }

  void saveCalibration() {
    // Guardar configuración principal
    preferences.begin("awg-config", false);
    preferences.putFloat("offset", sensorOffset);
    preferences.putBool("calibrated", isCalibrated);
    preferences.putFloat("emptyDist", emptyTankDistance);
    preferences.putFloat("tankHeight", tankHeight);

    // Guardar offsets del ventilador del compresor
    preferences.putFloat("fanOnOffset", compressorFanTempOnOffset);
    preferences.putFloat("fanOffOffset", compressorFanTempOffOffset);

    // Metadata de calibración
    preferences.putInt("calibVer", 1);
    preferences.putString("calibType", "table");
    preferences.end();

    // Guardar tabla de calibración
    preferences.begin("awg-calib", false);
    preferences.putInt("calibPoints", numCalibrationPoints);
    for (int i = 0; i < numCalibrationPoints; i++) {
      char keyDist[24];
      char keyVol[24];
      snprintf(keyDist, sizeof(keyDist), "calibDist%d", i);
      snprintf(keyVol, sizeof(keyVol), "calibVol%d", i);
      preferences.putFloat(keyDist, calibrationPoints[i].distance);
      preferences.putFloat(keyVol, calibrationPoints[i].volume);
    }
    preferences.end();
  }

  bool isCalibrationValid() {
    if (numCalibrationPoints < 2) return false;

    // Verificar que los puntos estén en orden descendente de distancia
    for (int i = 0; i < numCalibrationPoints - 1; i++) {
      if (calibrationPoints[i].distance <= calibrationPoints[i + 1].distance) {
        awgLog(LOG_WARNING, "❌ Error: Puntos no en orden descendente");
        return false;
      }
      if (calibrationPoints[i].volume >= calibrationPoints[i + 1].volume) {
        awgLog(LOG_WARNING, "❌ Error: Volúmenes no en orden ascendente");
        return false;
      }
      float distDiff = calibrationPoints[i].distance - calibrationPoints[i + 1].distance;
      float volDiff = calibrationPoints[i + 1].volume - calibrationPoints[i].volume;

      // Solo validar si hay suficiente diferencia
      if (distDiff > 1.0 && volDiff > 1.0) {
        float ratio = distDiff / volDiff;
        // Rango aceptable más amplio
        if (ratio < CALIBRATION_RATIO_MIN || ratio > CALIBRATION_RATIO_MAX) {
          awgLog(LOG_WARNING, "❌ Relación distancia-volumen anómala entre puntos " + String(i) + " y " + String(i + 1));
          return false;
        }
      }
    }
    return true;
  }

public:
  typedef struct SensorData SensorData_t;  // Typedef para acceso externo
  void processControl();
  void checkAlerts();

  // Getters para variables privadas (necesarios para validaciones externas)
  bool getBmeOnline() {
    return bmeOnline;
  }
  bool getSht1Online() {
    return sht1Online;
  }
  bool getPzemOnline() {
    return pzemOnline;
  }
  bool getRtcOnline() {
    return rtcOnline;
  }
  float getTankHeight() {
    return tankHeight;
  }
  SensorData getSensorData() {
    return data;
  }

  // Función de monitoreo automático de estado de sensores (simplificada)
  void monitorSensorStatus() {
    // Verificar estado actual de cada sensor
    bool currentBmeOnline = bmeOnline;
    bool currentSht1Online = sht1Online;
    bool currentPzemOnline = pzemOnline;
    bool currentRtcAvailable = rtcAvailable && rtcOnline;

    // Verificar termistor
     int adcValue = analogRead(TERMISTOR_PIN);
     float voltage = (adcValue * VREF) / ADC_RESOLUTION;
     float resistance = NAN;
     if (voltage > 0.0f && voltage < VREF) {
       resistance = NOMINAL_RESISTANCE * (voltage / (VREF - voltage));
     }
     float temp = calculateTemperature(resistance);
    bool currentTermistorOk = (!isnan(temp) && temp > TEMP_MIN_VALID && temp < TEMP_MAX_VALID);

    // Verificar HC-SR04
    float distance = getAverageDistance(1);
    bool currentUltrasonicOk = (distance >= 0 && distance <= ULTRASONIC_MAX_DISTANCE);

    // Estado anterior (variables locales para simplificar)
    static bool prevBmeOnline = false;
    static bool prevSht1Online = false;
    static bool prevPzemOnline = false;
    static bool prevRtcAvailable = false;
    static bool prevUltrasonicOk = false;
    static bool prevTermistorOk = false;

    // Comparar con estado anterior y mostrar alertas
    if (currentBmeOnline != prevBmeOnline) {
      awgLog(currentBmeOnline ? LOG_INFO : LOG_ERROR,
             currentBmeOnline ? "✅ BME280 RECUPERADO" : "🚨 BME280 DESCONECTADO");
      prevBmeOnline = currentBmeOnline;
    }

    if (currentSht1Online != prevSht1Online) {
      awgLog(currentSht1Online ? LOG_INFO : LOG_ERROR,
             currentSht1Online ? "✅ SHT31 RECUPERADO" : "🚨 SHT31 DESCONECTADO");
      prevSht1Online = currentSht1Online;
    }

    if (currentPzemOnline != prevPzemOnline) {
      awgLog(currentPzemOnline ? LOG_INFO : LOG_ERROR,
             currentPzemOnline ? "✅ PZEM RECUPERADO" : "🚨 PZEM DESCONECTADO");
      prevPzemOnline = currentPzemOnline;
    }

    if (currentRtcAvailable != prevRtcAvailable) {
      awgLog(currentRtcAvailable ? LOG_INFO : LOG_ERROR,
             currentRtcAvailable ? "✅ RTC RECUPERADO" : "🚨 RTC DESCONECTADO");
      prevRtcAvailable = currentRtcAvailable;
    }

    if (currentTermistorOk != prevTermistorOk) {
      awgLog(currentTermistorOk ? LOG_INFO : LOG_ERROR,
             currentTermistorOk ? "✅ TERMISTOR RECUPERADO" : "🚨 TERMISTOR ERROR");
      prevTermistorOk = currentTermistorOk;
    }

    if (currentUltrasonicOk != prevUltrasonicOk) {
      awgLog(currentUltrasonicOk ? LOG_INFO : LOG_ERROR,
             currentUltrasonicOk ? "✅ ULTRASONICO RECUPERADO" : "🚨 ULTRASONICO ERROR");
      prevUltrasonicOk = currentUltrasonicOk;
    }

    // Actualizar flag de falla de sensores
    sensorFailure = !bmeOnline || !sht1Online || !pzemOnline || !rtcOnline;

  }

  void performDiagnosticAndRecovery() {
    awgLog(LOG_INFO, "🔍🛠️ INICIANDO DIAGNÓSTICO Y RECUPERACIÓN DE SENSORES...");
    String failed = "", working = "";
    bool allOk = true;
    bool recoveryAttempted = false;

    // Diagnóstico inicial de sensores
    if (bmeOnline) {
      float t = bme.readTemperature(), h = bme.readHumidity(), p = bme.readPressure() / 100.0;
      if (!isnan(t) && !isnan(h) && !isnan(p)) working += "BME280, ";
      else { failed += "BME280, "; allOk = false; }
    } else { failed += "BME280, "; allOk = false; }

    if (sht1Online) {
      float t = sht31_1.readTemperature(), h = sht31_1.readHumidity();
      if (!isnan(t) && !isnan(h)) working += "SHT31, ";
      else { failed += "SHT31, "; allOk = false; }
    } else { failed += "SHT31, "; allOk = false; }

    if (pzemOnline) {
      float v = pzem.voltage();
      if (!isnan(v) && v > VOLTAGE_ZERO_THRESHOLD) working += "PZEM, ";
      else { failed += "PZEM, "; allOk = false; }
    } else { failed += "PZEM, "; allOk = false; }

    if (rtcAvailable && rtcOnline) working += "RTC, ";
    else { failed += "RTC, "; allOk = false; }

    int adc = analogRead(TERMISTOR_PIN);
     if (adc > 0) {
      float v = (adc * VREF) / ADC_RESOLUTION;
      float r = NAN;
      if (v > 0.0f && v < VREF) r = NOMINAL_RESISTANCE * (v / (VREF - v));
      float temp = calculateTemperature(r);
          if (!isnan(temp) && temp > TEMP_MIN_VALID && temp < TEMP_MAX_VALID) working += "Termistor, ";
          else { failed += "Termistor, "; allOk = false; }
    } else { failed += "Termistor, "; allOk = false; }

    float dist = getAverageDistance(3);
    if (dist >= 0 && dist <= ULTRASONIC_MAX_DISTANCE) working += "HC-SR04, ";
    else { failed += "HC-SR04, "; allOk = false; }

    // Si todos los sensores están OK, terminar diagnóstico
    if (allOk) {
      awgLog(LOG_INFO, "🎉 TODOS LOS SENSORES OK - No se requiere recuperación");
      return;
    }

    // Si hay fallos, intentar recuperación automática
    awgLog(LOG_WARNING, "⚠️ SENSORES CON PROBLEMAS: " + failed);
    awgLog(LOG_INFO, "🔄 Intentando recuperación automática...");

    // Recuperación de sensores I2C (reinicio del bus)
    if (!bmeOnline || !sht1Online || !rtcAvailable) {
      Wire.end();
      delay(100);
      Wire.begin(SDA_PIN, SCL_PIN);
      delay(100);

      if (!bmeOnline && Adafruit_BME280().begin(BME280_ADDR)) {
        bmeOnline = true;
        awgLog(LOG_INFO, "✅ BME280 recuperado");
        recoveryAttempted = true;
      }

      if (!sht1Online) {
        Adafruit_SHT31 tempSHT;
        tempSHT.begin(SHT31_ADDR_1);
        if (!isnan(tempSHT.readTemperature())) {
          sht1Online = true;
          awgLog(LOG_INFO, "✅ SHT31 recuperado");
          recoveryAttempted = true;
        }
      }

      if (!rtcAvailable && RTC_DS3231().begin()) {
        rtcAvailable = rtcOnline = true;
        awgLog(LOG_INFO, "✅ RTC recuperado");
        recoveryAttempted = true;
      }
    }

    // Recuperación del medidor PZEM (intentos consecutivos)
    if (!pzemOnline) {
      // Re-inicializar Serial2 por si se reconectó el dispositivo físicamente
      awgLog(LOG_DEBUG, "🔌 Re-inicializando Serial2 para PZEM antes de recovery attempts...");
      Serial2.end();
      delay(50);
      Serial2.begin(9600, SERIAL_8N1, RX2_PIN, TX2_PIN);
      delay(200);
      while (Serial2.available()) Serial2.read();

      int consecutiveSuccess = 0;
      for (int i = 0; i < RECOVERY_MAX_ATTEMPTS && consecutiveSuccess < RECOVERY_SUCCESS_THRESHOLD; i++) {
        float voltage = pzem.voltage();
        if (!isnan(voltage) && voltage > 0.1) consecutiveSuccess++;
        else consecutiveSuccess = 0;
        delay(300);
      }
      if (consecutiveSuccess >= RECOVERY_SUCCESS_THRESHOLD) {
        pzemOnline = true;
        pzemJustOnline = true; // Marcar para evitar alertas falsas inmediatamente después de reconectar
        awgLog(LOG_INFO, "✅ PZEM recuperado");
        recoveryAttempted = true;
      }
    }

    // Verificar resultados de recuperación después de estabilización
    if (recoveryAttempted) {
      delay(500); // Pequeño delay para estabilización

      // Re-diagnosticar rápidamente para verificar recuperación
      String stillFailed = "";
      bool finalAllOk = true;

      // Verificar BME280
      if (bmeOnline) {
        float t = bme.readTemperature();
        if (isnan(t)) { stillFailed += "BME280, "; finalAllOk = false; }
      } else { stillFailed += "BME280, "; finalAllOk = false; }

      // Verificar SHT31
      if (sht1Online) {
        float t = sht31_1.readTemperature();
        if (isnan(t)) { stillFailed += "SHT31, "; finalAllOk = false; }
      } else { stillFailed += "SHT31, "; finalAllOk = false; }

      // Verificar PZEM
      if (pzemOnline) {
        float v = pzem.voltage();
        if (isnan(v) || v <= VOLTAGE_ZERO_THRESHOLD) { stillFailed += "PZEM, "; finalAllOk = false; }
      } else { stillFailed += "PZEM, "; finalAllOk = false; }

      // Verificar RTC
      if (!rtcAvailable || !rtcOnline) { stillFailed += "RTC, "; finalAllOk = false; }

      // Verificar Termistor
       int adc2 = analogRead(TERMISTOR_PIN);
       if (adc2 > 0) {
         float v = (adc2 * VREF) / ADC_RESOLUTION;
           float r = NAN;
           if (v > 0.0f && v < VREF) r = NOMINAL_RESISTANCE * (v / (VREF - v));
           float temp = calculateTemperature(r);
          if (isnan(temp) || temp <= TEMP_MIN_VALID || temp >= TEMP_MAX_VALID) { stillFailed += "Termistor, "; finalAllOk = false; }
      } else { stillFailed += "Termistor, "; finalAllOk = false; }

      // Verificar HC-SR04
      float dist2 = getAverageDistance(3);
      if (dist2 < 0 || dist2 > ULTRASONIC_MAX_DISTANCE) { stillFailed += "HC-SR04, "; finalAllOk = false; }

      if (finalAllOk) {
        awgLog(LOG_INFO, "🎉 RECUPERACIÓN EXITOSA - Todos los sensores funcionando");
      } else {
        awgLog(LOG_WARNING, "⚠️ RECUPERACIÓN PARCIAL - Sensores aún con problemas: " + stillFailed);
      }
    }
    awgLog(LOG_INFO, "🔍🛠️ DIAGNÓSTICO Y RECUPERACIÓN COMPLETADOS");
  }

  AWGSensorManager()
    : sht31_1(&Wire),
      pzem(Serial2, RX2_PIN, TX2_PIN) {
    resetCalibration();
  }

  bool begin() {
    loadCalibration();
    Wire.begin(SDA_PIN, SCL_PIN);
    Wire.setTimeout(50);  // 50ms timeout para evitar bloqueos I2C
    Serial1.begin(115200, SERIAL_8N1, RX1_PIN, TX1_PIN);
    Serial2.begin(9600, SERIAL_8N1, RX2_PIN, TX2_PIN);
    analogReadResolution(12);  // Configurar ADC a 12 bits para el termistor
    pinMode(COMPRESSOR_RELAY_PIN, OUTPUT);
    digitalWrite(COMPRESSOR_RELAY_PIN, HIGH);
    pinMode(VENTILADOR_RELAY_PIN, OUTPUT);
    digitalWrite(VENTILADOR_RELAY_PIN, HIGH);
    pinMode(COMPRESSOR_FAN_RELAY_PIN, OUTPUT);
    digitalWrite(COMPRESSOR_FAN_RELAY_PIN, HIGH);
    pinMode(PUMP_RELAY_PIN, OUTPUT);
    digitalWrite(PUMP_RELAY_PIN, HIGH);
    pinMode(CONFIG_BUTTON_PIN, INPUT_PULLUP);
    buttonPressedLast = HIGH;  // Asumir no presionado al inicio
    pinMode(TRIG_PIN, OUTPUT);
    pinMode(ECHO_PIN, INPUT);
    digitalWrite(TRIG_PIN, LOW);

    // Inicializar RTC
    if (rtc.begin()) {
      rtcOnline = true;
      rtcAvailable = true;
      if (rtc.lostPower()) {
        rtc.adjust(DateTime(__DATE__, __TIME__));
      }
    }

    // Inicializar sensores
    bmeOnline = bme.begin(BME280_ADDR);
    sht1Online = sht31_1.begin(SHT31_ADDR_1);

    // Detección inicial del PZEM (no marcar como offline permanentemente)
    pzemOnline = false;
    awgLog(LOG_DEBUG, "Verificando conexión inicial con PZEM-004T...");
    for (int i = 0; i < PZEM_INIT_ATTEMPTS; i++) {
      float voltage = pzem.voltage();
      if (!isnan(voltage) && voltage > 0) {
        pzemOnline = true;
        awgLog(LOG_DEBUG, "PZEM-004T detectado en inicialización");
        break;
      }
      delay(500);
    }
    if (!pzemOnline) {
      awgLog(LOG_WARNING, "⚠️ PZEM-004T no detectado inicialmente");
    }

    // Test inicial del sensor ultrasónico
    float testDistance = getAverageDistance(3);
    if (testDistance >= 0) {
      lastValidDistance = testDistance;
      awgLog(LOG_DEBUG, "Sensor ultrasónico OK - Distancia: " + String(testDistance, 2) + " cm");
    } else {
      awgLog(LOG_WARNING, "⚠️ Sensor ultrasónico presenta problemas");
    }
    awgLog(LOG_DEBUG, "Inicialización de sensores completada");
    return bmeOnline || sht1Online || pzemOnline;
  }

  void readSensors() {
    if (rtcOnline) {      // Obtener timestamp si RTC está disponible
      DateTime now = rtc.now();
      data.timestamp = String(now.year()) + "-" + String(now.month()) + "-" + String(now.day()) + " " + String(now.hour()) + ":" + String(now.minute()) + ":" + String(now.second());
    } else {
      data.timestamp = "00-00-00 00:00:00";
    }

    // Leer sensores disponibles
      if (bmeOnline) {
        data.bmeTemp = validateTemp(bme.readTemperature());
        data.bmeHum = validateHumidity(bme.readHumidity());
        data.bmePres = bme.readPressure() / 100.0;
      } else {
        data.bmeTemp = NAN;
        data.bmeHum = NAN;
        data.bmePres = NAN;
      }
 
      if (sht1Online) {
        data.sht1Temp = validateTemp(sht31_1.readTemperature());
        data.sht1Hum = validateHumidity(sht31_1.readHumidity());
      } else {
        data.sht1Temp = NAN;
        data.sht1Hum = NAN;
      }

    // Sensor ultrasónico con promediado y manejo de errores
    float rawDistance = getAverageDistance(5);
    if (rawDistance >= 0) {
      data.distance = getSmoothedDistance(5);
      lastValidDistance = rawDistance;
    } else {
      data.distance = lastValidDistance;
    }

    // Leer PZEM si está disponible o intentar detectar periódicamente
    if (pzemOnline && millis() - lastPZEMRead > 2000) {
      // Leer valores reales del PZEM
      float rawVoltage = pzem.voltage();
      float rawCurrent = pzem.current();
      float rawPower = pzem.power();
      float rawEnergy = pzem.energy();

      // Verificar si el PZEM sigue conectado físicamente (requiere múltiples fallos consecutivos)
      static int consecutiveFailures = 0;
      const int maxConsecutiveFailures = 3;

      if (isnan(rawVoltage)) {
        consecutiveFailures++;
        awgLog(LOG_DEBUG, "📊 Fallo de lectura PZEM (" + String(consecutiveFailures) + "/" + String(maxConsecutiveFailures) + ")");

        if (consecutiveFailures >= maxConsecutiveFailures) {
          // PZEM desconectado físicamente después de múltiples fallos
          pzemOnline = false;
          consecutiveFailures = 0;
          awgLog(LOG_WARNING, "PZEM-004T desconectado físicamente después de " + String(maxConsecutiveFailures) + " fallos consecutivos");
          data.voltage = NAN;
          data.current = NAN;
          data.power = NAN;  // Energía se mantiene (no se resetea)
        } else {
          // Durante fallos temporales, poner corriente y potencia a NAN, mantener energía
          data.current = NAN;
          data.power = NAN;
          awgLog(LOG_DEBUG, "📊 Fallo temporal PZEM - corriente y potencia puestas a NAN, energía mantenida");
        }
      } else {
        consecutiveFailures = 0;                           // Reset contador de fallos
        data.voltage = constrain(rawVoltage, 0.0, 300.0);  // PZEM conectado, procesar valores según física real

        // Si voltaje es prácticamente 0, mostrar 0 en corriente y potencia
        if (data.voltage <= VOLTAGE_ZERO_THRESHOLD) {
          data.current = 0.0;
          data.power = 0.0;
        } else {
          // Voltaje presente, mostrar valores reales
          data.current = constrain(rawCurrent, 0.0, 100.0);
          data.power = constrain(rawPower, 0.0, 10000.0);
        }
        // Energía siempre se mantiene (acumulativa) si es válida
        if (!isnan(rawEnergy) && rawEnergy >= 0) {
          data.energy = rawEnergy;
        }
      }
      lastPZEMRead = millis();
    } else if (!pzemOnline) {
      // Intentar detectar PZEM periódicamente (cada 10 segundos)
      if (millis() - lastPZEMDetection > 10000) {
        lastPZEMDetection = millis();
        awgLog(LOG_DEBUG, "Intentando detectar PZEM-004T...");

        // Intentar leer voltaje para verificar si el PZEM está conectado
        float testVoltage = pzem.voltage();
        if (!isnan(testVoltage) && testVoltage > VOLTAGE_ZERO_THRESHOLD) {
          pzemOnline = true;
          pzemJustOnline = true;  // Marcar que acaba de conectarse para evitar alerta falsa
          awgLog(LOG_DEBUG, "✅ PZEM-004T detectado exitosamente con voltaje: " + String(testVoltage, 1) + "V");
        } else {
          awgLog(LOG_DEBUG, "❌ PZEM-004T no detectado, reintentando en 10s");
        }
      }
      // Si no está online, mostrar NAN para indicar no disponible
      data.voltage = NAN;
      data.current = NAN;
      data.power = NAN;  // Energía se mantiene (no resetear a 0)
    }

    // Leer temperatura del compresor (termistor NTC)
       // Leer múltiples muestras y promediar
       float sumVoltage = 0;
       int samples = 20;

       for (int i = 0; i < TERMISTOR_SAMPLES; i++) {
         int adcValue = analogRead(TERMISTOR_PIN);
         float voltage = (adcValue * VREF) / ADC_RESOLUTION;
         sumVoltage += voltage;
         delay(LOOP_DELAY);
       }
       float avgVoltage = sumVoltage / samples;
       // Calcular resistencia del termistor usando divisor de voltaje: R_term = R_fixed * (V_meas / (Vcc - V_meas))
       float resistance = NOMINAL_RESISTANCE * (avgVoltage / (VREF - avgVoltage));
       // Calcular temperatura
       data.compressorTemp = calculateTemperature(resistance);

    // Estados de relés
    data.compressorState = digitalRead(COMPRESSOR_RELAY_PIN) == LOW ? 1 : 0;
    data.ventiladorState = digitalRead(VENTILADOR_RELAY_PIN) == LOW ? 1 : 0;
    data.compressorFanState = digitalRead(COMPRESSOR_FAN_RELAY_PIN) == LOW ? 1 : 0;
    data.pumpState = digitalRead(PUMP_RELAY_PIN) == LOW ? 1 : 0;

    // Cálculos
    data.dewPoint = calculateDewPoint(data.sht1Temp, data.sht1Hum);
    data.absHumidity = calculateAbsoluteHumidity(data.bmeTemp, data.bmeHum, data.bmePres);
    data.waterVolume = calculateWaterVolume(data.distance);
    this->checkAlerts();  // Verificar alertas
  }

  float getDistance() {
    unsigned int duration = sonar.ping();
    if (duration == 0 || duration > 30000) {
      return -1.0;
    }

    float temperature = data.bmeTemp;  // Correccion por temperatura
    if (temperature == 0.0) {
      temperature = 25.0;              // Valor por defecto si no hay sensor de temperatura
    }

    float speedOfSound = 331.3 + (0.606 * temperature);            // velocidad del sonido en m/s
    float duration_s = duration * 1e-6f;                           // duration está en microsegundos -> convertir a segundos
    float distance = (duration_s * speedOfSound * 100.0f) / 2.0f;  // distancia en cm = (tiempo * velocidad * 100) / 2
    distance += sensorOffset;

    if (distance < ULTRASONIC_MIN_DISTANCE || distance > ULTRASONIC_MAX_DISTANCE) {
      return -1.0;
    }
    return distance;
  }

  float getAverageDistance(int samples) {
    if (samples < MIN_VALID_SAMPLES) samples = MIN_VALID_SAMPLES;
    float values[samples];
    int validSamples = 0;

    for (int i = 0; i < samples; i++) {
      float distance = getDistance();
      if (distance >= 0) {
        values[validSamples] = distance;
        validSamples++;
      }
      delay(60);
    }
    if (validSamples == 0) {
      return -1.0;
    }

    float sorted[validSamples];
    for (int i = 0; i < validSamples; i++) sorted[i] = values[i];
    for (int i = 0; i < validSamples - 1; i++) {
      for (int j = i + 1; j < validSamples; j++) {
        if (sorted[i] > sorted[j]) {
          float tmp = sorted[i];
          sorted[i] = sorted[j];
          sorted[j] = tmp;
        }
      }
    }
    float median = sorted[validSamples / 2];  // Mediana

    // Calcular desviaciones absolutas y MAD
    float deviations[validSamples];
    for (int i = 0; i < validSamples; i++) {
      deviations[i] = fabs(values[i] - median);
    }
    // Ordenar desviaciones para obtener mediana de desviaciones
    for (int i = 0; i < validSamples - 1; i++) {
      for (int j = i + 1; j < validSamples; j++) {
        if (deviations[i] > deviations[j]) {
          float tmp = deviations[i];
          deviations[i] = deviations[j];
          deviations[j] = tmp;
        }
      }
    }
    float mad = deviations[validSamples / 2];
    if (mad < 0.001) mad = 0.001;  // evitar división por cero

    // Filtrar muestras que estén a más de k*MAD del median (k típicamente 3-5)
    const float k = ULTRASONIC_FILTER_K;
    float filtered[validSamples];
    int fcount = 0;
    for (int i = 0; i < validSamples; i++) {
      if (fabs(values[i] - median) <= k * mad) {
        filtered[fcount++] = values[i];
      }
    }

    if (fcount == 0) {
      return median;  // Si todo fue filtrado, devolver la mediana
    }

    // Si hay suficientes valores, devolver la media de los filtrados; si no, la mediana.
    if (fcount >= MIN_VALID_SAMPLES) {
      float sum = 0.0;
      for (int i = 0; i < fcount; i++) sum += filtered[i];
      return sum / fcount;
    } else {
      return median;  // Si pocos valores, usar mediana (más robusto)
    }
  }

  void transmitData() {
      // Asegurar que los valores críticos nunca sean negativos para las gráficas
      float safeWaterVolume = max(WATER_VOLUME_MIN, data.waterVolume);  // Agua nunca negativa
      float safeEnergy = max(WATER_VOLUME_MIN, data.energy);            // Energía nunca negativa
  
      // Calcular porcentaje de agua
      float waterPercent = calculateWaterPercent(data.distance, safeWaterVolume);
      int len = snprintf(txBuffer, sizeof(txBuffer),
                         "%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%d,%d,%d,%d,%.2f\n",
                         data.bmeTemp, data.bmePres, data.bmeHum, data.absHumidity, data.dewPoint,
                         data.sht1Temp, data.sht1Hum, data.compressorTemp,
                         maxCompressorTemp, data.voltage, data.current, data.power, safeEnergy,
                         data.compressorState, data.ventiladorState, data.compressorFanState, data.pumpState,
                         safeWaterVolume);
      if (len > 0 && len < (int)sizeof(txBuffer)) {
        // Verificar que hay espacio en buffer UART antes de enviar
        if (Serial1.availableForWrite() >= (size_t)len) {
          Serial1.write(txBuffer, len);
          awgLog(LOG_DEBUG, "📡 Datos enviados al display: " + String(txBuffer).substring(0, 50) + "...");
        } else {
          awgLog(LOG_WARNING, "⚠️ Buffer UART lleno, datos no enviados al display");
        }
      }
  }

  void transmitMQTTData() {
    if (!mqttClient.connected()) {
      return;
    }

    // Asegurar que los valores críticos nunca sean negativos para las gráficas (pero permitir NAN para indicar no disponible)
    float safeWaterVolume = data.waterVolume;
    if (!isnan(safeWaterVolume) && safeWaterVolume < WATER_VOLUME_MIN) safeWaterVolume = WATER_VOLUME_MIN;
    float safeEnergy = data.energy;
    if (!isnan(safeEnergy) && safeEnergy < WATER_VOLUME_MIN) safeEnergy = WATER_VOLUME_MIN;
    StaticJsonDocument<DATA_JSON_SIZE> doc;

    // Función para convertir floats a strings con exactamente 2 decimales
    auto floatToString2Decimals = [](float value) -> String {
      char buffer[20];
      dtostrf(value, 1, 2, buffer);
      return String(buffer);
    };

    if (bmeOnline) {
      doc["t"] = floatToString2Decimals(data.bmeTemp);  // Temperatura ambiente
      doc["h"] = floatToString2Decimals(data.bmeHum);   // Humedad relativa ambiente
      doc["p"] = floatToString2Decimals(data.bmePres);  // presion atmosferica ambiente
    }
    doc["w"] = floatToString2Decimals(safeWaterVolume);  // Agua almacenada

    if (sht1Online) {
      doc["te"] = floatToString2Decimals(data.sht1Temp);  // Temperatura del evaporador
      doc["he"] = floatToString2Decimals(data.sht1Hum);   // Humedad relativa del evaporador
    }

    doc["tc"] = floatToString2Decimals(data.compressorTemp);  // Temperatura del compresor
    doc["dp"] = floatToString2Decimals(data.dewPoint);        // Temperatura punto de rocio
    doc["ha"] = floatToString2Decimals(data.absHumidity);     // Humedad Absoluta

    if (pzemOnline) {
      if (data.voltage > 0) doc["v"] = floatToString2Decimals(data.voltage);   // voltaje
      if (data.current >= 0) doc["c"] = floatToString2Decimals(data.current);  // corriente
      if (data.power >= 0) doc["po"] = floatToString2Decimals(data.power);     // potencia
    }
    if (safeEnergy >= 0) doc["e"] = floatToString2Decimals(safeEnergy);  // Energía (acumulativa)

    doc["calibrated"] = isCalibrated;

    // Información de conectividad MQTT para la pantalla de conectividad de la app
    doc["mqtt_broker"] = mqttBroker;
    doc["mqtt_port"] = mqttPort;
    doc["mqtt_topic"] = MQTT_TOPIC_DATA;
    doc["mqtt_connected"] = true;         // Si estamos transmitiendo, estamos conectados

    // Calcular porcentaje de agua
    float waterPercentMQTT = calculateWaterPercent(data.distance, safeWaterVolume);
    doc["water_height"] = floatToString2Decimals(waterPercentMQTT);
    doc["tank_capacity"] = floatToString2Decimals(tankCapacityLiters);

    if (rtcOnline) {
      DateTime now = rtc.now();
      doc["ts"] = now.unixtime();
    } else {
      doc["ts"] = floatToString2Decimals(millis() / 1000.0);
    }
    size_t jsonSize = serializeJson(doc, mqttBuffer, sizeof(mqttBuffer));

    if (jsonSize > 0 && jsonSize < sizeof(mqttBuffer)) {
      mqttClient.publish(MQTT_TOPIC_DATA, mqttBuffer, true);  // QoS 1 para asegurar entrega
    }
  }

  // Sistema de calibración simplificado
  void startCalibration() {
    awgLog(LOG_DEBUG, "=== CALIBRACIÓN INICIADA ===");
    calibrationMode = true;
    calibrationStartTime = millis();
    resetCalibration();
  }

  void processCalibration() {
    if (!calibrationMode) return;
    float currentDistance = getAverageDistance(5);
    if (currentDistance < 0) return;
    calibrationCurrentDistance = currentDistance;

    // Detectar tanque vacío (primeros 10 segundos)
    if (millis() - calibrationStartTime < 10000 && numCalibrationPoints == 0) {
      calibrationPoints[0].distance = currentDistance;
      calibrationPoints[0].volume = 0.0;
      numCalibrationPoints = 1;
      emptyTankDistance = currentDistance;
      awgLog(LOG_DEBUG, "✅ Tanque vacío calibrado: " + String(currentDistance, 2) + " cm");
      return;  // Salir después de detectar vacío
    }
  }

  void addCalibrationPoint(float knownVolume) {
    if (numCalibrationPoints >= MAX_CALIBRATION_POINTS) {
      awgLog(LOG_ERROR, "Máximo de puntos de calibración alcanzado");
      return;
    }

    // Tomar múltiples mediciones para mayor precisión
    float avgDistance = getAverageDistance(10);
    if (avgDistance < 0) {
      awgLog(LOG_ERROR, "Error en medición de distancia");
      return;
    }
    calibrationPoints[numCalibrationPoints].distance = avgDistance;
    calibrationPoints[numCalibrationPoints].volume = knownVolume;
    numCalibrationPoints++;
    sortCalibrationPoints();
    calculateTankHeight();
    awgLog(LOG_DEBUG, "✅ Punto añadido: " + String(avgDistance, 2) + "cm = " + String(knownVolume, 3) + "L");
    Serial.println("📊 Punto " + String(numCalibrationPoints) + ": " + String(avgDistance, 2) + " cm → " + String(knownVolume, 3) + " L");
  }

  void completeCalibration() {
    if (numCalibrationPoints < 2) {
      awgLog(LOG_ERROR, "Se necesitan al menos 2 puntos de calibración");
      return;
    }

    // Validar consistencia solo al final
    if (!isCalibrationValid()) {
      awgLog(LOG_ERROR, "Calibración inconsistente - Revise los puntos");
      printCalibrationTable();  // Mostrar tabla para debug
      return;
    }

    isCalibrated = true;
    saveCalibration();
    calibrationMode = false;
    awgLog(LOG_DEBUG, "✅ CALIBRACIÓN COMPLETADA");
    awgLog(LOG_DEBUG, "Puntos registrados: " + String(numCalibrationPoints));
    printCalibrationTable();

    // Mostrar ejemplo de medición actual
    float currentDistance = getAverageDistance(5);
    if (currentDistance >= 0) {
      float currentVolume = interpolateVolume(currentDistance);
      awgLog(LOG_DEBUG, "📏 Medición actual: " + String(currentDistance, 2) + "cm = " + String(currentVolume, 2) + "L");
    }
  }

  float getSmoothedDistance(int samples) {
    float rawDistance = getAverageDistance(samples);

    if (rawDistance < 0) {
      return smoothedDistance;  // Devolver último valor válido
    }

    if (firstDistanceReading) {
      smoothedDistance = rawDistance;
      firstDistanceReading = false;
    } else {
      // Filtro de suavizado exponencial
      float alpha = CONTROL_SMOOTHING_ALPHA;  // Factor de suavizado (0-1, mayor = menos suavizado)
      smoothedDistance = alpha * rawDistance + (1 - alpha) * smoothedDistance;
    }
    return smoothedDistance;
  }

  float calculateWaterVolume(float distance) {
    if (isCalibrated && numCalibrationPoints >= 2) {
      return interpolateVolume(distance);
    }
    return NAN;
  }

  float calculateWaterPercent(float distance, float volume) {
    float waterPercent = 0.0;
    if (tankCapacityLiters > 0 && volume >= 0) {
      // Método preferido: usar volumen calculado por calibración / capacidad total
      waterPercent = (volume / tankCapacityLiters) * 100.0;
      // Limitar entre 0% y 100%
      if (waterPercent < WATER_PERCENT_MIN) waterPercent = WATER_PERCENT_MIN;
      if (waterPercent > WATER_PERCENT_MAX) waterPercent = WATER_PERCENT_MAX;
    } else if (tankHeight > 0) {
      // Fallback: cálculo basado en altura (para compatibilidad)
      float effectiveHeight = tankHeight - sensorOffset;
      if (effectiveHeight > 0) {
        float distanceToWater = distance - sensorOffset;
        if (distanceToWater < 0) distanceToWater = 0;
        waterPercent = ((effectiveHeight - distanceToWater) / effectiveHeight) * 100.0;
        if (waterPercent < WATER_PERCENT_MIN) waterPercent = WATER_PERCENT_MIN;
        if (waterPercent > WATER_PERCENT_MAX) waterPercent = WATER_PERCENT_MAX;
      }
    }
    return waterPercent;
  }

  bool isInCalibrationMode() {
    return calibrationMode;
  }
  bool isTankCalibrated() {
    return isCalibrated;
  }
  float getCurrentCalibrationDistance() {
    return calibrationCurrentDistance;
  }

  void handleCommands() {
    // Buffer ampliado para comandos provenientes del UART1 (pantalla) - ahora 1024 bytes para JSON completo
    static char cmdBuf1[1024];
    static size_t cmdIdx1 = 0;
    while (Serial1.available()) {
      char c = (char)Serial1.read();
      // Registrar actividad de pantalla y encender backlight si está apagado
      lastScreenActivity = millis();
      if (!backlightOn) {
        digitalWrite(BACKLIGHT_PIN, HIGH);
        backlightOn = true;
      }
      if (c == '\n') {
        cmdBuf1[cmdIdx1] = '\0';
        if (cmdIdx1 > 0) {
            // Construir String temporal para reusar processCommand existente
            String tmp(cmdBuf1);
            processCommand(tmp);
        }
        cmdIdx1 = 0;
      } else if (c != '\r') {
        if (cmdIdx1 < sizeof(cmdBuf1) - 1) {
          cmdBuf1[cmdIdx1++] = c;
        } else {
          awgLog(LOG_WARNING, "Buffer UART1 lleno - comando muy largo, descartando");
          cmdIdx1 = 0;  // overflow: resetear
        }
      }
    }
  }

  void handleSerialCommands() {
    // Buffer ampliado para comandos desde el puerto USB Serial - ahora 1024 bytes para JSON completo
    static char cmdBuf0[1024];
    static size_t cmdIdx0 = 0;
    while (Serial.available()) {
      char c = (char)Serial.read();
      if (c == '\n') {
        cmdBuf0[cmdIdx0] = '\0';
        if (cmdIdx0 > 0) {
          String tmp(cmdBuf0);
          processCommand(tmp);
        }
        cmdIdx0 = 0;
      } else if (c != '\r') {
        if (cmdIdx0 < sizeof(cmdBuf0) - 1) {
          cmdBuf0[cmdIdx0] = c;
          cmdIdx0++;
        } else {
          awgLog(LOG_WARNING, "Buffer Serial lleno - comando muy largo, descartando");
          cmdIdx0 = 0;
        }
      }
    }
  }

  String getSystemStatus() {
    String status;
    status += "=== SISTEMA AWG ===\n";
    // Estados de los relés
    status += "Compresor: " + String(digitalRead(COMPRESSOR_RELAY_PIN) == LOW ? "ON" : "OFF") + "\n";
    status += "Ventilador: " + String(digitalRead(VENTILADOR_RELAY_PIN) == LOW ? "ON" : "OFF") + "\n";
    status += "Ventilador compresor: " + String(digitalRead(COMPRESSOR_FAN_RELAY_PIN) == LOW ? "ON" : "OFF") + "\n";
    status += "Bomba: " + String(digitalRead(PUMP_RELAY_PIN) == LOW ? "ON" : "OFF") + "\n";
    // Modo de operación
    status += "Modo: " + String(operationMode == MODE_AUTO ? "AUTO" : "MANUAL") + "\n";
    // Parámetros de control (resumen)
    status += "Control: deadband= " + String(control_deadband, 2) + "C min_off= " + String(control_min_off) + "s max_on= " + String(control_max_on) + "s samp= " + String(control_sampling) + "s alpha= " + String(control_alpha, 2) + " max_temp= " + String(maxCompressorTemp, 1) + "C\n";
    // Nivel de log (numérico y nombre)
    const char* logName = "UNKNOWN";
    switch (logLevel) {
      case LOG_ERROR: logName = "ERROR"; break;
      case LOG_WARNING: logName = "WARNING"; break;
      case LOG_INFO: logName = "INFO"; break;
      case LOG_DEBUG: logName = "DEBUG"; break;
    }
    status += "Nivel log: " + String(logLevel) + " (" + String(logName) + ")\n";
    // Lecturas principales
    status += "Distancia: " + String(data.distance, 2) + " cm\n";
    status += "Agua: " + String(data.waterVolume, 2) + " L\n";
    status += "Temp Ambiente: " + String(data.bmeTemp, 2) + " C\n";
    status += "Hum Ambiente: " + String(data.bmeHum, 2) + " %\n";
    status += "Temp Compresor: " + String(data.compressorTemp, 2) + " C\n";
    bool realmenteCalibrado = (isCalibrated && numCalibrationPoints >= 2);
    status += "Calibrado: " + String(realmenteCalibrado ? "SI" : "NO") + "\n";
    status += "Puntos calibración: " + String(numCalibrationPoints) + "\n";

    if (calibrationMode) {
      status += "=== MODO CALIBRACIÓN ===\n";
      status += "Distancia actual: " + String(calibrationCurrentDistance, 2) + " cm\n";
    }
    return status;
  }

  void printCalibrationTable() {
    awgLog(LOG_INFO, "=== TABLA DE CALIBRACIÓN ===");
    awgLog(LOG_INFO, "Distancia (cm) | Volumen (L)");
    awgLog(LOG_INFO, "----------------------------");

    for (int i = 0; i < numCalibrationPoints; i++) {
      String line = String(calibrationPoints[i].distance, 1) + " cm";
      line += " | " + String(calibrationPoints[i].volume, 1) + " L";

      // Mostrar porcentaje si es el último punto (tanque lleno)
      if (i == 0) {
        line += " (VACÍO)";
      } else if (i == numCalibrationPoints - 1) {
        line += " (LLENO)";
      }
      awgLog(LOG_INFO, line);
    }
  }

  void showCalibrationStatus() {
    if (calibrationMode) {
      Serial.println("=== MODO CALIBRACIÓN ACTIVO ===");
      Serial.println("Distancia actual: " + String(calibrationCurrentDistance, 2) + " cm");
      if (numCalibrationPoints > 0) {
        float currentVolume = interpolateVolume(calibrationCurrentDistance);
        Serial.println("Volumen estimado: " + String(currentVolume, 2) + " L");
      }
      Serial.println("Puntos registrados: " + String(numCalibrationPoints));
      Serial.println("Use CALIB_ADD X.X para agregar punto actual");
      Serial.println("Use CALIB_COMPLETE para finalizar");
    }
  }

  // Funciones de validación y cálculo
  float validateTemp(float temp) {
  return (temp > TEMP_MIN_VALID && temp < TEMP_MAX_VALID) ? temp : 0.0;
  }

  float validateHumidity(float hum) {
  return (hum >= WATER_PERCENT_MIN && hum <= WATER_PERCENT_MAX) ? hum : 0.0;
  }

  float calculateDewPoint(float temp, float hum) {
    const float a = 17.62, b = 243.12;
    float factor = log(hum / 100.0) + (a * temp) / (b + temp);
    return (b * factor) / (a - factor);
  }

  float calculateAbsoluteHumidity(float temp, float hum, float pres) {
    float presPa = pres * 100.0;
    float Pws = A_MAGNUS * exp((L / Rv) * (1.0 / ZERO_CELSIUS - 1.0 / (temp + ZERO_CELSIUS)));
    float Pw = (hum / 100.0) * Pws;
    float mixRatio = 0.622 * (Pw / (presPa - Pw));
    return (mixRatio * presPa * 1000.0) / (Rv * (temp + ZERO_CELSIUS));
  }

  void performSensorRecoveryInternal() {
    awgLog(LOG_DEBUG, "🔄 Verificando recuperación de sensores...");
    bool recoveryAttempted = false;

    // Recuperación de sensores I2C
    if (!bmeOnline || !sht1Online || !rtcAvailable) {
      Wire.end();
      delay(100);
      Wire.begin(SDA_PIN, SCL_PIN);
      delay(100);

      if (!bmeOnline && Adafruit_BME280().begin(BME280_ADDR)) {
        bmeOnline = true;
        awgLog(LOG_DEBUG, "✅ BME280 recuperado");
        recoveryAttempted = true;
      }

      if (!sht1Online) {
        Adafruit_SHT31 tempSHT;
        tempSHT.begin(SHT31_ADDR_1);
        if (!isnan(tempSHT.readTemperature())) {
          sht1Online = true;
          awgLog(LOG_DEBUG, "✅ SHT31 recuperado");
          recoveryAttempted = true;
        }
      }

      if (!rtcAvailable && RTC_DS3231().begin()) {
        rtcAvailable = rtcOnline = true;
        awgLog(LOG_DEBUG, "✅ RTC recuperado");
        recoveryAttempted = true;
      }
    }

    // Recuperación de PZEM
    if (!pzemOnline) {
      // Re-inicializar Serial2 por si se reconectó el dispositivo físicamente
      awgLog(LOG_DEBUG, "🔌 Re-inicializando Serial2 para PZEM antes de recovery attempts...");
      Serial2.end();
      delay(50);
      Serial2.begin(9600, SERIAL_8N1, RX2_PIN, TX2_PIN);
      delay(200);
      while (Serial2.available()) Serial2.read();

      int consecutiveSuccess = 0;
      for (int i = 0; i < RECOVERY_MAX_ATTEMPTS && consecutiveSuccess < RECOVERY_SUCCESS_THRESHOLD; i++) {
        float voltage = pzem.voltage();
        if (!isnan(voltage) && voltage > 0.1) consecutiveSuccess++;
        else consecutiveSuccess = 0;
        delay(300);
      }
      if (consecutiveSuccess >= RECOVERY_SUCCESS_THRESHOLD) {
        pzemOnline = true;
        pzemJustOnline = true; // Marcar para evitar alertas falsas inmediatamente después de reconectar
        awgLog(LOG_DEBUG, "✅ PZEM recuperado");
        recoveryAttempted = true;
      }
    }

    if (recoveryAttempted) awgLog(LOG_DEBUG, "🔄 Recuperación completada");
  }

  void sendConfigAckToApp(int changeCount) {
    if (!mqttClient.connected()) {
      awgLog(LOG_WARNING, "MQTT no conectado, no se puede enviar confirmación de configuración");
      return;
    }

    // Mensaje de confirmación simplificado (sin timestamp ni uptime innecesarios)
    StaticJsonDocument<100> doc;
    doc["type"] = "config_ack";
    doc["status"] = (changeCount > 0) ? "success" : "no_changes";
    doc["changes"] = changeCount;

    char buffer[100];
    size_t len = serializeJson(doc, buffer, sizeof(buffer));
    if (len > 0 && len < sizeof(buffer)) {
      // Enviar al topic STATUS en lugar de CONTROL para evitar loop
      bool sent = mqttClient.publish(MQTT_TOPIC_STATUS, buffer, true);
      if (sent) {
        awgLog(LOG_DEBUG, "📤 Confirmación de configuración enviada exitosamente: " + String(changeCount) + " cambios aplicados");
      } else {
        awgLog(LOG_ERROR, "Error al publicar confirmación MQTT (QoS 1)");
        // Intentar con QoS 0 como fallback
        sent = mqttClient.publish(MQTT_TOPIC_STATUS, buffer, false);
        if (sent) {
          awgLog(LOG_WARNING, "Confirmación enviada con QoS 0 (fallback)");
        } else {
          awgLog(LOG_ERROR, "Error crítico: No se pudo enviar confirmación ni con QoS 0");
        }
      }
      mqttClient.loop();  // Procesar MQTT para asegurar envío inmediato
    } else {
      awgLog(LOG_ERROR, "Error al serializar confirmación JSON - buffer insuficiente");
    }
  }

  // Nueva función para procesar configuración unificada
  void processUnifiedConfig(String jsonPayload) {
    // Verificar que el JSON esté completo (debe terminar con '}')
    if (!jsonPayload.endsWith("}")) {
      awgLog(LOG_ERROR, "JSON incompleto - no termina con '}' - Longitud: " + String(jsonPayload.length()));
      Serial1.println("UPDATE_CONFIG: ERR");
      return;
    }

    // Verificar caracteres de escape
    if (jsonPayload.indexOf('\\') != -1) {
      awgLog(LOG_WARNING, "JSON contiene caracteres de escape - removiendo...");
      jsonPayload.replace("\\", "");
    }

    // Verificar si el JSON comienza correctamente
    if (!jsonPayload.startsWith("{")) {
      awgLog(LOG_ERROR, "JSON malformado - no comienza con '{'");
      Serial1.println("UPDATE_CONFIG: ERR");
      return;
    }

    // Parsear JSON con documento grande para configuración completa
    DynamicJsonDocument doc(CONFIG_JSON_SIZE);
    DeserializationError error = deserializeJson(doc, jsonPayload);

    if (error) {
      awgLog(LOG_ERROR, "Error parseando JSON unificado: " + String(error.c_str()));
      Serial1.println("UPDATE_CONFIG: ERR");
      return;
    }

    awgLog(LOG_DEBUG, "✅ JSON unificado parseado correctamente");
    int changeCount = 0;
    bool hasChanges = false;
    bool mqttChanged = false;
    String changesSummary = "";

    // Procesar configuración MQTT
    if (doc.containsKey("mqtt")) {
      JsonObject mqtt = doc["mqtt"];
      awgLog(LOG_DEBUG, "📡 Procesando configuración MQTT...");

      String newBroker = mqtt["b"] | MQTT_BROKER;  // Usar clave abreviada 'b'
      int newPort = mqtt["p"] | MQTT_PORT;          // Usar clave abreviada 'p'

      if (newBroker != mqttBroker || newPort != mqttPort) {
        awgLog(LOG_DEBUG, "🔄 CAMBIO DE CONFIGURACIÓN MQTT DETECTADO:");
        awgLog(LOG_DEBUG, "  📡 BROKER ANTERIOR: " + mqttBroker + ":" + String(mqttPort));
        awgLog(LOG_DEBUG, "  🎯 BROKER NUEVO: " + newBroker + ":" + String(newPort));

        // Guardar nueva configuración en Preferences
        preferences.begin("awg-mqtt", false);
        preferences.putString("broker", newBroker);
        preferences.putInt("port", newPort);
        preferences.end();

        // Actualizar variables globales
        mqttBroker = newBroker;
        mqttPort = newPort;
        mqttChanged = true;
        changesSummary += "MQTT: " + newBroker + ":" + String(newPort) + " | ";
        changeCount++;
        hasChanges = true;
        awgLog(LOG_DEBUG, "✅ Configuración MQTT actualizada exitosamente");
      } else {
      }
    }

    // Procesar alertas
    if (doc.containsKey("alerts")) {
      JsonObject alerts = doc["alerts"];
      awgLog(LOG_DEBUG, "📊 Procesando configuración de alertas...");

      // Tanque lleno
      if (alerts.containsKey("tf")) {  // Clave abreviada
        bool newEn = alerts["tf"];
        String tfvStr = alerts["tfv"];  // Clave abreviada
        // Reemplazar coma por punto para compatibilidad con parsing decimal
        tfvStr.replace(',', '.');
        float newThr = tfvStr.toFloat();
        if (newThr >= 50.0 && newThr <= 100.0) {
          if (newEn != alertTankFull.enabled || fabs(newThr - alertTankFull.threshold) > 0.01) {
            alertTankFull.enabled = newEn;
            alertTankFull.threshold = newThr;
            changeCount++;
            hasChanges = true;
            awgLog(LOG_DEBUG, "✅ Alerta tanque lleno actualizada: " + String(newEn ? "ON" : "OFF") + " " + String(newThr, 1) + "%");
          } else {
          }
        } else {
          awgLog(LOG_WARNING, "Umbral de tanque lleno inválido: " + String(newThr, 1) + "% (debe estar entre 50-100%)");
        }
      }

      // Voltaje bajo
      if (alerts.containsKey("vl")) {  // Clave abreviada
        bool newEn = alerts["vl"];
        String vlvStr = alerts["vlv"];  // Clave abreviada
        // Reemplazar coma por punto para compatibilidad con parsing decimal
        vlvStr.replace(',', '.');
        float newThr = vlvStr.toFloat();
        if (newThr >= 80.0 && newThr <= 130.0) {
          if (newEn != alertVoltageLow.enabled || fabs(newThr - alertVoltageLow.threshold) > 0.01) {
            alertVoltageLow.enabled = newEn;
            alertVoltageLow.threshold = newThr;
            changeCount++;
            hasChanges = true;
            awgLog(LOG_DEBUG, "✅ Alerta voltaje bajo actualizada: " + String(newEn ? "ON" : "OFF") + " " + String(newThr, 1) + "V");
          } else {
          }
        } else {
          awgLog(LOG_WARNING, "Umbral de voltaje bajo inválido: " + String(newThr, 1) + "V (debe estar entre 80-130V)");
        }
      }

      // Humedad baja
      if (alerts.containsKey("hl")) {  // Clave abreviada
        bool newEn = alerts["hl"];
        String hlvStr = alerts["hlv"];  // Clave abreviada
        // Reemplazar coma por punto para compatibilidad con parsing decimal
        hlvStr.replace(',', '.');
        float newThr = hlvStr.toFloat();
        if (newThr >= 5.0 && newThr <= 50.0) {
          if (newEn != alertHumidityLow.enabled || fabs(newThr - alertHumidityLow.threshold) > 0.01) {
            alertHumidityLow.enabled = newEn;
            alertHumidityLow.threshold = newThr;
            changeCount++;
            hasChanges = true;
            awgLog(LOG_DEBUG, "✅ Alerta humedad baja actualizada: " + String(newEn ? "ON" : "OFF") + " " + String(newThr, 1) + "%");
          } else {
          }
        } else {
          awgLog(LOG_WARNING, "Umbral de humedad baja inválido: " + String(newThr, 1) + "% (debe estar entre 5-50%)");
        }
      }
    }

    // Procesar parámetros de control
    if (doc.containsKey("control")) {
      JsonObject control = doc["control"];
      awgLog(LOG_DEBUG, "🎛️ Procesando parámetros de control...");

      // Banda muerta
      if (control.containsKey("db")) {  // Clave abreviada
        String dbStr = control["db"];
        // Reemplazar coma por punto para compatibilidad con parsing decimal
        dbStr.replace(',', '.');
        float newVal = dbStr.toFloat();
        if (newVal >= 0.5 && newVal <= 10.0) {
          if (fabs(newVal - control_deadband) > 0.01) {
            control_deadband = newVal;
            changeCount++;
            hasChanges = true;
            awgLog(LOG_DEBUG, "✅ Banda muerta actualizada: " + String(newVal, 1) + "°C");
          } else {
          }
        } else {
          awgLog(LOG_WARNING, "Banda muerta inválida: " + String(newVal, 1) + "°C (debe estar entre 0.5-10.0°C)");
        }
      }

      // Temperatura máxima del compresor
      if (control.containsKey("mt")) {  // Clave abreviada
        String mtStr = control["mt"];
        // Reemplazar coma por punto para compatibilidad con parsing decimal
        mtStr.replace(',', '.');
        float newTemp = mtStr.toFloat();
        if (newTemp >= 50.0 && newTemp <= 150.0) {
          if (fabs(newTemp - maxCompressorTemp) > 0.01) {
            maxCompressorTemp = newTemp;
            alertCompressorTemp.threshold = newTemp;
            changeCount++;
            hasChanges = true;
            awgLog(LOG_DEBUG, "✅ Temperatura máxima del compresor actualizada: " + String(newTemp, 1) + "°C");
          } else {
          }
        } else {
          awgLog(LOG_WARNING, "Temperatura máxima del compresor inválida: " + String(newTemp, 1) + "°C (debe estar entre 50.0-150.0°C)");
        }
      }

      // Tiempo mínimo apagado
      if (control.containsKey("mof")) {  // Clave abreviada
        int newVal = control["mof"] | control_min_off;
        if (newVal >= 10 && newVal <= 300) {
          if (newVal != control_min_off) {
            control_min_off = newVal;
            changeCount++;
            hasChanges = true;
            awgLog(LOG_DEBUG, "✅ Tiempo min apagado actualizado: " + String(newVal) + "s");
          } else {
          }
        } else {
          awgLog(LOG_WARNING, "Tiempo min apagado inválido: " + String(newVal) + "s (debe estar entre 10-300s)");
        }
      }

      // Tiempo máximo encendido
      if (control.containsKey("mon")) {  // Clave abreviada
        int newVal = control["mon"] | control_max_on;
        if (newVal >= 300 && newVal <= 7200) {
          if (newVal != control_max_on) {
            control_max_on = newVal;
            changeCount++;
            hasChanges = true;
            awgLog(LOG_DEBUG, "✅ Tiempo max encendido actualizado: " + String(newVal) + "s");
          } else {
          }
        } else {
          awgLog(LOG_WARNING, "Tiempo max encendido inválido: " + String(newVal) + "s (debe estar entre 300-7200s)");
        }
      }

      // Intervalo de muestreo
      if (control.containsKey("smp")) {  // Clave abreviada
        int newVal = control["smp"] | control_sampling;
        if (newVal >= 2 && newVal <= 60) {
          if (newVal != control_sampling) {
            control_sampling = newVal;
            changeCount++;
            hasChanges = true;
            awgLog(LOG_DEBUG, "✅ Intervalo de muestreo actualizado: " + String(newVal) + "s");
          } else {
          }
        } else {
          awgLog(LOG_WARNING, "Intervalo de muestreo inválido: " + String(newVal) + "s (debe estar entre 2-60s)");
        }
      }

      // Factor de suavizado
      if (control.containsKey("alp")) {  // Clave abreviada
        String alpStr = control["alp"];
        // Reemplazar coma por punto para compatibilidad con parsing decimal
        alpStr.replace(',', '.');
        float newVal = alpStr.toFloat();
        if (newVal >= 0.0 && newVal <= 1.0) {
          if (fabs(newVal - control_alpha) > 0.01) {
            control_alpha = newVal;
            changeCount++;
            hasChanges = true;
            awgLog(LOG_DEBUG, "✅ Factor de suavizado actualizado: " + String(newVal, 2));
          } else {
          }
        } else {
          awgLog(LOG_WARNING, "Factor de suavizado inválido: " + String(newVal, 2) + " (debe estar entre 0.0-1.0)");
        }
      }
    }

    // Procesar configuración del tanque
    if (doc.containsKey("tank")) {
      JsonObject tank = doc["tank"];
      awgLog(LOG_DEBUG, "🪣 Procesando configuración del tanque...");
  
      // Capacidad del tanque
      if (tank.containsKey("cap")) {  // Clave abreviada
        String capStr = tank["cap"];
        // Reemplazar coma por punto para compatibilidad con parsing decimal
        capStr.replace(',', '.');
        float newCapacity = capStr.toFloat();
        if (newCapacity > 0 && newCapacity <= 10000) {
          if (fabs(newCapacity - tankCapacityLiters) > 0.01) {
            tankCapacityLiters = newCapacity;
            changeCount++;
            hasChanges = true;
            awgLog(LOG_DEBUG, "✅ Capacidad del tanque actualizada: " + String(newCapacity, 2) + "L");
          } else {
          }
        } else {
          awgLog(LOG_WARNING, "Capacidad del tanque inválida: " + String(newCapacity, 0) + "L (ignorando)");
        }
      }

      // Estado de calibración
      if (tank.containsKey("cal")) {  // Clave abreviada
        bool newCalibrated = tank["cal"] | isCalibrated;
        if (newCalibrated != isCalibrated) {
          isCalibrated = newCalibrated;
          changeCount++;
          hasChanges = true;
          awgLog(LOG_DEBUG, "✅ Estado de calibración actualizado: " + String(newCalibrated ? "SI" : "NO"));
        } else {
        }
      }

      // Puntos de calibración
      if (tank.containsKey("pts")) {  // Clave abreviada
        JsonArray points = tank["pts"];
        int validPoints = 0;
        if (points.size() > 0 && points.size() <= MAX_CALIBRATION_POINTS) {
          // Validar y cargar puntos
          for (int i = 0; i < points.size() && validPoints < MAX_CALIBRATION_POINTS; i++) {
            float dist = points[i]["d"] | -1.0f;  // Clave abreviada
            float vol = points[i]["l"] | -1.0f;   // Clave abreviada

            // Validar valores
            if (dist >= 0 && dist <= 400 && vol >= 0 && vol <= 10000) {
              calibrationPoints[validPoints].distance = dist;
              calibrationPoints[validPoints].volume = vol;
              validPoints++;
            } else {
              awgLog(LOG_WARNING, "Punto de calibración inválido ignorado: dist=" + String(dist, 1) + ", vol=" + String(vol, 1));
            }
          }
          if (validPoints > 0) {
            numCalibrationPoints = validPoints;
            sortCalibrationPoints();
            calculateTankHeight();
            saveCalibration();
            changeCount++;
            hasChanges = true;
            awgLog(LOG_INFO, "✅ Puntos agregados exitosamente: " + String(validPoints));
          } else {
            awgLog(LOG_WARNING, "No se encontraron puntos de calibración válidos");
          }
        } else {
          awgLog(LOG_WARNING, "Número de puntos de calibración inválido: " + String(points.size()));
        }
      }

      // Offset ultrasónico
      if (tank.containsKey("off")) {  // Clave abreviada
        String offStr = tank["off"];
        // Reemplazar coma por punto para compatibilidad con parsing decimal
        offStr.replace(',', '.');
        float newOffset = offStr.toFloat();
        if (newOffset >= -50.0 && newOffset <= 50.0) {
          if (fabs(newOffset - sensorOffset) > 0.01) {
            sensorOffset = newOffset;
            changeCount++;
            hasChanges = true;
            awgLog(LOG_DEBUG, "✅ Offset del sensor actualizado: " + String(newOffset, 1) + "cm");
          } else {
          }
        } else {
          awgLog(LOG_WARNING, "Offset del sensor fuera de rango: " + String(newOffset, 1) + "cm (ignorando)");
        }
      }
    }

    // Reconectar MQTT si cambió la configuración
    if (mqttChanged) {
      awgLog(LOG_DEBUG, "🔌 Reconectando MQTT con nueva configuración...");
      mqttClient.disconnect();
      delay(STARTUP_DELAY);
      if (WiFi.status() == WL_CONNECTED) {
        connectMQTT();
      } else {
        awgLog(LOG_WARNING, "No se reconectará a MQTT porque no hay conexión WiFi");
      }

      // Publicar estado de conexión actualizado
      if (mqttClient.connected()) {
        awgLog(LOG_DEBUG, "✅ Reconexión MQTT exitosa - Broker actual: " + mqttBroker + ":" + String(mqttPort));
        mqttClient.publish(MQTT_TOPIC_SYSTEM, "ESP32_AWG_ONLINE", true);
        // Re-suscribirse a los topics después de reconectar
        mqttClient.subscribe(MQTT_TOPIC_CONTROL);
      } else {
        awgLog(LOG_ERROR, "Reconexión MQTT fallida - Broker configurado: " + mqttBroker + ":" + String(mqttPort));
      }
    }

    // Mostrar resumen de cambios
    if (hasChanges) {
      awgLog(LOG_DEBUG, "✅ Configuración unificada actualizada exitosamente (" + String(changeCount) + " cambios)");
      // Mostrar configuración actual completa en Serial para debugging
      Serial.println("\n=== CONFIGURACIÓN ACTUALIZADA ===");
      Serial.println("📡 MQTT:");
      Serial.printf("  Broker: %s:%d\n", mqttBroker.c_str(), mqttPort);
      Serial.println("🎛️ PARÁMETROS DE CONTROL:");
      Serial.printf("  Banda muerta: %.1f°C\n", control_deadband);
      Serial.printf("  Tiempo min apagado: %d segundos\n", control_min_off);
      Serial.printf("  Tiempo max encendido: %d segundos\n", control_max_on);
      Serial.printf("  Intervalo muestreo: %d segundos\n", control_sampling);
      Serial.printf("  Factor suavizado: %.2f\n", control_alpha);
      Serial.println("🚨 CONFIGURACIÓN DE ALERTAS:");
      Serial.printf("  Tanque lleno: %s (%.1f%%)\n", alertTankFull.enabled ? "ON" : "OFF", alertTankFull.threshold);
      Serial.printf("  Voltaje bajo: %s (%.1fV)\n", alertVoltageLow.enabled ? "ON" : "OFF", alertVoltageLow.threshold);
      Serial.printf("  Humedad baja: %s (%.1f%%)\n", alertHumidityLow.enabled ? "ON" : "OFF", alertHumidityLow.threshold);
      Serial.printf("  Temp alta compresor: (%.1f°C)\n", maxCompressorTemp);
      Serial.println("🪣 CONFIGURACIÓN DEL TANQUE:");
      Serial.printf("  Calibrado: %s\n", isCalibrated ? "SI" : "NO");
      Serial.printf("  Offset ultrasónico: %.1f cm\n", sensorOffset);
      Serial.printf("  Capacidad tanque: %.2f L\n", tankCapacityLiters);
      Serial.printf("  Puntos calibración: %d\n", numCalibrationPoints);
      if (isCalibrated && numCalibrationPoints >= 2) {
        Serial.printf("  Altura tanque: %.1f cm\n", tankHeight);
      }
      Serial.println("================================\n");

      // Guardar configuración en memoria no volátil
      awgLog(LOG_DEBUG, "💾 Guardando configuración...");
      saveAlertConfig();
      preferences.begin("awg-config", false);
      preferences.putFloat("ctrl_deadband", control_deadband);
      preferences.putInt("ctrl_min_off", control_min_off);
      preferences.putInt("ctrl_max_on", control_max_on);
      preferences.putInt("ctrl_sampling", control_sampling);
      preferences.putFloat("ctrl_alpha", control_alpha);
      preferences.end();
      awgLog(LOG_INFO, "💾 Configuración guardada en memoria");

      // Enviar confirmación inmediata a la app vía MQTT
      awgLog(LOG_DEBUG, "📤 Enviando confirmación de configuración a la app...");
      sendConfigAckToApp(changeCount);
      Serial1.println("UPDATE_CONFIG: OK");
      awgLog(LOG_DEBUG, "🎉 Actualización de configuración completada exitosamente");
    } else {
      awgLog(LOG_DEBUG, "ℹ️ Configuración unificada recibida sin cambios");
      awgLog(LOG_DEBUG, "📤 Enviando confirmación de 'sin cambios' a la app...");
      sendConfigAckToApp(0);
      Serial1.println("UPDATE_CONFIG: OK");
    }
  }

  // Función para enviar backup completo de configuración a la app
  void sendConfigBackupToApp() {
    if (!mqttClient.connected()) {   // Validar conexión MQTT
      awgLog(LOG_WARNING, "MQTT no conectado, no se puede enviar backup de configuración");
      return;
    }
    awgLog(LOG_DEBUG, "💾 Generando backup completo de configuración para sincronización con app...");

    // Crear documento JSON con toda la configuración del sistema
    StaticJsonDocument<BACKUP_JSON_SIZE> backup;
    backup["type"] = "config_backup";
    backup["timestamp"] = rtcAvailable ? rtc.now().unixtime() : (millis() / 1000);
    backup["firmware_version"] = "AWG v1.0";

    // Configuración MQTT
    JsonObject mqtt = backup.createNestedObject("mqtt");
    mqtt["broker"] = mqttBroker;
    mqtt["port"] = mqttPort;

    // Parámetros de control automático
    JsonObject control = backup.createNestedObject("control");
    control["deadband"] = control_deadband;
    control["minOff"] = control_min_off;
    control["maxOn"] = control_max_on;
    control["sampling"] = control_sampling;
    control["alpha"] = control_alpha;

    // Configuración de alertas
    JsonObject alerts = backup.createNestedObject("alerts");
    alerts["tankFullEnabled"] = alertTankFull.enabled;
    alerts["tankFullThreshold"] = alertTankFull.threshold;
    alerts["voltageLowEnabled"] = alertVoltageLow.enabled;
    alerts["voltageLowThreshold"] = alertVoltageLow.threshold;
    alerts["humidityLowEnabled"] = alertHumidityLow.enabled;
    alerts["humidityLowThreshold"] = alertHumidityLow.threshold;
    alerts["alertCompressorTemp"] = JsonObject();
    alerts["alertCompressorTemp"]["enabled"] = true;
    alerts["alertCompressorTemp"]["threshold"] = maxCompressorTemp;

    // Configuración del tanque y calibración
    JsonObject tank = backup.createNestedObject("tank");
    tank["capacity"] = tankCapacityLiters;
    tank["isCalibrated"] = isCalibrated;
    tank["offset"] = sensorOffset;
    tank["height"] = tankHeight;
    tank["tank_capacity"] = tankCapacityLiters;  // Para consistencia

    // Tabla completa de puntos de calibración
    JsonArray calibPoints = tank.createNestedArray("calibrationPoints");
    for (int i = 0; i < numCalibrationPoints; i++) {
      JsonObject point = calibPoints.createNestedObject();
      point["distance"] = calibrationPoints[i].distance;
      point["liters"] = calibrationPoints[i].volume;
    }
    // Serializar el backup a string JSON
    String backupStr;
    serializeJson(backup, backupStr);

    // Enviar backup por MQTT para captura automática por la app
    if (mqttClient.connected()) {
      bool sent = mqttClient.publish(MQTT_TOPIC_STATUS, ("BACKUP:" + backupStr).c_str(), true);  // QoS 1
      if (sent) {
        awgLog(LOG_DEBUG, "📡 Backup de configuración enviado por MQTT para sincronización automática");
        awgLog(LOG_DEBUG, "📄 Backup JSON enviado: " + backupStr.substring(0, 200) + (backupStr.length() > 200 ? "..." : ""));
      } else {
        awgLog(LOG_ERROR, "Error al enviar backup por MQTT");
      }
      mqttClient.loop();  // Procesar MQTT para asegurar envío inmediato
    } else {
      awgLog(LOG_WARNING, "MQTT no conectado - Backup no enviado");
    }
  }

  void processCommand(String& cmd) {
    // DEBUG: mostrar comando entrante tal cual (longitud + contenido)
    awgLog(LOG_DEBUG, "RAW INCOMING CMD len=" + String(cmd.length()) + ": '" + cmd + "'");

    // Validación básica del comando
    if (cmd.length() == 0) {
      return;
    }

    cmd.trim();
    if (cmd.length() == 0) {
      return;
    }

    // IGNORAR MENSAJES DE CONFIRMACIÓN DE CONFIGURACIÓN (ACK) - SON RESPUESTAS AUTOMÁTICAS
    if (cmd.indexOf("\"type\":\"config_ack\"") != -1) {
      return;  // Salir sin procesar
    }

    cmd.toLowerCase();             // Hacer comandos case-insensitive
    unsigned long now = millis();  // Sistema de manejo de concurrencia mejorado

    // Verificar debounce para evitar comandos duplicados
    if (cmd == lastProcessedCommand && (now - lastCommandTime) < COMMAND_DEBOUNCE) {
      return;
    }

    // Verificar si hay un comando crítico en proceso
    if (isProcessingCommand) {
      if (now - lastCommandTime < COMMAND_TIMEOUT) {
        awgLog(LOG_WARNING, "Comando ignorado - Procesando comando crítico anterior: " + lastProcessedCommand);
        return;
      } else {
        awgLog(LOG_WARNING, "⏰ Timeout de comando crítico anterior, procesando nuevo comando");
        isProcessingCommand = false;
      }
    }

    // Sistema de ensamblaje de configuración fragmentada
    if (cmd.startsWith("update_config_part1")) {
      awgLog(LOG_DEBUG, "📦 Recibida parte 1 de configuración fragmentada");
      configFragments[0] = cmd.substring(19); // Quitar "update_config_part1"
      fragmentsReceived[0] = true;
      configAssembleTimeout = now + CONFIG_ASSEMBLE_TIMEOUT; // 10 segundos para ensamblar
      return;
    }

    if (cmd.startsWith("update_config_part2")) {
      if (!fragmentsReceived[0]) {
        awgLog(LOG_WARNING, "Parte 2 recibida antes que parte 1 - ignorando");
        return;
      }
      awgLog(LOG_DEBUG, "📦 Recibida parte 2 de configuración fragmentada");
      configFragments[1] = cmd.substring(19); // Quitar "update_config_part2"
      fragmentsReceived[1] = true;
      return;
    }

    if (cmd.startsWith("update_config_part3")) {
      if (!fragmentsReceived[0] || !fragmentsReceived[1]) {
        awgLog(LOG_WARNING, "Parte 3 recibida fuera de orden - ignorando");
        return;
      }
      awgLog(LOG_DEBUG, "📦 Recibida parte 3 de configuración fragmentada");
      configFragments[2] = cmd.substring(19); // Quitar "update_config_part3"
      fragmentsReceived[2] = true;
      return;
    }

    if (cmd.startsWith("update_config_part4")) {
      if (!fragmentsReceived[0] || !fragmentsReceived[1] || !fragmentsReceived[2]) {
        awgLog(LOG_WARNING, "Parte 4 recibida fuera de orden - ignorando");
        return;
      }
      awgLog(LOG_DEBUG, "📦 Recibida parte 4 de configuración fragmentada");
      configFragments[3] = cmd.substring(19); // Quitar "update_config_part4"
      fragmentsReceived[3] = true;
      return;
    }

    if (cmd == "update_config_assemble") {
      awgLog(LOG_DEBUG, "🔧 Iniciando ensamblaje de configuración fragmentada...");

      // Verificar que todas las partes estén presentes
      bool allPartsReceived = true;
      for (int i = 0; i < 4; i++) {
        if (!fragmentsReceived[i]) {
          allPartsReceived = false;
          awgLog(LOG_ERROR, "Parte " + String(i+1) + " de configuración faltante");
          break;
        }
      }

      if (!allPartsReceived) {
        awgLog(LOG_ERROR, "Ensamblaje fallido - partes faltantes");
        // Reset fragments
        for (int i = 0; i < 4; i++) {
          fragmentsReceived[i] = false;
          configFragments[i] = "";
        }
        configAssembleTimeout = 0;
        return;
      }

      // Ensamblar el JSON completo
      String fullJson = "\"mqtt\":" + configFragments[0] + ",\"alerts\":" + configFragments[1] + ",\"control\":" + configFragments[2] + ",\"tank\":" + configFragments[3];
      fullJson = "{" + fullJson + "}";

      // Procesar como update_config normal
      processUnifiedConfig(fullJson);

      // Reset fragments
      for (int i = 0; i < 4; i++) {
        fragmentsReceived[i] = false;
        configFragments[i] = "";
      }
      configAssembleTimeout = 0;
      return;
    }

    // Marcar comando como en proceso para comandos críticos
    bool isCriticalCommand = (cmd.startsWith("update_config") || cmd.startsWith("mode") || cmd == "on" || cmd == "off" || cmd == "onc" || cmd == "offc" || cmd.startsWith("calib_"));

    if (isCriticalCommand) {
      isProcessingCommand = true;
      lastCommandTime = now;
      lastProcessedCommand = cmd;
    } else {
      lastProcessedCommand = cmd;
      lastCommandTime = now;
    }

    // Procesar el comando directamente
    String cmdToProcess = cmd;

    // Acciones manuales deshabilitan control automático (override)
    if (cmdToProcess == "on" || cmdToProcess == "onc") {
      // Verificar temperatura del compresor antes de encender
      if (data.compressorTemp >= alertCompressorTemp.threshold) {
        awgLog(LOG_ERROR, "🚫 SEGURIDAD: Compresor NO encendido - Temperatura alta: " + String(data.compressorTemp, 1) + "°C (máx: " + String(alertCompressorTemp.threshold, 1) + "°C)");
        return;
      }
      operationMode = MODE_MANUAL;
      digitalWrite(COMPRESSOR_RELAY_PIN, LOW);
      awgLog(LOG_DEBUG, "Compresor ON");
      if (mqttClient.connected()) {
        mqttClient.publish(MQTT_TOPIC_STATUS, "COMP_ON");
      }
      sendStatesToDisplay();
    } else if (cmdToProcess == "off" || cmdToProcess == "offc") {
      operationMode = MODE_MANUAL;
      digitalWrite(COMPRESSOR_RELAY_PIN, HIGH);
      awgLog(LOG_DEBUG, "Compresor OFF");
      if (mqttClient.connected()) {
        mqttClient.publish(MQTT_TOPIC_STATUS, "COMP_OFF");
      }
      sendStatesToDisplay();
    } else if (cmdToProcess == "onv") {
      setVentiladorState(true);
      sendStatesToDisplay();
    } else if (cmdToProcess == "offv") {
      setVentiladorState(false);
      sendStatesToDisplay();
    } else if (cmdToProcess == "oncf") {
      setCompressorFanState(true);
      sendStatesToDisplay();
      // Publicar estado actualizado por MQTT para sincronización con la app
      publishActuatorStatus();
    } else if (cmdToProcess == "offcf") {
      setCompressorFanState(false);
      sendStatesToDisplay();
      // Publicar estado actualizado por MQTT para sincronización con la app
      publishActuatorStatus();
    } else if (cmdToProcess == "onb") {
      operationMode = MODE_MANUAL;
      setPumpState(true);
      sendStatesToDisplay();
    } else if (cmdToProcess == "offb") {
      operationMode = MODE_MANUAL;
      setPumpState(false);
      sendStatesToDisplay();
    }
    // Cambio de modo explícito
    else if (cmdToProcess == "mode auto" || cmdToProcess == "mode_auto" || cmdToProcess == "mode:auto") {
      operationMode = MODE_AUTO;
      awgLog(LOG_DEBUG, "Modo cambiado a AUTO");
      preferences.begin("awg-config", false);
      preferences.putInt("mode", (int)operationMode);
      preferences.end();
      if (mqttClient.connected()) mqttClient.publish(MQTT_TOPIC_STATUS, "MODE_AUTO");

      // ACTIVAR AUTOMÁTICAMENTE COMPRESOR Y VENTILADOR AL CAMBIAR A MODO AUTO
      awgLog(LOG_DEBUG, "🔄 Activando automáticamente compresor y ventilador para control automático");
      digitalWrite(COMPRESSOR_RELAY_PIN, LOW);
      awgLog(LOG_DEBUG, "Compresor ON");
      setVentiladorState(true);
      forceStartOnModeSwitch = true;  // Forzar una evaluación inmediata del controlador (one-shot)
      // Publicar estados actuales inmediatamente para sincronización
      publishActuatorStatus();
      sendStatesToDisplay();
    } else if (cmdToProcess == "mode manual" || cmdToProcess == "mode_manual" || cmdToProcess == "mode:manual") {
      operationMode = MODE_MANUAL;
      awgLog(LOG_DEBUG, "Modo cambiado a MANUAL");
      preferences.begin("awg-config", false);
      preferences.putInt("mode", (int)operationMode);
      preferences.end();
      if (mqttClient.connected()) mqttClient.publish(MQTT_TOPIC_STATUS, "MODE_MANUAL");
      // Cancelar cualquier forceStart pendiente
      forceStartOnModeSwitch = false;
      sendStatesToDisplay();
    }
    // SET_CTRL formato: SET_CTRL d,mnOff,mxOn,samp,alpha
    else if (cmd.startsWith("set_ctrl")) {
      String payload = cmd.substring(8);
      payload.trim();
      if (payload.length() > 0 && (payload[0] == ':' || payload[0] == '=' || payload[0] == ' ')) {
        payload = payload.substring(1);
      }
      payload.trim();
      char buf[64];
      payload.toCharArray(buf, sizeof(buf));
      float d = control_deadband;
      int mn = control_min_off;
      int mx = control_max_on;
      int samp = control_sampling;
      float a = control_alpha;
      if (sscanf(buf, "%f,%d,%d,%d,%f", &d, &mn, &mx, &samp, &a) == 5) {
        control_deadband = d;
        control_min_off = mn;
        control_max_on = mx;
        control_sampling = samp;
        control_alpha = a;
        // Persistir
        preferences.begin("awg-config", false);
        preferences.putFloat("ctrl_deadband", control_deadband);
        preferences.putInt("ctrl_min_off", control_min_off);
        preferences.putInt("ctrl_max_on", control_max_on);
        preferences.putInt("ctrl_sampling", control_sampling);
        preferences.putFloat("ctrl_alpha", control_alpha);
        preferences.end();
        awgLog(LOG_INFO, "✅ SET_CTRL aplicado: deadband=" + String(control_deadband, 2) + " min_off=" + String(control_min_off) + " max_on=" + String(control_max_on) + " sampling=" + String(control_sampling) + " alpha=" + String(control_alpha, 3));
        Serial1.println("SET_CTRL: OK");
      }
      else {
        awgLog(LOG_WARNING, "SET_CTRL formato inválido. Uso: SET_CTRL d,mn,mx,samp,alpha");
        Serial1.println("SET_CTRL: ERR");
      }
}
       else if (cmd.startsWith("set_mqtt")) {
         String payload = cmd.substring(8);
         payload.trim();
         if (payload.length() > 0 && (payload[0] == ':' || payload[0] == '=' || payload[0] == ' ')) {
           payload = payload.substring(1);
         }
         payload.trim();
         // Parsear broker y puerto
         int spaceIndex = payload.indexOf(' ');
         if (spaceIndex == -1) {
           awgLog(LOG_WARNING, "SET_MQTT formato inválido. Uso: SET_MQTT broker puerto");
           Serial1.println("SET_MQTT: ERR");
           return;
         }
         String newBroker = payload.substring(0, spaceIndex);
         String portStr = payload.substring(spaceIndex + 1);
         portStr.trim();
         int newPort = portStr.toInt();
         if (newBroker.length() == 0 || newPort <= 0 || newPort > 65535) {
           awgLog(LOG_WARNING, "SET_MQTT parámetros inválidos. Broker debe ser no vacío, puerto 1-65535");
           Serial1.println("SET_MQTT: ERR");
           return;
         }
         // Guardar en preferences
         preferences.begin("awg-mqtt", false);
         preferences.putString("broker", newBroker);
         preferences.putInt("port", newPort);
         preferences.end();
         // Actualizar variables globales
         mqttBroker = newBroker;
         mqttPort = newPort;
         awgLog(LOG_INFO, "✅ SET_MQTT aplicado: " + newBroker + ":" + String(newPort));
         Serial1.println("SET_MQTT: OK");
         // Reconectar MQTT
         mqttClient.disconnect();
         delay(STARTUP_DELAY);
         if (WiFi.status() == WL_CONNECTED) {
           connectMQTT();
         } else {
           awgLog(LOG_WARNING, "No se reconectará a MQTT porque no hay conexión WiFi");
         }
       }
       else if (cmd == "test") {
       testSensor();
       }
       else if (cmd == "system_info") {
      unsigned long currentUptime = (millis() - systemStartTime) / 1000;
      unsigned long totalUptimeHours = (totalUptime + currentUptime) / 3600;

      Serial.println("=== INFORMACIÓN DEL SISTEMA ===");
      Serial.println("📊 Estadísticas:");
      Serial.println("  - Reinicios totales: " + String(rebootCount));
      Serial.println("  - Uptime actual: " + String(currentUptime) + "s");
      Serial.println("  - Uptime total: " + String(totalUptimeHours) + "h");
      Serial.println("  - Reconexiones WiFi: " + String(wifiReconnectCount));
      Serial.println("  - Reconexiones MQTT: " + String(mqttReconnectCount));

      Serial.println("🔧 Hardware:");
      Serial.println("  - Memoria libre: " + String(ESP.getFreeHeap()) + " bytes");
      Serial.println("  - Memoria mínima: " + String(ESP.getMinFreeHeap()) + " bytes");
      Serial.println("  - CPU Freq: " + String(ESP.getCpuFreqMHz()) + " MHz");

      Serial.println("📡 Conectividad:");
      Serial.println("  - WiFi: " + String(WiFi.status() == WL_CONNECTED ? "Conectado" : "Desconectado"));
      Serial.println("  - MQTT: " + String(mqttClient.connected() ? "Conectado" : "Desconectado"));
      Serial.println("  - IP: " + WiFi.localIP().toString());

      Serial.println("⚙️ Configuración:");
      Serial.println("  - Modo: " + String(operationMode == MODE_AUTO ? "AUTO" : "MANUAL"));
      Serial.println("  - Nivel log: " + String(logLevel));
      Serial.println("  - Calibrado: " + String(this->isTankCalibrated() ? "SI" : "NO"));
    } else if (cmd == "clear_stats") {
      rebootCount = 0;
      totalUptime = 0;
      mqttReconnectCount = 0;
      wifiReconnectCount = 0;
      saveSystemStats();
      awgLog(LOG_INFO, "✅ Estadísticas del sistema reseteadas");
    } else if (cmd.startsWith("set_offset")) {
      String offsetStr = cmd.substring(10);
      offsetStr.trim();
      sensorOffset = offsetStr.toFloat();
      preferences.begin("awg-config", false);
      preferences.putFloat("offset", sensorOffset);
      preferences.end();
      awgLog(LOG_INFO, "✅ Offset ajustado a: " + String(sensorOffset, 2) + " cm");
  } else if (cmd.startsWith("set_log_level")) {
      String levelStr = cmd.substring(13);
      levelStr.trim();
      int newLevel = levelStr.toInt();
      if (newLevel >= LOG_ERROR && newLevel <= LOG_DEBUG) {
        logLevel = newLevel;
        preferences.begin("awg-config", false);
        preferences.putInt("logLevel", logLevel);
        preferences.end();
        // Obtener nombre del nivel
        const char* logName = "UNKNOWN";
        switch (newLevel) {
          case LOG_ERROR: logName = "ERROR"; break;
          case LOG_WARNING: logName = "WARNING"; break;
          case LOG_INFO: logName = "INFO"; break;
          case LOG_DEBUG: logName = "DEBUG"; break;
        }
        Serial.println("ℹ️ ✅ Nivel de log ajustado a: " + String(logLevel) + " (" + String(logName) + ")");
      } else {
        awgLog(LOG_WARNING, "Nivel de log inválido. Use: 0=ERROR, 1=WARNING, 2=INFO, 3=DEBUG");
      }
    } else if (cmd.startsWith("set_max_temp")) {
      String tempStr = cmd.substring(12);
      tempStr.trim();
      float newTemp = tempStr.toFloat();
      if (newTemp >= 50.0 && newTemp <= 150.0) {  // Validar rango razonable
        maxCompressorTemp = newTemp;
        alertCompressorTemp.threshold = newTemp;  // Actualizar también el umbral de alerta
        preferences.begin("awg-max-temp", false);
        preferences.putFloat("value", maxCompressorTemp);
        preferences.end();
        awgLog(LOG_INFO, "✅ Temperatura máxima del compresor ajustada a: " + String(maxCompressorTemp, 1) + "°C");
      } else {
        awgLog(LOG_WARNING, "Temperatura máxima inválida. Use: 50.0-150.0°C");
      }
    } else if (cmd.startsWith("set_tank_capacity")) {
      String capStr = cmd.substring(17);
      capStr.trim();
      float newCap = capStr.toFloat();
      if (newCap > 0 && newCap <= 10000) {  // Validar rango razonable
        tankCapacityLiters = newCap;
        preferences.begin("awg-config", false);
        preferences.putFloat("tankCapacity", tankCapacityLiters);
        preferences.end();
        awgLog(LOG_INFO, "✅ Capacidad del tanque ajustada a: " + String(tankCapacityLiters, 0) + " L");
      } else {
        awgLog(LOG_WARNING, "Capacidad del tanque inválida. Use: 1-10000 L");
      }
    } else if (cmd.indexOf("set_screen_timeout") != -1) {
      // SET_SCREEN_TIMEOUT: set or show screen idle timeout (seconds). Accepts separators ':' or '=' or space.
      int p = cmd.indexOf("set_screen_timeout");
      int valStart = p + 18; // length of 'set_screen_timeout'
      String valStr = "";
      if (valStart < cmd.length()) valStr = cmd.substring(valStart);
      valStr.trim();
      while (valStr.length() > 0 && (valStr.charAt(0) == ':' || valStr.charAt(0) == '=' || valStr.charAt(0) == ' ')) {
        valStr = valStr.substring(1);
        valStr.trim();
      }
      // If no value provided, print current timeout
      if (valStr.length() == 0) {
        awgLog(LOG_INFO, "SET_SCREEN_TIMEOUT: valor actual = " + String(screenTimeoutSec) + " segundos");
      } else {
        long newVal = valStr.toInt();
        if (newVal < 0) {
          awgLog(LOG_WARNING, "SET_SCREEN_TIMEOUT: valor inválido (debe ser >= 0)");
        } else {
          screenTimeoutSec = (unsigned int)newVal;
          preferences.begin("awg-config", false);
          preferences.putInt("screenTimeout", (int)newVal);
          preferences.end();
          // Enviar configuración al display
          Serial1.println("SCREEN_TIMEOUT:" + String(screenTimeoutSec));
          awgLog(LOG_INFO, "✅ SET_SCREEN_TIMEOUT: timeout de pantalla ajustado a " + String(screenTimeoutSec) + " segundos");
        }
      }
    } else if (cmd.startsWith("fan_offsets")) {
      String payload = cmd.substring(11);
      payload.trim();
      if (payload.length() > 0 && (payload[0] == ':' || payload[0] == '=' || payload[0] == ' ')) {
        payload = payload.substring(1);
      }
      payload.trim();
      char buf[64];
      payload.toCharArray(buf, sizeof(buf));
      float onOffset = compressorFanTempOnOffset;
      float offOffset = compressorFanTempOffOffset;
      if (sscanf(buf, "%f,%f", &onOffset, &offOffset) == 2) {
        if (onOffset >= 0.0 && onOffset <= maxCompressorTemp && offOffset >= 0.0 && offOffset <= maxCompressorTemp && onOffset < offOffset) {
          compressorFanTempOnOffset = onOffset;
          compressorFanTempOffOffset = offOffset;
          // Guardar en preferences
          preferences.begin("awg-config", false);
          preferences.putFloat("fanOnOffset", compressorFanTempOnOffset);
          preferences.putFloat("fanOffOffset", compressorFanTempOffOffset);
          preferences.end();
          awgLog(LOG_INFO, "✅ FAN_OFFSETS aplicado: encender=" + String(compressorFanTempOnOffset, 1) + "°C apagar=" + String(compressorFanTempOffOffset, 1) + "°C");
          Serial1.println("FAN_OFFSETS: OK");
        } else {
          awgLog(LOG_WARNING, "FAN_OFFSETS inválidos. Rango: 0.0-" + String(maxCompressorTemp, 1) + "°C, encender < apagar");
          Serial1.println("FAN_OFFSETS: ERR");
        }
      } else {
        awgLog(LOG_WARNING, "FAN_OFFSETS formato inválido. Uso: FAN_OFFSETS on,off");
        Serial1.println("FAN_OFFSETS: ERR");
      }
    } else if (cmd == "calibrate") {
      startCalibration();
    } else if (cmd == "status") {
      Serial.println(getSystemStatus());
    } else if (cmd == "calib_empty_force") {
      // Forzar punto vacío usando lectura actual
      float d = getAverageDistance(10);
      if (d >= 0) {
        calibrationPoints[0].distance = d;
        calibrationPoints[0].volume = 0.0;
        numCalibrationPoints = max(numCalibrationPoints, 1);
        emptyTankDistance = d;
        preferences.begin("awg-config", false);
        preferences.putFloat("emptyDist", emptyTankDistance);
        preferences.end();
        awgLog(LOG_DEBUG, "Punto VACÍO forzado: " + String(d, 2) + " cm");
      } else {
        awgLog(LOG_ERROR, "No se pudo medir para forzar vacío");
      }
    } else if (cmd == "calib_add") {
      awgLog(LOG_DEBUG, "Uso: CALIB_ADD <volumen_en_litros>");
    } else if (cmd.startsWith("calib_add")) {
      String volStr = cmd.substring(9);
      volStr.trim();
      float volume = volStr.toFloat();
      addCalibrationPoint(volume);
    } else if (cmd == "calib_upload") {
      awgLog(LOG_DEBUG, "Uso: CALIB_UPLOAD d1:v1,d2:v2,...");
    } else if (cmd.startsWith("calib_upload") || cmd.startsWith("CALIB_UPLOAD")) {  // Formato esperado: CALIB_UPLOAD d1:v1,d2:v2,...
      String payload = cmd.substring(12);
      payload.trim();
      if (payload.length() == 0) {
        awgLog(LOG_INFO, "Uso: CALIB_UPLOAD d1:v1,d2:v2,...");
        awgLog(LOG_INFO, "Ejemplo: CALIB_UPLOAD 150.5:0.0,120.3:500.0,90.1:1000.0");
      } else {
        // Parsear pares separados por coma
        int added = 0;
        bool maxReachedLogged = false;
        int start = 0;
        while (start < (int)payload.length()) {
          int comma = payload.indexOf(',', start);
          String pair;
          if (comma == -1) {
            pair = payload.substring(start);
            start = payload.length();
          } else {
            pair = payload.substring(start, comma);
            start = comma + 1;
          }
          pair.trim();
          int colon = pair.indexOf(':');
          if (colon == -1) continue;
          String dStr = pair.substring(0, colon);
          String vStr = pair.substring(colon + 1);
          dStr.trim();
          vStr.trim();
          // Reemplazar coma por punto para compatibilidad con parsing decimal
          dStr.replace(',', '.');
          vStr.replace(',', '.');
          float d = dStr.toFloat();
          float v = vStr.toFloat();
          if (d > 0 && v >= 0 && d <= 400 && v <= 10000) {
            if (numCalibrationPoints < MAX_CALIBRATION_POINTS) {
              calibrationPoints[numCalibrationPoints].distance = d;
              calibrationPoints[numCalibrationPoints].volume = v;
              numCalibrationPoints++;
              added++;
            } else if (!maxReachedLogged) {
              awgLog(LOG_WARNING, "Máximo de puntos de calibración alcanzado");
              maxReachedLogged = true;
            }
          }
        }
        if (added > 0) {
          sortCalibrationPoints();
          calculateTankHeight();
          saveCalibration();
          awgLog(LOG_DEBUG, "CALIB_UPLOAD: añadidos " + String(added) + " puntos");
          awgLog(LOG_INFO, "✅ Puntos agregados exitosamente: " + String(added));
        } else {
          awgLog(LOG_WARNING, "CALIB_UPLOAD: no se añadieron puntos válidos");
          awgLog(LOG_INFO, "Uso: CALIB_UPLOAD d1:v1,d2:v2,...");
        }
      }
    }else if (cmd == "calib_complete") {
       completeCalibration();
    }else if (cmd == "diag_recover") {
        performDiagnosticAndRecovery();
    }
    else if (cmd == "wifi_config") {
      awgLog(LOG_INFO, "Comando WIFI_CONFIG recibido del display");
      WiFi.disconnect();
      mqttClient.disconnect();
      delay(1000);
      portalActive = true;
      // Forzar LED blanco inmediatamente (portal bloqueante)
      currentLedState = LED_WHITE;
      setLedColor(COLOR_WHITE_R, COLOR_WHITE_G, COLOR_WHITE_B);
      awgLog(LOG_INFO, "Iniciando portal de configuración desde display...");
      wifiManager.setConfigPortalTimeout(WIFI_CONFIG_PORTAL_TIMEOUT);
      if (!wifiManager.startConfigPortal("DropsterAWG_WiFiConfig")) {
        awgLog(LOG_WARNING, "Portal de configuración falló o timeout");
      } else {
        awgLog(LOG_INFO, "Portal cerrado exitosamente");
      }
      setupWiFi();
      setupMQTT();
      portalActive = false;
      // Restaurar LED según estado actual
      updateLedState();
    }
    else if (cmd == "reconnect") {
      awgLog(LOG_INFO, "Comando RECONNECT recibido del display");
      if (WiFi.status() != WL_CONNECTED) {
        awgLog(LOG_INFO, "WiFi no conectado, intentando reconectar...");
        setupWiFi();
      } else {
        awgLog(LOG_INFO, "WiFi ya conectado");
      }
      if (WiFi.status() == WL_CONNECTED) {
        if (!mqttClient.connected()) {
          awgLog(LOG_INFO, "MQTT no conectado, intentando reconectar...");
          setupMQTT();
        } else {
          awgLog(LOG_INFO, "MQTT ya conectado");
        }
      } else {
        awgLog(LOG_WARNING, "No se puede conectar MQTT sin WiFi");
      }
    }
    else if (cmd == "reset_energy") {
      if (!getPzemOnline()) {
        awgLog(LOG_WARNING, "RESET_ENERGY: PZEM no conectado");
      } else {
        pzem.resetEnergy();
        delay(200);
        float after = pzem.energy();
        awgLog(LOG_INFO, "Energia reiniciada a 0.00 Wh");
      }
    }
    else if (cmd == "calib_list") {
      printCalibrationTable();                 // Mostrar tabla actual de calibración
    } else if (cmd.startsWith("calib_set")) {  // Formato esperado: CALIB_SET <idx>,<distance_cm>,<volume_L>
      String payload = cmd.substring(9);
      payload.trim();
      if (payload.length() > 0 && (payload[0] == ':' || payload[0] == '=' || payload[0] == ' ')) {
        payload = payload.substring(1);
      }
      payload.trim();
      char buf[64];
      payload.toCharArray(buf, sizeof(buf));
      int idx = -1;
      float d = 0.0f;
      float v = 0.0f;
      int parsed = sscanf(buf, "%d,%f,%f", &idx, &d, &v);
      if (parsed == 3 && idx >= 0 && idx < MAX_CALIBRATION_POINTS) {
        calibrationPoints[idx].distance = d;
        calibrationPoints[idx].volume = v;
        if (idx >= numCalibrationPoints) numCalibrationPoints = idx + 1;
        sortCalibrationPoints();
        calculateTankHeight();
        saveCalibration();
        awgLog(LOG_INFO, "CALIB_SET: punto " + String(idx) + " = " + String(d, 2) + " cm -> " + String(v, 2) + " L");
      } else {
        awgLog(LOG_WARNING, "Uso: CALIB_SET idx,distance_cm,volume_L");
      }
    } else if (cmd.startsWith("calib_remove")) {
      char buf[64];
      cmd.toCharArray(buf, sizeof(buf));
      int idx = -1;
      int parsed = sscanf(buf, "calib_remove %d", &idx);
      if (parsed == 1 && idx >= 0 && idx < numCalibrationPoints) {
        for (int i = idx; i < numCalibrationPoints - 1; i++) {
          calibrationPoints[i] = calibrationPoints[i + 1];
        }
        numCalibrationPoints--;
        saveCalibration();
        awgLog(LOG_INFO, "CALIB_REMOVE: eliminado punto " + String(idx));
      } else {
        awgLog(LOG_WARNING, "Uso: CALIB_REMOVE <idx>");
      }
    } else if (cmd == "calib_clear") {
      resetCalibration();
      numCalibrationPoints = 0;
      isCalibrated = false;
      saveCalibration();
      awgLog(LOG_INFO, "✅ Tabla de calibración vaciada");
    } else if (cmd == "reset") {
      ESP.restart();
    } else if (cmd == "factory_reset") {
      awgLog(LOG_INFO, "🔄 Iniciando reset de fábrica...");
      // Reset configuración MQTT
      preferences.begin("awg-mqtt", false);
      preferences.clear();
      preferences.end();
      // Reset configuración general
      preferences.begin("awg-config", false);
      preferences.clear();
      preferences.end();
      // Reset temperatura máxima del compresor
      preferences.begin("awg-max-temp", false);
      preferences.clear();
      preferences.end();
      // Reset alertas
      preferences.begin("awg-alerts", false);
      preferences.clear();
      preferences.end();
      // Reset estadísticas
      preferences.begin("awg-stats", false);
      preferences.clear();
      preferences.end();
      // Reset calibración
      preferences.begin("awg-calib", false);
      preferences.clear();
      preferences.end();
      awgLog(LOG_INFO, "✅ Reset de fábrica completado. Reiniciando...");
      delay(1000);
      ESP.restart();
    }
    // UPDATE_CONFIG: Procesar configuración unificada completa (solo si no es ACK propio)
    else if (cmd.startsWith("update_config") && cmd.indexOf("\"type\":\"config_ack\"") == -1) {
      awgLog(LOG_DEBUG, "📨 UPDATE_CONFIG RECIBIDO - Procesando configuración unificada...");
      awgLog(LOG_DEBUG, "📄 Comando completo: '" + cmd + "'");

      // Extraer payload JSON - quitar "update_config"
      String jsonPayload = cmd.substring(12);
      jsonPayload.trim();

      if (jsonPayload.length() == 0) {
        awgLog(LOG_ERROR, "Payload JSON vacío");
        Serial1.println("UPDATE_CONFIG: ERR");
        return;
      }
      awgLog(LOG_DEBUG, "📄 Procesando JSON unificado: " + jsonPayload.substring(0, 50) + (jsonPayload.length() > 50 ? "..." : ""));
      awgLog(LOG_DEBUG, "📏 Longitud del payload JSON: " + String(jsonPayload.length()) + " caracteres");
      processUnifiedConfig(jsonPayload);  // Procesar configuración unificada
    }
    // Ignorar mensajes de confirmación de configuración (ACK) - no procesar como comandos
    else if (cmd.indexOf("\"type\":\"config_ack\"") != -1) {
      return;  // Salir sin marcar como comando no reconocido
    }
    else if (cmd == "system_status") {
      unsigned long currentUptime = (millis() - systemStartTime) / 1000;
      unsigned long totalUptimeHours = (totalUptime + currentUptime) / 3600;

      Serial.println("╔══════════════════════════════════════════════════════════════╗");
      Serial.println("║                 SISTEMA DROPSTER AWG - STATUS                ║");
      Serial.println("╠══════════════════════════════════════════════════════════════╣");

      // ESTADO DEL SISTEMA
      Serial.println("║ 📊 ESTADO DEL SISTEMA:");
      Serial.printf("║   • Modo operación: %s\n", operationMode == MODE_AUTO ? "AUTOMÁTICO" : "MANUAL");
      Serial.printf("║   • Calibración tanque: %s\n", isCalibrated ? "COMPLETA" : "PENDIENTE");
      Serial.println("║");

      // SENSORES Y ACTUADORES
      Serial.println("║ 🔧 SENSORES Y ACTUADORES:");
      Serial.printf("║   • Compresor: %s\n", digitalRead(COMPRESSOR_RELAY_PIN) == LOW ? "ON" : "OFF");
      Serial.printf("║   • Ventilador: %s\n", digitalRead(VENTILADOR_RELAY_PIN) == LOW ? "ON" : "OFF");
      Serial.printf("║   • Ventilador compresor: %s\n", digitalRead(COMPRESSOR_FAN_RELAY_PIN) == LOW ? "ON" : "OFF");
      Serial.printf("║   • Bomba: %s\n", digitalRead(PUMP_RELAY_PIN) == LOW ? "ON" : "OFF");
      Serial.printf("║   • Temp ambiente: %.1f°C\n", this->getSensorData().bmeTemp);
      Serial.printf("║   • Temp compresor: %.1f°C\n", this->getSensorData().compressorTemp);
      Serial.printf("║   • Humedad: %.1f%%\n", this->getSensorData().bmeHum);
      Serial.printf("║   • Nivel agua: %.1f L\n", this->getSensorData().waterVolume);
      Serial.printf("║   • Offset sensor ultrasónico: %.1f cm\n", sensorOffset);
      Serial.printf("║   • Capacidad del tanque: %.2f L\n", tankCapacityLiters);
      Serial.println("║");

      // CONECTIVIDAD
      Serial.println("║ 📡 CONECTIVIDAD:");
      Serial.printf("║   • WiFi: %s\n", WiFi.status() == WL_CONNECTED ? "CONECTADO" : "DESCONECTADO");
      Serial.printf("║   • MQTT: %s\n", mqttClient.connected() ? "CONECTADO" : "DESCONECTADO");
      Serial.printf("║   • Broker: %s:%d\n", mqttBroker.c_str(), mqttPort);
      Serial.println("║");

      // CONFIGURACIÓN DE CONTROL
      Serial.println("║ 🎛️ CONFIGURACIÓN DE CONTROL:");
      Serial.printf("║   • Banda muerta: %.1f°C\n", control_deadband);
      Serial.printf("║   • Tiempo min apagado: %d s\n", control_min_off);
      Serial.printf("║   • Tiempo max encendido: %d s\n", control_max_on);
      Serial.printf("║   • Intervalo muestreo: %d s\n", control_sampling);
      Serial.printf("║   • Factor suavizado: %.2f\n", control_alpha);
      Serial.println("║");

      // ALERTAS
      Serial.println("║ 🚨 CONFIGURACIÓN DE ALERTAS:");
      Serial.printf("║   • Tanque lleno: %s (%.1f%%)\n", alertTankFull.enabled ? "ACTIVA" : "INACTIVA", alertTankFull.threshold);
      Serial.printf("║   • Voltaje bajo: %s (%.1fV)\n", alertVoltageLow.enabled ? "ACTIVA" : "INACTIVA", alertVoltageLow.threshold);
      Serial.printf("║   • Humedad baja: %s (%.1f%%)\n", alertHumidityLow.enabled ? "ACTIVA" : "INACTIVA", alertHumidityLow.threshold);
      Serial.printf("║   • Temp alta compresor: (%.1f°C)\n", maxCompressorTemp);
      Serial.println("║");

      // ESTADÍSTICAS
      Serial.println("║ 📈 ESTADÍSTICAS DEL SISTEMA:");
      Serial.printf("║   • Reinicios totales: %d\n", rebootCount);
      Serial.printf("║   • Uptime actual: %lu s\n", currentUptime);
      Serial.printf("║   • Uptime total: %lu h\n", totalUptimeHours);
      Serial.printf("║   • Reconexiones WiFi: %d\n", wifiReconnectCount);
      Serial.printf("║   • Reconexiones MQTT: %d\n", mqttReconnectCount);
      Serial.println("║");

      // HARDWARE
      Serial.println("║ 💻 INFORMACIÓN DEL HARDWARE:");
      Serial.printf("║   • Memoria libre: %d bytes\n", ESP.getFreeHeap());
      Serial.printf("║   • Memoria mínima: %d bytes\n", ESP.getMinFreeHeap());
      Serial.printf("║   • CPU Freq: %d MHz\n", ESP.getCpuFreqMHz());
      Serial.printf("║   • Firmware: v1.0\n", ESP.getCpuFreqMHz());
      Serial.println("║");
      Serial.println("╚══════════════════════════════════════════════════════════════╝");
    }
    else if (cmd.startsWith("sensor_status")) {
       String sensor = cmd.substring(13);
       sensor.trim();
       sensor.toUpperCase();

       Serial.println("=== ESTADO DETALLADO DEL SENSOR: " + sensor + " ===");
       if (sensor == "BME280" || sensor == "BME") {
         Serial.println("📊 Sensor: BME280 (Temperatura, Humedad, Presión Ambiente)");
         Serial.println("  Estado: " + String(bmeOnline ? "ONLINE" : "OFFLINE"));
         if (bmeOnline) {
           Serial.println("  Temperatura: " + String(data.bmeTemp, 2) + " °C");
           Serial.println("  Humedad: " + String(data.bmeHum, 2) + " %");
           Serial.println("  Presión: " + String(data.bmePres, 2) + " hPa");
         } else {
           Serial.println("  Lecturas: NO DISPONIBLES");
         }
       } else if (sensor == "SHT31" || sensor == "SHT") {
         Serial.println("📊 Sensor: SHT31 (Temperatura, Humedad del Evaporador)");
         Serial.println("  Estado: " + String(sht1Online ? "ONLINE" : "OFFLINE"));
         if (sht1Online) {
           Serial.println("  Temperatura: " + String(data.sht1Temp, 2) + " °C");
           Serial.println("  Humedad: " + String(data.sht1Hum, 2) + " %");
         } else {
           Serial.println("  Lecturas: NO DISPONIBLES");
         }
       } else if (sensor == "PZEM" || sensor == "PZEM004T") {
         Serial.println("📊 Sensor: PZEM-004T (Medidor de Energía)");
         Serial.println("  Estado: " + String(pzemOnline ? "ONLINE" : "OFFLINE"));
         if (pzemOnline) {
           Serial.println("  Voltaje: " + String(data.voltage, 2) + " V");
           Serial.println("  Corriente: " + String(data.current, 2) + " A");
           Serial.println("  Potencia: " + String(data.power, 2) + " W");
           Serial.println("  Energía: " + String(data.energy, 2) + " Wh");
         } else {
           Serial.println("  Lecturas: NO DISPONIBLES");
         }
       } else if (sensor == "RTC" || sensor == "RELOJ") {
         Serial.println("📊 Sensor: RTC DS3231 (Reloj de Tiempo Real)");
         Serial.println("  Estado: " + String((rtcAvailable && rtcOnline) ? "ONLINE" : "OFFLINE"));
         if (rtcAvailable && rtcOnline) {
           DateTime now = rtc.now();
           Serial.println("  Timestamp: " + String(now.year()) + "-" + String(now.month()) + "-" + String(now.day()) + " " + String(now.hour()) + ":" + String(now.minute()) + ":" + String(now.second()));
         } else {
           Serial.println("  Timestamp: NO DISPONIBLE");
         }
       } else if (sensor == "TERMISTOR" || sensor == "NTC") {
         Serial.println("📊 Sensor: Termistor NTC (Temperatura del Compresor)");
         Serial.println("  Estado: " + String((data.compressorTemp > ABSOLUTE_ZERO) ? "ONLINE" : "OFFLINE"));
         Serial.println("  Temperatura: " + String(data.compressorTemp, 2) + " °C");
       } else if (sensor == "ULTRASONICO" || sensor == "HC-SR04" || sensor == "NIVEL") {
         Serial.println("📊 Sensor: HC-SR04 (Nivel de Agua)");
         Serial.println("  Estado: " + String((data.distance >= 0) ? "ONLINE" : "OFFLINE"));
         Serial.println("  Distancia: " + String(data.distance, 2) + " cm");
         Serial.println("  Offset aplicado: " + String(sensorOffset, 2) + " cm");
         if (isCalibrated) {
           Serial.println("  Volumen calculado: " + String(data.waterVolume, 2) + " L");
           Serial.println("  Porcentaje: " + String(calculateWaterPercent(data.distance, data.waterVolume), 1) + " %");
         } else {
           Serial.println("  Calibración: PENDIENTE");
         }
       } else {
         Serial.println("❌ Sensor no reconocido. Sensores disponibles:");
         Serial.println("  - BME280 o BME");
         Serial.println("  - SHT31 o SHT");
         Serial.println("  - PZEM o PZEM004T");
         Serial.println("  - RTC o RELOJ");
         Serial.println("  - TERMISTOR o NTC");
         Serial.println("  - ULTRASONICO, HC-SR04 o NIVEL");
       }

       Serial.println("========================================");
     }
     else if (cmd == "backup_config") {
         /* Genera un respaldo completo de toda la configuración del sistema AWG en formato JSON.
            * El backup incluye: Configuración MQTT - Parámetros de control - Configuración de alertas - Configuración del tanque - Tabla completa de puntos de calibración
            *
            * Uso del backup:
            * 1. Se muestra en Serial como "BACKUP_CONFIG:{json}" para copiado manual
            * 2. Se envía por MQTT al topic de status para que la app lo capture automáticamente
            * 3. La app puede guardar este JSON para restauración futura
            * 4. Útil para backup antes de actualizaciones o troubleshooting*/
 
         awgLog(LOG_DEBUG, "💾 Generando backup completo de configuración del sistema AWG...");
 
         // Crear documento JSON con toda la configuración del sistema
         StaticJsonDocument<1024> backup;
         backup["type"] = "config_backup";
         backup["timestamp"] = rtcAvailable ? rtc.now().unixtime() : (millis() / 1000);
         backup["firmware_version"] = "AWG v1.0";
 
         // Configuración MQTT
         JsonObject mqtt = backup.createNestedObject("mqtt");
         mqtt["broker"] = mqttBroker;
         mqtt["port"] = mqttPort;
 
         // Parámetros de control automático
         JsonObject control = backup.createNestedObject("control");
         control["deadband"] = control_deadband;
         control["minOff"] = control_min_off;
         control["maxOn"] = control_max_on;
         control["sampling"] = control_sampling;
         control["alpha"] = control_alpha;
         control["mode"] = operationMode;
 
         // Configuración de alertas
         JsonObject alerts = backup.createNestedObject("alerts");
         alerts["tankFullEnabled"] = alertTankFull.enabled;
         alerts["tankFullThreshold"] = alertTankFull.threshold;
         alerts["voltageLowEnabled"] = alertVoltageLow.enabled;
         alerts["voltageLowThreshold"] = alertVoltageLow.threshold;
         alerts["humidityLowEnabled"] = alertHumidityLow.enabled;
         alerts["humidityLowThreshold"] = alertHumidityLow.threshold;
 
         // Configuración del tanque y calibración
         JsonObject tank = backup.createNestedObject("tank");
         tank["capacity"] = tankCapacityLiters;
         tank["isCalibrated"] = isCalibrated;
         tank["offset"] = sensorOffset;
         tank["height"] = tankHeight;
         tank["tank_capacity"] = tankCapacityLiters;  // Para consistencia
 
         // Tabla completa de puntos de calibración
         JsonArray calibPoints = tank.createNestedArray("calibrationPoints");
         for (int i = 0; i < numCalibrationPoints; i++) {
           JsonObject point = calibPoints.createNestedObject();
           point["distance"] = calibrationPoints[i].distance;
           point["liters"] = calibrationPoints[i].volume;
         }
 
         // Serializar el backup a string JSON
         String backupStr;
         serializeJson(backup, backupStr);
 
         // Mostrar backup en Serial para copiado manual
         Serial.println("BACKUP_CONFIG:" + backupStr);
 
         // Enviar backup por MQTT para captura automática por la app
         if (mqttClient.connected()) {
           mqttClient.publish(MQTT_TOPIC_SYSTEM, ("BACKUP:" + backupStr).c_str());
           awgLog(LOG_DEBUG, "📡 Backup enviado por MQTT para captura automática por la app");
         } else {
           awgLog(LOG_WARNING, "MQTT no conectado - Backup solo disponible en Serial");
         }
       }
     else if (cmd == "sync_rtc") {
       awgLog(LOG_WARNING, "Comando SYNC_RTC obsoleto - NTP eliminado");
       Serial1.println("SYNC_RTC: ERR - NTP removed");
     }
     else if (cmd.startsWith("set_time")) {
       String timeStr = cmd.substring(8);
       timeStr.trim();
       int year, month, day, hour, minute, second;
       if (sscanf(timeStr.c_str(), "%d-%d-%d %d:%d:%d", &year, &month, &day, &hour, &minute, &second) == 6) {
         if (rtcAvailable) {
           rtc.adjust(DateTime(year, month, day, hour, minute, second));
           awgLog(LOG_INFO, "RTC ajustado manualmente a: " + timeStr);
           Serial1.println("SET_TIME: OK");
         } else {
           awgLog(LOG_WARNING, "RTC no disponible para ajustar hora");
           Serial1.println("SET_TIME: ERR - RTC not available");
         }
       } else {
         awgLog(LOG_WARNING, "Formato SET_TIME inválido. Uso: SET_TIME YYYY-MM-DD HH:MM:SS");
         Serial1.println("SET_TIME: ERR");
       }
     }
    else if (cmdToProcess == "help") {
      printHelp();
    }
    else if (cmd.startsWith("BACKLIGHT:")) {
      // Procesar respuesta del display sobre estado del backlight
      String state = cmd.substring(10);
      state.trim();
      if (state == "ON") {
        if (!backlightOn) {
          digitalWrite(BACKLIGHT_PIN, HIGH);
        }
        backlightOn = true;
        lastScreenActivity = millis();  // Reset timer cuando se enciende
      } else if (state == "OFF") {
        if (backlightOn) {
          digitalWrite(BACKLIGHT_PIN, LOW);
        }
        backlightOn = false;
      }
    }
    else if (cmdToProcess.length() > 0) {
      awgLog(LOG_WARNING, "Comando no reconocido: " + cmdToProcess);
    }

    // Liberar bloqueo de comando crítico si fue establecido
    if (isCriticalCommand) {
      isProcessingCommand = false;
      awgLog(LOG_DEBUG, "🔓 Comando crítico completado: " + cmd);
    }
  }

  void printHelp() {
    String help = "╔══════════════════════════════════════════════════════════════╗\n";
    help += "║             SISTEMA DROPSTER AWG - COMANDOS DISPONIBLES      ║\n";
    help += "╠══════════════════════════════════════════════════════════════╣\n";
    help += "║ 🎛️ CONTROL MANUAL:\n";
    help += "║   • ON/OFF: Encender/Apagar compresor\n";
    help += "║   • ONB/OFFB: Encender/Apagar bomba\n";
    help += "║   • ONV/OFFV: Encender/Apagar ventilador\n";
    help += "║   • ONCF/OFFCF: Encender/Apagar ventilador compresor\n";
    help += "║   • MODE AUTO/MANUAL: Cambiar modo de operación\n";
    help += "║\n";
    help += "║ ⚙️ CONFIGURACIÓN:\n";
    help += "║   • SET_MQTT broker puerto: Cambiar configuración MQTT\n";
    help += "║   • SET_OFFSET X.X: Ajustar offset del sensor ultrasónico (cm)\n";
    help += "║   • SET_TANK_CAPACITY X.X: Ajustar capacidad del tanque (litros)\n";
    help += "║   • FAN_OFFSETS on,off: Ajustar offsets del ventilador compresor (°C).\n";
    help += "║   • RESET_ENERGY: Reinicia la energía acumulada medida por el PZEM.\n";
    help += "║   • SET_MAX_TEMP X.X: Ajustar temperatura máxima del compresor (°C)\n";
    help += "║   • SET_TIME YYYY-MM-DD HH:MM:SS: Ajustar fecha y hora del RTC\n";
    help += "║   • SET_CTRL d,mnOff,mxOn,samp,alpha: Ajustar parámetros (°C,seg,seg,seg,0-1)\n";
    help += "║   • SET_SCREEN_TIMEOUT X: Timeout pantalla reposo en seg (0=deshabilitado).\n";
    help += "║   • SET_LOG_LEVEL X: Nivel logs (0=ERROR,1=WARNING,2=INFO,3=DEBUG)\n";
    help += "║\n";
    help += "║ 📊 MONITOREO:\n";
    help += "║   • TEST: Probar sensor ultrasónico\n";
    help += "║   • SYSTEM_STATUS: Estado completo del sistema\n";
    help += "║   • SENSOR_STATUS sensor: Estado detallado de sensor específico\n";
    help += "║     (BME280, SHT31, PZEM, RTC, TERMISTOR, ULTRASONICO)\n";
    help += "║\n";
    help += "║ 🪣 CALIBRACIÓN:\n";
    help += "║   • CALIBRATE: Iniciar calibración automática (tanque vacío)\n";
    help += "║   • CALIB_ADD X.X: Añadir punto con volumen actual (X.X = litros)\n";
    help += "║   • CALIB_COMPLETE: Finalizar calibración y guardar\n";
    help += "║   • CALIB_LIST: Mostrar tabla de puntos de calibración\n";
    help += "║   • CALIB_SET idx,dist_cm,vol_L: Modificar punto\n";
    help += "║   • CALIB_REMOVE idx: Eliminar punto de calibración\n";
    help += "║   • CALIB_CLEAR: Borrar toda la tabla de calibración\n";
    help += "║   • CALIB_UPLOAD d1:v1,d2:v2,...: Subir tabla desde CSV\n";
    help += "║\n";
    help += "║ 🔧 MANTENIMIENTO:\n";
    help += "║   • DIAG_RECOVER: Diagnóstico y recuperación manual de sensores\n";
    help += "║   • BACKUP_CONFIG: Generar backup JSON de configuración\n";
    help += "║   • CLEAR_STATS: Resetear estadísticas del sistema\n";
    help += "║   • FACTORY_RESET: Reset completo de fábrica\n";
    help += "║   • RESET: Reiniciar sistema\n";
    help += "║\n";
    help += "║ ❓ AYUDA:\n";
    help += "║   • HELP: Mostrar esta ayuda\n";
    help += "╚══════════════════════════════════════════════════════════════╝\n";
    Serial.println(help);
  }

  void testSensor() {
    awgLog(LOG_DEBUG, "=== PRUEBA SENSOR ULTRASÓNICO ===");
    float measurements[TEST_SENSOR_SAMPLES];
    float sum = 0;
    float minVal = 999;
    float maxVal = 0;
    int validMeasurements = 0;

    for (int i = 0; i < TEST_SENSOR_SAMPLES; i++) {
      float dist = getDistance();
      if (dist >= 0) {
        measurements[validMeasurements] = dist;
        sum += dist;
        minVal = min(minVal, dist);
        maxVal = max(maxVal, dist);
        validMeasurements++;
        Serial.println("Medición " + String(i + 1) + ": " + String(dist, 2) + " cm");
      } else {
        Serial.println("Medición " + String(i + 1) + ": ERROR");
      }
      delay(300);
    }

    // Mostrar estadísticas
    if (validMeasurements > 0) {
      float average = sum / validMeasurements;
      float variation = maxVal - minVal;
      Serial.println("=== ESTADÍSTICAS ===");
      Serial.println("Mediciones válidas: " + String(validMeasurements) + "/" + String(TEST_SENSOR_SAMPLES));
      Serial.println("Mínimo: " + String(minVal, 2) + " cm");
      Serial.println("Máximo: " + String(maxVal, 2) + " cm");
      Serial.println("Promedio: " + String(average, 2) + " cm");
      Serial.println("Variación: " + String(variation, 2) + " cm");

      if (variation > 2.0) {  // Alerta si variación > 2cm
        Serial.println("⚠️  Alta variación - Verificar sensor");
      }
    }
    awgLog(LOG_DEBUG, "=== PRUEBA FINALIZADA ===");
  }


  // Función para calcular temperatura del termistor NTC
  float calculateTemperature(float resistance) {
    if (resistance <= 0) return ABSOLUTE_ZERO;  // Valor inválido
    float steinhart;
    steinhart = resistance / NOMINAL_RESISTANCE;  // (R/R0)
    steinhart = log(steinhart);                   // ln(R/R0)
    steinhart /= BETA;                            // 1/B * ln(R/R0)
    steinhart += 1.0 / NOMINAL_TEMP;              // + (1/T0)
    steinhart = 1.0 / steinhart;                  // Invertir para T en Kelvin
    return steinhart - ZERO_CELSIUS;              // Convertir a Celsius
  }
};

AWGSensorManager sensorManager;

// LED RGB: control eficiente por PWM usando LEDC (ESP32)
static bool ledBlinkOn = false;
static unsigned long lastLedToggle = 0;
static unsigned long lastLedUpdate = 0;
static const unsigned long LED_UPDATE_INTERVAL = 200; // ms
static const unsigned long LED_BLINK_INTERVAL = 500; // ms

// Inicializa los canales LEDC y pines usando driver/ledc (ESP-IDF)
void ledInit() {
  // Configurar timer (usar TIMER 0)
  ledc_timer_config_t ledc_timer = {};
  ledc_timer.speed_mode = LEDC_HIGH_SPEED_MODE;
  ledc_timer.duty_resolution = (ledc_timer_bit_t)LEDC_RES; // bits
  ledc_timer.timer_num = LEDC_TIMER_0;
  ledc_timer.freq_hz = LEDC_FREQ;
  ledc_timer.clk_cfg = LEDC_AUTO_CLK;
  ledc_timer_config(&ledc_timer);

  // Configurar canales R,G,B en el mismo timer
  ledc_channel_config_t ch = {};
  ch.gpio_num = LED_R_PIN;
  ch.speed_mode = LEDC_HIGH_SPEED_MODE;
  ch.channel = (ledc_channel_t)LEDC_CHANNEL_R;
  ch.intr_type = LEDC_INTR_DISABLE;
  ch.timer_sel = LEDC_TIMER_0;
  ch.duty = 0;
  ledc_channel_config(&ch);

  ch.gpio_num = LED_G_PIN;
  ch.channel = (ledc_channel_t)LEDC_CHANNEL_G;
  ch.duty = 0;
  ledc_channel_config(&ch);

  ch.gpio_num = LED_B_PIN;
  ch.channel = (ledc_channel_t)LEDC_CHANNEL_B;
  ch.duty = 0;
  ledc_channel_config(&ch);

  setLedColor(0, 0, 0);
}

// Escribe la intensidad (0-255) en cada canal (escala a resolución LEDC)
void setLedColor(uint8_t r, uint8_t g, uint8_t b) {
  uint32_t maxDuty = (1UL << LEDC_RES) - 1UL;
  uint32_t dutyR = (uint32_t)r * maxDuty / 255UL;
  uint32_t dutyG = (uint32_t)g * maxDuty / 255UL;
  uint32_t dutyB = (uint32_t)b * maxDuty / 255UL;
  ledc_set_duty(LEDC_HIGH_SPEED_MODE, (ledc_channel_t)LEDC_CHANNEL_R, dutyR);
  ledc_update_duty(LEDC_HIGH_SPEED_MODE, (ledc_channel_t)LEDC_CHANNEL_R);
  ledc_set_duty(LEDC_HIGH_SPEED_MODE, (ledc_channel_t)LEDC_CHANNEL_G, dutyG);
  ledc_update_duty(LEDC_HIGH_SPEED_MODE, (ledc_channel_t)LEDC_CHANNEL_G);
  ledc_set_duty(LEDC_HIGH_SPEED_MODE, (ledc_channel_t)LEDC_CHANNEL_B, dutyB);
  ledc_update_duty(LEDC_HIGH_SPEED_MODE, (ledc_channel_t)LEDC_CHANNEL_B);
}

// Actualiza el estado del LED según prioridades del sistema
void updateLedState() {
  unsigned long now = millis();
  if (now - lastLedUpdate < LED_UPDATE_INTERVAL) return;
  lastLedUpdate = now;

  // Determinar estado deseado según prioridad (mayor prioridad primero)
  RGBLedState desired = LED_OFF;

  // Prioridad máxima: Sobrecalentamiento compresor -> rojo sólido
  if (alertCompressorTempActive) {
    desired = LED_RED;
  }
  // 2) Portal de configuración activo -> blanco
  else if (portalActive) {
    desired = LED_WHITE;
  }
  // 3) Modo calibración -> naranja
  else if (sensorManager.isInCalibrationMode()) {
    desired = LED_ORANGE;
  }
  else {
    // 4) Falla en sensores -> rojo parpadeante
    bool sensorFail = !(sensorManager.getBmeOnline() && sensorManager.getSht1Online() && sensorManager.getPzemOnline() && sensorManager.getRtcOnline());
    if (sensorFail) {
      desired = LED_RED_BLINK;
    }
    // 5) Conectado a WiFi y MQTT -> verde
    else if (WiFi.status() == WL_CONNECTED && mqttClient.connected()) {
      desired = LED_GREEN;
    }
    // 6) Conectado a WiFi pero NO a MQTT -> azul
    else if (WiFi.status() == WL_CONNECTED && !mqttClient.connected()) {
      desired = LED_BLUE;
    }
    // 7) No conectado a WiFi / modo local -> amarillo
    else {
      desired = LED_YELLOW;
    }
  }

  // Si cambió el estado, reiniciar el parpadeo
  if (desired != currentLedState) {
    currentLedState = desired;
    ledBlinkOn = false;
    lastLedToggle = now;
  }

  // Aplicar color según el estado actual
  switch (currentLedState) {
    case LED_WHITE:
      setLedColor(COLOR_WHITE_R, COLOR_WHITE_G, COLOR_WHITE_B);
      break;
    case LED_ORANGE:
      setLedColor(COLOR_ORANGE_R, COLOR_ORANGE_G, COLOR_ORANGE_B);
      break;
    case LED_RED:
      setLedColor(COLOR_RED_R, COLOR_RED_G, COLOR_RED_B);
      break;
    case LED_RED_BLINK:
      if (now - lastLedToggle >= LED_BLINK_INTERVAL) {
        ledBlinkOn = !ledBlinkOn;
        lastLedToggle = now;
      }
      if (ledBlinkOn) setLedColor(COLOR_RED_R, COLOR_RED_G, COLOR_RED_B);
      else setLedColor(0, 0, 0);
      break;
    case LED_GREEN:
      setLedColor(COLOR_GREEN_R, COLOR_GREEN_G, COLOR_GREEN_B);
      break;
    case LED_BLUE:
      setLedColor(COLOR_BLUE_R, COLOR_BLUE_G, COLOR_BLUE_B);
      break;
    case LED_YELLOW:
      setLedColor(COLOR_YELLOW_R, COLOR_YELLOW_G, COLOR_YELLOW_B);
      break;
    default:
      setLedColor(0, 0, 0);
      break;
  }
}

/* Algoritmo de control automático de temperatura del sistema Dropster AWG.
 * Mantiene la temperatura del evaporador cerca del punto de rocío usando control PID-like.*/
void AWGSensorManager::processControl() {
  if (operationMode != MODE_AUTO) return;  // Solo ejecutar en modo automático
  if (!sht1Online) return;                 // Verificar que el sensor de temperatura del evaporador (SHT31) este disponible
  unsigned long now = millis();
  if (now - lastControlSample < (unsigned long)control_sampling * 1000UL) return;
  lastControlSample = now;

  // Leer temperatura del evaporador
  if (!sht1Online) {
    awgLog(LOG_WARNING, "Sensor SHT31 no disponible - control automático suspendido");
    return;
  }
  float rawTemp = data.sht1Temp;
  if (rawTemp == 0.0f) return;  // lectura inválida

  // Suavizado exponencial
  if (!evapSmoothedInitialized) {
    evapSmoothed = rawTemp;
    evapSmoothedInitialized = true;
  } else {
    evapSmoothed = CONTROL_SMOOTHING_ALPHA * rawTemp + (1.0f - CONTROL_SMOOTHING_ALPHA) * evapSmoothed;
  }
  float dew = data.dewPoint;

  // Banda diferencial (histeresis simétrica alrededor del punto de rocío)
  float onThreshold = dew + (control_deadband / 2.0f);
  float offThreshold = dew - (control_deadband / 2.0f);
  bool compressorOn = (digitalRead(COMPRESSOR_RELAY_PIN) == LOW);
  unsigned long nowMs = now;

  // Si compresor está encendido, verificar tiempo máximo o condición de apagado por histeresis
  if (compressorOn) {
    if (compressorOnStart == 0) compressorOnStart = nowMs;
    // Apagar si excede tiempo máximo continuo
    if (nowMs - compressorOnStart >= (unsigned long)control_max_on * 1000UL) {
      digitalWrite(COMPRESSOR_RELAY_PIN, HIGH);
      awgLog(LOG_DEBUG, "Compresor OFF (tiempo máximo excedido)");
      if (mqttClient.connected()) {
        mqttClient.publish(MQTT_TOPIC_STATUS, "COMP_OFF");
      }
      compressorOffStart = nowMs;
      compressorOnStart = 0;
    } else if (evapSmoothed <= offThreshold) {
      // Apagar por histeresis cuando temperatura cae suficientemente debajo del punto de rocío
      digitalWrite(COMPRESSOR_RELAY_PIN, HIGH);
      awgLog(LOG_DEBUG, "Compresor OFF (histeresis)");
      if (mqttClient.connected()) {
        mqttClient.publish(MQTT_TOPIC_STATUS, "COMP_OFF");
      }
      compressorOffStart = nowMs;
      compressorOnStart = 0;
    }
  } else {
    // Compresor apagado: solo encender si ha pasado el tiempo mínimo de apagado
    if (compressorOffStart == 0) compressorOffStart = nowMs;
    bool minOffElapsed = (nowMs - compressorOffStart >= (unsigned long)control_min_off * 1000UL);
    // Permitir arranque inmediato si se forzó el cambio a AUTO
    if (forceStartOnModeSwitch) {
      minOffElapsed = true;
    }
    if (minOffElapsed) {
      if (evapSmoothed >= onThreshold) {
        digitalWrite(COMPRESSOR_RELAY_PIN, LOW);
        awgLog(LOG_DEBUG, "Compresor ON (control automático)");
        if (mqttClient.connected()) {
          mqttClient.publish(MQTT_TOPIC_STATUS, "COMP_ON");
        }
        compressorOnStart = nowMs;
        compressorOffStart = 0;
        forceStartOnModeSwitch = false;
      }
    } else {
    }
  }
  setVentiladorState(true);  // En modo automático, el ventilador siempre está encendido

  // Publicar estado breve por Serial1 para la pantalla y por MQTT si está conectado
  char buf[64];
  snprintf(buf, sizeof(buf), "CTRL: evap=%.2f dew=%.2f mode=AUTO comp=%s\n",
           evapSmoothed, dew, compressorOn ? "ON" : "OFF");
  Serial1.print(buf);
  if (mqttClient.connected()) {
    mqttClient.publish(MQTT_TOPIC_STATUS, compressorOn ? "AUTO_COMP_ON" : "AUTO_COMP_OFF");
  }
}

// Función para verificar y enviar alertas
void AWGSensorManager::checkAlerts() {
  // Alerta voltaje = 0 (siempre habilitada) - Solo si PZEM está online para evitar falsos positivos al conectar MQTT
  bool isZero = (data.voltage <= VOLTAGE_ZERO_THRESHOLD);
  if (pzemOnline && isZero && !alertVoltageZeroActive && !pzemJustOnline) {
    String message = "El dispositivo Dropster AWG no esta siendo alimentado - Falla Electrica.";
    sendAlert("voltage_zero", message, data.voltage);
    alertVoltageZeroActive = true;
  } else if (pzemOnline && !isZero && alertVoltageZeroActive) {
    alertVoltageZeroActive = false;  // Reset cuando se recupera
  }

  // Reset flag después de primera lectura válida
  if (pzemJustOnline && data.voltage > VOLTAGE_ZERO_THRESHOLD) {
    pzemJustOnline = false;
  }

  // Alerta voltaje bajo
  if (alertVoltageLow.enabled && data.voltage > VOLTAGE_ZERO_THRESHOLD) {  // Solo si hay voltaje
    bool isLow = (data.voltage < alertVoltageLow.threshold);
    if (isLow && !alertVoltageLowActive) {
      String message = "Voltaje bajo detectado. No se recomienda utilizar el dispositivo Dropster AWG con este nivel de voltaje.";
      sendAlert("voltage_low", message, data.voltage);
      alertVoltageLowActive = true;
    } else if (!isLow && alertVoltageLowActive) {
      alertVoltageLowActive = false;  // Reset cuando se recupera
    }
  }
// Alerta tanque lleno
if (alertTankFull.enabled && data.waterVolume >= 0) {
  // Calcular porcentaje usando la función centralizada
  float waterPercent = calculateWaterPercent(data.distance, data.waterVolume);

  bool isFull = (waterPercent >= alertTankFull.threshold);
    if (isFull && !alertTankFullActive) {
      String message = "Tanque lleno detectado, active la salida de agua o no opere el dispositivo Dropster AWG en este estado";
      sendAlert("tank_full", message, waterPercent);
      alertTankFullActive = true;
    } else if (!isFull && alertTankFullActive) {
      alertTankFullActive = false;  // Reset cuando baja
    }
  }

  // Alerta humedad baja (BME280)
  if (alertHumidityLow.enabled && bmeOnline && data.bmeHum > 0) {  // Solo si BME está disponible
    bool isLow = (data.bmeHum < alertHumidityLow.threshold);
    awgLog(LOG_DEBUG, "💨 Verificando humedad baja - Actual: " + String(data.bmeHum, 1) + "%, Umbral: " + String(alertHumidityLow.threshold, 1) + "%, Es baja: " + String(isLow ? "SI" : "NO") + ", Activa: " + String(alertHumidityLowActive ? "SI" : "NO"));
    if (isLow && !alertHumidityLowActive) {
      awgLog(LOG_WARNING, "🚨 ALERTA HUMEDAD BAJA ACTIVADA - Enviando notificación");
      String message = "Humedad baja detectada. Operar el dispositivo Dropster AWG a este nivel de humedad puede presentar baja eficiencia.";
      sendAlert("humidity_low", message, data.bmeHum);
      alertHumidityLowActive = true;
    } else if (!isLow && alertHumidityLowActive) {
      awgLog(LOG_DEBUG, "✅ Alerta humedad baja resuelta - Reset");
      alertHumidityLowActive = false;  // Reset cuando se recupera
    }
  } else {
  }

  // Control automático del ventilador del compresor basado en temperatura (solo en modo AUTO)
  if (operationMode == MODE_AUTO && data.compressorTemp > 0) {  // Solo en modo automático y con lectura válida
    bool compressorFanOn = (digitalRead(COMPRESSOR_FAN_RELAY_PIN) == LOW);
    float tempThresholdOn = maxCompressorTemp - compressorFanTempOnOffset;   // Encender según offset configurable
    float tempThresholdOff = maxCompressorTemp - compressorFanTempOffOffset;  // Apagar según offset configurable

    // Encender ventilador si temperatura está cerca del límite superior
    if (data.compressorTemp >= tempThresholdOn && !compressorFanOn) {
      setCompressorFanState(true);
      awgLog(LOG_DEBUG, "🌡️ VENTILADOR COMPRESOR ENCENDIDO (AUTO) - Temperatura: " + String(data.compressorTemp, 1) + "°C (umbral: " + String(tempThresholdOn, 1) + "°C)");
    }
    // Apagar ventilador si temperatura bajó lo suficiente
    else if (data.compressorTemp <= tempThresholdOff && compressorFanOn) {
      setCompressorFanState(false);
      awgLog(LOG_DEBUG, "🌡️ VENTILADOR COMPRESOR APAGADO (AUTO) - Temperatura: " + String(data.compressorTemp, 1) + "°C (umbral: " + String(tempThresholdOff, 1) + "°C)");
    }
  }

  // Alerta temperatura compresor alta (Termistor NTC)
  if (alertCompressorTemp.enabled && data.compressorTemp > 0) {  // Solo si hay lectura válida
    bool isHigh = (data.compressorTemp >= alertCompressorTemp.threshold);
    if (isHigh && !alertCompressorTempActive) {
      awgLog(LOG_WARNING, "🔥 ALERTA TEMPERATURA COMPRESOR ALTA ACTIVADA - Enviando notificación");
      String message = "Temperatura del compresor demasiado alta. Deteniendo operación para prevenir daños.";
      sendAlert("compressor_temp_high", message, data.compressorTemp);
      alertCompressorTempActive = true;
      // Apagar compresor inmediatamente por seguridad
      digitalWrite(COMPRESSOR_RELAY_PIN, HIGH);
      awgLog(LOG_ERROR, "🚫 SEGURIDAD: Compresor APAGADO por temperatura alta: " + String(data.compressorTemp, 1) + "°C");
      if (mqttClient.connected()) {
        mqttClient.publish(MQTT_TOPIC_STATUS, "COMP_OFF");
      }
      // Actualizar display con el nuevo estado
      sendStatesToDisplay();
    } else if (!isHigh && alertCompressorTempActive) {
      awgLog(LOG_DEBUG, "✅ Temperatura del compresor normalizada");
      alertCompressorTempActive = false;  // Reset cuando baja
    }

    // Si acabamos de apagar el compresor por seguridad, publicar estados inmediatamente
    if (isHigh && !alertCompressorTempActive) {
      awgLog(LOG_DEBUG, "🚨 Publicando estados inmediatamente después de apagado por seguridad");
      publishActuatorStatus();  // Publicar estados actualizados inmediatamente
    }
  }
}

void awgLog(int level, const String& message) {
  if (level <= logLevel) {
    const char* levelStr = "LOG";
    const char* emoji = "";
    switch (level) {
      case LOG_ERROR:
        levelStr = "ERROR";
        emoji = "❌";
        break;
      case LOG_WARNING:
        levelStr = "WARNING";
        emoji = "⚠️";
        break;
      case LOG_INFO:
        levelStr = "INFO";
        emoji = "ℹ️";
        break;
      case LOG_DEBUG:
        levelStr = "DEBUG";
        emoji = "🔍";
        break;
    }
    char msgBuf[LOG_MSG_LEN];
    snprintf(msgBuf, sizeof(msgBuf), "%s %s", emoji, message.c_str());
    Serial.println(msgBuf);  // Imprimir por Serial

    // Guardar en buffer circular (char arrays) - siempre con timestamp completo para logs MQTT
    char fullMsgBuf[LOG_MSG_LEN];
    char timestamp[32];
    if (rtcAvailable) {
      DateTime now = rtc.now();
      snprintf(timestamp, sizeof(timestamp), "%04u-%02u-%02u %02u:%02u:%02u",
               now.year(), now.month(), now.day(), now.hour(), now.minute(), now.second());
    } else {
      snprintf(timestamp, sizeof(timestamp), "%lu", millis() / 1000);
    }
    snprintf(fullMsgBuf, sizeof(fullMsgBuf), "[%s] %s %s", timestamp, levelStr, message.c_str());
    strncpy(logBuffer[logBufferIndex], fullMsgBuf, LOG_MSG_LEN - 1);
    logBuffer[logBufferIndex][LOG_MSG_LEN - 1] = '\0';
    logBufferIndex = (logBufferIndex + 1) % LOG_BUFFER_SIZE;
  }
}

void onMqttMessage(char* topic, byte* payload, unsigned int length) {
  // Validación robusta del mensaje
  if (length == 0 || payload == nullptr) {
    awgLog(LOG_WARNING, "Mensaje MQTT vacío o inválido recibido");
    return;
  }

  try {
    String message;
    for (unsigned int i = 0; i < length; i++) {
      message += (char)payload[i];
    }
    String topicStr = String(topic);

    // Procesar mensaje según el topic
    if (topicStr == MQTT_TOPIC_CONTROL) {
      awgLog(LOG_DEBUG, "🎛️ Comando recibido: " + message);
      sensorManager.processCommand(message);
      awgLog(LOG_DEBUG, "✅ Comando procesado");
    } else {
      awgLog(LOG_WARNING, "📭 Topic no esperado: " + topicStr + " - mensaje ignorado");
    }
  } catch (...) {
    awgLog(LOG_ERROR, "Error crítico en callback MQTT - excepción capturada");
  }
}

void setVentiladorState(bool newState) {
  digitalWrite(VENTILADOR_RELAY_PIN, newState ? LOW : HIGH);
  awgLog(LOG_DEBUG, "Ventilador " + String(newState ? "ON" : "OFF"));
  // Notificar a pantalla vía UART1
  Serial1.println(String("VENT:") + (newState ? "ON" : "OFF"));
  if (mqttClient.connected()) {
    mqttClient.publish(MQTT_TOPIC_STATUS, ("VENT_" + String(newState ? "ON" : "OFF")).c_str());
    // Enviar actualización inmediata a la app por MQTT topic DATA
    StaticJsonDocument<20> updateDoc;
    updateDoc["vs"] = newState ? 1 : 0;
    char updateBuffer[20];
    size_t updateLen = serializeJson(updateDoc, updateBuffer, sizeof(updateBuffer));
    if (updateLen > 0 && updateLen < sizeof(updateBuffer)) {
      mqttClient.publish(MQTT_TOPIC_DATA, updateBuffer, false);  // QoS 0 para actualización inmediata
      awgLog(LOG_DEBUG, "📡 Actualización inmediata VS enviada: " + String(updateBuffer));
    }
  }
}

void setCompressorFanState(bool newState) {
  digitalWrite(COMPRESSOR_FAN_RELAY_PIN, newState ? LOW : HIGH);
  awgLog(LOG_DEBUG, "Ventilador compresor " + String(newState ? "ON" : "OFF"));
  // Notificar a pantalla vía UART1
  Serial1.println(String("CFAN:") + (newState ? "ON" : "OFF"));
  if (mqttClient.connected()) {
    mqttClient.publish(MQTT_TOPIC_STATUS, ("CFAN_" + String(newState ? "ON" : "OFF")).c_str());
    // Enviar actualización inmediata a la app por MQTT topic DATA
    StaticJsonDocument<20> updateDoc;
    updateDoc["cfs"] = newState ? 1 : 0;
    char updateBuffer[20];
    size_t updateLen = serializeJson(updateDoc, updateBuffer, sizeof(updateBuffer));
    if (updateLen > 0 && updateLen < sizeof(updateBuffer)) {
      mqttClient.publish(MQTT_TOPIC_DATA, updateBuffer, false);  // QoS 0 para actualización inmediata
      awgLog(LOG_DEBUG, "📡 Actualización inmediata CFS enviada: " + String(updateBuffer));
    }
  }
}

void setPumpState(bool newState) {
  // Validaciones de seguridad para la bomba
  if (newState) {  // Solo validar al encender
    // Verificar nivel de agua mínimo para bombear
    if (sensorManager.isTankCalibrated()) {
      AWGSensorManager::SensorData_t sensorData = sensorManager.getSensorData();
      float waterPercent = sensorManager.calculateWaterPercent(sensorData.distance, sensorData.waterVolume);
      if (waterPercent < MIN_WATER_LEVEL) {
        awgLog(LOG_ERROR, "🚫 SEGURIDAD: Bomba NO encendida - Nivel de agua insuficiente: " + String(waterPercent, 1) + "% (mín: " + String(MIN_WATER_LEVEL, 1) + "%)");

        // ACTUALIZAR ESTADO INMEDIATO EN LA APP - BOMBA PERMANECE OFF
        if (mqttClient.connected()) {
          StaticJsonDocument<20> updateDoc;
          updateDoc["ps"] = 0;  // Bomba OFF
          char updateBuffer[20];
          size_t updateLen = serializeJson(updateDoc, updateBuffer, sizeof(updateBuffer));
          if (updateLen > 0 && updateLen < sizeof(updateBuffer)) {
            mqttClient.publish(MQTT_TOPIC_DATA, updateBuffer, false);  // QoS 0 para actualización inmediata
            awgLog(LOG_DEBUG, "📡 Actualización inmediata PS enviada (bomba bloqueada por seguridad): " + String(updateBuffer));
          }
        }
        return;
      }
    }
    // Verificar voltaje mínimo
    AWGSensorManager::SensorData_t sensorData = sensorManager.getSensorData();
    if (sensorManager.getPzemOnline() && sensorData.voltage > 0.1 && sensorData.voltage < 100.0) {
      awgLog(LOG_ERROR, "🚫 SEGURIDAD: Bomba NO encendida - Voltaje bajo: " + String(sensorData.voltage, 1) + "V (mín: 100.0V)");

      // Mensaje de error de bomba - ahora se envía para que la app valide
      if (mqttClient.connected()) {
        StaticJsonDocument<150> errorDoc;
        errorDoc["type"] = "pump_error";
        errorDoc["reason"] = "low_voltage";
        errorDoc["message"] = "Voltaje insuficiente para activar la bomba";
        errorDoc["current_voltage"] = sensorData.voltage;
        errorDoc["min_voltage"] = 100.0;
        char errorBuffer[150];
        size_t errorLen = serializeJson(errorDoc, errorBuffer, sizeof(errorBuffer));
        if (errorLen > 0 && errorLen < sizeof(errorBuffer)) {
          mqttClient.publish(MQTT_TOPIC_ERRORS, errorBuffer, false);
          awgLog(LOG_DEBUG, "📤 Mensaje de error de bomba enviado por MQTT: voltaje insuficiente");
        }
      }

      // ACTUALIZAR ESTADO INMEDIATO EN LA APP - BOMBA PERMANECE OFF
      if (mqttClient.connected()) {
        StaticJsonDocument<20> updateDoc;
        updateDoc["ps"] = 0;  // Bomba OFF
        char updateBuffer[20];
        size_t updateLen = serializeJson(updateDoc, updateBuffer, sizeof(updateBuffer));
        if (updateLen > 0 && updateLen < sizeof(updateBuffer)) {
          mqttClient.publish(MQTT_TOPIC_DATA, updateBuffer, false);  // QoS 0 para actualización inmediata
          awgLog(LOG_DEBUG, "📡 Actualización inmediata PS enviada (bomba bloqueada por seguridad): " + String(updateBuffer));
        }
      }
      return;
    }
  }
  digitalWrite(PUMP_RELAY_PIN, newState ? LOW : HIGH);
  awgLog(LOG_DEBUG, "Bomba " + String(newState ? "ON" : "OFF"));
  // Notificar a pantalla vía UART1
  Serial1.println(String("PUMP:") + (newState ? "ON" : "OFF"));
  if (mqttClient.connected()) {
    mqttClient.publish(MQTT_TOPIC_STATUS, ("PUMP_" + String(newState ? "ON" : "OFF")).c_str());
    // Enviar actualización inmediata a la app por MQTT topic DATA
    StaticJsonDocument<20> updateDoc;
    updateDoc["ps"] = newState ? 1 : 0;
    char updateBuffer[20];
    size_t updateLen = serializeJson(updateDoc, updateBuffer, sizeof(updateBuffer));
    if (updateLen > 0 && updateLen < sizeof(updateBuffer)) {
      mqttClient.publish(MQTT_TOPIC_DATA, updateBuffer, false);  // QoS 0 para actualización inmediata
      awgLog(LOG_DEBUG, "📡 Actualización inmediata PS enviada: " + String(updateBuffer));
    }
  }
}

// Publica estado consolidado del sistema con información de conectividad
void publishConsolidatedStatus() {
  if (!mqttClient.connected()) return;
  StaticJsonDocument<300> statusDoc;
  statusDoc["type"] = "system_status";
  statusDoc["status"] = "online";
  statusDoc["compressor"] = digitalRead(COMPRESSOR_RELAY_PIN) == LOW ? 1 : 0;
  statusDoc["ventilador"] = digitalRead(VENTILADOR_RELAY_PIN) == LOW ? 1 : 0;
  statusDoc["compressor_fan"] = digitalRead(COMPRESSOR_FAN_RELAY_PIN) == LOW ? 1 : 0;
  statusDoc["pump"] = digitalRead(PUMP_RELAY_PIN) == LOW ? 1 : 0;
  statusDoc["mode"] = operationMode == MODE_AUTO ? "AUTO" : "MANUAL";
  statusDoc["calibrated"] = sensorManager.isTankCalibrated();
  statusDoc["tank_capacity"] = tankCapacityLiters;
  statusDoc["uptime"] = millis() / 1000;

  // Información de conectividad
  statusDoc["broker"] = mqttBroker;
  statusDoc["port"] = mqttPort;
  statusDoc["topic"] = MQTT_TOPIC_STATUS;
  statusDoc["wifi_connected"] = (WiFi.status() == WL_CONNECTED);

  char statusBuffer[300];
  size_t statusLen = serializeJson(statusDoc, statusBuffer, sizeof(statusBuffer));
  if (statusLen > 0 && statusLen < sizeof(statusBuffer)) {
    mqttClient.publish(MQTT_TOPIC_STATUS, statusBuffer, true);  // QoS 1 para asegurar entrega
    awgLog(LOG_DEBUG, "📊 Estado consolidado enviado - Uptime: " + String(millis() / 1000) + "s");
  }
}

String getSystemStateJSON() {
  StaticJsonDocument<300> doc;
  doc["compressor"] = digitalRead(COMPRESSOR_RELAY_PIN) == LOW ? 1 : 0;
  doc["ventilador"] = digitalRead(VENTILADOR_RELAY_PIN) == LOW ? 1 : 0;
  doc["compressor_fan"] = digitalRead(COMPRESSOR_FAN_RELAY_PIN) == LOW ? 1 : 0;
  doc["pump"] = digitalRead(PUMP_RELAY_PIN) == LOW ? 1 : 0;
  doc["uptime"] = millis() / 1000;
  doc["calibrated"] = sensorManager.isTankCalibrated();

  // Añadir modo y parámetros de control
  doc["mode"] = operationMode == MODE_AUTO ? "AUTO" : "MANUAL";
  doc["tank_capacity"] = tankCapacityLiters;
  JsonObject ctrl = doc.createNestedObject("control");
  ctrl["deadband"] = control_deadband;
  ctrl["min_off"] = control_min_off;
  ctrl["max_on"] = control_max_on;
  ctrl["sampling"] = control_sampling;
  ctrl["alpha"] = control_alpha;
  String output;
  serializeJson(doc, output);
  return output;
}

void setupWiFi() {
  WiFi.mode(WIFI_STA);
  awgLog(LOG_INFO, "🔄 Intentando conectar a red WiFi con credenciales guardadas...");
  String savedSSID = WiFi.SSID();
  awgLog(LOG_DEBUG, "📡 SSID guardado: '" + savedSSID + "' (longitud: " + String(savedSSID.length()) + ")");
  WiFi.begin();  // Conectar con credenciales guardadas en ESP32
  unsigned long start = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - start < 15000) {  // 15 segundos timeout
    delay(500);
    awgLog(LOG_DEBUG, "🔄 Estado WiFi durante conexión: " + String(WiFi.status()));
  }
  if (WiFi.status() == WL_CONNECTED) {
    awgLog(LOG_INFO, "✅ Conectado a WiFi: " + WiFi.SSID() + " (IP: " + WiFi.localIP().toString() + ")");
  } else {
    offlineMode = true;
    awgLog(LOG_INFO, "❌ Modo offline activado - No se pudo conectar a WiFi (verificar credenciales o señal)");
    awgLog(LOG_DEBUG, "🔍 Estado WiFi final: " + String(WiFi.status()) + " - Código de error posible");
  }
}

void setupMQTT() {
  mqttClient.setServer(mqttBroker.c_str(), mqttPort);
  mqttClient.setCallback(onMqttMessage);
  // Only attempt MQTT connection if WiFi is connected
  if (WiFi.status() == WL_CONNECTED) {
    connectMQTT();
  } else {
    awgLog(LOG_INFO, "MQTT: WiFi no conectado, salto intento de conexión MQTT por ahora");
  }
}

void connectMQTT() {
  // Ensure WiFi is connected before attempting MQTT
  if (WiFi.status() != WL_CONNECTED) {
    awgLog(LOG_WARNING, "🔌 Cancelando conexión MQTT: WiFi no conectado");
    return;
  }
  awgLog(LOG_INFO, "🔌 Iniciando conexión MQTT...");
  awgLog(LOG_INFO, "🎯 BROKER MQTT OBJETIVO: " + mqttBroker + ":" + String(mqttPort));
  awgLog(LOG_INFO, "📝 TOPIC MQTT OBJETIVO: " + String(MQTT_TOPIC_DATA));
  awgLog(LOG_INFO, "🔍 Verificando configuración MQTT actual...");
  String clientId = MQTT_CLIENT_ID;  // Client ID simple para conexión MQTT

  // Last Will (mensaje que el broker publicará si el cliente se desconecta inesperadamente)
  const char* willTopic = MQTT_TOPIC_SYSTEM;
  const char* willMessage = "ESP32_AWG_OFFLINE";
  const uint8_t willQos = 1;
  const bool willRetain = true;
  int attempts = 0;
  unsigned long backoff = MQTT_RECONNECT_DELAY;
  const unsigned long maxBackoff = MQTT_MAX_BACKOFF;
  const int maxAttempts = MQTT_MAX_ATTEMPTS;

  while (!mqttClient.connected() && attempts < maxAttempts) {
    awgLog(LOG_INFO, "🔄 Intentando conectar MQTT (intento " + String(attempts + 1) + "/" + String(maxAttempts) + ")");
    bool connected = false;

    if (String(MQTT_USER).length() > 0) {
      awgLog(LOG_DEBUG, "🔐 Usando autenticación MQTT");
      connected = mqttClient.connect(clientId.c_str(), MQTT_USER, MQTT_PASS, willTopic, willQos, willRetain, willMessage);
    } else {
      awgLog(LOG_DEBUG, "🔓 Conexión MQTT sin autenticación");
      connected = mqttClient.connect(clientId.c_str(), willTopic, willQos, willRetain, willMessage);
    }
    if (connected) {
      awgLog(LOG_INFO, "✅ CONEXIÓN MQTT EXITOSA!");
      bool subControl = mqttClient.subscribe(MQTT_TOPIC_CONTROL);                         // Suscribirse al tópico de control (incluye configuración)
      awgLog(LOG_DEBUG, "📡 SUSCRIPCIÓN CONTROL: '" + String(MQTT_TOPIC_CONTROL) + "' - " + (subControl ? "EXITOSA" : "FALLIDA"));
      mqttClient.publish(MQTT_TOPIC_SYSTEM, "ESP32_AWG_ONLINE", true);  // Publicar estado online (retained)
      awgLog(LOG_INFO, "📤 Estado online publicado");
      awgLog(LOG_INFO, "✅ Dispositivo Dropster AWG listo para operar!");
      systemReady = true;
      break;
    } else {
      awgLog(LOG_WARNING, "❌ Fallo conexión MQTT, código de estado: " + String(mqttClient.state()));
      awgLog(LOG_WARNING, "⏳ Reintentando en " + String(backoff) + "ms...");
      attempts++;
      delay(backoff);
      backoff = MQTT_RECONNECT_DELAY;  // Mantener delay fijo de 5 segundos por intento
    }
  }
  if (!mqttClient.connected()) {
    awgLog(LOG_ERROR, "💥 No se pudo conectar a MQTT tras " + String(maxAttempts) + " intentos");
    awgLog(LOG_ERROR, "🔍 Verifica la configuración del broker: " + mqttBroker + ":" + String(mqttPort));
  }
}

void loadMqttConfig() {
  preferences.begin("awg-mqtt", true);
  String savedBroker = preferences.getString("broker", "");
  int savedPort = preferences.getInt("port", 0);
  preferences.end();
  bool hasSavedConfig = (savedBroker.length() > 0 && savedPort > 0);  // Determinar si usar configuración guardada o valores por defecto

  if (hasSavedConfig) {
    mqttBroker = savedBroker;
    mqttPort = savedPort;
    awgLog(LOG_INFO, "🔧 Configuración MQTT CARGADA desde memoria:");
    awgLog(LOG_INFO, "  📡 Broker guardado: " + mqttBroker + ":" + String(mqttPort));
  } else {
    // Usar valores por defecto
    mqttBroker = MQTT_BROKER;
    mqttPort = MQTT_PORT;
    awgLog(LOG_INFO, "🔧 Usando configuración MQTT POR DEFECTO (primera vez):");
    awgLog(LOG_INFO, "  📡 Broker por defecto: " + mqttBroker + ":" + String(mqttPort));
  }
}

void loadAlertConfig() {
  preferences.begin("awg-alerts", true);
  alertTankFull.enabled = preferences.getBool("tankFullEn", true);
  alertTankFull.threshold = preferences.getFloat("tankFullThr", 90.0);
  alertVoltageLow.enabled = preferences.getBool("voltageLowEn", true);
  alertVoltageLow.threshold = preferences.getFloat("voltageLowThr", 100.0);
  alertHumidityLow.enabled = preferences.getBool("humidityLowEn", true);
  alertHumidityLow.threshold = preferences.getFloat("humidityLowThr", 30.0);
  alertVoltageZero.enabled = preferences.getBool("voltageZeroEn", true);
  preferences.end();
  awgLog(LOG_INFO, "Configuración de alertas cargada");
}

void loadSystemStats() {
  preferences.begin("awg-stats", true);
  rebootCount = preferences.getUInt("rebootCount", 0);
  totalUptime = preferences.getULong("totalUptime", 0);
  mqttReconnectCount = preferences.getUInt("mqttReconnects", 0);
  wifiReconnectCount = preferences.getUInt("wifiReconnects", 0);
  preferences.end();
}

void saveSystemStats() {
  preferences.begin("awg-stats", false);
  preferences.putUInt("rebootCount", rebootCount);
  preferences.putULong("totalUptime", totalUptime);
  preferences.putUInt("mqttReconnects", mqttReconnectCount);
  preferences.putUInt("wifiReconnects", wifiReconnectCount);
  preferences.end();
}

void saveAlertConfig() {
  preferences.begin("awg-alerts", false);
  preferences.putBool("tankFullEn", alertTankFull.enabled);
  preferences.putFloat("tankFullThr", alertTankFull.threshold);
  preferences.putBool("voltageLowEn", alertVoltageLow.enabled);
  preferences.putFloat("voltageLowThr", alertVoltageLow.threshold);
  preferences.putBool("humidityLowEn", alertHumidityLow.enabled);
  preferences.putFloat("humidityLowThr", alertHumidityLow.threshold);
  preferences.putBool("voltageZeroEn", alertVoltageZero.enabled);
  preferences.end();
}

void setup() {
  Serial.begin(115200);
  Serial1.begin(115200, SERIAL_8N1, RX1_PIN, TX1_PIN);
  delay(1000);
  awgLog(LOG_INFO, "🚀 Iniciando sistema AWG...");
  awgLog(LOG_INFO, "📋 Versión del firmware: v1.0");
  pinMode(CONFIG_BUTTON_PIN, INPUT_PULLUP);
  // Configurar pin de backlight (GPIO5) y encender por defecto
  pinMode(BACKLIGHT_PIN, OUTPUT);
  digitalWrite(BACKLIGHT_PIN, HIGH);
  backlightOn = true;
  lastScreenActivity = millis();
  loadSystemStats();  // Cargar estadísticas del sistema

  // Test UART communication
  Serial1.println("AWG_INIT:OK");

  // Cargar configuración MQTT antes de inicializar sensores
  awgLog(LOG_INFO, "⚙️ Cargando configuración MQTT...");
  loadMqttConfig();
  loadAlertConfig();
  awgLog(LOG_INFO, "🔧 Inicializando componentes del sistema...");
  // Inicializar LED RGB y demás componentes
  ledInit();
  sensorManager.begin();
  setupWiFi();
  if (WiFi.status() == WL_CONNECTED) {
    setupMQTT();
  } else {
    awgLog(LOG_INFO, "📡 MQTT no inicializado - Sin conexión WiFi");
  }

  // Registrar inicio del sistema
  systemStartTime = millis();
  rebootCount++;
}

void loop() {
  unsigned long now = millis();

  // Verificar timeout de ensamblaje de configuración fragmentada
  if (configAssembleTimeout > 0 && now > configAssembleTimeout) {
    awgLog(LOG_WARNING, "⏰ Timeout de ensamblaje de configuración fragmentada - cancelando");
    // Reset fragments
    for (int i = 0; i < 4; i++) {
      fragmentsReceived[i] = false;
      configFragments[i] = "";
    }
    configAssembleTimeout = 0;
  }

  bool buttonPressed = digitalRead(CONFIG_BUTTON_PIN);
  if (buttonPressed == LOW && buttonPressedLast == HIGH) {
    // Botón recién presionado
    if (now - configPortalTimeout > CONFIG_BUTTON_TIMEOUT) {
      configPortalTimeout = now;
      WiFi.disconnect();
      mqttClient.disconnect();
      delay(1000);
      portalActive = true; // Abrir portal de configuración
      currentLedState = LED_WHITE;
      setLedColor(COLOR_WHITE_R, COLOR_WHITE_G, COLOR_WHITE_B);
      awgLog(LOG_INFO, "Iniciando portal de configuración...");
      wifiManager.setConfigPortalTimeout(WIFI_CONFIG_PORTAL_TIMEOUT);
      if (!wifiManager.startConfigPortal("DropsterAWG_WiFiConfig")) {
        awgLog(LOG_WARNING, "Portal de configuración falló o timeout, continuando sin cambios");
      } else {
        awgLog(LOG_INFO, "Portal cerrado exitosamente");
      }
      // Después de configurar, reconectar
      setupWiFi();
      setupMQTT();
      portalActive = false;
      updateLedState();  // Restaurar LED según estado actual
    }
  }
  buttonPressedLast = buttonPressed;

  if (sensorManager.isInCalibrationMode()) {
    sensorManager.processCalibration();
  }

  if (now - lastRead >= SENSOR_READ_INTERVAL) {
    sensorManager.readSensors();
    lastRead = now;
    sensorManager.processControl();  // Ejecutar control automático NO-BLOQUEANTE inmediatamente después de nuevas lecturas
  }

  // Monitoreo automático de estado de sensores
  if (now - lastSensorStatusCheck >= SENSOR_STATUS_CHECK_INTERVAL) {
    sensorManager.monitorSensorStatus();
    lastSensorStatusCheck = now;
  }

  if (now - lastTransmit >= UART_TRANSMIT_INTERVAL) {
    sensorManager.transmitData();
    lastTransmit = now;
  }

  if (WiFi.status() == WL_CONNECTED) {
    if (!mqttClient.connected()) {
      // Evitar intentar reconectar continuamente: respetar backoff externo
      if (millis() - lastMqttAttempt >= mqttReconnectBackoff) {
        lastMqttAttempt = millis();
        // Incremental backoff exponencial con tope
        mqttReconnectBackoff = min(mqttReconnectBackoff * 2UL, MQTT_MAX_BACKOFF);
        mqttReconnectCount++;
        connectMQTT();
      }
    } else {
      mqttReconnectBackoff = MQTT_RECONNECT_DELAY;  // Reset backoff cuando está conectado
      mqttClient.loop();

      if (now - lastMQTTTransmit >= MQTT_TRANSMIT_INTERVAL) {
        sensorManager.transmitMQTTData();
        lastMQTTTransmit = now;
      }

      if (now - lastHeartbeat >= HEARTBEAT_INTERVAL) {
        publishConsolidatedStatus();  // Publicar estado consolidado del sistema con información de conectividad
        lastHeartbeat = now;
      }
    }
  } else if (now - lastWiFiCheck >= WIFI_CHECK_INTERVAL) {
    wl_status_t currentStatus = WiFi.status();
    awgLog(LOG_DEBUG, "🔄 Verificando WiFi (intento #" + String(wifiReconnectCount + 1) + ") - Estado actual: " + String(currentStatus));
    // Solo intentar reconectar si está completamente desconectado, no si ya está conectando
    if (currentStatus == WL_DISCONNECTED || currentStatus == WL_IDLE_STATUS) {
      awgLog(LOG_DEBUG, "🔄 Intentando reconectar WiFi...");
      WiFi.reconnect();
      wifiReconnectCount++;
      // Verificar resultado después de un breve delay
      delay(100);
      wl_status_t newStatus = WiFi.status();
      if (newStatus == WL_CONNECTED) {
        awgLog(LOG_INFO, "✅ Reconexión WiFi exitosa: " + WiFi.SSID() + " (IP: " + WiFi.localIP().toString() + ")");
        offlineMode = false;
      } else {
        awgLog(LOG_WARNING, "❌ Reconexión WiFi fallida - Estado: " + String(newStatus));
      }
    } else if (currentStatus == WL_CONNECTED) {
      awgLog(LOG_DEBUG, "✅ WiFi ya conectado");
      offlineMode = false;
    } else {
      awgLog(LOG_DEBUG, "⏳ WiFi en estado transitorio: " + String(currentStatus) + " - esperando...");
    }
    lastWiFiCheck = now;
  }
  // Gestionar timeout de pantalla (reposo/backlight) - enviar comandos al display
  if (screenTimeoutSec > 0) {
    if (backlightOn && (now - lastScreenActivity >= (unsigned long)screenTimeoutSec * 1000UL)) {
      Serial1.println("BACKLIGHT:OFF");
      digitalWrite(BACKLIGHT_PIN, LOW);
      backlightOn = false;
      awgLog(LOG_INFO, "Pantalla: backlight apagado por inactivity timeout (" + String(screenTimeoutSec) + "s)");
    }
  }
  sensorManager.handleCommands();
  sensorManager.handleSerialCommands();

  // Recuperación automática de sensores (cada 30 segundos)
  if (now - lastSensorRecoveryCheck >= SENSOR_RECOVERY_INTERVAL) {
    sensorManager.performSensorRecoveryInternal();
    lastSensorRecoveryCheck = now;
  }

  // Guardar estadísticas periódicamente (cada 5 minutos)
  static unsigned long lastStatsSave = 0;
  if (now - lastStatsSave >= STATS_SAVE_INTERVAL) {
    totalUptime += (now - lastStatsSave) / 1000;
    saveSystemStats();
    lastStatsSave = now;
  }
  updateLedState(); // Actualizar LED RGB según estado del sistema
  delay(10);
}
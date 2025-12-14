// Sistema Dropster AWG - Firmware v1.0

// 1. INCLUDES Y LIBRERÍAS
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
#include <driver/ledc.h>      // Control PWM LEDC directo (ESP-IDF) para LED RGB
#include <nvs_flash.h>        // Inicialización de NVS para evitar errores de calibración RF
#include "config.h"           // Archivo de configuración con pines y constantes

// 2. INSTANCIAS GLOBALES Y CONFIGURACIÓN INICIAL
// Gestión de conectividad
WiFiClient espClient;
PubSubClient mqttClient(espClient);

// Hardware del sistema
RTC_DS3231 rtc;
bool rtcAvailable = false;  // Estado del RTC para evitar llamadas repetidas
Preferences preferences;
NewPing sonar(TRIG_PIN, ECHO_PIN, 400);

// 3. VARIABLES GLOBALES DEL SISTEMA
int logLevel = LOG_INFO;
unsigned long configPortalTimeout = 0;
unsigned long portalStartTime = 0;
bool systemReady = false;
bool buttonPressedLast = HIGH;
float smoothedDistance = 0.0;
bool firstDistanceReading = true;
bool offlineMode = false;
bool portalActive = false;
bool sensorFailure = false;
bool configPortalForceActive = false;
bool isProcessingCommand = false;
unsigned long lastCommandTime = 0;
String lastProcessedCommand = "";
String configFragments[CONFIG_FRAGMENT_COUNT];
bool fragmentsReceived[CONFIG_FRAGMENT_COUNT] = {false, false, false, false};
unsigned long configAssembleTimeout = 0;
unsigned long systemStartTime = 0;
unsigned int rebootCount = 0;
unsigned long totalUptime = 0;
unsigned int mqttReconnectCount = 0;
unsigned int wifiReconnectCount = 0;
unsigned long lastSensorRecoveryCheck = 0;
String mqttBroker = MQTT_BROKER;
int mqttPort = MQTT_PORT;

// Modos de operación
enum OperationMode { MODE_MANUAL = 0, MODE_AUTO_PID = 1, MODE_AUTO_TIME = 2 };
OperationMode operationMode = MODE_MANUAL;
enum SelectedAutoMode { AUTO_MODE_PID = 0, AUTO_MODE_TIME = 1 };
SelectedAutoMode selectedAutoMode = AUTO_MODE_PID;
bool forceStartOnModeSwitch = false;

// Parámetros de control automático - mantiene temp evaporador cerca del punto de rocío
float control_deadband = CONTROL_DEADBAND_DEFAULT;
int control_min_off = CONTROL_MIN_OFF_DEFAULT;
int control_max_on = CONTROL_MAX_ON_DEFAULT;
int control_sampling = CONTROL_SAMPLING_DEFAULT;
float control_alpha = CONTROL_ALPHA_DEFAULT;

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
bool alertPumpLowActive = false;         // Alerta de nivel bomba bajo activa

// Configuración de cada tipo de alerta
AlertConfig alertTankFull = { true, ALERT_TANK_FULL_DEFAULT };        // Tanque lleno (>90% por defecto)
AlertConfig alertVoltageLow = { true, ALERT_VOLTAGE_LOW_DEFAULT };    // Voltaje bajo (<100V por defecto)
AlertConfig alertHumidityLow = { true, ALERT_HUMIDITY_LOW_DEFAULT };  // Humedad baja (<40% por defecto)
AlertConfig alertVoltageZero = { true, ALERT_VOLTAGE_ZERO_DEFAULT };  // Voltaje cero (siempre activo)
float maxCompressorTemp = MAX_COMPRESSOR_TEMP;                        // Temperatura máxima del compresor
AlertConfig alertCompressorTemp = { true, maxCompressorTemp };        // Temperatura compresor alta (>100°C por defecto)
AlertConfig alertPumpLow = { true, PUMP_MIN_LEVEL_DEFAULT };          // Nivel bomba bajo (<3.0L por defecto)

// Control de timing del ventilador evaporador
unsigned long evapFanOnStart = 0;   // Timestamp cuando se encendió el ventilador evaporador
unsigned long evapFanOffStart = 0;  // Timestamp cuando se apagó el ventilador evaporador

// Offsets para control del ventilador del evaporador
float evapFanTempOnOffset = EVAP_FAN_TEMP_ON_OFFSET_DEFAULT;    // Offset para encender ventilador (°C)
float evapFanTempOffOffset = EVAP_FAN_TEMP_OFF_OFFSET_DEFAULT;  // Offset para apagar ventilador (°C)
int evapFanMinOff = EVAP_FAN_MIN_OFF_DEFAULT;      // Tiempo mínimo de apagado antes de rearranque (s)
int evapFanMaxOn = EVAP_FAN_MAX_ON_DEFAULT;        // Tiempo máximo de funcionamiento continuo (s)

// Parámetros del modo automático por tiempo
int timeModeCompressorOnTime = TIME_MODE_COMPRESSOR_ON_TIME_DEFAULT;   // Tiempo encendido del compresor en modo tiempo (s)
int timeModeCompressorOffTime = TIME_MODE_COMPRESSOR_OFF_TIME_DEFAULT;  // Tiempo apagado del compresor en modo tiempo (s)
unsigned long timeModeCycleStart = 0; // Timestamp de inicio del ciclo actual en modo tiempo
bool timeModeCompressorState = false; // Estado deseado del compresor en modo tiempo

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

// Configuración del Display
unsigned int screenTimeoutSec = SCREEN_TIMEOUT_DEFAULT; // Timeout de reposo de la pantalla (segundos). 0 = deshabilitado
unsigned long lastScreenActivity = 0;
bool backlightOn = true;

// Variables para control de tiempo del loop principal
unsigned long lastRead = 0;                                 // Última lectura de sensores
unsigned long lastTransmit = 0;                             // Última transmisión UART
unsigned long lastMQTTTransmit = 0;                         // Última transmisión MQTT
unsigned long lastHeartbeat = 0;                            // Último heartbeat MQTT
unsigned long lastWiFiCheck = 0;                            // Última verificación WiFi
unsigned long lastMqttAttempt = 0;                          // Último intento de reconexión MQTT
unsigned long lastMqttPing = 0;                             // Último ping MQTT para mantener conexión
unsigned long mqttReconnectBackoff = MQTT_RECONNECT_DELAY;  // Backoff para reconexión MQTT

// Variables para rastrear últimos estados enviados al display (para envío eficiente)
static bool lastSentCompOn = false;
static bool lastSentVentOn = false;
static bool lastSentCompFanOn = false;
static bool lastSentPumpOn = false;
static String lastSentMode = "";
unsigned long lastSensorStatusCheck = 0;  // Última verificación de estado de sensores

// Protección del compresor
bool compressorProtectionActive = false;        // Flag de protección activa
unsigned long compressorProtectionStart = 0;    // Timestamp de inicio de protección
float compressorMaxCurrent = 0.0f;              // Corriente máxima medida durante protección
unsigned long compressorRetryDelayStart = 0;    // Timestamp de inicio del retraso de reintento
bool compressorTempProtectionActive = false;    // Flag de protección por temperatura activa

// 4. DECLARACIONES ANTICIPADAS DE FUNCIONES
// Configuración del sistema
void setupWiFi();
void setupMQTT();
void connectMQTT();
void reconnectSystem();
void loadMqttConfig();
void loadAlertConfig();
void loadSystemStats();
void saveSystemStats();
void saveAlertConfig();
void saveWiFiCredentials(String ssid, String password);
bool loadWiFiCredentials(String& ssid, String& password);

// Comunicación y logging
void onMqttMessage(char* topic, byte* payload, unsigned int length);
void awgLog(int level, const String& message);
String getSystemStateJSON();

// Control de actuadores
void setVentiladorState(bool newState);
void setCompressorFanState(bool newState);
void setPumpState(bool newState);
void publishState();
void handleCompressorProtection();

// Sistema de alertas
void sendAlert(String type, String message, float value);
void checkAlerts();

bool ensureMqttConnected(); // Función helper para asegurar conexión MQTT
void initRelays();          // Función para inicializar pines de relés

// Funciones helper para logs comunes
void logInfo(const String& message);
void logWarning(const String& message);
void logError(const String& message);
void logDebug(const String& message);

// Declaraciones anticipadas para el control del LED RGB
enum RGBLedState { LED_OFF = 0, LED_GREEN, LED_BLUE, LED_YELLOW, LED_RED, LED_RED_BLINK, LED_ORANGE, LED_WHITE };
RGBLedState currentLedState = LED_OFF;
void ledInit();
void setLedColor(uint8_t r, uint8_t g, uint8_t b);
void updateLedState();

// 5. FUNCIONES DE COMUNICACIÓN Y UTILIDADES
// Reconecta WiFi y MQTT eficientemente
void reconnectSystem() {
  if (WiFi.status() != WL_CONNECTED) {
    setupWiFi();
    delay(500);
  } else {
    logInfo( "WiFi ya conectado");
  }
  if (WiFi.status() == WL_CONNECTED) {
    if (!mqttClient.connected()) {
      setupMQTT();
    } else {
      logInfo( "MQTT ya conectado");
    }
  }
}

void sendAlert(String type, String message, float value) {
   if (!ensureMqttConnected()) {
     logWarning("MQTT no conectado, no se puede enviar alerta: " + type);
     return;
   }
   logDebug("Preparando envío de alerta: " + type + " - Valor: " + String(value, 2));

   // Convierte floats a strings con 2 decimales
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
    mqttClient.publish(MQTT_TOPIC_ALERTS, buffer, true);  // QoS 1 para asegurar entrega
    mqttClient.loop();  // Procesar MQTT para asegurar envío inmediato
  } else {
    logError( "Error al serializar JSON de alerta: " + type);
  }
}

// Función helper para publicar actualizaciones inmediatas por MQTT (QoS 0)
void publishImmediateUpdate(const char* key, int value) {
  if (!ensureMqttConnected()) return;
  StaticJsonDocument<20> doc;
  doc[key] = value;
  char buffer[20];
  size_t len = serializeJson(doc, buffer, sizeof(buffer));
  if (len > 0 && len < sizeof(buffer)) {
    mqttClient.publish(MQTT_TOPIC_DATA, buffer, false);
  }
}

// Función común para publicar estado de actuadores (UART + MQTT)
void publishState() {
   // Leer estados actuales de los relés
   bool compOn = (digitalRead(COMPRESSOR_RELAY_PIN) == LOW);
   bool ventOn = (digitalRead(VENTILADOR_RELAY_PIN) == LOW);
   bool compFanOn = (digitalRead(COMPRESSOR_FAN_RELAY_PIN) == LOW);
   bool pumpOn = (digitalRead(PUMP_RELAY_PIN) == LOW);

   // Determinar modo actual
   String modeStr;
   if (operationMode == MODE_MANUAL) modeStr = "MANUAL";
   else if (operationMode == MODE_AUTO_PID) modeStr = "AUTO_PID";
   else if (operationMode == MODE_AUTO_TIME) modeStr = "AUTO_TIME";
   else modeStr = "UNKNOWN";

   // Enviar por UART al display solo si cambió (envío eficiente)
   if (compOn != lastSentCompOn) {
     String compMsg = String("COMP:") + (compOn ? "ON" : "OFF");
     if (Serial1.availableForWrite() >= compMsg.length() + 1) {
       Serial1.println(compMsg);
       lastSentCompOn = compOn;
     } else {
       logWarning("⚠️ Buffer UART lleno - COMP no enviado");
     }
   }
   if (ventOn != lastSentVentOn) {
     String ventMsg = String("VENT:") + (ventOn ? "ON" : "OFF");
     if (Serial1.availableForWrite() >= ventMsg.length() + 1) {
       Serial1.println(ventMsg);
       lastSentVentOn = ventOn;
     } else {
       logWarning("⚠️ Buffer UART lleno - VENT no enviado");
     }
   }
   if (compFanOn != lastSentCompFanOn) {
     String cfanMsg = String("CFAN:") + (compFanOn ? "ON" : "OFF");
     if (Serial1.availableForWrite() >= cfanMsg.length() + 1) {
       Serial1.println(cfanMsg);
       lastSentCompFanOn = compFanOn;
     } else {
       logWarning("⚠️ Buffer UART lleno - CFAN no enviado");
     }
   }
   if (pumpOn != lastSentPumpOn) {
     String pumpMsg = String("PUMP:") + (pumpOn ? "ON" : "OFF");
     if (Serial1.availableForWrite() >= pumpMsg.length() + 1) {
       Serial1.println(pumpMsg);
       lastSentPumpOn = pumpOn;
     } else {
       logWarning("⚠️ Buffer UART lleno - PUMP no enviado");
     }
   }
   if (modeStr != lastSentMode) {
     String modeMsg = String("MODE:") + modeStr;
     if (Serial1.availableForWrite() >= modeMsg.length() + 1) {
       Serial1.println(modeMsg);
       lastSentMode = modeStr;
     } else {
       logWarning("⚠️ Buffer UART lleno - MODE no enviado");
     }
   }

   // Publicar por MQTT si conectado (siempre, ya que MQTT maneja QoS)
   if (mqttClient.connected()) {
     StaticJsonDocument<STATUS_JSON_SIZE> statusDoc;
     statusDoc["compressor"] = compOn ? 1 : 0;
     statusDoc["ventilador"] = ventOn ? 1 : 0;
     statusDoc["compressor_fan"] = compFanOn ? 1 : 0;
     statusDoc["pump"] = pumpOn ? 1 : 0;
     statusDoc["mode"] = modeStr;
     char statusBuffer[200];
     size_t statusLen = serializeJson(statusDoc, statusBuffer, sizeof(statusBuffer));
     if (statusLen > 0 && statusLen < sizeof(statusBuffer)) {
       mqttClient.publish(MQTT_TOPIC_STATUS, statusBuffer, true);  // QoS 1, retained
       logDebug( "📊 Estado actuadores publicado: " + String(statusBuffer));
     }
   }
}

// Función helper para asegurar conexión MQTT
bool ensureMqttConnected() {
  if (WiFi.status() != WL_CONNECTED) {
    logWarning( "WiFi no conectado - no se puede asegurar MQTT");
    return false;
  }
  if (!mqttClient.connected()) {
    logInfo("MQTT desconectado - intentando reconectar...");
    connectMQTT();
    return mqttClient.connected();
  }
  return true;
}

// Función para inicializar pines de relés
void initRelays() {
  // Configurar pines de relés como OUTPUT y apagarlos (HIGH = OFF)
  pinMode(COMPRESSOR_RELAY_PIN, OUTPUT);
  digitalWrite(COMPRESSOR_RELAY_PIN, HIGH);
  pinMode(VENTILADOR_RELAY_PIN, OUTPUT);
  digitalWrite(VENTILADOR_RELAY_PIN, HIGH);
  pinMode(COMPRESSOR_FAN_RELAY_PIN, OUTPUT);
  digitalWrite(COMPRESSOR_FAN_RELAY_PIN, HIGH);
  pinMode(PUMP_RELAY_PIN, OUTPUT);
  digitalWrite(PUMP_RELAY_PIN, HIGH);
  logDebug( "Pines de relés inicializados");
}

// Funciones helper para logs comunes
void logInfo(const String& message) {
  awgLog(LOG_INFO, message);
}

void logWarning(const String& message) {
  awgLog(LOG_WARNING, message);
}

void logError(const String& message) {
  awgLog(LOG_ERROR, message);
}

void logDebug(const String& message) {
  // Throttling DEBUG: max 1 por segundo
  static unsigned long lastDebugLog = 0;
  unsigned long now = millis();
  if (now - lastDebugLog < 1000) return;
  lastDebugLog = now;
  awgLog(LOG_DEBUG, message);
}

// Función helper para logs de conexión WiFi
void logWiFiConnected() {
  logInfo("✅ WiFi CONECTADO! IP: " + WiFi.localIP().toString());
}

// 6. GESTIÓN DE SENSORES - CLASE AWGSensorManager
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
  bool pzemJustOnline = false;          // Flag para evitar alerta falsa en primera lectura después de marcar online
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

  // Calcula volumen usando interpolación lineal basada en tabla de calibración
  float interpolateVolume(float distance) {
    if (numCalibrationPoints < 2) return 0.0;

    // Validar rango general
    if (distance > calibrationPoints[0].distance + CALIBRATION_DISTANCE_TOLERANCE) return WATER_VOLUME_MIN;
    if (distance < calibrationPoints[numCalibrationPoints - 1].distance - CALIBRATION_DISTANCE_TOLERANCE) return calibrationPoints[numCalibrationPoints - 1].volume;

    // Búsqueda lineal simple
    for (int i = 0; i < numCalibrationPoints - 1; i++) {
      if (distance <= calibrationPoints[i].distance && distance >= calibrationPoints[i + 1].distance) {
        float x0 = calibrationPoints[i].distance, y0 = calibrationPoints[i].volume;
        float x1 = calibrationPoints[i + 1].distance, y1 = calibrationPoints[i + 1].volume;
        if (fabs(x1 - x0) < 1e-6) return y0;
        return y0 + (y1 - y0) * ((x0 - distance) / (x0 - x1));
      }
    }
    return WATER_VOLUME_MIN;
  }

  void calculateTankHeight() {
    if (numCalibrationPoints >= 2) {
      tankHeight = calibrationPoints[0].distance - calibrationPoints[numCalibrationPoints - 1].distance;
    }
  }

  void loadCalibration() {
    // Abrir sesión de preferencias principal una sola vez para eficiencia
    preferences.begin("awg-config", true);
    sensorOffset = preferences.getFloat("offset", 0.0);
    isCalibrated = preferences.getBool("calibrated", false);
    emptyTankDistance = preferences.getFloat("emptyDist", 150.0); // Valor por defecto 150 cm para vacío
    tankHeight = preferences.getFloat("tankHeight", 100.0); // Valor por defecto 100 cm de altura
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

    // Cargar offsets del ventilador del evaporador
    evapFanTempOnOffset = preferences.getFloat("evapFanOnOffset", evapFanTempOnOffset);
    evapFanTempOffOffset = preferences.getFloat("evapFanOffOffset", evapFanTempOffOffset);
    evapFanMinOff = preferences.getInt("evapFanMinOff", evapFanMinOff);
    evapFanMaxOn = preferences.getInt("evapFanMaxOn", evapFanMaxOn);

    // Cargar tiempos del modo cíclico
    timeModeCompressorOnTime = preferences.getInt("timeModeOnTime", timeModeCompressorOnTime);
    timeModeCompressorOffTime = preferences.getInt("timeModeOffTime", timeModeCompressorOffTime);

    // Cargar modo automático seleccionado
    int savedSelectedMode = preferences.getInt("selectedAutoMode", (int)selectedAutoMode);
    selectedAutoMode = (savedSelectedMode == AUTO_MODE_TIME) ? AUTO_MODE_TIME : AUTO_MODE_PID;

    // Cargar modo guardado (0=MANUAL,1=AUTO_PID,2=AUTO_TIME)
    int storedMode = preferences.getInt("mode", (int)operationMode);
    if (storedMode == MODE_AUTO_PID) {
      operationMode = MODE_AUTO_PID;
    } else if (storedMode == MODE_AUTO_TIME) {
      operationMode = MODE_AUTO_TIME;
    } else {
      operationMode = MODE_MANUAL;
    }
    preferences.end();

    // Cargar temperatura máxima del compresor (sesión separada necesaria)
    preferences.begin("awg-max-temp", true);
    maxCompressorTemp = preferences.getFloat("value", MAX_COMPRESSOR_TEMP);
    preferences.end();
    alertCompressorTemp.threshold = maxCompressorTemp;  // Actualizar umbral de alerta con la temperatura máxima cargada

    // Cargar tabla de calibración (sesión separada necesaria)
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
      sortCalibrationPoints();
      calculateTankHeight();
    } else if (numCalibrationPoints >= 2) {
      // Si hay puntos guardados pero no está marcado como calibrado, marcarlo
      isCalibrated = true;
      preferences.begin("awg-config", false);
      preferences.putBool("calibrated", true);
      preferences.end();
      logInfo( "Calibración marcada como completa por puntos existentes");
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

    // Guardar offsets del ventilador del evaporador
    preferences.putFloat("evapFanOnOffset", evapFanTempOnOffset);
    preferences.putFloat("evapFanOffOffset", evapFanTempOffOffset);
    preferences.putInt("evapFanMinOff", evapFanMinOff);
    preferences.putInt("evapFanMaxOn", evapFanMaxOn);

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
        logWarning( "❌ Error: Puntos no en orden descendente");
        return false;
      }
      if (calibrationPoints[i].volume >= calibrationPoints[i + 1].volume) {
        logWarning( "❌ Error: Volúmenes no en orden ascendente");
        return false;
      }
      float distDiff = calibrationPoints[i].distance - calibrationPoints[i + 1].distance;
      float volDiff = calibrationPoints[i + 1].volume - calibrationPoints[i].volume;

      // Solo validar si hay suficiente diferencia
      if (distDiff > 1.0 && volDiff > 1.0) {
        float ratio = distDiff / volDiff;
        // Rango aceptable más amplio
        if (ratio < CALIBRATION_RATIO_MIN || ratio > CALIBRATION_RATIO_MAX) {
          logWarning( "❌ Relación distancia-volumen anómala entre puntos " + String(i) + " y " + String(i + 1));
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

  // Función para verificar si el tanque está lleno (protección para evitar activar compresor)
  bool isTankFull() {
    if (!isCalibrated || isnan(data.waterVolume)) {
      return false;  // Si no está calibrado o no hay datos válidos, asumir no lleno
    }
    float waterPercent = calculateWaterPercent(data.distance, data.waterVolume);
    return (waterPercent >= alertTankFull.threshold);
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

    // Comparar con estado anterior y mostrar alertas solo cuando cambie
    if (currentBmeOnline != prevBmeOnline) {
      if (currentBmeOnline) logInfo("✅ BME280 RECUPERADO");
      else logError("🚨 BME280 DESCONECTADO");
      prevBmeOnline = currentBmeOnline;
    }

    if (currentSht1Online != prevSht1Online) {
      if (currentSht1Online) logInfo("✅ SHT31 RECUPERADO");
      else logError("🚨 SHT31 DESCONECTADO");
      prevSht1Online = currentSht1Online;
    }

    if (currentPzemOnline != prevPzemOnline) {
      if (currentPzemOnline) logInfo("✅ PZEM RECUPERADO");
      else logError("🚨 PZEM DESCONECTADO");
      prevPzemOnline = currentPzemOnline;
    }

    if (currentRtcAvailable != prevRtcAvailable) {
      if (currentRtcAvailable) logInfo("✅ RTC RECUPERADO");
      else logError("🚨 RTC DESCONECTADO");
      prevRtcAvailable = currentRtcAvailable;
    }

    if (currentTermistorOk != prevTermistorOk) {
      if (currentTermistorOk) logInfo("✅ TERMISTOR RECUPERADO");
      else logError("🚨 TERMISTOR ERROR");
      prevTermistorOk = currentTermistorOk;
    }

    if (currentUltrasonicOk != prevUltrasonicOk) {
      if (currentUltrasonicOk) logInfo("✅ ULTRASONICO RECUPERADO");
      else logError("🚨 ULTRASONICO ERROR");
      prevUltrasonicOk = currentUltrasonicOk;
    }
    sensorFailure = !bmeOnline || !sht1Online || !pzemOnline || !rtcOnline; // Actualizar flag de falla de sensores
  }

  AWGSensorManager()
    : sht31_1(&Wire),
      pzem(Serial2, RX2_PIN, TX2_PIN) {
    resetCalibration();
  }

  bool begin() {
    loadCalibration();
    Wire.begin(SDA_PIN, SCL_PIN);
    Wire.setTimeout(50);            // 50ms timeout para evitar bloqueos I2C
    Serial1.begin(115200, SERIAL_8N1, RX1_PIN, TX1_PIN);
    Serial2.begin(9600, SERIAL_8N1, RX2_PIN, TX2_PIN);
    analogReadResolution(12);       // Configurar ADC a 12 bits para el termistor
    initRelays();                   // Inicializar pines de relés
    pinMode(CONFIG_BUTTON_PIN, INPUT_PULLUP);
    buttonPressedLast = HIGH;       // Asumir no presionado al inicio
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
    for (int i = 0; i < PZEM_INIT_ATTEMPTS; i++) {
      float voltage = pzem.voltage();
      if (!isnan(voltage) && voltage > 0) {
        pzemOnline = true;
        break;
      }
      delay(500);
    }
    if (!pzemOnline) {
      logWarning( "⚠️ PZEM-004T no detectado inicialmente");
    }

    // Test inicial del sensor ultrasónico
    float testDistance = getAverageDistance(3);
    if (testDistance >= 0) {
      lastValidDistance = testDistance;
    } else {
      logWarning( "⚠️ Sensor ultrasónico presenta problemas");
    }
    return bmeOnline || sht1Online || pzemOnline;
  }

  void readSensors() {
    if (rtcOnline) {      // Obtener timestamp si RTC está disponible
      DateTime now = rtc.now();
      data.timestamp = String(now.year()) + "-" + String(now.month()) + "-" + String(now.day()) + " " + String(now.hour()) + ":" + String(now.minute()) + ":" + String(now.second());
    } else {
      data.timestamp = "00-00-00 00:00:00";
    }

    // Leer sensores disponibles y actualizar estado online
      if (bmeOnline) {
        data.bmeTemp = validateTemp(bme.readTemperature());
        data.bmeHum = validateHumidity(bme.readHumidity());
        data.bmePres = bme.readPressure() / 100.0;
        // Actualizar online basado en lectura válida
        bmeOnline = (!isnan(data.bmeTemp) && !isnan(data.bmeHum));
      } else {
        data.bmeTemp = NAN;
        data.bmeHum = NAN;
        data.bmePres = NAN;
      }

      if (sht1Online) {
        data.sht1Temp = validateTemp(sht31_1.readTemperature());
        data.sht1Hum = validateHumidity(sht31_1.readHumidity());

        // Aplicar compensación de offset para temperatura del evaporador
        // Solo cuando el compresor está operando y ha pasado el tiempo mínimo
        bool compressorOn = (digitalRead(COMPRESSOR_RELAY_PIN) == LOW);
        if (compressorOn && compressorOnStart > 0 && (millis() - compressorOnStart) > EVAPORATOR_OFFSET_DELAY) {
          data.sht1Temp += EVAPORATOR_TEMP_OFFSET;
        }
        // Actualizar online basado en lectura válida
        sht1Online = (!isnan(data.sht1Temp) && !isnan(data.sht1Hum));
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
        logDebug( "📊 Fallo de lectura PZEM (" + String(consecutiveFailures) + "/" + String(maxConsecutiveFailures) + ")");

        if (consecutiveFailures >= maxConsecutiveFailures) {
          // PZEM desconectado físicamente después de múltiples fallos
          pzemOnline = false;
          consecutiveFailures = 0;
          logWarning( "PZEM-004T desconectado físicamente después de " + String(maxConsecutiveFailures) + " fallos consecutivos");
          data.voltage = NAN;
          data.current = NAN;
          data.power = NAN;  // Energía se mantiene (no se resetea)
        } else {
          // Durante fallos temporales, poner corriente y potencia a NAN, mantener energía
          data.current = NAN;
          data.power = NAN;
          logDebug( "📊 Fallo temporal PZEM - corriente y potencia puestas a NAN, energía mantenida");
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
   
            // Actualizar corriente máxima durante protección del compresor
            if (compressorProtectionActive && data.current > compressorMaxCurrent) {
              compressorMaxCurrent = data.current;
            }
          }
          lastPZEMRead = millis();
    } else if (!pzemOnline) {
      // Intentar detectar PZEM periódicamente (cada 10 segundos)
      if (millis() - lastPZEMDetection > 10000) {
        lastPZEMDetection = millis();
        logDebug( "Intentando detectar PZEM-004T...");

        // Intentar leer voltaje para verificar si el PZEM está conectado
        float testVoltage = pzem.voltage();
        if (!isnan(testVoltage) && testVoltage > VOLTAGE_ZERO_THRESHOLD) {
          pzemOnline = true;
          pzemJustOnline = true;  // Marcar que acaba de conectarse para evitar alerta falsa
          logDebug( "✅ PZEM-004T detectado exitosamente con voltaje: " + String(testVoltage, 1) + "V");
        } else {
          logDebug( "❌ PZEM-004T no detectado, reintentando en 10s");
        }
      }
      // Si no está online, mostrar NAN para indicar no disponible
      data.voltage = NAN;
      data.current = NAN;
      data.power = NAN;
    }

    // Leer temperatura del compresor (termistor NTC)
       // Leer múltiples muestras y promediar
       float sumVoltage = 0;
       int samples = 20;

       for (int i = 0; i < TERMISTOR_SAMPLES; i++) {
         int adcValue = analogRead(TERMISTOR_PIN);
         float voltage = (adcValue * VREF) / ADC_RESOLUTION;
         sumVoltage += voltage;
       }
       float avgVoltage = sumVoltage / samples;
       // Calcular resistencia del termistor usando divisor de voltaje: R_term = R_fixed * (V_meas / (Vcc - V_meas))
       float resistance = NOMINAL_RESISTANCE * (avgVoltage / (VREF - avgVoltage));
       data.compressorTemp = calculateTemperature(resistance); // Calcular temperatura

    // Estados de relés
    data.compressorState = digitalRead(COMPRESSOR_RELAY_PIN) == LOW ? 1 : 0;
    data.ventiladorState = digitalRead(VENTILADOR_RELAY_PIN) == LOW ? 1 : 0;
    data.compressorFanState = digitalRead(COMPRESSOR_FAN_RELAY_PIN) == LOW ? 1 : 0;
    data.pumpState = digitalRead(PUMP_RELAY_PIN) == LOW ? 1 : 0;

    // Cálculos
    data.dewPoint = calculateDewPoint(data.bmeTemp, data.bmeHum);
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
    float sum = 0.0;
    int validSamples = 0;

    for (int i = 0; i < samples; i++) {
      float distance = getDistance();
      if (distance >= 0) {
        sum += distance;
        validSamples++;
      }
      delay(60);
    }
    if (validSamples == 0) return -1.0;
    return sum / validSamples;  // Media simple
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
        // Verificar que hay espacio suficiente en buffer UART antes de enviar (con margen de seguridad)
        if (Serial1.availableForWrite() >= (size_t)len + 10) {  // +10 bytes de margen
          Serial1.write(txBuffer, len);
        } else {
          logWarning( "⚠️ Buffer UART lleno, datos no enviados al display (disponible: " + String(Serial1.availableForWrite()) + " bytes, necesario: " + String(len + 10) + " bytes)");
        }
      }
  }

  void transmitMQTTData() {
    if (!ensureMqttConnected()) {
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

    // Información de conectividad MQTT para la pantalla de conectividad de la app
    doc["mqtt_broker"] = mqttBroker;
    doc["mqtt_port"] = mqttPort;
    doc["mqtt_topic"] = MQTT_TOPIC_DATA;
    doc["mqtt_connected"] = true;         // Si estamos transmitiendo, estamos conectados
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
    logDebug( "=== CALIBRACIÓN INICIADA ===");
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
      logDebug( "✅ Tanque vacío calibrado: " + String(currentDistance, 2) + " cm");
      return;  // Salir después de detectar vacío
    }
  }

  void addCalibrationPoint(float knownVolume) {
    if (numCalibrationPoints >= MAX_CALIBRATION_POINTS) {
      logError( "Máximo de puntos de calibración alcanzado");
      return;
    }

    // Tomar múltiples mediciones para mayor precisión
    float avgDistance = getAverageDistance(10);
    if (avgDistance < 0) {
      logError( "Error en medición de distancia");
      return;
    }
    calibrationPoints[numCalibrationPoints].distance = avgDistance;
    calibrationPoints[numCalibrationPoints].volume = knownVolume;
    numCalibrationPoints++;
    sortCalibrationPoints();
    calculateTankHeight();
    logDebug( "✅ Punto añadido: " + String(avgDistance, 2) + "cm = " + String(knownVolume, 3) + "L");
    Serial.println("📊 Punto " + String(numCalibrationPoints) + ": " + String(avgDistance, 2) + " cm → " + String(knownVolume, 3) + " L");
  }

  void completeCalibration() {
    if (numCalibrationPoints < 2) {
      logError( "Se necesitan al menos 2 puntos de calibración");
      return;
    }

    // Validar consistencia solo al final
    if (!isCalibrationValid()) {
      logError( "Calibración inconsistente - Revise los puntos");
      printCalibrationTable();  // Mostrar tabla para debug
      return;
    }

    isCalibrated = true;
    saveCalibration();
    calibrationMode = false;
    logDebug( "✅ CALIBRACIÓN COMPLETADA");
    logDebug( "Puntos registrados: " + String(numCalibrationPoints));
    printCalibrationTable();

    // Mostrar ejemplo de medición actual
    float currentDistance = getAverageDistance(5);
    if (currentDistance >= 0) {
      float currentVolume = interpolateVolume(currentDistance);
      logDebug( "📏 Medición actual: " + String(currentDistance, 2) + "cm = " + String(currentVolume, 2) + "L");
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
    } else {
      // Tanque no calibrado: devolver 0.0 para evitar propagación de NAN
      return 0.0;
    }
  }

  float calculateWaterPercent(float distance, float volume) {
    if (false && !isnan(volume) && tankCapacityLiters > 0 && volume >= 0) {
      // Método preferido: usar volumen calculado por calibración / capacidad total
      float waterPercent = (volume / tankCapacityLiters) * 100.0;
      // Limitar entre 0% y 100%
      if (waterPercent < WATER_PERCENT_MIN) waterPercent = WATER_PERCENT_MIN;
      if (waterPercent > WATER_PERCENT_MAX) waterPercent = WATER_PERCENT_MAX;
      return waterPercent;
    } else if (tankHeight > 0) {
      // Fallback: cálculo basado en altura (para compatibilidad)
      float effectiveHeight = tankHeight - sensorOffset;
      if (effectiveHeight > 0) {
        float distanceToWater = distance - sensorOffset;
        if (distanceToWater < 0) distanceToWater = 0;
        float waterPercent = ((effectiveHeight - distanceToWater) / effectiveHeight) * 100.0;
        if (waterPercent < WATER_PERCENT_MIN) waterPercent = WATER_PERCENT_MIN;
        if (waterPercent > WATER_PERCENT_MAX) waterPercent = WATER_PERCENT_MAX;
        return waterPercent;
      }
    }
    return NAN;  // Si no hay datos válidos (tanque no calibrado), devolver NAN
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
          logWarning( "Buffer UART1 lleno - comando muy largo, descartando");
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
          logWarning( "Buffer Serial lleno - comando muy largo, descartando");
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
    String modeStr;
    if (operationMode == MODE_MANUAL) modeStr = "MANUAL";
    else if (operationMode == MODE_AUTO_PID) modeStr = "AUTO_PID";
    else if (operationMode == MODE_AUTO_TIME) modeStr = "AUTO_TIME";
    else modeStr = "UNKNOWN";
    status += "Modo: " + modeStr + "\n";
    String selectedModeStr = (selectedAutoMode == AUTO_MODE_PID) ? "PID" : "TIME";
    status += "Modo automático seleccionado: " + selectedModeStr + "\n";
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
    status += "Nivel del Tanque: " + String(calculateWaterPercent(data.distance, data.waterVolume), 1) + " %\n";
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
    logInfo( "=== TABLA DE CALIBRACIÓN ===");
    logInfo( "Distancia (cm) | Volumen (L)");
    logInfo( "----------------------------");
    for (int i = 0; i < numCalibrationPoints; i++) {
      String line = String(calibrationPoints[i].distance, 1) + " cm";
      line += " | " + String(calibrationPoints[i].volume, 1) + " L";

      // Mostrar porcentaje si es el último punto (tanque lleno)
      if (i == 0) {
        line += " (VACÍO)";
      } else if (i == numCalibrationPoints - 1) {
        line += " (LLENO)";
      }
      logInfo( line);
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

  void processUnifiedConfig(String jsonPayload) {
    // Verificar que el JSON esté completo (debe terminar con '}')
    if (!jsonPayload.endsWith("}")) {
      logError( "JSON incompleto - no termina con '}' - Longitud: " + String(jsonPayload.length()));
      Serial1.println("UPDATE_CONFIG: ERR");
      return;
    }

    // Verificar caracteres de escape
    if (jsonPayload.indexOf('\\') != -1) {
      logWarning( "JSON contiene caracteres de escape - removiendo...");
      jsonPayload.replace("\\", "");
    }

    // Verificar si el JSON comienza correctamente
    if (!jsonPayload.startsWith("{")) {
      logError( "JSON malformado - no comienza con '{'");
      Serial1.println("UPDATE_CONFIG: ERR");
      return;
    }

    // Parsear JSON con documento grande para configuración completa
    DynamicJsonDocument doc(CONFIG_JSON_SIZE);
    DeserializationError error = deserializeJson(doc, jsonPayload);

    if (error) {
      logError( "Error parseando JSON unificado: " + String(error.c_str()));
      Serial1.println("UPDATE_CONFIG: ERR");
      return;
    }

    int changeCount = 0;
    bool hasChanges = false;
    bool mqttChanged = false;
    String changesSummary = "";

    // Procesar configuración MQTT
    if (doc.containsKey("mqtt")) {
      JsonObject mqtt = doc["mqtt"];
      String newBroker = mqtt["b"] | MQTT_BROKER;
      int newPort = mqtt["p"] | MQTT_PORT;

      if (newBroker != mqttBroker || newPort != mqttPort) {
        preferences.begin("awg-mqtt", false);
        preferences.putString("broker", newBroker);
        preferences.putInt("port", newPort);
        preferences.end();
        mqttBroker = newBroker;
        mqttPort = newPort;
        mqttChanged = true;
        changesSummary += "MQTT: " + newBroker + ":" + String(newPort) + " | ";
        changeCount++;
        hasChanges = true;
      }
    }

    // Procesar alertas
    if (doc.containsKey("alerts")) {
      JsonObject alerts = doc["alerts"];

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
          }
        } else {
          logWarning( "Umbral de tanque lleno inválido: " + String(newThr, 1) + "% (debe estar entre 50-100%)");
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
          }
        } else {
          logWarning( "Umbral de voltaje bajo inválido: " + String(newThr, 1) + "V (debe estar entre 80-130V)");
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
          }
        } else {
          logWarning( "Umbral de humedad baja inválido: " + String(newThr, 1) + "% (debe estar entre 5-50%)");
        }
      }

      // Nivel bomba bajo
      if (alerts.containsKey("pl")) {  // Clave abreviada
        bool newEn = alerts["pl"];
        String plvStr = alerts["plv"];  // Clave abreviada
        // Reemplazar coma por punto para compatibilidad con parsing decimal
        plvStr.replace(',', '.');
        float newThr = plvStr.toFloat();
        if (newThr >= 1.0 && newThr <= 10.0) {
          if (newEn != alertPumpLow.enabled || fabs(newThr - alertPumpLow.threshold) > 0.01) {
            alertPumpLow.enabled = newEn;
            alertPumpLow.threshold = newThr;
            changeCount++;
            hasChanges = true;
          }
        } else {
          logWarning( "Umbral de nivel bomba bajo inválido: " + String(newThr, 1) + "L (debe estar entre 1-10L)");
        }
      }
    }

    // Procesar parámetros de control
    if (doc.containsKey("control")) {
      JsonObject control = doc["control"];

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
          }
        } else {
          logWarning( "Banda muerta inválida: " + String(newVal, 1) + "°C (debe estar entre 0.5-10.0°C)");
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
          }
        } else {
          logWarning( "Temperatura máxima del compresor inválida: " + String(newTemp, 1) + "°C (debe estar entre 50.0-150.0°C)");
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
          }
        } else {
          logWarning( "Tiempo min apagado inválido: " + String(newVal) + "s (debe estar entre 10-300s)");
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
          }
        } else {
          logWarning( "Tiempo max encendido inválido: " + String(newVal) + "s (debe estar entre 300-7200s)");
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
          }
        } else {
          logWarning( "Intervalo de muestreo inválido: " + String(newVal) + "s (debe estar entre 2-60s)");
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
          }
        } else {
          logWarning( "Factor de suavizado inválido: " + String(newVal, 2) + " (debe estar entre 0.0-1.0)");
        }
      }

      // Timeout del display
      if (control.containsKey("dt")) {  // Clave abreviada
        int newVal = control["dt"] | (screenTimeoutSec / 60);  // Convertir segundos a minutos para comparación
        if (newVal >= 0 && newVal <= 10) {  // 0-10 min
          int newSec = newVal * 60;  // Convertir minutos a segundos
          if (newSec != screenTimeoutSec) {
            screenTimeoutSec = newSec;
            changeCount++;
            hasChanges = true;
          }
        } else {
          logWarning( "Timeout display inválido: " + String(newVal) + " min (debe estar entre 0-10 min)");
        }
      }
    }

    // Procesar configuración del tanque
    if (doc.containsKey("tank")) {
      JsonObject tank = doc["tank"];

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
          }
        } else {
          logWarning( "Capacidad del tanque inválida: " + String(newCapacity, 0) + "L (ignorando)");
        }
      }

      // Estado de calibración
      if (tank.containsKey("cal")) {  // Clave abreviada
        bool newCalibrated = tank["cal"] | isCalibrated;
        if (newCalibrated != isCalibrated) {
          isCalibrated = newCalibrated;
          changeCount++;
          hasChanges = true;
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
              logWarning( "Punto de calibración inválido ignorado: dist=" + String(dist, 1) + ", vol=" + String(vol, 1));
            }
          }
          if (validPoints > 0) {
            numCalibrationPoints = validPoints;
            sortCalibrationPoints();
            calculateTankHeight();
            saveCalibration();
            changeCount++;
            hasChanges = true;
            logInfo( "✅ Puntos agregados exitosamente: " + String(validPoints));
          } else {
            logWarning( "No se encontraron puntos de calibración válidos");
          }
        } else if (points.size() > MAX_CALIBRATION_POINTS) {
          logWarning( "Número de puntos de calibración inválido: " + String(points.size()) + " (máx: " + String(MAX_CALIBRATION_POINTS) + ")");
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
            logDebug( "✅ Offset del sensor actualizado: " + String(newOffset, 1) + "cm");
          } else {
          }
        } else {
          logWarning( "Offset del sensor fuera de rango: " + String(newOffset, 1) + "cm (ignorando)");
        }
      }
    }

    // Reconectar MQTT si cambió la configuración
    if (mqttChanged) {
      logDebug( "🔌 Reconectando MQTT con nueva configuración...");
      mqttClient.disconnect();
      delay(STARTUP_DELAY);
      if (WiFi.status() == WL_CONNECTED) {
        connectMQTT();
      } else {
        logWarning( "No se reconectará a MQTT porque no hay conexión WiFi");
      }

      // Publicar estado de conexión actualizado
      if (mqttClient.connected()) {
        logDebug( "✅ Reconexión MQTT exitosa - Broker actual: " + mqttBroker + ":" + String(mqttPort));
        mqttClient.publish(MQTT_TOPIC_SYSTEM, "ESP32_AWG_ONLINE", true);
        mqttClient.subscribe(MQTT_TOPIC_CONTROL); // Re-suscribirse a los topics después de reconectar
      } else {
        logError( "Reconexión MQTT fallida - Broker configurado: " + mqttBroker + ":" + String(mqttPort));
      }
    }

    // Mostrar resumen de cambios
    if (hasChanges) {
      logDebug( "✅ Configuración unificada actualizada exitosamente (" + String(changeCount) + " cambios)");
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
      Serial.printf("  Timeout display: %s\n", screenTimeoutSec == 0 ? "Desactivado" : (String(screenTimeoutSec) + " segundos").c_str());
      Serial.println("🚨 CONFIGURACIÓN DE ALERTAS:");
      Serial.printf("  Tanque lleno: %s (%.1f%%)\n", alertTankFull.enabled ? "ON" : "OFF", alertTankFull.threshold);
      Serial.printf("  Voltaje bajo: %s (%.1fV)\n", alertVoltageLow.enabled ? "ON" : "OFF", alertVoltageLow.threshold);
      Serial.printf("  Humedad baja: %s (%.1f%%)\n", alertHumidityLow.enabled ? "ON" : "OFF", alertHumidityLow.threshold);
      Serial.printf("  Nivel bomba bajo: %s (%.1fL)\n", alertPumpLow.enabled ? "ON" : "OFF", alertPumpLow.threshold);
      Serial.printf("  Temp alta compresor: (%.1f°C)\n", maxCompressorTemp);
      Serial.println("🪣 CONFIGURACIÓN DEL TANQUE:");
      Serial.printf("  Calibrado: %s\n", isCalibrated ? "SI" : "NO");
      Serial.printf("  Offset ultrasónico: %.1f cm\n", sensorOffset);
      Serial.printf("  Capacidad tanque: %.2f L\n", tankCapacityLiters);
      if (isCalibrated && numCalibrationPoints >= 2) {
        Serial.printf("  Altura tanque: %.1f cm\n", tankHeight);
      }
      Serial.println("================================\n");

      // Guardar configuración en memoria no volátil
      logDebug( "💾 Guardando configuración...");
      saveAlertConfig();
      preferences.begin("awg-config", false);
      preferences.putFloat("ctrl_deadband", control_deadband);
      preferences.putInt("ctrl_min_off", control_min_off);
      preferences.putInt("ctrl_max_on", control_max_on);
      preferences.putInt("ctrl_sampling", control_sampling);
      preferences.putFloat("ctrl_alpha", control_alpha);
      preferences.putInt("screenTimeout", screenTimeoutSec);
      preferences.end();
      logInfo( "💾 Configuración guardada en memoria");
      Serial1.println("UPDATE_CONFIG: OK");
      logDebug( "🎉 Actualización de configuración completada exitosamente");
    } else {
      logDebug( "ℹ️ Configuración unificada recibida sin cambios");
      Serial1.println("UPDATE_CONFIG: OK");
    }
  }

  void processCommand(String& cmd) {
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
        logWarning( "Comando ignorado - Procesando comando crítico anterior: " + lastProcessedCommand);
        return;
      } else {
        logWarning( "⏰ Timeout de comando crítico anterior, procesando nuevo comando");
        isProcessingCommand = false;
      }
    }

    // Sistema de ensamblaje de configuración fragmentada
    if (cmd.startsWith("update_config_part1")) {
      configFragments[0] = cmd.substring(19); // Quitar "update_config_part1"
      fragmentsReceived[0] = true;
      configAssembleTimeout = now + CONFIG_ASSEMBLE_TIMEOUT; // 10 segundos para ensamblar
      return;
    }

    if (cmd.startsWith("update_config_part2")) {
      if (!fragmentsReceived[0]) {
        logWarning( "Parte 2 recibida antes que parte 1 - ignorando");
        return;
      }
      configFragments[1] = cmd.substring(19); // Quitar "update_config_part2"
      fragmentsReceived[1] = true;
      return;
    }

    if (cmd.startsWith("update_config_part3")) {
      if (!fragmentsReceived[0] || !fragmentsReceived[1]) {
        logWarning( "Parte 3 recibida fuera de orden - ignorando");
        return;
      }
      configFragments[2] = cmd.substring(19); // Quitar "update_config_part3"
      fragmentsReceived[2] = true;
      return;
    }

    if (cmd.startsWith("update_config_part4")) {
      if (!fragmentsReceived[0] || !fragmentsReceived[1] || !fragmentsReceived[2]) {
        logWarning( "Parte 4 recibida fuera de orden - ignorando");
        return;
      }
      configFragments[3] = cmd.substring(19); // Quitar "update_config_part4"
      fragmentsReceived[3] = true;
      return;
    }

    if (cmd == "update_config_assemble") {

      // Verificar que todas las partes estén presentes
      bool allPartsReceived = true;
      for (int i = 0; i < 4; i++) {
        if (!fragmentsReceived[i]) {
          allPartsReceived = false;
          logError( "Parte " + String(i+1) + " de configuración faltante");
          break;
        }
      }

      if (!allPartsReceived) {
        logError( "Ensamblaje fallido - partes faltantes");
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
      processUnifiedConfig(fullJson); // Procesar como update_config normal

      // Reset fragments
      for (int i = 0; i < 4; i++) {
        fragmentsReceived[i] = false;
        configFragments[i] = "";
      }
      configAssembleTimeout = 0;
      return;
    }
    bool isCriticalCommand = (cmd.startsWith("update_config") || cmd.startsWith("mode") || cmd == "on" || cmd == "off" || cmd.startsWith("calib_"));     // Marcar comando como en proceso para comandos críticos

    if (isCriticalCommand) {
      isProcessingCommand = true;
      lastCommandTime = now;
      lastProcessedCommand = cmd;
    } else {
      lastProcessedCommand = cmd;
      lastCommandTime = now;
    }
    String cmdToProcess = cmd; // Procesar el comando directamente

    if (cmdToProcess == "on") {
      // Verificar temperatura del compresor antes de encender
      if (data.compressorTemp >= alertCompressorTemp.threshold) {
        logError( "🚫 SEGURIDAD: Compresor NO encendido - Temperatura alta: " + String(data.compressorTemp, 1) + "°C (máx: " + String(alertCompressorTemp.threshold, 1) + "°C)");
        return;
      }
      // Verificar si el tanque está lleno antes de encender
      if (this->isTankFull()) {
        float waterPercent = this->calculateWaterPercent(data.distance, data.waterVolume);
        logError( "🚫 SEGURIDAD: Compresor NO encendido - Tanque lleno: " + String(waterPercent, 1) + "% (umbral: " + String(alertTankFull.threshold, 1) + "%)");
        return;
      }
      operationMode = MODE_MANUAL;
      digitalWrite(COMPRESSOR_RELAY_PIN, LOW);
      logDebug( "Compresor ON");
      if (mqttClient.connected()) {
        mqttClient.publish(MQTT_TOPIC_STATUS, "COMP_ON");
      }
      publishState();
    } else if (cmdToProcess == "off") {
    compressorProtectionActive = false;  // Reset protección al apagar manualmente
      operationMode = MODE_MANUAL;
      digitalWrite(COMPRESSOR_RELAY_PIN, HIGH);
      logDebug( "Compresor OFF");
      if (mqttClient.connected()) {
        mqttClient.publish(MQTT_TOPIC_STATUS, "COMP_OFF");
      }
      publishState();
    } else if (cmdToProcess == "onv") {
      setVentiladorState(true);
    } else if (cmdToProcess == "offv") {
      setVentiladorState(false);
    } else if (cmdToProcess == "oncf") {
      setCompressorFanState(true);
    } else if (cmdToProcess == "offcf") {
      setCompressorFanState(false);
    } else if (cmdToProcess == "onb") {
      operationMode = MODE_MANUAL;
      setPumpState(true);
    } else if (cmdToProcess == "offb") {
      operationMode = MODE_MANUAL;
      setPumpState(false);
    }
    // Cambio de modo explícito
    else if (cmdToProcess == "mode auto" || cmdToProcess == "mode_auto" || cmdToProcess == "mode:auto") {
      // Usar el modo automático seleccionado
      if (selectedAutoMode == AUTO_MODE_TIME) {
        operationMode = MODE_AUTO_TIME;
        logDebug( "Modo cambiado a AUTO_TIME (seleccionado)");
      } else {
        operationMode = MODE_AUTO_PID;
        logDebug( "Modo cambiado a AUTO_PID (seleccionado)");
      }
      preferences.begin("awg-config", false);
      preferences.putInt("mode", (int)operationMode);
      preferences.end();

      String modeStr = (operationMode == MODE_AUTO_TIME) ? "MODE_AUTO_TIME" : "MODE_AUTO_PID";
      if (mqttClient.connected()) mqttClient.publish(MQTT_TOPIC_STATUS, modeStr.c_str());

      if (operationMode == MODE_AUTO_TIME) {
        // ACTIVAR AUTOMÁTICAMENTE COMPRESOR AL CAMBIAR A MODO TIEMPO (ventilador siempre encendido)
        logDebug( "🔄 Activando automáticamente compresor para modo cíclico");
        digitalWrite(COMPRESSOR_RELAY_PIN, LOW);
        logDebug( "Compresor ON");
        setVentiladorState(true);  // Ventilador siempre encendido en modo tiempo
        timeModeCycleStart = millis();  // Reiniciar ciclo
        timeModeCompressorState = true;  // Empezar encendido
      } else {
        // ACTIVAR AUTOMÁTICAMENTE COMPRESOR Y VENTILADOR AL CAMBIAR A MODO PID
        logDebug( "🔄 Activando automáticamente compresor y ventilador para control PID");
        digitalWrite(COMPRESSOR_RELAY_PIN, LOW);
        logDebug( "Compresor ON");
        setVentiladorState(true);
        forceStartOnModeSwitch = true;  // Forzar una evaluación inmediata del controlador (one-shot)
      }

      // Publicar estados actuales inmediatamente para sincronización
      publishState();
    } else if (cmdToProcess == "mode auto_pid" || cmdToProcess == "mode_auto_pid" || cmdToProcess == "mode:auto_pid") {
      operationMode = MODE_AUTO_PID;
      selectedAutoMode = AUTO_MODE_PID;
      logDebug( "Modo cambiado a AUTO_PID");
      preferences.begin("awg-config", false);
      preferences.putInt("mode", (int)operationMode);
      preferences.putInt("selectedAutoMode", (int)selectedAutoMode);
      preferences.end();

      if (mqttClient.connected()) mqttClient.publish(MQTT_TOPIC_STATUS, "MODE_AUTO_PID");

      // ACTIVAR AUTOMÁTICAMENTE COMPRESOR Y VENTILADOR AL CAMBIAR A MODO PID
      logDebug( "🔄 Activando automáticamente compresor y ventilador para control PID");
      digitalWrite(COMPRESSOR_RELAY_PIN, LOW);
      logDebug( "Compresor ON");
      setVentiladorState(true);
      forceStartOnModeSwitch = true;  // Forzar una evaluación inmediata del controlador (one-shot)

      // Publicar estados actuales inmediatamente para sincronización
      publishState();
    } else if (cmdToProcess == "mode auto_time" || cmdToProcess == "mode_auto_time" || cmdToProcess == "mode:auto_time") {
      operationMode = MODE_AUTO_TIME;
      selectedAutoMode = AUTO_MODE_TIME;
      logDebug( "Modo cambiado a AUTO_TIME");
      preferences.begin("awg-config", false);
      preferences.putInt("mode", (int)operationMode);
      preferences.putInt("selectedAutoMode", (int)selectedAutoMode);
      preferences.end();

      if (mqttClient.connected()) mqttClient.publish(MQTT_TOPIC_STATUS, "MODE_AUTO_TIME");

      // ACTIVAR AUTOMÁTICAMENTE COMPRESOR AL CAMBIAR A MODO TIEMPO (ventilador siempre encendido)
      logDebug( "🔄 Activando automáticamente compresor para modo cíclico");
      digitalWrite(COMPRESSOR_RELAY_PIN, LOW);
      logDebug( "Compresor ON");
      setVentiladorState(true);  // Ventilador siempre encendido en modo tiempo
      timeModeCycleStart = millis();  // Reiniciar ciclo
      timeModeCompressorState = true;  // Empezar encendido

      // Publicar estados actuales inmediatamente para sincronización
      publishState();
    } else if (cmdToProcess == "mode manual" || cmdToProcess == "mode_manual" || cmdToProcess == "mode:manual") {
      operationMode = MODE_MANUAL;
      logDebug( "Modo cambiado a MANUAL");
      preferences.begin("awg-config", false);
      preferences.putInt("mode", (int)operationMode);
      preferences.end();
      if (mqttClient.connected()) mqttClient.publish(MQTT_TOPIC_STATUS, "MODE_MANUAL");
      // Cancelar cualquier forceStart pendiente
      forceStartOnModeSwitch = false;
      publishState();
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
        logInfo( "✅ SET_CTRL aplicado: deadband=" + String(control_deadband, 2) + " min_off=" + String(control_min_off) + " max_on=" + String(control_max_on) + " sampling=" + String(control_sampling) + " alpha=" + String(control_alpha, 3));
        Serial1.println("SET_CTRL: OK");
      }
      else {
        logWarning( "SET_CTRL formato inválido. Uso: SET_CTRL d,mn,mx,samp,alpha");
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
           logWarning( "SET_MQTT formato inválido. Uso: SET_MQTT broker puerto");
           Serial1.println("SET_MQTT: ERR");
           return;
         }
         String newBroker = payload.substring(0, spaceIndex);
         String portStr = payload.substring(spaceIndex + 1);
         portStr.trim();
         int newPort = portStr.toInt();
         if (newBroker.length() == 0 || newPort <= 0 || newPort > 65535) {
           logWarning( "SET_MQTT parámetros inválidos. Broker debe ser no vacío, puerto 1-65535");
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
         logInfo( "✅ SET_MQTT aplicado: " + newBroker + ":" + String(newPort));
         Serial1.println("SET_MQTT: OK");
         // Reconectar MQTT
         mqttClient.disconnect();
         delay(STARTUP_DELAY);
         if (WiFi.status() == WL_CONNECTED) {
           connectMQTT();
         } else {
           logWarning( "No se reconectará a MQTT porque no hay conexión WiFi");
         }
       }
       else if (cmd == "test") {
       testSensor();
       }
       else if (cmd == "reset_stats") {
         rebootCount = 0;
         totalUptime = 0;
         mqttReconnectCount = 0;
         wifiReconnectCount = 0;
         saveSystemStats();
         logInfo( "✅ Estadísticas del sistema reseteadas");
       }
      else if (cmd.startsWith("set_offset")) {
          String offsetStr = cmd.substring(10);
          offsetStr.trim();
          float newOffset = offsetStr.toFloat();
          if (newOffset >= -50.0 && newOffset <= 50.0) {
            sensorOffset = newOffset;
            preferences.begin("awg-config", false);
            preferences.putFloat("offset", sensorOffset);
            preferences.end();
            logInfo( "✅ Offset ajustado a: " + String(sensorOffset, 2) + " cm");
          } else {
            logWarning( "Offset del sensor fuera de rango: " + String(newOffset, 1) + " cm (debe estar entre -50.0 y 50.0 cm)");
          }
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
        logWarning( "Nivel de log inválido. Use: 0=ERROR, 1=WARNING, 2=INFO, 3=DEBUG");
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
        logInfo( "✅ Temperatura máxima del compresor ajustada a: " + String(maxCompressorTemp, 1) + "°C");
      } else {
        logWarning( "Temperatura máxima inválida. Use: 50.0-150.0°C");
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
        logInfo( "✅ Capacidad del tanque ajustada a: " + String(tankCapacityLiters, 0) + " L");
      } else {
        logWarning( "Capacidad del tanque inválida. Use: 1-10000 L");
      }
    } else if (cmd.indexOf("set_screen_timeout") != -1) {
      int p = cmd.indexOf("set_screen_timeout");
      int valStart = p + 18; // length of 'set_screen_timeout'
      String valStr = "";
      if (valStart < cmd.length()) valStr = cmd.substring(valStart);
      valStr.trim();
      while (valStr.length() > 0 && (valStr.charAt(0) == ':' || valStr.charAt(0) == '=' || valStr.charAt(0) == ' ')) {
        valStr = valStr.substring(1);
        valStr.trim();
      }

      if (valStr.length() == 0) {
        logInfo( "SET_SCREEN_TIMEOUT: valor actual = " + String(screenTimeoutSec) + " segundos");
      } else {
        long newVal = valStr.toInt();
        if (newVal < 0) {
          logWarning( "SET_SCREEN_TIMEOUT: valor inválido (debe ser >= 0)");
        } else {
          screenTimeoutSec = (unsigned int)newVal;
          preferences.begin("awg-config", false);
          preferences.putInt("screenTimeout", (int)newVal);
          preferences.end();
          // Enviar configuración al display
          Serial1.println("SCREEN_TIMEOUT:" + String(screenTimeoutSec));
          logInfo( "✅ SET_SCREEN_TIMEOUT: timeout de pantalla ajustado a " + String(screenTimeoutSec) + " segundos");
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
          logInfo( "✅ FAN_OFFSETS aplicado: encender=" + String(compressorFanTempOnOffset, 1) + "°C apagar=" + String(compressorFanTempOffOffset, 1) + "°C");
          Serial1.println("FAN_OFFSETS: OK");
        } else {
          logWarning( "FAN_OFFSETS inválidos. Rango: 0.0-" + String(maxCompressorTemp, 1) + "°C, encender < apagar");
          Serial1.println("FAN_OFFSETS: ERR");
        }
      } else {
        logWarning( "FAN_OFFSETS formato inválido. Uso: FAN_OFFSETS on,off");
        Serial1.println("FAN_OFFSETS: ERR");
      }
    } else if (cmd == "calibrate") {
      startCalibration();
    } else if (cmd == "status") {
      Serial.println(getSystemStatus());
    } else if (cmd == "calib_add") {
      logDebug( "Uso: CALIB_ADD <volumen_en_litros>");
    } else if (cmd.startsWith("calib_add")) {
      String volStr = cmd.substring(9);
      volStr.trim();
      float volume = volStr.toFloat();
      addCalibrationPoint(volume);
    } else if (cmd == "calib_upload") {
      logDebug( "Uso: CALIB_UPLOAD d1:v1,d2:v2,...");
    } else if (cmd.startsWith("calib_upload") || cmd.startsWith("CALIB_UPLOAD")) {  // Formato esperado: CALIB_UPLOAD d1:v1,d2:v2,...
      String payload = cmd.substring(12);
      payload.trim();
      if (payload.length() == 0) {
        logInfo( "Uso: CALIB_UPLOAD d1:v1,d2:v2,...");
        logInfo( "Ejemplo: CALIB_UPLOAD 150.5:0.0,120.3:500.0,90.1:1000.0");
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
              logWarning( "Máximo de puntos de calibración alcanzado");
              maxReachedLogged = true;
            }
          }
        }
        if (added > 0) {
          sortCalibrationPoints();
          calculateTankHeight();
          if (numCalibrationPoints >= 2) {
            isCalibrated = true;
            logInfo( "Calibración completada por CALIB_UPLOAD");
          }
          saveCalibration();
          logInfo( "✅ Puntos agregados exitosamente: " + String(added));
        } else {
          logWarning( "CALIB_UPLOAD: no se añadieron puntos válidos");
          logInfo( "Uso: CALIB_UPLOAD d1:v1,d2:v2,...");
        }
      }
    }else if (cmd == "calib_complete") {
       completeCalibration();
    }
    else if (cmd == "wifi_config") {
      logInfo( "Comando WIFI_CONFIG recibido del display");
      WiFi.disconnect();
      mqttClient.disconnect();
      delay(1000);
      portalActive = true;
      currentLedState = LED_WHITE;    // Forzar LED blanco inmediatamente (portal bloqueante)
      setLedColor(COLOR_WHITE_R, COLOR_WHITE_G, COLOR_WHITE_B);
      logInfo( "Iniciando portal de configuración desde display...");
      startCustomConfigPortal();
      setupWiFi();
      setupMQTT();
      portalActive = false;
      updateLedState();       // Restaurar LED según estado actual
    }
    else if (cmd == "reconnect") {
      logInfo( "Comando RECONNECT recibido del display");
      reconnectSystem();
    }
    else if (cmd == "reset_energy") {
      if (!getPzemOnline()) {
        logWarning( "RESET_ENERGY: PZEM no conectado");
      } else {
        pzem.resetEnergy();
        delay(200);
        float after = pzem.energy();
        logInfo( "Energia reiniciada a 0.00 Wh");
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
        // Validar rangos razonables
        if (d >= 0 && d <= 400 && v >= 0 && v <= 10000) {
          calibrationPoints[idx].distance = d;
          calibrationPoints[idx].volume = v;
          if (idx >= numCalibrationPoints) numCalibrationPoints = idx + 1;
          sortCalibrationPoints();
          calculateTankHeight();
          saveCalibration();
          logInfo( "CALIB_SET: punto " + String(idx) + " = " + String(d, 2) + " cm -> " + String(v, 2) + " L");
        } else {
          logWarning( "CALIB_SET: valores fuera de rango - distancia: " + String(d, 1) + " cm (0-400), volumen: " + String(v, 1) + " L (0-10000)");
        }
      } else {
        logWarning( "Uso: CALIB_SET idx,distance_cm,volume_L");
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
        logInfo( "CALIB_REMOVE: eliminado punto " + String(idx));
      } else {
        logWarning( "Uso: CALIB_REMOVE <idx>");
      }
    } else if (cmd == "calib_clear") {
      resetCalibration();
      numCalibrationPoints = 0;
      isCalibrated = false;
      saveCalibration();
      logInfo( "✅ Tabla de calibración vaciada");
    } else if (cmd == "reset") {
      ESP.restart();
    } else if (cmd == "reset_factory") {
      logInfo( "🔄 Iniciando reset de fábrica...");
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
      logInfo( "✅ Reset de fábrica completado. Reiniciando...");
      delay(1000);
      ESP.restart();
    }
    // UPDATE_CONFIG: Procesar configuración unificada completa (solo si no es ACK propio)
    else if (cmd.startsWith("update_config") && cmd.indexOf("\"type\":\"config_ack\"") == -1) {
      logDebug( "📨 UPDATE_CONFIG RECIBIDO - Procesando configuración unificada...");
      logDebug( "📄 Comando completo: '" + cmd + "'");

      // Extraer payload JSON - quitar "update_config"
      String jsonPayload = cmd.substring(12);
      jsonPayload.trim();

      if (jsonPayload.length() == 0) {
        logError( "Payload JSON vacío");
        Serial1.println("UPDATE_CONFIG: ERR");
        return;
      }
      logDebug( "📄 Procesando JSON unificado: " + jsonPayload.substring(0, 50) + (jsonPayload.length() > 50 ? "..." : ""));
      logDebug( "📏 Longitud del payload JSON: " + String(jsonPayload.length()) + " caracteres");
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
      String modeStr;
      if (operationMode == MODE_MANUAL) modeStr = "MANUAL";
      else if (operationMode == MODE_AUTO_PID) modeStr = "AUTO_PID";
      else if (operationMode == MODE_AUTO_TIME) modeStr = "AUTO_TIME";
      else modeStr = "UNKNOWN";
      Serial.printf("║   • Modo operación: %s\n", modeStr.c_str());
      String selectedModeStr = (selectedAutoMode == AUTO_MODE_PID) ? "PID" : "TIME";
      Serial.printf("║   • Modo automático seleccionado: %s\n", selectedModeStr.c_str());
      Serial.printf("║   • Calibración tanque: %s\n", isCalibrated ? "COMPLETA" : "PENDIENTE");
      Serial.println("║");

      // SENSORES Y ACTUADORES
      Serial.println("║ 🔧 SENSORES Y ACTUADORES:");
      Serial.printf("║   • Compresor: %s\n", digitalRead(COMPRESSOR_RELAY_PIN) == LOW ? "ON" : "OFF");
      Serial.printf("║   • Ventilador Evaporador: %s\n", digitalRead(VENTILADOR_RELAY_PIN) == LOW ? "ON" : "OFF");
      Serial.printf("║   • Ventilador Compresor: %s\n", digitalRead(COMPRESSOR_FAN_RELAY_PIN) == LOW ? "ON" : "OFF");
      Serial.printf("║   • Bomba de agua: %s\n", digitalRead(PUMP_RELAY_PIN) == LOW ? "ON" : "OFF");
      Serial.printf("║   • Temp ambiente: %.1f°C\n", this->getSensorData().bmeTemp);
      Serial.printf("║   • Temp compresor: %.1f°C\n", this->getSensorData().compressorTemp);
      Serial.printf("║   • Humedad ambiente: %.1f%%\n", this->getSensorData().bmeHum);
      Serial.printf("║   • Offset sensor ultrasónico: %.1f cm\n", sensorOffset);
      Serial.printf("║   • Agua almacenada: %.2f L\n", this->getSensorData().waterVolume);
      Serial.printf("║   • Nivel del Tanque: %.1f %%\n", calculateWaterPercent(this->getSensorData().distance, this->getSensorData().waterVolume));
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
      Serial.printf("║   • Nivel bomba bajo: %s (%.1fL)\n", alertPumpLow.enabled ? "ACTIVA" : "INACTIVA", alertPumpLow.threshold);
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
     else if (cmd.startsWith("set_time")) {
       String timeStr = cmd.substring(8);
       timeStr.trim();
       int year, month, day, hour, minute, second;
       if (sscanf(timeStr.c_str(), "%d-%d-%d %d:%d:%d", &year, &month, &day, &hour, &minute, &second) == 6) {
         if (rtcAvailable) {
           rtc.adjust(DateTime(year, month, day, hour, minute, second));
           logInfo( "RTC ajustado manualmente a: " + timeStr);
           Serial1.println("SET_TIME: OK");
         } else {
           logWarning( "RTC no disponible para ajustar hora");
           Serial1.println("SET_TIME: ERR - RTC not available");
         }
       } else {
         logWarning( "Formato SET_TIME inválido. Uso: SET_TIME YYYY-MM-DD HH:MM:SS");
         Serial1.println("SET_TIME: ERR");
       }
     } else if (cmd.startsWith("set_time_on")) {
       String timeStr = cmd.substring(11);
       timeStr.trim();
       int newTime = timeStr.toInt();
       if (newTime >= 30 && newTime <= 3600) {  // 30 segundos a 1 hora
         timeModeCompressorOnTime = newTime;
         preferences.begin("awg-config", false);
         preferences.putInt("timeModeOnTime", timeModeCompressorOnTime);
         preferences.end();
         logInfo( "✅ Tiempo encendido modo cíclico ajustado a: " + String(timeModeCompressorOnTime) + " segundos");
         Serial1.println("SET_TIME_ON: OK");
       } else {
         logWarning( "Tiempo encendido inválido. Use: 30-3600 segundos");
         Serial1.println("SET_TIME_ON: ERR");
       }
     } else if (cmd.startsWith("set_time_off")) {
       String timeStr = cmd.substring(12);
       timeStr.trim();
       int newTime = timeStr.toInt();
       if (newTime >= 30 && newTime <= 3600) {  // 30 segundos a 1 hora
         timeModeCompressorOffTime = newTime;
         preferences.begin("awg-config", false);
         preferences.putInt("timeModeOffTime", timeModeCompressorOffTime);
         preferences.end();
         logInfo( "✅ Tiempo apagado modo cíclico ajustado a: " + String(timeModeCompressorOffTime) + " segundos");
         Serial1.println("SET_TIME_OFF: OK");
       } else {
         logWarning( "Tiempo apagado inválido. Use: 30-3600 segundos");
         Serial1.println("SET_TIME_OFF: ERR");
       }
     } else if (cmd.startsWith("set_auto_mode")) {
       // Parsing más robusto: encontrar el espacio después de "set_auto_mode"
       int spaceIndex = cmd.indexOf(' ', 13); // Buscar espacio después de "set_auto_mode" (13 chars)
       String modeStr;
       if (spaceIndex != -1) {
         modeStr = cmd.substring(spaceIndex + 1);
       } else {
         modeStr = cmd.substring(13);
       }
       modeStr.trim();
       modeStr.toUpperCase();
       if (modeStr == "PID") {
         selectedAutoMode = AUTO_MODE_PID;
         preferences.begin("awg-config", false);
         preferences.putInt("selectedAutoMode", (int)selectedAutoMode);
         preferences.end();
         logInfo( "✅ Modo automático seleccionado: PID (control por temperatura)");
         Serial1.println("SET_AUTO_MODE: PID");
       } else if (modeStr == "TIME") {
         selectedAutoMode = AUTO_MODE_TIME;
         preferences.begin("awg-config", false);
         preferences.putInt("selectedAutoMode", (int)selectedAutoMode);
         preferences.end();
         logInfo( "✅ Modo automático seleccionado: TIME (control por tiempo cíclico)");
         Serial1.println("SET_AUTO_MODE: TIME");
       } else {
         logWarning( "Modo automático inválido: '" + modeStr + "'. Use: SET_AUTO_MODE PID o SET_AUTO_MODE TIME");
         Serial1.println("SET_AUTO_MODE: ERR");
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
      logWarning( "Comando no reconocido: " + cmdToProcess);
    }

    // Liberar bloqueo de comando crítico si fue establecido
    if (isCriticalCommand) {
      isProcessingCommand = false;
      logDebug( "🔓 Comando crítico completado: " + cmd);
    }
  }

  void printHelp() {
    String help = "╔══════════════════════════════════════════════════════════════╗\n";
    help += "║             SISTEMA DROPSTER AWG - COMANDOS DISPONIBLES      ║\n";
    help += "╠══════════════════════════════════════════════════════════════╣\n";
    help += "║ 🎛️ CONTROL MANUAL:\n";
    help += "║   • ON/OFF: Encender/Apagar compresor.\n";
    help += "║   • ONB/OFFB: Encender/Apagar bomba.\n";
    help += "║   • ONV/OFFV: Encender/Apagar ventilador.\n";
    help += "║   • ONCF/OFFCF: Encender/Apagar ventilador compresor.\n";
    help += "║   • MODE MANUAL: Cambiar a modo manual.\n";
    help += "║   • MODE AUTO: Cambiar al modo automático seleccionado (PID o TIME).\n";
    help += "║   • MODE AUTO_PID: Cambiar a modo automático PID.\n";
    help += "║   • MODE AUTO_TIME: Cambiar a modo automático por tiempo.\n";
    help += "║   • SET_AUTO_MODE PID/TIME: Seleccionar qué modo usar con MODE AUTO.\n";
    help += "║\n";
    help += "║ ⚙️ CONFIGURACIÓN:\n";
    help += "║   • SET_MQTT broker puerto: Cambiar configuración MQTT.\n";
    help += "║   • SET_OFFSET X.X: Ajustar offset del sensor ultrasónico (cm).\n";
    help += "║   • SET_TANK_CAPACITY X.X: Ajustar capacidad del tanque (litros).\n";
    help += "║   • FAN_OFFSETS on,off: Ajustar offsets del ventilador compresor (°C).\n";
    help += "║   • SET_MAX_TEMP X.X: Ajustar temperatura máxima del compresor (°C).\n";
    help += "║   • SET_TIME YYYY-MM-DD HH:MM:SS: Ajustar fecha y hora del RTC.\n";
    help += "║   • SET_TIME_ON X: Ajustar tiempo encendido modo cíclico (30-3600 seg, defecto 900s=15min).\n";
    help += "║   • SET_TIME_OFF X: Ajustar tiempo apagado modo cíclico (30-3600 seg, defecto 450s=7.5min).\n";
    help += "║   • SET_CTRL d,mnOff,mxOn,samp,alpha: Ajustar parámetros (°C,seg,seg,seg,0-1).\n";
    help += "║   • SET_SCREEN_TIMEOUT X: Timeout pantalla reposo en seg (0=deshabilitado).\n";
    help += "║   • SET_LOG_LEVEL X: Nivel logs (0=ERROR,1=WARNING,2=INFO,3=DEBUG).\n";
    help += "║\n";
    help += "║ 📊 MONITOREO:\n";
    help += "║   • TEST: Probar sensor ultrasónico.\n";
    help += "║   • SYSTEM_STATUS: Estado completo del sistema.\n";
    help += "║   • SENSOR_STATUS sensor: Estado detallado de sensor específico\n";
    help += "║     (BME280, SHT31, PZEM, RTC, TERMISTOR, ULTRASONICO).\n";
    help += "║\n";
    help += "║ 🪣 CALIBRACIÓN:\n";
    help += "║   • CALIBRATE: Iniciar calibración automática (tanque vacío).\n";
    help += "║   • CALIB_ADD X.X: Añadir punto con volumen actual (X.X = litros).\n";
    help += "║   • CALIB_COMPLETE: Finalizar calibración y guardar.\n";
    help += "║   • CALIB_LIST: Mostrar tabla de puntos de calibración.\n";
    help += "║   • CALIB_SET idx,dist_cm,vol_L: Modificar punto.\n";
    help += "║   • CALIB_REMOVE idx: Eliminar punto de calibración.\n";
    help += "║   • CALIB_CLEAR: Borrar toda la tabla de calibración.\n";
    help += "║   • CALIB_UPLOAD d1:v1,d2:v2,...: Subir tabla desde CSV.\n";
    help += "║\n";
    help += "║ 🔧 MANTENIMIENTO:\n";
    help += "║   • RESET: Reiniciar sistema.\n";
    help += "║   • RESET_ENERGY: Reinicia la energía acumulada medida por el PZEM.\n";
    help += "║   • RESET_FACTORY: Reset completo de fábrica (valores predeterminados).\n";
    help += "║   • RESET_STATS: Resetear estadísticas del sistema.\n";
    help += "║\n";
    help += "║ ❓ AYUDA:\n";
    help += "║   • HELP: Mostrar esta ayuda\n";
    help += "╚══════════════════════════════════════════════════════════════╝\n";
    Serial.println(help);
  }

  void testSensor() {
    logDebug( "=== PRUEBA SENSOR ULTRASÓNICO ===");
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
    logDebug( "=== PRUEBA FINALIZADA ===");
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
  RGBLedState desired = LED_OFF; // Determinar estado deseado según prioridad (mayor prioridad primero)

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

/* Control automático: mantiene temp evaporador cerca del punto de rocío (PID o cíclico) */
void AWGSensorManager::processControl() {
  if (operationMode != MODE_AUTO_PID && operationMode != MODE_AUTO_TIME) return;  // Solo ejecutar en modos automáticos
  unsigned long now = millis();

  // Verificar recuperación automática de protección por temperatura
  if (compressorTempProtectionActive) {
    if (data.compressorTemp <= maxCompressorTemp - 20.0f) {
      compressorTempProtectionActive = false;
      logInfo( "Protección temperatura compresor recuperada - temperatura bajó a " + String(data.compressorTemp, 1) + "°C");
    } else {
      return;  // No ejecutar control mientras protección por temperatura activa
    }
  }

  // Modo automático por tiempo
  if (operationMode == MODE_AUTO_TIME) {
    // Ventilador del evaporador siempre encendido en modo tiempo
    if (digitalRead(VENTILADOR_RELAY_PIN) == HIGH) {
      setVentiladorState(true);
    }

    // Control cíclico del compresor
    if (timeModeCycleStart == 0) {
      // Iniciar primer ciclo
      timeModeCycleStart = now;
      timeModeCompressorState = true;  // Empezar encendido
      // Verificar si el tanque está lleno antes de encender
      if (this->isTankFull()) {
        logWarning( "🚫 SEGURIDAD: Compresor NO encendido en modo tiempo - Tanque lleno");
        return;  // Salir sin encender el compresor
      }
      digitalWrite(COMPRESSOR_RELAY_PIN, LOW);
      logDebug( "Modo tiempo: Iniciando ciclo - Compresor ON");
      publishState();
      compressorOnStart = now;
      compressorProtectionActive = true;
      compressorProtectionStart = now;
      compressorMaxCurrent = 0.0f;
    } else {
      // Calcular tiempo transcurrido en el ciclo actual
      unsigned long cycleElapsed = now - timeModeCycleStart;
      unsigned long targetTime = timeModeCompressorState ?
        (unsigned long)timeModeCompressorOnTime * 1000UL :
        (unsigned long)timeModeCompressorOffTime * 1000UL;

      if (cycleElapsed >= targetTime) {
        // Cambiar estado del compresor
        timeModeCompressorState = !timeModeCompressorState;
        timeModeCycleStart = now;

        if (timeModeCompressorState) {
          // Encender compresor
          // Verificar si el tanque está lleno antes de encender
          if (this->isTankFull()) {
            logWarning( "🚫 SEGURIDAD: Compresor NO encendido en modo tiempo - Tanque lleno");
            return;  // Salir sin encender el compresor
          }
          digitalWrite(COMPRESSOR_RELAY_PIN, LOW);
          logDebug( "Modo tiempo: Compresor ON - Ciclo: " + String(timeModeCompressorOnTime) + "s ON");
          publishState();
          compressorOnStart = now;
          compressorProtectionActive = true;
          compressorProtectionStart = now;
          compressorMaxCurrent = 0.0f;
        } else {
          compressorProtectionActive = false;  // Reset protección al apagar en modo tiempo
          // Apagar compresor
          digitalWrite(COMPRESSOR_RELAY_PIN, HIGH);
          logDebug( "Modo tiempo: Compresor OFF - Ciclo: " + String(timeModeCompressorOffTime) + "s OFF");
          publishState();
          compressorOffStart = now;
          compressorOnStart = 0;
        }
      }
    }

    // Control del ventilador del compresor en modo tiempo: encendido cuando compresor APAGADO, apagado cuando compresor ENCENDIDO
    bool compressorOn = (digitalRead(COMPRESSOR_RELAY_PIN) == LOW);
    bool compressorFanOn = (digitalRead(COMPRESSOR_FAN_RELAY_PIN) == LOW);

    if (compressorOn && compressorFanOn) {
      // Compresor encendido: apagar ventilador del compresor
      setCompressorFanState(false);
    } else if (!compressorOn && !compressorFanOn) {
      // Compresor apagado: encender ventilador del compresor
      setCompressorFanState(true);
    }
    return;  // Salir después de procesar modo tiempo
  }

  // Modo automático PID
  if (!sht1Online) return;     // Verificar que el sensor de temperatura del evaporador (SHT31) este disponible
  if (now - lastControlSample < (unsigned long)control_sampling * 1000UL) return;
  lastControlSample = now;

  // Leer temperatura del evaporador
  if (!sht1Online) {
    logWarning( "Sensor SHT31 no disponible - control automático suspendido");
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
      compressorProtectionActive = false;  // Reset protección al apagar por tiempo máximo
    if (nowMs - compressorOnStart >= (unsigned long)control_max_on * 1000UL) {
      digitalWrite(COMPRESSOR_RELAY_PIN, HIGH);
      publishState();
      compressorOffStart = nowMs;
      compressorOnStart = 0;
      compressorProtectionActive = false;  // Reset protección al apagar por histeresis
    } else if (evapSmoothed <= offThreshold) {
      // Apagar por histeresis cuando temperatura cae suficientemente debajo del punto de rocío
      digitalWrite(COMPRESSOR_RELAY_PIN, HIGH);
      publishState();
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
    if (minOffElapsed && compressorRetryDelayStart == 0) {  // No permitir arranque si hay retraso de reintento
      if (evapSmoothed >= onThreshold) {
        // Verificar si el tanque está lleno antes de encender
        if (this->isTankFull()) {
          logWarning( "🚫 SEGURIDAD: Compresor NO encendido en modo PID - Tanque lleno");
          return;  // Salir sin encender el compresor
        }
        digitalWrite(COMPRESSOR_RELAY_PIN, LOW);
        publishState();
        compressorOnStart = nowMs;
        compressorOffStart = 0;
        forceStartOnModeSwitch = false;

        // Iniciar protección del compresor
        compressorProtectionActive = true;
        compressorProtectionStart = nowMs;
        compressorMaxCurrent = 0.0f;
      }
    }
  }
  // Control ventilador evaporador (recircula aire caliente)
  bool evapFanOn = (digitalRead(VENTILADOR_RELAY_PIN) == LOW);

  // Histeresis temperatura: enciende frío, apaga caliente
  if (evapFanOn) {
    if (evapSmoothed >= (dew + evapFanTempOffOffset)) {
      // Apagar cuando temperatura sube suficientemente por encima del punto de rocío
      setVentiladorState(false);
    }
  } else {
    if (evapSmoothed <= (dew - evapFanTempOnOffset)) {
      // Encender cuando temperatura cae suficientemente por debajo del punto de rocío
      setVentiladorState(true);
    }
  }

  // Publicar estado breve por Serial1 para la pantalla
  char buf[64];
  snprintf(buf, sizeof(buf), "CTRL: evap=%.2f dew=%.2f mode=AUTO comp=%s\n",
           evapSmoothed, dew, compressorOn ? "ON" : "OFF");
  Serial1.print(buf);
}

// Función para manejar la protección del compresor
void handleCompressorProtection() {
  unsigned long now = millis();

  // Verificar si hay retraso de reintento activo
  if (compressorRetryDelayStart > 0) {
    if (now - compressorRetryDelayStart >= COMPRESSOR_RETRY_DELAY) {
      // Retraso expirado, resetear y permitir reintento
      compressorRetryDelayStart = 0;
      logInfo( "Retraso de reintento del compresor expirado - listo para reintentar");
    } else {
      // Aún en retraso, no permitir arranque
      return;
    }
  }

  // Verificar protección activa
  if (compressorProtectionActive) {
    if (now - compressorProtectionStart >= COMPRESSOR_PROTECTION_TIME) {
      // Tiempo de protección expirado, evaluar corriente
      compressorProtectionActive = false;

      if (compressorMaxCurrent < COMPRESSOR_MIN_CURRENT) {
        // Arranque fallido - apagar compresor y programar reintento
        digitalWrite(COMPRESSOR_RELAY_PIN, HIGH);
        logWarning( "Protección del compresor: Arranque fallido - corriente máxima: " + String(compressorMaxCurrent, 2) + "A");
        if (mqttClient.connected()) {
          mqttClient.publish(MQTT_TOPIC_STATUS, "COMP_OFF");
        }
        publishState();
        compressorOffStart = now;
        compressorOnStart = 0;

        // Iniciar retraso de reintento
        compressorRetryDelayStart = now;
      } else {
        // Arranque exitoso
        logInfo( "Protección del compresor: Arranque exitoso");
      }
    }
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
      String message = "Voltaje bajo detectado.";
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
      String message = "Tanque lleno detectado";
      sendAlert("tank_full", message, waterPercent);
      alertTankFullActive = true;
    } else if (!isFull && alertTankFullActive) {
      alertTankFullActive = false;  // Reset cuando baja
    }
  }

  // Alerta humedad baja (BME280)
  if (alertHumidityLow.enabled && bmeOnline && data.bmeHum > 0) {  // Solo si BME está disponible
    bool isLow = (data.bmeHum < alertHumidityLow.threshold);
    if (isLow && !alertHumidityLowActive) {
      String message = "Humedad baja detectada. Operar el dispositivo Dropster AWG a este nivel de humedad puede presentar baja eficiencia.";
      sendAlert("humidity_low", message, data.bmeHum);
      alertHumidityLowActive = true;
    } else if (!isLow && alertHumidityLowActive) {
      alertHumidityLowActive = false;  // Reset cuando se recupera
    }
  }

  // Protección automática de la bomba por nivel bajo
  bool pumpOn = (digitalRead(PUMP_RELAY_PIN) == LOW);
  if (pumpOn && alertPumpLow.enabled && !isnan(data.waterVolume) && data.waterVolume <= alertPumpLow.threshold) {
    // Enviar alerta si no está ya activa
    if (!alertPumpLowActive) {
      String message = "Nivel de agua crítico - Bomba apagada por seguridad.";
      sendAlert("pump_low_level", message, data.waterVolume);
      alertPumpLowActive = true;
    }
    setPumpState(false);
  } else if (!pumpOn && alertPumpLowActive) {
    alertPumpLowActive = false;  // Reset cuando se recupera
  }

  // Control automático del ventilador del compresor basado en temperatura (solo en modos automáticos)
  if ((operationMode == MODE_AUTO_PID || operationMode == MODE_AUTO_TIME) && data.compressorTemp > 0) {  // Solo en modos automáticos y con lectura válida
    bool compressorFanOn = (digitalRead(COMPRESSOR_FAN_RELAY_PIN) == LOW);
    float tempThresholdOn = maxCompressorTemp - compressorFanTempOnOffset;   // Encender según offset configurable
    float tempThresholdOff = maxCompressorTemp - compressorFanTempOffOffset;  // Apagar según offset configurable

    // Encender ventilador si temperatura está cerca del límite superior
    if (data.compressorTemp >= tempThresholdOn && !compressorFanOn) {
      setCompressorFanState(true);
    }
    // Apagar ventilador si temperatura bajó lo suficiente
    else if (data.compressorTemp <= tempThresholdOff && compressorFanOn) {
      setCompressorFanState(false);
    }
  }

  // Alerta temperatura compresor alta (Termistor NTC)
   if (alertCompressorTemp.enabled && data.compressorTemp > 0) {  // Solo si hay lectura válida
     bool isHigh = (data.compressorTemp >= alertCompressorTemp.threshold);
     if (isHigh && !alertCompressorTempActive) {
       String message = "Temperatura del compresor demasiado alta.";
       sendAlert("compressor_temp_high", message, data.compressorTemp);
       alertCompressorTempActive = true;
       compressorTempProtectionActive = true;  // Activar protección por temperatura
       // Apagar compresor inmediatamente por seguridad
       digitalWrite(COMPRESSOR_RELAY_PIN, HIGH);
       if (mqttClient.connected()) {
         mqttClient.publish(MQTT_TOPIC_STATUS, "COMP_OFF");
       }
       // Actualizar display con el nuevo estado
       publishState();  // Publicar estados actualizados inmediatamente
     } else if (!isHigh && alertCompressorTempActive) {
       alertCompressorTempActive = false;  // Reset cuando baja
     }
   }
}

void awgLog(int level, const String& message) {
  if (level <= logLevel) {
    const char* levelStr = "LOG";
    switch (level) {
      case LOG_ERROR:
        levelStr = "ERROR";
        break;
      case LOG_WARNING:
        levelStr = "WARNING";
        break;
      case LOG_INFO:
        levelStr = "INFO";
        break;
      case LOG_DEBUG:
        levelStr = "DEBUG";
        break;
    }
    char msgBuf[LOG_MSG_LEN];
    snprintf(msgBuf, sizeof(msgBuf), "%s", message.c_str());
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
    logWarning( "Mensaje MQTT vacío o inválido recibido");
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
      logDebug( "🎛️ Comando recibido: " + message);
      sensorManager.processCommand(message);
      logDebug( "✅ Comando procesado");
    } else {
      logWarning( "📭 Topic no esperado: " + topicStr + " - mensaje ignorado");
    }
  } catch (...) {
    logError( "Error crítico en callback MQTT - excepción capturada");
  }
}

void setVentiladorState(bool newState) {
  digitalWrite(VENTILADOR_RELAY_PIN, newState ? LOW : HIGH);
  logDebug( "Ventilador " + String(newState ? "ON" : "OFF"));
  publishState();
}

void setCompressorFanState(bool newState) {
  digitalWrite(COMPRESSOR_FAN_RELAY_PIN, newState ? LOW : HIGH);
  logDebug( "Ventilador compresor " + String(newState ? "ON" : "OFF"));
  publishState();
}

void setPumpState(bool newState) {
  // Validaciones de seguridad para la bomba
  if (newState) {  // Solo validar al encender
    // Verificar nivel de agua mínimo para bombear
    AWGSensorManager::SensorData_t sensorData = sensorManager.getSensorData();
    if (sensorData.waterVolume < alertPumpLow.threshold) {
      logError("SEGURIDAD: Bomba NO encendida - Nivel de agua insuficiente: " + String(sensorData.waterVolume, 1) + "L (min: " + String(alertPumpLow.threshold, 1) + "L)");
      publishImmediateUpdate("ps", 0);
      return;
    }
  }
  digitalWrite(PUMP_RELAY_PIN, newState ? LOW : HIGH);
  logDebug("Bomba " + String(newState ? "ON" : "OFF"));
  publishState();
}

// Publica estado consolidado del sistema con información de conectividad
void publishConsolidatedStatus() {
  if (!ensureMqttConnected()) return;
  StaticJsonDocument<300> statusDoc;
  statusDoc["type"] = "system_status";
  statusDoc["status"] = "online";
  statusDoc["compressor"] = digitalRead(COMPRESSOR_RELAY_PIN) == LOW ? 1 : 0;
  statusDoc["ventilador"] = digitalRead(VENTILADOR_RELAY_PIN) == LOW ? 1 : 0;
  statusDoc["compressor_fan"] = digitalRead(COMPRESSOR_FAN_RELAY_PIN) == LOW ? 1 : 0;
  statusDoc["pump"] = digitalRead(PUMP_RELAY_PIN) == LOW ? 1 : 0;
  String modeStr;
  if (operationMode == MODE_MANUAL) modeStr = "MANUAL";
  else if (operationMode == MODE_AUTO_PID) modeStr = "AUTO_PID";
  else if (operationMode == MODE_AUTO_TIME) modeStr = "AUTO_TIME";
  else modeStr = "UNKNOWN";
  statusDoc["mode"] = modeStr;
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
    logDebug( "📊 Estado consolidado enviado - Uptime: " + String(millis() / 1000) + "s");
  }
}

String getSystemStateJSON() {
  StaticJsonDocument<300> doc;
  doc["compressor"] = digitalRead(COMPRESSOR_RELAY_PIN) == LOW ? 1 : 0;
  doc["ventilador"] = digitalRead(VENTILADOR_RELAY_PIN) == LOW ? 1 : 0;
  doc["compressor_fan"] = digitalRead(COMPRESSOR_FAN_RELAY_PIN) == LOW ? 1 : 0;
  doc["pump"] = digitalRead(PUMP_RELAY_PIN) == LOW ? 1 : 0;
  doc["uptime"] = millis() / 1000;

  // Añadir modo y parámetros de control
  String modeStr;
  if (operationMode == MODE_MANUAL) modeStr = "MANUAL";
  else if (operationMode == MODE_AUTO_PID) modeStr = "AUTO_PID";
  else if (operationMode == MODE_AUTO_TIME) modeStr = "AUTO_TIME";
  else modeStr = "UNKNOWN";
  doc["mode"] = modeStr;
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
  logInfo( "🔄 Intentando conectar a red WiFi con credenciales guardadas...");

  // Verificar si hay credenciales guardadas en preferencias
  String savedSSID, savedPass;
  bool hasCredentials = loadWiFiCredentials(savedSSID, savedPass);

  if (!hasCredentials) {
    logWarning( "❌ No hay credenciales WiFi guardadas - Operando en modo local");
    offlineMode = true;
    return;
  }
  logInfo( "📡 Conectando a WiFi: " + savedSSID);
  WiFi.begin(savedSSID.c_str(), savedPass.c_str());

  // Esperar conexión con timeout
  unsigned long startAttempt = millis();
  const unsigned long timeout = 15000; // 15 segundos timeout

  while (WiFi.status() != WL_CONNECTED && millis() - startAttempt < timeout) {
    delay(500);
  }

  if (WiFi.status() == WL_CONNECTED) {
    logWiFiConnected();
    offlineMode = false;
  } else {
    logError( "❌ WiFi NO CONECTADO después de " + String(timeout/1000) + "s - Estado: " + String(WiFi.status()));
    logInfo( "🏠 Operando en modo local");
    offlineMode = true;
  }
}

void setupMQTT() {
  mqttClient.setServer(mqttBroker.c_str(), mqttPort);
  mqttClient.setCallback(onMqttMessage);
  // Configuración optimizada para estabilidad mejorada
  mqttClient.setKeepAlive(90);  // Keep-alive reducido a 90 segundos para mejor responsividad
  mqttClient.setSocketTimeout(20);  // Timeout de socket optimizado
  mqttClient.setBufferSize(1024);  // Buffer aumentado para mensajes largos
  if (WiFi.status() == WL_CONNECTED) {
    connectMQTT();
  } else {
    logInfo( "MQTT: WiFi no conectado, salto intento de conexión MQTT por ahora");
  }
}

void connectMQTT() {
  if (WiFi.status() != WL_CONNECTED) {
    logWarning( "🔌 Cancelando conexión MQTT: WiFi no conectado");
    return;
  }
  logInfo( "🔌 Iniciando conexión MQTT...");
  logInfo( "🎯 BROKER MQTT OBJETIVO: " + mqttBroker + ":" + String(mqttPort));
  logInfo( "📝 TOPIC MQTT OBJETIVO: " + String(MQTT_TOPIC_DATA));
  String clientId = String(MQTT_CLIENT_ID) + "_" + String(random(1000, 9999));  // Client ID único para evitar conflictos

  // Mensaje que el broker publicará si el cliente se desconecta inesperadamente
  const char* willTopic = MQTT_TOPIC_SYSTEM;
  const char* willMessage = "ESP32_AWG_OFFLINE";
  const uint8_t willQos = 1;
  const bool willRetain = true;

  // Solo un intento por llamada - reconexión manejada en loop principal
  logInfo( "🔄 Intentando conectar MQTT con Client ID: " + clientId);
  bool connected = false;

  // Intentar conexión con timeout
  unsigned long connectStart = millis();
  if (String(MQTT_USER).length() > 0) {
    connected = mqttClient.connect(clientId.c_str(), MQTT_USER, MQTT_PASS, willTopic, willQos, willRetain, willMessage);
  } else {
    connected = mqttClient.connect(clientId.c_str(), willTopic, willQos, willRetain, willMessage);
  }
  unsigned long connectTime = millis() - connectStart;

  if (connected) {
    logInfo( "✅ CONEXIÓN MQTT EXITOSA!");
    // Suscribirse a todos los topics necesarios
    mqttClient.subscribe(MQTT_TOPIC_CONTROL);
    mqttClient.publish(MQTT_TOPIC_SYSTEM, "ESP32_AWG_ONLINE", true);  // Publicar estado online (retained)
    logInfo( "📤 Estado online publicado");
    logInfo( "✅ Dispositivo Dropster AWG listo para operar!");
    systemReady = true;
  } else {
    int errorCode = mqttClient.state();
    String errorMsg = getMqttErrorMessage(errorCode);
    logError( "❌ CONEXIÓN MQTT FALLIDA!");
    logError( "   Código de error: " + String(errorCode));
    logError( "   Descripción: " + errorMsg);
    logError( "   Broker: " + mqttBroker + ":" + String(mqttPort));
    logError( "   Tiempo de conexión: " + String(connectTime) + "ms");

    // Diagnóstico adicional para errores comunes
    if (errorCode == MQTT_CONNECT_FAILED) {
      logError( "   🔍 Diagnóstico: Broker unreachable - verificar conexión a internet");
    } else if (errorCode == MQTT_CONNECTION_LOST) {
      logError( "   🔍 Diagnóstico: Conexión perdida - posible problema de red");
    } else if (errorCode == MQTT_CONNECT_BAD_CREDENTIALS) {
      logError( "   🔍 Diagnóstico: Credenciales inválidas - verificar usuario/contraseña");
    }
    logWarning( "🔄 Intentando reconexión en " + String(mqttReconnectBackoff/1000) + " segundos...");
  }
}

// Función auxiliar para obtener mensaje de error MQTT
String getMqttErrorMessage(int code) {
  switch (code) {
    case MQTT_CONNECTION_TIMEOUT: return "Connection timeout";
    case MQTT_CONNECTION_LOST: return "Connection lost";
    case MQTT_CONNECT_FAILED: return "Connect failed";
    case MQTT_DISCONNECTED: return "Disconnected";
    case MQTT_CONNECTED: return "Connected";
    case MQTT_CONNECT_BAD_PROTOCOL: return "Bad protocol";
    case MQTT_CONNECT_BAD_CLIENT_ID: return "Bad client ID";
    case MQTT_CONNECT_UNAVAILABLE: return "Unavailable";
    case MQTT_CONNECT_BAD_CREDENTIALS: return "Bad credentials";
    case MQTT_CONNECT_UNAUTHORIZED: return "Unauthorized";
    default: return "Unknown error";
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
    logInfo( "🔧 Configuración MQTT CARGADA desde memoria:");
    logInfo( "  📡 Broker guardado: " + mqttBroker + ":" + String(mqttPort));
  } else {
    // Usar valores por defecto
    mqttBroker = MQTT_BROKER;
    mqttPort = MQTT_PORT;
    logInfo( "🔧 Usando configuración MQTT POR DEFECTO (primera vez):");
    logInfo( "  📡 Broker por defecto: " + mqttBroker + ":" + String(mqttPort));
  }
}

void startCustomConfigPortal() {
  WiFiManager wifiManager;  // Instancia local para evitar duplicados de parámetros
  // Crear parámetros personalizados dentro de la función para evitar duplicados
  WiFiManagerParameter custom_mqtt_broker("broker", "MQTT Broker", mqttBroker.c_str(), 40);
  WiFiManagerParameter custom_mqtt_port("port", "MQTT Port", String(mqttPort).c_str(), 6);

  // Agregar parámetros personalizados al WiFiManager
  wifiManager.addParameter(&custom_mqtt_broker);
  wifiManager.addParameter(&custom_mqtt_port);
  wifiManager.setConfigPortalTimeout(WIFI_CONFIG_PORTAL_TIMEOUT);  // Configurar timeout del portal

  // Iniciar portal de configuración personalizado
  bool success = false;
  configPortalForceActive = true;  // Marcar que el portal debe permanecer activo
  portalStartTime = millis();      // Guardar tiempo de inicio

  // Bucle para mantener el portal activo hasta guardar o timeout
  while (configPortalForceActive && (millis() - portalStartTime < CONFIG_PORTAL_MAX_TIMEOUT)) {
    logInfo( "Iniciando portal de configuración...");
    success = wifiManager.startConfigPortal("DropsterAWG_WiFiConfig");    // Iniciar portal de configuración

    if (success) {
      logInfo( "Portal cerrado exitosamente");

      // Guardar credenciales WiFi si están disponibles
      String configuredSSID = WiFi.SSID();
      String configuredPass = WiFi.psk();
      if (configuredSSID.length() > 0) {
        saveWiFiCredentials(configuredSSID, configuredPass);
      }

      // Guardar configuración MQTT si cambió
      String newBroker = custom_mqtt_broker.getValue();
      String newPortStr = custom_mqtt_port.getValue();
      int newPort = newPortStr.toInt();

      if (newBroker.length() > 0 && newPort > 0 && newPort <= 65535) {
        if (newBroker != mqttBroker || newPort != mqttPort) {
          preferences.begin("awg-mqtt", false);
          preferences.putString("broker", newBroker);
          preferences.putInt("port", newPort);
          preferences.end();
          mqttBroker = newBroker;
          mqttPort = newPort;
          logInfo( "✅ Configuración MQTT guardada desde portal:");
          logInfo( "  📡 Broker: " + mqttBroker + ":" + String(mqttPort));
        } else {
          logInfo( "Configuración MQTT sin cambios");
        }
      } else {
        logWarning( "Configuración MQTT inválida desde portal - usando valores anteriores");
      }

      // Salir del bucle si el portal se cerró exitosamente
      configPortalForceActive = false;
      break;
    } else {
      logWarning( "Portal de configuración falló o timeout, reintentando...");

      // Verificar si se alcanzó el timeout máximo
      if (millis() - portalStartTime >= CONFIG_PORTAL_MAX_TIMEOUT) {
        logWarning( "⏰ Timeout máximo de portal de configuración alcanzado (2 minutos)");
        configPortalForceActive = false;
        break;
      }
      delay(1000);
    }
  }
  configPortalForceActive = false;  // Asegurar que el flag se resetee
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
  alertPumpLow.enabled = preferences.getBool("pumpLowEn", true);
  alertPumpLow.threshold = preferences.getFloat("pumpLowThr", PUMP_MIN_LEVEL_DEFAULT);
  preferences.end();
  logInfo( "Configuración de alertas cargada");
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
  preferences.putBool("pumpLowEn", alertPumpLow.enabled);
  preferences.putFloat("pumpLowThr", alertPumpLow.threshold);
  preferences.end();
}

// Función para guardar credenciales WiFi en preferencias
void saveWiFiCredentials(String ssid, String password) {
  preferences.begin("awg-wifi", false);
  preferences.putString("ssid", ssid);
  preferences.putString("password", password);
  preferences.end();
  logInfo( "✅ Credenciales WiFi guardadas: " + ssid);
}

// Función para cargar credenciales WiFi desde preferencias
bool loadWiFiCredentials(String& ssid, String& password) {
  preferences.begin("awg-wifi", true);
  ssid = preferences.getString("ssid", "");
  password = preferences.getString("password", "");
  preferences.end();
  bool hasCredentials = (ssid.length() > 0 && password.length() > 0);
  if (hasCredentials) {
    logDebug( "📡 Credenciales WiFi cargadas: " + ssid);
  } else {
    logDebug( "❌ No hay credenciales WiFi guardadas");
  }
  return hasCredentials;
}


void setup() {
   // Inicializar NVS para evitar errores de calibración RF (store_cal_data_to_nvs_handle failed)
   esp_err_t ret = nvs_flash_init();
   if (ret == ESP_ERR_NVS_NO_FREE_PAGES || ret == ESP_ERR_NVS_NEW_VERSION_FOUND || ret == ESP_ERR_NVS_INVALID_HANDLE) {
     logWarning("NVS corrupted or invalid (0x" + String(ret, HEX) + "), erasing and retrying...");
     ESP_ERROR_CHECK(nvs_flash_erase());
     ret = nvs_flash_init();
     ESP_ERROR_CHECK(ret);
     logInfo("NVS reinicializado exitosamente");
   } else if (ret != ESP_OK) {
     logWarning("NVS init failed (0x" + String(ret, HEX) + "), but not erasing to preserve config");
   }
   Serial.begin(115200);
   Serial1.begin(115200, SERIAL_8N1, RX1_PIN, TX1_PIN);
   delay(500);
   logInfo("🚀 Iniciando sistema AWG...");
   logInfo("📋 Versión del firmware: v1.0");
   pinMode(CONFIG_BUTTON_PIN, INPUT_PULLUP);

   // Configurar pin de backlight y encender por defecto
   pinMode(BACKLIGHT_PIN, OUTPUT);
   digitalWrite(BACKLIGHT_PIN, HIGH);
   backlightOn = true;
   lastScreenActivity = millis();
   loadSystemStats();              // Cargar estadísticas del sistema
   Serial1.println("AWG_INIT:OK"); // Test UART communication

  // Cargar configuración MQTT antes de inicializar sensores
  loadMqttConfig();
  loadAlertConfig();
  logInfo( "🔧 Inicializando componentes del sistema...");
  ledInit(); // Inicializar LED RGB
  sensorManager.begin();
  reconnectSystem(); // Conectar WiFi y MQTT de forma eficiente (igual que el comando RECONNECT)
  publishState();   // Enviar estados iniciales al display
  // Registrar inicio del sistema
  systemStartTime = millis();
  rebootCount++;
}

void loop() {
  unsigned long now = millis();

  // Verificar timeout de ensamblaje de configuración fragmentada
  if (configAssembleTimeout > 0 && now > configAssembleTimeout) {
    logWarning( "⏰ Timeout de ensamblaje de configuración fragmentada - cancelando");
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
      logInfo( "Iniciando portal de configuración...");
      startCustomConfigPortal();
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
    handleCompressorProtection();    // Manejar protección del compresor
    publishState();  // Publicar estado actualizado después de cambios
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
        mqttReconnectCount++;
        logInfo( "🔄 Intentando reconexión MQTT #" + String(mqttReconnectCount) + " (backoff: " + String(mqttReconnectBackoff/1000) + "s)");

        // Backoff exponencial mejorado con jitter para evitar thundering herd
        if (mqttReconnectCount <= 3) {
          mqttReconnectBackoff = MQTT_RECONNECT_DELAY;  // 3 segundos para primeros intentos
        } else if (mqttReconnectCount <= 7) {
          mqttReconnectBackoff = MQTT_RECONNECT_DELAY * 2;  // 6 segundos
        } else if (mqttReconnectCount <= 12) {
          mqttReconnectBackoff = MQTT_RECONNECT_DELAY * 4;  // 12 segundos
        } else {
          // Backoff exponencial con jitter para evitar sincronización
          unsigned long baseDelay = MQTT_RECONNECT_DELAY * 8UL;  // Base de 24 segundos
          unsigned long jitter = random(0, baseDelay / 4);  // Jitter del 25%
          mqttReconnectBackoff = min(baseDelay + jitter, MQTT_MAX_BACKOFF);
        }
        connectMQTT();
      }
    } else {
      mqttReconnectBackoff = MQTT_RECONNECT_DELAY;  // Reset backoff cuando está conectado
      mqttClient.loop();

      // Ping MQTT periódico para mantener conexión viva (cada 45 segundos)
      if (now - lastMqttPing >= 45000) {
        if (mqttClient.publish(MQTT_TOPIC_SYSTEM, "PING", false)) {
          // Ping exitoso, no loguear
        } else {
          logWarning( "❌ Error enviando ping MQTT - posible desconexión");
          // Forzar verificación de conexión si ping falla
          if (mqttClient.state() != MQTT_CONNECTED) {
            logWarning( "🔌 Conexión MQTT perdida detectada por ping fallido");
            mqttClient.disconnect();
          }
        }
        lastMqttPing = now;
      }

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
    static wl_status_t prevWiFiStatus = WL_DISCONNECTED;  // Estado anterior para detectar cambios

    // Log específico cuando WiFi se conecta por primera vez
    if (currentStatus == WL_CONNECTED && prevWiFiStatus != WL_CONNECTED) {
      offlineMode = false;
      wifiReconnectCount = 0;  // Reset contador en conexión exitosa
    }

    // Solo intentar reconectar si está completamente desconectado
    if (currentStatus == WL_DISCONNECTED || currentStatus == WL_IDLE_STATUS || currentStatus == WL_NO_SSID_AVAIL) {
      wifiReconnectCount++;
      if (wifiReconnectCount <= 3) {
        // Primeros intentos: reconectar rápido
        WiFi.reconnect();
      } else if (wifiReconnectCount <= 5) {
        // Intentos medios: reiniciar conexión completa
        WiFi.disconnect();
        delay(1000);
        String ssid = WiFi.SSID();
        String pass = WiFi.psk();
        if (ssid.length() > 0) {
          WiFi.begin(ssid.c_str(), pass.c_str());
        }
      } else {
        // Muchos intentos fallidos: operar en modo local
        offlineMode = true;
        wifiReconnectCount = 0;  // Reset contador
      }
    } else if (currentStatus == WL_CONNECTED) { // WiFi conectado, verificar calidad de señal
      int rssi = WiFi.RSSI();
      if (rssi < -80) {
        logWarning( "⚠️ Señal WiFi débil: " + String(rssi) + " dBm");
      }
    }
    prevWiFiStatus = currentStatus;  // Actualizar estado anterior
    lastWiFiCheck = now;
  }
  // Gestionar timeout de pantalla (reposo/backlight) - enviar comandos al display
  if (screenTimeoutSec > 0) {
    if (backlightOn && (now - lastScreenActivity >= (unsigned long)screenTimeoutSec * 1000UL)) {
      Serial1.println("BACKLIGHT:OFF");
      digitalWrite(BACKLIGHT_PIN, LOW);
      backlightOn = false;
    }
  }
  sensorManager.handleCommands();
  sensorManager.handleSerialCommands();

  // Guardar estadísticas periódicamente (cada 5 minutos)
  static unsigned long lastStatsSave = 0;
  if (now - lastStatsSave >= STATS_SAVE_INTERVAL) {
    totalUptime += (now - lastStatsSave) / 1000;
    saveSystemStats();
    lastStatsSave = now;
  }
  updateLedState(); // Actualizar LED RGB según estado del sistema
}
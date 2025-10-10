/* ========================================================================================
 * Sistema Dropster AWG (Atmospheric Water Generator) - Firmware
 * ========================================================================================
 *
 * Descripción: Sistema de control completo para generador de agua atmosférico
 * con monitoreo de sensores, control automático, comunicación MQTT y display LCD TFT.
 *
 * Funcionalidades principales:
 * - Monitoreo de variables climaticas, electricas y del dispositivo como temperaturas y nivel de agua
 * - Modo de operacion automatico y manual
 * - Sistema de alertas configurable (tanque lleno, voltaje bajo, humedad baja, temp compresor alta)
 * - Comunicación MQTT bidireccional con app móvil
 * - Interfaz serial para comandos y configuración local (ROOT)
 * - Display LCD TFT integrado para control y monitoreo local
 *
 * Versión: v1.0
 * Fecha: 6/10/2025
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
float smoothedDistance = 0.0;           // Distancia suavizada del sensor ultrasónico
bool firstDistanceReading = true;       // Flag para inicialización del suavizado

// Sistema de manejo de concurrencia (evita comandos simultáneos)
bool isProcessingCommand = false;   // Flag de procesamiento de comando activo
unsigned long lastCommandTime = 0;  // Timestamp del último comando
String lastProcessedCommand = "";   // Último comando procesado (evita duplicados)

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
float lastValidDistance = 0.0;  // Última distancia válida medida

// Configuración del tanque
float tankCapacityLiters = TANK_CAPACITY_DEFAULT;  // Capacidad total del tanque en litros

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
bool prevBmeOnline = false;
bool prevSht1Online = false;
bool prevPzemOnline = false;
bool prevRtcAvailable = false;
bool prevUltrasonicOk = false;
bool prevTermistorOk = false;
bool prevDisplayOk = false;

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
void publishCurrentStates();                // Publica estados actuales por MQTT

// Sistema de alertas
void sendAlert(String type, String message, float value);  // Envía alerta por MQTT
void checkAlerts();                                        // Verifica condiciones de alerta

// Comunicación con display
void sendStatesToDisplay();  // Envía estados al display LCD

// ========================================================================================
// 11. FUNCIONES DE COMUNICACIÓN Y UTILIDADES
// ========================================================================================

//Publica todos los estados actuales del sistema por MQTT para sincronización inmediata. (Útil cuando la app se conecta o necesita actualizar su estado)
void publishCurrentStates() {
  if (!mqttClient.connected()) return;

  // Leer estados actuales de los relés
  bool compOn = (digitalRead(COMPRESSOR_RELAY_PIN) == LOW);
  bool ventOn = (digitalRead(VENTILADOR_RELAY_PIN) == LOW);
  bool compFanOn = (digitalRead(COMPRESSOR_FAN_RELAY_PIN) == LOW);
  bool pumpOn = (digitalRead(PUMP_RELAY_PIN) == LOW);

  // Publicar estados individuales
  mqttClient.publish(MQTT_TOPIC_STATUS, compOn ? "COMP_ON" : "COMP_OFF");
  mqttClient.publish(MQTT_TOPIC_STATUS, ventOn ? "VENT_ON" : "VENT_OFF");
  mqttClient.publish(MQTT_TOPIC_STATUS, compFanOn ? "CFAN_ON" : "CFAN_OFF");
  mqttClient.publish(MQTT_TOPIC_STATUS, pumpOn ? "PUMP_ON" : "PUMP_OFF");

  // Publicar modo de operación actual
  mqttClient.publish(MQTT_TOPIC_STATUS, operationMode == MODE_AUTO ? "MODE_AUTO" : "MODE_MANUAL");
}

/* Envía una alerta del sistema por MQTT hacia la aplicación móvil. Incluye información detallada del evento para notificaciones push
 * Tipo de alerta ("tank_full", "voltage_low", "humidity_low", "hightemp_comp") - mensaje descriptivo y valor detectado*/
void sendAlert(String type, String message, float value) {
  if (!mqttClient.connected()) {
    awgLog(LOG_WARNING, "MQTT no conectado, no se puede enviar alerta: " + type);
    return;
  }
  awgLog(LOG_DEBUG, "📤 Preparando envío de alerta: " + type + " - Valor: " + String(value, 2));

  // Función para redondear floats a 2 decimales
  auto roundTo2Decimals = [](float val) -> float {
    return round(val * 100.0) / 100.0;
  };

  // Crear documento JSON con información de la alerta
  StaticJsonDocument<200> doc;
  doc["type"] = type;
  doc["message"] = message;
  doc["value"] = roundTo2Decimals(value);

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
    awgLog(LOG_INFO, "✅ Alerta enviada exitosamente: " + type + " - " + String(value, 2));

    // Log específico para debug de humedad baja
    if (type == "humidity_low") {
      awgLog(LOG_DEBUG, "💨 ALERTA HUMEDAD BAJA enviada - Valor: " + String(value, 2) + "%, Mensaje: " + message);
    }
    mqttClient.loop();  // Procesar MQTT para asegurar envío inmediato
  } else {
    awgLog(LOG_ERROR, "❌ Error al serializar JSON de alerta: " + type);
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
// 12. GESTIÓN DE SENSORES - CLASE AWGSensorManager
// ========================================================================================

/* Clase principal para gestión de todos los sensores del sistema Dropster AWG.
 * Maneja la lectura, validación, calibración, procesamiento de datos de sensores, algoritmos de control automático de temperatura y sistema de alertas*/
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
     * para mayor precisión. Maneja casos extremos y validaciones de rango.
     * @param distance Distancia medida por el sensor ultrasónico (cm)
     * @return Volumen estimado en litros, o 0.0 si no hay calibración válida*/
  float interpolateVolume(float distance) {
    // Verificar que hay suficientes puntos de calibración
    if (numCalibrationPoints < 2) {
      if (!calibrationMode) {
        awgLog(LOG_WARNING, "No hay suficientes puntos de calibración para calcular volumen");
      }
      return 0.0;
    }

    // Validar rango general
    if (distance > calibrationPoints[0].distance + 2.0) {
      return 0.0;  // Demasiado lejos - probablemente error de medición
    }
    if (distance < calibrationPoints[numCalibrationPoints - 1].distance - 2.0) {
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
    if (v < 0.0) v = 0.0;  // Asegurar rango válido
    return v;
  }

  void calculateTankHeight() {
    if (numCalibrationPoints >= 2) {
      tankHeight = calibrationPoints[0].distance - calibrationPoints[numCalibrationPoints - 1].distance;
      awgLog(LOG_INFO, "Altura calibrada del tanque: " + String(tankHeight, 2) + " cm");
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
    int calibVer = preferences.getInt("calibVer", 0);
    String calibType = preferences.getString("calibType", "table");

    // Cargar parámetros de control si existen (si no, mantener valores por defecto)
    control_deadband = preferences.getFloat("ctrl_deadband", control_deadband);
    control_min_off = preferences.getInt("ctrl_min_off", control_min_off);
    control_max_on = preferences.getInt("ctrl_max_on", control_max_on);
    control_sampling = preferences.getInt("ctrl_sampling", control_sampling);
    control_alpha = preferences.getFloat("ctrl_alpha", control_alpha);

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
      awgLog(LOG_INFO, "Calibración cargada: " + String(numCalibrationPoints) + " puntos (ver " + String(calibVer) + ")");
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
        if (ratio < 0.1 || ratio > 10.0) {
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

  // Función de monitoreo automático de estado de sensores
  void monitorSensorStatus() {
    // Verificar estado actual de cada sensor
    bool currentBmeOnline = bmeOnline;
    bool currentSht1Online = sht1Online;
    bool currentPzemOnline = pzemOnline;
    bool currentRtcAvailable = rtcAvailable && rtcOnline;

    // Verificar termistor
    int adcValue = analogRead(TERMISTOR_PIN);
    float resistance = (adcValue * VREF) / ADC_RESOLUTION / CURRENT;
    float temp = calculateTemperature(resistance);
    bool currentTermistorOk = (!isnan(temp) && temp > -50 && temp < 200);

    // Verificar HC-SR04
    float distance = getAverageDistance(1);  // Verificación rápida
    bool currentUltrasonicOk = (distance >= 0 && distance <= 400);

    // Verificar pantalla (ping rápido)
    Serial1.println("P");  // Ping corto
    delay(50);
    bool currentDisplayOk = Serial1.available();

    // Comparar con estado anterior y mostrar alertas
    if (currentBmeOnline != prevBmeOnline) {
      if (!currentBmeOnline) {
        awgLog(LOG_ERROR, "🚨 FALLO DETECTADO: BME280 (Sensor ambiental) - DESCONECTADO");
      } else {
        awgLog(LOG_INFO, "✅ RECUPERADO: BME280 (Sensor ambiental) - FUNCIONANDO");
      }
      prevBmeOnline = currentBmeOnline;
    }

    if (currentSht1Online != prevSht1Online) {
      if (!currentSht1Online) {
        awgLog(LOG_ERROR, "🚨 FALLO DETECTADO: SHT31 (Sensor evaporador) - DESCONECTADO");
      } else {
        awgLog(LOG_INFO, "✅ RECUPERADO: SHT31 (Sensor evaporador) - FUNCIONANDO");
      }
      prevSht1Online = currentSht1Online;
    }

    if (currentPzemOnline != prevPzemOnline) {
      if (!currentPzemOnline) {
        awgLog(LOG_ERROR, "🚨 FALLO DETECTADO: PZEM-004T (Medidor energía) - DESCONECTADO");
      } else {
        awgLog(LOG_INFO, "✅ RECUPERADO: PZEM-004T (Medidor energía) - FUNCIONANDO");
      }
      prevPzemOnline = currentPzemOnline;
    }

    if (currentRtcAvailable != prevRtcAvailable) {
      if (!currentRtcAvailable) {
        awgLog(LOG_ERROR, "🚨 FALLO DETECTADO: DS3231 (RTC) - DESCONECTADO");
      } else {
        awgLog(LOG_INFO, "✅ RECUPERADO: DS3231 (RTC) - FUNCIONANDO");
      }
      prevRtcAvailable = currentRtcAvailable;
    }

    if (currentTermistorOk != prevTermistorOk) {
      if (!currentTermistorOk) {
        awgLog(LOG_ERROR, "🚨 FALLO DETECTADO: Termistor (Temp. compresor) - ERROR DE LECTURA");
      } else {
        awgLog(LOG_INFO, "✅ RECUPERADO: Termistor (Temp. compresor) - FUNCIONANDO");
      }
      prevTermistorOk = currentTermistorOk;
    }

    if (currentUltrasonicOk != prevUltrasonicOk) {
      if (!currentUltrasonicOk) {
        awgLog(LOG_ERROR, "🚨 FALLO DETECTADO: HC-SR04 (Sensor nivel) - ERROR DE LECTURA");
      } else {
        awgLog(LOG_INFO, "✅ RECUPERADO: HC-SR04 (Sensor nivel) - FUNCIONANDO");
      }
      prevUltrasonicOk = currentUltrasonicOk;
    }

    if (currentDisplayOk != prevDisplayOk) {
      if (!currentDisplayOk) {
        awgLog(LOG_ERROR, "🚨 FALLO DETECTADO: Pantalla LCD - DESCONECTADA");
      } else {
        awgLog(LOG_INFO, "✅ RECUPERADO: Pantalla LCD - FUNCIONANDO");
      }
      prevDisplayOk = currentDisplayOk;
    }
  }

  void performSensorDiagnostics() {
    awgLog(LOG_INFO, "🔍 DIAGNÓSTICO COMPLETO DE SENSORES - SISTEMA DROPSTER AWG");
    awgLog(LOG_INFO, "═══════════════════════════════════════════════════════════════");

    String failedSensors = "";
    String workingSensors = "";
    bool allOk = true;

    // 1. Verificar BME280 (Temperatura, Humedad, Presión)
    awgLog(LOG_INFO, "🔧 Verificando BME280 (Sensor ambiental)...");
    if (bmeOnline) {
      float temp = bme.readTemperature();
      float hum = bme.readHumidity();
      float pres = bme.readPressure() / 100.0;
      if (!isnan(temp) && !isnan(hum) && !isnan(pres)) {
        awgLog(LOG_INFO, "  ✅ BME280: OK - " + String(temp, 1) + "°C, " + String(hum, 1) + "%, " + String(pres, 1) + "hPa");
        workingSensors += "BME280, ";
      } else {
        awgLog(LOG_ERROR, "  ❌ BME280: ERROR - Lectura inválida");
        failedSensors += "BME280, ";
        allOk = false;
      }
    } else {
      awgLog(LOG_ERROR, "  ❌ BME280: DESCONECTADO - No responde en bus I2C");
      failedSensors += "BME280, ";
      allOk = false;
    }

    // 2. Verificar SHT31 (Temperatura y Humedad de alta precisión)
    awgLog(LOG_INFO, "🔧 Verificando SHT31 (Sensor evaporador)...");
    if (sht1Online) {
      float temp = sht31_1.readTemperature();
      float hum = sht31_1.readHumidity();
      if (!isnan(temp) && !isnan(hum)) {
        awgLog(LOG_INFO, "  ✅ SHT31: OK - " + String(temp, 1) + "°C, " + String(hum, 1) + "%");
        workingSensors += "SHT31, ";
      } else {
        awgLog(LOG_ERROR, "  ❌ SHT31: ERROR - Lectura inválida");
        failedSensors += "SHT31, ";
        allOk = false;
      }
    } else {
      awgLog(LOG_ERROR, "  ❌ SHT31: DESCONECTADO - No responde en bus I2C");
      failedSensors += "SHT31, ";
      allOk = false;
    }

    // 3. Verificar PZEM-004T (Medidor de energía)
    awgLog(LOG_INFO, "🔧 Verificando PZEM-004T (Medidor energía)...");
    if (pzemOnline) {
      float voltage = pzem.voltage();
      float current = pzem.current();
      if (!isnan(voltage) && voltage > 0.1) {
        awgLog(LOG_INFO, "  ✅ PZEM-004T: OK - " + String(voltage, 1) + "V, " + String(current, 2) + "A");
        workingSensors += "PZEM-004T, ";
      } else {
        awgLog(LOG_ERROR, "  ❌ PZEM-004T: ERROR - No detecta voltaje válido");
        failedSensors += "PZEM-004T, ";
        allOk = false;
      }
    } else {
      awgLog(LOG_ERROR, "  ❌ PZEM-004T: DESCONECTADO - No responde en puerto serial");
      failedSensors += "PZEM-004T, ";
      allOk = false;
    }

    // 4. Verificar DS3231 (Reloj de tiempo real)
    awgLog(LOG_INFO, "🔧 Verificando DS3231 (RTC)...");
    if (rtcAvailable && rtcOnline) {
      DateTime now = rtc.now();
      awgLog(LOG_INFO, "  ✅ DS3231: OK - " + String(now.year()) + "-" + String(now.month()) + "-" + String(now.day()) + " " + String(now.hour()) + ":" + String(now.minute()));
      workingSensors += "DS3231, ";
    } else {
      awgLog(LOG_ERROR, "  ❌ DS3231: DESCONECTADO - No responde en bus I2C");
      failedSensors += "DS3231, ";
      allOk = false;
    }

    // 5. Verificar Termistor (Temperatura del compresor)
    awgLog(LOG_INFO, "🔧 Verificando Termistor (Temp. compresor)...");
    int adcValue = analogRead(TERMISTOR_PIN);
    if (adcValue > 0) {
      float resistance = (adcValue * VREF) / ADC_RESOLUTION / CURRENT;
      float temp = calculateTemperature(resistance);
      if (!isnan(temp) && temp > -50 && temp < 200) {
        awgLog(LOG_INFO, "  ✅ Termistor: OK - " + String(temp, 1) + "°C");
        workingSensors += "Termistor, ";
      } else {
        awgLog(LOG_ERROR, "  ❌ Termistor: ERROR - Temperatura fuera de rango");
        failedSensors += "Termistor, ";
        allOk = false;
      }
    } else {
      awgLog(LOG_ERROR, "  ❌ Termistor: ERROR - No se puede leer ADC");
      failedSensors += "Termistor, ";
      allOk = false;
    }

    // 6. Verificar HC-SR04 (Sensor ultrasónico)
    awgLog(LOG_INFO, "🔧 Verificando HC-SR04 (Sensor nivel)...");
    float distance = getAverageDistance(3);
    if (distance >= 0 && distance <= 400) {
      awgLog(LOG_INFO, "  ✅ HC-SR04: OK - " + String(distance, 1) + " cm");
      workingSensors += "HC-SR04, ";
    } else {
      awgLog(LOG_ERROR, "  ❌ HC-SR04: ERROR - No detecta distancia válida");
      failedSensors += "HC-SR04, ";
      allOk = false;
    }

    // Resultado final
    awgLog(LOG_INFO, "═══════════════════════════════════════════════════════════════");
    if (allOk) {
      awgLog(LOG_INFO, "🎉 TODOS LOS SENSORES FUNCIONANDO CORRECTAMENTE");
    } else {
      // Quitar coma final
      if (failedSensors.length() > 0) {
        failedSensors = failedSensors.substring(0, failedSensors.length() - 2);
      }
      if (workingSensors.length() > 0) {
        workingSensors = workingSensors.substring(0, workingSensors.length() - 2);
      }

      awgLog(LOG_ERROR, "⚠️ SENSORES CON PROBLEMAS: " + failedSensors);
      if (workingSensors.length() > 0) {
        awgLog(LOG_INFO, "✅ Sensores OK: " + workingSensors);
      }
      awgLog(LOG_WARNING, "🔧 Recomendación: Verificar conexiones físicas y alimentación de los sensores fallidos");
    }
    awgLog(LOG_INFO, "═══════════════════════════════════════════════════════════════");
  }

  AWGSensorManager()
    : sht31_1(&Wire),
      pzem(Serial2, RX2_PIN, TX2_PIN) {
    resetCalibration();
  }

  bool begin() {
    loadCalibration();
    Wire.begin(SDA_PIN, SCL_PIN);
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
    awgLog(LOG_INFO, "Verificando conexión inicial con PZEM-004T...");
    for (int i = 0; i < PZEM_INIT_ATTEMPTS; i++) {
      float voltage = pzem.voltage();
      if (!isnan(voltage) && voltage > 0) {
        pzemOnline = true;
        awgLog(LOG_INFO, "PZEM-004T detectado en inicialización");
        break;
      }
      delay(500);
    }
    if (!pzemOnline) {
      awgLog(LOG_INFO, "⚠️ PZEM-004T no detectado inicialmente, se intentará detectar periódicamente");
    }

    // Test inicial del sensor ultrasónico
    float testDistance = getAverageDistance(3);
    if (testDistance >= 0) {
      lastValidDistance = testDistance;
      awgLog(LOG_INFO, "Sensor ultrasónico OK - Distancia: " + String(testDistance, 2) + " cm");
    } else {
      awgLog(LOG_WARNING, "Sensor ultrasónico presenta problemas");
    }

    // Inicializar estado anterior de sensores para monitoreo automático
    prevBmeOnline = bmeOnline;
    prevSht1Online = sht1Online;
    prevPzemOnline = pzemOnline;
    prevRtcAvailable = rtcAvailable && rtcOnline;

    // Verificar estado inicial de termistor
    int adcValue = analogRead(TERMISTOR_PIN);
    float resistance = (adcValue * VREF) / ADC_RESOLUTION / CURRENT;
    float temp = calculateTemperature(resistance);
    prevTermistorOk = (!isnan(temp) && temp > -50 && temp < 200);

    // Verificar estado inicial de HC-SR04
    prevUltrasonicOk = (testDistance >= 0 && testDistance <= 400);

    // Verificar estado inicial de pantalla
    Serial1.println("P");
    delay(50);
    prevDisplayOk = Serial1.available();

    awgLog(LOG_INFO, "Inicialización de sensores completada");
    return bmeOnline || sht1Online || pzemOnline;
  }

  void readSensors() {
    // Obtener timestamp si RTC está disponible
    if (rtcOnline) {
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
    }

    if (sht1Online) {
      data.sht1Temp = validateTemp(sht31_1.readTemperature());
      data.sht1Hum = validateHumidity(sht31_1.readHumidity());
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
          awgLog(LOG_WARNING, "⚠️ PZEM-004T desconectado físicamente después de " + String(maxConsecutiveFailures) + " fallos consecutivos");
          data.voltage = 0.0;
          data.current = 0.0;
          data.power = 0.0;  // Energía se mantiene (no se resetea)
        } else {
          // Durante fallos temporales, poner corriente y potencia a 0, mantener energía
          data.current = 0.0;
          data.power = 0.0;
          awgLog(LOG_DEBUG, "📊 Fallo temporal PZEM - corriente y potencia puestas a 0, energía mantenida");
        }
      } else {
        consecutiveFailures = 0;                           // Reset contador de fallos
        data.voltage = constrain(rawVoltage, 0.0, 300.0);  // PZEM conectado, procesar valores según física real

        // Si voltaje es prácticamente 0, mostrar 0 en corriente y potencia
        if (data.voltage <= 0.1) {
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
        awgLog(LOG_INFO, "Intentando detectar PZEM-004T...");

        // Intentar leer voltaje para verificar si el PZEM está conectado
        float testVoltage = pzem.voltage();
        if (!isnan(testVoltage) && testVoltage > 0.1) {
          pzemOnline = true;
          awgLog(LOG_INFO, "✅ PZEM-004T detectado exitosamente con voltaje: " + String(testVoltage, 1) + "V");
        } else {
          awgLog(LOG_INFO, "❌ PZEM-004T no detectado, reintentando en 10s");
        }
      }

      // Si no está online, mostrar 0 en todo excepto energía
      data.voltage = 0.0;
      data.current = 0.0;
      data.power = 0.0;  // Energía se mantiene (no resetear a 0)
    }

    // Leer temperatura del compresor (termistor NTC)
    {
      // Leer múltiples muestras y promediar
      float sumVoltage = 0;
      int samples = 20;

      for (int i = 0; i < samples; i++) {
        int adcValue = analogRead(TERMISTOR_PIN);
        float voltage = (adcValue * VREF) / ADC_RESOLUTION;
        sumVoltage += voltage;
        delay(10);
      }
      float avgVoltage = sumVoltage / samples;
      // Calcular resistencia del termistor: R = V / I
      float resistance = avgVoltage / CURRENT;
      // Calcular temperatura
      data.compressorTemp = calculateTemperature(resistance);
    }

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
      temperature = 25.0;  // Valor por defecto si no hay sensor de temperatura
    }

    float speedOfSound = 331.3 + (0.606 * temperature);            // velocidad del sonido en m/s
    float duration_s = duration * 1e-6f;                           // duration está en microsegundos -> convertir a segundos
    float distance = (duration_s * speedOfSound * 100.0f) / 2.0f;  // distancia en cm = (tiempo * velocidad * 100) / 2
    distance += sensorOffset;

    if (distance < 2.0f || distance > 400.0f) {
      return -1.0;
    }
    return distance;
  }

  float getAverageDistance(int samples) {
    if (samples < 3) samples = 3;
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
    if (fcount >= 3) {
      float sum = 0.0;
      for (int i = 0; i < fcount; i++) sum += filtered[i];
      return sum / fcount;
    } else {
      return median;  // Si pocos valores, usar mediana (más robusto)
    }
  }

  void transmitData() {
    // Asegurar que los valores críticos nunca sean negativos para las gráficas
    float safeWaterVolume = max(0.0f, data.waterVolume);  // Agua nunca negativa
    float safeEnergy = max(0.0f, data.energy);            // Energía nunca negativa

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
      Serial1.write(txBuffer, len);
      awgLog(LOG_DEBUG, "Datos enviados al display: " + String(txBuffer));
    }
  }

  void transmitMQTTData() {
    if (!mqttClient.connected()) {
      return;
    }

    // Asegurar que los valores críticos nunca sean negativos para las gráficas
    float safeWaterVolume = max(0.0f, data.waterVolume);  // Agua nunca negativa
    float safeEnergy = max(0.0f, data.energy);            // Energía nunca negativa
    StaticJsonDocument<300> doc;

    // Función para redondear floats a exactamente 2 decimales
    auto roundTo2Decimals = [](float value) -> float {
      return round(value * 100.0) / 100.0;
    };

    if (bmeOnline) {
      doc["t"] = roundTo2Decimals(data.bmeTemp);  // Temperatura ambiente
      doc["h"] = roundTo2Decimals(data.bmeHum);   // Humedad relativa ambiente
      doc["p"] = roundTo2Decimals(data.bmePres);  // presion atmosferica ambiente
    }

    doc["w"] = roundTo2Decimals(safeWaterVolume);  // Agua almacenada

    if (sht1Online) {
      doc["te"] = roundTo2Decimals(data.sht1Temp);  // Temperatura del evaporador
      doc["he"] = roundTo2Decimals(data.sht1Hum);   // Humedad relativa del evaporador
    }

    doc["tc"] = roundTo2Decimals(data.compressorTemp);  // Temperatura del compresor
    doc["dp"] = roundTo2Decimals(data.dewPoint);        // Temperatura punto de rocio
    doc["ha"] = roundTo2Decimals(data.absHumidity);     // Humedad Absoluta

    if (pzemOnline) {
      if (data.voltage > 0) doc["v"] = roundTo2Decimals(data.voltage);   // voltaje
      if (data.current >= 0) doc["c"] = roundTo2Decimals(data.current);  // corriente
      if (data.power >= 0) doc["po"] = roundTo2Decimals(data.power);     // potencia
    }
    if (safeEnergy >= 0) doc["e"] = roundTo2Decimals(safeEnergy);  // Energía (acumulativa)

    doc["cs"] = data.compressorState;
    doc["vs"] = data.ventiladorState;
    doc["cfs"] = data.compressorFanState;
    doc["ps"] = data.pumpState;
    doc["calibrated"] = isCalibrated;

    // Información de conectividad MQTT para la pantalla de conectividad de la app
    doc["mqtt_broker"] = mqttBroker;
    doc["mqtt_port"] = mqttPort;
    doc["mqtt_topic"] = MQTT_TOPIC_DATA;
    doc["mqtt_connected"] = true;  // Si estamos transmitiendo, estamos conectados

    // Calcular porcentaje de agua
    float waterPercentMQTT = calculateWaterPercent(data.distance, safeWaterVolume);
    doc["water_height"] = roundTo2Decimals(waterPercentMQTT);
    doc["tank_capacity"] = roundTo2Decimals(tankCapacityLiters);

    if (rtcOnline) {
      DateTime now = rtc.now();
      doc["ts"] = now.unixtime();
    } else {
      doc["ts"] = roundTo2Decimals(millis() / 1000.0);
    }
    size_t jsonSize = serializeJson(doc, mqttBuffer, sizeof(mqttBuffer));

    if (jsonSize > 0 && jsonSize < sizeof(mqttBuffer)) {
      mqttClient.publish(MQTT_TOPIC_DATA, mqttBuffer, false);
    }
  }

  // Sistema de calibración simplificado
  void startCalibration() {
    awgLog(LOG_INFO, "=== CALIBRACIÓN INICIADA ===");
    awgLog(LOG_INFO, "1. Asegúrese de que el tanque esté VACÍO");
    awgLog(LOG_INFO, "2. El sistema medirá automáticamente el punto 0.0L");
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
      awgLog(LOG_INFO, "✅ Tanque vacío calibrado: " + String(currentDistance, 2) + " cm");
      awgLog(LOG_INFO, "Ahora agregue agua y use: CALIB_ADD X.X (donde X.X son litros)");
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
    awgLog(LOG_INFO, "✅ Punto añadido: " + String(avgDistance, 2) + "cm = " + String(knownVolume, 3) + "L");
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
    awgLog(LOG_INFO, "✅ CALIBRACIÓN COMPLETADA");
    awgLog(LOG_INFO, "Puntos registrados: " + String(numCalibrationPoints));
    printCalibrationTable();

    // Mostrar ejemplo de medición actual
    float currentDistance = getAverageDistance(5);
    if (currentDistance >= 0) {
      float currentVolume = interpolateVolume(currentDistance);
      awgLog(LOG_INFO, "📏 Medición actual: " + String(currentDistance, 2) + "cm = " + String(currentVolume, 2) + "L");
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
      float alpha = 0.7;  // Factor de suavizado (0-1, mayor = menos suavizado)
      smoothedDistance = alpha * rawDistance + (1 - alpha) * smoothedDistance;
    }
    return smoothedDistance;
  }

  float calculateWaterVolume(float distance) {
    if (isCalibrated && numCalibrationPoints >= 2) {
      return interpolateVolume(distance);
    }
    return 0.0;
  }

  float calculateWaterPercent(float distance, float volume) {
    float waterPercent = 0.0;
    if (tankCapacityLiters > 0 && volume >= 0) {
      // Método preferido: usar volumen calculado por calibración / capacidad total
      waterPercent = (volume / tankCapacityLiters) * 100.0;
      // Limitar entre 0% y 100%
      if (waterPercent < 0) waterPercent = 0;
      if (waterPercent > 100) waterPercent = 100;
    } else if (tankHeight > 0) {
      // Fallback: cálculo basado en altura (para compatibilidad)
      float effectiveHeight = tankHeight - sensorOffset;
      if (effectiveHeight > 0) {
        float distanceToWater = distance - sensorOffset;
        if (distanceToWater < 0) distanceToWater = 0;
        waterPercent = ((effectiveHeight - distanceToWater) / effectiveHeight) * 100.0;
        if (waterPercent < 0) waterPercent = 0;
        if (waterPercent > 100) waterPercent = 100;
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
    // Buffer fijo para comandos provenientes del UART1 (pantalla)
    static char cmdBuf1[128];
    static size_t cmdIdx1 = 0;
    while (Serial1.available()) {
      char c = (char)Serial1.read();
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
          cmdIdx1 = 0;  // overflow: resetear
        }
      }
    }
  }

  void handleSerialCommands() {
    // Buffer para comandos desde el puerto USB Serial
    static char cmdBuf0[128];
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
          cmdBuf0[cmdIdx0++] = c;
        } else {
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

  void performSensorRecoveryInternal() {
    awgLog(LOG_DEBUG, "🔄 Iniciando verificación de recuperación de sensores...");
    bool recoveryAttempted = false;

    // 1. Recuperación de sensores I2C (BME280, SHT31, RTC)
    if (!bmeOnline || !sht1Online || !rtcAvailable) {
      awgLog(LOG_DEBUG, "🔧 Verificando sensores I2C...");

      // Reset del bus I2C
      Wire.end();
      delay(100);
      Wire.begin(SDA_PIN, SCL_PIN);
      delay(100);

      // Intentar recuperar BME280
      if (!bmeOnline) {
        Adafruit_BME280 tempBME;
        if (tempBME.begin(BME280_ADDR)) {
          bmeOnline = true;
          awgLog(LOG_INFO, "✅ BME280 recuperado exitosamente");
          recoveryAttempted = true;
        } else {
          awgLog(LOG_DEBUG, "❌ BME280 no recuperado");
        }
      }

      // Intentar recuperar SHT31
      if (!sht1Online) {
        Adafruit_SHT31 tempSHT;
        tempSHT.begin(SHT31_ADDR_1);
        // Intentar una lectura de prueba
        float temp = tempSHT.readTemperature();
        if (!isnan(temp)) {
          sht1Online = true;
          awgLog(LOG_INFO, "✅ SHT31 recuperado exitosamente");
          recoveryAttempted = true;
        } else {
          awgLog(LOG_DEBUG, "❌ SHT31 no recuperado");
        }
      }

      // Intentar recuperar RTC
      if (!rtcAvailable) {
        RTC_DS3231 tempRTC;
        if (tempRTC.begin()) {
          rtcAvailable = true;
          rtcOnline = true;
          awgLog(LOG_INFO, "✅ RTC recuperado exitosamente");
          recoveryAttempted = true;
        } else {
          awgLog(LOG_DEBUG, "❌ RTC no recuperado");
        }
      }
    }

    // 2. Recuperación de PZEM-004T (Serial)
    if (!pzemOnline) {
      awgLog(LOG_DEBUG, "🔧 Verificando PZEM-004T...");

      // Intentar múltiples lecturas consecutivas para verificar recuperación estable
      bool pzemRecovered = false;
      int consecutiveSuccess = 0;
      const int requiredConsecutive = 3;  // Requiere 3 lecturas consecutivas exitosas

      for (int i = 0; i < 5 && consecutiveSuccess < requiredConsecutive; i++) {
        float voltage = pzem.voltage();
        if (!isnan(voltage) && voltage > 0.1) {  // Voltaje válido (>0.1V para evitar ruido)
          consecutiveSuccess++;
          awgLog(LOG_DEBUG, "📊 Lectura PZEM exitosa " + String(consecutiveSuccess) + "/" + String(requiredConsecutive) + ": " + String(voltage, 1) + "V");
        } else {
          consecutiveSuccess = 0;  // Reset contador si falla
          awgLog(LOG_DEBUG, "📊 Lectura PZEM fallida o voltaje cero");
        }
        delay(300);  // Mayor delay entre lecturas
      }

      if (consecutiveSuccess >= requiredConsecutive) {
        pzemOnline = true;
        pzemRecovered = true;
        awgLog(LOG_INFO, "✅ PZEM-004T recuperado exitosamente después de " + String(requiredConsecutive) + " lecturas consecutivas válidas");
        recoveryAttempted = true;
      } else {
        awgLog(LOG_DEBUG, "❌ PZEM-004T no recuperado - no se obtuvieron " + String(requiredConsecutive) + " lecturas consecutivas válidas");
      }
    }
    if (recoveryAttempted) {
      awgLog(LOG_INFO, "🔄 Recuperación de sensores completada");
    } else {
      awgLog(LOG_DEBUG, "🔄 Todos los sensores operativos - no se requirió recuperación");
    }
  }

  // Función para enviar confirmación de configuración a la app
  void sendConfigAckToApp(int changeCount) {
    // Validar conexión MQTT
    if (!mqttClient.connected()) {
      awgLog(LOG_WARNING, "⚠️ MQTT no conectado, no se puede enviar confirmación de configuración");
      return;
    }

    // Validar parámetros
    if (changeCount < 0) {
      awgLog(LOG_ERROR, "❌ Número de cambios inválido: " + String(changeCount));
      return;
    }

    // Crear documento JSON con validación
    StaticJsonDocument<150> ackDoc;
    ackDoc["type"] = "config_ack";
    ackDoc["status"] = (changeCount > 0) ? "success" : "no_changes";
    ackDoc["changes"] = changeCount;
    ackDoc["timestamp"] = rtcAvailable ? rtc.now().unixtime() : (millis() / 1000);
    ackDoc["uptime"] = millis() / 1000;  // Añadir uptime para debugging

    // Serializar con validación de tamaño
    char ackBuffer[150];
    size_t ackLen = serializeJson(ackDoc, ackBuffer, sizeof(ackBuffer));

    if (ackLen > 0 && ackLen < sizeof(ackBuffer) - 1) {
      // Enviar con QoS 1 para asegurar entrega y reintento automático
      bool sent = mqttClient.publish(MQTT_TOPIC_STATUS, ackBuffer, true);  // QoS 1
      if (sent) {
        awgLog(LOG_INFO, "📤 Confirmación de configuración enviada exitosamente: " + String(changeCount) + " cambios aplicados");
        awgLog(LOG_DEBUG, "📄 JSON enviado: " + String(ackBuffer));
      } else {
        awgLog(LOG_ERROR, "❌ Error al publicar confirmación MQTT (QoS 1)");
        // Intentar con QoS 0 como fallback
        sent = mqttClient.publish(MQTT_TOPIC_STATUS, ackBuffer, false);
        if (sent) {
          awgLog(LOG_WARNING, "⚠️ Confirmación enviada con QoS 0 (fallback)");
        } else {
          awgLog(LOG_ERROR, "❌ Error crítico: No se pudo enviar confirmación ni con QoS 0");
        }
      }
      mqttClient.loop();  // Procesar MQTT para asegurar envío inmediato
    } else {
      awgLog(LOG_ERROR, "❌ Error al serializar confirmación JSON - buffer insuficiente o error de serialización");
      awgLog(LOG_DEBUG, "📏 Longitud requerida: " + String(ackLen) + ", buffer disponible: " + String(sizeof(ackBuffer)));
    }
  }

  void processCommand(String& cmd) {
    // Validación básica del comando
    if (cmd.length() == 0) {
      awgLog(LOG_DEBUG, "Comando vacío recibido, ignorado");
      return;
    }

    cmd.trim();
    if (cmd.length() == 0) {
      awgLog(LOG_DEBUG, "Comando solo espacios recibido, ignorado");
      return;
    }
    cmd.toLowerCase();             // Hacer comandos case-insensitive
    unsigned long now = millis();  // Sistema de manejo de concurrencia mejorado

    // Verificar debounce para evitar comandos duplicados
    if (cmd == lastProcessedCommand && (now - lastCommandTime) < COMMAND_DEBOUNCE) {
      awgLog(LOG_DEBUG, "Comando duplicado ignorado por debounce: " + cmd);
      return;
    }

    // Verificar si hay un comando crítico en proceso
    if (isProcessingCommand) {
      if (now - lastCommandTime < COMMAND_TIMEOUT) {
        awgLog(LOG_WARNING, "⚠️ Comando ignorado - Procesando comando crítico anterior: " + lastProcessedCommand);
        return;
      } else {
        awgLog(LOG_WARNING, "⏰ Timeout de comando crítico anterior, procesando nuevo comando");
        isProcessingCommand = false;
      }
    }

    // Marcar comando como en proceso para comandos críticos
    bool isCriticalCommand = (cmd.startsWith("update_") || cmd.startsWith("mode") || cmd == "on" || cmd == "off" || cmd == "onc" || cmd == "offc" || cmd.startsWith("calib_"));

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
      awgLog(LOG_INFO, "Compresor ON");
      if (mqttClient.connected()) {
        mqttClient.publish(MQTT_TOPIC_STATUS, "COMP_ON");
      }
      sendStatesToDisplay();
    } else if (cmdToProcess == "off" || cmdToProcess == "offc") {
      operationMode = MODE_MANUAL;
      digitalWrite(COMPRESSOR_RELAY_PIN, HIGH);
      awgLog(LOG_INFO, "Compresor OFF");
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
    } else if (cmdToProcess == "offcf") {
      setCompressorFanState(false);
      sendStatesToDisplay();
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
      awgLog(LOG_INFO, "Modo cambiado a AUTO");
      preferences.begin("awg-config", false);
      preferences.putInt("mode", (int)operationMode);
      preferences.end();
      if (mqttClient.connected()) mqttClient.publish(MQTT_TOPIC_STATUS, "MODE_AUTO");

      // ACTIVAR AUTOMÁTICAMENTE COMPRESOR Y VENTILADOR AL CAMBIAR A MODO AUTO
      awgLog(LOG_INFO, "🔄 Activando automáticamente compresor y ventilador para control automático");
      digitalWrite(COMPRESSOR_RELAY_PIN, LOW);
      awgLog(LOG_INFO, "Compresor ON");
      if (mqttClient.connected()) {
        mqttClient.publish(MQTT_TOPIC_STATUS, "COMP_ON");
      }
      setVentiladorState(true);
      forceStartOnModeSwitch = true;  // Forzar una evaluación inmediata del controlador (one-shot)
      // Publicar estados actuales inmediatamente para sincronización
      publishCurrentStates();
      sendStatesToDisplay();
    } else if (cmdToProcess == "mode manual" || cmdToProcess == "mode_manual" || cmdToProcess == "mode:manual") {
      operationMode = MODE_MANUAL;
      awgLog(LOG_INFO, "Modo cambiado a MANUAL");
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
      } else {
        awgLog(LOG_WARNING, "SET_CTRL formato inválido. Uso: SET_CTRL d,mn,mx,samp,alpha");
        Serial1.println("SET_CTRL: ERR");
      }
    } else if (cmd == "test") {
      testSensor();
    } else if (cmd == "system_info") {
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
    } else if (cmd == "recover_sensors") {
      awgLog(LOG_INFO, "🔧 Forzando recuperación manual de sensores...");
      this->performSensorRecoveryInternal();
      awgLog(LOG_INFO, "✅ Recuperación manual completada");
    } else if (cmd == "check_sensors") {
      this->performSensorDiagnostics();
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
        awgLog(LOG_INFO, "Punto VACÍO forzado: " + String(d, 2) + " cm");
      } else {
        awgLog(LOG_ERROR, "No se pudo medir para forzar vacío");
      }
    } else if (cmd == "calib_add") {
      awgLog(LOG_INFO, "Uso: CALIB_ADD <volumen_en_litros>");
    } else if (cmd.startsWith("calib_add")) {
      String volStr = cmd.substring(9);
      volStr.trim();
      float volume = volStr.toFloat();
      addCalibrationPoint(volume);
    } else if (cmd == "calib_upload") {
      awgLog(LOG_INFO, "Uso: CALIB_UPLOAD d1:v1,d2:v2,...");
    } else if (cmd.startsWith("calib_upload")) {  // Formato esperado: CALIB_UPLOAD d1:v1,d2:v2,...
      String payload = cmd.substring(12);
      payload.trim();
      if (payload.length() == 0) {
        awgLog(LOG_WARNING, "Payload vacío para CALIB_UPLOAD");
      } else {
        // Parsear pares separados por coma
        int added = 0;
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
          int colon = pair.indexOf(':');
          if (colon == -1) continue;
          String dStr = pair.substring(0, colon);
          String vStr = pair.substring(colon + 1);
          dStr.trim();
          vStr.trim();
          float d = dStr.toFloat();
          float v = vStr.toFloat();
          if (d > 0 && v >= 0) {
            if (numCalibrationPoints < MAX_CALIBRATION_POINTS) {
              calibrationPoints[numCalibrationPoints].distance = d;
              calibrationPoints[numCalibrationPoints].volume = v;
              numCalibrationPoints++;
              added++;
            }
          }
        }
        if (added > 0) {
          sortCalibrationPoints();
          calculateTankHeight();
          awgLog(LOG_INFO, "CALIB_UPLOAD: añadidos " + String(added) + " puntos");
        } else {
          awgLog(LOG_WARNING, "CALIB_UPLOAD: no se añadieron puntos válidos");
        }
      }
    } else if (cmd == "calib_complete") {
      completeCalibration();
    } else if (cmd == "calib_list") {
      printCalibrationTable();                 // Mostrar tabla actual de calibración
    } else if (cmd.startsWith("calib_set")) {  // Formato esperado: CALIB_SET <idx> <distance_cm> <volume_L>
      char buf[128];
      cmd.toCharArray(buf, sizeof(buf));
      int idx = -1;
      float d = 0.0f;
      float v = 0.0f;
      int parsed = sscanf(buf, "calib_set %d %f %f", &idx, &d, &v);
      if (parsed == 3 && idx >= 0 && idx < MAX_CALIBRATION_POINTS) {
        calibrationPoints[idx].distance = d;
        calibrationPoints[idx].volume = v;
        if (idx >= numCalibrationPoints) numCalibrationPoints = idx + 1;
        sortCalibrationPoints();
        calculateTankHeight();
        saveCalibration();
        awgLog(LOG_INFO, "CALIB_SET: punto " + String(idx) + " = " + String(d, 2) + " cm -> " + String(v, 2) + " L");
      } else {
        awgLog(LOG_WARNING, "Uso: CALIB_SET <idx> <distance_cm> <volume_L>");
      }
    } else if (cmd.startsWith("calib_remove")) {  // Formato: CALIB_REMOVE <idx>
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
      awgLog(LOG_INFO, "CALIB_CLEAR: tabla de calibración vaciada");
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
    // UPDATE_CONFIG: Procesar configuración completa desde la app
    else if (cmd.startsWith("update_config") || cmd.startsWith("update_unified_config")) {
      awgLog(LOG_INFO, "📨 Recibido comando UPDATE_CONFIG desde la app");

      // Extraer payload JSON
      String jsonPayload;
      if (cmd.startsWith("update_config")) {
        jsonPayload = cmd.substring(12);  // Quitar "UPDATE_CONFIG"
      } else if (cmd.startsWith("update_unified_config")) {
        jsonPayload = cmd.substring(20);  // Quitar "UPDATE_UNIFIED_CONFIG"
      } else {
        jsonPayload = cmd;
      }
      awgLog(LOG_INFO, "📄 Payload JSON extraído, longitud: " + String(jsonPayload.length()));
      awgLog(LOG_INFO, "📄 JSON a parsear: " + jsonPayload.substring(0, 200) + (jsonPayload.length() > 200 ? "..." : ""));

      // Parsear JSON con documento más grande para incluir MQTT
      DynamicJsonDocument doc(1536);
      DeserializationError error = deserializeJson(doc, jsonPayload);

      if (error) {
        awgLog(LOG_ERROR, "❌ Error parseando UPDATE_CONFIG: " + String(error.c_str()));
        Serial1.println("UPDATE_CONFIG: ERR");
      } else {
        awgLog(LOG_INFO, "✅ JSON parseado correctamente");

        // Procesar configuración con logs organizados
        String changesSummary = "";
        int changeCount = 0;
        bool hasChanges = false;
        bool mqttChanged = false;

        // Procesar configuración MQTT primero
        if (doc.containsKey("mqtt")) {
          JsonObject mqtt = doc["mqtt"];
          awgLog(LOG_DEBUG, "📡 Procesando configuración MQTT...");

          String newBroker = mqtt["broker"] | MQTT_BROKER;
          int newPort = mqtt["port"] | MQTT_PORT;

          if (newBroker != mqttBroker || newPort != mqttPort) {
            awgLog(LOG_INFO, "🔄 CAMBIO DE CONFIGURACIÓN MQTT DETECTADO:");
            awgLog(LOG_INFO, "  📡 BROKER ANTERIOR: " + mqttBroker + ":" + String(mqttPort));
            awgLog(LOG_INFO, "  🎯 BROKER NUEVO: " + newBroker + ":" + String(newPort));

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
          }
        }

        // Procesar alertas
        if (doc.containsKey("alerts")) {
          JsonObject alerts = doc["alerts"];
          awgLog(LOG_DEBUG, "📊 Procesando configuración de alertas...");

          // Tanque lleno con validación de umbral
          if (alerts.containsKey("tankFullEnabled")) {
            bool newEn = alerts["tankFullEnabled"] | alertTankFull.enabled;
            float newThr = alerts["tankFullThreshold"] | alertTankFull.threshold;
            if (newThr >= 50.0 && newThr <= 100.0) {  // Validar rango del umbral
              if (newEn != alertTankFull.enabled || fabs(newThr - alertTankFull.threshold) > 0.01) {
                alertTankFull.enabled = newEn;
                alertTankFull.threshold = newThr;
                changesSummary += "Tanque lleno: " + String(newEn ? "ON" : "OFF") + " " + String(newThr, 1) + "% | ";
                changeCount++;
                hasChanges = true;
                awgLog(LOG_DEBUG, "✅ Alerta actualizada: " + String(newEn ? "ON" : "OFF") + " " + String(newThr, 1) + "%");
              }
            } else {
              awgLog(LOG_WARNING, "⚠️ Umbral de tanque lleno inválido: " + String(newThr, 1) + "% (debe estar entre 50-100%)");
            }
          }

          // Voltaje bajo con validación de umbral
          if (alerts.containsKey("voltageLowEnabled")) {
            bool newEn = alerts["voltageLowEnabled"] | alertVoltageLow.enabled;
            float newThr = alerts["voltageLowThreshold"] | alertVoltageLow.threshold;
            if (newThr >= 80.0 && newThr <= 130.0) {  // Validar rango del umbral
              if (newEn != alertVoltageLow.enabled || fabs(newThr - alertVoltageLow.threshold) > 0.01) {
                alertVoltageLow.enabled = newEn;
                alertVoltageLow.threshold = newThr;
                changesSummary += "Voltaje bajo: " + String(newEn ? "ON" : "OFF") + " " + String(newThr, 1) + "V | ";
                changeCount++;
                hasChanges = true;
                awgLog(LOG_DEBUG, "✅ Alerta actualizada: " + String(newEn ? "ON" : "OFF") + " " + String(newThr, 1) + "V");
              }
            } else {
              awgLog(LOG_WARNING, "⚠️ Umbral de voltaje bajo inválido: " + String(newThr, 1) + "V (debe estar entre 80-130V)");
            }
          }

          // Humedad baja con validación de umbral
          if (alerts.containsKey("humidityLowEnabled")) {
            bool newEn = alerts["humidityLowEnabled"] | alertHumidityLow.enabled;
            float newThr = alerts["humidityLowThreshold"] | alertHumidityLow.threshold;
            if (newThr >= 5.0 && newThr <= 50.0) {  // Validar rango del umbral
              if (newEn != alertHumidityLow.enabled || fabs(newThr - alertHumidityLow.threshold) > 0.01) {
                alertHumidityLow.enabled = newEn;
                alertHumidityLow.threshold = newThr;
                changesSummary += "Humedad baja: " + String(newEn ? "ON" : "OFF") + " " + String(newThr, 1) + "% | ";
                changeCount++;
                hasChanges = true;
                awgLog(LOG_DEBUG, "✅ Alerta actualizada: " + String(newEn ? "ON" : "OFF") + " " + String(newThr, 1) + "%");
              }
            } else {
              awgLog(LOG_WARNING, "⚠️ Umbral de humedad baja inválido: " + String(newThr, 1) + "% (debe estar entre 5-50%)");
            }
          }
        }

        // Procesar parámetros de control
        if (doc.containsKey("control")) {
          JsonObject control = doc["control"];
          awgLog(LOG_DEBUG, "🎛️ Procesando parámetros de control...");

          // Banda muerta con validación de rango
          if (control.containsKey("deadband")) {
            float newVal = control["deadband"] | control_deadband;
            if (newVal >= 0.5 && newVal <= 10.0) {  // Validar rango razonable
              if (fabs(newVal - control_deadband) > 0.01) {
                control_deadband = newVal;
                changesSummary += "Banda muerta: " + String(newVal, 1) + "°C | ";
                changeCount++;
                hasChanges = true;
                awgLog(LOG_INFO, "✅ Banda muerta actualizada: " + String(newVal, 1) + "°C");
              }
            } else {
              awgLog(LOG_WARNING, "⚠️ Banda muerta inválida: " + String(newVal, 1) + "°C (debe estar entre 0.5-10.0°C)");
            }
          }

          // Temperatura máxima del compresor
          if (control.containsKey("maxCompressorTemp")) {
            float newTemp = control["maxCompressorTemp"] | maxCompressorTemp;
            if (newTemp >= 50.0 && newTemp <= 150.0) {  // Validar rango razonable
              if (fabs(newTemp - maxCompressorTemp) > 0.01) {
                maxCompressorTemp = newTemp;
                alertCompressorTemp.threshold = newTemp;
                changesSummary += "Temp máx compresor: " + String(newTemp, 1) + "°C | ";
                changeCount++;
                hasChanges = true;
                awgLog(LOG_INFO, "✅ Temperatura máxima del compresor actualizada: " + String(newTemp, 1) + "°C");
              }
            } else {
              awgLog(LOG_WARNING, "⚠️ Temperatura máxima del compresor inválida: " + String(newTemp, 1) + "°C (debe estar entre 50.0-150.0°C)");
            }
          }

          // Tiempo mínimo apagado con validación
          if (control.containsKey("minOff")) {
            int newVal = control["minOff"] | control_min_off;
            if (newVal >= 10 && newVal <= 300) {  // Validar rango razonable
              if (newVal != control_min_off) {
                control_min_off = newVal;
                changesSummary += "Min apagado: " + String(newVal) + "s | ";
                changeCount++;
                hasChanges = true;
                awgLog(LOG_INFO, "✅ Tiempo min apagado actualizado: " + String(newVal) + "s");
              }
            } else {
              awgLog(LOG_WARNING, "⚠️ Tiempo min apagado inválido: " + String(newVal) + "s (debe estar entre 10-300s)");
            }
          }

          // Tiempo máximo encendido con validación
          if (control.containsKey("maxOn")) {
            int newVal = control["maxOn"] | control_max_on;
            if (newVal >= 300 && newVal <= 7200) {  // Validar rango razonable
              if (newVal != control_max_on) {
                control_max_on = newVal;
                changesSummary += "Max encendido: " + String(newVal) + "s | ";
                changeCount++;
                hasChanges = true;
                awgLog(LOG_INFO, "✅ Tiempo max encendido actualizado: " + String(newVal) + "s");
              }
            } else {
              awgLog(LOG_WARNING, "⚠️ Tiempo max encendido inválido: " + String(newVal) + "s (debe estar entre 300-7200s)");
            }
          }

          // Intervalo de muestreo con validación
          if (control.containsKey("sampling")) {
            int newVal = control["sampling"] | control_sampling;
            if (newVal >= 2 && newVal <= 60) {  // Validar rango razonable
              if (newVal != control_sampling) {
                control_sampling = newVal;
                changesSummary += "Muestreo: " + String(newVal) + "s | ";
                changeCount++;
                hasChanges = true;
                awgLog(LOG_INFO, "✅ Intervalo de muestreo actualizado: " + String(newVal) + "s");
              }
            } else {
              awgLog(LOG_WARNING, "⚠️ Intervalo de muestreo inválido: " + String(newVal) + "s (debe estar entre 2-60s)");
            }
          }

          // Factor de suavizado con validación
          if (control.containsKey("alpha")) {
            float newVal = control["alpha"] | control_alpha;
            if (newVal >= 0.0 && newVal <= 1.0) {  // Validar rango 0-1
              if (fabs(newVal - control_alpha) > 0.01) {
                control_alpha = newVal;
                changesSummary += "Suavizado: " + String(newVal, 2) + " | ";
                changeCount++;
                hasChanges = true;
                awgLog(LOG_INFO, "✅ Factor de suavizado actualizado: " + String(newVal, 2));
              }
            } else {
              awgLog(LOG_WARNING, "⚠️ Factor de suavizado inválido: " + String(newVal, 2) + " (debe estar entre 0.0-1.0)");
            }
          }
        }

        // Procesar configuración del tanque con validaciones mejoradas
        if (doc.containsKey("tank")) {
          JsonObject tank = doc["tank"];
          awgLog(LOG_DEBUG, "🪣 Procesando configuración del tanque...");

          // Capacidad del tanque
          if (tank.containsKey("capacity")) {
            float newCapacity = tank["capacity"] | 1000.0f;
            if (newCapacity > 0 && newCapacity <= 10000) {  // Validar rango razonable
              if (fabs(newCapacity - tankCapacityLiters) > 0.01) {
                tankCapacityLiters = newCapacity;
                changesSummary += "Capacidad tanque: " + String(newCapacity, 0) + "L | ";
                changeCount++;
                hasChanges = true;
                awgLog(LOG_INFO, "✅ Capacidad del tanque actualizada: " + String(newCapacity, 0) + "L");
              }
            } else {
              awgLog(LOG_WARNING, "⚠️ Capacidad del tanque inválida: " + String(newCapacity, 0) + "L (ignorando)");
            }
          }

          // Estado de calibración
          if (tank.containsKey("isCalibrated")) {
            bool newCalibrated = tank["isCalibrated"] | isCalibrated;
            if (newCalibrated != isCalibrated) {
              isCalibrated = newCalibrated;
              changesSummary += "Calibrado: " + String(newCalibrated ? "SI" : "NO") + " | ";
              changeCount++;
              hasChanges = true;
              awgLog(LOG_INFO, "✅ Estado de calibración actualizado: " + String(newCalibrated ? "SI" : "NO"));
            }
          }

          // Puntos de calibración con validación completa
          if (tank.containsKey("calibrationPoints")) {
            JsonArray points = tank["calibrationPoints"];
            int validPoints = 0;
            if (points.size() > 0 && points.size() <= MAX_CALIBRATION_POINTS) {
              // Validar y cargar puntos
              for (int i = 0; i < points.size() && validPoints < MAX_CALIBRATION_POINTS; i++) {
                float dist = points[i]["distance"] | -1.0f;
                float vol = points[i]["liters"] | -1.0f;

                // Validar valores
                if (dist >= 0 && dist <= 400 && vol >= 0 && vol <= 10000) {
                  calibrationPoints[validPoints].distance = dist;
                  calibrationPoints[validPoints].volume = vol;
                  validPoints++;
                } else {
                  awgLog(LOG_WARNING, "⚠️ Punto de calibración inválido ignorado: dist=" + String(dist, 1) + ", vol=" + String(vol, 1));
                }
              }
              if (validPoints > 0) {
                numCalibrationPoints = validPoints;
                sortCalibrationPoints();
                calculateTankHeight();
                saveCalibration();
                changesSummary += "Puntos calibración: " + String(validPoints) + " | ";
                changeCount++;
                hasChanges = true;
                awgLog(LOG_INFO, "✅ Puntos de calibración actualizados: " + String(validPoints) + " puntos válidos");
              } else {
                awgLog(LOG_WARNING, "⚠️ No se encontraron puntos de calibración válidos");
              }
            } else {
              awgLog(LOG_WARNING, "⚠️ Número de puntos de calibración inválido: " + String(points.size()));
            }
          }

          // Offset ultrasónico con validación
          if (tank.containsKey("ultrasonicOffset")) {
            float newOffset = tank["ultrasonicOffset"] | sensorOffset;
            if (newOffset >= -50.0 && newOffset <= 50.0) {  // Validar rango razonable
              if (fabs(newOffset - sensorOffset) > 0.01) {
                sensorOffset = newOffset;
                changesSummary += "Offset sensor: " + String(newOffset, 1) + "cm | ";
                changeCount++;
                hasChanges = true;
                awgLog(LOG_INFO, "✅ Offset del sensor actualizado: " + String(newOffset, 1) + "cm");
              }
            } else {
              awgLog(LOG_WARNING, "⚠️ Offset del sensor fuera de rango: " + String(newOffset, 1) + "cm (ignorando)");
            }
          }
        }

        // Procesar configuración de notificaciones
        if (doc.containsKey("notifications")) {
          JsonObject notifications = doc["notifications"];
          awgLog(LOG_DEBUG, "🔔 Procesando configuración de notificaciones...");

          // Reporte diario
          if (notifications.containsKey("dailyReportEnabled")) {
            // Nota: Esta configuración no se guarda actualmente en el ESP32
            // Solo se maneja en la app, pero podemos mostrar que se recibió
            bool dailyEnabled = notifications["dailyReportEnabled"] | false;
            awgLog(LOG_INFO, "ℹ️ Reporte diario: " + String(dailyEnabled ? "HABILITADO" : "DESHABILITADO"));
          }

          if (notifications.containsKey("dailyReportHour")) {
            int hour = notifications["dailyReportHour"] | 20;
            int minute = notifications["dailyReportMinute"] | 0;
            awgLog(LOG_INFO, "ℹ️ Hora reporte diario: " + String(hour) + ":" + String(minute < 10 ? "0" : "") + String(minute));
          }

          // Notificaciones push
          if (notifications.containsKey("showNotifications")) {
            bool showNotif = notifications["showNotifications"] | true;
            awgLog(LOG_INFO, "ℹ️ Notificaciones push: " + String(showNotif ? "HABILITADAS" : "DESHABILITADAS"));
          }
        }

        // Reconectar MQTT si cambió la configuración
        if (mqttChanged) {
          awgLog(LOG_INFO, "🔌 Reconectando MQTT con nueva configuración...");
          mqttClient.disconnect();
          delay(1000);
          connectMQTT();

          // Publicar estado de conexión actualizado
          if (mqttClient.connected()) {
            awgLog(LOG_INFO, "✅ Reconexión MQTT exitosa - Broker actual: " + mqttBroker + ":" + String(mqttPort));
            mqttClient.publish(MQTT_TOPIC_STATUS, "ESP32_AWG_ONLINE", true);
            // Re-suscribirse a los topics después de reconectar
            mqttClient.subscribe(MQTT_TOPIC_CONTROL);
            mqttClient.subscribe(MQTT_TOPIC_CONFIG);
          } else {
            awgLog(LOG_ERROR, "❌ Reconexión MQTT fallida - Broker configurado: " + mqttBroker + ":" + String(mqttPort));
          }
        }

        // Mostrar resumen de cambios con visualización mejorada
        if (hasChanges) {
          awgLog(LOG_INFO, "✅ Configuración completa actualizada exitosamente (" + String(changeCount) + " cambios)");
          if (changesSummary.length() > 0) {
            awgLog(LOG_DEBUG, "📋 Cambios: " + changesSummary.substring(0, changesSummary.length() - 3));
          }

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

          Serial.println("🪣 CONFIGURACIÓN DEL TANQUE:");
          Serial.printf("  Calibrado: %s\n", isCalibrated ? "SI" : "NO");
          Serial.printf("  Offset ultrasónico: %.1f cm\n", sensorOffset);
          Serial.printf("  Capacidad tanque: %.0f L\n", tankCapacityLiters);
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

          // Enviar confirmación robusta a la app vía MQTT
          sendConfigAckToApp(changeCount);
          Serial1.println("UPDATE_CONFIG: OK");
          awgLog(LOG_INFO, "🎉 Actualización de configuración completada exitosamente");
        } else {
          awgLog(LOG_INFO, "ℹ️ Configuración recibida sin cambios");
          sendConfigAckToApp(0);  // Confirmación de "sin cambios"
          Serial1.println("UPDATE_CONFIG: OK");
        }
      }
    } else if (cmd == "system_status") {
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
      Serial.printf("║   • Capacidad del tanque: %.0f L\n", tankCapacityLiters);
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
    } else if (cmd == "backup_config") {
      /* Genera un respaldo completo de toda la configuración del sistema AWG en formato JSON.
         * El backup incluye: Configuración MQTT - Parámetros de control - Configuración de alertas - Configuración del tanque - Tabla completa de puntos de calibración
         *
         * Uso del backup:
         * 1. Se muestra en Serial como "BACKUP_CONFIG:{json}" para copiado manual
         * 2. Se envía por MQTT al topic de status para que la app lo capture automáticamente
         * 3. La app puede guardar este JSON para restauración futura
         * 4. Útil para backup antes de actualizaciones o troubleshooting*/

      awgLog(LOG_INFO, "💾 Generando backup completo de configuración del sistema AWG...");

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
      awgLog(LOG_INFO, "📄 Backup generado - Copie el JSON de Serial para guardar manualmente");

      // Enviar backup por MQTT para captura automática por la app
      if (mqttClient.connected()) {
        mqttClient.publish(MQTT_TOPIC_STATUS, ("BACKUP:" + backupStr).c_str());
        awgLog(LOG_INFO, "📡 Backup enviado por MQTT para captura automática por la app");
      } else {
        awgLog(LOG_WARNING, "⚠️ MQTT no conectado - Backup solo disponible en Serial");
      }
      awgLog(LOG_INFO, "✅ Backup de configuración completado exitosamente");
      awgLog(LOG_INFO, "💡 Use este backup para restaurar configuración o troubleshooting");
    } else if (cmdToProcess == "help") {
      printHelp();
    } else if (cmdToProcess.length() > 0) {
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
    help += "║   • ONV/OFFV: Encender/Apagar ventilador\n";
    help += "║   • ONCF/OFFCF: Encender/Apagar ventilador del compresor\n";
    help += "║   • ONB/OFFB: Encender/Apagar bomba\n";
    help += "║   • MODE AUTO/MANUAL: Cambiar modo de operación\n";
    help += "║\n";
    help += "║ ⚙️ CONFIGURACIÓN:\n";
    help += "║   • SET_CTRL d,mnOff,mxOn,samp,alpha: Ajustar parámetros (°C,seg,seg,seg,0-1)\n";
    help += "║   • SET_OFFSET X.X: Ajustar offset del sensor ultrasónico (cm)\n";
    help += "║   • SET_LOG_LEVEL X: Nivel logs (0=ERROR,1=WARNING,2=INFO,3=DEBUG)\n";
    help += "║   • SET_MAX_TEMP X.X: Ajustar temperatura máxima del compresor (°C)\n";
    help += "║   • SET_TANK_CAPACITY X.X: Ajustar capacidad del tanque (litros)\n";
    help += "║\n";
    help += "║ 📊 MONITOREO:\n";
    help += "║   • SYSTEM_STATUS: Estado completo del sistema\n";
    help += "║   • TEST: Probar sensor ultrasónico\n";
    help += "║   • CHECK_SENSORS: Diagnóstico detallado de todos los sensores\n";
    help += "║\n";
    help += "║ 🪣 CALIBRACIÓN:\n";
    help += "║   • CALIBRATE: Iniciar calibración automática (tanque vacío)\n";
    help += "║   • CALIB_ADD X.X: Añadir punto con volumen actual (X.X = litros)\n";
    help += "║   • CALIB_COMPLETE: Finalizar calibración y guardar\n";
    help += "║   • CALIB_LIST: Mostrar tabla de puntos de calibración\n";
    help += "║   • CALIB_SET <idx> <dist_cm> <vol_L>: Modificar punto\n";
    help += "║   • CALIB_REMOVE <idx>: Eliminar punto de calibración\n";
    help += "║   • CALIB_CLEAR: Borrar toda la tabla de calibración\n";
    help += "║   • CALIB_UPLOAD d1:v1,d2:v2,...: Subir tabla desde CSV\n";
    help += "║\n";
    help += "║ 🔧 MANTENIMIENTO:\n";
    help += "║   • BACKUP_CONFIG: Generar backup JSON de configuración\n";
    help += "║   • CLEAR_STATS: Resetear estadísticas del sistema\n";
    help += "║   • RECOVER_SENSORS: Forzar recuperación de sensores\n";
    help += "║   • FACTORY_RESET: Reset completo de fábrica\n";
    help += "║   • RESET: Reiniciar sistema\n";
    help += "║\n";
    help += "║ ❓ AYUDA:\n";
    help += "║   • HELP: Mostrar esta ayuda\n";
    help += "╚══════════════════════════════════════════════════════════════╝\n";
    Serial.println(help);
  }

  void testSensor() {
    awgLog(LOG_INFO, "=== PRUEBA SENSOR ULTRASÓNICO ===");
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
    awgLog(LOG_INFO, "=== PRUEBA FINALIZADA ===");
  }

  float validateTemp(float temp) {
    return (temp > -50.0 && temp < 100.0) ? temp : 0.0;
  }

  float validateHumidity(float hum) {
    return (hum >= 0.0 && hum <= 100.0) ? hum : 0.0;
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

  // Función para calcular temperatura del termistor NTC
  float calculateTemperature(float resistance) {
    if (resistance <= 0) return -273.15;  // Valor inválido
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
    evapSmoothed = control_alpha * rawTemp + (1.0f - control_alpha) * evapSmoothed;
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
      awgLog(LOG_INFO, "Compresor OFF (tiempo máximo excedido)");
      if (mqttClient.connected()) {
        mqttClient.publish(MQTT_TOPIC_STATUS, "COMP_OFF");
      }
      compressorOffStart = nowMs;
      compressorOnStart = 0;
    } else if (evapSmoothed <= offThreshold) {
      // Apagar por histeresis cuando temperatura cae suficientemente debajo del punto de rocío
      digitalWrite(COMPRESSOR_RELAY_PIN, HIGH);
      awgLog(LOG_INFO, "Compresor OFF (histeresis)");
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
        awgLog(LOG_INFO, "Compresor ON (control automático)");
        if (mqttClient.connected()) {
          mqttClient.publish(MQTT_TOPIC_STATUS, "COMP_ON");
        }
        compressorOnStart = nowMs;
        compressorOffStart = 0;
        forceStartOnModeSwitch = false;
      }
    } else {
      awgLog(LOG_DEBUG, "Esperando min_off para poder arrancar compresor");  // log de espera para diagnóstico (nivel DEBUG)
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
  // Alerta voltaje = 0 (siempre habilitada)
  bool isZero = (data.voltage <= 0.1);
  if (isZero && !alertVoltageZeroActive) {
    String message = "El dispositivo Dropster AWG no esta siendo alimentado - Falla Electrica.";
    sendAlert("voltage_zero", message, data.voltage);
    alertVoltageZeroActive = true;
  } else if (!isZero && alertVoltageZeroActive) {
    alertVoltageZeroActive = false;  // Reset cuando se recupera
  }

  // Alerta voltaje bajo
  if (alertVoltageLow.enabled && data.voltage > 0.1) {  // Solo si hay voltaje
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
      awgLog(LOG_INFO, "✅ Alerta humedad baja resuelta - Reset");
      alertHumidityLowActive = false;  // Reset cuando se recupera
    }
  } else {
    awgLog(LOG_DEBUG, "💨 Alerta humedad baja no verificada - Habilitada: " + String(alertHumidityLow.enabled ? "SI" : "NO") + ", BME online: " + String(bmeOnline ? "SI" : "NO") + ", Humedad válida: " + String(data.bmeHum > 0 ? "SI" : "NO"));
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
    } else if (!isHigh && alertCompressorTempActive) {
      awgLog(LOG_INFO, "✅ Temperatura del compresor normalizada");
      alertCompressorTempActive = false;  // Reset cuando baja
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
    awgLog(LOG_WARNING, "⚠️ Mensaje MQTT vacío o inválido recibido");
    return;
  }
  String message;

  for (unsigned int i = 0; i < length; i++) {
    message += (char)payload[i];
  }
  String topicStr = String(topic);
  awgLog(LOG_INFO, "📨 MQTT recibido - Topic: '" + topicStr + "', Longitud: " + String(length) + " bytes");

  // Log detallado para mensajes de control y config
  if (topicStr == MQTT_TOPIC_CONTROL) {
    awgLog(LOG_INFO, "🎛️ Comando de control recibido: " + message.substring(0, 100) + (message.length() > 100 ? "..." : ""));
  } else if (topicStr == MQTT_TOPIC_CONFIG) {
    awgLog(LOG_INFO, "⚙️ Comando de configuración recibido: " + message.substring(0, 100) + (message.length() > 100 ? "..." : ""));
  }
  // Procesar mensaje según el topic
  if (topicStr == MQTT_TOPIC_CONTROL) {
    awgLog(LOG_DEBUG, "🔄 Procesando comando de control...");
    sensorManager.processCommand(message);
    awgLog(LOG_DEBUG, "✅ Comando procesado");
  } else if (topicStr == MQTT_TOPIC_CONFIG) {
    awgLog(LOG_DEBUG, "🔄 Procesando comando de configuración...");
    sensorManager.processCommand(message);
    awgLog(LOG_DEBUG, "✅ Comando de configuración procesado");
  } else {
    awgLog(LOG_DEBUG, "📭 Mensaje ignorado - Topic: " + topicStr + " (no es control ni config)");
  }
}

void setVentiladorState(bool newState) {
  digitalWrite(VENTILADOR_RELAY_PIN, newState ? LOW : HIGH);
  awgLog(LOG_INFO, "Ventilador " + String(newState ? "ON" : "OFF"));
  // Notificar a pantalla vía UART1
  Serial1.println(String("VENT:") + (newState ? "ON" : "OFF"));
  if (mqttClient.connected()) {
    mqttClient.publish(MQTT_TOPIC_STATUS, ("VENT_" + String(newState ? "ON" : "OFF")).c_str());
  }
}

void setCompressorFanState(bool newState) {
  digitalWrite(COMPRESSOR_FAN_RELAY_PIN, newState ? LOW : HIGH);
  awgLog(LOG_INFO, "Ventilador compresor " + String(newState ? "ON" : "OFF"));
  // Notificar a pantalla vía UART1
  Serial1.println(String("CFAN:") + (newState ? "ON" : "OFF"));
  if (mqttClient.connected()) {
    mqttClient.publish(MQTT_TOPIC_STATUS, ("CFAN_" + String(newState ? "ON" : "OFF")).c_str());
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
        return;
      }
    }
    // Verificar voltaje mínimo
    AWGSensorManager::SensorData_t sensorData = sensorManager.getSensorData();
    if (sensorManager.getPzemOnline() && sensorData.voltage > 0.1 && sensorData.voltage < 100.0) {
      awgLog(LOG_ERROR, "🚫 SEGURIDAD: Bomba NO encendida - Voltaje bajo: " + String(sensorData.voltage, 1) + "V (mín: 100.0V)");
      return;
    }
  }
  digitalWrite(PUMP_RELAY_PIN, newState ? LOW : HIGH);
  awgLog(LOG_INFO, "Bomba " + String(newState ? "ON" : "OFF"));
  // Notificar a pantalla vía UART1
  Serial1.println(String("PUMP:") + (newState ? "ON" : "OFF"));
  if (mqttClient.connected()) {
    mqttClient.publish(MQTT_TOPIC_STATUS, ("PUMP_" + String(newState ? "ON" : "OFF")).c_str());
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

  if (rtcAvailable) {
    DateTime now = rtc.now();
    statusDoc["timestamp"] = now.unixtime();
  } else {
    statusDoc["timestamp"] = millis() / 1000;
  }

  char statusBuffer[300];
  size_t statusLen = serializeJson(statusDoc, statusBuffer, sizeof(statusBuffer));
  if (statusLen > 0 && statusLen < sizeof(statusBuffer)) {
    mqttClient.publish(MQTT_TOPIC_STATUS, statusBuffer, false);
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
  if (digitalRead(CONFIG_BUTTON_PIN) == LOW) {
    awgLog(LOG_INFO, "Iniciando portal de configuración...");
    wifiManager.setConfigPortalTimeout(WIFI_CONFIG_PORTAL_TIMEOUT);
    if (!wifiManager.startConfigPortal("AWG_Config_AP")) {
      delay(3000);
      ESP.restart();
    }
  } else {
    wifiManager.setConnectTimeout(WIFI_CONNECT_TIMEOUT);
    if (!wifiManager.autoConnect("AWG_Config_AP")) {
      delay(3000);
      ESP.restart();
    }
  }
  if (WiFi.status() == WL_CONNECTED) {
    awgLog(LOG_INFO, "Conectado a WiFi: " + WiFi.SSID());
  }
}

void setupMQTT() {
  mqttClient.setServer(mqttBroker.c_str(), mqttPort);
  mqttClient.setCallback(onMqttMessage);
  connectMQTT();
}

void connectMQTT() {
  awgLog(LOG_INFO, "🔌 Iniciando conexión MQTT...");
  awgLog(LOG_INFO, "🎯 BROKER MQTT OBJETIVO: " + mqttBroker + ":" + String(mqttPort));
  awgLog(LOG_INFO, "📝 TOPIC MQTT OBJETIVO: " + String(MQTT_TOPIC_DATA));
  awgLog(LOG_INFO, "🔍 Verificando configuración MQTT actual...");
  String clientId = MQTT_CLIENT_ID;  // Client ID simple para conexión MQTT

  // Last Will (mensaje que el broker publicará si el cliente se desconecta inesperadamente)
  const char* willTopic = MQTT_TOPIC_STATUS;
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
      mqttClient.subscribe(MQTT_TOPIC_CONTROL);                         // Suscribirse al tópico de control
      mqttClient.subscribe(MQTT_TOPIC_CONFIG);                          // Suscribirse al tópico de configuración
      mqttClient.publish(MQTT_TOPIC_STATUS, "ESP32_AWG_ONLINE", true);  // Publicar estado online (retained)
      awgLog(LOG_INFO, "📤 Estado online publicado");
      break;
    } else {
      awgLog(LOG_WARNING, "❌ Fallo conexión MQTT, código de estado: " + String(mqttClient.state()));
      awgLog(LOG_WARNING, "⏳ Reintentando en " + String(backoff) + "ms...");
      attempts++;
      delay(backoff);
      backoff = min(backoff * 2, maxBackoff);
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
  delay(1000);
  awgLog(LOG_INFO, "🚀 Iniciando sistema AWG...");
  awgLog(LOG_INFO, "📋 Versión del firmware: v1.0");
  pinMode(CONFIG_BUTTON_PIN, INPUT_PULLUP);
  loadSystemStats();  // Cargar estadísticas del sistema

  // Cargar configuración MQTT antes de inicializar sensores
  awgLog(LOG_INFO, "⚙️ Cargando configuración MQTT...");
  loadMqttConfig();
  loadAlertConfig();
  awgLog(LOG_INFO, "🔧 Inicializando componentes del sistema...");
  sensorManager.begin();
  setupWiFi();
  setupMQTT();

  // Registrar inicio del sistema
  systemStartTime = millis();
  rebootCount++;
  awgLog(LOG_INFO, "✅ Sistema Dropster AWG iniciado completamente");
  awgLog(LOG_INFO, "🎯 === CONFIGURACIÓN MQTT ACTIVA ===");
  awgLog(LOG_INFO, "  📡 BROKER: " + mqttBroker + ":" + String(mqttPort));
  awgLog(LOG_INFO, "  🔗 ESTADO: Online");
  awgLog(LOG_INFO, "=====================================");
}

void loop() {
  unsigned long now = millis();
  if (digitalRead(CONFIG_BUTTON_PIN) == LOW) {
    if (now - configPortalTimeout > CONFIG_BUTTON_TIMEOUT) {
      configPortalTimeout = now;
      WiFi.disconnect();
      mqttClient.disconnect();
      delay(1000);
      setupWiFi();
      setupMQTT();
    }
  }

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
        // Publicar estado consolidado del sistema con información de conectividad
        publishConsolidatedStatus();
        lastHeartbeat = now;
      }
    }
  } else if (now - lastWiFiCheck >= WIFI_CHECK_INTERVAL) {
    WiFi.reconnect();
    wifiReconnectCount++;
    lastWiFiCheck = now;
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
  if (now - lastStatsSave >= 300000) {
    totalUptime += (now - lastStatsSave) / 1000;
    saveSystemStats();
    lastStatsSave = now;
  }
  delay(10);
}
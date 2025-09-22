#include <Wire.h>
#include <math.h>
#include <WiFi.h>
#include <WiFiManager.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>
#include <Preferences.h>
#include <NewPing.h>
#include <Adafruit_BME280.h>
#include <Adafruit_SHT31.h>
#include <PZEM004Tv30.h>
#include <RTClib.h>
#include "esp32_mqtt_config.h"

#define LOG_MSG_LEN 240

 // Instancias globales
 WiFiManager wifiManager;
WiFiClient espClient;
PubSubClient mqttClient(espClient);
RTC_DS3231 rtc;
bool rtcAvailable = false;              // indicador global para evitar llamar rtc.begin() repetidamente en funciones de log
Preferences preferences;
NewPing sonar(TRIG_PIN, ECHO_PIN, 400); // 400 cm máximo

// Variables de sistema
int logLevel = LOG_INFO;
bool shouldSaveConfig = false;
bool configPortalRequested = false;
unsigned long configPortalTimeout = 0;
float smoothedDistance = 0.0;
bool firstDistanceReading = true;
bool systemState = false;           // false = OFF, true = ON
unsigned long lastStateChange = 0;

// Modo de operación: MANUAL o AUTOMÁTICO
enum OperationMode { MODE_MANUAL = 0, MODE_AUTO = 1 };
OperationMode operationMode = MODE_MANUAL;
// Flags de comportamiento
bool forceStartOnModeSwitch = false;      // one-shot: al cambiar a AUTO, permitir arranque inmediato
bool ventilatorManualOverride = false;    // si true, AUTO no modifica el ventilador

// Parámetros de control (valores iniciales según tu elección)
float control_deadband = 3.0f;         // en °C
int control_min_off = 60;              // segundos mínimos apagado antes de volver a encender
int control_max_on = 1800;             // segundos máximos encendido continuo
int control_sampling = 8;              // intervalo de muestreo en segundos para la lógica de control
float control_alpha = 0.2f;            // suavizado exponencial para la lectura del evaporador

// Tiempos para control del compresor
unsigned long compressorOnStart = 0;
unsigned long compressorOffStart = 0;
unsigned long lastControlSample = 0; // timestamp de último muestreo de control
// Buffer de logs circular (armazenamiento en char[][] para evitar fragmentación)
char logBuffer[LOG_BUFFER_SIZE][LOG_MSG_LEN];
int logBufferIndex = 0;

// Variables para calibración del sensor
float sensorOffset = 0.0;
bool isCalibrated = false;
float emptyTankDistance = 0.0;
float tankHeight = 0.0;
float lastValidDistance = 0.0;

// Declaración anticipada de funciones
void setupWiFi();
void setupMQTT();
void connectMQTT();
void onMqttMessage(char* topic, byte* payload, unsigned int length);
void saveConfigCallback();
void awgLog(int level, const String &message);
void setSystemState(bool newState);
void setCompressorState(bool newState);
void setVentiladorState(bool newState);
void setPumpState(bool newState);
String getSystemStateJSON();

// --- Gestión de sensores ---
class AWGSensorManager {
private:
    Adafruit_BME280 bme;
    Adafruit_SHT31 sht31_1;
    PZEM004Tv30 pzem;

// Control automático - estado interno para el algoritmo PID/simple
float evapSmoothed = 0.0f;
bool evapSmoothedInitialized = false;
// Prototipo: la implementación de processControl() está definida fuera de la clase
   struct SensorData {
        float bmeTemp = 0, bmeHum = 0, bmePres = 0;
        float sht1Temp = 0, sht1Hum = 0;
        float distance = 0;
        float voltage = 0, current = 0, power = 0, energy = 0;
        float dewPoint = 0, absHumidity = 0, waterVolume = 0;
        int compressorState = 0;
        int ventiladorState = 0;
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
    bool rtcOnline = false;

    // Variables para calibración
    typedef struct {
        float distance; // distancia en cm
        float volume;   // volumen en litros
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

    float interpolateVolume(float distance) {
        // búsqueda binaria para encontrar intervalo + interpolación lineal.
        if (numCalibrationPoints < 2) {
            if (!calibrationMode) {
                awgLog(LOG_WARNING, "No hay suficientes puntos de calibración");
            }
            return 0.0;
        }
    
        // Validar rango general
        if (distance > calibrationPoints[0].distance + 2.0) {
            // Demasiado lejos - probablemente error de medición
            return 0.0;
        }
        if (distance < calibrationPoints[numCalibrationPoints - 1].distance - 2.0) {
            // Demasiado cerca - devolver volumen máximo conocido
            return calibrationPoints[numCalibrationPoints - 1].volume;
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
    
        // Protección contra división por cero
        if (fabs(x1 - x0) < 1e-6) {
            return y0;
        }
    
        // Interpolación lineal por defecto (robusta y rápida)
        float v = y0 + (y1 - y0) * ((x0 - distance) / (x0 - x1));
    
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
                    // Mezclar suavemente resultado lineal y cuadrático (evitar oscilaciones)
                    v = (v * 0.6f) + (vquad * 0.4f);
                }
            }
        }
        // Asegurar rango válido
        if (v < 0.0) v = 0.0;
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
        logLevel = preferences.getInt("logLevel", LOG_INFO); // Cargar nivel de logs
        int calibVer = preferences.getInt("calibVer", 0);
        String calibType = preferences.getString("calibType", "table");
        // Cargar parámetros de control si existen (si no, mantener valores por defecto)
        control_deadband = preferences.getFloat("ctrl_deadband", control_deadband);
        control_min_off = preferences.getInt("ctrl_min_off", control_min_off);
        control_max_on = preferences.getInt("ctrl_max_on", control_max_on);
        control_sampling = preferences.getInt("ctrl_sampling", control_sampling);
        control_alpha = preferences.getFloat("ctrl_alpha", control_alpha);
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
                    awgLog(LOG_WARNING, "❌ Relación distancia-volumen anómala entre puntos " + String(i) + " y " + String(i+1));
                    return false;
                }
            }
        }
    return true;
    }

public:
    void processControl();
    AWGSensorManager() :
        sht31_1(&Wire),
        pzem(Serial2, RX2_PIN, TX2_PIN)
    {
        resetCalibration();
    }

    bool begin() {
        loadCalibration();
        
        Wire.begin(SDA_PIN, SCL_PIN);
        Serial1.begin(115200, SERIAL_8N1, RX1_PIN, TX1_PIN);
        Serial2.begin(9600, SERIAL_8N1, RX2_PIN, TX2_PIN);
        pinMode(COMPRESSOR_RELAY_PIN, OUTPUT);
        digitalWrite(COMPRESSOR_RELAY_PIN, HIGH);
        pinMode(VENTILADOR_RELAY_PIN, OUTPUT);
        digitalWrite(VENTILADOR_RELAY_PIN, HIGH);
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
        
        // Detección del PZEM
        pzemOnline = false;
        for (int i = 0; i < 3; i++) {
            float voltage = pzem.voltage();
            if (!isnan(voltage) && voltage > 0) {
                pzemOnline = true;
                break;
            }
            delay(500);
        }

        // Test inicial del sensor ultrasónico
        float testDistance = getAverageDistance(3);
        if (testDistance >= 0) {
            lastValidDistance = testDistance;
            awgLog(LOG_INFO, "Sensor ultrasónico OK - Distancia: " + String(testDistance, 2) + " cm");
        } else {
            awgLog(LOG_WARNING, "Sensor ultrasónico presenta problemas");
        }

        awgLog(LOG_INFO, "Inicialización de sensores completada");
        return bmeOnline || sht1Online || pzemOnline;
    }

    void readSensors() {
        // Obtener timestamp si RTC está disponible
        if (rtcOnline) {
            DateTime now = rtc.now();
            data.timestamp = String(now.year()) + "-" +
                            String(now.month()) + "-" +
                            String(now.day()) + " " +
                            String(now.hour()) + ":" +
                            String(now.minute()) + ":" +
                            String(now.second());
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

        // Leer PZEM si está disponible
        if (pzemOnline && millis() - lastPZEMRead > 2000) {
            data.voltage = constrain(pzem.voltage(), 0.0, 300.0);
            data.current = constrain(pzem.current(), 0.0, 100.0);
            data.power = constrain(pzem.power(), 0.0, 10000.0);
            data.energy = max(0.0f, pzem.energy());
            lastPZEMRead = millis();

            if (data.voltage <= 0.1) {
                data.current = 0.0;
                data.power = 0.0;
                data.voltage = 0.0;
            }
        } else if (!pzemOnline) {
            data.voltage = 0.0;
            data.current = 0.0;
            data.power = 0.0;
            data.energy = 0.0;
        }

        // Estados de relés
        data.compressorState = digitalRead(COMPRESSOR_RELAY_PIN) == LOW ? 1 : 0;
        data.ventiladorState = digitalRead(VENTILADOR_RELAY_PIN) == LOW ? 1 : 0;
        data.pumpState = digitalRead(PUMP_RELAY_PIN) == LOW ? 1 : 0;

        //----------------------- Cálculos -------------------------
        data.dewPoint = calculateDewPoint(data.sht1Temp, data.sht1Hum);
        data.absHumidity = calculateAbsoluteHumidity(data.bmeTemp, data.bmeHum, data.bmePres);
        data.waterVolume = calculateWaterVolume(data.distance);
    }
    
    float getDistance() {
        unsigned int duration = sonar.ping();
        if (duration == 0 || duration > 30000) {
            return -1.0;
        }

        float temperature = data.bmeTemp; //correccion por temperatura
        if (temperature == 0.0) {
            temperature = 25.0; // Valor por defecto si no hay sensor de temperatura
        }
    
        // velocidad del sonido en m/s
        float speedOfSound = 331.3 + (0.606 * temperature);
        // duration está en microsegundos -> convertir a segundos
        float duration_s = duration * 1e-6f;
        // distancia en cm = (tiempo * velocidad * 100) / 2
        float distance = (duration_s * speedOfSound * 100.0f) / 2.0f;
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
    
        // Mediana
        float median = sorted[validSamples / 2];
    
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
        if (mad < 0.001) mad = 0.001; // evitar división por cero
    
        // Filtrar muestras que estén a más de k*MAD del median (k típicamente 3-5)
        const float k = 3.5;
        float filtered[validSamples];
        int fcount = 0;
        for (int i = 0; i < validSamples; i++) {
            if (fabs(values[i] - median) <= k * mad) {
                filtered[fcount++] = values[i];
            }
        }
    
        if (fcount == 0) {
            // Si todo fue filtrado, devolver la mediana
            return median;
        }
    
        // Si hay suficientes valores, devolver la media de los filtrados; si no, la mediana.
        if (fcount >= 3) {
            float sum = 0.0;
            for (int i = 0; i < fcount; i++) sum += filtered[i];
            return sum / fcount;
        } else {
            // Si pocos valores, usar mediana (más robusto)
            return median;
        }
    }

    void transmitData() {
        int len = snprintf(txBuffer, sizeof(txBuffer),
            "%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%d,%d,%d,%.2f\n",
            data.bmeTemp, data.bmePres, data.bmeHum, data.absHumidity, data.dewPoint,
            data.waterVolume, data.sht1Temp, data.sht1Hum,
            data.voltage, data.current, data.power, data.energy,
            data.compressorState, data.ventiladorState, data.pumpState,
            (tankHeight > 0 ? (tankHeight - (data.distance - SENSOR_TO_TOP)) : 0)
        );
        
        if (len > 0 && len < (int)sizeof(txBuffer)) {
            Serial1.write(txBuffer, len);
        }
    }

    void transmitMQTTData() {
        if (!mqttClient.connected()) {
            return;
        }

        StaticJsonDocument<300> doc;

        if (bmeOnline) {
            doc["t"] = round(data.bmeTemp * 100) / 100;
            doc["h"] = round(data.bmeHum * 100) / 100;
            doc["p"] = round(data.bmePres * 100) / 100;
        }
        
        doc["w"] = round(data.waterVolume * 100) / 100;
        
        if (sht1Online) {
            doc["te"] = round(data.sht1Temp * 100) / 100;
            doc["he"] = round(data.sht1Hum * 100) / 100;
        }
        
        doc["dp"] = round(data.dewPoint * 100) / 100;
        doc["ha"] = round(data.absHumidity * 100) / 100;
        
        if (pzemOnline) {
            if (data.voltage > 0) doc["v"] = round(data.voltage * 100) / 100;
            if (data.current >= 0) doc["c"] = round(data.current * 100) / 100;
            if (data.power >= 0) doc["po"] = round(data.power * 100) / 100;
            if (data.energy >= 0) doc["e"] = round(data.energy * 100) / 100;
        }
        
        doc["cs"] = data.compressorState;
        doc["vs"] = data.ventiladorState;
        doc["ps"] = data.pumpState;
        doc["system_state"] = systemState ? "ON" : "OFF";
        doc["calibrated"] = isCalibrated;
        doc["water_height"] = round((tankHeight > 0 ? (tankHeight - (data.distance - SENSOR_TO_TOP)) : 0) * 100) / 100;
        
        if (rtcOnline) {
            DateTime now = rtc.now();
            doc["ts"] = now.unixtime();
        } else {
            doc["ts"] = millis() / 1000;
        }

        size_t jsonSize = serializeJson(doc, mqttBuffer, sizeof(mqttBuffer));
        if (jsonSize > 0 && jsonSize < sizeof(mqttBuffer)) {
            mqttClient.publish(MQTT_TOPIC_DATA, mqttBuffer, false);
        }
    }

    void transmitAguaRapido() {
        Serial1.printf("A:%.2f\n", data.waterVolume);
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
            return; // Salir después de detectar vacío
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
        awgLog(LOG_INFO, "✅ Punto añadido: " + String(avgDistance, 2) + 
           "cm = " + String(knownVolume, 3) + "L");
        Serial.println("📊 Punto " + String(numCalibrationPoints) + ": " + 
                  String(avgDistance, 2) + " cm → " + String(knownVolume, 3) + " L");
    
    }

    void completeCalibration() {
        if (numCalibrationPoints < 2) {
            awgLog(LOG_ERROR, "Se necesitan al menos 2 puntos de calibración");
            return;
        }

        // Validar consistencia solo al final
        if (!isCalibrationValid()) {
            awgLog(LOG_ERROR, "Calibración inconsistente - Revise los puntos");
            printCalibrationTable(); // Mostrar tabla para debug
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
            awgLog(LOG_INFO, "📏 Medición actual: " + String(currentDistance, 2) + 
               "cm = " + String(currentVolume, 2) + "L");
        }
    }

    float getSmoothedDistance(int samples) {
        float rawDistance = getAverageDistance(samples);
    
        if (rawDistance < 0) {
            return smoothedDistance; // Devolver último valor válido
        }
    
        if (firstDistanceReading) {
            smoothedDistance = rawDistance;
            firstDistanceReading = false;
        }else {
            // Filtro de suavizado exponencial
            float alpha = 0.7; // Factor de suavizado (0-1, mayor = menos suavizado)
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

    bool isInCalibrationMode() { return calibrationMode; }
    bool isTankCalibrated() { return isCalibrated; }
    float getCurrentCalibrationDistance() { return calibrationCurrentDistance; }

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
                    // overflow: resetear
                    cmdIdx1 = 0;
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
        status += "Bomba: " + String(digitalRead(PUMP_RELAY_PIN) == LOW ? "ON" : "OFF") + "\n";
        // Modo de operación
        status += "Modo: " + String(operationMode == MODE_AUTO ? "AUTO" : "MANUAL") + "\n";
        // Parámetros de control (resumen)
        status += "Control: deadband= " + String(control_deadband,2) + "C min_off= " + String(control_min_off) + "s max_on= " + String(control_max_on) + "s samp= " + String(control_sampling) + "s alpha= " + String(control_alpha,2) + "\n";
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
        status += "Temp: " + String(data.bmeTemp, 2) + " C\n";
        status += "Hum: " + String(data.bmeHum, 2) + " %\n";
        
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

void processCommand(String &cmd) {
    cmd.trim();

    // Acciones manuales deshabilitan control automático (override)
    if (cmd == "ON" || cmd == "ONC") {
        operationMode = MODE_MANUAL;
        setCompressorState(true);
    }
    else if (cmd == "OFF" || cmd == "OFFC") {
        operationMode = MODE_MANUAL;
        setCompressorState(false);
    }
    else if (cmd == "ONV") {
        // Permitir control manual del ventilador sin forzar cambio a MANUAL
        ventilatorManualOverride = true;
        setVentiladorState(true);
    }
    else if (cmd == "OFFV") {
        ventilatorManualOverride = true;
        setVentiladorState(false);
    }
    else if (cmd == "ONB") {
        operationMode = MODE_MANUAL;
        setPumpState(true);
    }
    else if (cmd == "OFFB") {
        operationMode = MODE_MANUAL;
        setPumpState(false);
    }
    // Cambio de modo explícito
    else if (cmd == "MODE AUTO" || cmd == "MODE_AUTO" || cmd == "MODE:AUTO") {
        operationMode = MODE_AUTO;
        awgLog(LOG_INFO, "Modo cambiado a AUTO");
        Serial1.println("MODE: AUTO");
        preferences.begin("awg-config", false);
        preferences.putInt("mode", (int)operationMode);
        preferences.end();
        if (mqttClient.connected()) mqttClient.publish(MQTT_TOPIC_STATUS, "MODE_AUTO");
        // Forzar una evaluación inmediata del controlador (one-shot)
        forceStartOnModeSwitch = true;
        // Quitar override manual del ventilador para que AUTO pueda controlarlo y seguir al compresor
        ventilatorManualOverride = false;
        // Ejecutar control ahora mismo para intentar arrancar si es necesario
        this->processControl();
        // Si el compresor quedó encendido tras el proceso, asegurar que el ventilador también se encienda
        if (digitalRead(COMPRESSOR_RELAY_PIN) == LOW) {
            setVentiladorState(true);
        }
    }
    else if (cmd == "MODE MANUAL" || cmd == "MODE_MANUAL" || cmd == "MODE:MANUAL") {
        operationMode = MODE_MANUAL;
        awgLog(LOG_INFO, "Modo cambiado a MANUAL");
        Serial1.println("MODE: MANUAL");
        preferences.begin("awg-config", false);
        preferences.putInt("mode", (int)operationMode);
        preferences.end();
        if (mqttClient.connected()) mqttClient.publish(MQTT_TOPIC_STATUS, "MODE_MANUAL");
        // Cancelar cualquier forceStart pendiente
        forceStartOnModeSwitch = false;

        // Enviar inmediatamente el estado real de los relés para sincronizar la pantalla
        bool compOn = (digitalRead(COMPRESSOR_RELAY_PIN) == LOW);
        bool ventOn = (digitalRead(VENTILADOR_RELAY_PIN) == LOW);
        bool pumpOn = (digitalRead(PUMP_RELAY_PIN) == LOW);

        Serial1.println(String("COMP:") + (compOn ? "ON" : "OFF"));
        Serial1.println(String("VENT:") + (ventOn ? "ON" : "OFF"));
        Serial1.println(String("PUMP:") + (pumpOn ? "ON" : "OFF"));

        // Publicar estados individuales en MQTT también (retained sería ideal, pero mantenemos comportamiento actual)
        if (mqttClient.connected()) {
            mqttClient.publish(MQTT_TOPIC_STATUS, compOn ? "COMP_ON" : "COMP_OFF");
            mqttClient.publish(MQTT_TOPIC_STATUS, ventOn ? "VENT_ON" : "VENT_OFF");
            mqttClient.publish(MQTT_TOPIC_STATUS, pumpOn ? "PUMP_ON" : "PUMP_OFF");
        }
    }
    // GET_CTRL
    else if (cmd == "GET_CTRL") {
        String s = "CTRL: deadband=" + String(control_deadband,2) +
                   " min_off=" + String(control_min_off) +
                   " max_on=" + String(control_max_on) +
                   " sampling=" + String(control_sampling) +
                   " alpha=" + String(control_alpha,3);
        Serial.println(s);
        awgLog(LOG_INFO, s);
    }
    // SET_CTRL formato: SET_CTRL d,mnOff,mxOn,samp,alpha
    else if (cmd.startsWith("SET_CTRL")) {
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
            awgLog(LOG_INFO, "SET_CTRL aplicado: deadband=" + String(control_deadband,2));
            Serial1.println("SET_CTRL: OK");
        } else {
            awgLog(LOG_WARNING, "SET_CTRL formato inválido. Uso: SET_CTRL d,mn,mx,samp,alpha");
            Serial1.println("SET_CTRL: ERR");
        }
    }
    // VENT_AUTO: quitar override manual del ventilador y volver a control automático
    else if (cmd == "VENT_AUTO" || cmd == "VENT_CLEAR") {
        ventilatorManualOverride = false;
        awgLog(LOG_INFO, "VENT_AUTO: Ventilador vuelve a control AUTO");
        Serial1.println("VENT: AUTO");
    }
    else if (cmd == "TEST") {
        testSensor();
    }
    else if (cmd.startsWith("SET_OFFSET")) {
        String offsetStr = cmd.substring(10);
        offsetStr.trim();
        sensorOffset = offsetStr.toFloat();
        preferences.begin("awg-config", false);
        preferences.putFloat("offset", sensorOffset);
        preferences.end();
        awgLog(LOG_INFO, "Offset ajustado a: " + String(sensorOffset, 2) + " cm");
    }
    else if (cmd.startsWith("SET_LOG_LEVEL")) {
        String levelStr = cmd.substring(13);
        levelStr.trim();
        int newLevel = levelStr.toInt();
            if (newLevel >= LOG_ERROR && newLevel <= LOG_DEBUG) {
                logLevel = newLevel;
                preferences.begin("awg-config", false);
                preferences.putInt("logLevel", logLevel);
                preferences.end();
                awgLog(LOG_INFO, "Nivel de log ajustado a: " + String(logLevel));
            }else {
                awgLog(LOG_WARNING, "Nivel de log inválido. Use: 0=ERROR, 1=WARNING, 2=INFO, 3=DEBUG");
             }
    }
    else if (cmd == "CALIBRATE") {
        startCalibration();
    }
    else if (cmd == "STATUS") {
        Serial.println(getSystemStatus());
    }
    else if (cmd == "CALIB_EMPTY_FORCE") {
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
    }
    else if (cmd == "CALIB_ADD") {
        awgLog(LOG_INFO, "Uso: CALIB_ADD <volumen_en_litros>");
    }
    else if (cmd.startsWith("CALIB_ADD")) {
        String volStr = cmd.substring(9);
        volStr.trim();
        float volume = volStr.toFloat();
        addCalibrationPoint(volume);
    }
    else if (cmd == "CALIB_UPLOAD") {
        awgLog(LOG_INFO, "Uso: CALIB_UPLOAD d1:v1,d2:v2,...");
    }
    else if (cmd.startsWith("CALIB_UPLOAD")) {
        // Formato esperado: CALIB_UPLOAD d1:v1,d2:v2,...
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
                dStr.trim(); vStr.trim();
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
    }
    else if (cmd == "CALIB_COMPLETE") {
        completeCalibration();
    }
    else if (cmd == "CALIB_LIST") {
        // Mostrar tabla actual de calibración
        printCalibrationTable();
    }
    else if (cmd.startsWith("CALIB_SET")) {
        // Formato esperado: CALIB_SET <idx> <distance_cm> <volume_L>
        char buf[128];
        cmd.toCharArray(buf, sizeof(buf));
        int idx = -1;
        float d = 0.0f;
        float v = 0.0f;
        int parsed = sscanf(buf, "CALIB_SET %d %f %f", &idx, &d, &v);
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
    }
    else if (cmd.startsWith("CALIB_REMOVE")) {
        // Formato: CALIB_REMOVE <idx>
        char buf[64];
        cmd.toCharArray(buf, sizeof(buf));
        int idx = -1;
        int parsed = sscanf(buf, "CALIB_REMOVE %d", &idx);
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
    }
    else if (cmd == "CALIB_CLEAR") {
        resetCalibration();
        numCalibrationPoints = 0;
        isCalibrated = false;
        saveCalibration();
        awgLog(LOG_INFO, "CALIB_CLEAR: tabla de calibración vaciada");
    }
    else if (cmd == "RESET") {
        ESP.restart();
    }
    else if (cmd == "HELP") {
        printHelp();
    }
    else if (cmd.length() > 0) {
        awgLog(LOG_WARNING, "Comando no reconocido: " + cmd);
    }
}

    void printHelp() {
        String help = "=== COMANDOS DISPONIBLES ===\n";
        help += "ON/OFF: Activar/desactivar compresor (forzar modo MANUAL)\n";
        help += "ONV/OFFV: Encender/Apagar ventilador (forzar modo MANUAL)\n";
        help += "ONB/OFFB: Encender/Apagar bomba (forzar modo MANUAL)\n";
        help += "MODE AUTO / MODE MANUAL: Cambiar modo de operación\n";
        help += "GET_CTRL: Mostrar parámetros de control actuales\n";
        help += "SET_CTRL d,mnOff,mxOn,samp,alpha : Ajustar parámetros de control\n";
        help += "STATUS: Estado del sistema\n";
        help += "TEST: Probar sensor ultrasónico\n";
        help += "SET_OFFSET X.X: Ajustar offset del sensor\n";
        help += "SET_LOG_LEVEL X: Nivel de logs (0=ERROR,1=WARNING,2=INFO,3=DEBUG)\n";
        help += "CALIBRATE: Iniciar calibración automática (tanque vacío primero)\n";
        help += "CALIB_ADD X.X: Añadir punto de calibración usando lectura actual (X.X = litros)\n";
        help += "CALIB_COMPLETE: Finalizar calibración y guardar\n";
        help += "CALIB_LIST: Mostrar tabla actual de puntos de calibración\n";
        help += "CALIB_SET <idx> <dist_cm> <vol_L>: Modificar/crear punto en índice <idx>\n";
        help += "CALIB_REMOVE <idx>: Eliminar punto de calibración en índice <idx>\n";
        help += "CALIB_CLEAR: Borrar toda la tabla de calibración\n";
        help += "CALIB_UPLOAD d1:v1,d2:v2,... : Subir tabla desde CSV\n";
        help += "RESET: Reiniciar sistema\n";
        help += "HELP: Mostrar esta ayuda\n";
        Serial.println(help);
    }

    void testSensor() {
        awgLog(LOG_INFO, "=== PRUEBA SENSOR ULTRASÓNICO ===");
    
        float measurements[5];
        float sum = 0;
        float minVal = 999;
        float maxVal = 0;
        int validMeasurements = 0;
    
        for (int i = 0; i < 5; i++) {
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
            Serial.println("Mediciones válidas: " + String(validMeasurements) + "/5");
            Serial.println("Mínimo: " + String(minVal, 2) + " cm");
            Serial.println("Máximo: " + String(maxVal, 2) + " cm");
            Serial.println("Promedio: " + String(average, 2) + " cm");
            Serial.println("Variación: " + String(variation, 2) + " cm");
        
            if (variation > 2.0) { // Alerta si variación > 2cm
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
        float Pws = A_MAGNUS * exp((L / Rv) * (1.0/ZERO_CELSIUS - 1.0/(temp + ZERO_CELSIUS)));
        float Pw = (hum / 100.0) * Pws;
        float mixRatio = 0.622 * (Pw / (presPa - Pw));
        return (mixRatio * presPa * 1000.0) / (Rv * (temp + ZERO_CELSIUS));
    }
};
 
// Definición de processControl fuera de la clase
void AWGSensorManager::processControl() {
    // Solo operar en modo automático
    if (operationMode != MODE_AUTO) return;
    // Requiere sensor disponible
    if (!sht1Online && !bmeOnline) return;
 
    unsigned long now = millis();
    if (now - lastControlSample < (unsigned long)control_sampling * 1000UL) return;
    lastControlSample = now;
 
    // Leer temperatura del evaporador (usar SHT si está disponible, sino BME)
    float rawTemp = sht1Online ? data.sht1Temp : data.bmeTemp;
    if (rawTemp == 0.0f) return; // lectura inválida
 
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
            setCompressorState(false);
            compressorOffStart = nowMs;
            compressorOnStart = 0;
        } else if (evapSmoothed <= offThreshold) {
            // Apagar por histeresis cuando temperatura cae suficientemente debajo del punto de rocío
            setCompressorState(false);
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
                setCompressorState(true);
                compressorOnStart = nowMs;
                compressorOffStart = 0;
                // consumir el one-shot
                forceStartOnModeSwitch = false;
            }
        } else {
            // log de espera para diagnóstico (nivel DEBUG)
            awgLog(LOG_DEBUG, "Esperando min_off para poder arrancar compresor");
        }
    }
 
    // El ventilador sigue al compresor en modo automático salvo override manual
    bool newCompressorOn = (digitalRead(COMPRESSOR_RELAY_PIN) == LOW);
    if (!ventilatorManualOverride) {
        setVentiladorState(newCompressorOn);
    } else {
        awgLog(LOG_DEBUG, "Ventilador en override manual; AUTO no lo modificará");
    }
 
    // Publicar estado breve por Serial1 para la pantalla y por MQTT si está conectado
    char buf[64];
    snprintf(buf, sizeof(buf), "CTRL: evap=%.2f dew=%.2f mode=AUTO comp=%s\n",
             evapSmoothed, dew, newCompressorOn ? "ON" : "OFF");
    Serial1.print(buf);
    if (mqttClient.connected()) {
        mqttClient.publish(MQTT_TOPIC_STATUS, newCompressorOn ? "AUTO_COMP_ON" : "AUTO_COMP_OFF");
    }
}

AWGSensorManager sensorManager;

 // Variables para control de tiempo
 unsigned long lastRead = 0;
 unsigned long lastTransmit = 0;
 unsigned long lastAguaTransmit = 0;
 unsigned long lastMQTTTransmit = 0;
 unsigned long lastHeartbeat = 0;
 unsigned long lastWiFiCheck = 0;
 // Control de reintentos MQTT (backoff externo)
 unsigned long lastMqttAttempt = 0;
 unsigned long mqttReconnectBackoff = MQTT_RECONNECT_DELAY;

void awgLog(int level, const String &message) {
  if (level <= logLevel) {
    const char* levelStr = "LOG";
    switch(level) {
      case LOG_ERROR: levelStr = "ERROR"; break;
      case LOG_WARNING: levelStr = "WARNING"; break;
      case LOG_INFO: levelStr = "INFO"; break;
      case LOG_DEBUG: levelStr = "DEBUG"; break;
    }

    char timestamp[32];
    if (rtcAvailable) {
      DateTime now = rtc.now();
      snprintf(timestamp, sizeof(timestamp), "%04u-%02u-%02u %02u:%02u:%02u",
               now.year(), now.month(), now.day(), now.hour(), now.minute(), now.second());
    } else {
      snprintf(timestamp, sizeof(timestamp), "%lu", millis() / 1000);
    }

    // Construir mensaje seguro en buffer fijo
    char msgBuf[LOG_MSG_LEN];
    snprintf(msgBuf, sizeof(msgBuf), "[%s] [%s] %s", timestamp, levelStr, message.c_str());

    // Imprimir por Serial
    Serial.println(msgBuf);

    // Guardar en buffer circular (char arrays)
    strncpy(logBuffer[logBufferIndex], msgBuf, LOG_MSG_LEN - 1);
    logBuffer[logBufferIndex][LOG_MSG_LEN - 1] = '\0';
    logBufferIndex = (logBufferIndex + 1) % LOG_BUFFER_SIZE;

    if (mqttClient.connected() && level <= LOG_WARNING) {
      // Publicar versión truncada para evitar saturación
      mqttClient.publish(MQTT_TOPIC_LOGS, msgBuf);
    }
  }
}

void saveConfigCallback() {
  shouldSaveConfig = true;
}

void onMqttMessage(char* topic, byte* payload, unsigned int length) {
  String message;
  for (unsigned int i = 0; i < length; i++) {
    message += (char)payload[i];
  }

  if (String(topic) == MQTT_TOPIC_CONTROL) {
    if (message == "ON") {
      setSystemState(true);
    } else if (message == "OFF") {
      setSystemState(false);
    } else if (message == "GET_DATA") {
      sensorManager.transmitMQTTData();
    } else if (message == "CALIBRATE") {
      sensorManager.startCalibration();
    }
  }
}

void setSystemState(bool newState) {
    // para compatibilidad: setSystemState controla el compresor (botón principal)
    if (systemState != newState) {
        systemState = newState;
        setCompressorState(newState);
        lastStateChange = millis();
        
        awgLog(LOG_INFO, "Sistema (Compresor) " + String(newState ? "ON" : "OFF"));
        
        if (mqttClient.connected()) {
            mqttClient.publish(MQTT_TOPIC_STATUS, ("SYSTEM_COMP_" + String(newState ? "ON" : "OFF")).c_str());
        }
    }
}

// Control granular de relés
void setCompressorState(bool newState) {
    digitalWrite(COMPRESSOR_RELAY_PIN, newState ? LOW : HIGH);
    awgLog(LOG_INFO, "Compresor " + String(newState ? "ON" : "OFF"));
    // Notificar a pantalla vía UART1 para sincronizar UI local
    Serial1.println(String("COMP:") + (newState ? "ON" : "OFF"));
    if (mqttClient.connected()) {
        mqttClient.publish(MQTT_TOPIC_STATUS, ("COMP_" + String(newState ? "ON" : "OFF")).c_str());
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

void setPumpState(bool newState) {
    digitalWrite(PUMP_RELAY_PIN, newState ? LOW : HIGH);
    awgLog(LOG_INFO, "Bomba " + String(newState ? "ON" : "OFF"));
    // Notificar a pantalla vía UART1
    Serial1.println(String("PUMP:") + (newState ? "ON" : "OFF"));
    if (mqttClient.connected()) {
        mqttClient.publish(MQTT_TOPIC_STATUS, ("PUMP_" + String(newState ? "ON" : "OFF")).c_str());
    }
}

String getSystemStateJSON() {
    StaticJsonDocument<300> doc;
    doc["system_state"] = systemState ? "ON" : "OFF";
    doc["compressor"] = digitalRead(COMPRESSOR_RELAY_PIN) == LOW ? 1 : 0;
    doc["ventilador"] = digitalRead(VENTILADOR_RELAY_PIN) == LOW ? 1 : 0;
    doc["pump"] = digitalRead(PUMP_RELAY_PIN) == LOW ? 1 : 0;
    doc["uptime"] = millis() / 1000;
    doc["calibrated"] = sensorManager.isTankCalibrated();
    // Añadir modo y parámetros de control
    doc["mode"] = operationMode == MODE_AUTO ? "AUTO" : "MANUAL";
    JsonObject ctrl = doc.createNestedObject("control");
    ctrl["deadband"] = control_deadband;
    ctrl["min_off"] = control_min_off;
    ctrl["max_on"] = control_max_on;
    ctrl["sampling"] = control_sampling;
    ctrl["alpha"] = control_alpha;
    // Indicar si el ventilador tiene override manual
    ctrl["vent_override"] = ventilatorManualOverride;
    
    String output;
    serializeJson(doc, output);
    return output;
}

void setupWiFi() {
  if (digitalRead(CONFIG_BUTTON_PIN) == LOW) {
    awgLog(LOG_INFO, "Iniciando portal de configuración...");
    wifiManager.setConfigPortalTimeout(180);
    if (!wifiManager.startConfigPortal("AWG_Config_AP")) {
      delay(3000);
      ESP.restart();
    }
  } else {
    wifiManager.setConnectTimeout(30);
    if (!wifiManager.autoConnect("AWG_Config_AP")) {
      delay(3000);
      ESP.restart();
    }
  }
  
  if (WiFi.status() == WL_CONNECTED) {
    awgLog(LOG_INFO, "Conectado a WiFi: " + WiFi.SSID());
    awgLog(LOG_INFO, "IP: " + WiFi.localIP().toString());
  }
}

void setupMQTT() {
  mqttClient.setServer(MQTT_BROKER, MQTT_PORT);
  mqttClient.setCallback(onMqttMessage);
  connectMQTT();
}

void connectMQTT() {
  // Client ID estable y único basado en MAC completa (menos riesgo de colisiones)
  uint64_t mac = ESP.getEfuseMac();
  String macStr = String((uint32_t)(mac >> 32), HEX) + String((uint32_t)mac, HEX);
  macStr.toUpperCase();
  String clientId = String(MQTT_CLIENT_ID) + "_" + macStr;

  // Last Will (mensaje que el broker publicará si el cliente se desconecta inesperadamente)
  const char* willTopic = MQTT_TOPIC_STATUS;
  const char* willMessage = "ESP32_AWG_OFFLINE";
  const uint8_t willQos = 1;
  const bool willRetain = true;

  int attempts = 0;
  unsigned long backoff = MQTT_RECONNECT_DELAY;
  const unsigned long maxBackoff = 60000UL; // 60s máximo
  const int maxAttempts = 8;

  while (!mqttClient.connected() && attempts < maxAttempts) {
    awgLog(LOG_INFO, "Intentando conectar MQTT (intento " + String(attempts + 1) + ")");
    bool connected = false;
    if (String(MQTT_USER).length() > 0) {
      connected = mqttClient.connect(clientId.c_str(), MQTT_USER, MQTT_PASS, willTopic, willQos, willRetain, willMessage);
    } else {
      // Usar overload sin usuario/clave si no están definidos
      connected = mqttClient.connect(clientId.c_str(), willTopic, willQos, willRetain, willMessage);
    }

    if (connected) {
      // Suscribirse al tópico de control
      mqttClient.subscribe(MQTT_TOPIC_CONTROL);
      // Publicar estado online (retained)
      mqttClient.publish(MQTT_TOPIC_STATUS, "ESP32_AWG_ONLINE", true);
      awgLog(LOG_INFO, "Conectado a MQTT");
      break;
    } else {
      awgLog(LOG_WARNING, "Fallo conexión MQTT, state=" + String(mqttClient.state()));
      attempts++;
      delay(backoff);
      backoff = min(backoff * 2, maxBackoff);
    }
  }

  if (!mqttClient.connected()) {
    awgLog(LOG_ERROR, "No se pudo conectar a MQTT tras varios intentos");
  }
}

void setup() {
  Serial.begin(115200);
  delay(1000);
  
  awgLog(LOG_INFO, "Iniciando sistema AWG...");
  
  pinMode(CONFIG_BUTTON_PIN, INPUT_PULLUP);
  
  sensorManager.begin();
  setupWiFi();
  setupMQTT();
  
  awgLog(LOG_INFO, "Sistema AWG iniciado");
}

void loop() {
    unsigned long now = millis();

    if (digitalRead(CONFIG_BUTTON_PIN) == LOW) {
        if (now - configPortalTimeout > CONFIG_BUTTON_TIMEOUT) {
            configPortalRequested = true;
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
        // Ejecutar control automático NO-BLOQUEANTE inmediatamente después de nuevas lecturas
        sensorManager.processControl();
    }

    if (now - lastTransmit >= UART_TRANSMIT_INTERVAL) {
        sensorManager.transmitData();
        lastTransmit = now;
    }

    if (now - lastAguaTransmit >= AGUA_TRANSMIT_INTERVAL) {
        sensorManager.transmitAguaRapido();
        lastAguaTransmit = now;
    }

    if (WiFi.status() == WL_CONNECTED) {
        if (!mqttClient.connected()) {
            // Evitar intentar reconectar continuamente: respetar backoff externo
            if (millis() - lastMqttAttempt >= mqttReconnectBackoff) {
                lastMqttAttempt = millis();
                // Incremental backoff exponencial con tope
                mqttReconnectBackoff = min(mqttReconnectBackoff * 2UL, 60000UL);
                connectMQTT();
            }
        } else {
            // Reset backoff cuando está conectado
            mqttReconnectBackoff = MQTT_RECONNECT_DELAY;
            mqttClient.loop();
            
            if (now - lastMQTTTransmit >= MQTT_TRANSMIT_INTERVAL) {
                sensorManager.transmitMQTTData();
                lastMQTTTransmit = now;
            }
            
            if (now - lastHeartbeat >= HEARTBEAT_INTERVAL) {
                mqttClient.publish(MQTT_TOPIC_HEARTBEAT, "OK", false);
                lastHeartbeat = now;
            }
        }
    } else if (now - lastWiFiCheck >= WIFI_CHECK_INTERVAL) {
        WiFi.reconnect();
        lastWiFiCheck = now;
    }

    sensorManager.handleCommands();
    sensorManager.handleSerialCommands();
    
    delay(10);
}
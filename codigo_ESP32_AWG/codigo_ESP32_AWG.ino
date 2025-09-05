#include <Wire.h>
#include <Adafruit_BME280.h>
#include <Adafruit_SHT31.h>
#include <PZEM004Tv30.h>
#include <math.h>
#include <WiFi.h>
#include <PubSubClient.h>
#include <RTClib.h>
#include <ArduinoJson.h>

// --- Configuración de pines ---
#define LED_PIN 4
#define SDA_PIN 21
#define SCL_PIN 22
#define RX1_PIN 14    // UART1 RX para pantalla
#define TX1_PIN 15    // UART1 TX para pantalla
#define RX2_PIN 19    // UART2 RX para PZEM
#define TX2_PIN 18    // UART2 TX para PZEM
#define TRIG_PIN 12
#define ECHO_PIN 13

// Direcciones I2C
#define SHT31_ADDR_1 0x44
#define SHT31_ADDR_2 0x45
#define BME280_ADDR 0x76

// Dimensiones del tanque
#define TANK_HEIGHT 100.0
#define TANK_RADIUS 25.0

// Constantes para cálculos
const float Rv = 461.5;
const float L = 2.5e6;
const float ZERO_CELSIUS = 273.15;
const float a_magnus = 611.2;

// --- Configuración WiFi y MQTT (Broker Público Mosquitto) ---
const char* ssid = "Tus nalgas_plus";
const char* password = "Mc2321332";
const char* mqtt_server = "test.mosquitto.org"; // Broker público Mosquitto (debe coincidir con Flutter)
const int mqtt_port = 1883;
const char* mqtt_user = "";  // Usuario MQTT (vacío para broker público)
const char* mqtt_pass = "";  // Contraseña MQTT (vacía para broker público)

// === CONFIGURACIÓN OPTIMIZADA PARA MÁXIMA ROBUSTEZ ===
// ✅ Reconexión automática inteligente con backoff exponencial
// ✅ Heartbeat optimizado cada 45 segundos
// ✅ QoS 1 para suscripciones críticas
// ✅ Buffer aumentado a 1024 bytes
// ✅ Keep alive agresivo de 20 segundos
// ✅ JSON compacto para menor ancho de banda
// ✅ Intervalos optimizados para balance velocidad/eficiencia

// Topics MQTT únicos para evitar interferencias (deben coincidir con la app Flutter)
const char* topic_data = "dropster/data";        // Datos del ESP32
const char* topic_status = "dropster/status";    // Estado del ESP32
const char* topic_control = "dropster/control";  // Comandos desde app
const char* topic_heartbeat = "dropster/heartbeat"; // Heartbeat del ESP32

// Instancias globales
WiFiClient espClient;
PubSubClient mqttClient(espClient);
RTC_DS3231 rtc;

// --- Clase optimizada para gestión de sensores ---
class AWGSensorManager {
private:
    Adafruit_BME280 bme;
    Adafruit_SHT31 sht31_1;
    Adafruit_SHT31 sht31_2;
    PZEM004Tv30 pzem;

    struct SensorData {
        float bmeTemp = 0, bmeHum = 0, bmePres = 0;
        float sht1Temp = 0, sht1Hum = 0;
        float sht2Temp = 0, sht2Hum = 0;
        float distance = 0;
        float voltage = 0, current = 0, power = 0, energy = 0;
        float dewPoint = 0, absHumidity = 0, waterVolume = 0;
        String timestamp = "";
    } data;

    char txBuffer[300];
    char mqttBuffer[500];

    // Para filtrado de distancia
    float lastDistance = TANK_HEIGHT;

public:
    AWGSensorManager() :
        sht31_1(&Wire),
        sht31_2(&Wire),
        pzem(Serial2, RX2_PIN, TX2_PIN) {}

    bool begin() {
        Wire.begin(SDA_PIN, SCL_PIN);
        Serial.begin(115200);
        Serial1.begin(115200, SERIAL_8N1, RX1_PIN, TX1_PIN);
        Serial2.begin(9600, SERIAL_8N1, RX2_PIN, TX2_PIN);

        // Configurar LED de control
        pinMode(LED_PIN, OUTPUT);
        digitalWrite(LED_PIN, LOW);

        pinMode(TRIG_PIN, OUTPUT);
        pinMode(ECHO_PIN, INPUT);

        bool allSensorsOK = true;

        // Inicializar RTC DS3231
        if (!rtc.begin()) {
            Serial.println("Error: RTC DS3231 no encontrado");
            allSensorsOK = false;
        } else {
            Serial.println("RTC DS3231 OK");
            if (rtc.lostPower()) {
                Serial.println("RTC perdió energía, configurando fecha/hora...");
                rtc.adjust(DateTime(F(__DATE__), F(__TIME__)));
            }
        }

        if (!bme.begin(BME280_ADDR)) {
            Serial.println("Error: BME280");
            allSensorsOK = false;
        }
        if (!sht31_1.begin(SHT31_ADDR_1)) {
            Serial.println("Error: SHT31 #1");
            allSensorsOK = false;
        }
        if (!sht31_2.begin(SHT31_ADDR_2)) {
            Serial.println("Error: SHT31 #2");
            allSensorsOK = false;
        }
        if (allSensorsOK) {
            Serial.println("Sensores OK");
        }
        return allSensorsOK;
    }

    void readSensors() {
        // Obtener timestamp del RTC
        DateTime now = rtc.now();
        data.timestamp = String(now.year()) + "-" +
                        String(now.month()) + "-" +
                        String(now.day()) + " " +
                        String(now.hour()) + ":" +
                        String(now.minute()) + ":" +
                        String(now.second());

        // BME280
        data.bmeTemp = validateTemp(bme.readTemperature());
        data.bmeHum = validateHumidity(bme.readHumidity());
        data.bmePres = bme.readPressure() / 100.0;

        // SHT31
        data.sht1Temp = validateTemp(sht31_1.readTemperature());
        data.sht1Hum = validateHumidity(sht31_1.readHumidity());
        data.sht2Temp = validateTemp(sht31_2.readTemperature());
        data.sht2Hum = validateHumidity(sht31_2.readHumidity());

        // HC-SR04 - Lectura estable y rápida
        data.distance = getStableFastDistance();

        // PZEM-004T (con NAN check)
        data.voltage = pzem.voltage();
        if (isnan(data.voltage)) data.voltage = 0.0;
        data.current = pzem.current();
        if (isnan(data.current)) data.current = 0.0;
        data.power = pzem.power();
        if (isnan(data.power)) data.power = 0.0;
        data.energy = pzem.energy();
        if (isnan(data.energy)) data.energy = 0.0;

        // Cálculos
        data.dewPoint = calculateDewPoint(data.sht1Temp, data.sht1Hum);
        data.absHumidity = calculateAbsoluteHumidity(data.bmeTemp, data.bmeHum, data.bmePres);
        data.waterVolume = calculateWaterVolume(data.distance);
    }

    // Transmisión por UART (para pantalla)
    void transmitData() {
        int len = snprintf(txBuffer, sizeof(txBuffer),
            "%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f\n",
            data.bmeTemp,         // Temp Amb
            data.bmePres,         // Presion
            data.bmeHum,          // HR Amb
            data.absHumidity,     // HA Amb
            data.dewPoint,        // Pto Rocio
            data.waterVolume,     // Agua Almac
            data.sht1Temp,        // Temp Evap
            data.sht1Hum,         // Hum Evap
            data.sht2Temp,        // Temp Cond
            data.sht2Hum,         // Hum Cond
            data.voltage,         // Voltaje
            data.current,         // Corriente
            data.power,           // Potencia
            data.energy           // Energia
        );
        if (len > 0 && len < (int)sizeof(txBuffer)) {
            Serial1.write(txBuffer, len);
        }
    }

    // Transmisión por MQTT optimizada (formato JSON compacto)
    void transmitMQTTData() {
        if (!mqttClient.connected()) {
            Serial.println("❌ MQTT desconectado");
            return;
        }

        // Crear JSON compacto con TODOS los datos del sistema AWG
        StaticJsonDocument<600> doc; // Aumentado para más datos

        // === DATOS PRINCIPALES ===
        if (data.bmeTemp > -50) doc["t"] = round(data.bmeTemp * 10) / 10; // Temp ambiente
        if (data.bmeHum >= 0) doc["h"] = round(data.bmeHum * 10) / 10;   // Humedad ambiente
        if (data.bmePres > 0) doc["p"] = round(data.bmePres);            // Presión atm
        if (data.waterVolume >= 0) doc["w"] = round(data.waterVolume * 100) / 100; // Agua almacenada

        // === SENSORES ADICIONALES ===
        if (data.sht1Temp > -50) doc["te"] = round(data.sht1Temp * 10) / 10; // Temp evaporador
        if (data.sht1Hum >= 0) doc["he"] = round(data.sht1Hum * 10) / 10;    // Humedad evaporador
        if (data.sht2Temp > -50) doc["tc"] = round(data.sht2Temp * 10) / 10; // Temp condensador
        if (data.sht2Hum >= 0) doc["hc"] = round(data.sht2Hum * 10) / 10;    // Humedad condensador

        // === CÁLCULOS DERIVADOS ===
        if (data.dewPoint > -50) doc["dp"] = round(data.dewPoint * 10) / 10; // Punto de rocío
        if (data.absHumidity > 0) doc["ha"] = round(data.absHumidity * 1000) / 1000; // Humedad absoluta

        // === DATOS ELÉCTRICOS ===
        if (data.voltage >= 0) doc["v"] = round(data.voltage * 10) / 10; // Voltaje
        if (data.current >= 0) doc["c"] = round(data.current * 100) / 100; // Corriente
        if (data.power >= 0) doc["po"] = round(data.power);              // Potencia
        if (data.energy >= 0) doc["e"] = round(data.energy * 10) / 10;   // Energía

        // === TIMESTAMP ===
        DateTime now = rtc.now();
        doc["ts"] = now.unixtime(); // Timestamp Unix

        // Serializar JSON
        size_t jsonSize = serializeJson(doc, mqttBuffer, sizeof(mqttBuffer));

        if (jsonSize == 0 || jsonSize >= sizeof(mqttBuffer)) {
            Serial.println("❌ Error JSON");
            return;
        }

        // Enviar con QoS 1 para mayor confiabilidad
        bool success = mqttClient.publish(topic_data, mqttBuffer, false); // QoS 0 para velocidad

        if (success) {
            Serial.print("📤 MQTT: ");
            Serial.print(jsonSize);
            Serial.println(" bytes ✓");
        } else {
            Serial.println("❌ MQTT envío falló");
        }
    }

    // Envío rápido solo de agua almacenada
    void transmitAguaRapido() {
        Serial1.printf("A:%.2f\n", data.waterVolume);
    }

    void handleCommands() {
        static String cmdBuffer;
        while (Serial1.available()) {
            char c = Serial1.read();
            if (c == '\n') {
                processCommand(cmdBuffer);
                cmdBuffer = "";
            } else if (c != '\r') {
                cmdBuffer += c;
            }
        }
    }

private:
    void processCommand(String &cmd) {
        cmd.trim();
        if (cmd == "ON") {
            digitalWrite(LED_PIN, HIGH);
        } else if (cmd == "OFF") {
            digitalWrite(LED_PIN, LOW);
        }
    }

    float validateTemp(float temp) {
        return (temp > -50.0 && temp < 100.0) ? temp : 0.0;
    }
    float validateHumidity(float hum) {
        return (hum >= 0.0 && hum <= 100.0) ? hum : 0.0;
    }

    // Lectura simple de distancia
    float getDistance() {
        digitalWrite(TRIG_PIN, LOW);
        delayMicroseconds(2);
        digitalWrite(TRIG_PIN, HIGH);
        delayMicroseconds(10);
        digitalWrite(TRIG_PIN, LOW);

        unsigned long timeout = micros() + 30000;
        while (digitalRead(ECHO_PIN) == LOW && micros() < timeout);
        long start = micros();
        while (digitalRead(ECHO_PIN) == HIGH && micros() < timeout);
        long duration = micros() - start;

        float distance = duration * 0.034 / 2.0;
        return (distance > 2.0 && distance < 400.0) ? distance : TANK_HEIGHT;
    }

    // Mediana de 3 lecturas rápidas
    float getMedianDistance() {
        float a = getDistance();
        delay(5);
        float b = getDistance();
        delay(5);
        float c = getDistance();
        // Ordenar a, b, c y devolver la mediana
        if ((a <= b && b <= c) || (c <= b && b <= a)) return b;
        else if ((b <= a && a <= c) || (c <= a && a <= b)) return a;
        else return c;
    }

    // Filtro exponencial rápido sobre la mediana
    float getStableFastDistance() {
        float alpha = 0.5; // Más alto = más rápido, menos suave
        float median = getMedianDistance();
        float stable = alpha * median + (1 - alpha) * lastDistance;
        lastDistance = stable;
        return stable;
    }

    float calculateDewPoint(float temp, float hum) {
        const float a = 17.62, b = 243.12;
        float factor = log(hum / 100.0) + (a * temp) / (b + temp);
        return (b * factor) / (a - factor);
    }
    float calculateAbsoluteHumidity(float temp, float hum, float pres) {
        float presPa = pres * 100.0;
        float Pws = a_magnus * exp((L / Rv) * (1.0/ZERO_CELSIUS - 1.0/(temp + ZERO_CELSIUS)));
        float Pw = (hum / 100.0) * Pws;
        float mixRatio = 0.622 * (Pw / (presPa - Pw));
        return (mixRatio * presPa * 1000.0) / (Rv * (temp + ZERO_CELSIUS));
    }
    float calculateWaterVolume(float distance) {
        float waterHeight = constrain(TANK_HEIGHT - distance, 0.0f, TANK_HEIGHT);
        return PI * pow(TANK_RADIUS / 10.0, 2) * (waterHeight / 10.0);
    }
};

AWGSensorManager sensorManager;

// Variables para WiFi y MQTT
unsigned long lastWiFiCheck = 0;
unsigned long lastMQTTCheck = 0;
unsigned long lastMQTTTransmit = 0;
unsigned long lastHeartbeat = 0;

void setup() {
    if (!sensorManager.begin()) {
        Serial.println("Error en inicialización");
        while (1) delay(1000);
    }

    // Inicializar WiFi
    setupWiFi();

    // Configurar MQTT con parámetros optimizados para máxima robustez
    mqttClient.setServer(mqtt_server, mqtt_port);
    mqttClient.setCallback(onMqttMessage);

    // Configurar keep alive agresivo para detectar desconexiones rápidamente
    mqttClient.setKeepAlive(20); // 20 segundos (más agresivo)

    // Configurar buffer más grande para mensajes JSON grandes
    mqttClient.setBufferSize(1024); // Aumentado para mensajes más grandes

    Serial.println("🚀 Sistema iniciado - MQTT configurado");
    Serial.print("📡 Broker: ");
    Serial.println(mqtt_server);
    Serial.print("🔌 Puerto: ");
    Serial.println(mqtt_port);
    Serial.print("📋 Topics: ");
    Serial.print(topic_data);
    Serial.print(", ");
    Serial.println(topic_control);
}

void setupWiFi() {
    WiFi.begin(ssid, password);
    Serial.print("Conectando a WiFi");

    int attempts = 0;
    while (WiFi.status() != WL_CONNECTED && attempts < 20) {
        delay(500);
        Serial.print(".");
        attempts++;
    }

    if (WiFi.status() == WL_CONNECTED) {
        Serial.println();
        Serial.print("WiFi conectado! IP: ");
        Serial.println(WiFi.localIP());
    } else {
        Serial.println();
        Serial.println("Error: No se pudo conectar a WiFi");
    }
}

void connectMQTT() {
    static unsigned long lastReconnectAttempt = 0;
    static int reconnectAttempts = 0;
    const int maxReconnectAttempts = 3; // Reducido para ser más rápido
    const unsigned long baseDelay = 2000; // Delay base reducido

    // Evitar reconexiones demasiado frecuentes (solo si no hay muchos intentos fallidos)
    if (reconnectAttempts < maxReconnectAttempts &&
        millis() - lastReconnectAttempt < baseDelay) {
        return;
    }

    lastReconnectAttempt = millis();

    // Si ya está conectado, no hacer nada
    if (mqttClient.connected()) {
        reconnectAttempts = 0; // Reset contador si está conectado
        return;
    }

    Serial.print("🔌 MQTT: Intentando conectar (");
    Serial.print(reconnectAttempts + 1);
    Serial.print("/");
    Serial.print(maxReconnectAttempts);
    Serial.print(")...");

    // Generar ID único para evitar conflictos
    String clientId = "ESP32_AWG_" + String(ESP.getEfuseMac() % 10000, HEX);

    // Intentar conectar con timeout más corto
    bool connected = mqttClient.connect(clientId.c_str(), mqtt_user, mqtt_pass);

    if (connected) {
        Serial.println(" ✅ CONECTADO!");
        reconnectAttempts = 0; // Reset contador en éxito

        // Suscribirse a topics inmediatamente
        mqttClient.subscribe(topic_control, 1); // QoS 1 para mayor confiabilidad
        mqttClient.subscribe(topic_status, 1);

        // Enviar mensaje de conexión
        mqttClient.publish(topic_status, "ESP32_AWG_ONLINE", true); // Retained

        Serial.println("📡 Suscrito a topics de control");
    } else {
        Serial.print(" ❌ FALLÓ (rc=");
        Serial.print(mqttClient.state());
        Serial.println(")");

        reconnectAttempts++;

        // Delay exponencial pero limitado
        if (reconnectAttempts < maxReconnectAttempts) {
            unsigned long delayTime = baseDelay * (1 << (reconnectAttempts - 1)); // 2s, 4s, 8s
            Serial.print("⏳ Reintentando en ");
            Serial.print(delayTime / 1000);
            Serial.println("s...");
            delay(delayTime);
        } else {
            // Después de máximo intentos, esperar más tiempo
            Serial.println("⏸️ Máximo intentos alcanzado, esperando 15s...");
            reconnectAttempts = 0;
            delay(15000);
        }
    }
}

void onMqttMessage(char* topic, byte* payload, unsigned int length) {
    String message;
    for (unsigned int i = 0; i < length; i++) {
        message += (char)payload[i];
    }

    Serial.print("Mensaje recibido [");
    Serial.print(topic);
    Serial.print("]: ");
    Serial.println(message);

    if (String(topic) == topic_control) {
        if (message == "GET_STATUS") {
            mqttClient.publish(topic_status, "AWG_RUNNING");
        } else if (message == "GET_DATA") {
            sensorManager.transmitMQTTData();
        } else if (message == "ON") {
            digitalWrite(LED_PIN, HIGH);
            Serial.println("✅ LED encendido - Sistema ON");
            mqttClient.publish(topic_status, "SYSTEM_ON");
        } else if (message == "OFF") {
            digitalWrite(LED_PIN, LOW);
            Serial.println("❌ LED apagado - Sistema OFF");
            mqttClient.publish(topic_status, "SYSTEM_OFF");
        }
    }
}

void loop() {
    static unsigned long lastRead = 0;
    static unsigned long lastTransmit = 0;
    static unsigned long lastAguaTransmit = 0;

    unsigned long now = millis();

    // === CONEXIONES (Verificaciones eficientes) ===
    // WiFi cada 15 segundos (reducido para ser más responsivo)
    if (now - lastWiFiCheck >= 15000) {
        if (WiFi.status() != WL_CONNECTED) {
            Serial.println("📶 WiFi desconectado, reconectando...");
            setupWiFi();
        }
        lastWiFiCheck = now;
    }

    // MQTT cada 3 segundos (más frecuente para reconexión rápida)
    if (WiFi.status() == WL_CONNECTED && (now - lastMQTTCheck >= 3000)) {
        if (!mqttClient.connected()) {
            connectMQTT();
        }
        lastMQTTCheck = now;
    }

    // Mantener conexión MQTT activa (sin delay adicional)
    if (mqttClient.connected()) {
        mqttClient.loop();
    }

    // === SENSORES (Lectura optimizada) ===
    // Leer sensores cada 2 segundos (reducido para más frecuencia pero no excesiva)
    if (now - lastRead >= 2000) {
        sensorManager.readSensors();
        lastRead = now;
    }

    // === TRANSMISIONES (Optimizadas por prioridad) ===

    // UART cada 3 segundos (pantalla local - alta prioridad)
    if (now - lastTransmit >= 3000) {
        sensorManager.transmitData();
        lastTransmit = now;
    }

    // MQTT cada 8 segundos (datos a app - balanceado)
    if (mqttClient.connected() && (now - lastMQTTTransmit >= 8000)) {
        sensorManager.transmitMQTTData();
        lastMQTTTransmit = now;
    }

    // Agua rápida cada 1 segundo (pantalla local - muy frecuente)
    if (now - lastAguaTransmit >= 1000) {
        sensorManager.transmitAguaRapido();
        lastAguaTransmit = now;
    }

    // Heartbeat MQTT cada 45 segundos (conexión viva - menos frecuente)
    if (mqttClient.connected() && (now - lastHeartbeat >= 45000)) {
        mqttClient.publish(topic_heartbeat, "OK", false);
        Serial.println("💓 Heartbeat");
        lastHeartbeat = now;
    }

    // === COMANDOS (Procesamiento inmediato) ===
    sensorManager.handleCommands();

    // Delay reducido para mayor responsividad
    delay(5);
}
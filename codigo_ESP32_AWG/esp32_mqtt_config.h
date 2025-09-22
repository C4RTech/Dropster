#ifndef ESP32_MQTT_CONFIG_H
#define ESP32_MQTT_CONFIG_H

// Configuración WiFi
#define WIFI_SSID "YOUR_WIFI_SSID"
#define WIFI_PASS "YOUR_WIFI_PASSWORD"


// Configuración MQTT
#define MQTT_BROKER "test.mosquitto.org"
#define MQTT_PORT 1883
#define MQTT_USER ""
#define MQTT_PASS ""
#define MQTT_CLIENT_ID "ESP32_Dropster_AWG"
#define MQTT_KEEP_ALIVE 60

// Tópicos (deben coincidir con Flutter)
#define MQTT_TOPIC_DATA "dropster/data"
#define MQTT_TOPIC_STATUS "dropster/status"
#define MQTT_TOPIC_CONTROL "dropster/control"
#define MQTT_TOPIC_HEARTBEAT "dropster/heartbeat"
#define MQTT_TOPIC_LOGS "dropster/logs"
#define MQTT_TOPIC_CALIBRATION "dropster/calibration"

// Intervalos de operación (ms)
#define SENSOR_READ_INTERVAL 3000
#define UART_TRANSMIT_INTERVAL 3000
#define AGUA_TRANSMIT_INTERVAL 1000
#define MQTT_TRANSMIT_INTERVAL 10000
#define HEARTBEAT_INTERVAL 60000
#define WIFI_CHECK_INTERVAL 10000
#define SENSOR_CHECK_INTERVAL 30000
#define MQTT_RECONNECT_DELAY 5000
#define WIFI_RECONNECT_DELAY 5000
#define CONFIG_BUTTON_TIMEOUT 5000

// CONFIGURACIÓN DEL SISTEMA DE TANQUE
#define MAX_CALIBRATION_POINTS 10
#define SENSOR_TO_TOP 4.0

// Constantes para cálculos
#define Rv 461.5
#define L 2.5e6
#define ZERO_CELSIUS 273.15
#define A_MAGNUS 611.2

// Niveles de logging
#define LOG_ERROR 0
#define LOG_WARNING 1
#define LOG_INFO 2
#define LOG_DEBUG 3

// Pines
#define COMPRESSOR_RELAY_PIN 4
#define VENTILADOR_RELAY_PIN 0
#define PUMP_RELAY_PIN 27
#define SDA_PIN 21
#define SCL_PIN 22
#define RX1_PIN 14
#define TX1_PIN 15
#define RX2_PIN 19
#define TX2_PIN 18
#define TRIG_PIN 12
#define ECHO_PIN 13
#define CONFIG_BUTTON_PIN 5

// Direcciones I2C
#define SHT31_ADDR_1 0x44
#define BME280_ADDR 0x76

// Buffer sizes
#define TX_BUFFER_SIZE 300
#define MQTT_BUFFER_SIZE 400
#define LOG_BUFFER_SIZE 10
#define PARAM_BUFFER_SIZE 40

// Verificaciones básicas
#if !defined(WIFI_SSID) || !defined(WIFI_PASS)
  #error "WiFi SSID/PASSWORD no definidos en esp32_mqtt_config.h"
#endif

#if !defined(MQTT_BROKER)
  #error "MQTT_BROKER no definido en esp32_mqtt_config.h"
#endif

#endif  // ESP32_MQTT_CONFIG_H
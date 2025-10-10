#ifndef CONFIG_H
#define CONFIG_H

// Configuración MQTT
#define MQTT_BROKER "test.mosquitto.org"
#define MQTT_PORT 1883
#define MQTT_USER ""
#define MQTT_PASS ""
#define MQTT_CLIENT_ID "ESP32_Dropster_AWG"

// Tópicos (deben coincidir con Dropster App)
#define MQTT_TOPIC_DATA "dropster/data"
#define MQTT_TOPIC_STATUS "dropster/status"
#define MQTT_TOPIC_CONTROL "dropster/control"
#define MQTT_TOPIC_CONFIG "dropster/config"
#define MQTT_TOPIC_ALERTS "dropster/alerts"

// Intervalos de operación (ms)
#define SENSOR_READ_INTERVAL 3000
#define UART_TRANSMIT_INTERVAL 3000
#define MQTT_TRANSMIT_INTERVAL 10000
#define HEARTBEAT_INTERVAL 60000
#define WIFI_CHECK_INTERVAL 10000
#define MQTT_RECONNECT_DELAY 5000
#define WIFI_RECONNECT_DELAY 5000
#define CONFIG_BUTTON_TIMEOUT 5000

// CONFIGURACIÓN DEL SISTEMA DE TANQUE
#define MAX_CALIBRATION_POINTS 10

// Constantes para cálculos
#define Rv 461.5
#define L 2.5e6
#define ZERO_CELSIUS 273.15
#define A_MAGNUS 611.2

// Constantes del termistor NTC
#define BETA 3950.0                    // Coeficiente Beta
#define NOMINAL_RESISTANCE 10000.0     // 10kΩ a 25°C
#define NOMINAL_TEMP 298.15            // 25°C en Kelvin (25.0 + 273.15)
#define CURRENT 100e-6                 // 100 microamperios
#define ADC_RESOLUTION 4095            // 12 bits
#define VREF 3.3                       // Voltaje de referencia

// Niveles de logging
#define LOG_ERROR 0
#define LOG_WARNING 1
#define LOG_INFO 2
#define LOG_DEBUG 3

// Pines
#define COMPRESSOR_RELAY_PIN 4
#define VENTILADOR_RELAY_PIN 0
#define COMPRESSOR_FAN_RELAY_PIN 26
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
#define TERMISTOR_PIN 34

// Direcciones I2C
#define SHT31_ADDR_1 0x44
#define BME280_ADDR 0x76

// Buffer sizes
#define TX_BUFFER_SIZE 300
#define MQTT_BUFFER_SIZE 400
#define LOG_BUFFER_SIZE 10
#define PARAM_BUFFER_SIZE 40

// Configuración de comandos y concurrencia
#define COMMAND_TIMEOUT 5000               // Timeout para comandos críticos (ms)
#define COMMAND_DEBOUNCE 1000              // Debounce entre comandos (ms)

// Límites de seguridad para temperaturas
#define MAX_SAFE_TEMP 50.0f                // Temperatura máxima segura (°C)
#define MIN_SAFE_TEMP -10.0f               // Temperatura mínima segura (°C)
#define MAX_SAFE_HUMIDITY 95.0f            // Humedad máxima segura (%)
#define MIN_WATER_LEVEL 5.0f               // Nivel mínimo de agua para bombear (%)
#define MAX_COMPRESSOR_TEMP 100.0f         // Temperatura máxima segura del compresor (°C)

// Parámetros de control automático (valores por defecto)
#define CONTROL_DEADBAND_DEFAULT 3.0f      // Banda muerta (°C)
#define CONTROL_MIN_OFF_DEFAULT 60         // Tiempo mínimo apagado (s)
#define CONTROL_MAX_ON_DEFAULT 1800        // Tiempo máximo encendido (s)
#define CONTROL_SAMPLING_DEFAULT 8         // Intervalo de muestreo (s)
#define CONTROL_ALPHA_DEFAULT 0.2f         // Factor de suavizado (0-1)

// Configuración de alertas (umbrales por defecto)
#define ALERT_TANK_FULL_DEFAULT 90.0f      // Tanque lleno (%)
#define ALERT_VOLTAGE_LOW_DEFAULT 100.0f   // Voltaje bajo (V)
#define ALERT_HUMIDITY_LOW_DEFAULT 40.0f   // Humedad baja (%)
#define ALERT_VOLTAGE_ZERO_DEFAULT 0.0f    // Voltaje cero (siempre activo)

// Configuración del tanque
#define TANK_CAPACITY_DEFAULT 1000.0f      // Capacidad por defecto (L)

// Configuración de recuperación de sensores
#define SENSOR_RECOVERY_INTERVAL 30000     // Intervalo de recuperación (ms)

#define LOG_MSG_LEN 240                    // Longitud máxima de mensajes de log

// Configuración de monitoreo automático de sensores
#define SENSOR_STATUS_CHECK_INTERVAL 30000 // Intervalo de verificación de estado de sensores (ms)

// Configuración WiFi
#define WIFI_CONFIG_PORTAL_TIMEOUT 180
#define WIFI_CONNECT_TIMEOUT 30

// Configuración MQTT adicional
#define MQTT_MAX_ATTEMPTS 8
#define MQTT_MAX_BACKOFF 60000UL

// Constantes de algoritmos
#define ULTRASONIC_FILTER_K 3.5f
#define PZEM_INIT_ATTEMPTS 3
#define TEST_SENSOR_SAMPLES 5

// Verificaciones básicas
#if !defined(MQTT_BROKER)
  #error "MQTT_BROKER no definido en config.h"
#endif

#endif  // CONFIG_H
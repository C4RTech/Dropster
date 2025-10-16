#ifndef CONFIG_H
#define CONFIG_H

// Configuración MQTT
#define MQTT_BROKER "test.mosquitto.org"
#define MQTT_PORT 1883
#define MQTT_USER ""
#define MQTT_PASS ""
#define MQTT_CLIENT_ID "ESP32_Dropster_AWG"

// Tópicos organizados (deben coincidir con Dropster App)
#define MQTT_TOPIC_DATA "dropster/data"           // Datos de sensores (JSON, QoS 0)
#define MQTT_TOPIC_STATUS "dropster/status"       // Estados actuadores + modo (JSON, QoS 1, retained)
#define MQTT_TOPIC_CONTROL "dropster/control"     // Comandos app → ESP32 (control + configuración)
#define MQTT_TOPIC_ALERTS "dropster/alerts"       // Alertas específicas
#define MQTT_TOPIC_ERRORS "dropster/errors"       // Mensajes de error
#define MQTT_TOPIC_SYSTEM "dropster/system"       // Estado general del sistema

// Intervalos de operación (ms)
#define SENSOR_READ_INTERVAL 3000
#define UART_TRANSMIT_INTERVAL 3000
#define MQTT_TRANSMIT_INTERVAL 3000
#define HEARTBEAT_INTERVAL 60000
#define WIFI_CHECK_INTERVAL 10000
#define MQTT_RECONNECT_DELAY 5000
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
#define MQTT_BUFFER_SIZE 1024  // Aumentado para mensajes JSON largos
#define LOG_BUFFER_SIZE 10

// Configuración de comandos y concurrencia
#define COMMAND_TIMEOUT 5000               // Timeout para comandos críticos (ms)
#define COMMAND_DEBOUNCE 1000              // Debounce entre comandos (ms)

// Límites de seguridad
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

// Tamaños de buffers JSON
#define STATUS_JSON_SIZE 200
#define DATA_JSON_SIZE 300
#define BACKUP_JSON_SIZE 1024
#define CONFIG_JSON_SIZE 2048

// Constantes de algoritmos
#define CALIBRATION_DISTANCE_TOLERANCE 2.0f    // Tolerancia para distancia en calibración
#define CALIBRATION_RATIO_MIN 0.1f             // Ratio mínimo distancia/volumen
#define CALIBRATION_RATIO_MAX 10.0f            // Ratio máximo distancia/volumen
#define MIN_VALID_SAMPLES 3                    // Muestras mínimas para promedio
#define ULTRASONIC_MIN_DISTANCE 2.0f           // Distancia mínima válida (cm)
#define ULTRASONIC_MAX_DISTANCE 400.0f         // Distancia máxima válida (cm)
#define WATER_VOLUME_MIN 0.0f                  // Volumen mínimo de agua
#define TEMP_MIN_VALID -50.0f                  // Temperatura mínima válida (°C)
#define TEMP_MAX_VALID 200.0f                  // Temperatura máxima válida (°C)
#define ABSOLUTE_ZERO -273.15f                 // Cero absoluto para cálculos
#define COMPRESSOR_FAN_TEMP_ON_OFFSET 10.0f    // Offset para encender ventilador (°C)
#define COMPRESSOR_FAN_TEMP_OFF_OFFSET 20.0f   // Offset para apagar ventilador (°C)
#define CONTROL_SMOOTHING_ALPHA 0.7f           // Factor de suavizado en control
#define TERMISTOR_SAMPLES 20                   // Muestras para promediar termistor
#define RECOVERY_MAX_ATTEMPTS 5                // Intentos máximos de recuperación
#define RECOVERY_SUCCESS_THRESHOLD 3           // Umbral de éxito en recuperación

// Constantes de timing adicionales
#define STARTUP_DELAY 1000                     // Delay de inicio (ms)
#define LOOP_DELAY 10                          // Delay del loop principal (ms)
#define STATS_SAVE_INTERVAL 300000UL           // Intervalo para guardar estadísticas (ms, 5 min)
#define CONFIG_ASSEMBLE_TIMEOUT 10000          // Timeout para ensamblaje de config (ms)

// Constantes para arrays y contadores
#define CONFIG_FRAGMENT_COUNT 4                 // Número de fragmentos de configuración

// Otras constantes
#define WATER_PERCENT_MIN 0.0f                  // Porcentaje mínimo de agua
#define WATER_PERCENT_MAX 100.0f                // Porcentaje máximo de agua
#define VOLTAGE_ZERO_THRESHOLD 0.1f             // Umbral para voltaje cero

#endif  // CONFIG_H
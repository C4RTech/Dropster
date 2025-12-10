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

// Intervalos de operación (ms) - Optimizados para estabilidad UART
#define SENSOR_READ_INTERVAL 2000  // Reducido para lecturas más frecuentes
#define UART_TRANSMIT_INTERVAL 5000  // Intervalo para datos de sensores (estados se envían solo al cambiar)
#define MQTT_TRANSMIT_INTERVAL 5000
#define HEARTBEAT_INTERVAL 30000     // Reducido a 30s para mejor keep-alive
#define WIFI_CHECK_INTERVAL 10000
#define MQTT_RECONNECT_DELAY 3000    // Reducido para reconexión más rápida
#define CONFIG_BUTTON_TIMEOUT 5000

// CONFIGURACIÓN DEL SISTEMA DE TANQUE
#define MAX_CALIBRATION_POINTS 30

// Constantes para cálculos
#define Rv 461.5
#define L 2.5e6
#define ZERO_CELSIUS 273.15
#define A_MAGNUS 611.2

// Constantes del termistor NTC
#define BETA 3435.0                    // Coeficiente Beta
#define NOMINAL_RESISTANCE 10000.0     // 10kΩ a 25°C
#define NOMINAL_TEMP 246.5            //  (calibrado para 27°C)
#define ADC_RESOLUTION 4095            // 12 bits
#define VREF 3.3                       // Voltaje de referencia

// Niveles de logging
#define LOG_ERROR 0
#define LOG_WARNING 1
#define LOG_INFO 2
#define LOG_DEBUG 3

// Pines
#define COMPRESSOR_RELAY_PIN 33
#define VENTILADOR_RELAY_PIN 27
#define COMPRESSOR_FAN_RELAY_PIN 25
#define PUMP_RELAY_PIN 26
#define SDA_PIN 21
#define SCL_PIN 22
#define RX1_PIN 0
#define TX1_PIN 4
#define RX2_PIN 19
#define TX2_PIN 18
#define TRIG_PIN 12
#define ECHO_PIN 14
#define CONFIG_BUTTON_PIN 15
#define TERMISTOR_PIN 34

// Pines LED RGB
#define LED_R_PIN 2
#define LED_G_PIN 23
#define LED_B_PIN 32
#define BACKLIGHT_PIN 5  // GPIO del ESP32 conectado al pin BL del display (GPIO21 del display)
#define LEDC_CHANNEL_R 0
#define LEDC_CHANNEL_G 1
#define LEDC_CHANNEL_B 2
#define LEDC_FREQ 5000
#define LEDC_RES 8

// Intensidades LED RGB (0.0-1.0) - Máximo brillo para mejor visibilidad
#define LED_INTENSITY_R 1.0f
#define LED_INTENSITY_G 1.0f
#define LED_INTENSITY_B 1.0f

// Colores predefinidos con intensidades ajustadas
#define COLOR_RED_R (uint8_t)(255 * LED_INTENSITY_R)
#define COLOR_RED_G 0
#define COLOR_RED_B 0

#define COLOR_GREEN_R 0
#define COLOR_GREEN_G (uint8_t)(255 * LED_INTENSITY_G)
#define COLOR_GREEN_B 0

#define COLOR_BLUE_R 0
#define COLOR_BLUE_G 0
#define COLOR_BLUE_B (uint8_t)(255 * LED_INTENSITY_B)

#define COLOR_WHITE_R (uint8_t)(255 * LED_INTENSITY_R)
#define COLOR_WHITE_G (uint8_t)(255 * LED_INTENSITY_G)
#define COLOR_WHITE_B (uint8_t)(255 * LED_INTENSITY_B)

#define COLOR_YELLOW_R (uint8_t)(255 * LED_INTENSITY_R)
#define COLOR_YELLOW_G (uint8_t)(255 * LED_INTENSITY_G)
#define COLOR_YELLOW_B 0

#define COLOR_ORANGE_R (uint8_t)(210 * LED_INTENSITY_R)
#define COLOR_ORANGE_G (uint8_t)(50 * LED_INTENSITY_G)
#define COLOR_ORANGE_B 0

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
#define MAX_COMPRESSOR_TEMP 95.0f         // Temperatura máxima segura del compresor (°C)

// Parámetros de control automático (valores por defecto)
#define CONTROL_DEADBAND_DEFAULT 3.0f      // Banda muerta (°C)
#define CONTROL_MIN_OFF_DEFAULT 120        // Tiempo mínimo apagado (s) - ajustado a 2 minutos
#define CONTROL_MAX_ON_DEFAULT 7200        // Tiempo máximo encendido (s) - aumentado para mayor tiempo de funcionamiento continuo
#define CONTROL_SAMPLING_DEFAULT 7         // Intervalo de muestreo (s)
#define CONTROL_ALPHA_DEFAULT 0.2f         // Factor de suavizado (0-1)

// Configuración de alertas (umbrales por defecto)
#define ALERT_TANK_FULL_DEFAULT 90.0f      // Tanque lleno (%)
#define ALERT_VOLTAGE_LOW_DEFAULT 100.0f   // Voltaje bajo (V)
#define ALERT_HUMIDITY_LOW_DEFAULT 40.0f   // Humedad baja (%)
#define ALERT_VOLTAGE_ZERO_DEFAULT 0.0f    // Voltaje cero (siempre activo)

// Configuración del tanque
#define TANK_CAPACITY_DEFAULT 20.0f      // Capacidad por defecto (L)

// Configuración de protección de bomba
#define PUMP_MIN_LEVEL_DEFAULT 2.0f       // Nivel mínimo para bomba (L)

#define LOG_MSG_LEN 240                    // Longitud máxima de mensajes de log

// Configuración de monitoreo automático de sensores
#define SENSOR_STATUS_CHECK_INTERVAL 30000 // Intervalo de verificación de estado de sensores (ms)

// Configuración WiFi
#define WIFI_CONFIG_PORTAL_TIMEOUT 120

// Configuración MQTT adicional - Mejorada para estabilidad
#define MQTT_MAX_BACKOFF 300000UL   // Máximo 5 minutos de backoff

// Constantes de algoritmos
#define PZEM_INIT_ATTEMPTS 3
#define TEST_SENSOR_SAMPLES 5

// Verificaciones básicas
#if !defined(MQTT_BROKER)
  #error "MQTT_BROKER no definido en config.h"
#endif

// Tamaños de buffers JSON
#define STATUS_JSON_SIZE 200
#define DATA_JSON_SIZE 300
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
#define COMPRESSOR_FAN_TEMP_ON_OFFSET_DEFAULT 10.0f    // Offset por defecto para encender ventilador (°C)
#define COMPRESSOR_FAN_TEMP_OFF_OFFSET_DEFAULT 20.0f   // Offset por defecto para apagar ventilador (°C)

// Offsets para control del ventilador del evaporador
#define EVAP_FAN_TEMP_ON_OFFSET_DEFAULT 1.0f    // Offset para encender ventilador evaporador (°C) - reducido para mayor eficiencia
#define EVAP_FAN_TEMP_OFF_OFFSET_DEFAULT 0.5f   // Offset para apagar ventilador evaporador (°C) - reducido para mantener temperatura más estable
#define EVAP_FAN_MIN_OFF_DEFAULT 30             // Tiempo mínimo apagado (s) - reducido para mayor eficiencia
#define EVAP_FAN_MAX_ON_DEFAULT 1800            // Tiempo máximo encendido (s)

// Offset de compensación para temperatura del evaporador (SHT31)
#define EVAPORATOR_TEMP_OFFSET 15.0f            // Offset aplicado cuando compresor opera > 1 min (°C)
#define EVAPORATOR_OFFSET_DELAY 60000UL         // Tiempo mínimo de operación del compresor para aplicar offset (ms, 1 min)

#define CONTROL_SMOOTHING_ALPHA 0.7f           // Factor de suavizado en control
#define TERMISTOR_SAMPLES 10                   // Muestras para promediar termistor (reducido para mayor velocidad)

// Constantes de timing adicionales
#define STARTUP_DELAY 1000                     // Delay de inicio (ms)
#define STATS_SAVE_INTERVAL 300000UL           // Intervalo para guardar estadísticas (ms, 5 min)
#define CONFIG_ASSEMBLE_TIMEOUT 10000          // Timeout para ensamblaje de config (ms)

// Protección del compresor
#define COMPRESSOR_PROTECTION_TIME 10000UL     // Tiempo de monitoreo inicial (ms, 10s)
#define COMPRESSOR_MIN_CURRENT 1.7f            // Corriente mínima para considerar arranque exitoso (A)
#define COMPRESSOR_RETRY_DELAY 60000UL         // Retraso antes de reintentar arranque (ms, 1 min)

#define CONFIG_PORTAL_MAX_TIMEOUT 120000UL     // Máximo tiempo de portal de configuración (ms, 2 minutos)

// Constantes para arrays y contadores
#define CONFIG_FRAGMENT_COUNT 4                 // Número de fragmentos de configuración

// Otras constantes
#define WATER_PERCENT_MIN 0.0f                  // Porcentaje mínimo de agua
#define WATER_PERCENT_MAX 100.0f                // Porcentaje máximo de agua
#define VOLTAGE_ZERO_THRESHOLD 0.1f             // Umbral para voltaje cero

#endif  // CONFIG_H
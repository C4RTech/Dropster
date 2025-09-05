// Configuración MQTT para ESP32 Dropster
// Este archivo debe ser incluido en el código del ESP32 AWG

#ifndef ESP32_MQTT_CONFIG_H
#define ESP32_MQTT_CONFIG_H

// Configuración del broker MQTT (debe coincidir con la app Flutter)
#define MQTT_BROKER "broker.emqx.io"  // Broker principal
#define MQTT_PORT 1883
#define MQTT_TOPIC_DATA "dropster/data"  // Tópico para enviar datos
#define MQTT_TOPIC_CONTROL "awg/control"  // Tópico para recibir comandos

// Credenciales MQTT (si el broker las requiere)
#define MQTT_USER ""  // Usuario (vacío para brokers públicos)
#define MQTT_PASS ""  // Contraseña (vacío para brokers públicos)

// Configuración del cliente MQTT
#define MQTT_CLIENT_ID "ESP32_Dropster_AWG"
#define MQTT_KEEP_ALIVE 20

// Configuración de WiFi
#define WIFI_SSID "Tus nalgas_plus"
#define WIFI_PASS "Mc2321332"

// Configuración de envío de datos
#define MQTT_SEND_INTERVAL 5000  // Enviar datos cada 5 segundos

#endif // ESP32_MQTT_CONFIG_H
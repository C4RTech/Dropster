# CHANGELOG — Dropster

## Dropster_BETA_1.0 — 2025-09-22

Resumen
- Esta versión marca la primera beta pública del proyecto Dropster. Incluye el firmware AWG, la interfaz local (pantalla) y la app Flutter.

Archivos claves revisados
- [`codigo_ESP32_AWG/codigo_ESP32_AWG.ino:1`](codigo_ESP32_AWG/codigo_ESP32_AWG.ino:1) — Firmware principal AWG: sensores, control, calibración, MQTT.
- [`codigo_ESP32_AWG/esp32_mqtt_config.h:1`](codigo_ESP32_AWG/esp32_mqtt_config.h:1) — Configuración de pines, constantes y MQTT (contiene credenciales placeholder).
- [`codigo_ESP32_PANTALLA/codigo_ESP32_PANTALLA.ino:1`](codigo_ESP32_PANTALLA/codigo_ESP32_PANTALLA.ino:1) — Interfaz local LVGL, parser UART, controles.
- [`lib/services/mqtt_service.dart:1`](lib/services/mqtt_service.dart:1) — Servicio MQTT en Flutter.
- [`lib/services/singleton_mqtt_service.dart:1`](lib/services/singleton_mqtt_service.dart:1) — Orquestador de datos y notificador.

Highlights / funcionalidades principales
- Lectura de BME280, SHT31, PZEM y sensor ultrasónico con filtrado robusto.
- Algoritmo de control automático con anti-ciclado y lógica de ventilador.
- Sistema de calibración por tabla con interpolación lineal y refinamiento cuadrático.
- Interfaz táctil local con LVGL y sincronización UART.
- App Flutter con cliente MQTT resiliente y almacenamiento en Hive.

Instrucciones rápidas (Quickstart)
1. Clona el repositorio:
   git clone https://github.com/C4RTech/Dropster.git
2. Firmware AWG:
   - Abrir [`codigo_ESP32_AWG/codigo_ESP32_AWG.ino:1`](codigo_ESP32_AWG/codigo_ESP32_AWG.ino:1) en el IDE (Arduino o PlatformIO).
   - Revisar y editar credenciales en [`codigo_ESP32_AWG/esp32_mqtt_config.h:1`](codigo_ESP32_AWG/esp32_mqtt_config.h:1) o configurar WiFiManager AP al primer arranque.
   - Compilar y subir al ESP32.
3. Interfaz pantalla:
   - Abrir [`codigo_ESP32_PANTALLA/codigo_ESP32_PANTALLA.ino:1`](codigo_ESP32_PANTALLA/codigo_ESP32_PANTALLA.ino:1), compilar y flashear al segundo ESP32 (si aplica).
4. App Flutter:
   - Instalar dependencias: flutter pub get
   - Ejecutar: flutter run

Notas de release (Dropster_BETA_1.0)
- Estado: Beta. Uso con fines de prueba. No apto aún para despliegue comercial.
- Seguridad: MQTT por defecto usa broker público sin TLS. Cambiar a broker seguro antes de uso en producción.
- Credenciales: [`codigo_ESP32_AWG/esp32_mqtt_config.h:1`](codigo_ESP32_AWG/esp32_mqtt_config.h:1) contiene placeholders; no exponer credenciales en repositorio.

Problemas conocidos y limitaciones
- Firmware monolítico en un solo .ino dificulta mantenimiento y pruebas.
- No hay OTA seguro implementado.
- Buffer de logs limitado y sin mecanismo centralizado de descarga.
- Falta de pruebas unitarias y simuladores.

Recomendaciones inmediatas (prioridad alta)
- Eliminar credenciales hardcode y usar provisioning (WiFiManager AP + QR/BLE).
- Habilitar MQTTS y autenticación.
- Refactorizar firmware en módulos .h/.cpp y agregar PlatformIO.

Contenido del release y archivos adjuntos sugeridos
- Sugerido: archivo ZIP del repo en este tag y notas breves.

Pasos para crear el tag y release (ejecutar localmente)
- git add -A
- git commit -m "DROPSTER BETA 1.0"
- git push origin HEAD:refs/heads/main
- git tag -a Dropster_BETA_1.0 -m "Dropster Beta 1.0"
- git push origin Dropster_BETA_1.0
- Opcional (GitHub CLI): gh release create Dropster_BETA_1.0 --title "Dropster Beta 1.0" --notes-file ./CHANGELOG.md

Contacto y soporte
- Repo: https://github.com/C4RTech/Dropster
- Issues: usa la sección Issues del repo para reportar bugs y solicitudes.

Historia de cambios
- 2025-09-22: Primera beta pública — funciones base (sensores, control, UI local, app MQTT).
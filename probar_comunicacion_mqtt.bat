@echo off
echo ============================================
echo PRUEBA DE COMUNICACION MQTT PUBLICA
echo ============================================
echo.

echo PASO 1: Verificando conectividad a brokers publicos...
echo.

echo Probando test.mosquitto.org...
ping -n 1 test.mosquitto.org >nul 2>&1
if %errorlevel% == 0 (
    echo ✅ test.mosquitto.org - Conectividad OK
) else (
    echo ❌ test.mosquitto.org - Sin conectividad
)

echo.
echo Probando broker.hivemq.com...
ping -n 1 broker.hivemq.com >nul 2>&1
if %errorlevel% == 0 (
    echo ✅ broker.hivemq.com - Conectividad OK
) else (
    echo ❌ broker.hivemq.com - Sin conectividad
)

echo.
echo ============================================
echo INSTRUCCIONES PARA PRUEBA:
echo ============================================
echo.
echo 1. SUBE EL CODIGO AL ESP32:
echo    - El ESP32 se conectara automaticamente a test.mosquitto.org
echo    - Publicara datos en: dropster_test/data
echo    - Escuchara comandos en: dropster_test/control
echo.
echo 2. INSTALA LA APP EN TU TELEFONO:
echo    flutter build apk
echo    - Instala el APK generado
echo.
echo 3. VERIFICA LA COMUNICACION:
echo    - La app deberia recibir datos del ESP32
echo    - Los controles de la app deberian funcionar en el ESP32
echo.
echo 4. MONITOREA LOS LOGS:
echo    - ESP32: Serial Monitor (115200 baud)
echo    - App: Logs en la consola de desarrollo
echo.
echo ============================================
echo TOPICS DE COMUNICACION:
echo ============================================
echo.
echo ESP32 → App: dropster_test/data
echo ESP32 → App: dropster_test/status
echo ESP32 → App: dropster_test/heartbeat
echo App → ESP32: dropster_test/control
echo.
echo ============================================

pause
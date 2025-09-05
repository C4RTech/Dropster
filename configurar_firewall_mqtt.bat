@echo off
echo Configurando firewall para Mosquitto MQTT...
echo.

echo Agregando regla para puerto 1883 (MQTT)...
netsh advfirewall firewall add rule name="Mosquitto MQTT" dir=in action=allow protocol=TCP localport=1883

echo.
echo Agregando regla para puerto 8883 (MQTT SSL) - opcional...
netsh advfirewall firewall add rule name="Mosquitto MQTT SSL" dir=in action=allow protocol=TCP localport=8883

echo.
echo Verificando reglas creadas...
netsh advfirewall firewall show rule name="Mosquitto MQTT"

echo.
echo Configuracion completada!
echo Ahora puedes probar la conexion desde otros dispositivos.
echo.
pause
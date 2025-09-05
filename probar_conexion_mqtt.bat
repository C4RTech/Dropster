@echo off
echo Probando conexion MQTT al broker local...
echo.

echo 1. Probando localhost (debe funcionar):
"C:\Program Files\mosquitto\mosquitto_pub.exe" -h 127.0.0.1 -p 1883 -t "test/localhost" -m "Mensaje desde localhost"
echo.

echo 2. Probando IP de red local (192.168.1.123):
"C:\Program Files\mosquitto\mosquitto_pub.exe" -h 192.168.1.123 -p 1883 -t "test/network" -m "Mensaje desde red local"
echo.

echo 3. Verificando estado del broker:
netstat -ano | findstr :1883
echo.

echo 4. Verificando reglas de firewall:
netsh advfirewall firewall show rule name="Mosquitto MQTT"
echo.

echo Pruebas completadas!
echo Si la prueba 2 falla, ejecuta 'configurar_firewall_mqtt.bat' como administrador.
echo.
pause
# Procedimientos de Calibración de Sensores - Dropster AWG

## Introducción

Este documento describe los procedimientos para calibrar los sensores utilizados en el dispositivo Dropster AWG. Una calibración adecuada asegura la precisión de las mediciones y el correcto funcionamiento del sistema.

## Sensores a Calibrar

### 1. Sensor de Temperatura y Humedad (BME280)

#### Calibración de Temperatura
1. Coloque el sensor en un ambiente de temperatura conocida (usando un termómetro de referencia calibrado).
2. Espere 30 minutos para que el sensor se estabilice.
3. Registre la lectura del sensor y la temperatura real.
4. Ajuste el offset en el firmware:
   ```cpp
   // En config.h
   #define TEMP_OFFSET 0.5  // Ajustar según diferencia medida
   ```

#### Calibración de Humedad
1. Use una cámara de humedad sellada con solución salina saturada.
2. Espere 2 horas para estabilización.
3. Compare con higrómetro de referencia.
4. Ajuste el factor de calibración en el código.

### 2. Sensor de Temperatura Adicional (SHT30)

#### Procedimiento
1. Compare lecturas con termómetro de referencia en rangos de 0°C, 25°C y 50°C.
2. Calcule el error promedio.
3. Ajuste la compensación en el firmware.

### 3. Sensor Ultrasónico (Nivel de Agua)

#### Calibración
1. Vacíe completamente el tanque.
2. Mida la distancia real desde el sensor hasta el fondo.
3. Registre la lectura del sensor.
4. Calcule el factor de corrección:
   ```
   factor_correccion = distancia_real / lectura_sensor
   ```

### 4. Sensor Eléctrico (PZEM004T)

#### Verificación
1. Use un multímetro calibrado para verificar voltaje, corriente y potencia.
2. Compare lecturas en diferentes cargas.
3. Ajuste factores de calibración si es necesario.

## Frecuencia de Calibración

- **Temperatura/Humedad**: Cada 6 meses o cuando se detecten desviaciones >2°C o >5% HR
- **Nivel de Agua**: Al instalar y cada 3 meses
- **Parámetros Eléctricos**: Anual o cuando se detecten anomalías

## Herramientas Requeridas

- Termómetro digital calibrado
- Higrómetro de referencia
- Multímetro digital
- Cámara de calibración de humedad
- Software Arduino IDE para ajustes

## Registro de Calibraciones

Mantenga un registro de todas las calibraciones realizadas, incluyendo:
- Fecha
- Técnico responsable
- Valores antes/después
- Condiciones ambientales
- Resultados

## Notas Importantes

- Realice calibraciones en condiciones ambientales controladas.
- No modifique los sensores físicamente.
- Verifique la integridad de cables y conexiones antes de calibrar.
- Documente cualquier reemplazo de sensor.
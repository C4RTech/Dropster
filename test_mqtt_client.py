import paho.mqtt.client as mqtt
import json
import time

# Configuración MQTT
BROKER = "test.mosquitto.org"
PORT = 1883
TOPICS = {
    "data": "awg/data",
    "status": "awg/status", 
    "control": "awg/control",
    "heartbeat": "awg/heartbeat"
}

def on_connect(client, userdata, flags, rc):
    if rc == 0:
        print("✅ Conectado al broker MQTT")
        # Suscribirse a todos los topics del AWG
        for topic_name, topic in TOPICS.items():
            client.subscribe(topic)
            print(f"📡 Suscrito a: {topic}")
    else:
        print(f"❌ Error de conexión: {rc}")

def on_message(client, userdata, msg):
    topic = msg.topic
    payload = msg.payload.decode()
    
    print(f"\n📨 Mensaje recibido:")
    print(f"   Topic: {topic}")
    
    # Intentar parsear como JSON
    try:
        data = json.loads(payload)
        print(f"   Datos JSON:")
        for key, value in data.items():
            print(f"     {key}: {value}")
    except:
        print(f"   Payload: {payload}")
    
    print("-" * 50)

def send_test_commands(client):
    """Enviar comandos de prueba al ESP32"""
    print("\n🔧 Enviando comandos de prueba...")
    
    # Solicitar estado
    client.publish(TOPICS["control"], "GET_STATUS")
    print("📤 Enviado: GET_STATUS")
    
    time.sleep(2)
    
    # Solicitar datos
    client.publish(TOPICS["control"], "GET_DATA")
    print("📤 Enviado: GET_DATA")

def main():
    print("🚀 Cliente MQTT de Prueba para AWG")
    print("=" * 50)
    
    # Crear cliente MQTT
    client = mqtt.Client()
    client.on_connect = on_connect
    client.on_message = on_message
    
    try:
        # Conectar al broker
        print(f"🔗 Conectando a {BROKER}:{PORT}...")
        client.connect(BROKER, PORT, 60)
        
        # Iniciar loop en background
        client.loop_start()
        
        # Esperar un poco para la conexión
        time.sleep(3)
        
        # Enviar comandos de prueba
        send_test_commands(client)
        
        # Mantener el cliente corriendo
        print("\n👂 Escuchando mensajes... (Ctrl+C para salir)")
        while True:
            time.sleep(1)
            
    except KeyboardInterrupt:
        print("\n🛑 Deteniendo cliente...")
    except Exception as e:
        print(f"❌ Error: {e}")
    finally:
        client.loop_stop()
        client.disconnect()
        print("👋 Cliente desconectado")

if __name__ == "__main__":
    main()

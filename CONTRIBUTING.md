# Guía de Contribución - Dropster

¡Gracias por tu interés en contribuir a Dropster! Este documento describe cómo puedes ayudar al proyecto.

## 🚀 Inicio Rápido

1. **Fork** el repositorio
2. **Clona** tu fork: `git clone https://github.com/tu-usuario/Dropster.git`
3. **Crea** una rama: `git checkout -b feature/nueva-funcionalidad`
4. **Instala** dependencias: `flutter pub get`
5. **Desarrolla** y **prueba** tus cambios
6. **Commit**: `git commit -m "Descripción clara"`
7. **Push**: `git push origin feature/nueva-funcionalidad`
8. **Pull Request**: Abre un PR en GitHub

## 📋 Tipos de Contribuciones

### 🐛 Reportes de Bugs
- Usa la plantilla de issue en GitHub
- Incluye pasos para reproducir
- Especifica versión de Flutter/Dart
- Adjunta logs si es posible

### ✨ Nuevas Funcionalidades
- Discute ideas grandes en Issues primero
- Sigue la arquitectura existente
- Incluye tests cuando sea posible

### 📚 Documentación
- Mejoras a README, guías de usuario
- Comentarios en código
- Traducciones

### 🧪 Tests
- Tests unitarios para lógica compleja
- Tests de integración para MQTT
- Tests de UI para widgets críticos

## 🛠️ Configuración de Desarrollo

### Flutter App
```bash
flutter pub get
flutter run
```

### Firmware ESP32
- Instala Arduino IDE
- Abre `hardware/awg/mainAWG.ino` o `hardware/display/mainDisplay.ino`
- Instala las librerías necesarias vía Library Manager (WiFi, PubSubClient, etc.)
- Configura los pines y parámetros en `config.h`
- Compila y sube al ESP32

### Testing MQTT
- Sigue `docs/mqtt_test_guide.md`
- Usa broker público para desarrollo

## 📝 Estándares de Código

### Flutter/Dart
- Usa `flutter analyze` para linting
- Sigue [Effective Dart](https://dart.dev/guides/language/effective-dart)
- Nombres descriptivos en inglés
- Documenta funciones públicas

### ESP32/C++
- Comentarios en español/inglés
- Nombres de variables en inglés
- Usa defines para constantes
- Manejo robusto de errores

### Commits
- Mensajes claros en inglés
- Prefijos: `feat:`, `fix:`, `docs:`, `refactor:`
- Ejemplo: `feat: add offline mode support`

## 🔍 Pull Requests

### Checklist
- [ ] Tests pasan
- [ ] Linting OK
- [ ] Documentación actualizada
- [ ] Funciona en Android/iOS
- [ ] Firmware compila sin errores

### Descripción del PR
- ¿Qué resuelve?
- Cómo probar
- Screenshots si aplica
- Breaking changes?

## 📞 Contacto

- **Issues**: Para bugs y features
- **Discussions**: Para preguntas generales
- **Email**: carlosguedez7323@gmail.com

¡Tus contribuciones hacen que Dropster sea mejor! 🎉
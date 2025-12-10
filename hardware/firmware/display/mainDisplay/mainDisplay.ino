/* ========================================================================================
 * Sistema Dropster AWG (Atmospheric Water Generator) - Interfaz Local v1.0
 * ========================================================================================
 * Descripción: Interfaz de control y monitoreo local del dispositivo Dropster AWG
 * ========================================================================================*/

// Librerias
#include <lvgl.h>
#include <TFT_eSPI.h>
#include <XPT2046_Touchscreen.h>
#include <math.h>

// Pines para el táctil
#define XPT2046_IRQ 36
#define XPT2046_MOSI 32
#define XPT2046_MISO 39
#define XPT2046_CLK 25
#define XPT2046_CS 33

// Pin para control del backlight del display
#define TFT_BACKLIGHT_PIN 21
#define LV_COLOR_DEPTH 16

SPIClass touchscreenSPI = SPIClass(VSPI);
XPT2046_Touchscreen touchscreen(XPT2046_CS, XPT2046_IRQ);

// Dimensiones y buffer de la pantalla
#define SCREEN_WIDTH 240
#define SCREEN_HEIGHT 320
#define DRAW_BUF_SIZE (SCREEN_WIDTH * SCREEN_HEIGHT / 10 * (LV_COLOR_DEPTH / 8))
uint32_t draw_buf[DRAW_BUF_SIZE / 4];
bool ledState = false;
bool ventState = false;
bool compFanState = false;
bool pumpState = false;
// Variables para control del backlight
bool backlightOn = true;
unsigned long lastActivityTime = 0;
unsigned int screenTimeoutSec = 0;  // Timeout en segundos, 0 = deshabilitado
lv_obj_t *labels[13];
lv_obj_t *agua_label;

// UI handles globales para control de modo y botones
lv_obj_t *ui_btn_comp;
lv_obj_t *ui_btn_vent;
lv_obj_t *ui_btn_comp_fan;
lv_obj_t *ui_btn_pump;
lv_obj_t *mode_btn_small;
bool uiModeAuto = false;

// Variables para mantener últimos valores válidos
float lastValidVals[19];

// Paleta de colores
#define COLOR_PRIMARY     lv_color_hex(0xFFF9C4)
#define COLOR_SECONDARY   lv_color_hex(0xFFD700)
#define COLOR_WHITE       lv_color_hex(0xFFFFFF)
#define COLOR_ACCENT1     lv_color_hex(0xFF9800)
#define COLOR_DARK        lv_color_hex(0x5D4037)
#define COLOR_ACCENT2     lv_color_hex(0xFFC107)
#define COLOR_PANEL       lv_color_hex(0xFFF59D)
#define COLOR_SHADOW      lv_color_hex(0xF57F17)

// Logging para LVGL (opcional)
void log_print(lv_log_level_t level, const char * buf) {
  LV_UNUSED(level);
}

// Touchscreen para LVGL
void touchscreen_read(lv_indev_t * indev, lv_indev_data_t * data) {
   if(touchscreen.tirqTouched() && touchscreen.touched()) {
     TS_Point p = touchscreen.getPoint();
     int x = map(p.x, 200, 3700, 1, SCREEN_WIDTH);
     int y = map(p.y, 240, 3800, 1, SCREEN_HEIGHT);
     data->state = LV_INDEV_STATE_PRESSED;
     data->point.x = x;
     data->point.y = y;

     // Reset timer de actividad cuando hay toque en pantalla
     lastActivityTime = millis();
     if (!backlightOn) {
       digitalWrite(TFT_BACKLIGHT_PIN, HIGH);
       backlightOn = true;
       Serial.println("BACKLIGHT:ON");  // Notificar al ESP32
     }
   } else {
     data->state = LV_INDEV_STATE_RELEASED;
   }
}

// Botón: ON/OFF inmediato y respuesta rápida
static void event_handler_btn(lv_event_t * e) {
  lv_event_code_t code = lv_event_get_code(e);
  lv_obj_t * obj = (lv_obj_t*) lv_event_get_target(e);
  if(code == LV_EVENT_CLICKED) {
    lv_obj_t * label = lv_obj_get_child(obj, 0);
    const char *txt = label ? lv_label_get_text(label) : NULL;
    bool currentlyOn = (txt && strstr(txt, "APAGAR") != NULL);
    if (currentlyOn) {
      Serial1.println("off"); // Comando para apagar Compresor
      lv_label_set_text(label, "ENCENDER AWG");
      lv_obj_set_style_bg_color(obj, COLOR_SECONDARY, 0);
      lv_obj_set_style_shadow_color(obj, lv_color_darken(COLOR_SECONDARY, 30), 0);
      ledState = false;
    } else {
      Serial1.println("on");  // Comando para encender Compresor
      lv_label_set_text(label, "APAGAR AWG");
      lv_obj_set_style_bg_color(obj, COLOR_ACCENT1, 0);
      lv_obj_set_style_shadow_color(obj, lv_color_darken(COLOR_ACCENT1, 30), 0);
      ledState = true;
    }
  }
}

// Handler ventilador
static void event_handler_vent(lv_event_t * e) {
  lv_event_code_t code = lv_event_get_code(e);
  lv_obj_t * obj = (lv_obj_t*) lv_event_get_target(e);
  if(code == LV_EVENT_CLICKED) {
    lv_obj_t * label = lv_obj_get_child(obj, 0);
    const char *txt = label ? lv_label_get_text(label) : NULL;
    bool currentlyOn = (txt && strstr(txt, "APAGAR") != NULL);
    if (currentlyOn) {
      Serial1.println("offv"); // Comando para apagar FAN Evaporador
      lv_label_set_text(label, "ENCEDER EFAN");
      lv_obj_set_style_bg_color(obj, COLOR_SECONDARY, 0);
      ventState = false;
    } else {
      Serial1.println("onv");  // Comando para encender FAN Evaporador
      lv_label_set_text(label, "APAGAR EFAN");
      lv_obj_set_style_bg_color(obj, COLOR_ACCENT1, 0);
      ventState = true;
    }
  }
}

// Handler ventilador del compresor
static void event_handler_comp_fan(lv_event_t * e) {
   lv_event_code_t code = lv_event_get_code(e);
   lv_obj_t * obj = (lv_obj_t*) lv_event_get_target(e);
   if(code == LV_EVENT_CLICKED) {
     lv_obj_t * label = lv_obj_get_child(obj, 0);
     const char *txt = label ? lv_label_get_text(label) : NULL;
     bool currentlyOn = (txt && strstr(txt, "APAGAR") != NULL); // "APAGAR CFAN" => actualmente encendido
     if (currentlyOn) {
       Serial1.println("offcf"); // Comando para apagar FAN Compresor
       lv_label_set_text(label, "ENCENDER CFAN");
       lv_obj_set_style_bg_color(obj, COLOR_SECONDARY, 0);
       compFanState = false;
     } else {
       Serial1.println("oncf");  // Comando para encender FAN Compresor
       lv_label_set_text(label, "APAGAR CFAN");
       lv_obj_set_style_bg_color(obj, COLOR_ACCENT1, 0);
       compFanState = true;
     }
   }
}

// Handler bomba
static void event_handler_pump(lv_event_t * e) {
   lv_event_code_t code = lv_event_get_code(e);
   lv_obj_t * obj = (lv_obj_t*) lv_event_get_target(e);
   if(code == LV_EVENT_CLICKED) {
     lv_obj_t * label = lv_obj_get_child(obj, 0);
     const char *txt = label ? lv_label_get_text(label) : NULL;
     bool currentlyOn = (txt && strstr(txt, "APAGAR") != NULL);
     if (currentlyOn) {
       Serial1.println("offb"); // Comando para apagar Bomba de agua
       lv_label_set_text(label, "ENCENDER BOMB");
       lv_obj_set_style_bg_color(obj, COLOR_SECONDARY, 0);
       pumpState = false;
     } else {
       Serial1.println("onb");  // Comando para encender Bomba de agua
       lv_label_set_text(label, "APAGAR BOMB");
       lv_obj_set_style_bg_color(obj, COLOR_ACCENT1, 0);
       pumpState = true;
     }
   }
}

// Handler para cambiar Modo AUTO / MANUAL desde la pantalla
static void event_handler_mode(lv_event_t * e) {
  if (lv_event_get_code(e) != LV_EVENT_CLICKED) return;
  uiModeAuto = !uiModeAuto;

  // actualizar botón MODE y botones operativos
  if (uiModeAuto) {
    // mostrar MODO AUTO y deshabilitar botones manuales
    if (mode_btn_small) {
      lv_obj_t *lbl = lv_obj_get_child(mode_btn_small, 0);
      if (lbl) lv_label_set_text(lbl, "MODO AUTO");
      lv_obj_set_style_bg_color(mode_btn_small, lv_color_hex(0x64B5F6), 0);
    }
    if (ui_btn_comp) lv_obj_add_state(ui_btn_comp, LV_STATE_DISABLED);
    if (ui_btn_vent) lv_obj_add_state(ui_btn_vent, LV_STATE_DISABLED);
    if (ui_btn_comp_fan) lv_obj_add_state(ui_btn_comp_fan, LV_STATE_DISABLED);
    if (ui_btn_pump) lv_obj_add_state(ui_btn_pump, LV_STATE_DISABLED);
    Serial1.println("MODE AUTO");
  } else {
    // mostrar MODO MANUAL y habilitar botones manuales
    if (mode_btn_small) {
      lv_obj_t *lbl = lv_obj_get_child(mode_btn_small, 0);
      if (lbl) lv_label_set_text(lbl, "MODO MANUAL");
      lv_obj_set_style_bg_color(mode_btn_small, COLOR_SECONDARY, 0);
    }
    if (ui_btn_comp) lv_obj_clear_state(ui_btn_comp, LV_STATE_DISABLED);
    if (ui_btn_vent) lv_obj_clear_state(ui_btn_vent, LV_STATE_DISABLED);
    if (ui_btn_comp_fan) lv_obj_clear_state(ui_btn_comp_fan, LV_STATE_DISABLED);
    if (ui_btn_pump) lv_obj_clear_state(ui_btn_pump, LV_STATE_DISABLED);
    Serial1.println("MODE MANUAL");
  }
}

// Handler para activar portal WiFi desde display
static void event_handler_wifi_config(lv_event_t * e) {
  if (lv_event_get_code(e) != LV_EVENT_CLICKED) return;
  Serial1.println("WIFI_CONFIG");  // Comando para abrir portal WiFi
}

// Handler para reconectar WiFi y MQTT desde display
static void event_handler_reconnect(lv_event_t * e) {
   if (lv_event_get_code(e) != LV_EVENT_CLICKED) return;
   Serial1.println("RECONNECT");  // Comando para reconectar WiFi y MQTT
}

// Handler para resetear energía desde display
static void event_handler_reset_energy(lv_event_t * e) {
   if (lv_event_get_code(e) != LV_EVENT_CLICKED) return;
   Serial1.println("reset_energy");  // Comando para resetear energía
}

const char* names[13] = {
    "Temperatura:", "Presion ATM:", "Humedad Relativa:", "Humedad Abs:", "Pto Rocio:",
    "Temperatura:", "Humedad Relativa:",
    "Temperatura:", "Temp Max:",
    "Voltaje:", "Corriente:", "Potencia:", "Energia:"
};
const char* formats[13] = {
    "%.2f °C", "%.2f hPa", "%.2f %%", "%.2f g/m3", "%.2f °C",
    "%.2f °C", "%.2f %%",
    "%.2f °C", "%.2f °C",
    "%.2f V", "%.2f A", "%.2f W", "%.2f Wh"
};

void lv_create_main_gui(void) {
    lv_obj_t * bg = lv_screen_active();
    lv_obj_set_style_bg_color(bg, COLOR_PRIMARY, 0);
    lv_obj_set_style_bg_opa(bg, LV_OPA_COVER, 0);

    lv_obj_t *title = lv_label_create(bg);
    lv_label_set_text(title, "DROPSTER");
    lv_obj_set_style_text_color(title, COLOR_DARK, 0);
    lv_obj_set_style_text_font(title, &lv_font_montserrat_22, 0);
    lv_obj_align(title, LV_ALIGN_TOP_MID, 0, 15);

    lv_obj_t *subtitle = lv_label_create(bg);
    lv_label_set_text(subtitle, "Sistema Generador de Agua Atmosferica");
    lv_obj_set_style_text_color(subtitle, COLOR_DARK, 0);
    lv_obj_set_style_text_font(subtitle, &lv_font_montserrat_14, 0);
    lv_obj_set_style_text_align(subtitle, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_set_width(subtitle, SCREEN_WIDTH - 20);
    lv_obj_align(subtitle, LV_ALIGN_TOP_MID, 0, 45);

    // Contenedor para el valor de agua almacenada
    lv_obj_t * agua_cont = lv_obj_create(bg);
    lv_obj_set_size(agua_cont, 180, 80);
    lv_obj_align(agua_cont, LV_ALIGN_TOP_MID, 0, 90);
    lv_obj_set_style_bg_color(agua_cont, lv_color_lighten(COLOR_PANEL, 30), 0);
    lv_obj_set_style_radius(agua_cont, 15, 0);
    lv_obj_set_style_border_width(agua_cont, 0, 0);
    lv_obj_set_style_shadow_color(agua_cont, COLOR_SHADOW, 0);
    lv_obj_set_style_shadow_width(agua_cont, 15, 0);
    lv_obj_set_style_shadow_spread(agua_cont, 3, 0);
    lv_obj_set_style_shadow_ofs_y(agua_cont, 3, 0);
    lv_obj_set_style_pad_all(agua_cont, 5, 0);

    lv_obj_t * agua_flex = lv_obj_create(agua_cont);
    lv_obj_remove_style(agua_flex, NULL, LV_PART_MAIN);
    lv_obj_set_size(agua_flex, LV_PCT(100), LV_PCT(100));
    lv_obj_set_style_bg_opa(agua_flex, LV_OPA_0, 0);
    lv_obj_set_style_border_width(agua_flex, 0, 0);
    lv_obj_set_flex_flow(agua_flex, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_flex_align(agua_flex, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    lv_obj_center(agua_flex);

    lv_obj_t * agua_title = lv_label_create(agua_flex);
    lv_label_set_text(agua_title, "AGUA ALMACENADA");
    lv_obj_set_style_text_color(agua_title, COLOR_DARK, 0);
    lv_obj_set_style_text_font(agua_title, &lv_font_montserrat_12, 0);
    lv_obj_set_style_text_align(agua_title, LV_TEXT_ALIGN_CENTER, 0);

    agua_label = lv_label_create(agua_flex);
    lv_label_set_text(agua_label, "0 L");
    lv_obj_set_style_text_color(agua_label, COLOR_ACCENT1, 0);
    lv_obj_set_style_text_font(agua_label, &lv_font_montserrat_28, 0);
    lv_obj_set_style_text_align(agua_label, LV_TEXT_ALIGN_CENTER, 0);

    lv_obj_t * agua_time = lv_label_create(agua_flex);
    lv_label_set_text(agua_time, "HOY");
    lv_obj_set_style_text_color(agua_time, COLOR_DARK, 0);
    lv_obj_set_style_text_font(agua_time, &lv_font_montserrat_12, 0);
    lv_obj_set_style_text_align(agua_time, LV_TEXT_ALIGN_CENTER, 0);

    // Panel de datos con subtítulos
    lv_obj_t * data_panel = lv_obj_create(bg);
    lv_obj_set_size(data_panel, 220, 200);
    lv_obj_align(data_panel, LV_ALIGN_TOP_MID, 0, 440);
    lv_obj_set_style_bg_color(data_panel, COLOR_PANEL, 0);
    lv_obj_set_style_bg_opa(data_panel, LV_OPA_100, 0);
    lv_obj_set_style_border_color(data_panel, lv_color_lighten(COLOR_ACCENT1, 20), 0);
    lv_obj_set_style_border_width(data_panel, 2, 0);
    lv_obj_set_style_radius(data_panel, 15, 0);
    lv_obj_set_style_shadow_color(data_panel, COLOR_SHADOW, 0);
    lv_obj_set_style_shadow_width(data_panel, 15, 0);
    lv_obj_set_style_shadow_spread(data_panel, 3, 0);
    lv_obj_set_style_shadow_ofs_y(data_panel, 3, 0);
    lv_obj_set_flex_flow(data_panel, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_flex_align(data_panel, LV_FLEX_ALIGN_START, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_SPACE_EVENLY);
    lv_obj_set_style_pad_all(data_panel, 6, 0);
    lv_obj_set_style_pad_row(data_panel, 2, 0);

    // Botón para configurar WiFi
    lv_obj_t *wifi_config_btn = lv_button_create(bg);
    lv_obj_set_size(wifi_config_btn, 180, 30);
    lv_obj_add_event_cb(wifi_config_btn, event_handler_wifi_config, LV_EVENT_CLICKED, NULL);
    lv_obj_set_style_bg_color(wifi_config_btn, COLOR_SECONDARY, 0);
    lv_obj_set_style_radius(wifi_config_btn, 16, 0);
    lv_obj_set_style_shadow_color(wifi_config_btn, lv_color_darken(COLOR_SECONDARY, 20), 0);
    lv_obj_set_style_shadow_width(wifi_config_btn, 10, 0);
    lv_obj_set_style_shadow_ofs_y(wifi_config_btn, 1, 0);

    lv_obj_t *wifi_config_label = lv_label_create(wifi_config_btn);
    lv_label_set_text(wifi_config_label, "WIFI CONFIG");
    lv_obj_set_style_text_color(wifi_config_label, COLOR_DARK, 0);
    lv_obj_set_style_text_font(wifi_config_label, &lv_font_montserrat_14, 0);
    lv_obj_center(wifi_config_label);
    lv_obj_align_to(wifi_config_btn, data_panel, LV_ALIGN_OUT_BOTTOM_MID, 0, 20);

    // Botón para reconectar WiFi y MQTT
    lv_obj_t *reconnect_btn = lv_button_create(bg);
    lv_obj_set_size(reconnect_btn, 180, 30);
    lv_obj_add_event_cb(reconnect_btn, event_handler_reconnect, LV_EVENT_CLICKED, NULL);
    lv_obj_set_style_bg_color(reconnect_btn, COLOR_SECONDARY, 0);
    lv_obj_set_style_radius(reconnect_btn, 16, 0);
    lv_obj_set_style_shadow_color(reconnect_btn, lv_color_darken(COLOR_SECONDARY, 20), 0);
    lv_obj_set_style_shadow_width(reconnect_btn, 10, 0);
    lv_obj_set_style_shadow_ofs_y(reconnect_btn, 1, 0);

    lv_obj_t *reconnect_label = lv_label_create(reconnect_btn);
    lv_label_set_text(reconnect_label, "RECONECTAR");
    lv_obj_set_style_text_color(reconnect_label, COLOR_DARK, 0);
    lv_obj_set_style_text_font(reconnect_label, &lv_font_montserrat_14, 0);
    lv_obj_center(reconnect_label);
    lv_obj_align_to(reconnect_btn, wifi_config_btn, LV_ALIGN_OUT_BOTTOM_MID, 0, 15);

    // Botón para resetear energía
    lv_obj_t *reset_energy_btn = lv_button_create(bg);
    lv_obj_set_size(reset_energy_btn, 180, 30);
    lv_obj_add_event_cb(reset_energy_btn, event_handler_reset_energy, LV_EVENT_CLICKED, NULL);
    lv_obj_set_style_bg_color(reset_energy_btn, COLOR_SECONDARY, 0);
    lv_obj_set_style_radius(reset_energy_btn, 16, 0);
    lv_obj_set_style_shadow_color(reset_energy_btn, lv_color_darken(COLOR_SECONDARY, 20), 0);
    lv_obj_set_style_shadow_width(reset_energy_btn, 10, 0);
    lv_obj_set_style_shadow_ofs_y(reset_energy_btn, 1, 0);

    lv_obj_t *reset_energy_label = lv_label_create(reset_energy_btn);
    lv_label_set_text(reset_energy_label, "RESET ENERGIA");
    lv_obj_set_style_text_color(reset_energy_label, COLOR_DARK, 0);
    lv_obj_set_style_text_font(reset_energy_label, &lv_font_montserrat_14, 0);
    lv_obj_center(reset_energy_label);
    lv_obj_align_to(reset_energy_btn, reconnect_btn, LV_ALIGN_OUT_BOTTOM_MID, 0, 15);

    // Subtítulo 1: VALORES AMBIENTALES (sin Agua almac)
    lv_obj_t *sub1 = lv_label_create(data_panel);
    lv_label_set_text(sub1, "VALORES AMBIENTALES");
    lv_obj_set_style_text_color(sub1, COLOR_ACCENT1, 0);
    lv_obj_set_style_text_font(sub1, &lv_font_montserrat_12, 0);
    lv_obj_set_style_text_align(sub1, LV_TEXT_ALIGN_LEFT, 0);

    int idx = 0;
    for (int i = 0; i <= 4; i++, idx++) { // Temp Amb, Presion, HR Amb, HA Amb, Pto Rocio
        lv_obj_t * cont = lv_obj_create(data_panel);
        lv_obj_set_size(cont, LV_PCT(100), LV_SIZE_CONTENT);
        lv_obj_set_style_bg_opa(cont, LV_OPA_0, 0);
        lv_obj_set_style_border_width(cont, 0, 0);
        lv_obj_set_flex_flow(cont, LV_FLEX_FLOW_ROW);
        lv_obj_set_flex_align(cont, LV_FLEX_ALIGN_SPACE_BETWEEN, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
        lv_obj_set_style_pad_column(cont, 5, 0);

        lv_obj_t * name_lbl = lv_label_create(cont);
        lv_label_set_text(name_lbl, names[idx]);
        lv_obj_set_style_text_color(name_lbl, COLOR_DARK, 0);
        lv_obj_set_style_text_font(name_lbl, &lv_font_montserrat_12, 0);
        labels[idx] = lv_label_create(cont);
        lv_label_set_text(labels[idx], "--");
        lv_obj_set_style_text_color(labels[idx], COLOR_ACCENT1, 0);
        lv_obj_set_style_text_font(labels[idx], &lv_font_montserrat_12, 0);
        lv_obj_set_style_text_align(labels[idx], LV_TEXT_ALIGN_RIGHT, 0);
    }

    // Subtítulo 2: EVAPORADOR
    lv_obj_t *sub2 = lv_label_create(data_panel);
    lv_label_set_text(sub2, "EVAPORADOR");
    lv_obj_set_style_text_color(sub2, COLOR_ACCENT1, 0);
    lv_obj_set_style_text_font(sub2, &lv_font_montserrat_12, 0);
    lv_obj_set_style_text_align(sub2, LV_TEXT_ALIGN_LEFT, 0);

    for (int i = 5; i <= 6; i++, idx++) { // Temp Evap, Hum Evap
        lv_obj_t * cont = lv_obj_create(data_panel);
        lv_obj_set_size(cont, LV_PCT(100), LV_SIZE_CONTENT);
        lv_obj_set_style_bg_opa(cont, LV_OPA_0, 0);
        lv_obj_set_style_border_width(cont, 0, 0);
        lv_obj_set_flex_flow(cont, LV_FLEX_FLOW_ROW);
        lv_obj_set_flex_align(cont, LV_FLEX_ALIGN_SPACE_BETWEEN, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
        lv_obj_set_style_pad_column(cont, 5, 0);

        lv_obj_t * name_lbl = lv_label_create(cont);
        lv_label_set_text(name_lbl, names[idx]);
        lv_obj_set_style_text_color(name_lbl, COLOR_DARK, 0);
        lv_obj_set_style_text_font(name_lbl, &lv_font_montserrat_12, 0);
        labels[idx] = lv_label_create(cont);
        lv_label_set_text(labels[idx], "--");
        lv_obj_set_style_text_color(labels[idx], COLOR_ACCENT1, 0);
        lv_obj_set_style_text_font(labels[idx], &lv_font_montserrat_12, 0);
        lv_obj_set_style_text_align(labels[idx], LV_TEXT_ALIGN_RIGHT, 0);
    }

    // Subtítulo 3: COMPRESOR
    lv_obj_t *sub3 = lv_label_create(data_panel);
    lv_label_set_text(sub3, "COMPRESOR");
    lv_obj_set_style_text_color(sub3, COLOR_ACCENT1, 0);
    lv_obj_set_style_text_font(sub3, &lv_font_montserrat_12, 0);
    lv_obj_set_style_text_align(sub3, LV_TEXT_ALIGN_LEFT, 0);

    for (int i = 7; i <= 8; i++, idx++) { // Temp Compresor, Temp Max Compresor
        lv_obj_t * cont = lv_obj_create(data_panel);
        lv_obj_set_size(cont, LV_PCT(100), LV_SIZE_CONTENT);
        lv_obj_set_style_bg_opa(cont, LV_OPA_0, 0);
        lv_obj_set_style_border_width(cont, 0, 0);
        lv_obj_set_flex_flow(cont, LV_FLEX_FLOW_ROW);
        lv_obj_set_flex_align(cont, LV_FLEX_ALIGN_SPACE_BETWEEN, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
        lv_obj_set_style_pad_column(cont, 5, 0);

        lv_obj_t * name_lbl = lv_label_create(cont);
        lv_label_set_text(name_lbl, names[idx]);
        lv_obj_set_style_text_color(name_lbl, COLOR_DARK, 0);
        lv_obj_set_style_text_font(name_lbl, &lv_font_montserrat_12, 0);
        labels[idx] = lv_label_create(cont);
        lv_label_set_text(labels[idx], "--");
        lv_obj_set_style_text_color(labels[idx], COLOR_ACCENT1, 0);
        lv_obj_set_style_text_font(labels[idx], &lv_font_montserrat_12, 0);
        lv_obj_set_style_text_align(labels[idx], LV_TEXT_ALIGN_RIGHT, 0);
    }

    // Subtítulo 4: CONSUMO ELECTRICO
    lv_obj_t *sub4 = lv_label_create(data_panel);
    lv_label_set_text(sub4, "CONSUMO ELECTRICO");
    lv_obj_set_style_text_color(sub4, COLOR_ACCENT1, 0);
    lv_obj_set_style_text_font(sub4, &lv_font_montserrat_12, 0);
    lv_obj_set_style_text_align(sub4, LV_TEXT_ALIGN_LEFT, 0);

    for (int i = 9; i <= 12; i++, idx++) { // Voltaje, Corriente, Potencia, Energia
        lv_obj_t * cont = lv_obj_create(data_panel);
        lv_obj_set_size(cont, LV_PCT(100), LV_SIZE_CONTENT);
        lv_obj_set_style_bg_opa(cont, LV_OPA_0, 0);
        lv_obj_set_style_border_width(cont, 0, 0);
        lv_obj_set_flex_flow(cont, LV_FLEX_FLOW_ROW);
        lv_obj_set_flex_align(cont, LV_FLEX_ALIGN_SPACE_BETWEEN, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
        lv_obj_set_style_pad_column(cont, 5, 0);
 
        lv_obj_t * name_lbl = lv_label_create(cont);
        lv_label_set_text(name_lbl, names[idx]);
        lv_obj_set_style_text_color(name_lbl, COLOR_DARK, 0);
        lv_obj_set_style_text_font(name_lbl, &lv_font_montserrat_12, 0);
        labels[idx] = lv_label_create(cont);
        lv_label_set_text(labels[idx], "--");
        lv_obj_set_style_text_color(labels[idx], COLOR_ACCENT1, 0);
        lv_obj_set_style_text_font(labels[idx], &lv_font_montserrat_12, 0);
        lv_obj_set_style_text_align(labels[idx], LV_TEXT_ALIGN_RIGHT, 0);
    }

    // Contenedor de botones
    lv_obj_t *btn_cont = lv_obj_create(bg);
    lv_obj_set_size(btn_cont, 220, 190);
    lv_obj_align(btn_cont, LV_ALIGN_BOTTOM_MID, 0, 185);
    lv_obj_set_flex_flow(btn_cont, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_flex_align(btn_cont, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    lv_obj_set_style_pad_all(btn_cont, 6, 0);
    lv_obj_set_style_pad_row(btn_cont, 6, 0);
    lv_obj_set_style_border_width(btn_cont, 0, 0);
    lv_obj_set_style_shadow_width(btn_cont, 0, 0);
    lv_obj_set_style_bg_opa(btn_cont, LV_OPA_0, 0);
    lv_obj_set_scrollbar_mode(btn_cont, LV_SCROLLBAR_MODE_OFF);

    // Botón principal: Compresor
    ui_btn_comp = lv_button_create(btn_cont);
    lv_obj_set_size(ui_btn_comp, 180, 40);
    lv_obj_add_event_cb(ui_btn_comp, event_handler_btn, LV_EVENT_CLICKED, NULL);
    lv_obj_set_style_bg_color(ui_btn_comp, COLOR_SECONDARY, 0);
    lv_obj_set_style_radius(ui_btn_comp, 20, 0);
    lv_obj_set_style_shadow_color(ui_btn_comp, COLOR_SHADOW, 0);
    lv_obj_set_style_shadow_width(ui_btn_comp, 12, 0);
    lv_obj_set_style_shadow_ofs_y(ui_btn_comp, 1, 0);

    lv_obj_t *label = lv_label_create(ui_btn_comp);
    lv_label_set_text(label, "ENCENDER AWG");
    lv_obj_set_style_text_color(label, COLOR_DARK, 0);
    lv_obj_set_style_text_font(label, &lv_font_montserrat_14, 0);
    lv_obj_center(label);

    mode_btn_small = lv_button_create(bg);
    lv_obj_set_size(mode_btn_small, 180, 30); 
    lv_obj_add_event_cb(mode_btn_small, event_handler_mode, LV_EVENT_CLICKED, NULL);
    lv_obj_set_style_bg_color(mode_btn_small, lv_color_hex(0x64B5F6), 0); // azul claro
    lv_obj_set_style_radius(mode_btn_small, 16, 0);
    lv_obj_set_style_shadow_color(mode_btn_small, lv_color_darken(lv_color_hex(0x64B5F6), 20), 0);
    lv_obj_set_style_shadow_width(mode_btn_small, 10, 0);
    lv_obj_set_style_shadow_ofs_y(mode_btn_small, 1, 0);
    lv_obj_t *mode_small_label = lv_label_create(mode_btn_small);
    lv_label_set_text(mode_small_label, "MODO MANUAL");
    lv_obj_set_style_text_color(mode_small_label, COLOR_DARK, 0);
    lv_obj_set_style_text_font(mode_small_label, &lv_font_montserrat_14, 0);
    lv_obj_center(mode_small_label);
    lv_obj_align_to(mode_btn_small, agua_cont, LV_ALIGN_OUT_BOTTOM_MID, 0, 27);

    // Botón Ventilador del Evaporador
    ui_btn_vent = lv_button_create(btn_cont);
    lv_obj_set_size(ui_btn_vent, 180, 40);
    lv_obj_add_event_cb(ui_btn_vent, event_handler_vent, LV_EVENT_CLICKED, NULL);
    lv_obj_set_style_bg_color(ui_btn_vent, COLOR_SECONDARY, 0);
    lv_obj_set_style_radius(ui_btn_vent, 18, 0);
    lv_obj_set_style_shadow_color(ui_btn_vent, COLOR_SHADOW, 0);
    lv_obj_set_style_shadow_width(ui_btn_vent, 12, 0);
    lv_obj_set_style_shadow_ofs_y(ui_btn_vent, 1, 0);

    lv_obj_t *label_vent = lv_label_create(ui_btn_vent);
    lv_label_set_text(label_vent, "ENCENDER EFAN");
    lv_obj_set_style_text_color(label_vent, COLOR_DARK, 0);
    lv_obj_set_style_text_font(label_vent, &lv_font_montserrat_14, 0);
    lv_obj_center(label_vent);

    // Botón Ventilador del Compresor
    ui_btn_comp_fan = lv_button_create(btn_cont);
    lv_obj_set_size(ui_btn_comp_fan, 180, 40);
    lv_obj_add_event_cb(ui_btn_comp_fan, event_handler_comp_fan, LV_EVENT_CLICKED, NULL);
    lv_obj_set_style_bg_color(ui_btn_comp_fan, COLOR_SECONDARY, 0);
    lv_obj_set_style_radius(ui_btn_comp_fan, 18, 0);
    lv_obj_set_style_shadow_color(ui_btn_comp_fan, COLOR_SHADOW, 0);
    lv_obj_set_style_shadow_width(ui_btn_comp_fan, 12, 0);
    lv_obj_set_style_shadow_ofs_y(ui_btn_comp_fan, 1, 0);

    lv_obj_t *label_comp_fan = lv_label_create(ui_btn_comp_fan);
    lv_label_set_text(label_comp_fan, "ENCENDER CFAN");
    lv_obj_set_style_text_color(label_comp_fan, COLOR_DARK, 0);
    lv_obj_set_style_text_font(label_comp_fan, &lv_font_montserrat_14, 0);
    lv_obj_center(label_comp_fan);

    // Botón Bomba
    ui_btn_pump = lv_button_create(btn_cont);
    lv_obj_set_size(ui_btn_pump, 180, 40);
    lv_obj_add_event_cb(ui_btn_pump, event_handler_pump, LV_EVENT_CLICKED, NULL);
    lv_obj_set_style_bg_color(ui_btn_pump, COLOR_SECONDARY, 0);
    lv_obj_set_style_radius(ui_btn_pump, 18, 0);
    lv_obj_set_style_shadow_color(ui_btn_pump, COLOR_SHADOW, 0);
    lv_obj_set_style_shadow_width(ui_btn_pump, 12, 0);
    lv_obj_set_style_shadow_ofs_y(ui_btn_pump, 1, 0);

    lv_obj_t *label_pump = lv_label_create(ui_btn_pump);
    lv_label_set_text(label_pump, "ENCENDER BOMB");
    lv_obj_set_style_text_color(label_pump, COLOR_DARK, 0);
    lv_obj_set_style_text_font(label_pump, &lv_font_montserrat_14, 0);
    lv_obj_center(label_pump);
}

void update_labels(float vals[18]) {
    // Valores ambientales (0..4). Mantener último valor válido si nuevo es NAN.
    for (int i = 0; i <= 4; i++) {
        if (!isnan(vals[i])) {
            lastValidVals[i] = vals[i];
            lv_label_set_text_fmt(labels[i], formats[i], vals[i]);
        } else if (!isnan(lastValidVals[i])) {
            lv_label_set_text_fmt(labels[i], formats[i], lastValidVals[i]);
        } else {
            lv_label_set_text(labels[i], "--");
        }
    }

    // Evaporador: Temp <- vals[5], Hum <- vals[6]
    if (!isnan(vals[5])) {
        lastValidVals[5] = vals[5];
        lv_label_set_text_fmt(labels[5], formats[5], vals[5]);
    } else if (!isnan(lastValidVals[5])) {
        lv_label_set_text_fmt(labels[5], formats[5], lastValidVals[5]);
    } else {
        lv_label_set_text(labels[5], "--");
    }
    if (!isnan(vals[6])) {
        lastValidVals[6] = vals[6];
        lv_label_set_text_fmt(labels[6], formats[6], vals[6]);
    } else if (!isnan(lastValidVals[6])) {
        lv_label_set_text_fmt(labels[6], formats[6], lastValidVals[6]);
    } else {
        lv_label_set_text(labels[6], "--");
    }

    // Compresor: Temp actual <- vals[7], Temp máxima <- vals[8]
    if (!isnan(vals[7])) {
        lastValidVals[7] = vals[7];
        lv_label_set_text_fmt(labels[7], formats[7], vals[7]);
    } else if (!isnan(lastValidVals[7])) {
        lv_label_set_text_fmt(labels[7], formats[7], lastValidVals[7]);
    } else {
        lv_label_set_text(labels[7], "--");
    }
    if (!isnan(vals[8])) {
        lastValidVals[8] = vals[8];
        lv_label_set_text_fmt(labels[8], formats[8], vals[8]);
    } else if (!isnan(lastValidVals[8])) {
        lv_label_set_text_fmt(labels[8], formats[8], lastValidVals[8]);
    } else {
        lv_label_set_text(labels[8], "--");
    }

    // Consumo eléctrico: Voltaje/Corriente/Potencia/Energia <- vals[9..12]
    if (!isnan(vals[9])) {
        lastValidVals[9] = vals[9];
        lv_label_set_text_fmt(labels[9], formats[9], vals[9]);
    } else if (!isnan(lastValidVals[9])) {
        lv_label_set_text_fmt(labels[9], formats[9], lastValidVals[9]);
    } else {
        lv_label_set_text(labels[9], "--");
    }
    if (!isnan(vals[10])) {
        lastValidVals[10] = vals[10];
        lv_label_set_text_fmt(labels[10], formats[10], vals[10]);
    } else if (!isnan(lastValidVals[10])) {
        lv_label_set_text_fmt(labels[10], formats[10], lastValidVals[10]);
    } else {
        lv_label_set_text(labels[10], "--");
    }
    if (!isnan(vals[11])) {
        lastValidVals[11] = vals[11];
        lv_label_set_text_fmt(labels[11], formats[11], vals[11]);
    } else if (!isnan(lastValidVals[11])) {
        lv_label_set_text_fmt(labels[11], formats[11], lastValidVals[11]);
    } else {
        lv_label_set_text(labels[11], "--");
    }
    if (!isnan(vals[12])) {
        lastValidVals[12] = vals[12];
        lv_label_set_text_fmt(labels[12], formats[12], vals[12]);
    } else if (!isnan(lastValidVals[12])) {
        lv_label_set_text_fmt(labels[12], formats[12], lastValidVals[12]);
    } else {
        lv_label_set_text(labels[12], "--");
    }

    // Agua almacenada (vals[17])
    if (!isnan(vals[17])) {
        lastValidVals[17] = vals[17];
        lv_label_set_text_fmt(agua_label, "%.2f L", vals[17]);
    } else if (!isnan(lastValidVals[17])) {
        lv_label_set_text_fmt(agua_label, "%.2f L", lastValidVals[17]);
    } else {
        lv_label_set_text(agua_label, "-- L");
    }
}

void update_agua_almacenada(float agua) {
    lv_label_set_text_fmt(agua_label, "%.2f L", agua);
}

void setup() {
    Serial.begin(115200);
    Serial1.begin(115200, SERIAL_8N1, 35, 22);  // RX=35 (de AWG TX=4), TX=22 (a AWG RX=0)
    delay(100);  // Esperar estabilización UART
    lv_init();
    lv_log_register_print_cb(log_print);

    // Configurar pin del backlight
    pinMode(TFT_BACKLIGHT_PIN, OUTPUT);
    digitalWrite(TFT_BACKLIGHT_PIN, HIGH);  // Encender backlight por defecto
    backlightOn = true;
    lastActivityTime = millis();

    touchscreenSPI.begin(XPT2046_CLK, XPT2046_MISO, XPT2046_MOSI, XPT2046_CS);
    touchscreen.begin(touchscreenSPI);
    touchscreen.setRotation(2);

    lv_display_t * disp;
    disp = lv_tft_espi_create(SCREEN_WIDTH, SCREEN_HEIGHT, draw_buf, sizeof(draw_buf));
    lv_display_set_rotation(disp, LV_DISPLAY_ROTATION_270);

    lv_indev_t * indev = lv_indev_create();
    lv_indev_set_type(indev, LV_INDEV_TYPE_POINTER);
    lv_indev_set_read_cb(indev, touchscreen_read);
    lv_create_main_gui();

    // Inicializar últimos valores válidos
    for (int i = 0; i < 19; i++) {
        lastValidVals[i] = NAN;
    }
}

void loop() {
    // Buffer fijo
    static char buffer[256];
    static size_t buf_idx = 0;
    const size_t BUF_MAX = sizeof(buffer) - 1;
    const int MAX_BYTES_PER_LOOP = 256; // limitar bytes procesados por iteración para mantener la UI responsiva
    int processed = 0;

    while (Serial1.available() && processed < MAX_BYTES_PER_LOOP) {
        char c = (char)Serial1.read();
        processed++;

        if (c == '\r') continue;
        if (c == '\n') {
 
            buffer[buf_idx] = '\0';
 
            // Trim inicial
            char *msg = buffer;
            while (*msg == ' ' || *msg == '\t') msg++;
 
            // Mensaje rápido de agua almacenada: "A:23.5"
            if (buf_idx >= 2 && msg[0] == 'A' && msg[1] == ':') {
                char *endptr = NULL;
                float agua = (float)strtod(&msg[2], &endptr);
                if (endptr != &msg[2]) {
                    update_agua_almacenada(agua);
                }
            }
            // Mensaje de inicialización desde AWG
            else if (strncmp(msg, "AWG_INIT:", 9) == 0) {
            }
            // Mensajes de estado o control desde AWG: MODE:, COMP:, VENT:, PUMP:, CTRL:
            else if (strncmp(msg, "MODE:", 5) == 0) {
                char *modeVal = msg + 5;
                while (*modeVal == ' ' || *modeVal == '\t') modeVal++;
                if (strstr(modeVal, "AUTO") != NULL) {
                    uiModeAuto = true;
                    if (mode_btn_small) {
                      lv_obj_t *lbl = lv_obj_get_child(mode_btn_small, 0);
                      if (lbl) lv_label_set_text(lbl, "MODO AUTO");
                      lv_obj_set_style_bg_color(mode_btn_small, lv_color_hex(0x64B5F6), 0);
                    }
                    if (ui_btn_comp) lv_obj_add_state(ui_btn_comp, LV_STATE_DISABLED);
                    if (ui_btn_vent) lv_obj_add_state(ui_btn_vent, LV_STATE_DISABLED);
                    if (ui_btn_comp_fan) lv_obj_add_state(ui_btn_comp_fan, LV_STATE_DISABLED);
                    if (ui_btn_pump) lv_obj_add_state(ui_btn_pump, LV_STATE_DISABLED);
                } else {
                    uiModeAuto = false;
                    if (mode_btn_small) {
                      lv_obj_t *lbl = lv_obj_get_child(mode_btn_small, 0);
                      if (lbl) lv_label_set_text(lbl, "MODO MANUAL");
                      lv_obj_set_style_bg_color(mode_btn_small, COLOR_SECONDARY, 0);
                    }
                    if (ui_btn_comp) lv_obj_clear_state(ui_btn_comp, LV_STATE_DISABLED);
                    if (ui_btn_vent) lv_obj_clear_state(ui_btn_vent, LV_STATE_DISABLED);
                    if (ui_btn_comp_fan) lv_obj_clear_state(ui_btn_comp_fan, LV_STATE_DISABLED);
                    if (ui_btn_pump) lv_obj_clear_state(ui_btn_pump, LV_STATE_DISABLED);
                }
            }
            else if (strncmp(msg, "COMP:", 5) == 0) {
                char *v = msg + 5;
                while (*v == ' ' || *v == '\t') v++;
                bool on = (strstr(v, "ON") != NULL);

                // Mantener la variable local en sincronía con el estado real del compresor
                ledState = on;

                if (ui_btn_comp) {
                    lv_obj_t *lbl = lv_obj_get_child(ui_btn_comp, 0);
                    if (on) {
                        lv_label_set_text(lbl, "APAGAR AWG");
                        lv_obj_set_style_bg_color(ui_btn_comp, COLOR_ACCENT1, 0);
                        lv_obj_set_style_shadow_color(ui_btn_comp, lv_color_darken(COLOR_ACCENT1, 30), 0);
                    } else {
                        lv_label_set_text(lbl, "ENCENDER AWG");
                        lv_obj_set_style_bg_color(ui_btn_comp, COLOR_SECONDARY, 0);
                        lv_obj_set_style_shadow_color(ui_btn_comp, lv_color_darken(COLOR_SECONDARY, 30), 0);
                    }
                }
            }
            else if (strncmp(msg, "VENT:", 5) == 0) {
                char *v = msg + 5;
                while (*v == ' ' || *v == '\t') v++;
                bool on = (strstr(v, "ON") != NULL);

                // Sincronizar estado local del ventilador
                ventState = on;

                if (ui_btn_vent) {
                    lv_obj_t *lbl = lv_obj_get_child(ui_btn_vent, 0);
                    if (on) {
                        lv_label_set_text(lbl, "APAGAR EFAN");
                        lv_obj_set_style_bg_color(ui_btn_vent, COLOR_ACCENT1, 0);
                    } else {
                        lv_label_set_text(lbl, "ENCENDER EFAN");
                        lv_obj_set_style_bg_color(ui_btn_vent, COLOR_SECONDARY, 0);
                    }
                }
            }
            else if (strncmp(msg, "CFAN:", 5) == 0) {
                char *v = msg + 5;
                while (*v == ' ' || *v == '\t') v++;
                bool on = (strstr(v, "ON") != NULL);

                // Sincronizar estado local del ventilador del compresor
                compFanState = on;

                if (ui_btn_comp_fan) {
                    lv_obj_t *lbl = lv_obj_get_child(ui_btn_comp_fan, 0);
                    if (on) {
                        lv_label_set_text(lbl, "APAGAR CFAN");
                        lv_obj_set_style_bg_color(ui_btn_comp_fan, COLOR_ACCENT1, 0);
                    } else {
                        lv_label_set_text(lbl, "ENCENDER CFAN");
                        lv_obj_set_style_bg_color(ui_btn_comp_fan, COLOR_SECONDARY, 0);
                    }
                }
            }
            else if (strncmp(msg, "PUMP:", 5) == 0) {
                char *v = msg + 5;
                while (*v == ' ' || *v == '\t') v++;
                bool on = (strstr(v, "ON") != NULL);

                // Sincronizar estado local de la bomba
                pumpState = on;

                if (ui_btn_pump) {
                    lv_obj_t *lbl = lv_obj_get_child(ui_btn_pump, 0);
                    if (on) {
                        lv_label_set_text(lbl, "APAGAR BOMB");
                        lv_obj_set_style_bg_color(ui_btn_pump, COLOR_ACCENT1, 0);
                    } else {
                        lv_label_set_text(lbl, "ENCENDER BOMB");
                        lv_obj_set_style_bg_color(ui_btn_pump, COLOR_SECONDARY, 0);
                    }
                }
            }
            else if (strncmp(msg, "CTRL:", 5) == 0) {
            }
            else if (strncmp(msg, "BACKLIGHT:", 10) == 0) {
                char *state = msg + 10;
                while (*state == ' ' || *state == '\t') state++;
                if (strstr(state, "ON") != NULL) {
                    digitalWrite(TFT_BACKLIGHT_PIN, HIGH);
                    backlightOn = true;
                    lastActivityTime = millis();
                } else if (strstr(state, "OFF") != NULL) {
                    digitalWrite(TFT_BACKLIGHT_PIN, LOW);
                    backlightOn = false;
                }
            }
            else if (strncmp(msg, "SCREEN_TIMEOUT:", 15) == 0) {
                char *timeoutStr = msg + 15;
                while (*timeoutStr == ' ' || *timeoutStr == '\t') timeoutStr++;
                screenTimeoutSec = atoi(timeoutStr);
                lastActivityTime = millis();  // Reset timer al cambiar configuración
            }
            // Mensaje CSV completo (valores)
            else if (buf_idx > 0) {
                float vals[18];
                int idx = 0;

                // Hacemos una copia modificable del buffer (ya es char[])
                char tmpBuf[256];
                size_t copyLen = buf_idx < sizeof(tmpBuf) - 1 ? buf_idx : (sizeof(tmpBuf) - 1);
                memcpy(tmpBuf, buffer, copyLen);
                tmpBuf[copyLen] = '\0';

                char *ptr = strtok(tmpBuf, ",");
                while (ptr && idx < 18) {
                    // Intentar convertir; marcar como NAN si no es numérico
                    char *endptr = nullptr;
                    double v = strtod(ptr, &endptr);
                    if (endptr != ptr) {
                        vals[idx++] = (float)v;
                    } else {
                        vals[idx++] = NAN;
                    }
                    ptr = strtok(NULL, ",");
                }
                // Guardar número de campos y rellenar el resto con NAN
                int fieldCount = idx;
                for (int i = idx; i < 18; i++) vals[i] = NAN;
                update_labels(vals);
            }
 
            // Reset del buffer para el próximo mensaje
            buf_idx = 0;
            buffer[0] = '\0';
        } else {
            // Añadir char al buffer si hay espacio; si no, descartar y resetear para evitar overflow
            if (buf_idx < BUF_MAX) {
                buffer[buf_idx++] = c;
            } else {
                // Buffer overflow - resetear para recuperar operación
                buf_idx = 0;
                buffer[0] = '\0';
            }
        }
    }
    // Gestionar timeout del backlight
    unsigned long currentTime = millis();
    if (screenTimeoutSec > 0 && backlightOn) {
        if (currentTime - lastActivityTime >= (unsigned long)screenTimeoutSec * 1000UL) {
            digitalWrite(TFT_BACKLIGHT_PIN, LOW);
            backlightOn = false;
            Serial.println("BACKLIGHT:OFF");  // Notificar al ESP32
        }
    }

    // Procesar la UI frecuentemente para evitar "pegados"
    lv_task_handler();
    lv_tick_inc(5);

    // Si hay más datos pendientes, dar un pequeño respiro para mantener responsividad
    if (Serial1.available() > 0) {
        delay(1);
    } else {
        delay(2);
    }
}
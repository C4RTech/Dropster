#define LV_COLOR_DEPTH 16
#include <lvgl.h>
#include <TFT_eSPI.h>
#include <XPT2046_Touchscreen.h>

// Pines para el táctil
#define XPT2046_IRQ 36
#define XPT2046_MOSI 32
#define XPT2046_MISO 39
#define XPT2046_CLK 25
#define XPT2046_CS 33

SPIClass touchscreenSPI = SPIClass(VSPI);
XPT2046_Touchscreen touchscreen(XPT2046_CS, XPT2046_IRQ);

// Dimensiones y buffer de la pantalla
#define SCREEN_WIDTH 240
#define SCREEN_HEIGHT 320
#define DRAW_BUF_SIZE (SCREEN_WIDTH * SCREEN_HEIGHT / 10 * (LV_COLOR_DEPTH / 8))
uint32_t draw_buf[DRAW_BUF_SIZE / 4];
bool ledState = false;
lv_obj_t *labels[13];
lv_obj_t *agua_label;

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
  Serial.println(buf);
  Serial.flush();
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
  } else {
    data->state = LV_INDEV_STATE_RELEASED;
  }
}

// Botón: ON/OFF inmediato y respuesta rápida
static void event_handler_btn(lv_event_t * e) {
  lv_event_code_t code = lv_event_get_code(e);
  lv_obj_t * obj = (lv_obj_t*) lv_event_get_target(e);
  if(code == LV_EVENT_CLICKED) {
    ledState = !ledState;
    lv_obj_t * label = lv_obj_get_child(obj, 0);
    if (ledState) {
      Serial1.println("ON");
      lv_label_set_text(label, "APAGAR AWG");
      lv_obj_set_style_bg_color(obj, COLOR_ACCENT1, 0);
      lv_obj_set_style_shadow_color(obj, lv_color_darken(COLOR_ACCENT1, 30), 0);
    } else {
      Serial1.println("OFF");
      lv_label_set_text(label, "ENCENDER AWG");
      lv_obj_set_style_bg_color(obj, COLOR_SECONDARY, 0);
      lv_obj_set_style_shadow_color(obj, lv_color_darken(COLOR_SECONDARY, 30), 0);
    }
  }
}

// Nombres y formatos en el orden solicitado (sin "Agua almac")
const char* names[13] = {
    "Temperatura:", "Presion ATM:", "Humedad Relativa:", "Humedad Abs:", "Pto Rocio:",      //valores ambientales
    "Temperatura:", "Humedad Relativa:",                                                    //temp, hum Evaporador
    "Temperatura:", "Humedad Relativa:",                                                    //temp, hum Condensador
    "Voltaje:", "Corriente:", "Potencia:", "Energia:"                                       //consumo electrico
};
const char* formats[13] = {
    "%.2f °C", "%.2f hPa", "%.2f %%", "%.2f g/m3", "%.2f °C",
    "%.2f °C", "%.2f %%",
    "%.2f °C", "%.2f %%",
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
    lv_obj_align(agua_cont, LV_ALIGN_TOP_MID, 0, 85);
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
    lv_obj_align(data_panel, LV_ALIGN_TOP_MID, 0, 250);
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

    // Subtítulo 3: CONDENSADOR
    lv_obj_t *sub3 = lv_label_create(data_panel);
    lv_label_set_text(sub3, "CONDENSADOR");
    lv_obj_set_style_text_color(sub3, COLOR_ACCENT1, 0);
    lv_obj_set_style_text_font(sub3, &lv_font_montserrat_12, 0);
    lv_obj_set_style_text_align(sub3, LV_TEXT_ALIGN_LEFT, 0);

    for (int i = 7; i <= 8; i++, idx++) { // Temp Cond, Hum Cond
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

    // Botón
    lv_obj_t *btn = lv_button_create(bg);
    lv_obj_set_size(btn, 180, 40);
    lv_obj_align(btn, LV_ALIGN_BOTTOM_MID, 0, -15);
    lv_obj_add_event_cb(btn, event_handler_btn, LV_EVENT_CLICKED, NULL);
    lv_obj_set_style_bg_color(btn, COLOR_SECONDARY, 0);
    lv_obj_set_style_bg_grad_color(btn, lv_color_lighten(COLOR_SECONDARY, 20), 0);
    lv_obj_set_style_bg_grad_dir(btn, LV_GRAD_DIR_HOR, 0);
    lv_obj_set_style_radius(btn, 20, 0);
    lv_obj_set_style_shadow_color(btn, COLOR_SHADOW, 0);
    lv_obj_set_style_shadow_width(btn, 20, 0);
    lv_obj_set_style_shadow_spread(btn, 2, 0);
    lv_obj_set_style_shadow_ofs_y(btn, 3, 0);
    lv_obj_set_style_border_color(btn, lv_color_darken(COLOR_SECONDARY, 20), 0);
    lv_obj_set_style_border_width(btn, 2, 0);

    lv_obj_t *label = lv_label_create(btn);
    lv_label_set_text(label, "ENCENDER AWG");
    lv_obj_set_style_text_color(label, COLOR_DARK, 0);
    lv_obj_set_style_text_font(label, &lv_font_montserrat_14, 0);
    lv_obj_center(label);

    lv_obj_set_style_translate_y(btn, -2, LV_STATE_PRESSED);
    lv_obj_set_style_shadow_ofs_y(btn, 1, LV_STATE_PRESSED);
}

// Actualiza los valores en pantalla con los datos recibidos por UART
void update_labels(float vals[14]) {
    // Mapea los índices: 0-4, 6-7, 8-9, 10-13 (sin agua almac, que es vals[5])
    int idx = 0;
    for (int i = 0; i <= 4; i++, idx++) {
        lv_label_set_text_fmt(labels[idx], formats[idx], vals[i]);
    }
    for (int i = 6; i <= 7; i++, idx++) {
        lv_label_set_text_fmt(labels[idx], formats[idx], vals[i]);
    }
    for (int i = 8; i <= 9; i++, idx++) {
        lv_label_set_text_fmt(labels[idx], formats[idx], vals[i]);
    }
    for (int i = 10; i <= 13; i++, idx++) {
        lv_label_set_text_fmt(labels[idx], formats[idx], vals[i]);
    }
    // Agua almacenada SIEMPRE se muestra tal cual
    lv_label_set_text_fmt(agua_label, "%.2f L", vals[5]);
}

void update_agua_almacenada(float agua) {
    lv_label_set_text_fmt(agua_label, "%.2f L", agua);
}

void setup() {
    Serial.begin(115200);
    Serial1.begin(115200, SERIAL_8N1, 27, 22);
    lv_init();
    lv_log_register_print_cb(log_print);

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
}

void loop() {
    static String buffer = "";
    while (Serial1.available()) {
        char c = Serial1.read();
        if (c == '\n') {
            // Mensaje rápido de agua almacenada: "A:23.5"
            if (buffer.startsWith("A:")) {
                float agua = buffer.substring(2).toFloat();
                update_agua_almacenada(agua);
            }
            // Mensaje CSV completo
            else {
                float vals[14];
                int idx = 0;
                char *ptr = strtok((char*)buffer.c_str(), ",");
                while (ptr && idx < 14) {
                    vals[idx++] = atof(ptr);
                    ptr = strtok(NULL, ",");
                }
                if (idx == 14) update_labels(vals);
            }
            buffer = "";
        } else {
            buffer += c;
        }
    }
    lv_task_handler();
    lv_tick_inc(5);
    delay(5);
}
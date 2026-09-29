// Adalight frame: 'A' 'd' 'a' | count-1 hi | count-1 lo | hi ^ lo ^ 0x55 | R G B * count
// 'K' after each show() paces the host: AVR serial RX is blind while show() disables interrupts.
// ESP32-S3/C3 hardware CDC can miss the connect edge, so the app also accepts a 'K' as ready.

#if defined(ARDUINO_ARCH_ESP8266)
  // Pin numbers are GPIO numbers, not NodeMCU D labels.
  #define FASTLED_ESP8266_RAW_PIN_ORDER
#endif
#include <FastLED.h>

#ifndef LED_TYPE
  #define LED_TYPE WS2812B
#endif
#ifndef COLOR_ORDER
  #define COLOR_ORDER GRB
#endif
#ifndef MAX_MILLIAMPS
  #define MAX_MILLIAMPS 1500
#endif
#define IDLE_TIMEOUT_MS 5000

#include "Board.h"

CRGB leds[MAX_LEDS];

static const uint8_t MAGIC[] = {'A', 'd', 'a'};
static unsigned long lastFrameMs = 0;
static bool isIdle = true;
static uint16_t shown = MAX_LEDS;
#if BOARD_NATIVE_USB
static bool hostConnected = false;
#endif

static void bootAnimation() {
  const uint8_t brightness = 90;
  const uint16_t wipeMs = 550;
  const uint8_t wipeFrames = 24;
  const uint16_t step = (MAX_LEDS + wipeFrames - 1) / wipeFrames;
  FastLED.setBrightness(brightness);
  for (uint16_t i = 0; i < MAX_LEDS; i++) {
    leds[i] = CHSV((uint8_t)(i * 3), 255, 255);
    if (i % step == step - 1 || i == MAX_LEDS - 1) {
      FastLED.show();
      delay(wipeMs / wipeFrames);
    }
  }
  delay(120);
  for (int16_t b = brightness; b >= 0; b -= 15) {
    FastLED.setBrightness(b);
    FastLED.show();
    delay(25);
  }
  FastLED.clear(true);
  FastLED.setBrightness(255);
}

static void greet() {
  bootAnimation();
  while (Serial.available()) Serial.read();
  Serial.print("Ada\n");
  isIdle = true;
}

static void service() {
  if (!isIdle && millis() - lastFrameMs > IDLE_TIMEOUT_MS) {
    FastLED.clear(true);
    isIdle = true;
  }
#if BOARD_NATIVE_USB
  bool connected = (bool)Serial;
  if (connected && !hostConnected) greet();
  hostConnected = connected;
#endif
  yield();
}

void setup() {
  FastLED.addLeds<LED_TYPE, DATA_PIN, COLOR_ORDER>(leds, MAX_LEDS);
  FastLED.setMaxPowerInVoltsAndMilliamps(5, MAX_MILLIAMPS);
  FastLED.setDither(0);

#if defined(ARDUINO_ARCH_ESP32) && !BOARD_NATIVE_USB
  Serial.setRxBufferSize(2048);
#endif
  Serial.begin(BAUD_RATE);
  Serial.setTimeout(100);
#if BOARD_NATIVE_USB
  bootAnimation();
#else
  greet();
#endif
}

void loop() {
  uint8_t matched = 0;
  while (matched < sizeof(MAGIC)) {
    if (!Serial.available()) {
      service();
      continue;
    }
    uint8_t b = Serial.read();
    if (b == MAGIC[matched]) {
      matched++;
    } else {
      matched = (b == MAGIC[0]) ? 1 : 0;
    }
  }

  uint8_t header[3];
  if (Serial.readBytes(header, 3) != 3) return;
  if (header[2] != (header[0] ^ header[1] ^ 0x55)) return;

  uint32_t count = ((uint32_t)header[0] << 8 | header[1]) + 1;
  uint16_t kept = count < MAX_LEDS ? count : MAX_LEDS;
  if (Serial.readBytes((uint8_t*)leds, (size_t)kept * 3) != (size_t)kept * 3) return;
  for (uint32_t extra = (count - kept) * 3; extra > 0; extra--) {
    uint8_t sink;
    if (Serial.readBytes(&sink, 1) != 1) return;
  }

  uint16_t length = kept > shown ? kept : shown;
  for (uint16_t i = kept; i < length; i++) leds[i] = CRGB::Black;
  FastLED[0].setLeds(leds, length);
  FastLED.show();
  shown = kept;
  Serial.write('K');
  lastFrameMs = millis();
  isIdle = false;
}

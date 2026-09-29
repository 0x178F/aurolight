#pragma once

#if defined(ARDUINO_ARCH_ESP32)
  #if ARDUINO_USB_CDC_ON_BOOT && !defined(BOARD_NATIVE_USB)
    #define BOARD_NATIVE_USB 1
  #endif
  #if defined(CONFIG_IDF_TARGET_ESP32C3)
    #define BOARD_DATA_PIN 4
  #else
    #define BOARD_DATA_PIN 16
  #endif
  #define BOARD_BAUD_RATE 921600
  #define BOARD_MAX_LEDS 1000
#elif defined(ARDUINO_ARCH_ESP8266)
  #define BOARD_DATA_PIN 4
  #define BOARD_BAUD_RATE 921600
  #define BOARD_MAX_LEDS 1000
#elif defined(ARDUINO_ARCH_RP2040)
  #ifndef BOARD_NATIVE_USB
    #define BOARD_NATIVE_USB 1
  #endif
  #define BOARD_DATA_PIN 2
  #define BOARD_BAUD_RATE 115200
  #define BOARD_MAX_LEDS 1000
#elif defined(TEENSYDUINO)
  #ifndef BOARD_NATIVE_USB
    #define BOARD_NATIVE_USB 1
  #endif
  #define BOARD_DATA_PIN 2
  #define BOARD_BAUD_RATE 115200
  #define BOARD_MAX_LEDS 1000
#elif defined(ARDUINO_AVR_MEGA2560)
  #define BOARD_DATA_PIN 5
  #define BOARD_BAUD_RATE 115200
  #define BOARD_MAX_LEDS 600
#elif defined(ARDUINO_ARCH_AVR)
  #define BOARD_DATA_PIN 5
  #define BOARD_BAUD_RATE 115200
  #define BOARD_MAX_LEDS 200
#else
  #error "Unsupported board: add it to Board.h"
#endif

#ifndef BOARD_NATIVE_USB
  #define BOARD_NATIVE_USB 0
#endif

#ifndef DATA_PIN
  #define DATA_PIN BOARD_DATA_PIN
#endif
#ifndef BAUD_RATE
  #define BAUD_RATE BOARD_BAUD_RATE
#endif
#ifndef MAX_LEDS
  #define MAX_LEDS BOARD_MAX_LEDS
#endif

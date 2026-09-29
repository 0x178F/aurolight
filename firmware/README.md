# Aurolight firmware

Receives Adalight frames from the app over USB and drives the strip with [FastLED](https://github.com/FastLED/FastLED).

- `Aurolight/Aurolight.ino`: the firmware. Strip settings (`LED_TYPE`, `COLOR_ORDER`, `MAX_MILLIAMPS`) are at the top.
- `Aurolight/Board.h`: per-board defaults (data pin, baud rate, maximum LEDs).
- `platformio.ini`: one build environment per board.

## Supported boards

| Board | Environment | Data pin | Baud rate | Max LEDs | Logic level |
|-------|-------------|----------|-----------|----------|-------------|
| Arduino Nano (old bootloader, most clones) | `nano` | D5 | 115200 | 200 | 5 V |
| Arduino Nano (new bootloader) | `nano_new` | D5 | 115200 | 200 | 5 V |
| Arduino Uno | `uno` | D5 | 115200 | 200 | 5 V |
| Arduino Mega 2560 | `mega` | D5 | 115200 | 600 | 5 V |
| ESP32 dev board (CP2102 / CH340) | `esp32` | GPIO16 | 921600 | 1000 | 3.3 V |
| ESP32-S3 DevKitC (native USB port) | `esp32s3` | GPIO16 | any¹ | 1000 | 3.3 V |
| ESP32-C3 SuperMini (native USB) | `esp32c3` | GPIO4 | any¹ | 1000 | 3.3 V |
| ESP8266 (Wemos D1 mini, NodeMCU) | `esp8266` | GPIO4 (D2) | 921600 | 1000 | 3.3 V |
| Raspberry Pi Pico (RP2040) | `pico` | GP2 | any¹ | 1000 | 3.3 V |
| Teensy 4.1 | `teensy41` | 2 | any¹ | 1000 | 3.3 V |

¹ Native USB: the baud rate doesn't limit the speed.

Set the app's baud rate to the board's value. 115200 carries about 25 frames/s for 140 LEDs; long strips need a
faster board.

## Wiring

| Strip | Connection |
|-------|------------|
| DIN   | Board data pin → 330–470 Ω resistor → DIN |
| GND   | Power supply GND + board GND (common ground) |
| +5V   | Power supply +5V |

- The power supply, the board and the strip must share ground.
- Power the board over USB; don't connect the power supply's +5V to the board as well.
- Size the supply for the strip: a WS2812B LED draws up to 60 mA at full white, so 150 LEDs need about 9 A at
  most. Set `MAX_MILLIAMPS` to about 80% of the supply's rating (e.g. 5 A → 4000); the firmware dims to stay
  under it.
- A 1000 µF capacitor across the strip's +5V and GND protects the first LEDs from the inrush at power-on.
- **3.3 V boards** (ESP32, ESP8266, Pico, Teensy): WS2812B strips expect a 5 V data signal. Short runs often work
  without help, but for reliable colors put a level shifter (74AHCT125 or 74HCT245) between the data pin and DIN.

## Build and flash

Quit Aurolight first: the serial port can only be open in one app.

```bash
make flash BOARD=esp32          # from the repo root; BOARD defaults to nano
# or, in firmware/:
pio run -e esp32 -t upload
```

With more than one board connected, pick the port: `make flash BOARD=esp32 PORT=/dev/cu.usbserial-…`.

First upload:

- **Arduino Nano clones:** if `nano` fails with "not in sync", try `nano_new`.
- **Raspberry Pi Pico:** hold BOOTSEL while plugging it in.
- **Teensy:** press the program button when the upload starts.
- **ESP32:** some boards need BOOT held while the upload starts.

Other strip types or pins without editing files:

```bash
PLATFORMIO_BUILD_FLAGS="-D DATA_PIN=13 -D LED_TYPE=SK6812 -D MAX_LEDS=300" make flash BOARD=esp32
```

With the Arduino IDE: install **FastLED** from the Library Manager, open `Aurolight/Aurolight.ino`, pick your board
and upload. For ESP32-S3/C3 set **USB CDC On Boot: Enabled**.

On start, a rainbow grows from the first LED: a quick check that the strip works and which way it runs.

## Protocol

```
'A' 'd' 'a' | count-1 hi | count-1 lo | hi ^ lo ^ 0x55 | R G B × count
```

The board replies `K` after showing each frame; the app waits for it, or a timeout, before sending the next. It
greets with `Ada\n` on connect.

## Adding a board

Add a branch to `Board.h` (data pin, baud rate, max LEDs, `BOARD_NATIVE_USB` if it has native USB), and an
environment to `platformio.ini`; CI builds every environment.

# Hello Nerves LCD SPI Example

Tiny Nerves demo that drives 320×480 SPI LCDs (ILI9486 / ST7796S) and optional
touch (XPT2046 / GT911) on Raspberry Pi–class targets. The app shows build
info, time, basic network status, and a demo image/text buffer.

## Getting Started

```bash
# Pick your hardware target
export MIX_TARGET=rpi3      # or rpi4, etc.

# Pick your display variant (see table below)
export LCD_TYPE=c           # a | b | c | f | g   (defaults to a)

# Optional Wi-Fi
export NERVES_WIFI_SSID="your-ssid"
export NERVES_WIFI_PASSPHRASE="your-psk"

# Dependencies & firmware
mix deps.get
mix firmware

# Flash or upload
mix burn                    # SD card
./upload nerves.local       # OTA via ssh/mdns
```

- The firmware advertises via mDNS as `nerves.local` (plus the serial-based hostname).
- If you see “Image Nothing…”, place a 320×480 RGB565 file at `priv/piyopiyoex_320x480.rgb565`.

## Display Types

Set `LCD_TYPE` to select panel + touch wiring/modules:

| LCD_TYPE | Panel                      | Controller |   Touch | Notes |
| -------: | -------------------------- | ---------: | ------: | ----- |
|      `a` | Waveshare 3.5" RPi LCD (A) |    ILI9486 | XPT2046 | TFT   |
|      `b` | Waveshare 3.5" RPi LCD (B) |    ILI9486 | XPT2046 | IPS   |
|      `c` | Waveshare 3.5" RPi LCD (C) |    ILI9486 | XPT2046 | TFT   |
|      `f` | Waveshare 3.5" RPi LCD (F) |    ST7796S |   GT911 | IPS   |
|      `g` | Waveshare 3.5" RPi LCD (G) |    ST7796S | XPT2046 | IPS   |

Reference pages:

- [https://www.waveshare.com/wiki/3.5inch*RPi_LCD*(A)](https://www.waveshare.com/wiki/3.5inch_RPi_LCD_%28A%29)
- [https://www.waveshare.com/wiki/3.5inch*RPi_LCD*(B)](https://www.waveshare.com/wiki/3.5inch_RPi_LCD_%28B%29)
- [https://www.waveshare.com/wiki/3.5inch*RPi_LCD*(C)](https://www.waveshare.com/wiki/3.5inch_RPi_LCD_%28C%29)
- [https://www.waveshare.com/wiki/3.5inch*RPi_LCD*(F)](https://www.waveshare.com/wiki/3.5inch_RPi_LCD_%28F%29)
- [https://www.waveshare.com/wiki/3.5inch*RPi_LCD*(G)](https://www.waveshare.com/wiki/3.5inch_RPi_LCD_%28G%29)
- MHS 3.5" (C-compatible): [https://www.lcdwiki.com/MHS-3.5inch_RPi_Display](https://www.lcdwiki.com/MHS-3.5inch_RPi_Display)

## What It Shows

- Build target, app version, and `lcd_<type>` label (`SampleApp.display_name/0`)
- Time (updated ~500 ms), network status lines (using VintageNet)
- Optional sprite text, simple color swatches, and an RGB565 demo image

## Pins and Buses (Raspberry Pi)

From the code defaults:

**LCD ili9486(for A/B/C)(SPI over `spidev0.0`):**

- SPI: `spidev0.0`
- `DC`: GPIO 24
- `RST`: GPIO 25
- `BL` (backlight enable): GPIO 18

**LCD ST7796S(for F/G)(SPI over `spidev0.0`):**

- SPI: `spidev0.0`
- `DC`: GPIO 22
- `RST`: GPIO 27
- `BL` (backlight enable): GPIO 18

**Touch XPT2046 (for A/B/C/G):**

- SPI: `spidev0.1`
- `IRQ` (pen-irq): GPIO 17

**Touch GT911 (for F):**

- I²C bus: `i2c-1`
- I²C addr: `0x14` (7-bit)
- `INT`: GPIO 4
- `RST`: GPIO 17

Adjust as needed if your hat uses different pins.

## Hardware Targets

Nerves builds depend on `MIX_TARGET`. If it is unset, the project runs on the host for fast cycles and utility tasks. See supported targets:
[https://hexdocs.pm/nerves/supported-targets.html](https://hexdocs.pm/nerves/supported-targets.html)

Typical targets: `rpi3`, `rpi4`.

## Configuration

Key environment variables:

- `MIX_TARGET` – Nerves system target (e.g., `rpi3`)
- `LCD_TYPE` – one of `a|b|c|f|g` (default `a`)
- `NERVES_NETWORK_SSID`, `NERVES_NETWORK_PSK` – Wi-Fi credentials

Other notable config:

- `regulatory_domain` set to `"JP"` in `config/target.exs`
- SSH keys are required for shell/OTA (reads `~/.ssh/id_*.pub`)

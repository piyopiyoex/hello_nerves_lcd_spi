defmodule SampleApp.LcdF.UI do
  use GenServer
  require Logger

  alias SampleApp.LcdG.ST7796S, as: LCD
  alias SampleApp.NetInfo
  alias SampleApp.TextDraw

  def start_link(_args \\ []) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(_) do
    # LCD 初期化
    {:ok, spi_lcd} = Circuits.SPI.open("spidev0.0", speed_hz: 60_000_000)
    {:ok, dc} = Circuits.GPIO.open(22, :output)
    {:ok, rst} = Circuits.GPIO.open(27, :output)
    LCD.init(spi_lcd, dc, rst)

    gpio = 18
    frequency = 800
    Pigpiox.Pwm.hardware_pwm(gpio, frequency, 1_000_000) # 100%
#    Pigpiox.Pwm.hardware_pwm(gpio, frequency, 500_000)   # 50%
#    Pigpiox.Pwm.hardware_pwm(gpio, frequency, 100_000)   # 10%
#    Pigpiox.Pwm.hardware_pwm(gpio, frequency, 10_000)    # 1%

    # 背景描画
    LCD.fill_rect(spi_lcd, dc, 0, 0, 320, 480, 0xF800)
    LCD.fill_rect(spi_lcd, dc, 0, 0, 320, 320, 0x07E0)
    LCD.fill_rect(spi_lcd, dc, 0, 0, 320, 160, 0x001F)

    build_target = SampleApp.build_target()
    display_str = SampleApp.display_name()
    rgb565_path = SampleApp.piyopiyoex_rgb565_path()

    buffer =
      if File.exists?(rgb565_path) do
        LCD.load_rgb565_to_buffer(rgb565_path)
      else
        :binary.copy(<<0xFF, 0xFF>>, 320 * 480)
        |> TextDraw.draw_text(60, 200, "Image Nothing...", 255, 0, 0, 2)
      end

    buffer = TextDraw.draw_text(buffer, 20, 330, display_str, 0, 0, 255, 2)

    buffer = TextDraw.draw_text(buffer, 20, 80, "Target: #{build_target}", 0, 0, 255, 4)

    LCD.flush_to_lcd(spi_lcd, dc, buffer)

    # 色見本　赤、緑、青
    LCD.fill_rect(spi_lcd, dc, 0, 0, 25, 25, 0xF800)
    LCD.fill_rect(spi_lcd, dc, 25, 25, 25, 25, 0x07E0)
    LCD.fill_rect(spi_lcd, dc, 50, 50, 25, 25, 0x001F)

    # 0.5秒ごとに時刻/IP表示更新
    :timer.send_interval(500, :tick)

    {:ok, %{spi: spi_lcd, dc: dc}}
  end

  # 時刻 + IP 表示
  @impl true
  def handle_info(:tick, %{spi: spi_lcd, dc: dc} = state) do
    now =
      DateTime.utc_now()
      |> DateTime.add(9 * 3600, :second)
      |> DateTime.to_naive()

    time_str = Calendar.strftime(now, "%Y-%m-%d %H:%M:%S")
    sprite = LCD.build_sprite(time_str, 0x0000, 0xFFFF, 2)
    x = 320 - sprite.w - 3
    y = 480 - sprite.h - 3
    LCD.push_sprite(spi_lcd, dc, x, y, %{w: sprite.w, h: sprite.h, pixels: sprite.pixels})

    lines = NetInfo.get_status_strings()

    Enum.with_index(lines)
    |> Enum.each(fn {line, idx} ->
      sprite = LCD.build_sprite(line, 0x0000, 0xFFFF, 2)

      LCD.push_sprite(spi_lcd, dc, 20, 360 + idx * 20, %{
        w: sprite.w,
        h: sprite.h,
        pixels: sprite.pixels
      })
    end)

    # ssidを取得して表示
    ssid_str = current_ssid()
    sprite_ssid = LCD.build_sprite(ssid_str, 0x0000, 0xFFFF, 2)

    LCD.push_sprite(spi_lcd, dc, 20, 440, %{
      w: sprite_ssid.w,
      h: sprite_ssid.h,
      pixels: sprite_ssid.pixels
    })

    {:noreply, state}
  end

  # XPT2046 GenServerからのタッチ通知を受け取る
  def handle_info({:touch, x, y}, %{spi: spi_lcd, dc: dc} = state) do
    text = :io_lib.format("x=~4..0B, y=~4..0B", [x, y]) |> IO.iodata_to_binary()
    # 緑文字
    sprite = LCD.build_sprite(text, 0x0000, 0xFEA0, 2)
    LCD.push_sprite(spi_lcd, dc, 150, 1, %{w: sprite.w, h: sprite.h, pixels: sprite.pixels})

    {:noreply, state}
  end

  defp current_ssid do
    case VintageNet.get(["interface", "wlan0", "wifi", "current_ap"]) do
      %_{ssid: ssid} -> ssid
      _ -> "No SSID"
    end
  end
end

defmodule SampleApp.LcdG.UI do
  use GenServer
  require Logger

  alias SampleApp.Backlight
  alias SampleApp.LcdG.ST7796S, as: LCD
  alias SampleApp.NetInfo
  alias SampleApp.TextDraw

  def start_link(_args \\ []) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(_) do
    # SPI 初期化リトライ: 最大20回 / 100ms間隔
    spi_result = retry_open_spi("spidev0.0", 60_000_000, 0, 20, 100)

    with {:ok, spi_lcd} <- spi_result,
         {:ok, dc} <- Circuits.GPIO.open(22, :output),
         {:ok, rst} <- Circuits.GPIO.open(27, :output) do
      # バックライト ON
      {:ok, _pid} = Backlight.start(18, 1.0)

      # LCD初期化
      case LCD.init(spi_lcd, dc, rst) do
        :ok -> :ok
        other -> Logger.error("LCD.init returned unexpected: #{inspect(other)}")
      end

      # 初期画面描画
      try do
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
        buffer = TextDraw.draw_text(buffer, 5, 80, "Target: #{build_target}", 0, 0, 255, 4)
        LCD.flush_to_lcd(spi_lcd, dc, buffer)

        # 色見本　赤、緑、青
        LCD.fill_rect(spi_lcd, dc, 0, 0, 25, 25, 0xF800)
        LCD.fill_rect(spi_lcd, dc, 25, 25, 25, 25, 0x07E0)
        LCD.fill_rect(spi_lcd, dc, 50, 50, 25, 25, 0x001F)
      rescue
        exc ->
          Logger.error("Exception during initial drawing: #{inspect(exc)}")
      end

      # 0.5秒ごとに時刻/IP表示更新
      :timer.send_interval(500, :tick)

      {:ok, %{spi: spi_lcd, dc: dc, rst: rst}}
    else
      {:error, reason} ->
        Logger.error("UI init failed: #{inspect(reason)}")
        {:stop, reason}

      other ->
        Logger.error("UI init unexpected result: #{inspect(other)}")
        {:stop, :init_failed}
    end
  end

  # SPI初期化リトライ関数
  defp retry_open_spi(device, speed_hz, mode, retries, interval_ms) do
    case Circuits.SPI.open(device, speed_hz: speed_hz, mode: mode) do
      {:ok, spi} ->
        {:ok, spi}

      {:error, reason} ->
        if retries > 0 do
          Logger.warning("SPI open failed (#{inspect(reason)}), retrying... [#{retries} left]")
          Process.sleep(interval_ms)
          retry_open_spi(device, speed_hz, mode, retries - 1, interval_ms)
        else
          Logger.error("SPI open failed after retries: #{inspect(reason)}")
          {:error, reason}
        end
    end
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

    lines = NetInfo.get_status_strings() || []

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
    ssid = NetInfo.get_ssid() || ""
    sprite_ssid = LCD.build_sprite(ssid, 0x0000, 0xFFFF, 2)

    LCD.push_sprite(spi_lcd, dc, 20, 440, %{
      w: sprite_ssid.w,
      h: sprite_ssid.h,
      pixels: sprite_ssid.pixels
    })

    {:noreply, state}
  end

  # XPT2046 GenServerからのタッチ通知を受け取る
  @impl true
  def handle_info({:touch, x, y}, %{spi: spi_lcd, dc: dc} = state) do
    text = :io_lib.format("x=~4..0B, y=~4..0B", [x, y]) |> IO.iodata_to_binary()
    sprite = LCD.build_sprite(text, 0x0000, 0xFEA0, 2)
    LCD.push_sprite(spi_lcd, dc, 150, 1, %{w: sprite.w, h: sprite.h, pixels: sprite.pixels})

    {:noreply, state}
  end
end

defmodule SampleApp.LcdC.UI do
  use GenServer
  require Logger
  alias SampleApp.LcdC.LCD
  alias SampleApp.Color
  alias SampleApp.Framebuffer
  alias SampleApp.NetInfo
  alias SampleApp.TextDraw

  def start_link(options \\ []) do
    GenServer.start_link(__MODULE__, options, name: __MODULE__)
  end

  @impl true
  def init(options) do
    display_width = 320
    display_height = 480

    is_high_speed = Keyword.get(options, :is_high_speed, true)
    spi_speed_hz = if is_high_speed, do: 125_000_000, else: 10_000_000

    # LCD 初期化
    {:ok, spi_lcd} = Circuits.SPI.open("spidev0.0", speed_hz: spi_speed_hz)
    {:ok, bl} = Circuits.GPIO.open(18, :output)
    Circuits.GPIO.write(bl, 1)

    {:ok, dc} = Circuits.GPIO.open(24, :output)
    {:ok, rst} = Circuits.GPIO.open(25, :output)

    # LCD 初期化
    {:ok, display} =
<<<<<<< HEAD
      ILI9486.new(
        is_high_speed: is_high_speed,
=======
      ILI9486.start_link(
        is_high_speed: true,
>>>>>>> origin/main
        spi_lcd: spi_lcd,
        # spi_touch: spi_touch,
        gpio_dc: dc,
        gpio_rst: rst,
        width: display_width,
        height: display_height,
        rotation: 0,
        pix_fmt: :rgb565
      )

    # 背景描画
    colors = [
      red: {255, 0, 0},
      green: {0, 255, 0},
      blue: {0, 0, 255},
      navy: {0, 0, 2}
    ]

    for {color_name, {red, green, blue}} <- colors do
      IO.puts("表示中: #{color_name}")
      pixel = Color.rgb565_binary(red, green, blue)
      buffer = :binary.copy(pixel, display_width * display_height)
      ILI9486.display_565(display, buffer)
      Process.sleep(500)
    end

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

    # 色見本　赤、緑、青
    buffer = Framebuffer.draw_filled_rect(buffer, 0, 0, 25, 25, 255, 0, 0)
    buffer = Framebuffer.draw_filled_rect(buffer, 25, 25, 25, 25, 0, 255, 0)
    buffer = Framebuffer.draw_filled_rect(buffer, 50, 50, 25, 25, 0, 0, 255)

    ILI9486.display_565(display, buffer)

    # 0.5秒ごとに時刻/IP表示更新
    :timer.send_interval(500, :tick)

    {:ok, %{spi: spi_lcd, dc: dc, buffer: buffer, display: display}}
  end

  # 時刻 + IP 表示
  @impl true
  def handle_info(:tick, %{spi: _spi_lcd, dc: _dc, buffer: buffer, display: display} = state) do
    now =
      DateTime.utc_now()
      |> DateTime.add(9 * 3600, :second)
      |> DateTime.to_naive()

    time_str = Calendar.strftime(now, "%Y-%m-%d %H:%M:%S")
    sprite = LCD.build_sprite(time_str, 0x0000, 0xFFFF, 2)
    x = 320 - sprite.w - 3
    y = 480 - sprite.h - 3
    buffer = Framebuffer.draw_sprite_with_background(buffer, x, y, sprite, 255, 255, 255)

    lines = NetInfo.get_status_strings()

    {buffer, _count} =
      Enum.with_index(lines)
      |> Enum.reduce({buffer, 0}, fn {line, idx}, {buf, count} ->
        sprite = LCD.build_sprite(line, 0x0000, 0xFFFF, 2)
        x = 20
        y = 360 + idx * 20

        new_buf = Framebuffer.draw_sprite_with_background(buf, x, y, sprite, 255, 255, 255)
        {new_buf, count + 1}
      end)

    # ssidを取得して表示
    sprite_ssid = LCD.build_sprite(NetInfo.get_ssid(), 0x0000, 0xFFFF, 2)

    x = 20
    y = 440

    new_buffer =
      Framebuffer.draw_sprite_with_background(buffer, x, y, sprite_ssid, 255, 255, 255)

    ILI9486.display_565(display, new_buffer)

    {:noreply, %{state | buffer: new_buffer}}
  end

  def handle_info({:touch, x, y}, %{buffer: buffer, display: display} = state) do
    text = :io_lib.format("x=~4..0B, y=~4..0B", [x, y]) |> IO.iodata_to_binary()
    # 緑文字
    sprite = LCD.build_sprite(text, 0x0000, 0xFEA0, 2)

    x_pos = 150
    y_pos = 1

    # sprite を背景（白）で塗ってから描画
    new_buffer =
      Framebuffer.draw_sprite_with_background(buffer, x_pos, y_pos, sprite, 255, 255, 255)

    ILI9486.display_565(display, new_buffer)

    {:noreply, %{state | buffer: new_buffer}}
  end
end

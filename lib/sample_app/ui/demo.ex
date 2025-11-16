defmodule SampleApp.UI.Demo do
  use GenServer
  require Logger

  alias SampleApp.Framebuffer
  alias SampleApp.NetInfo
  alias SampleApp.RGB565
  alias SampleApp.TextDraw

  ## Public API

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    driver_mod = Keyword.fetch!(opts, :driver)
    driver_opts = Keyword.get(opts, :driver_opts, [])

    {width, height} =
      case Keyword.get(opts, :size) do
        {w, h} when is_integer(w) and is_integer(h) ->
          {w, h}

        _ ->
          w = Keyword.get(driver_opts, :width)
          h = Keyword.get(driver_opts, :height)
          if is_integer(w) and is_integer(h), do: {w, h}, else: driver_mod.default_size()
      end

    # ドライバ起動
    {:ok, driver} = driver_mod.start_link(driver_opts)

    # 色テスト + 初期画面
    run_color_test(driver_mod, driver, width, height)
    buffer = build_initial_buffer(width, height)

    driver_mod.display_565(driver, buffer)
    :timer.send_interval(500, :tick)

    initial_state = %{
      driver_mod: driver_mod,
      driver: driver,
      width: width,
      height: height,
      buffer: buffer
    }

    {:ok, initial_state}
  end

  @impl true
  def handle_info(:tick, %{driver_mod: m, driver: d, width: w, height: h, buffer: buffer} = state) do
    now =
      DateTime.utc_now()
      |> DateTime.add(9 * 3600, :second)
      |> DateTime.to_naive()

    time_str = Calendar.strftime(now, "%Y-%m-%d %H:%M:%S")
    sprite_time = RGB565.build_sprite(time_str, 0x0000, 0xFFFF, 2)
    x_time = w - sprite_time.w - 3
    y_time = h - sprite_time.h - 3

    buffer =
      Framebuffer.draw_sprite_with_background(buffer, x_time, y_time, sprite_time, 255, 255, 255)

    lines = NetInfo.get_status_strings() || []

    {buffer, _count} =
      Enum.with_index(lines)
      |> Enum.reduce({buffer, 0}, fn {line, idx}, {buf, count} ->
        sprite = RGB565.build_sprite(line, 0x0000, 0xFFFF, 2)
        x = 20
        y = 360 + idx * 20
        {Framebuffer.draw_sprite_with_background(buf, x, y, sprite, 255, 255, 255), count + 1}
      end)

    ssid = NetInfo.get_ssid() || ""
    sprite_ssid = RGB565.build_sprite(ssid, 0x0000, 0xFFFF, 2)

    buffer =
      Framebuffer.draw_sprite_with_background(buffer, 20, 440, sprite_ssid, 255, 255, 255)

    m.display_565(d, buffer)

    {:noreply, %{state | buffer: buffer}}
  end

  @impl true
  def handle_info({:touch, x, y}, %{driver_mod: m, driver: d, buffer: buffer} = state) do
    text = :io_lib.format("x=~4..0B, y=~4..0B", [x, y]) |> IO.iodata_to_binary()
    sprite = RGB565.build_sprite(text, 0x0000, 0xFEA0, 2)

    buffer =
      Framebuffer.draw_sprite_with_background(buffer, 150, 1, sprite, 255, 255, 255)

    m.display_565(d, buffer)

    {:noreply, %{state | buffer: buffer}}
  end

  ## Helpers

  defp run_color_test(driver_mod, driver, width, height) do
    colors = [
      red: {255, 0, 0},
      green: {0, 255, 0},
      blue: {0, 0, 255},
      navy: {0, 0, 2}
    ]

    for {color_name, {r, g, b}} <- colors do
      IO.puts("表示中: #{color_name}")
      pixel = SampleApp.Color.rgb565_binary(r, g, b)
      buffer = :binary.copy(pixel, width * height)
      driver_mod.display_565(driver, buffer)
      Process.sleep(500)
    end
  end

  defp build_initial_buffer(width, height) do
    build_target = SampleApp.build_target()
    display_str = SampleApp.display_name()
    rgb565_path = SampleApp.piyopiyoex_rgb565_path()

    buffer =
      if File.exists?(rgb565_path) do
        SampleApp.RGB565.load_rgb565_to_buffer(rgb565_path)
      else
        :binary.copy(<<0xFF, 0xFF>>, width * height)
        |> TextDraw.draw_text(60, 200, "Image Nothing...", 255, 0, 0, 2)
      end

    buffer =
      buffer
      |> TextDraw.draw_text(20, 330, display_str, 0, 0, 255, 2)
      |> TextDraw.draw_text(5, 80, "Target: #{build_target}", 0, 0, 255, 4)
      |> Framebuffer.draw_filled_rect(0, 0, 25, 25, 255, 0, 0)
      |> Framebuffer.draw_filled_rect(25, 25, 25, 25, 0, 255, 0)
      |> Framebuffer.draw_filled_rect(50, 50, 25, 25, 0, 0, 255)

    buffer
  end
end

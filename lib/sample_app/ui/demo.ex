defmodule SampleApp.UI.Demo do
  use GenServer
  require Logger

  alias SampleApp.Framebuffer
  alias SampleApp.NetInfo
  alias SampleApp.RGB565
  alias SampleApp.TextDraw
  alias __MODULE__.State

  defmodule State do
    @enforce_keys [:lcd, :touch]
    defstruct lcd: nil,
              touch: %{mod: nil, pid: nil}
  end

  @tick_interval_ms 500

  ## Public API

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  ## GenServer callbacks

  @impl true
  def init(opts) do
    {driver_mod, driver_opts} = Keyword.fetch!(opts, :lcd_driver)
    {:ok, driver_pid} = driver_mod.start_link(driver_opts)
    %{width: width, height: height} = driver_mod.size(driver_pid)

    run_color_test(driver_mod, driver_pid, width, height)

    buffer = build_initial_buffer(width, height)
    driver_mod.display_565(driver_pid, buffer)

    :timer.send_interval(@tick_interval_ms, :tick)

    {touch_mod, touch_pid} = start_touch_driver(opts, width, height)

    lcd = %{
      mod: driver_mod,
      pid: driver_pid,
      width: width,
      height: height,
      buffer: buffer
    }

    touch = %{
      mod: touch_mod,
      pid: touch_pid
    }

    state = %State{
      lcd: lcd,
      touch: touch
    }

    {:ok, state}
  end

  @impl true
  def handle_info(:tick, %State{lcd: lcd} = state) do
    %{
      mod: driver_mod,
      pid: driver_pid,
      width: width,
      height: height,
      buffer: buffer
    } = lcd

    buffer =
      buffer
      |> draw_clock(width, height)
      |> draw_net_info()
      |> draw_ssid()

    driver_mod.display_565(driver_pid, buffer)

    new_lcd = %{lcd | buffer: buffer}

    {:noreply, %State{state | lcd: new_lcd}}
  end

  @impl true
  def handle_info({:touch, x, y}, state) do
    {:noreply, apply_touch_to_buffer(state, x, y)}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  ## Touch driver startup (polling style)

  defp start_touch_driver(opts, screen_width, screen_height) do
    case Keyword.get(opts, :touch_driver) do
      nil ->
        {nil, nil}

      {mod, touch_opts} ->
        touch_opts =
          touch_opts
          |> Keyword.put_new(:screen_width, screen_width)
          |> Keyword.put_new(:screen_height, screen_height)
          |> Keyword.put_new(:ui_pid, self())

        case mod.start_link(touch_opts) do
          {:ok, pid} ->
            {mod, pid}

          {:error, reason} ->
            Logger.warning("タッチドライバ #{inspect(mod)} の起動に失敗したため無効化します: #{inspect(reason)}")
            {nil, nil}
        end

      other ->
        Logger.warning("不正な :touch_driver オプションを無視します: #{inspect(other)}")
        {nil, nil}
    end
  end

  ## Drawing helpers

  defp draw_clock(buffer, width, height) do
    now =
      DateTime.utc_now()
      |> DateTime.add(9 * 3600, :second)
      |> DateTime.to_naive()

    time_str = Calendar.strftime(now, "%Y-%m-%d %H:%M:%S")
    sprite_time = RGB565.build_sprite(time_str, 0x0000, 0xFFFF, 2)
    x_time = width - sprite_time.w - 3
    y_time = height - sprite_time.h - 3

    Framebuffer.draw_sprite_with_background(buffer, x_time, y_time, sprite_time, 255, 255, 255)
  end

  defp draw_net_info(buffer) do
    lines = NetInfo.get_status_strings() || []

    Enum.with_index(lines)
    |> Enum.reduce(buffer, fn {line, idx}, buf ->
      sprite = RGB565.build_sprite(line, 0x0000, 0xFFFF, 2)
      x = 20
      y = 360 + idx * 20
      Framebuffer.draw_sprite_with_background(buf, x, y, sprite, 255, 255, 255)
    end)
  end

  defp draw_ssid(buffer) do
    ssid = NetInfo.get_ssid() || ""
    sprite_ssid = RGB565.build_sprite(ssid, 0x0000, 0xFFFF, 2)
    Framebuffer.draw_sprite_with_background(buffer, 20, 440, sprite_ssid, 255, 255, 255)
  end

  defp apply_touch_to_buffer(%State{lcd: lcd} = state, x, y) do
    %{mod: driver_mod, pid: driver_pid, buffer: buffer} = lcd

    text =
      :io_lib.format("x=~4..0B, y=~4..0B", [x, y])
      |> IO.iodata_to_binary()

    sprite = RGB565.build_sprite(text, 0x0000, 0xFEA0, 2)

    buffer =
      Framebuffer.draw_sprite_with_background(buffer, 150, 1, sprite, 255, 255, 255)

    driver_mod.display_565(driver_pid, buffer)

    new_lcd = %{lcd | buffer: buffer}
    %State{state | lcd: new_lcd}
  end

  ## Color test & initial buffer

  defp run_color_test(driver_mod, driver_pid, width, height) do
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
      driver_mod.display_565(driver_pid, buffer)
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

    buffer
    |> TextDraw.draw_text(20, 330, display_str, 0, 0, 255, 2)
    |> TextDraw.draw_text(5, 80, "Target: #{build_target}", 0, 0, 255, 4)
    |> Framebuffer.draw_filled_rect(0, 0, 25, 25, 255, 0, 0)
    |> Framebuffer.draw_filled_rect(25, 25, 25, 25, 0, 255, 0)
    |> Framebuffer.draw_filled_rect(50, 50, 25, 25, 0, 0, 255)
  end
end

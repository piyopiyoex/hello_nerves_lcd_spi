defmodule SampleApp.Touch.XPT2046 do
  @moduledoc """
  XPT2046 用のポーリング型タッチドライバ。

  一定間隔で IRQ ピンを読み取り、タッチ中は SPI から座標を取得して
  UI プロセスに `{:touch, x, y}` を送信する。
  """

  use GenServer
  import Bitwise
  require Logger

  defmodule State do
    @enforce_keys [:ui_pid, :irq, :spi]
    defstruct ui_pid: nil,
              irq: nil,
              spi: nil,
              poll_interval_ms: 100,
              screen_width: 320,
              screen_height: 480,
              x_min: 149,
              x_max: 3845,
              y_min: 294,
              y_max: 3831
  end

  @default_irq_pin 17
  @default_spi_bus "spidev0.1"
  @default_poll_interval_ms 100

  @default_x_min 149
  @default_x_max 3845
  @default_y_min 294
  @default_y_max 3831

  ## Public API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  ## GenServer callbacks

  @impl true
  def init(opts) do
    ui_pid = Keyword.fetch!(opts, :ui_pid)

    irq_pin = Keyword.get(opts, :irq_pin, @default_irq_pin)
    spi_bus = Keyword.get(opts, :spi_bus, @default_spi_bus)
    poll_interval_ms = Keyword.get(opts, :poll_interval_ms, @default_poll_interval_ms)

    screen_width = Keyword.fetch!(opts, :screen_width)
    screen_height = Keyword.fetch!(opts, :screen_height)

    x_min = Keyword.get(opts, :x_min, @default_x_min)
    x_max = Keyword.get(opts, :x_max, @default_x_max)
    y_min = Keyword.get(opts, :y_min, @default_y_min)
    y_max = Keyword.get(opts, :y_max, @default_y_max)

    {:ok, irq} = Circuits.GPIO.open(irq_pin, :input)
    {:ok, spi} = Circuits.SPI.open(spi_bus)

    Logger.info("XPT2046 初期化完了 (irq_pin=#{irq_pin}, spi_bus=#{spi_bus})")

    state = %State{
      ui_pid: ui_pid,
      irq: irq,
      spi: spi,
      poll_interval_ms: poll_interval_ms,
      screen_width: screen_width,
      screen_height: screen_height,
      x_min: x_min,
      x_max: x_max,
      y_min: y_min,
      y_max: y_max
    }

    schedule_poll(state)
    {:ok, state}
  end

  @impl true
  def handle_info(:poll, state) do
    state = read_touch(state)
    schedule_poll(state)
    {:noreply, state}
  end

  ## Internal helpers

  defp schedule_poll(%State{poll_interval_ms: interval}) do
    Process.send_after(self(), :poll, interval)
  end

  defp read_touch(%State{irq: irq, spi: spi} = state) do
    case Circuits.GPIO.read(irq) do
      # アクティブ Low: 0 のときタッチ中
      0 ->
        raw_x = read_axis(spi, 0x90)
        raw_y = read_axis(spi, 0xD0)

        # 出力が 90 度回転している前提で、X/Y を入れ替えつつスケーリング
        x =
          scale(
            state.y_max - raw_y,
            0,
            state.y_max - state.y_min,
            state.screen_width
          )

        y =
          scale(
            state.x_max - raw_x,
            0,
            state.x_max - state.x_min,
            state.screen_height
          )

        Logger.debug("XPT2046 touch: X=#{x}, Y=#{y}")
        send(state.ui_pid, {:touch, x, y})
        state

      _ ->
        state
    end
  end

  defp read_axis(spi, command) do
    <<_, h, l>> = Circuits.SPI.transfer!(spi, <<command, 0x00, 0x00>>)
    (h <<< 8 ||| l) >>> 3
  end

  defp scale(raw, raw_min, raw_max, size) do
    raw = max(min(raw, raw_max), raw_min)

    if raw_max == raw_min do
      0
    else
      trunc((raw - raw_min) * size / (raw_max - raw_min))
    end
  end
end

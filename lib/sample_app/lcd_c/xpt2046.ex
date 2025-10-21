defmodule SampleApp.LcdC.XPT2046 do
  use GenServer
  import Bitwise
  require Logger
  alias SampleApp.LcdB.UI

  # タッチ検出割込みピン（Lowでタッチ）
  @irq_pin 17
  # タッチパネル用 SPI デバイス
  @spi_bus "spidev0.1"

  # キャリブレーション用の最小・最大（経験的に求めた値）
  @x_min 149
  @x_max 3845
  @y_min 294
  @y_max 3831

  @screen_width 320
  @screen_height 480

  def start_link(_args \\ []) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(_) do
    {:ok, irq} = Circuits.GPIO.open(@irq_pin, :input)
    {:ok, spi} = Circuits.SPI.open(@spi_bus)

    Logger.info("XPT2046 初期化完了")

    state = %{
      irq: irq,
      spi: spi
    }

    schedule_poll()
    {:ok, state}
  end

  @impl true
  def handle_info(:poll, %{irq: irq, spi: spi} = state) do
    read_touch(irq, spi)
    schedule_poll()
    {:noreply, state}
  end

  defp schedule_poll do
    Process.send_after(self(), :poll, 100)
  end

  defp read_touch(irq, spi) do
    case Circuits.GPIO.read(irq) do
      # タッチされている
      0 ->
        # X軸コマンド
        raw_x = read_axis(spi, 0x90)
        # Y軸コマンド
        raw_y = read_axis(spi, 0xD0)

        # XPT2046の出力が90度回転している前提で、X/Yを入れ替え + スケーリング
        x = scale(@y_max - raw_y, 0, @y_max - @y_min, @screen_width)
        y = scale(@x_max - raw_x, 0, @x_max - @x_min, @screen_height)

        Logger.info("Touch: X=#{x}, Y=#{y}")
        # ⭐ UI にメッセージ送信
        send(UI, {:touch, x, y})

      _ ->
        :ok
    end
  end

  defp read_axis(spi, command) do
    <<_, h, l>> = Circuits.SPI.transfer!(spi, <<command, 0x00, 0x00>>)
    (h <<< 8 ||| l) >>> 3
  end

  defp scale(raw, raw_min, raw_max, screen_size) do
    raw = max(min(raw, raw_max), raw_min)
    trunc((raw - raw_min) * screen_size / (raw_max - raw_min))
  end
end

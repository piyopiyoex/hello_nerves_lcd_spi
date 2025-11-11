defmodule SampleApp.Touch.XPT2046 do
  import Bitwise
  use GenServer
  require Logger

  @moduledoc """
  XPT2046 タッチコントローラ用の GenServer。

  オプション:
    * `:ui` — タッチイベントの送信先となる UI プロセス。`pid` または登録名を指定。

  挙動:
    * タッチを検出すると、`{:touch, x, y}` を `:ui` で指定したプロセスへ送信する。
    * `:ui` が未起動または不正な場合は `ArgumentError` を送出する。
  """

  # タッチ検出割り込みピン（Low でタッチ）
  @irq_pin 17
  # タッチパネル用 SPI デバイス
  @spi_bus "spidev0.1"

  # キャリブレーション用の最小・最大（経験則）
  @x_min 149
  @x_max 3845
  @y_min 294
  @y_max 3831

  # 画面サイズ（ピクセル）
  @screen_width 320
  @screen_height 480

  @doc """
  ドライバを起動する。`ui:` オプションは必須（`pid` または登録名）。
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    ui =
      case Keyword.get(opts, :ui) do
        pid when is_pid(pid) ->
          pid

        name when is_atom(name) ->
          case Process.whereis(name) do
            nil -> raise ArgumentError, "UI プロセス #{inspect(name)} が起動していません"
            pid -> pid
          end

        other ->
          raise ArgumentError,
                ":ui オプションが不正です。`pid` または登録名（atom）を指定してください: #{inspect(other)}"
      end

    {:ok, irq} = Circuits.GPIO.open(@irq_pin, :input)
    {:ok, spi} = Circuits.SPI.open(@spi_bus)

    Logger.info("XPT2046 の初期化が完了しました")

    state = %{
      irq: irq,
      spi: spi,
      ui: ui
    }

    # 定期読み取りを開始
    schedule_poll()
    {:ok, state}
  end

  @impl true
  def handle_info(:poll, %{irq: irq, spi: spi, ui: ui} = state) do
    read_touch(irq, spi, ui)
    schedule_poll()
    {:noreply, state}
  end

  # 読み取り間隔（ミリ秒）
  defp schedule_poll do
    Process.send_after(self(), :poll, 100)
  end

  # タッチ状態を読み取り、必要に応じて UI へ通知
  defp read_touch(irq, spi, ui) do
    case Circuits.GPIO.read(irq) do
      # 0（Low）でタッチ中
      0 ->
        # X 軸の生データ
        raw_x = read_axis(spi, 0x90)
        # Y 軸の生データ
        raw_y = read_axis(spi, 0xD0)

        # 90 度回転している前提で X/Y を入れ替え + スケーリング
        x = scale(@y_max - raw_y, 0, @y_max - @y_min, @screen_width)
        y = scale(@x_max - raw_x, 0, @x_max - @x_min, @screen_height)

        Logger.info("Touch: X=#{x}, Y=#{y}")

        # UI へ通知（`pid`／登録名どちらでも可）
        if ui do
          send(ui, {:touch, x, y})
        end

      _ ->
        :ok
    end
  end

  # 指定軸の 12bit 生データを取得
  defp read_axis(spi, command) do
    <<_, h, l>> = Circuits.SPI.transfer!(spi, <<command, 0x00, 0x00>>)
    (h <<< 8 ||| l) >>> 3
  end

  # 生データを画面座標へスケール
  defp scale(raw, raw_min, raw_max, screen_size) do
    raw = max(min(raw, raw_max), raw_min)
    trunc((raw - raw_min) * screen_size / (raw_max - raw_min))
  end
end

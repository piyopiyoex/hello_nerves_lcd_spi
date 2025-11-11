defmodule SampleApp.Touch.GT911 do
  @moduledoc """
  GT911 用のポーリング型タッチドライバ。

  一定間隔で I2C からタッチ情報を読み取り、タッチがあれば
  UI プロセスに `{:touch, x, y}` を送信する。
  """

  use GenServer
  import Bitwise
  require Logger

  defmodule State do
    @enforce_keys [:ui_pid, :i2c]
    defstruct ui_pid: nil,
              i2c: nil,
              i2c_addr: 0x14,
              max_x: 0,
              max_y: 0,
              screen_width: 480,
              screen_height: 320,
              poll_interval_ms: 50
  end

  @default_i2c_addr 0x14
  @default_i2c_bus "i2c-1"
  @default_int_pin 4
  @default_rst_pin 17
  @default_poll_interval_ms 50

  ## Public API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  ## GenServer callbacks

  @impl true
  def init(opts) do
    ui_pid = Keyword.fetch!(opts, :ui_pid)

    i2c_bus = Keyword.get(opts, :i2c_bus, @default_i2c_bus)
    i2c_addr = Keyword.get(opts, :i2c_addr, @default_i2c_addr)
    int_pin = Keyword.get(opts, :int_pin, @default_int_pin)
    rst_pin = Keyword.get(opts, :rst_pin, @default_rst_pin)
    poll_interval_ms = Keyword.get(opts, :poll_interval_ms, @default_poll_interval_ms)

    screen_width = Keyword.fetch!(opts, :screen_width)
    screen_height = Keyword.fetch!(opts, :screen_height)

    {:ok, i2c} = Circuits.I2C.open(i2c_bus)
    {:ok, rst} = Circuits.GPIO.open(rst_pin, :output)
    {:ok, int} = Circuits.GPIO.open(int_pin, :output)

    Logger.info("GT911 初期化中... (i2c_bus=#{i2c_bus}, addr=0x#{Integer.to_string(i2c_addr, 16)})")

    # リセットシーケンス（元コードを簡略化）
    Circuits.GPIO.write(int, 0)
    Circuits.GPIO.write(rst, 0)
    Process.sleep(10)

    Circuits.GPIO.write(rst, 1)
    Process.sleep(50)

    # INT ピンを解放
    :ok = Circuits.GPIO.close(int)
    :ok = Circuits.GPIO.close(rst)
    Process.sleep(50)

    # 製品 ID 読み出し
    pid = read_reg16(i2c, i2c_addr, 0x8140, 4)
    product_id = pid |> Enum.map(&<<&1::utf8>>) |> Enum.join()
    Logger.info("GT911 Product ID: #{product_id}")

    # 最大座標読み出し
    [x_low, x_high, y_low, y_high] = read_reg16(i2c, i2c_addr, 0x8048, 4)
    max_x = x_high <<< 8 ||| x_low
    max_y = y_high <<< 8 ||| y_low

    Logger.info("GT911 最大X: #{max_x}, 最大Y: #{max_y}")

    enable_touch_reporting(i2c, i2c_addr)

    state = %State{
      ui_pid: ui_pid,
      i2c: i2c,
      i2c_addr: i2c_addr,
      max_x: max_x,
      max_y: max_y,
      screen_width: screen_width,
      screen_height: screen_height,
      poll_interval_ms: poll_interval_ms
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

  defp read_touch(%State{i2c: i2c, i2c_addr: addr} = state) do
    case read_reg16(i2c, addr, 0x814E, 1) do
      [status] when (status &&& 0x80) != 0 ->
        num_points = status &&& 0x0F

        if num_points > 0 do
          buf = read_reg16(i2c, addr, 0x8150, num_points * 8)

          for i <- 0..(num_points - 1) do
            base = i * 8

            raw_x =
              (Enum.at(buf, base) || 0) |||
                (Enum.at(buf, base + 1) || 0) <<< 8

            raw_y =
              (Enum.at(buf, base + 2) || 0) |||
                (Enum.at(buf, base + 3) || 0) <<< 8

            tid = Enum.at(buf, base + 4) || 0

            # ミラーリングして画面座標にスケーリング
            x =
              scale(
                state.max_x - raw_x,
                0,
                state.max_x,
                state.screen_width
              )

            y =
              scale(
                state.max_y - raw_y,
                0,
                state.max_y,
                state.screen_height
              )

            Logger.debug("GT911 touch #{i}: ID=#{tid} X=#{x}, Y=#{y}")
            send(state.ui_pid, {:touch, x, y})
          end
        end

        safe_clear_status(i2c, addr)
        state

      _ ->
        state
    end
  end

  defp enable_touch_reporting(i2c, addr) do
    case write_reg16(i2c, addr, 0x8040, [0x01]) do
      :ok ->
        Logger.info("GT911: タッチ報告を有効化しました")

      {:error, reason} ->
        Logger.error("[GT911] タッチ有効化失敗: #{inspect(reason)}")
    end
  end

  defp safe_clear_status(i2c, addr) do
    case write_reg16(i2c, addr, 0x814E, [0x00]) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning("[GT911] ステータスクリア失敗: #{inspect(reason)}")
    end
  end

  defp read_reg16(i2c, addr, reg, len) do
    high = reg >>> 8 &&& 0xFF
    low = reg &&& 0xFF

    with :ok <- Circuits.I2C.write(i2c, addr, <<high, low>>),
         {:ok, data} <- Circuits.I2C.read(i2c, addr, len) do
      :binary.bin_to_list(data)
    else
      _ -> []
    end
  end

  defp write_reg16(i2c, addr, reg, values) do
    high = reg >>> 8 &&& 0xFF
    low = reg &&& 0xFF
    data = <<high, low>> <> :binary.list_to_bin(values)

    Circuits.I2C.write(i2c, addr, data)
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

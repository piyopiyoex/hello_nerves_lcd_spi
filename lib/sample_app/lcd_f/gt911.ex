defmodule SampleApp.LcdF.GT911 do
  import Bitwise
  use GenServer
  require Logger

  @i2c_addr 0x14
  @i2c_bus "i2c-1"
  @int_pin 4
  @rst_pin 17

  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(_) do
    {:ok, i2c} = Circuits.I2C.open(@i2c_bus)

    {:ok, rst} = Circuits.GPIO.open(@rst_pin, :output)
    {:ok, int} = Circuits.GPIO.open(@int_pin, :output)

    # 初期化シーケンス
    Logger.info("GT911 初期化中...")

    Circuits.GPIO.write(int, 0)
    Circuits.GPIO.write(rst, 0)
    Process.sleep(10)

    Circuits.GPIO.write(rst, 1)
    Process.sleep(50)

    # INTピンを入力に戻す
    :ok = Circuits.GPIO.close(int)
    Process.sleep(50)

    pid = read_reg16(i2c, 0x8140, 4)
    Logger.info("GT911 Product ID: #{Enum.map(pid, &<<&1::utf8>>) |> Enum.join()}")

    [x_low, x_high, y_low, y_high] = read_reg16(i2c, 0x8048, 4)
    max_x = x_high <<< 8 ||| x_low
    max_y = y_high <<< 8 ||| y_low

    Logger.info("GT911 最大X: #{max_x}, 最大Y: #{max_y}")

    enable_touch_reporting(i2c)

    state = %{
      i2c: i2c,
      max_x: max_x,
      max_y: max_y
    }

    # 定期読み取りタイマー
    schedule_poll()
    {:ok, state}
  end

  def handle_info(:poll, state) do
    read_touch(state)
    schedule_poll()
    {:noreply, state}
  end

  defp schedule_poll do
    Process.send_after(self(), :poll, 50)
  end

  defp read_touch(%{i2c: i2c, max_x: max_x, max_y: max_y} = _state) do
    case read_reg16(i2c, 0x814E, 1) do
      [status] when (status &&& 0x80) != 0 ->
        num_points = status &&& 0x0F

        if num_points > 0 do
          buf = read_reg16(i2c, 0x8150, num_points * 8)

          for i <- 0..(num_points - 1) do
            base = i * 8
            raw_x = Enum.at(buf, base) ||| Enum.at(buf, base + 1) <<< 8
            raw_y = Enum.at(buf, base + 2) ||| Enum.at(buf, base + 3) <<< 8
            tid = Enum.at(buf, base + 4)
            x = max_x - raw_x
            y = max_y - raw_y

            Logger.info("Touch #{i}: ID=#{tid} X=#{x} Y=#{y}")

            # ⭐ UI にメッセージ送信
            send(SampleApp.LcdF.UI, {:touch, x, y})
          end
        end

        safe_clear_status(i2c)

      _ ->
        :ok
    end
  end

  defp enable_touch_reporting(i2c) do
    case write_reg16(i2c, 0x8040, [0x01]) do
      :ok -> Logger.info("タッチ報告を有効化しました")
      {:error, reason} -> Logger.error("[ERROR] タッチ有効化失敗: #{inspect(reason)}")
    end
  end

  defp safe_clear_status(i2c) do
    case write_reg16(i2c, 0x814E, [0x00]) do
      :ok -> :ok
      {:error, reason} -> Logger.warning("[警告] ステータスクリア失敗: #{inspect(reason)}")
    end
  end

  defp read_reg16(i2c, addr, len) do
    high = addr >>> 8 &&& 0xFF
    low = addr &&& 0xFF

    with :ok <- Circuits.I2C.write(i2c, @i2c_addr, <<high, low>>),
         {:ok, data} <- Circuits.I2C.read(i2c, @i2c_addr, len) do
      :binary.bin_to_list(data)
    else
      _ -> []
    end
  end

  defp write_reg16(i2c, addr, values) do
    high = addr >>> 8 &&& 0xFF
    low = addr &&& 0xFF
    data = <<high, low>> <> :binary.list_to_bin(values)

    Circuits.I2C.write(i2c, @i2c_addr, data)
  end
end

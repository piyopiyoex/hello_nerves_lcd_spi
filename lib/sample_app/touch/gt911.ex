defmodule SampleApp.Touch.GT911 do
  import Bitwise
  use GenServer
  require Logger

  @moduledoc """
  GT911 タッチコントローラ用の GenServer。

  オプション:
    * `:ui` — タッチイベントの送信先となる UI プロセス。`pid` または登録名を指定。

  挙動:
    * タッチを検出すると、`{:touch, x, y}` を `:ui` で指定したプロセスへ送信する。
    * `:ui` が未起動または不正な場合は `ArgumentError` を送出する。
  """

  @i2c_addr 0x14
  @i2c_bus "i2c-1"
  @int_pin 4
  @rst_pin 17

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

    {:ok, i2c} = Circuits.I2C.open(@i2c_bus)

    {:ok, rst} = Circuits.GPIO.open(@rst_pin, :output)
    {:ok, int} = Circuits.GPIO.open(@int_pin, :output)

    # 初期化シーケンス
    Logger.info("GT911 を初期化しています…")

    Circuits.GPIO.write(int, 0)
    Circuits.GPIO.write(rst, 0)
    Process.sleep(10)

    Circuits.GPIO.write(rst, 1)
    Process.sleep(50)

    # INT ピンを入力に戻す
    :ok = Circuits.GPIO.close(int)
    Process.sleep(50)

    pid =
      read_reg16(i2c, 0x8140, 4)
      |> Enum.map(&<<&1::utf8>>)
      |> Enum.join()

    Logger.info("GT911 Product ID: #{pid}")

    [x_low, x_high, y_low, y_high] = read_reg16(i2c, 0x8048, 4)
    max_x = x_high <<< 8 ||| x_low
    max_y = y_high <<< 8 ||| y_low

    Logger.info("GT911 最大 X: #{max_x}, 最大 Y: #{max_y}")

    enable_touch_reporting(i2c)

    state = %{
      i2c: i2c,
      max_x: max_x,
      max_y: max_y,
      ui: ui
    }

    # 定期読み取りを開始
    schedule_poll()
    {:ok, state}
  end

  @impl true
  def handle_info(:poll, state) do
    read_touch(state)
    schedule_poll()
    {:noreply, state}
  end

  # 読み取り間隔（ミリ秒）
  defp schedule_poll, do: Process.send_after(self(), :poll, 50)

  # タッチ座標を読み取り、必要に応じて UI へ通知
  defp read_touch(%{i2c: i2c, max_x: max_x, max_y: max_y, ui: ui}) do
    case read_reg16(i2c, 0x814E, 1) do
      # 0x80 ビットが立っていれば座標データが準備済み
      [status] when (status &&& 0x80) != 0 ->
        num_points = status &&& 0x0F

        if num_points > 0 do
          # 1 点あたり 8 バイト
          buf = read_reg16(i2c, 0x8150, num_points * 8)

          for i <- 0..(num_points - 1) do
            base = i * 8
            raw_x = Enum.at(buf, base) ||| Enum.at(buf, base + 1) <<< 8
            raw_y = Enum.at(buf, base + 2) ||| Enum.at(buf, base + 3) <<< 8
            tid = Enum.at(buf, base + 4)

            # 画面座標への補正（左右・上下反転を想定）
            x = max_x - raw_x
            y = max_y - raw_y

            Logger.info("Touch #{i}: ID=#{tid} X=#{x} Y=#{y}")

            # UI へ通知（`pid`／登録名どちらでも可）
            if ui, do: send(ui, {:touch, x, y})
          end
        end

        # ステータスをクリアして次回に備える
        safe_clear_status(i2c)

      _ ->
        :ok
    end
  end

  # タッチ報告を有効化
  defp enable_touch_reporting(i2c) do
    case write_reg16(i2c, 0x8040, [0x01]) do
      :ok -> Logger.info("タッチ報告を有効化しました")
      {:error, reason} -> Logger.error("タッチ報告の有効化に失敗しました: #{inspect(reason)}")
    end
  end

  # ステータスレジスタをクリア
  defp safe_clear_status(i2c) do
    case write_reg16(i2c, 0x814E, [0x00]) do
      :ok -> :ok
      {:error, reason} -> Logger.warning("ステータスのクリアに失敗しました: #{inspect(reason)}")
    end
  end

  # 16bit アドレスのレジスタを読み込み
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

  # 16bit アドレスのレジスタへ書き込み
  defp write_reg16(i2c, addr, values) do
    high = addr >>> 8 &&& 0xFF
    low = addr &&& 0xFF
    data = <<high, low>> <> :binary.list_to_bin(values)

    Circuits.I2C.write(i2c, @i2c_addr, data)
  end
end

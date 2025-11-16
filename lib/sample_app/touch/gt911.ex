defmodule SampleApp.Touch.GT911 do
  import Bitwise
  use GenServer
  require Logger

  @moduledoc """
  GT911 タッチコントローラ用の GenServer。
  """

  @i2c_addr 0x14
  @i2c_bus "i2c-1"
  @int_pin 4
  @rst_pin 17

  @fallback_max_x 800
  @fallback_max_y 480

  @doc """
  ドライバを起動する。`ui:` オプションは必須（`pid` または登録名）。
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    ui = Keyword.get(opts, :ui)

    unless is_pid(ui) or is_atom(ui) do
      raise ArgumentError,
            ":ui オプションが不正です。`pid` または登録名（atom）を指定してください: #{inspect(ui)}"
    end

    {:ok, i2c} = Circuits.I2C.open(@i2c_bus)
    {:ok, rst} = Circuits.GPIO.open(@rst_pin, :output)
    {:ok, int} = Circuits.GPIO.open(@int_pin, :output)

    Logger.info("GT911 初期化中...")

    Circuits.GPIO.write(int, 0)
    Circuits.GPIO.write(rst, 0)
    Process.sleep(10)

    Circuits.GPIO.write(rst, 1)
    Process.sleep(50)

    # INT ピンを入力に戻す
    :ok = Circuits.GPIO.close(int)
    Process.sleep(50)

    # Product ID（失敗時は空文字列）
    pid_bytes = read_reg16(i2c, 0x8140, 4)

    product_id =
      pid_bytes
      |> Enum.map(&<<&1::utf8>>)
      |> Enum.join()

    Logger.info("GT911 Product ID: #{product_id}")

    {max_x, max_y} =
      case read_reg16(i2c, 0x8048, 4) do
        [x_low, x_high, y_low, y_high] ->
          {
            x_high <<< 8 ||| x_low,
            y_high <<< 8 ||| y_low
          }

        other ->
          Logger.warning("GT911 解像度レジスタ(0x8048)の読み取りに失敗したためフォールバック値を使用します: #{inspect(other)}")

          {@fallback_max_x, @fallback_max_y}
      end

    Logger.info("GT911 最大X: #{max_x}, 最大Y: #{max_y}")

    enable_touch_reporting(i2c)

    state = %{
      i2c: i2c,
      max_x: max_x,
      max_y: max_y,
      ui: ui
    }

    # 定期読み取りタイマー
    schedule_poll()
    {:ok, state}
  end

  @impl true
  def handle_info(:poll, state) do
    read_touch(state)
    schedule_poll()
    {:noreply, state}
  end

  defp schedule_poll do
    Process.send_after(self(), :poll, 50)
  end

  # タッチ座標読み取り
  defp read_touch(%{i2c: i2c, max_x: max_x, max_y: max_y, ui: ui}) do
    case read_reg16(i2c, 0x814E, 1) do
      # 0x80 ビットが立っていれば座標データが準備済み
      [status] when (status &&& 0x80) != 0 ->
        num_points = status &&& 0x0F

        if num_points > 0 do
          # 1点あたり8バイト
          buf = read_reg16(i2c, 0x8150, num_points * 8)

          for i <- 0..(num_points - 1) do
            base = i * 8

            case Enum.slice(buf, base, 8) do
              [x_low, x_high, y_low, y_high, tid | _rest] ->
                # 旧実装と同じ endian
                raw_x = x_low ||| x_high <<< 8
                raw_y = y_low ||| y_high <<< 8

                # 画面座標への補正（左右・上下反転を想定）
                x = max_x - raw_x
                y = max_y - raw_y

                Logger.info("Touch #{i}: ID=#{tid} X=#{x} Y=#{y}")

                if ui do
                  send(ui, {:touch, x, y})
                end

              other ->
                Logger.warning("GT911 タッチ座標読み取りに失敗しました: #{inspect(other)}")
            end
          end
        end

        # ステータスをクリア
        safe_clear_status(i2c)

      _ ->
        :ok
    end
  end

  # タッチ報告を有効化
  defp enable_touch_reporting(i2c) do
    case write_reg16(i2c, 0x8040, [0x01]) do
      :ok ->
        Logger.info("タッチ報告を有効化しました")

      {:error, reason} ->
        # ここだけは一度は知りたいのでログを出す
        Logger.error("[ERROR] タッチ有効化失敗: #{inspect(reason)}")
    end
  end

  # ステータスレジスタをクリア
  defp safe_clear_status(i2c) do
    case write_reg16(i2c, 0x814E, [0x00]) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning("[警告] ステータスクリア失敗: #{inspect(reason)}")
    end
  end

  # 16bit アドレスのレジスタを読み込み
  # 旧実装と同じく、エラー時はログを出さずに `[]` を返す。
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

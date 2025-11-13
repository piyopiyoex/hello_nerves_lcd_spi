defmodule SampleApp.LcdG.ST7796S do
  @moduledoc """
  LCD制御モジュール (ST7796S 320x480用)
  """

  import Bitwise
  alias SampleApp.Font5x7

  @width 320
  @height 480

  # コマンド送信 (DC = 0)
  def send_cmd(spi, dc, cmd) when is_integer(cmd) do
    Circuits.GPIO.write(dc, 0)
    Circuits.SPI.transfer(spi, <<cmd>>)
  end

  # データ送信（整数）
  def send_data(spi, dc, data) when is_integer(data) do
    Circuits.GPIO.write(dc, 1)
    Circuits.SPI.transfer(spi, <<data>>)
  end

  # データ送信（バイナリ）
  def send_data(spi, dc, data) when is_binary(data) do
    Circuits.GPIO.write(dc, 1)
    Circuits.SPI.transfer(spi, data)
  end

  # LCDリセット
  def reset(rst) do
    Circuits.GPIO.write(rst, 1)
    :timer.sleep(50)
    Circuits.GPIO.write(rst, 0)
    :timer.sleep(50)
    Circuits.GPIO.write(rst, 1)
    :timer.sleep(150)
  end

  def init(spi, dc, rst) do
    reset(rst)
    send_cmd(spi, dc, 0x11)
    :timer.sleep(120)

    # Memory Data Access Control MY,MX~~
    send_cmd(spi, dc, 0x36)
    send_data(spi, dc, <<0x88>>)

    send_cmd(spi, dc, 0x3A)
    # send_data(spi, dc, <<0x66)
    send_data(spi, dc, <<0x05>>)

    # Command Set Control
    send_cmd(spi, dc, 0xF0)
    send_data(spi, dc, <<0xC3>>)

    send_cmd(spi, dc, 0xF0)
    send_data(spi, dc, <<0x96>>)

    send_cmd(spi, dc, 0xB4)
    send_data(spi, dc, <<0x01>>)

    send_cmd(spi, dc, 0xB7)
    send_data(spi, dc, <<0xC6>>)

    send_cmd(spi, dc, 0xC0)
    send_data(spi, dc, <<0x80>>)
    send_data(spi, dc, <<0x45>>)

    send_cmd(spi, dc, 0xC1)
    # 18  #00
    send_data(spi, dc, <<0x13>>)

    send_cmd(spi, dc, 0xC2)
    send_data(spi, dc, <<0xA7>>)

    send_cmd(spi, dc, 0xC5)
    send_data(spi, dc, <<0x0A>>)

    send_cmd(spi, dc, 0xE8)
    send_data(spi, dc, <<0x40>>)
    send_data(spi, dc, <<0x8A>>)
    send_data(spi, dc, <<0x00>>)
    send_data(spi, dc, <<0x00>>)
    send_data(spi, dc, <<0x29>>)
    send_data(spi, dc, <<0x19>>)
    send_data(spi, dc, <<0xA5>>)
    send_data(spi, dc, <<0x33>>)

    send_cmd(spi, dc, 0xE0)
    send_data(spi, dc, <<0xD0>>)
    send_data(spi, dc, <<0x08>>)
    send_data(spi, dc, <<0x0F>>)
    send_data(spi, dc, <<0x06>>)
    send_data(spi, dc, <<0x06>>)
    send_data(spi, dc, <<0x33>>)
    send_data(spi, dc, <<0x30>>)
    send_data(spi, dc, <<0x33>>)
    send_data(spi, dc, <<0x47>>)
    send_data(spi, dc, <<0x17>>)
    send_data(spi, dc, <<0x13>>)
    send_data(spi, dc, <<0x13>>)
    send_data(spi, dc, <<0x2B>>)
    send_data(spi, dc, <<0x31>>)

    send_cmd(spi, dc, 0xE1)
    send_data(spi, dc, <<0xD0>>)
    send_data(spi, dc, <<0x0A>>)
    send_data(spi, dc, <<0x11>>)
    send_data(spi, dc, <<0x0B>>)
    send_data(spi, dc, <<0x09>>)
    send_data(spi, dc, <<0x07>>)
    send_data(spi, dc, <<0x2F>>)
    send_data(spi, dc, <<0x33>>)
    send_data(spi, dc, <<0x47>>)
    send_data(spi, dc, <<0x38>>)
    send_data(spi, dc, <<0x15>>)
    send_data(spi, dc, <<0x16>>)
    send_data(spi, dc, <<0x2C>>)
    send_data(spi, dc, <<0x32>>)

    send_cmd(spi, dc, 0xF0)
    send_data(spi, dc, <<0x3C>>)

    send_cmd(spi, dc, 0xF0)
    send_data(spi, dc, <<0x69>>)

    send_cmd(spi, dc, 0x21)

    send_cmd(spi, dc, 0x11)

    :timer.sleep(100)

    send_cmd(spi, dc, 0x29)
    # ✅ 戻り値を明示する
    :ok
  end

  def set_address_window(spi, dc, x0, y0, x1, y1) do
    send_cmd(spi, dc, 0x2A)

    for byte <- [x0 >>> 8, x0 &&& 0xFF, x1 >>> 8, x1 &&& 0xFF] do
      send_data(spi, dc, <<byte>>)
    end

    send_cmd(spi, dc, 0x2B)

    for byte <- [y0 >>> 8, y0 &&& 0xFF, y1 >>> 8, y1 &&& 0xFF] do
      send_data(spi, dc, <<byte>>)
    end

    send_cmd(spi, dc, 0x2C)
  end

  def fill_rect(spi, dc, x, y, w, h, color) do
    x1 = x + w - 1
    y1 = y + h - 1

    # Column address set
    send_cmd(spi, dc, 0x2A)

    for byte <- [x >>> 8, x &&& 0xFF, x1 >>> 8, x1 &&& 0xFF] do
      send_data(spi, dc, <<byte>>)
    end

    # Page address set
    send_cmd(spi, dc, 0x2B)

    for byte <- [y >>> 8, y &&& 0xFF, y1 >>> 8, y1 &&& 0xFF] do
      send_data(spi, dc, <<byte>>)
    end

    # Memory write
    send_cmd(spi, dc, 0x2C)

    pixel_data = <<color >>> 8, color &&& 0xFF>>
    total_pixels = w * h
    max_chunk_bytes = 2048
    max_chunk_pixels = div(max_chunk_bytes, 2)

    fill_chunk = fn fill_chunk, remaining ->
      if remaining > 0 do
        chunk_pixels = min(remaining, max_chunk_pixels)
        data = :binary.copy(pixel_data, chunk_pixels)

        case send_data(spi, dc, data) do
          {:ok, _} -> fill_chunk.(fill_chunk, remaining - chunk_pixels)
          {:error, reason} -> {:error, reason}
        end
      else
        :ok
      end
    end

    fill_chunk.(fill_chunk, total_pixels)
  end

  def draw_pixel(spi, dc, x, y, color) do
    # Column address set
    send_cmd(spi, dc, 0x2A)

    for byte <- [x >>> 8, x &&& 0xFF, x >>> 8, x &&& 0xFF] do
      send_data(spi, dc, <<byte>>)
    end

    # Page address set
    send_cmd(spi, dc, 0x2B)

    for byte <- [y >>> 8, y &&& 0xFF, y >>> 8, y &&& 0xFF] do
      send_data(spi, dc, <<byte>>)
    end

    # Memory write
    send_cmd(spi, dc, 0x2C)
    send_data(spi, dc, <<color >>> 8, color &&& 0xFF>>)
  end

  def set_window(spi, dc, x1, y1, x2, y2) do
    send_cmd(spi, dc, 0x2A)
    send_data(spi, dc, <<0x00, x1, 0x00, x2>>)

    send_cmd(spi, dc, 0x2B)
    send_data(spi, dc, <<0x00, y1, 0x00, y2>>)
  end

  def draw_rect(spi, dc, x, y, w, h, color \\ <<0xF8, 0x00>>) do
    x2 = x + w - 1
    y2 = y + h - 1

    send_cmd(spi, dc, 0x2A)
    send_data(spi, dc, <<x::16, x2::16>>)

    send_cmd(spi, dc, 0x2B)
    send_data(spi, dc, <<y::16, y2::16>>)

    send_cmd(spi, dc, 0x2C)

    pixel_count = w * h
    payload = :binary.copy(color, pixel_count)

    # 分割送信（最大2048B制限を考慮）
    chunk_size = 2048

    Enum.chunk_every(:binary.bin_to_list(payload), chunk_size)
    |> Enum.each(fn chunk ->
      send_data(spi, dc, :binary.list_to_bin(chunk))
    end)
  end

  def load_image_path() do
    priv_path = :code.priv_dir(:sample_app) |> to_string()
    Path.join(priv_path, "image.rgb565")
  end

  # ビットマップ表示（RGB565形式）
  def display_bitmap(spi, dc, path) do
    case File.read(path) do
      {:ok, data} ->
        expected_size = @width * @height * 2

        if byte_size(data) != expected_size do
          IO.puts("画像サイズが不正です: #{byte_size(data)}バイト（期待: #{expected_size}）")
        else
          set_address_window(spi, dc, 0, 0, @width - 1, @height - 1)
          transfer_bitmap(spi, dc, data)
        end

      {:error, reason} ->
        IO.puts("画像ファイルの読み込みに失敗: #{reason}")
    end
  end

  defp transfer_bitmap(spi, dc, data) do
    Circuits.GPIO.write(dc, 1)
    chunk_size = 2048

    0..(byte_size(data) - 1)//chunk_size
    |> Enum.each(fn offset ->
      chunk = binary_part(data, offset, min(chunk_size, byte_size(data) - offset))
      Circuits.SPI.transfer(spi, chunk)
    end)
  end

  def load_rgb565_to_buffer(path) do
    case File.read(path) do
      {:ok, data} ->
        expected_size = 320 * 480 * 2

        if byte_size(data) == expected_size do
          data
        else
          raise "サイズが不正です: #{byte_size(data)}バイト (期待: #{expected_size})"
        end

      {:error, reason} ->
        raise "画像読み込みエラー: #{reason}"
    end
  end

  def flush_to_lcd(spi, dc, buffer) do
    set_address_window(spi, dc, 0, 0, 319, 479)
    Circuits.GPIO.write(dc, 1)

    chunk_size = 2048

    0..(byte_size(buffer) - 1)//chunk_size
    |> Enum.each(fn offset ->
      chunk = binary_part(buffer, offset, min(chunk_size, byte_size(buffer) - offset))
      Circuits.SPI.transfer(spi, chunk)
    end)
  end

  def build_sprite(text, fg, bg, scale) do
    width = String.length(text) * (5 + 1) * scale
    height = 7 * scale
    buffer_size = width * height * 2

    fg_bytes = <<fg >>> 8, fg &&& 0xFF>>
    bg_bytes = <<bg >>> 8, bg &&& 0xFF>>

    # 背景色でバッファを塗りつぶして初期化
    pixels = :binary.copy(bg_bytes, div(buffer_size, 2))

    # 文字列を描画
    buffer =
      text
      |> String.to_charlist()
      |> Enum.with_index()
      |> Enum.reduce(pixels, fn {char, ci}, acc_buffer ->
        case Font5x7.get(char) do
          nil ->
            IO.puts("文字 '#{<<char>>}' はフォントに未定義です。")
            acc_buffer

          bitmap ->
            Enum.with_index(bitmap)
            |> Enum.reduce(acc_buffer, fn {row, dy}, buf1 ->
              Enum.reduce(0..4, buf1, fn dx, buf2 ->
                if (row &&& 1 <<< (4 - dx)) != 0 do
                  draw_scaled_pixel(
                    buf2,
                    width,
                    (ci * (5 + 1) + dx) * scale,
                    dy * scale,
                    fg_bytes,
                    scale
                  )
                else
                  buf2
                end
              end)
            end)
        end
      end)

    %{
      text: text,
      fg: fg,
      bg: bg,
      w: width,
      h: height,
      pixels: buffer
    }
  end

  def push_sprite(spi, dc, lcd_x, lcd_y, %{w: w, h: h, pixels: pixels}) do
    x1 = min(lcd_x + w - 1, 319)
    y1 = min(lcd_y + h - 1, 479)

    # Column address set (0x2A)
    send_cmd(spi, dc, 0x2A)

    for byte <- [lcd_x >>> 8, lcd_x &&& 0xFF, x1 >>> 8, x1 &&& 0xFF] do
      send_data(spi, dc, <<byte>>)
    end

    # Page address set (0x2B)
    send_cmd(spi, dc, 0x2B)

    for byte <- [lcd_y >>> 8, lcd_y &&& 0xFF, y1 >>> 8, y1 &&& 0xFF] do
      send_data(spi, dc, <<byte>>)
    end

    # Memory write (0x2C)
    send_cmd(spi, dc, 0x2C)

    # 分割送信 (2048バイトずつ)
    max_chunk_bytes = 2048

    send_chunks = fn send_chunks, bin ->
      case bin do
        <<chunk::binary-size(max_chunk_bytes), rest::binary>> ->
          case send_data(spi, dc, chunk) do
            {:ok, _} -> send_chunks.(send_chunks, rest)
            {:error, reason} -> {:error, reason}
          end

        <<last::binary>> ->
          send_data(spi, dc, last)
      end
    end

    send_chunks.(send_chunks, pixels)
  end

  defp draw_scaled_pixel(buffer, image_width, x, y, color_bytes, scale) do
    <<_::binary>> = buffer

    for dy <- 0..(scale - 1),
        dx <- 0..(scale - 1),
        reduce: buffer do
      acc ->
        col = x + dx
        row = y + dy
        offset = (row * image_width + col) * 2

        # 直接バイナリを更新
        :binary.part(acc, 0, offset) <>
          color_bytes <>
          :binary.part(acc, offset + 2, byte_size(acc) - offset - 2)
    end
  end

  def draw_datetime(spi, dc, screen_width) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    # "2025-06-07 12:34:56"
    text = NaiveDateTime.to_string(now)
    scale = 1
    sprite = build_sprite(text, 0x0000, 0xFFFF, scale)

    # 右端に配置
    x = screen_width - sprite.w - 2
    # 画面高さが320の場合
    y = 480 - sprite.h - 2

    push_sprite(spi, dc, x, y, sprite)
  end

  def draw_text(spi, dc, x0, y0, text, color, scale \\ 1) do
    Enum.reduce(String.graphemes(text), 0, fn ch, offset ->
      draw_char(spi, dc, x0 + offset, y0, ch, color, scale)
      offset + 6 * scale
    end)
  end

  def draw_char(spi, dc, x0, y0, ch, color, scale) do
    font = Font5x7.get(ch)

    for row <- 0..6 do
      line = Enum.at(font, row)

      for col <- 0..4 do
        if (line &&& 1 <<< (4 - col)) != 0 do
          draw_block(spi, dc, x0 + col * scale, y0 + row * scale, scale, color)
        end
      end
    end
  end

  defp draw_block(spi, dc, x, y, scale, color) do
    fill_rect(spi, dc, x, y, scale, scale, color)
  end
end

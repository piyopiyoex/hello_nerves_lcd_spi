defmodule SampleApp.RGB565 do
  @moduledoc """
  RGB565 バッファを扱う LCD 用ヘルパ群。
  """

  import Bitwise
  alias SampleApp.Font5x7

  @width 320
  @height 480
  @bytes_per_pixel 2
  @expected_size @width * @height * @bytes_per_pixel

  @type rgb565 :: 0..0xFFFF

  @doc """
  `path` で指定した 320×480 の RGB565 生画像を読み込み、バイナリバッファとして返す。

  画像サイズがちょうど #{@expected_size} バイトでない場合は例外を送出する。
  """
  @spec load_rgb565_to_buffer(Path.t()) :: binary()
  def load_rgb565_to_buffer(path) when is_binary(path) do
    case File.read(path) do
      {:ok, data} when byte_size(data) == @expected_size ->
        data

      {:ok, bad} ->
        raise ArgumentError,
              "invalid RGB565 size: #{byte_size(bad)} bytes (expected #{@expected_size})"

      {:error, reason} ->
        raise "failed to read #{path}: #{inspect(reason)}"
    end
  end

  @doc """
  RGB565 のテキストスプライトを生成する。

  * `text`  — 描画する文字列（`Font5x7` がサポートする ASCII）
  * `fg`    — 前景色（RGB565, 例: `0xFFFF`）
  * `bg`    — 背景色（RGB565）
  * `scale` — 拡大率（1, 2, ... の整数）

  返り値は `%{w:, h:, pixels:}` 形式のマップで、`pixels` は RGB565 のバイナリ。
  """
  @spec build_sprite(String.t(), rgb565, rgb565, pos_integer()) :: %{
          w: pos_integer(),
          h: pos_integer(),
          pixels: binary()
        }
  def build_sprite(text, fg, bg, scale) when is_integer(scale) and scale >= 1 do
    char_w = 5
    char_h = 7
    spacing = 1

    width = String.length(text) * (char_w + spacing) * scale
    height = char_h * scale
    px_count = width * height

    fg_bytes = <<fg >>> 8, fg &&& 0xFF>>
    bg_bytes = <<bg >>> 8, bg &&& 0xFF>>

    # 背景色でバッファを初期化
    pixels = :binary.copy(bg_bytes, px_count)

    buffer =
      text
      |> String.to_charlist()
      |> Enum.with_index()
      |> Enum.reduce(pixels, fn {char, ci}, acc_buffer ->
        case Font5x7.get(char) do
          nil ->
            # 未定義グリフはスキップ（背景のまま）
            acc_buffer

          bitmap_rows ->
            # 5x7 ビットマップを `scale` 倍で描画
            Enum.with_index(bitmap_rows)
            |> Enum.reduce(acc_buffer, fn {row_bits, dy}, buf1 ->
              Enum.reduce(0..(char_w - 1), buf1, fn dx, buf2 ->
                if (row_bits &&& 1 <<< (char_w - 1 - dx)) != 0 do
                  x0 = (ci * (char_w + spacing) + dx) * scale
                  y0 = dy * scale
                  draw_scaled_pixel(buf2, width, x0, y0, fg_bytes, scale)
                else
                  buf2
                end
              end)
            end)
        end
      end)

    %{w: width, h: height, pixels: buffer}
  end

  # RGB565 の平面バッファ上で、(x, y) を左上とする `scale`×`scale` の塗りつぶしブロックを描画
  defp draw_scaled_pixel(buffer, image_width, x, y, color_bytes, scale) do
    # バイナリの一部を差し替えることでインプレース更新に近い形で反映
    for dy <- 0..(scale - 1),
        dx <- 0..(scale - 1),
        reduce: buffer do
      acc ->
        col = x + dx
        row = y + dy
        offset = (row * image_width + col) * @bytes_per_pixel

        :binary.part(acc, 0, offset) <>
          color_bytes <>
          :binary.part(acc, offset + @bytes_per_pixel, byte_size(acc) - offset - @bytes_per_pixel)
    end
  end
end

defmodule SampleApp.Framebuffer do
  import Bitwise
  alias SampleApp.Font5x7

  @width 320
  @height 480

  def new do
    # RGB565で青 (0, 0, 255) → 00000 000000 11111 = 0x001F
    rgb565 = 0x0000
    pixel = <<rgb565 >>> 8 &&& 0xFF, rgb565 &&& 0xFF>>

    # 幅×高さ分のピクセルで埋めたバイナリを作成
    :binary.copy(pixel, @width * @height)
  end

  def put_pixel(buffer, x, y, r, g, b) do
    if x < 0 or x >= @width or y < 0 or y >= @height do
      buffer
    else
      index = (y * @width + x) * 2
      <<before::binary-size(index), _::binary-size(2), rest::binary>> = buffer

      rgb565 = (r &&& 0xF8) <<< 8 ||| (g &&& 0xFC) <<< 3 ||| b >>> 3
      new_pixel = <<rgb565 >>> 8 &&& 0xFF, rgb565 &&& 0xFF>>

      <<before::binary, new_pixel::binary, rest::binary>>
    end
  end

  def draw_filled_rect(buffer, x0, y0, width, height, r, g, b) do
    pixel_bin = to_rgb565_bin(r, g, b)
    line_bin = :binary.copy(pixel_bin, width)

    Enum.reduce(0..(height - 1), buffer, fn dy, acc ->
      index = ((y0 + dy) * @width + x0) * 2
      before = binary_part(acc, 0, index)
      rest = binary_part(acc, index + width * 2, byte_size(acc) - index - width * 2)
      <<before::binary, line_bin::binary, rest::binary>>
    end)
  end

  defp to_rgb565_bin(r, g, b) do
    rgb565 = (r &&& 0xF8) <<< 8 ||| (g &&& 0xFC) <<< 3 ||| b >>> 3
    <<rgb565 >>> 8 &&& 0xFF, rgb565 &&& 0xFF>>
  end

  def draw_char(buffer, x, y, char, r, g, b) do
    case Font5x7.get(char) do
      nil ->
        IO.puts("文字 '#{<<char>>}' はフォントに未定義です。")
        buffer

      bitmap ->
        Enum.with_index(bitmap)
        |> Enum.reduce(buffer, fn {row, dy}, acc_buffer ->
          Enum.reduce(0..4, acc_buffer, fn dx, inner_buffer ->
            if (row &&& 1 <<< (4 - dx)) != 0 do
              put_pixel(inner_buffer, x + dx, y + dy, r, g, b)
            else
              inner_buffer
            end
          end)
        end)
    end
  end

  def draw_sprite(buffer, x, y, %{w: w, h: h, pixels: pixels}) do
    Enum.reduce(0..(h - 1), buffer, fn dy, acc_buf ->
      row_start = dy * w * 2
      row_bin = binary_part(pixels, row_start, w * 2)
      index = ((y + dy) * @width + x) * 2

      before = binary_part(acc_buf, 0, index)
      rest = binary_part(acc_buf, index + w * 2, byte_size(acc_buf) - index - w * 2)

      before <> row_bin <> rest
    end)
  end

  def draw_sprite_with_background(buffer, x, y, sprite, bg_r, bg_g, bg_b) do
    %{w: w, h: h} = sprite

    buffer =
      draw_filled_rect(buffer, x, y, w, h, bg_r, bg_g, bg_b)

    draw_sprite(buffer, x, y, sprite)
  end
end

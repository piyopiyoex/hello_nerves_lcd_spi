defmodule SampleApp.TextDraw do
  import Bitwise
  alias SampleApp.Font5x7
  alias SampleApp.Framebuffer

  # 文字1文字を描画（拡大対応）
  def draw_char(buffer, x, y, char, r, g, b, scale \\ 1) do
    case Font5x7.get(char) do
      nil ->
        IO.puts("文字 '#{<<char>>}' はフォントに未定義です。")
        buffer

      bitmap ->
        Enum.with_index(bitmap)
        |> Enum.reduce(buffer, fn {row, dy}, acc_buffer ->
          Enum.reduce(0..4, acc_buffer, fn dx, inner_buffer ->
            if (row &&& 1 <<< (4 - dx)) != 0 do
              draw_scaled_pixel(inner_buffer, x + dx * scale, y + dy * scale, r, g, b, scale)
            else
              inner_buffer
            end
          end)
        end)
    end
  end

  # 拡大したピクセルを描画
  defp draw_scaled_pixel(buffer, x, y, r, g, b, scale) do
    Enum.reduce(0..(scale - 1), buffer, fn dy, acc1 ->
      Enum.reduce(0..(scale - 1), acc1, fn dx, acc2 ->
        Framebuffer.put_pixel(acc2, x + dx, y + dy, r, g, b)
      end)
    end)
  end

  # 文字列を描画（拡大対応）
  def draw_text(buffer, x, y, string, r, g, b, scale \\ 1) when is_binary(string) do
    string
    |> String.to_charlist()
    |> Enum.with_index()
    |> Enum.reduce(buffer, fn {char, index}, acc_buffer ->
      dx = index * (5 + 1) * scale
      draw_char(acc_buffer, x + dx, y, char, r, g, b, scale)
    end)
  end
end

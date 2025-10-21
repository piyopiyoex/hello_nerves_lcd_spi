defmodule SampleApp.Color do
  import Bitwise

  def rgb565(r, g, b) when r in 0..255 and g in 0..255 and b in 0..255 do
    (r &&& 0xF8) <<< 8 ||| (g &&& 0xFC) <<< 3 ||| b >>> 3
  end

  def rgb565_binary(r, g, b), do: <<rgb565(r, g, b)::16-big>>

  def rgb565_hex(r, g, b), do: to_hex(rgb565(r, g, b), 4, "0x")

  def rgb565_bits(r, g, b), do: to_bits(rgb565(r, g, b), 16)

  defp to_hex(int_value, width, prefix) do
    int_value
    |> Integer.to_string(16)
    |> String.upcase()
    |> String.pad_leading(width, "0")
    |> (&(prefix <> &1)).()
  end

  defp to_bits(int_value, width) do
    int_value
    |> Integer.to_string(2)
    |> String.pad_leading(width, "0")
  end
end

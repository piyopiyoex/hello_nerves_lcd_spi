defmodule SampleApp do
  @moduledoc """
  Documentation for `SampleApp`.
  """

  @default_lcd_type "a"

  def app_name, do: Application.get_application(__MODULE__)

  def lcd_type do
    Application.get_env(app_name(), :lcd_type, @default_lcd_type)
    |> to_string()
    |> String.downcase()
  end

  def build_target do
    Nerves.Runtime.mix_target()
  end

  def app_version do
    Nerves.Runtime.KV.get_active("nerves_fw_version")
  end

  def display_name do
    "lcd_#{lcd_type()} v#{app_version()} #{build_target()}"
  end

  def piyopiyoex_rgb565_path do
    Application.app_dir(app_name(), "priv/piyopiyoex_320x480.rgb565")
  end

  def ui_mod do
    case lcd_type() do
      "a" -> SampleApp.LcdA.UI
      "b" -> SampleApp.LcdB.UI
      "c" -> SampleApp.LcdC.UI
      "f" -> SampleApp.LcdF.UI
      "g" -> SampleApp.LcdG.UI
      _ -> SampleApp.LcdA.UI
    end
  end

  def touch_mod do
    case lcd_type() do
      "a" -> SampleApp.LcdA.XPT2046
      "b" -> SampleApp.LcdB.XPT2046
      "c" -> SampleApp.LcdC.XPT2046
      "f" -> SampleApp.LcdF.GT911
      "g" -> SampleApp.LcdG.XPT2046
      _ -> SampleApp.LcdA.XPT2046
    end
  end
end

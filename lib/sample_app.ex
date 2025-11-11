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

  def ui_child_spec do
    case lcd_type() do
      "b" -> {SampleApp.UI.ILI9486, is_high_speed: false, rotation: 180}
      "c" -> {SampleApp.UI.ILI9486, is_high_speed: true, rotation: 0}
      "f" -> {SampleApp.LcdF.UI, []}
      "g" -> {SampleApp.LcdG.UI, []}
      _ -> {SampleApp.UI.ILI9486, is_high_speed: false, rotation: 0}
    end
  end

  def touch_child_spec do
    {ui, _opts} = ui_child_spec()

    case lcd_type() do
      "f" -> {SampleApp.Touch.GT911, ui: ui}
      _ -> {SampleApp.Touch.XPT2046, ui: ui}
    end
  end
end

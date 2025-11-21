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
end

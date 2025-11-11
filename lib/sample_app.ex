defmodule SampleApp do
  @moduledoc """
  Documentation for `SampleApp`.
  """

  @default_lcd_type "A"

  def app_name, do: Application.get_application(__MODULE__)

  def lcd_type do
    Application.get_env(app_name(), :lcd_type, @default_lcd_type)
  end

  def build_target do
    Nerves.Runtime.mix_target()
  end

  def app_version do
    Nerves.Runtime.KV.get_active("nerves_fw_version")
  end

  def display_name do
    "LCD (#{lcd_type()}) #{build_target()} v#{app_version()}"
  end

  def piyopiyoex_rgb565_path do
    Application.app_dir(app_name(), "priv/piyopiyoex_320x480.rgb565")
  end
end
